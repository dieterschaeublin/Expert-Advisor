// Dateisystem-Zugriff auf eine MetaTrader-4-Installation:
// Datenordner finden, EAs installieren, Logs lesen, Chart-Vorlagen erzeugen.
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

export const BRIDGE_DIR = "ClaudeBridge";
export const SAFE_NAME = /^[A-Za-z0-9_\-]{1,64}$/;

const TIMEFRAMES = { M1: 1, M5: 5, M15: 15, M30: 30, H1: 60, H4: 240, D1: 1440, W1: 10080, MN1: 43200 };

/** Ein Wert aus der Claude-Desktop-Konfiguration ist "leer", wenn er fehlt oder ein unaufgeloester Platzhalter ist. */
export function configValue(raw) {
  if (raw === undefined || raw === null) return "";
  const v = String(raw).trim();
  return v.startsWith("${") ? "" : v;
}

export function timeframeToMinutes(tf) {
  const m = TIMEFRAMES[String(tf).toUpperCase()];
  if (!m) throw new Error(`Unbekannter Zeitrahmen "${tf}". Erlaubt: ${Object.keys(TIMEFRAMES).join(", ")}`);
  return m;
}

/** Ist dies ein MT4-Datenordner (enthaelt MQL4/Experts)? */
export function isDataDir(dir) {
  try {
    return fs.statSync(path.join(dir, "MQL4", "Experts")).isDirectory();
  } catch {
    return false;
  }
}

function searchRoots() {
  const home = os.homedir();
  if (process.platform === "darwin") {
    return [path.join(home, "Library", "Application Support"), path.join(home, ".wine"), "/Applications"];
  }
  if (process.platform === "win32") {
    return [
      process.env.APPDATA && path.join(process.env.APPDATA, "MetaQuotes", "Terminal"),
      process.env.ProgramFiles,
      process.env["ProgramFiles(x86)"],
    ].filter(Boolean);
  }
  return [path.join(home, ".wine"), path.join(home, ".mt4")];
}

/** Breitensuche nach Ordnern, die MQL4/Experts enthalten (begrenzte Tiefe und Anzahl). */
export function findDataDirs(roots = searchRoots(), { maxDepth = 10, maxDirs = 40000 } = {}) {
  const found = [];
  const queue = roots.filter((r) => fs.existsSync(r)).map((r) => ({ dir: r, depth: 0 }));
  let visited = 0;
  const skip = new Set(["node_modules", ".git", "Caches", "Logs", "MQL5", "history", "tester", "Google", "Mozilla"]);

  while (queue.length && visited < maxDirs) {
    const { dir, depth } = queue.shift();
    visited++;
    if (isDataDir(dir)) {
      found.push(dir);
      continue; // nicht weiter in einen Datenordner hinein
    }
    if (depth >= maxDepth) continue;
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      if (!e.isDirectory() || e.isSymbolicLink() || skip.has(e.name)) continue;
      queue.push({ dir: path.join(dir, e.name), depth: depth + 1 });
    }
  }
  return found;
}

export function bridgeDir(dataDir) {
  return path.join(dataDir, "MQL4", "Files", BRIDGE_DIR);
}

/** Liest status.json der Bruecke (falls vorhanden) inkl. Alter in Sekunden. */
export function readBridgeStatus(dataDir) {
  const file = path.join(bridgeDir(dataDir), "status.json");
  try {
    const stat = fs.statSync(file);
    const status = JSON.parse(fs.readFileSync(file, "latin1"));
    const ageSeconds = (Date.now() - stat.mtimeMs) / 1000;
    return { ...status, age_seconds: Math.round(ageSeconds), alive: status.running !== false && ageSeconds < 10 };
  } catch {
    return null;
  }
}

function lastActivity(dataDir) {
  const candidates = [path.join(bridgeDir(dataDir), "status.json"), path.join(dataDir, "MQL4", "Logs"), path.join(dataDir, "logs")];
  let latest = 0;
  for (const c of candidates) {
    try {
      latest = Math.max(latest, fs.statSync(c).mtimeMs);
    } catch {
      /* ignorieren */
    }
  }
  return latest;
}

/** Waehlt den passenden Datenordner: konfiguriert > laufende Bruecke > zuletzt benutzt. */
export function resolveDataDir(configured, cache = {}) {
  const cfg = configValue(configured);
  if (cfg) {
    if (!isDataDir(cfg)) {
      throw new Error(`Der konfigurierte Ordner "${cfg}" ist kein MT4-Datenordner (MQL4/Experts fehlt). In MT4: Datei > Datenordner oeffnen.`);
    }
    return { dataDir: cfg, candidates: [cfg], source: "konfiguriert" };
  }
  if (!cache.candidates) cache.candidates = findDataDirs();
  const candidates = cache.candidates;
  if (!candidates.length) {
    throw new Error(
      "Kein MetaTrader-4-Datenordner gefunden. Bitte in MT4 'Datei > Datenordner oeffnen' waehlen und diesen Ordner " +
        "in den Connector-Einstellungen von Claude Desktop als 'MT4-Datenordner' eintragen."
    );
  }
  const alive = candidates.find((d) => readBridgeStatus(d)?.alive);
  if (alive) return { dataDir: alive, candidates, source: "aktive ClaudeBridge" };
  const sorted = [...candidates].sort((a, b) => lastActivity(b) - lastActivity(a));
  return { dataDir: sorted[0], candidates, source: "zuletzt benutzt" };
}

export function listExperts(dataDir) {
  const dir = path.join(dataDir, "MQL4", "Experts");
  const files = fs.readdirSync(dir);
  const names = new Set(files.filter((f) => /\.(mq4|ex4)$/i.test(f)).map((f) => f.replace(/\.(mq4|ex4)$/i, "")));
  return [...names].sort().map((name) => {
    const src = path.join(dir, `${name}.mq4`);
    const bin = path.join(dir, `${name}.ex4`);
    const srcStat = fs.existsSync(src) ? fs.statSync(src) : null;
    const binStat = fs.existsSync(bin) ? fs.statSync(bin) : null;
    return {
      name,
      source: Boolean(srcStat),
      compiled: Boolean(binStat),
      compiled_up_to_date: Boolean(srcStat && binStat && binStat.mtimeMs >= srcStat.mtimeMs),
      modified: srcStat ? srcStat.mtime.toISOString() : binStat?.mtime.toISOString(),
    };
  });
}

/** Schreibt eine .mq4-Datei nach MQL4/Experts (vorhandene Datei wird als .mq4.bak gesichert). */
export function installExpert(dataDir, name, source) {
  if (!SAFE_NAME.test(name)) throw new Error(`Ungueltiger EA-Name "${name}" (nur Buchstaben, Ziffern, _ und -).`);
  const target = path.join(dataDir, "MQL4", "Experts", `${name}.mq4`);
  let backup = null;
  if (fs.existsSync(target)) {
    const old = fs.readFileSync(target);
    if (old.equals(Buffer.from(source))) return { path: target, backup: null, unchanged: true };
    backup = `${target}.bak`;
    fs.copyFileSync(target, backup);
  }
  fs.writeFileSync(target, source);
  return { path: target, backup, unchanged: false };
}

/** Dekodiert MT4-Logdateien (ANSI oder UTF-16LE). */
export function decodeText(buf) {
  if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe) return buf.subarray(2).toString("utf16le");
  if (buf.length >= 4 && buf[1] === 0 && buf[3] === 0) return buf.toString("utf16le");
  return buf.toString("latin1");
}

export function readLog(dataDir, { kind = "experts", lines = 100, filter = "", date } = {}) {
  const dir = kind === "terminal" ? path.join(dataDir, "logs") : path.join(dataDir, "MQL4", "Logs");
  if (!fs.existsSync(dir)) return { file: null, lines: [] };
  let file;
  if (date) {
    file = path.join(dir, `${date.replace(/-/g, "")}.log`);
  } else {
    const logs = fs
      .readdirSync(dir)
      .filter((f) => /^\d{8}\.log$/.test(f))
      .sort();
    if (!logs.length) return { file: null, lines: [] };
    file = path.join(dir, logs[logs.length - 1]);
  }
  if (!fs.existsSync(file)) return { file, lines: [] };
  let all = decodeText(fs.readFileSync(file)).split(/\r?\n/).filter(Boolean);
  if (filter) {
    const f = filter.toLowerCase();
    all = all.filter((l) => l.toLowerCase().includes(f));
  }
  return { file, lines: all.slice(-lines) };
}

/** Erzeugt eine MT4-Chartvorlage (.tpl), die den angegebenen EA mit Eingaben laedt. */
export function buildTemplate({ expert, symbol, periodMinutes, inputs = {} }) {
  const inputLines = Object.entries(inputs).map(([k, v]) => {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(k)) throw new Error(`Ungueltiger Parametername "${k}"`);
    const val = typeof v === "boolean" ? (v ? "true" : "false") : String(v).replace(/[\r\n]/g, " ");
    return `${k}=${val}`;
  });
  return [
    "<chart>",
    `symbol=${symbol}`,
    `period=${periodMinutes}`,
    "leftpos=0",
    "scale=8",
    "graph=1",
    "fore=0",
    "grid=0",
    "volume=0",
    "scroll=1",
    "shift=1",
    "ohlc=1",
    "askline=1",
    "days=0",
    "descriptions=0",
    "shift_size=20",
    "fixed_pos=0",
    "window_type=3",
    "background_color=16777215",
    "foreground_color=0",
    "barup_color=0",
    "bardown_color=0",
    "bullcandle_color=16777215",
    "bearcandle_color=0",
    "chartline_color=0",
    "volumes_color=32768",
    "grid_color=12632256",
    "askline_color=17919",
    "stops_color=17919",
    "",
    "<window>",
    "height=100",
    "fixed_height=0",
    "<indicator>",
    "name=main",
    "</indicator>",
    "</window>",
    "",
    "<expert>",
    `name=${expert}`,
    "flags=343",
    "window_num=0",
    "<inputs>",
    ...inputLines,
    "</inputs>",
    "</expert>",
    "</chart>",
    "",
  ].join("\r\n");
}

export function writeTemplate(dataDir, name, content) {
  const dir = bridgeDir(dataDir);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `${name}.tpl`);
  fs.writeFileSync(file, content, "latin1");
  return file;
}
