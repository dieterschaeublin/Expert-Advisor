// Kompiliert einen EA mit MetaEditor (unter macOS/Linux ueber Wine, unter Windows direkt).
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFile } from "node:child_process";
import { configValue, decodeText, SAFE_NAME } from "./mt4.js";

/** Wine-Prefix (Ordner, der drive_c enthaelt) aus einem Pfad ableiten. */
export function winePrefixOf(p) {
  const idx = p.split(path.sep).indexOf("drive_c");
  if (idx < 0) return null;
  return p.split(path.sep).slice(0, idx).join(path.sep) || path.sep;
}

/** Unix-Pfad innerhalb eines Wine-Prefix in einen Windows-Pfad (C:\...) umwandeln. */
export function toWindowsPath(p) {
  const parts = p.split(path.sep);
  const idx = parts.indexOf("drive_c");
  if (idx < 0) throw new Error(`Pfad liegt nicht in einem Wine-Laufwerk C: ${p}`);
  return "C:\\" + parts.slice(idx + 1).join("\\");
}

/** Windows-Pfad (z. B. TERMINAL_PATH der Bruecke) in einen Unix-Pfad im Prefix umwandeln. */
export function fromWindowsPath(prefix, winPath) {
  const m = /^([A-Za-z]):\\(.*)$/.exec(winPath || "");
  if (!m || m[1].toUpperCase() !== "C") return null;
  return path.join(prefix, "drive_c", ...m[2].split("\\"));
}

function findFile(roots, fileName, maxDepth) {
  const queue = roots.filter((r) => r && fs.existsSync(r)).map((dir) => ({ dir, depth: 0 }));
  const lower = fileName.toLowerCase();
  while (queue.length) {
    const { dir, depth } = queue.shift();
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    const hit = entries.find((e) => e.isFile() && e.name.toLowerCase() === lower);
    if (hit) return path.join(dir, hit.name);
    if (depth >= maxDepth) continue;
    for (const e of entries) if (e.isDirectory() && !e.isSymbolicLink()) queue.push({ dir: path.join(dir, e.name), depth: depth + 1 });
  }
  return null;
}

export function findMetaEditor(dataDir, terminalPath) {
  const portable = path.join(dataDir, "metaeditor.exe");
  if (fs.existsSync(portable)) return portable;
  if (process.platform === "win32") {
    if (terminalPath && fs.existsSync(path.join(terminalPath, "metaeditor.exe"))) return path.join(terminalPath, "metaeditor.exe");
    return findFile([process.env.ProgramFiles, process.env["ProgramFiles(x86)"]], "metaeditor.exe", 3);
  }
  const prefix = winePrefixOf(dataDir);
  if (!prefix) return null;
  const fromBridge = fromWindowsPath(prefix, terminalPath);
  if (fromBridge && fs.existsSync(path.join(fromBridge, "metaeditor.exe"))) return path.join(fromBridge, "metaeditor.exe");
  const drive = path.join(prefix, "drive_c");
  return findFile([path.join(drive, "Program Files"), path.join(drive, "Program Files (x86)")], "metaeditor.exe", 3);
}

export function findWine(configured) {
  const cfg = configValue(configured);
  if (cfg) return cfg;
  const home = os.homedir();
  const fixed = [
    "/Applications/MetaTrader 4.app/Contents/SharedSupport/wine/bin/wine64",
    "/Applications/MetaTrader 4.app/Contents/SharedSupport/wine/bin/wine",
    "/opt/homebrew/bin/wine64",
    "/opt/homebrew/bin/wine",
    "/usr/local/bin/wine64",
    "/usr/local/bin/wine",
    "/usr/bin/wine",
  ];
  for (const f of fixed) if (fs.existsSync(f)) return f;
  // Wine-Bundles in beliebigen .app-Paketen (z. B. MT4-Versionen von Brokern)
  for (const appsDir of ["/Applications", path.join(home, "Applications")]) {
    let apps = [];
    try {
      apps = fs.readdirSync(appsDir).filter((a) => a.endsWith(".app"));
    } catch {
      continue;
    }
    const prioritized = apps.sort((a, b) => Number(/meta|mt4|trader/i.test(b)) - Number(/meta|mt4|trader/i.test(a)));
    for (const app of prioritized) {
      const contents = path.join(appsDir, app, "Contents");
      const hit = findFile([contents], "wine64", 6) || findFile([contents], "wine", 6);
      if (hit) return hit;
    }
  }
  return null;
}

function run(cmd, args, env, timeoutMs) {
  return new Promise((resolve) => {
    execFile(cmd, args, { env: { ...process.env, ...env }, timeout: timeoutMs }, (error, stdout, stderr) => {
      resolve({ error, stdout: String(stdout || ""), stderr: String(stderr || "") });
    });
  });
}

export async function compileExpert(dataDir, name, { winePath, terminalPath, timeoutMs = 90000 } = {}) {
  if (!SAFE_NAME.test(name)) throw new Error(`Ungueltiger EA-Name "${name}"`);
  const src = path.join(dataDir, "MQL4", "Experts", `${name}.mq4`);
  const ex4 = path.join(dataDir, "MQL4", "Experts", `${name}.ex4`);
  const logFile = path.join(dataDir, "MQL4", "Experts", `${name}.log`);
  if (!fs.existsSync(src)) throw new Error(`Quelldatei nicht gefunden: ${src}`);

  const editor = findMetaEditor(dataDir, terminalPath);
  if (!editor) {
    throw new Error("metaeditor.exe wurde nicht gefunden. Bitte die Datei in MT4 mit F4 (MetaEditor) oeffnen und F7 druecken.");
  }

  const started = Date.now();
  fs.rmSync(logFile, { force: true });

  let result;
  if (process.platform === "win32") {
    result = await run(editor, [`/compile:${src}`, "/log"], {}, timeoutMs);
  } else {
    const wine = findWine(winePath);
    if (!wine) {
      throw new Error(
        "Wine wurde nicht gefunden (wird von MT4 auf dem Mac intern genutzt). Bitte in den Connector-Einstellungen den Pfad " +
          "zu 'wine64' angeben oder in MT4 mit F4 den MetaEditor oeffnen und F7 druecken."
      );
    }
    const prefix = winePrefixOf(editor) || winePrefixOf(dataDir);
    result = await run(
      wine,
      [toWindowsPath(editor), `/compile:${toWindowsPath(src)}`, "/log"],
      { WINEPREFIX: prefix, WINEDEBUG: "-all" },
      timeoutMs
    );
  }

  const log = fs.existsSync(logFile) ? decodeText(fs.readFileSync(logFile)).split(/\r?\n/).filter(Boolean) : [];
  const summary = log.find((l) => /result|error\(s\)|errors?,/i.test(l)) || "";
  const m = /(\d+)\s+error/i.exec(summary);
  const errors = m ? Number(m[1]) : null;
  const ex4Fresh = fs.existsSync(ex4) && fs.statSync(ex4).mtimeMs >= started - 2000;

  return {
    success: ex4Fresh && (errors === null || errors === 0),
    errors,
    summary,
    ex4: ex4Fresh ? ex4 : null,
    log: log.slice(-60),
    editor,
    process_error: result.error ? String(result.error.message || result.error) : null,
  };
}
