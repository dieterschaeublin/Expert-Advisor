"""Strategie-Recherche auf MT4-H1-Exporten (History Center CSV).

Bar-basierter Backtest mit konservativen Annahmen:
  * Einstieg zum Eroeffnungskurs der Kerze NACH dem Signal
  * Werden Stop und Ziel in derselben Kerze beruehrt, zaehlt der Stop
  * Kursluecken ueber den Stop werden zum Eroeffnungskurs abgerechnet
  * Kosten (Spread + Kommission) pro Trade in Pips abgezogen
  * Swap wird nicht beruecksichtigt
Ergebnisse in R (Vielfache des Anfangsrisikos), Portfolio mit festem Risiko pro Trade.

Aufruf:  python3 research/backtest.py <ordner-mit-csv>
"""
import sys
import glob
import os
import numpy as np
import pandas as pd
from numba import njit

IS_START, IS_END, OOS_END = "2016-01-01", "2023-01-01", "2027-01-01"

# All-in-Kosten (Spread + Kommission) in Pips je Trade
COST_ECN = {"EURUSD": 0.9, "USDJPY": 1.0, "GBPUSD": 1.2, "EURGBP": 1.3, "USDCHF": 1.4}
RETAIL_EXTRA = 0.8  # Aufschlag Standard-Konto


def load(folder):
    data = {}
    for f in sorted(glob.glob(os.path.join(folder, "*.csv"))):
        sym = os.path.basename(f).split("-")[-1].replace("60.csv", "")
        df = pd.read_csv(f, header=None, names=["d", "t", "o", "h", "l", "c", "v"])
        df.index = pd.to_datetime(df.d + " " + df.t, format="%Y.%m.%d %H:%M")
        df = df.loc[IS_START:, ["o", "h", "l", "c"]].astype(float)
        df = df[~df.index.duplicated()]
        data[sym] = df
    return data


def ema(x, n):
    return pd.Series(x).ewm(span=n, adjust=False).mean().values


def atr(df, n=14):
    pc = df.c.shift(1)
    tr = np.maximum(df.h - df.l, np.maximum((df.h - pc).abs(), (df.l - pc).abs()))
    return tr.ewm(alpha=1 / n, adjust=False).mean().values


def daily_atr(df, n=14):
    d = df.resample("1D").agg({"o": "first", "h": "max", "l": "min", "c": "last"}).dropna()
    a = pd.Series(atr(d, n), index=d.index).shift(1)  # Wert des Vortags
    return a.reindex(df.index, method="ffill").values


def rsi(c, n):
    s = pd.Series(c)
    d = s.diff()
    up = d.clip(lower=0).ewm(alpha=1 / n, adjust=False).mean()
    dn = (-d.clip(upper=0)).ewm(alpha=1 / n, adjust=False).mean()
    return (100 - 100 / (1 + up / dn)).values


@njit(cache=True)
def simulate(o, h, l, c, hour, long_sig, short_sig, exit_long, exit_short, stopdist,
             tp_r, trail, trail_atr, max_bars, exit_hour, cost):
    n = len(c)
    out = np.zeros((n, 5))  # entry_idx, exit_idx, dir, R, sd
    k = 0
    pos = 0
    entry = 0.0
    stop = 0.0
    tp = 0.0
    sd = 0.0
    ei = 0
    best = 0.0
    for i in range(1, n - 1):
        if pos != 0:
            px = -1.0
            if pos == 1:
                if o[i] <= stop:
                    px = o[i]
                elif l[i] <= stop:
                    px = stop
                elif tp_r > 0 and h[i] >= tp:
                    px = tp if o[i] < tp else o[i]
            else:
                if o[i] >= stop:
                    px = o[i]
                elif h[i] >= stop:
                    px = stop
                elif tp_r > 0 and l[i] <= tp:
                    px = tp if o[i] > tp else o[i]
            if px < 0:
                done = False
                if max_bars > 0 and i - ei + 1 >= max_bars:
                    done = True
                if exit_hour >= 0 and hour[i] == exit_hour:
                    done = True
                if (pos == 1 and exit_long[i]) or (pos == -1 and exit_short[i]):
                    done = True
                if done:
                    px = c[i]
                elif trail > 0:
                    if pos == 1:
                        best = max(best, c[i])
                        stop = max(stop, best - trail * trail_atr[i])
                    else:
                        best = min(best, c[i])
                        stop = min(stop, best + trail * trail_atr[i])
            if px >= 0:
                out[k, 0] = ei
                out[k, 1] = i
                out[k, 2] = pos
                out[k, 3] = ((px - entry) * pos - cost) / sd
                out[k, 4] = sd
                k += 1
                pos = 0
        if pos == 0 and stopdist[i] > 0 and (long_sig[i] or short_sig[i]):
            pos = 1 if long_sig[i] else -1
            ei = i + 1
            entry = o[i + 1]
            sd = stopdist[i]
            stop = entry - pos * sd
            tp = entry + pos * sd * tp_r
            best = entry
    return out[:k]


# ---------------------------------------------------------------- Strategien
def prep(df):
    f = {}
    f["atr"] = atr(df)
    f["atrd"] = daily_atr(df)
    f["hour"] = df.index.hour.values.astype(np.int64)
    f["date"] = df.index.normalize().values
    f["bpd"] = max(1, int(round(pd.Timedelta("1D") / df.index.to_series().diff().mode()[0])))
    return f


def no(n):
    return np.zeros(n, dtype=np.bool_)


def strat_donchian(df, f, N, sl, tr, flt):
    c, h, l = df.c.values, df.h, df.l
    hh = h.rolling(N).max().shift(1).values
    ll = l.rolling(N).min().shift(1).values
    long_s = c > hh
    short_s = c < ll
    if flt:
        e = ema(c, flt)
        long_s &= c > e
        short_s &= c < e
    sd = sl * f["atrd"]
    return dict(long_sig=long_s, short_sig=short_s, exit_long=no(len(c)), exit_short=no(len(c)),
                stopdist=np.nan_to_num(sd), tp_r=0.0, trail=tr, trail_atr=np.nan_to_num(f["atrd"]),
                max_bars=0, exit_hour=-1)


def strat_emacross(df, f, fast, slow, sl):
    c = df.c.values
    ef, es = ema(c, fast), ema(c, slow)
    up = (ef > es) & (np.roll(ef, 1) <= np.roll(es, 1))
    dn = (ef < es) & (np.roll(ef, 1) >= np.roll(es, 1))
    return dict(long_sig=up, short_sig=dn, exit_long=ef < es, exit_short=ef > es,
                stopdist=np.nan_to_num(sl * f["atrd"]), tp_r=0.0, trail=0.0,
                trail_atr=np.zeros(len(c)), max_bars=0, exit_hour=-1)


def strat_tsmom(df, f, lookback_days, sl):
    c = df.c.values
    L = lookback_days * f["bpd"]
    mom = c - np.roll(c, L)
    mom[:L] = 0
    at0 = f["hour"] == 0  # einmal taeglich pruefen
    long_s = (mom > 0) & at0
    short_s = (mom < 0) & at0
    return dict(long_sig=long_s, short_sig=short_s, exit_long=(mom < 0) & at0, exit_short=(mom > 0) & at0,
                stopdist=np.nan_to_num(sl * f["atrd"]), tp_r=0.0, trail=0.0,
                trail_atr=np.zeros(len(c)), max_bars=0, exit_hour=-1)


def strat_orb(df, f, start_h, end_h, tp_r, max_range_atr):
    """Ausbruch aus der Spanne start_h..end_h-1 (Server-Zeit), Einstieg bis 4 h danach, Exit 22 Uhr."""
    hour = f["hour"]
    g = pd.DataFrame({"h": df.h.values, "l": df.l.values, "date": f["date"], "hour": hour})
    rng = g[(g.hour >= start_h) & (g.hour < end_h)].groupby("date").agg(rh=("h", "max"), rl=("l", "min"))
    g = g.join(rng, on="date")
    c = df.c.values
    win = (hour >= end_h) & (hour < end_h + 4)
    width = (g.rh - g.rl).values
    ok = win & (width <= max_range_atr * f["atrd"]) & (width > 0)
    long_s = ok & (c > g.rh.values)
    short_s = ok & (c < g.rl.values)
    # nur der erste Ausbruch pro Tag
    first = pd.Series(long_s | short_s).groupby(f["date"]).cumsum().values == 1
    long_s &= first
    short_s &= first
    return dict(long_sig=long_s, short_sig=short_s, exit_long=no(len(c)), exit_short=no(len(c)),
                stopdist=np.nan_to_num(width), tp_r=tp_r, trail=0.0, trail_atr=np.zeros(len(c)),
                max_bars=0, exit_hour=22)


def strat_rsi2(df, f, th, trend, sl, max_bars):
    c = df.c.values
    r = rsi(c, 2)
    e = ema(c, trend)
    e5 = ema(c, 5)
    long_s = (r < th) & (c > e)
    short_s = (r > 100 - th) & (c < e)
    return dict(long_sig=long_s, short_sig=short_s, exit_long=c > e5, exit_short=c < e5,
                stopdist=np.nan_to_num(sl * f["atr"]), tp_r=0.0, trail=0.0, trail_atr=np.zeros(len(c)),
                max_bars=max_bars, exit_hour=-1)


FAMILIES = {
    "Donchian-Trend": (strat_donchian, [dict(N=N, sl=sl, tr=tr, flt=flt)
                                        for N in (24, 72, 120, 240) for sl in (1.5, 2.5)
                                        for tr in (2.0, 3.0) for flt in (0, 200)]),
    "EMA-Kreuzung": (strat_emacross, [dict(fast=a, slow=b, sl=sl)
                                      for a, b in ((20, 100), (50, 200), (100, 400), (24, 120))
                                      for sl in (2.0, 3.0)]),
    "Zeitreihen-Momentum": (strat_tsmom, [dict(lookback_days=d, sl=sl)
                                          for d in (20, 60, 120) for sl in (2.0, 3.0)]),
    "London-Breakout": (strat_orb, [dict(start_h=s, end_h=e, tp_r=t, max_range_atr=m)
                                    for s, e in ((2, 9), (0, 9), (3, 10)) for t in (1.0, 1.5, 2.0)
                                    for m in (0.6, 1.0)]),
    "RSI2-Rueckkehr": (strat_rsi2, [dict(th=th, trend=tr, sl=sl, max_bars=mb)
                                    for th in (5, 10) for tr in (200, 600) for sl in (2.0, 3.0)
                                    for mb in (12, 36)]),
}


def resample(data, rule):
    agg = {"o": "first", "h": "max", "l": "min", "c": "last"}
    return {k: v.resample(rule).agg(agg).dropna() for k, v in data.items()}


def run(data, family, params, extra_cost=0.0, cache={}):
    fn, _ = FAMILIES[family]
    trades = []
    for sym, df in data.items():
        key = (sym, len(df))
        if key not in cache:
            cache[key] = prep(df)
        f = cache[key]
        pip = 0.01 if "JPY" in sym else 0.0001
        s = fn(df, f, **params)
        t = simulate(df.o.values, df.h.values, df.l.values, df.c.values, f["hour"],
                     s["long_sig"].astype(np.bool_), s["short_sig"].astype(np.bool_),
                     np.asarray(s["exit_long"], dtype=np.bool_), np.asarray(s["exit_short"], dtype=np.bool_),
                     s["stopdist"], s["tp_r"], s["trail"], s["trail_atr"], s["max_bars"], s["exit_hour"],
                     (COST_ECN[sym] + extra_cost) * pip)
        if len(t):
            tr = pd.DataFrame(t, columns=["ei", "xi", "dir", "R", "sd"])
            tr["sym"] = sym
            tr["entry_time"] = df.index[tr.ei.astype(int)]
            tr["exit_time"] = df.index[tr.xi.astype(int)]
            trades.append(tr)
    return pd.concat(trades) if trades else pd.DataFrame()


def stats(tr, risk=0.005):
    if len(tr) == 0:
        return dict(trades=0)
    tr = tr.sort_values("exit_time")
    R = tr.R.values
    eq = np.cumprod(1 + risk * R)
    dd = 1 - eq / np.maximum.accumulate(eq)
    years = max((tr.exit_time.max() - tr.entry_time.min()).days / 365.25, 0.1)
    gp, gl = R[R > 0].sum(), -R[R < 0].sum()
    return dict(trades=len(R), per_year=round(len(R) / years), win=round((R > 0).mean() * 100, 1),
                avgR=round(R.mean(), 3), PF=round(gp / gl, 2) if gl > 0 else np.inf,
                totR=round(R.sum(), 1), CAGR=round((eq[-1] ** (1 / years) - 1) * 100, 1),
                maxDD=round(dd.max() * 100, 1))


def split(tr):
    return tr[tr.entry_time < IS_END], tr[tr.entry_time >= IS_END]


if __name__ == "__main__":
    data = load(sys.argv[1])
    print({k: (str(v.index[0].date()), str(v.index[-1].date()), len(v)) for k, v in data.items()})
    rows = []
    for fam, (_, grid) in FAMILIES.items():
        for p in grid:
            tr = run(data, fam, p)
            ins, oos = split(tr)
            si, so = stats(ins), stats(oos)
            rows.append(dict(family=fam, params=p, **{f"IS_{k}": v for k, v in si.items()},
                             **{f"OOS_{k}": v for k, v in so.items()}))
    res = pd.DataFrame(rows)
    pd.set_option("display.width", 250, "display.max_columns", 30, "display.max_colwidth", 80)
    res.to_pickle("/tmp/claude-0/-home-user-Expert-Advisor/afe3bf41-0f3e-59da-963e-e519b96dc19c/scratchpad/res.pkl")
    print("\n=== Familien: Anteil Varianten mit positivem Ergebnis (IS / OOS) ===")
    for fam, g in res.groupby("family"):
        print(f"{fam:22s} n={len(g):3d}  IS>0: {(g.IS_totR > 0).mean():.0%}  OOS>0: {(g.OOS_totR > 0).mean():.0%}  "
              f"median avgR IS {g.IS_avgR.median():+.3f}  OOS {g.OOS_avgR.median():+.3f}")
    print("\n=== Beste Variante je Familie (nach IS avgR, min. 100 IS-Trades) ===")
    best = res[res.IS_trades >= 100].sort_values("IS_avgR", ascending=False).groupby("family").head(1)
    print(best[["family", "params", "IS_trades", "IS_per_year", "IS_win", "IS_avgR", "IS_PF", "IS_CAGR", "IS_maxDD",
                "OOS_trades", "OOS_win", "OOS_avgR", "OOS_PF", "OOS_CAGR", "OOS_maxDD"]].to_string(index=False))
