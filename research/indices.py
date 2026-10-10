"""Aktienindex-CFDs: RSI(2)-Ruecksetzer + Monatswechsel (Turn of the Month), nur Long.

Hintergrund: Devisen haben keine eingebaute Drift und kaum kurzfristige Rueckkehr zum Mittel.
Aktienindizes haben beides (langfristiger Aufwaertstrend, kurzfristige Uebertreibungen nach
unten werden meist aufgeholt) und zusaetzlich den Monatswechsel-Effekt (Gehaltszahlungen,
Fonds-Zufluesse zum Monatsanfang). Getestet werden genau die Regeln des EA Index_PullbackTOM.

Daten: MT4-Export (History Center, D1 oder H1) z. B. US500, NAS100, US30, GER40, UK100, XAUUSD,
oder Tagesdaten als CSV mit Kopfzeile (Date,Open,High,Low,Close ...), z. B. von Yahoo Finance
(^GSPC, ^NDX, ^GDAXI) oder stooq.com. Das Symbol wird aus dem Dateinamen gelesen,
z. B. "US500-1440.csv", "GER40.csv"; Yahoo-Namen wie "^GSPC.csv" werden zugeordnet.

Annahmen:
  * Signal auf Tagesschluss, Einstieg/Ausstieg zur Eroeffnung der naechsten Tageskerze
  * Katastrophen-Stop 3 x ATR(14) (wie im EA), bei Kursluecke zum Eroeffnungskurs
  * Kosten: Spread in Indexpunkten je Trade (COST_PTS) + Finanzierung je Nacht
    (Leitzins + 2,5 % p.a. Broker-Aufschlag ~ 6 % p.a. -> 0,016 % je Kalendertag)
Ergebnis in % des Index je Trade und als Jahresrendite bei 100 % investiertem Kapital.

Aufruf:  python3 research/indices.py <ordner-mit-csv>
"""
import sys
import glob
import os
import numpy as np
import pandas as pd

IS_START, IS_END, OOS_END = "2012-01-01", "2020-01-01", "2027-01-01"
COST_PTS = {"US500": 0.6, "SPX500": 0.6, "NAS100": 1.8, "USTEC": 1.8, "US30": 3.0,
            "GER40": 1.5, "DE40": 1.5, "UK100": 1.2, "JP225": 8.0, "EU50": 1.5, "XAUUSD": 0.3}
ALIASES = {"GSPC": "US500", "SPX": "US500", "NDX": "NAS100", "DJI": "US30", "GDAXI": "GER40",
           "DAX": "GER40", "FTSE": "UK100", "N225": "JP225", "STOXX50E": "EU50", "GOLD": "XAUUSD"}
FIN_PA = 0.06  # Finanzierung Long p.a.


def load(folder):
    data = {}
    for f in sorted(glob.glob(os.path.join(folder, "*.csv"))):
        name = os.path.basename(f).upper()
        base = name.split("-")[0].split(".")[0].lstrip("^").replace("_D", "")
        sym = next((s for s in COST_PTS if s in name), ALIASES.get(base, base))
        with open(f) as fh:
            first = fh.readline()
        if first[:1].isalpha():  # Kopfzeile -> Yahoo/stooq-Format
            df = pd.read_csv(f)
            df.columns = [c.strip().lower() for c in df.columns]
            df.index = pd.to_datetime(df["date"].astype(str).str[:10])
            df = df.rename(columns={"open": "o", "high": "h", "low": "l", "close": "c"})
            df = df[["o", "h", "l", "c"]].apply(pd.to_numeric, errors="coerce").dropna()
        else:
            df = pd.read_csv(f, header=None, names=["d", "t", "o", "h", "l", "c", "v"])
            df.index = pd.to_datetime(df.d + " " + df.t, format="%Y.%m.%d %H:%M")
            df = df[["o", "h", "l", "c"]].astype(float)
        df = df[~df.index.duplicated()].sort_index()
        d = df.resample("1D").agg({"o": "first", "h": "max", "l": "min", "c": "last"}).dropna()
        d = d[d.index.dayofweek < 5]  # Sonntagskerzen einiger Broker verwerfen
        data[sym] = d
    return data


def rsi(c, n):
    d = c.diff()
    up = d.clip(lower=0).ewm(alpha=1 / n, adjust=False).mean()
    dn = (-d.clip(upper=0)).ewm(alpha=1 / n, adjust=False).mean()
    return 100 - 100 / (1 + up / dn)


def atr(d, n=14):
    pc = d.c.shift(1)
    tr = np.maximum(d.h - d.l, np.maximum((d.h - pc).abs(), (d.l - pc).abs()))
    return tr.ewm(alpha=1 / n, adjust=False).mean()


def run(d, entry_sig, exit_sig, cost_pts, stop_atr=3.0, max_bars=10):
    """entry_sig[i]/exit_sig[i] gelten am Schluss von Kerze i -> Ausfuehrung zur Eroeffnung i+1."""
    o, l, idx = d.o.values, d.l.values, d.index
    a = atr(d).values
    trades = []
    i, n = 0, len(d)
    while i < n - 1:
        if not entry_sig[i]:
            i += 1
            continue
        e = i + 1
        entry, stop = o[e], o[e] - stop_atr * a[i]
        x, px = None, None
        for j in range(e, n):
            if o[j] <= stop and j > e:
                x, px = j, o[j]
                break
            if l[j] <= stop:
                x, px = j, stop
                break
            if j + 1 < n and (exit_sig[j] or j - e + 1 >= max_bars):
                x, px = j + 1, o[j + 1]
                break
        if x is None:
            break
        nights = (idx[x] - idx[e]).days
        ret = (px - entry - cost_pts) / entry - FIN_PA / 365 * nights
        trades.append((idx[e], ret, x - e))
        i = x
    return pd.DataFrame(trades, columns=["t", "ret", "bars"]).set_index("t")


def signals(d, rsi_low, trend=200):
    c = d.c
    sma_t = c.rolling(trend).mean()
    sma5 = c.rolling(5).mean()
    pb_in = ((rsi(c, 2) < rsi_low) & (c > sma_t)).values
    pb_out = (c > sma5).values

    # Monatswechsel: Kauf zur Eroeffnung des letzten Handelstags, Verkauf zur Eroeffnung des 4. Handelstags
    m = d.index.to_period("M")
    day_no = d.groupby(m).cumcount().values + 1          # Handelstag im Monat (1, 2, ...)
    nxt = d.index + pd.offsets.BDay(1)
    last_day = (nxt.month != d.index.month)               # Kalender-Logik wie im EA (ohne Feiertage)
    tom_in = np.roll(last_day, -1)                         # Signal am Vortag -> Einstieg Eroeffnung letzter Tag
    tom_in[-1] = False
    tom_out = (day_no == 3)                                # Schluss Tag 3 -> Ausstieg Eroeffnung Tag 4
    return pb_in, pb_out, tom_in, tom_out


def stats(t, years):
    if len(t) == 0:
        return "keine Trades"
    r = t.ret
    tstat = r.mean() / r.std(ddof=1) * np.sqrt(len(r)) if len(r) > 1 else 0
    return (f"n={len(r):4d}  Treffer {100 * (r > 0).mean():3.0f}%  "
            f"Mittel {100 * r.mean():+.3f}%  t={tstat:+.1f}  "
            f"Jahr {100 * r.sum() / years:+5.1f}%  im Markt {t.bars.sum() / (years * 252) * 100:3.0f}%")


def main(folder):
    data = load(folder)
    if not data:
        sys.exit("Keine CSV-Dateien gefunden.")
    periods = [(IS_START, IS_END), (IS_END, OOS_END)]
    for sym, d in data.items():
        cost = COST_PTS.get(sym, 0.0002 * d.c.iloc[-1])
        print(f"\n=== {sym}  ({d.index[0].date()} - {d.index[-1].date()}, Kosten {cost} Pkt) ===")
        for a, b in periods:
            x = d.loc[a:b]
            if len(x) > 50:
                yrs = len(x) / 252
                bh = (x.c.iloc[-1] / x.c.iloc[0]) ** (1 / yrs) - 1
                print(f"  Buy & Hold {a[:4]}-{b[:4]}: {100 * bh:+.1f}%/Jahr")
        variants = [("RSI2<5 ", 5, "pb"), ("RSI2<10", 10, "pb"), ("RSI2<25", 25, "pb"), ("Monatswechsel", 10, "tom")]
        for name, lo, kind in variants:
            pb_in, pb_out, tom_in, tom_out = signals(d, lo)
            t = run(d, pb_in, pb_out, cost) if kind == "pb" else run(d, tom_in, tom_out, cost, max_bars=6)
            for a, b in periods:
                x = t.loc[a:b]
                yrs = max(len(d.loc[a:b]) / 252, 0.01)
                print(f"  {name:14s} {a[:4]}-{b[:4]}: {stats(x, yrs)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
