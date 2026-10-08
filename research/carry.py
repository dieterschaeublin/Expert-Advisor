"""Carry-Strategie (Zinsdifferenz) mit optionalem Trendfilter auf Tagesbasis.

Leitzinsen (Monatsende, gerundet; 2026 angenommen = letzter bekannter Stand).
Swap = Zinsdifferenz minus Broker-Aufschlag, taeglich verbucht. Kosten bei jedem Positionswechsel.
Aufruf: python3 research/carry.py <ordner-mit-csv>
"""
import sys
import numpy as np
import pandas as pd
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import backtest as bt

# (gueltig ab, Satz in %) - Fed Funds Obergrenze, EZB Einlagensatz, BoE Bank Rate, SNB Leitzins, BoJ
RATES = {
    "USD": [("2015-12", .50), ("2016-12", .75), ("2017-03", 1.0), ("2017-06", 1.25), ("2017-12", 1.5), ("2018-03", 1.75),
            ("2018-06", 2.0), ("2018-09", 2.25), ("2018-12", 2.5), ("2019-08", 2.25), ("2019-09", 2.0), ("2019-10", 1.75),
            ("2020-03", .25), ("2022-03", .5), ("2022-05", 1.0), ("2022-06", 1.75), ("2022-07", 2.5), ("2022-09", 3.25),
            ("2022-11", 4.0), ("2022-12", 4.5), ("2023-02", 4.75), ("2023-03", 5.0), ("2023-05", 5.25), ("2023-07", 5.5),
            ("2024-09", 5.0), ("2024-11", 4.75), ("2024-12", 4.5), ("2025-09", 4.25), ("2025-10", 4.0), ("2025-12", 3.75)],
    "EUR": [("2015-12", -.3), ("2016-03", -.4), ("2019-09", -.5), ("2022-07", 0.0), ("2022-09", .75), ("2022-11", 1.5),
            ("2022-12", 2.0), ("2023-02", 2.5), ("2023-03", 3.0), ("2023-05", 3.25), ("2023-06", 3.5), ("2023-08", 3.75),
            ("2023-09", 4.0), ("2024-06", 3.75), ("2024-09", 3.5), ("2024-10", 3.25), ("2024-12", 3.0), ("2025-01", 2.75),
            ("2025-03", 2.5), ("2025-04", 2.25), ("2025-06", 2.0)],
    "GBP": [("2015-12", .5), ("2016-08", .25), ("2017-11", .5), ("2018-08", .75), ("2020-03", .1), ("2021-12", .25),
            ("2022-02", .5), ("2022-03", .75), ("2022-05", 1.0), ("2022-06", 1.25), ("2022-08", 1.75), ("2022-09", 2.25),
            ("2022-11", 3.0), ("2022-12", 3.5), ("2023-02", 4.0), ("2023-03", 4.25), ("2023-05", 4.5), ("2023-06", 5.0),
            ("2023-08", 5.25), ("2024-08", 5.0), ("2024-11", 4.75), ("2025-02", 4.5), ("2025-05", 4.25), ("2025-08", 4.0)],
    "CHF": [("2015-12", -.75), ("2022-06", -.25), ("2022-09", .5), ("2022-12", 1.0), ("2023-03", 1.5), ("2023-06", 1.75),
            ("2024-03", 1.5), ("2024-06", 1.25), ("2024-09", 1.0), ("2024-12", .5), ("2025-03", .25), ("2025-06", 0.0)],
    "JPY": [("2015-12", .0), ("2016-02", -.1), ("2024-03", .1), ("2024-07", .25), ("2025-01", .5)],
}
SWAP_MARKUP = 1.0   # % p.a., den der Broker auf beiden Seiten abzieht (konservativ)


def rate_series(cur, index):
    s = pd.Series({pd.Timestamp(d): r for d, r in RATES[cur]}).sort_index()
    return s.reindex(s.index.union(index)).ffill().reindex(index).values


def backtest_pair(sym, df, trend_days, min_diff):
    d = df.resample("1D").agg({"o": "first", "h": "max", "l": "min", "c": "last"}).dropna()
    base, quote = sym[:3], sym[3:]
    diff = rate_series(base, d.index) - rate_series(quote, d.index)       # Zinsvorteil long
    pos = np.where(diff > min_diff, 1, np.where(diff < -min_diff, -1, 0)).astype(float)
    if trend_days:
        e = bt.ema(d.c.values, trend_days)
        pos = np.where((pos > 0) & (d.c.values < e), 0, pos)
        pos = np.where((pos < 0) & (d.c.values > e), 0, pos)
    pip = 0.01 if "JPY" in sym else 0.0001
    c = d.c.values
    gap_days = np.diff(d.index.values).astype("timedelta64[D]").astype(float)
    ret = np.zeros(len(c))
    p_prev = pos[:-1]
    ret[1:] = p_prev * (c[1:] / c[:-1] - 1)                                          # Kursveraenderung
    ret[1:] += (p_prev * diff[:-1] - np.abs(p_prev) * SWAP_MARKUP) / 100 / 365 * gap_days  # Swap
    turn = np.abs(np.diff(pos, prepend=0))
    ret -= turn * bt.COST_ECN[sym] * pip / c                                          # Kosten
    return pd.Series(ret, index=d.index), pd.Series(pos, index=d.index)


def summary(r):
    yrs = len(r) / 260
    ann = (1 + r).prod() ** (1 / yrs) - 1
    vol = r.std() * np.sqrt(260)
    eq = (1 + r).cumprod()
    dd = (1 - eq / eq.cummax()).max()
    return ann * 100, vol * 100, ann / vol if vol else np.nan, dd * 100


if __name__ == "__main__":
    data = bt.load(sys.argv[1])
    for trend in (0, 100):
        print(f"\n=== Carry {'+ Trendfilter EMA ' + str(trend) + ' Tage' if trend else 'pur'} (1:1 Hebel je Paar, gleich gewichtet) ===")
        rets = {}
        for sym, df in data.items():
            r, p = backtest_pair(sym, df, trend, 0.5)
            rets[sym] = r
            i, o = r[r.index < bt.IS_END], r[r.index >= bt.IS_END]
            a1, v1, s1, d1 = summary(i)
            a2, v2, s2, d2 = summary(o)
            print(f"{sym}: 2016-22 {a1:+5.1f}%/J Sharpe {s1:+.2f} DD {d1:4.1f}% | 2023-26 {a2:+5.1f}%/J Sharpe {s2:+.2f} DD {d2:4.1f}% "
                  f"| Anteil Tage investiert {(p != 0).mean():.0%}")
        port = pd.DataFrame(rets).fillna(0).mean(axis=1)
        for name, rr in (("2016-22", port[port.index < bt.IS_END]), ("2023-26", port[port.index >= bt.IS_END])):
            a, v, s, dd = summary(rr)
            print(f"  PORTFOLIO {name}: {a:+5.1f}%/Jahr, Vol {v:4.1f}%, Sharpe {s:+.2f}, max. Rueckgang {dd:4.1f}%")
        yearly = port.groupby(port.index.year).apply(lambda x: (1 + x).prod() - 1) * 100
        print("  pro Jahr: " + "  ".join(f"{y}:{v:+.1f}%" for y, v in yearly.items()))
