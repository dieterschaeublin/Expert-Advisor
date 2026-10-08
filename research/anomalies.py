"""Pruefung dokumentierter Kalender-/Tageszeit-Effekte (Breedon & Ranaldo 2013; Gotobi USDJPY).

Strenger Massstab: Out-of-sample (2023-2026) muss nach Kosten t > 2 erreichen.
Aufruf: python3 research/anomalies.py <ordner-mit-csv>
"""
import sys
import numpy as np
import pandas as pd
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import backtest as bt


def tstat(x):
    x = np.asarray(x, float)
    return x.mean() / (x.std(ddof=1) / np.sqrt(len(x))) if len(x) > 2 else np.nan


def window_trades(df, h_start, h_end, direction, pip, cost_pips, days_mask=None):
    """Taeglich: Einstieg Eroeffnung h_start, Ausstieg Schluss der Kerze h_end-1. Ergebnis in Pips netto."""
    o = df.o[df.index.hour == h_start]
    c = df.c[df.index.hour == h_end - 1]
    o.index, c.index = o.index.normalize(), c.index.normalize()
    j = pd.concat([o, c], axis=1, keys=["o", "c"], sort=True).dropna()
    if days_mask is not None:
        j = j[days_mask(j.index)]
    return (direction * (j.c - j.o) / pip - cost_pips).rename("pips")


def scan_hours(data):
    print("=== 1) Tageszeit-Effekt: bestes Zeitfenster je Paar (gewaehlt 2016-2022, geprueft 2023-2026) ===")
    print(f"{'Paar':7s} {'Fenster':>9s} {'Richt.':>6s} | {'IS Pips/Tag':>11s} {'t':>5s} | {'OOS Pips/Tag':>12s} {'t':>5s} {'Tage':>5s}")
    found = []
    for sym, df in data.items():
        pip = 0.01 if "JPY" in sym else 0.0001
        cost = bt.COST_ECN[sym]
        best = None
        # 23-03 Uhr ausgeschlossen: Rollover-Spread verzerrt die Bid-Daten (siehe ERGEBNIS.md)
        for hs in range(3, 23):
            for L in range(1, 9):
                he = hs + L
                if he > 23:
                    continue
                for d in (1, -1):
                    r = window_trades(df, hs, he, d, pip, cost)
                    ins = r[r.index < bt.IS_END]
                    t = tstat(ins)
                    if best is None or t > best[0]:
                        best = (t, hs, he, d, ins.mean())
        t, hs, he, d, m = best
        oos = window_trades(df, hs, he, d, pip, cost)
        oos = oos[oos.index >= bt.IS_END]
        to = tstat(oos)
        found.append((sym, to))
        print(f"{sym:7s} {hs:02d}-{he:02d} Uhr {'long' if d > 0 else 'short':>6s} | {m:+11.2f} {t:5.2f} | {oos.mean():+12.2f} {to:5.2f} {len(oos):5d}")
    print("(Getestete Fenster je Paar: ca. 280 -> im IS sind t-Werte um 3 allein durch Zufall zu erwarten)")
    return found


def gotobi_mask(idx):
    """5./10./15./20./25. und Monatsletzter; faellt der Tag aufs Wochenende -> vorheriger Freitag."""
    s = pd.Series(idx, index=idx)
    out = np.zeros(len(idx), bool)
    for k, d in enumerate(idx):
        for target in (5, 10, 15, 20, 25, 30):
            try:
                t = d.replace(day=target)
            except ValueError:
                t = (d + pd.offsets.MonthEnd(0)).normalize()
            while t.weekday() >= 5:
                t -= pd.Timedelta(days=1)
            if t == d:
                out[k] = True
    return out


def gotobi(data):
    print("\n=== 2) Gotobi-Effekt USDJPY: long vom Tagesbeginn bis ca. Tokio-Fixing (Server 00-03/04 Uhr) ===")
    df = data["USDJPY"]
    for he in (3, 4):
        for name, mask in (("Gotobi-Tage", gotobi_mask), ("andere Tage", lambda i: ~gotobi_mask(i))):
            r = window_trades(df, 0, he, 1, 0.01, bt.COST_ECN["USDJPY"], mask)
            for per, rr in (("IS ", r[r.index < bt.IS_END]), ("OOS", r[r.index >= bt.IS_END])):
                print(f"  bis {he:02d} Uhr  {name:12s} {per}: {rr.mean():+6.2f} Pips netto/Tag, t={tstat(rr):5.2f}, n={len(rr)}")


if __name__ == "__main__":
    data = bt.load(sys.argv[1])
    scan_hours(data)
    gotobi(data)
