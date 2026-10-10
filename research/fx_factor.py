"""Waehrungs-Faktor-Portfolio (Carry + Momentum + Value-Umkehr) - Backtest zum EA FX_FactorBasket.mq4.

Gleiche Regeln wie der EA, Parameter fest (nicht optimiert):
  * 8 Waehrungen (USD + je eine pro USD-Paar), Signale jeweils gegen USD (USD selbst = 0)
  * Carry  = Leitzins(c) - Leitzins(USD)
  * Momentum = Rendite der letzten 63 Handelstage (3 Monate)
  * Value-Umkehr = -(Rendite der letzten 756 Handelstage, 36 Monate); fehlt bis genug Historie da ist
  * je Signal z-Wert ueber alle Waehrungen, Mittelwert der z-Werte, Gewichte = Abweichung vom Mittel (Summe 0)
  * Volatilitaets-Steuerung: Ziel 6 % p.a. aus den letzten 60 Tagen, Brutto-Hebel max. 3
  * Umschichtung am letzten Handelstag des Monats (Schlusskurs), gilt ab dem Folgetag
Kosten: ECN-Kosten je Paar auf den Umsatz, Swap = Zinsdifferenz minus SWAP_MARKUP auf jeder Position.
Der Notfall-Stop und der Rueckgang-Schalter des EA werden nicht simuliert.

Aufruf: python3 research/fx_factor.py <ordner-mit-csv>
Benoetigt H1-Exporte von EURUSD, GBPUSD, AUDUSD, NZDUSD, USDJPY, USDCHF, USDCAD.
"""
import sys
import numpy as np
import pandas as pd
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import backtest as bt
from carry import rate_series, summary, SWAP_MARKUP

PAIRS = ["EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDJPY", "USDCHF", "USDCAD"]
MOM_DAYS, VALUE_DAYS, VOL_DAYS = 63, 756, 60
TARGET_VOL, MAX_GROSS = 0.06, 3.0


def currency(pair):
    """Waehrung des Paars ausser USD und Vorzeichen (+1: Paar long = Waehrung long)."""
    return (pair[3:], -1) if pair.startswith("USD") else (pair[:3], 1)


def zscore(x):
    x = np.asarray(x, float)
    s = x.std()
    return (x - x.mean()) / s if s > 0 else np.zeros_like(x)


def weights(i, px, rets, rates, use):
    """Zielgewichte je Waehrung (ohne USD) am Tag i; Logik identisch zum EA."""
    n = px.shape[1]
    zs = []
    if use["carry"]:
        zs.append(zscore(np.append(rates[i], 0.0)))
    if use["mom"] and i >= MOM_DAYS:
        zs.append(zscore(np.append(px[i] / px[i - MOM_DAYS] - 1, 0.0)))
    if use["value"] and i >= VALUE_DAYS:
        zs.append(zscore(np.append(-(px[i] / px[i - VALUE_DAYS] - 1), 0.0)))
    if not zs or i < VOL_DAYS:
        return np.zeros(n)
    s = np.mean(zs, axis=0)
    w = (s - s.mean())[:n]                      # USD-Gewicht ist implizit -Summe
    vol = (rets[i - VOL_DAYS + 1:i + 1] @ w).std() * np.sqrt(260)
    if vol <= 0:
        return np.zeros(n)
    w = w * TARGET_VOL / vol
    gross = np.abs(w).sum()
    return w * MAX_GROSS / gross if gross > MAX_GROSS else w


def run(data, use):
    pairs = [p for p in PAIRS if p in data]
    closes = pd.DataFrame({p: data[p].c.resample("1D").last() for p in pairs}).dropna()
    closes = closes[closes.index.dayofweek < 5]
    ccys = [currency(p)[0] for p in pairs]
    sign = np.array([currency(p)[1] for p in pairs])
    px = np.where(sign > 0, closes.values, 1 / closes.values)          # Waehrung in USD
    rets = np.vstack([np.zeros(len(pairs)), px[1:] / px[:-1] - 1])
    rates = np.column_stack([rate_series(c, closes.index) for c in ccys]) - rate_series("USD", closes.index)[:, None]
    cost = np.array([bt.cost_pips(p) * bt.pip_size(p) for p in pairs]) / closes.values   # Anteil am Nominal
    days = np.append(1.0, np.diff(closes.index.values).astype("timedelta64[D]").astype(float))
    month_end = closes.index.to_series().dt.month.diff().shift(-1).fillna(1).values != 0

    w = np.zeros(len(pairs))
    out, gross = np.zeros(len(closes)), np.zeros(len(closes))
    for i in range(len(closes)):
        out[i] = w @ rets[i] + (w @ rates[i - 1] - np.abs(w).sum() * SWAP_MARKUP) / 100 / 365 * days[i] if i else 0.0
        if month_end[i]:
            new = weights(i, px, rets, rates, use)
            out[i] -= np.abs(new - w) @ cost[i]
            w = new
        gross[i] = np.abs(w).sum()
    return pd.Series(out, index=closes.index), pd.Series(gross, index=closes.index)


if __name__ == "__main__":
    data = bt.load(sys.argv[1])
    missing = [p for p in PAIRS if p not in data]
    if len(PAIRS) - len(missing) < 3:
        sys.exit("Mindestens 3 der Paare noetig: " + ", ".join(PAIRS))
    if missing:
        print("ACHTUNG - ohne " + ", ".join(missing) + " (weniger Waehrungen als im EA)")
    variants = {"Carry": dict(carry=1, mom=0, value=0), "Momentum": dict(carry=0, mom=1, value=0),
                "Value-Umkehr": dict(carry=0, mom=0, value=1), "KOMBINIERT (EA)": dict(carry=1, mom=1, value=1)}
    for name, use in variants.items():
        r, g = run(data, use)
        r, g = r[g.cummax() > 0], g[g.cummax() > 0]                  # erst ab der ersten Position werten
        print(f"\n=== {name}  (ab {r.index[0]:%Y-%m}, mittl. Brutto-Hebel {g.mean():.2f}) ===")
        for label, rr in (("2016-22", r[r.index < bt.IS_END]), ("2023-26", r[r.index >= bt.IS_END])):
            if len(rr) > 60:
                a, v, s, dd = summary(rr)
                print(f"  {label}: {a:+5.1f}%/Jahr, Vol {v:4.1f}%, Sharpe {s:+.2f}, max. Rueckgang {dd:4.1f}%")
        yearly = r.groupby(r.index.year).apply(lambda x: (1 + x).prod() - 1) * 100
        print("  pro Jahr: " + "  ".join(f"{y}:{v:+.1f}%" for y, v in yearly.items()))
