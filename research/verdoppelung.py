"""Konto verdoppeln: Wie wahrscheinlich ist das bei gegebenem Vorteil und Risiko pro Trade?

Monte-Carlo mit festem Risiko-Anteil pro Trade (Lots wachsen/schrumpfen mit dem Konto).
Ein Pfad endet, wenn das Konto sich verdoppelt (Ziel) oder halbiert (Ruin) oder die Laufzeit abläuft.
Trade-Ergebnis zweiwertig: Gewinn +b R mit Wahrscheinlichkeit p, sonst -1 R (b aus Erwartung abgeleitet).

Aufruf:  python3 research/verdoppelung.py
"""
import numpy as np

YEARS = 5
PATHS = 20000
RISKS = (0.005, 0.01, 0.02, 0.05, 0.10, 0.20)

# (Bezeichnung, Erwartung je Trade in R, Trefferquote, Trades pro Jahr)
CASES = (
    ("RSI2-D1 (bester Kandidat, +0,04 R, 34/Jahr)", 0.04, 0.60, 34),
    ("gleicher Ansatz, 5x mehr Trades (170/Jahr)", 0.04, 0.60, 170),
    ("kein Vorteil (0 R, 250/Jahr)", 0.00, 0.60, 250),
    ("typisch nach Kosten (-0,05 R, 250/Jahr)", -0.05, 0.60, 250),
)


def simulate(edge, p, n_year, risk, rng):
    b = (edge + (1 - p)) / p  # Gewinn in R, so dass p*b - (1-p) = edge
    n = YEARS * n_year
    win = rng.random((PATHS, n)) < p
    growth = np.where(win, 1 + risk * b, 1 - risk)
    eq = np.cumprod(growth, axis=1)
    hit_up = eq >= 2.0
    hit_dn = eq <= 0.5
    first_up = np.where(hit_up.any(1), hit_up.argmax(1), n)
    first_dn = np.where(hit_dn.any(1), hit_dn.argmax(1), n)
    doubled = first_up < first_dn
    halved = first_dn < first_up
    years = (first_up[doubled] + 1) / n_year
    return doubled.mean(), halved.mean(), (np.median(years) if doubled.any() else np.nan), np.median(eq[:, -1])


def main():
    rng = np.random.default_rng(1)
    print(f"Laufzeit {YEARS} Jahre, {PATHS} Pfade. Ziel: Konto x2 vor Konto x0,5.\n")
    for label, edge, p, n_year in CASES:
        print(label)
        print(f"  {'Risiko':>7} | {'verdoppelt':>10} | {'halbiert':>8} | {'Median Jahre bis x2':>19} | {'Median Konto (ohne Stopp)':>25}")
        for risk in RISKS:
            up, dn, yrs, med = simulate(edge, p, n_year, risk, rng)
            yrs_s = f"{yrs:.1f}" if np.isfinite(yrs) else "-"
            print(f"  {risk:7.1%} | {up:10.0%} | {dn:8.0%} | {yrs_s:>19} | {med:25.2f}")
        print()


if __name__ == "__main__":
    main()
