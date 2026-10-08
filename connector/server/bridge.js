// Datei-basierte Kommunikation mit dem ClaudeBridge-EA in MetaTrader 4.
// Befehl:  MQL4/Files/ClaudeBridge/<id>.cmd   (key=value pro Zeile)
// Antwort: MQL4/Files/ClaudeBridge/<id>.json  (vom EA geschrieben)
import fs from "node:fs";
import path from "node:path";
import { bridgeDir, readBridgeStatus } from "./mt4.js";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let counter = 0;

function encodeParams(params) {
  return Object.entries(params)
    .filter(([, v]) => v !== undefined && v !== null && v !== "")
    .map(([k, v]) => `${k}=${String(v).replace(/[\r\n=]/g, " ")}`)
    .join("\r\n");
}

export async function sendCommand(dataDir, action, params = {}, { timeoutMs = 10000, pollMs = 100 } = {}) {
  const dir = bridgeDir(dataDir);
  fs.mkdirSync(dir, { recursive: true });

  const id = `${Date.now()}_${process.pid}_${counter++}`;
  const part = path.join(dir, `${id}.part`);
  const cmd = path.join(dir, `${id}.cmd`);
  const res = path.join(dir, `${id}.json`);

  fs.writeFileSync(part, encodeParams({ action, ...params }) + "\r\n", "latin1");
  fs.renameSync(part, cmd);

  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (fs.existsSync(res)) {
      let text = "";
      // Datei kann einen Moment nach dem Umbenennen noch leer sein
      for (let i = 0; i < 5 && !text; i++) {
        text = fs.readFileSync(res, "latin1").trim();
        if (!text) await sleep(50);
      }
      fs.rmSync(res, { force: true });
      try {
        return JSON.parse(text);
      } catch {
        throw new Error(`Ungueltige Antwort von ClaudeBridge: ${text.slice(0, 200)}`);
      }
    }
    await sleep(pollMs);
  }

  const stillQueued = fs.existsSync(cmd);
  fs.rmSync(cmd, { force: true });
  const status = readBridgeStatus(dataDir);
  let hint;
  if (!status) hint = "Der ClaudeBridge-EA wurde in diesem Datenordner noch nie gestartet. Bitte 'ClaudeBridge' auf einen Chart ziehen.";
  else if (!status.alive) hint = `ClaudeBridge laeuft nicht (letztes Lebenszeichen vor ${status.age_seconds}s). Ist MT4 offen und der EA auf einem Chart?`;
  else hint = stillQueued ? "ClaudeBridge laeuft, hat den Befehl aber nicht abgeholt." : "ClaudeBridge hat nicht rechtzeitig geantwortet.";
  throw new Error(`Keine Antwort von MetaTrader (${action}). ${hint}`);
}
