# M5 Trend-Scalper – Expert Advisor für MetaTrader 4

Ein automatisierter Scalping-EA für den **5-Minuten-Chart**, der viele kleine Trades **in Richtung des übergeordneten Trends** eröffnet und das Risiko pro Trade sowie pro Tag strikt begrenzt.

Datei: [`MQL4/Experts/M5_TrendScalper.mq4`](MQL4/Experts/M5_TrendScalper.mq4)

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
| Stops | ATR (14) | SL = 1,5 × ATR, TP = 1,2 × ATR – passt sich der Volatilität an |

### Long-Einstieg (Short spiegelbildlich)
1. Aufwärtstrend auf M5 **und** H1
2. Tief einer der letzten 3 Kerzen ≤ unteres Bollinger Band
3. RSI(7) war unter 30 und schließt wieder darüber
4. Letzte Kerze ist bullisch (Close > Open)

### Trade-Management
- **Break-Even:** ab 0,7 × ATR Gewinn wird der SL auf Einstieg + 0,5 Pips gezogen
- **Trailing-Stop:** ab 0,9 × ATR Gewinn folgt der SL im Abstand 0,6 × ATR
- **Zeit-Exit:** Trades werden nach 48 Kerzen (4 Stunden) geschlossen
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
| Volatilitäts-Filter | ATR zwischen 2 und 15 Pips |
| Max. Stop Loss | 20 Pips – sonst kein Trade |
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
| Einstieg | `InpRsiPeriod` | 7 | RSI-Periode |
| | `InpRsiOversold` / `InpRsiOverbought` | 30 / 70 | RSI-Grenzen |
| | `InpUseBBFilter`, `InpBBPeriod`, `InpBBDeviation`, `InpBBLookback` | true, 20, 2.0, 3 | Bollinger-Band-Filter |
| | `InpRequireCandle` | true | Bestätigungskerze |
| Exits | `InpAtrPeriod` | 14 | ATR-Periode |
| | `InpSLAtrMult` / `InpTPAtrMult` | 1.5 / 1.2 | SL/TP als ATR-Vielfaches |
| | `InpMinSLPips` / `InpMaxSLPips` | 5 / 20 | SL-Grenzen |
| | `InpUseBreakEven`, `InpBEAtrMult`, `InpBELockPips` | true, 0.7, 0.5 | Break-Even |
| | `InpUseTrailing`, `InpTrailStartAtr`, `InpTrailDistAtr` | true, 0.9, 0.6 | Trailing-Stop |
| | `InpMaxBarsInTrade` | 48 | Zeit-Exit (0 = aus) |
| Filter | `InpMaxSpreadPips` | 2.0 | Max. Spread |
| | `InpMinAtrPips` / `InpMaxAtrPips` | 2 / 15 | Volatilitätsbereich |
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
