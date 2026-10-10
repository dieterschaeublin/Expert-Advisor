# Web-Recherche: Welche EA-Strategien haben die besten Belege? (Oktober 2026)

**Ziel:** Ansätze finden, für die es *unabhängige* Belege gibt (Fachartikel, lange Datenreihen, Out-of-Sample),
statt weitere Indikator-Kombinationen zu optimieren. Ausgangspunkt sind die eigenen Ergebnisse in
[`ERGEBNIS.md`](ERGEBNIS.md): ~270 getestete Varianten auf FX (H1–D1), kein belastbarer Vorteil.

---

## 1. Was die Literatur über die bisherigen Ergebnisse sagt

Die eigenen Fehlschläge passen zum Stand der Forschung, sie sind also kein Programmierfehler:

| Eigenes Ergebnis | Befund in der Literatur |
|---|---|
| Kurzfristige FX-Indikatorsignale ≈ 0, nach Kosten negativ | Schnelle Trend-Horizonte haben schon **vor Kosten** an Ertrag verloren (Winton-Whitepaper, siehe Quellen) |
| FX-Momentum/Trend (Donchian, EMA, TSMOM) negativ | Replikation von Währungs-Momentum mit Daten bis 2020: Sharpe **0,66 In-Sample → 0,06 Out-of-Sample**, übersteht keine moderaten Kosten. Mit vollem Spread fällt das Original von 10 % auf 4 % p.a. |
| Tageszeit- und Gotobi-Effekt nur In-Sample | Kalendereffekte verschwinden typischerweise nach Veröffentlichung: **Pre-FOMC-Drift** seit 2016 praktisch weg (Kurov/Wolfe/Gilbert 2021); **Overnight-Drift** im US-Aktienmarkt (02–03 Uhr ET, ~3,7 %/Jahr) laut NY Fed seit 2021 nahe null |
| Carry mit 5 G10-Paaren schwach | Carry braucht viele Währungen mit großen Zinsdifferenzen; G10 allein ist zu dünn |
| Viele Varianten → einzelne positive Treffer | Genau das beschreiben Bailey/López de Prado: bei vielen Versuchen ist der beste Backtest fast immer überschätzt (→ *Deflated Sharpe Ratio*, *PBO*) |

**Folgerung:** Mit FX allein auf Basis von Kurs-Indikatoren ist nach heutigem Wissensstand wenig zu holen.
Die besten Belege gibt es für Effekte, die (a) einen **strukturellen Grund** haben (erzwungene Handelsströme,
Risikoprämie), (b) über **viele Märkte und Jahrzehnte** gemessen wurden und (c) mit **festen Parametern aus der
Quelle** getestet werden können, also ohne eigene Optimierung.

---

## 2. Kandidaten mit den stärksten Belegen (nach Priorität)

### A) Intraday-Momentum auf US-Aktienindizes (US500 / NAS100) ⭐ höchste Priorität

**Belege:**
- **Baltussen, Da, Lammers, Martens (2021, *Journal of Financial Economics*)**: Über 60 Futures (Aktien, Anleihen,
  Rohstoffe, Währungen), 1974–2020. Die Rendite des Tages bis zur letzten halben Stunde sagt die Rendite der
  **letzten 30 Minuten** voraus. **Mechanismus:** Gamma-Hedging von Options-Market-Makern und gehebelten ETFs, die
  *mit* der Bewegung handeln müssen. Diese Ströme sind strukturell und durch das wachsende 0DTE-Optionsvolumen eher
  größer geworden.
- **Zarattini, Aziz, Barbon (2024/2025), „Beat the Market“**: SPY, 1-Minuten-Daten 2007–2024.
  „Noise Area“ = Band um die Tageseröffnung aus der durchschnittlichen Intraday-Bewegung der letzten **14 Tage**
  (Multiplikator 1). Ausbruch → Position in Ausbruchsrichtung, Trailing-Stop, Schluss vor Handelsende.
  Ergebnis **nach Kosten**: 19,6 % p.a., Sharpe 1,33 (Buy & Hold: 0,45).

**Warum gut für einen MT4-EA:**
- rein intraday → **keine Overnight-Finanzierung** (bei Index-CFDs sonst ca. Leitzins + 2,5 % p.a. auf Long-Positionen)
- Parameter kommen aus der Studie → praktisch **ein einziger Versuch**, kein Data-Mining
- unabhängig von den bisher getesteten FX-Ideen (Diversifikation)

**Risiken:** CFD-Spread auf US500 (ca. 0,4–1 Punkt) und Ausführung zur vollen/halben Stunde; der Effekt ist bei
Futures gemessen, nicht bei CFDs. Die Zarattini-Ergebnisse stammen von den Autoren selbst (ein Autor betreibt eine
Trading-Firma) → unabhängige Prüfung nötig.

**Testplan:** M1- oder M5-Export US500 aus MT4 (so weit zurück wie möglich), Regeln 1:1 aus dem Paper,
reale CFD-Spreads; Teilperioden bis 2019 / 2020–2026 getrennt auswerten. Akzeptanz nur bei positivem Ergebnis in
**beiden** Perioden nach Kosten.

### B) Langsames Trendfolgen über viele Anlageklassen + Volatilitäts-Steuerung

**Belege:**
- Zeitreihen-Momentum (Moskowitz/Ooi/Pedersen 2012): 12-Monats-Signal profitabel über 58 Märkte;
  Langzeitstudie 1880–2016: ~11 % p.a. netto bei halber Aktienvolatilität.
- 2022 Rekordjahr (SG Trend Index +27 %), 2023 flach, 2024 gemischt → **lange Durststrecken sind normal**.
- Gold: 24-Monats-Momentum gehört zu den wenigen Regeln, die Buy & Hold schlagen (Bartsch et al. 2018).
- Volatilitäts-Targeting (Harvey et al. 2018, Moreira/Muir 2017): verbessert Sharpe bei Aktien/Risiko-Anlagen und
  **reduziert extreme Verluste in allen Klassen**; bei FX allein kaum Sharpe-Gewinn.

**Wichtig – Unterschied zum eigenen Test:** Getestet wurden bisher nur 5 FX-Paare. Trendfolgen funktioniert in der
Literatur *nur als Portfolio* über Anlageklassen (Indizes, Anleihen, Energie, Metalle, Agrar, FX). Der Ertrag kommt
aus wenigen großen Trends, die man nur erwischt, wenn man breit gestreut ist.

**Umsetzung als EA:** D1, ein Signal (z. B. 12-Monats-Rendite bzw. EMA-Kreuz 50/200 als Äquivalent), Positionsgröße
so, dass jedes Instrument das gleiche Risiko (Ziel-Volatilität) trägt, ~15–25 CFDs.
**Haupthindernis:** CFD-Finanzierung (Leitzins ± 2,5 % p.a.) frisst bei monatelangen Haltedauern einen großen Teil des
erwarteten Ertrags → vor dem Bau Swap-Sätze des Brokers je Instrument erfassen und im Backtest berücksichtigen.
Ehrliche Erwartung: Sharpe 0,3–0,6, mehrjährige Verlustphasen möglich.

### C) Kurzfristige Rückkehr zum Mittelwert auf Aktienindizes (RSI(2), long only)

**Belege:** Connors/Alvarez (2008) auf S&P 500; die Idee ist seit über 15 Jahren öffentlich, Praktiker berichten
Fortbestand. Plausibel, weil Aktienindizes eine positive Drift haben und kurzfristig überreagieren.
**Aber:** keine unabhängige, kostenbereinigte Studie mit Trennung vor/nach Veröffentlichung gefunden → schwächste
Beweislage der drei. Der eigene D1-RSI(2)-Test auf FX war der einzige leicht positive Kandidat (t ≈ 1) – auf
Indizes sollte der Effekt stärker sein, weil FX keine Drift hat.

**Vorteil:** `backtest.py` kann das mit D1-Indexdaten fast ohne Aufwand prüfen → schneller, billiger Test.

### D) Monatsende-/Turn-of-the-Month auf Indizes – nur als Zusatzfilter

Carchano/Pardo (188 Kalenderanomalien in S&P-500-, DAX-, Nikkei-Futures): Turn-of-the-Month war die **einzige**, die
über Teilperioden bestand. Ältere Studie der Atlanta Fed: verschwunden nach 1990. Uneinheitlich → nicht als
eigenständiger EA, höchstens als Filter für A/C.

---

## 3. Wovon die Belege abraten

| Ansatz | Grund |
|---|---|
| Martingale / Grid / Averaging | Hohe Trefferquote, aber negativer Erwartungswert bleibt; Totalverlust-Risiko (siehe eigene Positionsgrößen-Simulation) |
| Indikator-Kombis auf M1–H1 FX | Literatur und eigene Tests: ≈ 0 vor Kosten |
| Veröffentlichte Kalendereffekte (Pre-FOMC, Overnight-Drift, Gotobi, Tageszeit) | nach Veröffentlichung verschwunden |
| ML/Neuronale Netze auf Indikatoren | höchstes Überanpassungsrisiko; ohne sehr strenge Validierung nicht aussagekräftig |
| Monatsende-Fixing-Flows FX | nur Bankmodelle, Trefferquote laut Banken selbst „gemischt“, kein unabhängiger Beleg |
| Weekend-Gap-Fill | eigener Test: vermutlich Rollover-Artefakt der Bid-Daten |

---

## 4. Methodik für alle weiteren Tests

1. **Hypothese und Parameter vorher festlegen** (aus der Quelle übernehmen) und hier dokumentieren.
2. **Versuche zählen.** Bei N getesteten Varianten den besten Sharpe mit der *Deflated Sharpe Ratio* bewerten.
   Bisher ~270 Varianten → ein t-Wert von 2 reicht nicht.
3. Zwei getrennte Zeiträume (bis 2019 / ab 2020), Akzeptanz nur wenn **beide** nach Kosten positiv.
4. Realistische Kosten: Bid/Ask, Kommission, **Swap/Finanzierung**, Ausführung zum nächsten Kurs.
5. Danach mindestens 3 Monate Demo-Live-Messung mit Vergleich Live vs. Backtest derselben Periode.

---

## 5. Empfehlung / nächste Schritte

1. **Intraday-Momentum-EA US500 (A)** bauen und testen – stärkste Beweislage, struktureller Grund, kein Swap,
   Parameter fix aus dem Paper. Dafür nötig: M1/M5-Export US500 (und NAS100) aus MT4.
2. **RSI(2) long only auf US500/GER40 D1 (C)** als schneller Test mit vorhandenem `backtest.py`.
3. **Trendfolge-Portfolio (B)** nur, wenn die Swap-Sätze des Brokers es zulassen – zuerst Kostenrechnung.

Realistische Erwartung: Selbst die besten belegten Ansätze liefern Sharpe-Werte um 0,5–1,3 *vor*
Umsetzungsverlusten. Ein EA, der im Backtest deutlich mehr verspricht, ist mit hoher Wahrscheinlichkeit überangepasst.

---

## Quellen

- Baltussen, Da, Lammers, Martens: *Hedging Demand and Market Intraday Momentum*, JFE 2021 –
  [EUR](https://pure.eur.nl/en/publications/hedging-demand-and-market-intraday-momentum/),
  [PDF](https://www3.nd.edu/~zda/intramom.pdf)
- Zarattini, Aziz, Barbon: *Beat the Market – An Effective Intraday Momentum Strategy for SPY* –
  [Concretum](https://concretumgroup.com/beat-the-market-an-effective-intraday-momentum-strategy-for-sp500-etf-spy/),
  [Uni St. Gallen PDF](https://alexandria.unisg.ch/server/api/core/bitstreams/a99aba00-f967-49b3-aceb-f544dc386e0b/content)
- Boyarchenko, Larsen, Whelan: *The Overnight Drift* –
  [NY Fed SR 917](https://www.newyorkfed.org/medialibrary/media/research/staff_reports/sr917.pdf);
  [Liberty Street Economics 07/2026: The Disappearing Overnight Drift](https://libertystreeteconomics.newyorkfed.org/2026/07/the-disappearing-overnight-drift/)
- Kurov, Wolfe, Gilbert: *The Disappearing Pre-FOMC Announcement Drift* –
  [PDF](https://www.skidmore.edu/economics/documents/KurovWolfeGilbert-TheDisappearingPre-FOMC-Announce-Drift-200914.pdf)
- Menkhoff, Sarno, Schmeling, Schrimpf: *Currency Momentum Strategies* –
  [City Univ.](https://openaccess.city.ac.uk/3296); Kosten: [CXO](https://www.cxoadvisory.com/momentum-investing/momentum-investing-for-currencies);
  Replikation bis 2020: [ADU](https://repository.adu.ac.ae/bitstreams/30d15095-739e-4967-a33f-7233bf0644df/download)
- Levine, Pedersen: *Which Trend Is Your Friend?* – [CBS PDF](https://research-api.cbs.dk/ws/files/60084063/lasse_heje_pedersen_et_al_which_trend_is_your_friend_publishersversion.pdf)
- Trend-Following-Performance: [Graham Capital](https://www.grahamcapital.com/wp-content/uploads/2023/08/Is-Trend-Following-Performance-Mercurial_July-2022-1.pdf),
  [SG CTA 2022](https://alpha-week.com/2022-cta-index-performance-review),
  [Top Traders Unplugged 2024](https://www.toptradersunplugged.com/?p=14551),
  [Winton: Fast trend decay](https://www.TrendFollowing.com/whitepaper/d.pdf)
- Gold-Momentum (Bartsch et al.): [CXO](https://www.cxoadvisory.com/?p=31400)
- Volatilitäts-Targeting: [Harvey et al.](https://people.duke.edu/~charvey/Research/Published_Papers/P135_The_impact_of.pdf),
  [Moreira/Muir NBER](https://www.nber.org/papers/w22208.pdf)
- Turn-of-the-Month: [Atlanta Fed](https://www.atlantafed.org/research/publications/wp/2000/11.aspx),
  [CXO Kalendereffekte Futures](https://cxoadvisory.com/calendar-effects/stock-index-futures-calendar-effects),
  [Quantpedia](https://quantpedia.com/strategies/turn-of-the-month-in-equity-indexes)
- RSI(2): [CXO-Review Connors](https://www.cxoadvisory.com/technical-trading/a-few-notes-on-short-term-trading-strategies-that-work/)
- Überanpassung: [Deflated Sharpe Ratio](https://papers.ssrn.com/abstract=2460551),
  [Probability of Backtest Overfitting](https://papers.ssrn.com/abstract=2326253)
- CFD-Finanzierung: [IG](https://www.ig.com/en-ch/help-and-support/articles/840292-what-funding-and-interest-charges-do-you-apply-to-cash-cfds),
  [City Index](https://cityindex.com/en-au/trading-academy/courses/trading-with-city-index/overnight-funding-explained)
- FX-Monatsende-Flows: [FTSE Russell](https://www.lseg.com/content/lseg/en_us/insights/ftse-russell/is-london-end-of-day-still-key-for-apac-fx-traders)
