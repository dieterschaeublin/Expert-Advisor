"""Weekend-Gap-Fill nach Richtung, Einstiegsstunde und Zeitraum (vorab festgelegte Varianten).
Aufruf: python3 research/gap_by_direction.py <ordner-mit-csv>
"""
import sys
import numpy as np
import pandas as pd
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import backtest as bt
import weekend_gap as wg

data = bt.load(sys.argv[1])
rows = []
for sym, df in data.items():
    g = wg.weekly_gaps(df)
    g["gap_atr"] = (g.open - g.fri_close).abs() / g.atrd
    cost = (bt.cost_pips(sym) + wg.EXTRA_OPEN_COST) * bt.pip_size(sym)
    for _, x in g[g.gap_atr > 0.25].iterrows():
        for eb in (0, 1):
            for stop in (1.5, 2.0):
                r = wg.trade(df, x, eb, 0.5, stop, 24, cost)
                if r is not None:
                    rows.append(dict(t=x.t, sym=sym, up=x.open > x.fri_close, big=x.gap_atr > 0.5,
                                     entry=eb + 1, stop=stop, R=r))
r = pd.DataFrame(rows)
print(f"{r.sym.nunique()} Paare. Luecken > 0,25 ATR: nach oben {r[(r.entry==1)&(r.stop==2)].up.sum()}, "
      f"nach unten {(~r[(r.entry==1)&(r.stop==2)].up).sum()}")


def line(lab, v):
    if len(v) < 3:
        return f"{lab}: zu wenige"
    t = v.mean() / (v.std(ddof=1) / np.sqrt(len(v)))
    return f"{lab}: n={len(v):3d} Treffer {np.mean(v > 0):.0%} {v.mean():+.3f}R t={t:+.2f}"


for entry in (1, 2):
    for stop in (2.0, 1.5):
        for up, lab in ((True, "VERKAUF (Luecke hoch)"), (False, "KAUF (Luecke runter)")):
            s = r[(r.entry == entry) & (r.stop == stop) & (r.up == up)]
            print(f"Einstieg {entry}. Std, Stop {stop}x, {lab:22s} | "
                  f"{line('2016-22', s[s.t < bt.IS_END].R.values)} | {line('2023-26', s[s.t >= bt.IS_END].R.values)}")
    print()
s = r[(r.entry == 1) & (r.stop == 2.0) & r.up]
print("Verkauf sofort, Stop 2x, je Paar:", ", ".join(f"{k}:{g.R.mean():+.2f}R/{len(g)}" for k, g in s.groupby("sym")))
s2 = s[s.big]
print(line("Verkauf sofort, nur Luecken > 0,5 ATR, gesamt", s2.R.values))
