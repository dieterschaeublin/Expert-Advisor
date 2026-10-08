# Strategie-Recherche – Ergebnis (Oktober 2026)

**Daten:** MT4-H1-Export (MetaQuotes-Demo) EURUSD, GBPUSD, USDJPY, USDCHF, EURGBP, 2016–2026.
**Methode:** `backtest.py` – Optimierung 2016–2022, Prüfung 2023–2026; Bewertung über alle 5 Paare gemeinsam;
ECN-Kosten 0,9–1,4 Pips pro Trade; Stop zuerst, wenn Stop und Ziel in derselben Kerze liegen; kein Swap.
**Validierung der Testumgebung:** Zufallseinstiege ergeben −0,046 R (theoretisch erwartet −0,047 R).

## Ergebnis: Kein belastbar profitabler Ansatz gefunden

Insgesamt **~200 Varianten** aus 5 Strategie-Familien auf H1, H4 und D1 getestet.

| Familie | H1 | H4 | D1 | Bemerkung |
|---|---|---|---|---|
| Donchian-Trendausbruch | ✗ | ✗ | ✗ | 2016–2026 schon **vor Kosten** negativ |
| EMA-Kreuzung | ✗ | ✗ | ✗ | Zeitraum 2016–2022 teils positiv, 2023–2026 in allen Varianten negativ |
| Zeitreihen-Momentum | ✗ | ✗ | ✗ | vor Kosten negativ |
| London-Breakout | ✗ | – | – | vor Kosten +0,005 R, Kosten −0,05 R |
| RSI(2)-Rückkehr im Trend | ✗ | ≈0 | (+) | einziger Kandidat, siehe unten |

**Bester Kandidat:** RSI(2)-Rückkehr auf D1 (RSI(2) < 5 im Aufwärtstrend über EMA 600, Exit über EMA 5, Stop 2 × Tages-ATR)
- 2016–2022: +0,045 R/Trade, t = 1,1
- 2023–2026: +0,039 R/Trade, t = 0,8, Profit-Faktor 1,19
- ca. 34 Trades/Jahr über 5 Paare, Haltedauer ~4 Tage
- Bei 0,5 % Risiko/Trade ≈ **0,7 % Rendite pro Jahr**

**Bewertung:** Nicht statistisch signifikant (t < 2). Bei ~200 getesteten Varianten sind einige positive Treffer
allein durch Zufall zu erwarten. Kein ausreichender Beleg für einen echten Vorteil.

Die früheren M5-EAs (M5_TrendScalper, ECN_MomentumScalper) bestätigen das Bild: Auf kurzen Zeitrahmen
schwanken einfache Indikator-Signale um null, die Kosten machen daraus einen stetigen Verlust.

## Nachtrag: Dokumentierte Markteffekte (`anomalies.py`)

| Effekt | 2016–2022 | 2023–2026 | Bewertung |
|---|---|---|---|
| „Long um Mitternacht“ (alle Paare, t = 8–18) | stark | stark | **Datenartefakt:** Bid-Kurse fallen beim Rollover (Spread-Ausweitung, Kurslücke −1 bis −3 Pips um 0 Uhr) und erholen sich bis 2 Uhr. Zum Ask nicht handelbar. |
| Tageszeit-Effekt (Breedon & Ranaldo), ohne 23–03 Uhr | EURUSD short 11–15 Uhr t = 3,8 | t = 0,4 | passt zur Theorie, aber nicht mehr vorhanden (bei ~280 Fenstern je Paar ist t ≈ 3 im IS auch Zufall) |
| Gotobi USDJPY (Tokio-Fixing) | t = 2,5 | t = 0,4 | nicht mehr vorhanden |

**Fazit:** Auch die in der Literatur beschriebenen Effekte bestehen den Out-of-Sample-Test nicht.
