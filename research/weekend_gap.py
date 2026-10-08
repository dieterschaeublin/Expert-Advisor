"""Weekend-Gap-Fill: Bei grosser Kursluecke zum Wochenbeginn Richtung Freitags-Schlusskurs handeln.

Einstieg wahlweise zur Eroeffnung der 1., 2. oder 3. Stunde der neuen Woche (1. Stunde = unrealistisch,
da Spreads zur Wochen-Eroeffnung stark ausgeweitet sind; nur als Obergrenze gezeigt).
Ziel: Freitags-Schlusskurs (oder Anteil davon). Stop: Vielfaches der Lueckengroesse. Zeit-Exit.
Stop wird zuerst geprueft, wenn Stop und Ziel in derselben Kerze liegen.
Aufruf: python3 research/weekend_gap.py <ordner-mit-csv>
"""
import sys
import numpy as np
import pandas as pd
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import backtest as bt

EXTRA_OPEN_COST = 0.5   # Pips Zusatzkosten fuer erhoehten Spread kurz nach Wochen-Eroeffnung


def weekly_gaps(df):
    idx = df.index
    new_week = np.where(np.diff(idx.values).astype("timedelta64[h]").astype(int) > 24)[0] + 1
    atrd = bt.daily_atr(df)
    rows = []
    for k in new_week:
        rows.append(dict(k=k, fri_close=df.c.iat[k - 1], open=df.o.iat[k], atrd=atrd[k], t=idx[k]))
    return pd.DataFrame(rows)


def trade(df, g, entry_bar, fill, stop_mult, max_bars, cost):
    """Ein Trade je Woche; Ergebnis in R (Risiko = Abstand Einstieg-Stop)."""
    k = g.k + entry_bar
    if k >= len(df):
        return None
    gap = g.open - g.fri_close
    d = -1 if gap > 0 else 1                       # gegen die Luecke handeln
    entry = df.o.iat[k]
    target = entry + d * fill * abs(entry - g.fri_close) if fill < 1 else g.fri_close
    if d * (target - entry) <= 0:                  # Luecke schon geschlossen
        return None
    stop = entry - d * stop_mult * abs(gap)
    risk = abs(entry - stop)
    for i in range(k, min(k + max_bars, len(df))):
        lo, hi = df.l.iat[i], df.h.iat[i]
        if (d == 1 and lo <= stop) or (d == -1 and hi >= stop):
            return (stop - entry) * d / risk - cost / risk
        if (d == 1 and hi >= target) or (d == -1 and lo <= target):
            return (target - entry) * d / risk - cost / risk
    return (df.c.iat[min(k + max_bars, len(df)) - 1] - entry) * d / risk - cost / risk


if __name__ == "__main__":
    data = bt.load(sys.argv[1])
    print("Lueckengroesse zum Wochenbeginn (Pips, Median / 90%-Quantil / Anzahl > 0,25 Tages-ATR):")
    gaps = {}
    for sym, df in data.items():
        pip = bt.pip_size(sym)
        g = weekly_gaps(df)
        g["gap_pips"] = (g.open - g.fri_close).abs() / pip
        g["gap_atr"] = (g.open - g.fri_close).abs() / g.atrd
        gaps[sym] = g
        print(f"  {sym}: {g.gap_pips.median():5.1f} / {g.gap_pips.quantile(.9):5.1f} / {(g.gap_atr > .25).sum()} von {len(g)} Wochen")

    rows = []
    for min_gap in (0.1, 0.25, 0.5):
        for entry_bar in (0, 1, 2):
            for fill in (0.5, 1.0):
                for stop_mult in (1.0, 2.0):
                    for max_bars in (12, 24):
                        R = []
                        for sym, df in data.items():
                            pip = bt.pip_size(sym)
                            cost = (bt.cost_pips(sym) + EXTRA_OPEN_COST) * pip
                            for _, g in gaps[sym][gaps[sym].gap_atr > min_gap].iterrows():
                                r = trade(df, g, entry_bar, fill, stop_mult, max_bars, cost)
                                if r is not None:
                                    R.append((g.t, r))
                        r = pd.DataFrame(R, columns=["t", "R"])
                        ins, oos = r[r.t < bt.IS_END].R, r[r.t >= bt.IS_END].R
                        t = lambda x: x.mean() / (x.std() / np.sqrt(len(x))) if len(x) > 2 else np.nan
                        rows.append(dict(min_gap=min_gap, entry_h=entry_bar + 1, fill=fill, stop=stop_mult, max_h=max_bars,
                                         IS_n=len(ins), IS_win=(ins > 0).mean() * 100, IS_R=ins.mean(), IS_t=t(ins),
                                         OOS_n=len(oos), OOS_win=(oos > 0).mean() * 100, OOS_R=oos.mean(), OOS_t=t(oos)))
    res = pd.DataFrame(rows).round(3)
    pd.set_option("display.width", 200)
    print(f"\n{len(res)} Varianten. Je Einstiegsstunde: Anteil Varianten positiv (IS / OOS) und Median R:")
    for e, g in res.groupby("entry_h"):
        print(f"  Einstieg {e}. Stunde: IS>0 {(g.IS_R > 0).mean():.0%}  OOS>0 {(g.OOS_R > 0).mean():.0%}  "
              f"Median IS {g.IS_R.median():+.3f}R  OOS {g.OOS_R.median():+.3f}R  Trefferquote IS {g.IS_win.median():.0f}%")
    print("\nJe Paar, Standard-Variante (Luecke > 0.25 ATR, Einstieg 2. Stunde, Ziel 50 %, Stop 2x, 24 h):")
    for sym, df in data.items():
        pip = bt.pip_size(sym)
        cost = (bt.cost_pips(sym) + EXTRA_OPEN_COST) * pip
        rr = [trade(df, g, 1, 0.5, 2.0, 24, cost) for _, g in gaps[sym][gaps[sym].gap_atr > 0.25].iterrows()]
        rr = np.array([x for x in rr if x is not None])
        if len(rr):
            print(f"  {sym}: {len(rr):3d} Trades, Treffer {np.mean(rr > 0):.0%}, {rr.mean():+.3f} R/Trade, Kosten {bt.cost_pips(sym)} Pips")
    print("\nBeste 8 Varianten nach IS (Einstieg ab 2. Stunde):")
    print(res[res.entry_h >= 2].sort_values("IS_R", ascending=False).head(8).to_string(index=False))
