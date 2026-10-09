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

## Nachtrag: Carry (Zinsdifferenz, `carry.py`)

Halten der höher verzinsten Währung, Swap = Leitzinsdifferenz − 1 % p.a. Broker-Aufschlag, ECN-Kosten bei Wechseln.

| Variante | 2016–2022 | 2023–2026 |
|---|---|---|
| Carry pur, Portfolio 5 Paare | −0,3 %/Jahr, Sharpe −0,06 | +1,6 %/Jahr, Sharpe +0,34 |
| Carry + Trendfilter (EMA 100 Tage) | −0,6 %/Jahr | +0,6 %/Jahr |

Positiv fast nur durch **USDJPY** (2023–2026 +9,3 %/Jahr) – eine Einzelwette auf die Zinsdifferenz USA/Japan
mit bekanntem Crash-Risiko (z. B. August 2024). Mit nur 5 G10-Paaren und kleinen Zinsdifferenzen
reicht der Swap-Ertrag nach Broker-Aufschlag nicht. **Kein nachhaltiger Ansatz.**

## Nachtrag: Weekend-Gap-Fill (`weekend_gap.py`)

Kurslücke zum Wochenbeginn (Montag-Eröffnung vs. Freitags-Schluss), Handel Richtung Lückenschluss.
Typische Lücke: 6–10 Pips (Median); Lücken > 0,25 Tages-ATR: ca. 10 pro Jahr und Paar. 72 Varianten.

| Einstieg | Varianten positiv 2016–22 | 2023–26 | Median R 2016–22 | Trefferquote |
|---|---|---|---|---|
| 1. Stunde (Wochen-Eröffnung) | 96 % | 100 % | +0,12 R | 76 % |
| 2. Stunde | **0 %** | 62 % | −0,06 R | 63 % |
| 3. Stunde | 0 % | 17 % | −0,15 R | 54 % |

**Bewertung:** Der Lückenschluss findet überwiegend in der **ersten Stunde** statt – genau dann, wenn die
Spreads zur Wochen-Eröffnung stark ausgeweitet sind (EURUSD oft mehrere Pips). Die Bid-Daten zeigen den
Vorteil, aber zum realen Ask ist er vermutlich nicht erreichbar. Ab der 2. Stunde (normale Spreads) ist der
Ansatz 2016–2022 in **allen** Varianten negativ. Ohne Bid/Ask-Tickdaten der Wochen-Eröffnung nicht abschließend
prüfbar → mit Dukascopy-Tickdaten (Bid + Ask) gezielt nachtesten.

### Gap-Fill: Richtung und Positionsgröße

Sofort-Einstieg nach Richtung (Lücke > 0,25 ATR, Ziel 50 %, Stop 2 × Lücke):

| Richtung | 2016–22 | 2023–26 | Bewertung |
|---|---|---|---|
| Kauf nach Lücke runter | 93 % Treffer, +0,13 R, t = 5,5 | 96 %, +0,19 R, t = 18 | **unglaubwürdig**: Kauf erfolgt zum Ask (bei Eröffnung stark ausgeweitet); zudem erzeugt der Rollover-Rückgang des Bid künstliche „Lücken nach unten“, die sich mit normalisierendem Spread „schließen“ (doppelt so viele Fälle wie nach oben) |
| Verkauf nach Lücke hoch (zum Bid = realistisch) | 76 %, −0,05 R, t = −1,0 | 84 %, +0,11 R, t = 2,2 | uneinheitlich, kein belastbarer Vorteil |

Positionsgröße (realistischer Einstieg 2. Stunde, 463 Trades, Erwartung −0,005 R):
0,5 % Risiko → −1 %, max. Rückgang 8 % · 2 % → −5,5 %, 29 % · 5 % → −17 %, 58 % · 10 % → −40 %, 84 %.
Hohe Trefferquote bei kleinem Gewinn/großem Verlust rechtfertigt **keine** größere Position.

### Gap-Fill mit 15 Paaren (`gap_by_direction.py`)

Lücken > 0,25 ATR: **462 nach oben, 1341 nach unten** – die starke Schieflage bestätigt das Rollover-Artefakt
(Bid fällt zur Eröffnung künstlich → scheinbare Lücken nach unten). Kauf-Ergebnisse (96–98 % Treffer, t bis 60) sind daher nicht verwertbar.

| Verkauf nach Lücke hoch (Stop 2 × Lücke) | 2016–22 | 2023–26 |
|---|---|---|
| sofort | 74 %, −0,026 R, t = −1,0 | 82 %, +0,096 R, t = +4,1 |
| 2. Stunde | 71 %, −0,051 R, t = −2,1 | 68 %, −0,020 R, t = −0,7 |
| sofort, nur Lücken > 0,5 ATR | gesamt 70 %, +0,030 R, t = +1,2 | |

**Bewertung:** Positiv nur sofort und nur 2023–2026; 2016–2022 negativ. Nicht konsistent → kein
belastbarer Vorteil. Klärung nur mit Bid/Ask-Daten oder Live-Messung auf ECN-Demo (WeekendGapFill-EA).

**Update mit 22 Paaren:** Lücken > 0,25 ATR: 686 nach oben, 1993 nach unten (Artefakt bestätigt).
Verkauf sofort: 2016–22 −0,009 R (t = −0,5, n = 473) · 2023–26 +0,094 R (t = +4,8, n = 213).
Verkauf 2. Stunde: in beiden Zeiträumen negativ. Unverändertes Fazit: nur 2023–2026 positiv.
Der EA hat dafür die Option `InpDirection` (nur Verkäufe) zur Live-Messung auf ECN-Demo.

**Gold/Silber (Gegenprobe):** Metalle eröffnen nicht genau zum Rollover → keine künstliche Schieflage
(Gold: 38 Lücken hoch, 22 runter). Ergebnis: **kein Vorteil** in keiner Richtung (Gold sofort: −0,04 R / +0,01 R
Verkauf, −0,11 R / −0,07 R Kauf). Stützt die Vermutung, dass der scheinbar starke FX-Lückenschluss zum großen
Teil vom Rollover-Effekt in den Bid-Daten stammt.

## Nachtrag: Konto verdoppeln (`verdoppelung.py`)

Monte-Carlo, 20 000 Pfade, 5 Jahre, festes Risiko in % des aktuellen Kontos. Gezählt wird, was zuerst eintritt:
Konto ×2 oder Konto ×0,5. Trefferquote 60 %, Gewinn in R so gewählt, dass die Erwartung stimmt.

| Risiko/Trade | RSI2-D1, +0,04 R, 34/Jahr | +0,04 R, 170/Jahr (hypothetisch) | 0 R, 250/Jahr | −0,05 R, 250/Jahr |
|---|---|---|---|---|
| 0,5 % | 0 % ×2 · 0 % ×0,5 | 0 % · 0 % | 0 % · 0 % | 0 % · 1 % |
| 1 % | 0 % · 0 % | 9 % · 0 % | 1 % · 2 % | 0 % · 53 % |
| 2 % | 1 % · 0 % | **52 % · 2 %** | 15 % · 32 % | 0 % · 94 % |
| 5 % | 30 % · 13 % | 69 % · 29 % | 33 % · 66 % | 4 % · 96 % |
| 10 % | 48 % · 44 % | 52 % · 48 % | 33 % · 67 % | 13 % · 87 % |
| 20 % | 42 % · 58 % | 42 % · 58 % | 32 % · 68 % | 21 % · 79 % |

**Bewertung:**
- Ohne Vorteil (0 R) ist Verdoppeln bei jedem Risiko **unwahrscheinlicher als Halbieren** (max. ~33 %).
  Mit den realen Kosten (−0,05 R) halbiert sich das Konto schon bei 1–2 % Risiko meist innerhalb von 5 Jahren.
  Mehr Risiko macht aus einer Strategie ohne Vorteil nur ein schnelleres Münzwerfen mit Verlust.
- Selbst der beste Kandidat (+0,04 R, nicht signifikant) verdoppelt bei 0,5 % Risiko in 5 Jahren praktisch nie
  (Median-Konto +3 %). Ab ~10 % Risiko überwiegt der Volatilitätsverlust den Vorteil.
- Ein realistischer Weg zur Verdopplung bräuchte einen **belegten** Vorteil von ≥ 0,04 R bei **≥ 150 Trades/Jahr**
  und ~2 % Risiko. Einen solchen Ansatz hat die Recherche nicht gefunden.

**Fazit:** Ein „Verdopplungs-EA“ lässt sich nicht über Lotgröße oder Hebel erzwingen. Ohne nachgewiesenen
Vorteil ist der sicherste Weg zu einem höheren Kontostand, das Risiko klein zu halten und weiter nach einem
echten Vorteil zu suchen (z. B. Gap-Fill-Live-Messung auf ECN-Demo).
