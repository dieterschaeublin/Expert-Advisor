# MetaTrader 4 Connector für Claude Desktop

Ein **lokaler Connector** (MCP-Server), der Claude Desktop direkt mit deinem MetaTrader 4 auf dem Mac (oder Windows) verbindet. Danach kannst du im Chat z. B. sagen:

> „Installiere den M5_TrendScalper und starte ihn auf EURUSD M5 mit 0,25 % Risiko.“
> „Wie steht mein Konto? Welche Trades sind offen?“
> „Zeig mir die letzten Meldungen des EA.“

Alles läuft auf deinem Computer – **keine Zugangsdaten verlassen den Mac**, es gibt keinen Cloud-Dienst dazwischen.

---

## So funktioniert es

```
Claude Desktop ──(Connector .mcpb)──► MT4-Datenordner ◄──(liest/schreibt)── ClaudeBridge-EA in MT4
                    │                    MQL4/Experts  (EAs installieren)
                    │                    MQL4/Files/ClaudeBridge  (Befehle/Antworten)
                    └─► MetaEditor (über Wine) zum Kompilieren
```

| Teil | Aufgabe |
|---|---|
| `metatrader4-connector.mcpb` | Erweiterung für Claude Desktop. Findet den MT4-Datenordner, kopiert und kompiliert EAs, liest Logs, schickt Befehle an MT4 |
| `ClaudeBridge.mq4` | Kleiner EA, der in MT4 auf **einem** Chart läuft und die Befehle des Connectors ausführt (Kontodaten, Positionen, Chart öffnen + EA laden, optional Trades). Er handelt **nicht** selbst |

---

## Einrichtung (einmalig, ca. 5 Minuten)

### 1. Claude Desktop installieren
Falls noch nicht vorhanden: [claude.ai/download](https://claude.ai/download) → Mac-Version installieren und anmelden.
*(Der Connector funktioniert nur in der Desktop-App, nicht im Browser oder am Handy.)*

### 2. Connector installieren
1. Datei [`dist/metatrader4-connector.mcpb`](../dist/metatrader4-connector.mcpb) herunterladen
2. **Doppelklick** auf die Datei → Claude Desktop öffnet sich → **Installieren**
   *(Alternativ: Claude Desktop → Einstellungen → Erweiterungen → Datei ins Fenster ziehen)*
3. Einstellungen des Connectors:
   - **MT4-Datenordner:** leer lassen (wird automatisch gesucht). Falls nicht gefunden: in MT4 *Datei → Datenordner öffnen* und diesen Ordner auswählen
   - **Trading erlauben:** vorerst **aus** lassen
4. Connector aktivieren (Schalter auf „an“)

### 3. ClaudeBridge in MT4 installieren
1. MT4 starten
2. In Claude Desktop einen neuen Chat öffnen und schreiben:
   > „Prüfe meinen MT4-Status und installiere die ClaudeBridge.“
3. In MT4: **Navigator** (Menü *Ansicht → Navigator*) → Rechtsklick auf *Expert Advisors* → **Aktualisieren**
4. **ClaudeBridge** auf einen beliebigen Chart ziehen (z. B. EURUSD H1)
   - Reiter *Allgemein*: „Live-Trading erlauben“ ✔
   - Reiter *Eingaben*: „Trading über Claude erlauben“ **false** lassen (siehe unten)
5. Oben **AutoTrading** einschalten → Smiley oben rechts im Chart, Text „ClaudeBridge aktiv“ oben links

> Falls Claude meldet, dass das automatische Kompilieren nicht geklappt hat: In MT4 **F4** (am Mac ggf. **fn+F4**) drücken (MetaEditor), links *ClaudeBridge.mq4* öffnen, **F7** drücken. Danach Schritt 3.

### 4. Fertig – Beispiele
- „Installiere den M5_TrendScalper und starte ihn auf EURUSD M5.“
- „Starte den M5_TrendScalper zusätzlich auf USDJPY mit InpRiskPercent 0.25.“
- „Zeig mir Kontostand und offene Positionen.“
- „Wie war das Ergebnis der letzten 7 Tage?“
- „Gibt es Fehler im Experten-Log?“

Claude fragt vor dem Starten eines EA bzw. vor Trades nach deiner Bestätigung.

---

## Trading über Claude (optional)

Standardmäßig kann Claude **nur lesen und EAs installieren/starten** – keine Orders. Damit Claude selbst Trades eröffnen, schließen oder ändern darf, müssen **beide** Schalter an sein:

1. Claude Desktop → Einstellungen → Erweiterungen → MetaTrader 4 Connector → **Trading erlauben**
2. ClaudeBridge-EA → Eingaben → **Trading über Claude erlauben = true** (zusätzlich Limit „Max. Lotgröße“, Standard 1.0)

Für den automatischen Handel mit dem M5_TrendScalper ist das **nicht nötig** – der EA handelt selbst.

---

## Verfügbare Werkzeuge

| Werkzeug | Funktion |
|---|---|
| `mt4_status` | Datenordner, Bridge-Status, MetaEditor/Wine, Freigaben |
| `mt4_list_experts` | Installierte EAs inkl. Kompilierstatus |
| `mt4_install_ea` | Mitgelieferten oder eigenen EA installieren und kompilieren |
| `mt4_compile_ea` | EA kompilieren, Fehler/Warnungen zurückgeben |
| `mt4_attach_ea` | Neuen Chart öffnen und EA mit Eingaben laden |
| `mt4_read_log` | Experten- oder Terminal-Log lesen |
| `mt4_account` / `mt4_positions` / `mt4_history` | Konto, offene und geschlossene Trades |
| `mt4_quote` / `mt4_charts` | Kurs/Spread, offene Charts |
| `mt4_open_trade` / `mt4_close_trade` / `mt4_modify_trade` | Trading (nur mit doppelter Freigabe) |

---

## Fehlerbehebung

| Problem | Lösung |
|---|---|
| „Kein MetaTrader-4-Datenordner gefunden“ | In MT4 *Datei → Datenordner öffnen*, Ordner in den Connector-Einstellungen eintragen |
| „Keine Antwort von MetaTrader … noch nie gestartet“ | ClaudeBridge ist nicht auf einem Chart → Schritt 3 |
| „ClaudeBridge läuft nicht“ | MT4 ist geschlossen oder der Chart mit ClaudeBridge wurde entfernt |
| Kompilieren klappt nicht | In MT4 F4 → Datei öffnen → F7. Optional in den Einstellungen den Pfad zu `wine64` angeben (liegt meist in `/Applications/MetaTrader 4.app/Contents/SharedSupport/wine/bin/`) |
| EA nach `mt4_attach_ea` nicht aktiv | AutoTrading einschalten; notfalls EA manuell auf den von Claude geöffneten Chart ziehen |
| Mehrere MT4-Installationen | `mt4_status` zeigt alle; den gewünschten Datenordner in den Einstellungen festlegen |

---

## Hinweise

- **Getestet** wurde der Connector mit einem simulierten MT4-Datenordner (automatische Tests in `test/`). Die MQL4-Bridge und das automatische Kompilieren über Wine konnten mangels MT4 in der Entwicklungsumgebung nicht live getestet werden – bei Problemen bitte die Meldung von Claude bzw. aus dem Experten-Log weitergeben.
- `mt4_attach_ea` nutzt eine Chartvorlage (`ChartApplyTemplate`). Je nach MT4-Build kann es sein, dass der EA danach noch manuell bestätigt werden muss.
- Der Connector funktioniert nur, solange MT4 läuft. Für 24/5-Betrieb MT4 auf einem (Windows-)VPS betreiben – der Connector läuft dann in Claude Desktop auf dem VPS.

## Entwicklung

```bash
cd connector
npm install
npm test          # Tests mit simuliertem MT4
npm run build     # erzeugt ../dist/metatrader4-connector.mcpb
```
