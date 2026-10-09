# M5 Trend-Scalper – Expert Advisor für MetaTrader 4

Ein automatisierter Scalping-EA für den **5-Minuten-Chart**, der viele kleine Trades **in Richtung des übergeordneten Trends** eröffnet und das Risiko pro Trade sowie pro Tag strikt begrenzt.

Datei: [`MQL4/Experts/M5_TrendScalper.mq4`](MQL4/Experts/M5_TrendScalper.mq4)

> **Neu: Direkte Verbindung mit Claude Desktop.** Mit dem [MetaTrader 4 Connector](connector/README.md) kann Claude den EA direkt in deinem MT4 installieren, kompilieren, starten und Konto/Trades auslesen.

---

## Strategie

Die Idee: **„Mit dem Trend handeln, aber erst nach einem Rücksetzer einsteigen.“** So kauft man im Aufwärtstrend günstig und verkauft im Abwärtstrend teuer. Kurze Haltedauer und kleine Ziele bringen eine hohe Trefferquote.

| Baustein | Indikator | Zweck |
|---|---|---|
| Trendfilter M5 | EMA 50 & EMA 200 | Long nur wenn Kurs > EMA 200, EMA 50 > EMA 200 und EMA 200 steigt (Short umgekehrt) |
| Trendfilter H1 | EMA 50 (H1) | Bestätigt den Trend auf höherem Zeitrahmen, filtert Seitwärtsphasen |
| Rücksetzer | Bollinger Bands (20, 2.0) | Kurs hat in den letzten 3 Kerzen das äußere Band berührt |
| Timing | RSI (7) | RSI kreuzt aus überverkauft (30) bzw. überkauft (70) zurück |
| Bestätigung | Kerzenfarbe | Signalkerze schließt in Trendrichtung |
| Stops | ATR (14) | SL = 2,0 × ATR (min. 8 Pips), TP = 2,0 × ATR – passt sich der Volatilität an |
| Kostenfilter | Spread vs. SL | Trade nur, wenn Spread (+ Kommission) ≤ 15 % des Stop Loss |
| Trendstärke (optional) | ADX (14) | Nur handeln, wenn ADX ≥ 20 |

### Long-Einstieg (Short spiegelbildlich)
1. Aufwärtstrend auf M5 **und** H1
2. Tief einer der letzten 3 Kerzen ≤ unteres Bollinger Band
3. RSI(7) war unter 30 und schließt wieder darüber
4. Letzte Kerze ist bullisch (Close > Open)

### Trade-Management
- **Break-Even:** ab 1,2 × ATR Gewinn wird der SL auf Einstieg + 1 Pip gezogen
- **Trailing-Stop:** standardmäßig aus (optional ab 1,5 × ATR, Abstand 1,0 × ATR)
- **Zeit-Exit:** Trades werden nach 72 Kerzen (6 Stunden) geschlossen
- **Wochenende:** freitags ab 18 Uhr keine neuen Trades, ab 21 Uhr wird alles geschlossen

---

## Risiko-Management

| Schutz | Standard |
|---|---|
| Risiko pro Trade | **0,5 %** des Kontos (Lotgröße wird automatisch berechnet) |
| Max. gleichzeitige Trades | 1 pro Symbol |
| Max. Trades pro Tag | 30 |
| Tagesverlust-Limit | 3 % → keine neuen Trades mehr an diesem Tag |
| Verlustserie | nach 3 Verlusten in Folge 60 Minuten Pause |
| Spread-Filter | max. 2,0 Pips |
| Kosten-Filter | Spread + Kommission ≤ 15 % des SL |
| Volatilitäts-Filter | ATR zwischen 3 und 20 Pips |
| Max. Stop Loss | 25 Pips – sonst kein Trade |
| Handelszeit | 08–20 Uhr Server-Zeit (London + New York) |

Der EA ist **ECN-kompatibel**: Die Order wird zuerst ohne SL/TP gesendet und danach sofort modifiziert. Kann der Stop Loss nicht gesetzt werden, wird der Trade aus Sicherheitsgründen sofort geschlossen – **es gibt nie eine Position ohne Stop Loss.**

---

## Empfehlungen

- **Zeitrahmen:** M5 (guter Kompromiss: genug Signale, aber weniger Rauschen und Spread-Anteil als M1; M15 liefert deutlich weniger Trades)
- **Währungspaare:** Paare mit niedrigem Spread – **EURUSD**, **USDJPY**, GBPUSD, AUDUSD, EURJPY
- **Broker:** ECN-/Raw-Spread-Konto mit niedrigen Kommissionen; bei Scalping fressen Spreads sonst den Gewinn
- **VPS:** für 24/5-Betrieb mit geringer Latenz empfohlen
- **Mehrere Paare:** EA auf jedem Chart separat starten – gleiche Magic Number ist ok, da nach Symbol getrennt wird. Gesamtrisiko beachten (z. B. 4 Paare × 0,5 % = 2 % gleichzeitig möglich)

---

## Installation

1. MetaTrader 4 öffnen → **Datei → Datenordner öffnen**
2. `M5_TrendScalper.mq4` nach `MQL4/Experts/` kopieren
3. Im MT4 **Navigator** → Rechtsklick auf *Expert Advisors* → **Aktualisieren** (oder Datei im MetaEditor öffnen und **F7** zum Kompilieren drücken)
4. Chart z. B. **EURUSD, M5** öffnen und den EA auf den Chart ziehen
5. Im Reiter *Allgemein* **„Live-Trading erlauben“** aktivieren, oben in der Symbolleiste **„Auto-Trading“** einschalten
6. Rechts oben erscheint ein lachender Smiley, links oben das Info-Panel

> **Server-Zeit beachten:** Die Handelszeiten beziehen sich auf die Uhrzeit des Brokers (im *Marktübersicht*-Fenster sichtbar). Viele Broker laufen auf GMT+2/+3 – dann entspricht 08–20 Uhr ungefähr der London- und New-York-Session.

---

## Warum Version 2? (Lehren aus dem ersten Backtest)

Backtest v1 (EURUSD M5, Spread 1,5 Pips, 10 000 USD): 1520 Trades, 52 % Treffer, **Netto −8429 USD**, Profit-Faktor 0,48.

| Ursache | Zahl | Änderung in v2 |
|---|---|---|
| Spread frisst den Gewinn | Spread ≈ 25 % des SL, ≈ 12 USD Kosten pro Trade, ≈ 19 000 USD gesamt | Kostenfilter (Spread ≤ 15 % SL), SL min. 8 Pips / 2 × ATR |
| Gewinner zu klein | Ø Gewinn 9,99 vs. Ø Verlust 22,31 → bräuchte 69 % Treffer | TP = SL (1:1), Break-Even später, Trailing aus |
| Schwaches Signal | 52 % Treffer ≈ Münzwurf | optionaler ADX-Filter, Optimierung empfohlen |

**Folge:** Bei 1,5 Pips Spread handelt v2 auf M5 deutlich seltener (nur bei ATR ≥ ca. 5 Pips). Für mehr Trades: **M15-Chart** oder ein **ECN-/Raw-Konto** (Spread 0,1–0,3 Pips + Kommission; dann `InpCommissionPips` ≈ 0,7 setzen).

## Backtest & Optimierung (unbedingt vor Live-Einsatz!)

1. **Ansicht → Strategietester** (Strg+R)
2. Expert: `M5_TrendScalper`, Symbol: EURUSD, Zeitraum: **M5**, Modell: **„Jeder Tick“**
3. Mindestens 1–2 Jahre Daten testen (Daten über *Extras → Historienzentrum* laden; für realistische Ergebnisse Tickdaten verwenden)
4. Spread im Tester realistisch einstellen (z. B. 10 Punkte = 1 Pip bei 5-stelligen Kursen) – der Standard „aktuell“ ist bei Scalpern oft zu optimistisch

Sinnvolle Parameter zum Optimieren:
- `InpRsiPeriod` (5–14), `InpRsiOversold` / `InpRsiOverbought` (20–35 / 65–80)
- `InpSLAtrMult` (1,0–2,5), `InpTPAtrMult` (0,8–2,0)
- `InpSessionStartHour` / `InpSessionEndHour`
- `InpUseHTFFilter` / `InpUseBBFilter` / `InpRequireCandle` (aus = **mehr** Trades, aber meist schlechtere Qualität)

**Mehr Trades gewünscht?** RSI-Grenzen auf 35/65 setzen, `InpBBLookback` erhöhen oder den H1-Filter abschalten. **Weniger Risiko?** `InpRiskPercent` auf 0,25 % senken.

Danach **mindestens 4 Wochen auf einem Demokonto** laufen lassen, bevor echtes Geld eingesetzt wird.

---

## Alle Parameter

| Gruppe | Parameter | Standard | Beschreibung |
|---|---|---|---|
| Allgemein | `InpMagicNumber` | 250501 | Kennung der EA-Orders |
| | `InpSlippagePips` | 1.5 | Max. Slippage |
| Money Mgmt | `InpRiskPercent` | 0.5 | Risiko % pro Trade (0 = feste Lots) |
| | `InpFixedLots` | 0.01 | Feste Lots, wenn Risiko = 0 |
| | `InpMaxLots` | 5.0 | Obergrenze Lotgröße |
| | `InpMaxOpenTrades` | 1 | Gleichzeitige Trades pro Symbol |
| | `InpMaxTradesPerDay` | 30 | Trades pro Tag |
| Trend | `InpEmaFast` / `InpEmaSlow` | 50 / 200 | EMAs auf Chart-Zeitrahmen |
| | `InpEmaSlopeBars` | 5 | Steigung der EMA 200 prüfen |
| | `InpUseHTFFilter`, `InpHTF`, `InpHTFEma` | true, H1, 50 | Filter höherer Zeitrahmen |
| | `InpUseAdxFilter`, `InpAdxPeriod`, `InpAdxMin` | false, 14, 20 | ADX-Trendstärke-Filter |
| Einstieg | `InpRsiPeriod` | 7 | RSI-Periode |
| | `InpRsiOversold` / `InpRsiOverbought` | 30 / 70 | RSI-Grenzen |
| | `InpUseBBFilter`, `InpBBPeriod`, `InpBBDeviation`, `InpBBLookback` | true, 20, 2.0, 3 | Bollinger-Band-Filter |
| | `InpRequireCandle` | true | Bestätigungskerze |
| Exits | `InpAtrPeriod` | 14 | ATR-Periode |
| | `InpSLAtrMult` / `InpTPAtrMult` | 2.0 / 2.0 | SL/TP als ATR-Vielfaches |
| | `InpMinSLPips` / `InpMaxSLPips` | 8 / 25 | SL-Grenzen |
| | `InpUseBreakEven`, `InpBEAtrMult`, `InpBELockPips` | true, 1.2, 1.0 | Break-Even |
| | `InpUseTrailing`, `InpTrailStartAtr`, `InpTrailDistAtr` | false, 1.5, 1.0 | Trailing-Stop |
| | `InpMaxBarsInTrade` | 72 | Zeit-Exit (0 = aus) |
| Filter | `InpMaxSpreadPips` | 2.0 | Max. Spread |
| | `InpMaxSpreadToSL` | 0.15 | Max. Kosten im Verhältnis zum SL (0 = aus) |
| | `InpCommissionPips` | 0 | Kommission pro Trade in Pips (ECN) |
| | `InpMinAtrPips` / `InpMaxAtrPips` | 3 / 20 | Volatilitätsbereich |
| | `InpUseSession`, `InpSessionStartHour`, `InpSessionEndHour` | true, 8, 20 | Handelszeiten |
| | `InpFridayStopHour`, `InpFridayCloseAll`, `InpFridayCloseHour` | 18, true, 21 | Wochenend-Schutz |
| Schutz | `InpDailyLossPct` | 3.0 | Tagesverlust-Limit % |
| | `InpDailyProfitPct` | 0 | Tagesziel % (0 = aus) |
| | `InpMaxConsecLosses`, `InpPauseMinutes` | 3, 60 | Pause nach Verlustserie |
| | `InpShowPanel` | true | Info-Panel |

> **Hinweis bei JPY-Paaren und Gold:** Die Pip-Berechnung erfolgt automatisch (3/5-stellige Kurse). Bei Gold (XAUUSD) oder Indizes müssen `InpMaxSpreadPips`, `InpMin/MaxAtrPips` und `InpMin/MaxSLPips` angepasst werden.

---

## ⚠️ Risikohinweis

Forex- und CFD-Handel mit Hebel ist mit einem hohen Verlustrisiko verbunden. Dieser EA ist **keine Gewinngarantie**. Vergangene Ergebnisse (auch im Backtest) lassen keine Rückschlüsse auf die Zukunft zu. Scalping reagiert besonders empfindlich auf Spreads, Kommissionen, Slippage und Latenz – Ergebnisse können sich daher von Broker zu Broker stark unterscheiden. Setze nur Kapital ein, dessen Verlust du verkraften kannst, und teste immer zuerst auf einem Demokonto.

---

# ECN Momentum-Scalper (für ECN-/Raw-Spread-Konten)

Datei: [`MQL4/Experts/ECN_MomentumScalper.mq4`](MQL4/Experts/ECN_MomentumScalper.mq4)

Neuer Ansatz nach der Auswertung des M5_TrendScalper-Backtests: Dort lag die Trefferquote bis zum Break-Even bei 56 % – ein **zufälliger** Einstieg hätte bei denselben Abständen ca. 54 % erreicht. Das Rücksetzer-Signal (RSI + Bollinger) hatte also keinen Vorteil. Der ECN-EA handelt deshalb **mit** dem Momentum statt dagegen.

## Strategie
| Baustein | Regel |
|---|---|
| Trend | H1-Schlusskurs über/unter EMA 50 **und** M5-Schlusskurs über/unter EMA 100 |
| Ausbruch | Schlusskurs bricht frisch aus dem Hoch/Tief der letzten 20 M5-Kerzen aus |
| Momentum | Ausbruchskerze mit Körper ≥ 0,5 × ATR, Schluss im oberen/unteren Drittel |
| Volatilität | ATR(14) ≥ ATR(100) – nur wenn der Markt in Bewegung kommt |
| Kosten | Spread + Kommission ≤ 15 % des Stop Loss; Kommission ist in der Lotgröße eingerechnet |
| Stop Loss | 1,5 × ATR (6–20 Pips) |
| Take Profit | 1,5 R (1,5 × Stop-Abstand) |
| Break-Even | ab 1 R, gesichert werden Kommission + 0,3 Pips |
| Zeit-Exit | nach 36 Kerzen (3 Stunden) |
| Sperre | nach einem Verlust 12 Kerzen keine Trades in dieselbe Richtung |
| Handelszeit | 9–19 Uhr Server-Zeit, max. 12 Trades/Tag |
| Kontoschutz | 0,5 % Risiko/Trade, Tagesverlust-Limit 2 %, Pause nach 4 Verlusten in Folge |

## ECN-Kosten im MT4-Strategietester simulieren

Der MT4-Tester zieht **keine Kommission** ab. Damit der Test realistisch ist, die Kommission in den Spread einrechnen:

| Einstellung | Wert | Begründung |
|---|---|---|
| Spread (Tester, Feld „Spread“) | **9** | 0,2 Pips Raw-Spread + 0,7 Pips Kommission ($7/Lot) = 0,9 Pips |
| `InpCommissionPerLot` | **0** | Kommission steckt schon im Spread – sonst doppelt gezählt |
| `InpMaxSpreadPips` | 1.0 (Standard) | |

Im **Live-Betrieb** auf dem ECN-Konto: `InpCommissionPerLot` auf die echte Kommission deines Brokers setzen (z. B. 7.0 für $3,50 pro Seite und Lot) und Tester-Spread vergessen.

## Testprotokoll (bitte so durchführen)
1. **Zeitraum A** 2023.01.01–2024.12.31 mit Standard-Einstellungen testen
2. **Zeitraum B** 2025.01.01–2026.10.07 mit **denselben** Einstellungen testen
3. Nur wenn **beide** Zeiträume Profit-Faktor > 1,1 zeigen, auf ein ECN-Demokonto
4. Zum Vergleich einmal mit Spread 15 testen – das zeigt, wie stark das Ergebnis an den Kosten hängt

> **Ehrlicher Hinweis:** Auch dieser EA konnte nicht mit echten Kursdaten getestet werden (kein Datenzugang in der Entwicklungsumgebung). Er ist logisch besser begründet als der Rücksetzer-Ansatz, aber erst der Backtest zeigt, ob er einen Vorteil hat.

---

# D1 RSI(2)-Rückkehr – EXPERIMENT (nur Demo)

Datei: [`MQL4/Experts/D1_RSI2_Reversion_DEMO.mq4`](MQL4/Experts/D1_RSI2_Reversion_DEMO.mq4)

Einziger Kandidat aus der [Strategie-Recherche](research/ERGEBNIS.md) – **ohne statistisch belegten Vorteil** (Backtest 2023–2026: +0,039 R/Trade, Profit-Faktor 1,19, t = 0,8). Er läuft standardmäßig **nur auf Demokonten**.

| Regel | Wert |
|---|---|
| Zeitrahmen | D1, je ein Chart für EURUSD, GBPUSD, USDJPY, USDCHF, EURGBP |
| Long | RSI(2) < 5 und Schluss über EMA(600) |
| Short | RSI(2) > 95 und Schluss unter EMA(600) |
| Stop | 2 × ATR(14), kein Take Profit |
| Exit | Schluss über/unter EMA(5) oder nach 12 Tagen |
| Erwartung | ca. 34 Trades/Jahr über alle 5 Paare zusammen |

Zum Beobachten: mindestens 6 Monate auf dem Demokonto laufen lassen und mit dem Backtest vergleichen.

---

# Weekend-Gap-Fill – EXPERIMENT mit Messprotokoll

Datei: [`MQL4/Experts/WeekendGapFill.mq4`](MQL4/Experts/WeekendGapFill.mq4)

Handelt die Kurslücke zum Wochenbeginn Richtung Freitags-Schluss – aber **erst, wenn Spread + Kommission ≤ 15 % der offenen Restlücke** sind. Hintergrund: Im Backtest (Bid-Daten) schließt sich die Lücke meist in der ersten Stunde, wenn die Spreads am höchsten sind; ob danach ein Vorteil übrig bleibt, muss **live gemessen** werden (der MT4-Tester rechnet mit festem Spread).

| Regel | Standard |
|---|---|
| Mindest-Lücke | 0,25 × Tages-ATR(14) |
| Richtung (`InpDirection`) | beide / **nur Verkäufe nach Lücke hoch** (empfohlen für den Test) / nur Käufe |
| Warten auf günstigen Spread | max. 60 Minuten nach Wochen-Eröffnung |
| Mindest-Restlücke beim Einstieg | 60 % der ursprünglichen Lücke |
| Ziel | 50 % der Restlücke |
| Stop | 2 × Lückengröße |
| Zeit-Exit | 24 Stunden |
| Risiko | 0,5 % inkl. Kommission (7 $/Lot Standard) |

**Einsatz:** ECN-Demokonto, je ein Chart pro Symbol (EURUSD, GBPUSD, USDJPY, USDCHF, EURGBP; später Gold/Indizes), Zeitrahmen egal. Mac/VPS muss am **Montag zur Wochen-Eröffnung** laufen.

**Messprotokoll:** `MQL4/Files/WeekendGap_<Symbol>.csv` – Lücke, Spread und Restlücke **minutenweise** in der ersten Stunde, Signale, Trades. Nach 2–3 Monaten die CSV-Dateien zur Auswertung schicken. Mit `InpTradeEnabled = false` misst der EA nur, ohne zu handeln.

---

# Martingale-Grid – Nachkauf mit Lot-Verdopplung (nur Demo)

Datei: [`MQL4/Experts/MartingaleGrid.mq4`](MQL4/Experts/MartingaleGrid.mq4)

Startet mit **0,01 Lot** und kauft nach, wenn der Kurs gegen die Position läuft. Bei jedem Nachkauf wird die Lotgröße **verdoppelt**. Der ganze Korb wird geschlossen, sobald er netto (inkl. Kommission und Swap) **10 Pips über dem Durchschnittspreis** steht.

| Stufe | 1 | 2 | 3 | 4 | 5 | 6 | Korb-Stop |
|---|---|---|---|---|---|---|---|
| Abstand zum Start | 0 | 25 | 55 | 91 | 134 | 186 | 248 Pips |
| Lots | 0,01 | 0,02 | 0,04 | 0,08 | 0,16 | 0,32 | Σ 0,63 |

Der Nachkauf-Abstand beginnt bei 25 Pips und wächst je Stufe um den Faktor 1,2. So braucht der Korb mehr Kursbewegung, bevor er die großen Stufen erreicht. Nach der letzten Stufe (186 Pips) muss sich der Kurs nur um rund 42 Pips erholen, damit der Korb im Ziel ist.

| Parameter | Standard |
|---|---|
| Richtung | Trend: Schluss über/unter EMA 200 auf H4 (oder nur Kauf / nur Verkauf) |
| Start-Lots / Faktor | 0,01 / 2,0 |
| Nachkauf-Abstand | 25 Pips, je Stufe × 1,2 |
| Max. Stufen | 6 |
| Korb-Ziel | +10 Pips netto über Durchschnitt |
| Korb-Stop | eine Stufe hinter dem letzten Nachkauf (248 Pips), Verlust ca. **650 USD** auf EURUSD |
| Equity-Stop | Korb schließen bei Verlust ≥ 10 % des Kontostands |
| Pause nach Notbremse | 24 Stunden |
| Freitag | ab 18 Uhr kein neuer Korb |
| Spread-Filter | max. 2,5 Pips |

Beim Start schreibt der EA den Plan mit dem maximalen Verlust in Kontowährung ins Journal. **Empfohlenes Konto:** ab 10.000 USD bei 0,01 Start-Lot. Mit 1.000 USD greift bei diesen Einstellungen schon um Stufe 4–5 der Equity-Stop.

> ⚠️ **Verdoppeln erhöht die Trefferquote, nicht die Erwartung.** Viele kleine Gewinne (ca. 1–6 USD je Korb bei 0,01 Start) werden selten, aber sicher von einem großen Verlust (ca. 650 USD) aufgezehrt. Ein einziger Korb-Stop entspricht grob 100–600 Gewinn-Körben. Ohne die Notbremsen führt eine lange Trendphase zum Totalverlust. Erst ausgiebig im Strategietester und auf einem Demokonto testen.
