#!/usr/bin/env node
// MCP-Server: verbindet Claude Desktop lokal mit MetaTrader 4.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  configValue,
  resolveDataDir,
  readBridgeStatus,
  listExperts,
  installExpert,
  readLog,
  buildTemplate,
  writeTemplate,
  timeframeToMinutes,
  SAFE_NAME,
} from "./mt4.js";
import { sendCommand } from "./bridge.js";
import { compileExpert, findMetaEditor, findWine } from "./compile.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const VERSION = "1.0.0";
const config = {
  dataDir: process.env.MT4_DATA_DIR,
  allowTrading: configValue(process.env.MT4_ALLOW_TRADING) === "true",
  winePath: process.env.MT4_WINE_PATH,
};
const discoveryCache = {};

// Mitgelieferte EAs: im Bundle unter ea/, im Repository unter MQL4/Experts/
const BUNDLED_DIRS = [path.join(here, "..", "ea"), path.join(here, "..", "..", "MQL4", "Experts")];
function bundledExperts() {
  const map = {};
  for (const dir of BUNDLED_DIRS) {
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      if (f.endsWith(".mq4") && !map[f.slice(0, -4)]) map[f.slice(0, -4)] = path.join(dir, f);
    }
  }
  return map;
}

function dataDir() {
  return resolveDataDir(config.dataDir, discoveryCache).dataDir;
}

const ok = (data) => ({ content: [{ type: "text", text: typeof data === "string" ? data : JSON.stringify(data, null, 2) }] });
const fail = (msg) => ({ content: [{ type: "text", text: `Fehler: ${msg}` }], isError: true });

function tool(handler) {
  return async (args) => {
    try {
      return await handler(args ?? {});
    } catch (e) {
      return fail(e?.message || String(e));
    }
  };
}

async function bridge(action, params, opts) {
  const res = await sendCommand(dataDir(), action, params, opts);
  if (res && res.ok === false) throw new Error(res.error || "Unbekannter Fehler in ClaudeBridge");
  return res;
}

function requireTrading() {
  if (!config.allowTrading) {
    throw new Error(
      "Trading ist im Connector deaktiviert. In Claude Desktop unter Einstellungen > Erweiterungen > MetaTrader 4 Connector " +
        "die Option 'Trading erlauben' aktivieren (zusaetzlich muss im ClaudeBridge-EA 'Trading ueber Claude erlauben' an sein)."
    );
  }
}

const server = new McpServer({ name: "metatrader4-connector", version: VERSION });

// ---------------------------------------------------------------- Status / Installation
server.registerTool(
  "mt4_status",
  {
    title: "MT4-Status",
    description:
      "Zeigt, welche MetaTrader-4-Installation verwendet wird (Datenordner), ob der ClaudeBridge-EA laeuft, ob MetaEditor/Wine " +
      "zum Kompilieren gefunden wurden und ob Trading erlaubt ist. Immer zuerst aufrufen.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  },
  tool(async () => {
    const r = resolveDataDir(config.dataDir, discoveryCache);
    const status = readBridgeStatus(r.dataDir);
    const editor = findMetaEditor(r.dataDir, status?.terminal_path);
    return ok({
      connector_version: VERSION,
      data_dir: r.dataDir,
      data_dir_source: r.source,
      other_installations: r.candidates.filter((c) => c !== r.dataDir),
      bridge: status
        ? { running: status.alive, last_seen_seconds_ago: status.age_seconds, ...status }
        : { running: false, hint: "ClaudeBridge noch nicht gestartet: mt4_install_ea mit name='ClaudeBridge' ausfuehren und den EA in MT4 auf einen Chart ziehen." },
      metaeditor: editor,
      wine: process.platform === "win32" ? "nicht benoetigt" : findWine(config.winePath),
      connector_trading_allowed: config.allowTrading,
      bundled_experts: Object.keys(bundledExperts()),
    });
  })
);

server.registerTool(
  "mt4_list_experts",
  {
    title: "Installierte EAs",
    description: "Listet alle Expert Advisors im MT4-Ordner MQL4/Experts mit Kompilierstatus auf.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  },
  tool(async () => ok(listExperts(dataDir())))
);

server.registerTool(
  "mt4_install_ea",
  {
    title: "EA installieren",
    description:
      "Kopiert einen Expert Advisor nach MQL4/Experts und kompiliert ihn optional. Ohne 'source' wird ein mitgelieferter EA " +
      "installiert (z. B. 'M5_TrendScalper' oder 'ClaudeBridge'). Mit 'source' wird der uebergebene MQL4-Quellcode gespeichert. " +
      "Eine vorhandene Datei wird als .mq4.bak gesichert.",
    inputSchema: {
      name: z.string().regex(SAFE_NAME).describe("Dateiname ohne .mq4, z. B. M5_TrendScalper"),
      source: z.string().optional().describe("Optional: vollstaendiger MQL4-Quellcode"),
      compile: z.boolean().default(true).describe("Nach dem Kopieren kompilieren"),
    },
  },
  tool(async ({ name, source, compile }) => {
    const dir = dataDir();
    let code = source;
    if (!code) {
      const file = bundledExperts()[name];
      if (!file) throw new Error(`Kein mitgelieferter EA "${name}". Verfuegbar: ${Object.keys(bundledExperts()).join(", ")}`);
      code = fs.readFileSync(file, "utf8");
    }
    const installed = installExpert(dir, name, code);
    const result = { installed };
    if (compile) {
      try {
        result.compile = await compileExpert(dir, name, { winePath: config.winePath, terminalPath: readBridgeStatus(dir)?.terminal_path });
      } catch (e) {
        result.compile = { success: false, error: e.message };
      }
      if (!result.compile.success) {
        result.next_step =
          "Automatisches Kompilieren hat nicht geklappt. In MT4: F4 (MetaEditor) > Datei im Navigator oeffnen > F7. " +
          "Alternativ MT4 neu starten - MT4 kompiliert neue .mq4-Dateien beim Start.";
      }
    }
    result.hint =
      name === "ClaudeBridge"
        ? "Jetzt in MT4 im Navigator (Strg+N) unter 'Expert Advisors' > Rechtsklick > Aktualisieren, dann 'ClaudeBridge' auf einen beliebigen Chart ziehen."
        : "Im MT4-Navigator unter 'Expert Advisors' > Rechtsklick > Aktualisieren. Mit mt4_attach_ea kann der EA auf einen Chart gesetzt werden.";
    return ok(result);
  })
);

server.registerTool(
  "mt4_compile_ea",
  {
    title: "EA kompilieren",
    description: "Kompiliert eine .mq4-Datei aus MQL4/Experts mit MetaEditor und liefert Fehler und Warnungen zurueck.",
    inputSchema: { name: z.string().regex(SAFE_NAME).describe("EA-Name ohne .mq4") },
  },
  tool(async ({ name }) => {
    const dir = dataDir();
    return ok(await compileExpert(dir, name, { winePath: config.winePath, terminalPath: readBridgeStatus(dir)?.terminal_path }));
  })
);

server.registerTool(
  "mt4_attach_ea",
  {
    title: "EA auf Chart starten",
    description:
      "Oeffnet in MT4 einen neuen Chart (Symbol + Zeitrahmen) und laedt den EA mit den angegebenen Eingaben ueber eine Vorlage. " +
      "Benoetigt den laufenden ClaudeBridge-EA. Der EA handelt danach selbststaendig, sofern AutoTrading in MT4 aktiv ist. " +
      "Vorher den Nutzer um Bestaetigung bitten und danach mit mt4_read_log pruefen, ob der EA geladen wurde.",
    inputSchema: {
      name: z.string().regex(SAFE_NAME).describe("EA-Name, z. B. M5_TrendScalper"),
      symbol: z.string().regex(/^[A-Za-z0-9._#\-]{2,20}$/).describe("Symbol, z. B. EURUSD"),
      timeframe: z.string().default("M5").describe("M1, M5, M15, M30, H1, H4, D1"),
      inputs: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).optional().describe("Optionale EA-Eingaben, z. B. {\"InpRiskPercent\": 0.5}"),
    },
  },
  tool(async ({ name, symbol, timeframe, inputs }) => {
    const dir = dataDir();
    const expert = listExperts(dir).find((e) => e.name === name);
    if (!expert?.compiled) throw new Error(`EA "${name}" ist nicht kompiliert (keine .ex4). Zuerst mt4_install_ea oder mt4_compile_ea ausfuehren.`);
    const periodMinutes = timeframeToMinutes(timeframe);
    const tplName = `claude_${name}_${symbol.replace(/[^A-Za-z0-9]/g, "")}_${periodMinutes}`;
    writeTemplate(dir, tplName, buildTemplate({ expert: name, symbol, periodMinutes, inputs }));
    const res = await bridge("attach_ea", { symbol, period: periodMinutes, template: `${tplName}.tpl` });
    return ok({
      ...res,
      next_step:
        "In 5-10 Sekunden mt4_read_log (kind='experts', filter=EA-Name) pruefen. Falls der EA nicht erscheint oder einen traurigen Smiley zeigt: " +
        "AutoTrading einschalten bzw. den EA manuell auf den geoeffneten Chart ziehen.",
    });
  })
);

server.registerTool(
  "mt4_read_log",
  {
    title: "MT4-Log lesen",
    description: "Liest das Experten-Log (Ausgaben der EAs) oder das Terminal-Log (Verbindung, Orders) von MetaTrader 4.",
    inputSchema: {
      kind: z.enum(["experts", "terminal"]).default("experts"),
      lines: z.number().int().min(1).max(1000).default(100),
      filter: z.string().optional().describe("Nur Zeilen, die diesen Text enthalten"),
      date: z.string().regex(/^\d{4}-?\d{2}-?\d{2}$/).optional().describe("Datum JJJJ-MM-TT, Standard: neuestes Log"),
    },
    annotations: { readOnlyHint: true },
  },
  tool(async (args) => ok(readLog(dataDir(), args)))
);

// ---------------------------------------------------------------- Kontodaten (ueber Bruecke)
server.registerTool(
  "mt4_account",
  {
    title: "Kontoinformationen",
    description: "Kontostand, Equity, Margin, Hebel, Server, Demo/Live und ob Trading erlaubt ist.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  },
  tool(async () => ok({ ...(await bridge("account")), connector_trading_allowed: config.allowTrading }))
);

server.registerTool(
  "mt4_positions",
  {
    title: "Offene Positionen",
    description: "Alle offenen Trades und Pending Orders des Kontos.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  },
  tool(async () => ok(await bridge("positions")))
);

server.registerTool(
  "mt4_history",
  {
    title: "Handelshistorie",
    description: "Geschlossene Trades der letzten X Tage inkl. Netto-Ergebnis. Nur Trades, die im MT4-Reiter 'Kontoauszug' geladen sind.",
    inputSchema: { days: z.number().int().min(1).max(365).default(7) },
    annotations: { readOnlyHint: true },
  },
  tool(async ({ days }) => ok(await bridge("history", { days })))
);

server.registerTool(
  "mt4_quote",
  {
    title: "Kurs abfragen",
    description: "Aktueller Bid/Ask, Spread, Mindestlot und Stop-Level eines Symbols.",
    inputSchema: { symbol: z.string().regex(/^[A-Za-z0-9._#\-]{2,20}$/) },
    annotations: { readOnlyHint: true },
  },
  tool(async ({ symbol }) => ok(await bridge("quote", { symbol })))
);

server.registerTool(
  "mt4_charts",
  {
    title: "Offene Charts",
    description: "Listet die in MT4 geoeffneten Charts (Symbol, Zeitrahmen in Minuten).",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  },
  tool(async () => ok(await bridge("charts")))
);

// ---------------------------------------------------------------- Trading (doppelt abgesichert)
server.registerTool(
  "mt4_open_trade",
  {
    title: "Trade eroeffnen",
    description:
      "Eroeffnet eine Market-Order (buy/sell). Nur nach ausdruecklicher Bestaetigung des Nutzers mit allen Details verwenden. " +
      "SL/TP entweder als Preis (sl/tp) oder in Pips (sl_pips/tp_pips). Ein Stop Loss wird dringend empfohlen.",
    inputSchema: {
      symbol: z.string().regex(/^[A-Za-z0-9._#\-]{2,20}$/),
      type: z.enum(["buy", "sell"]),
      lots: z.number().positive().max(100),
      sl: z.number().positive().optional(),
      tp: z.number().positive().optional(),
      sl_pips: z.number().positive().optional(),
      tp_pips: z.number().positive().optional(),
      comment: z.string().max(25).optional(),
    },
    annotations: { destructiveHint: true, openWorldHint: true },
  },
  tool(async (args) => {
    requireTrading();
    return ok(await bridge("open", { ...args, comment: args.comment || "Claude" }, { timeoutMs: 20000 }));
  })
);

server.registerTool(
  "mt4_close_trade",
  {
    title: "Trade schliessen",
    description: "Schliesst einen offenen Trade per Ticket (oder loescht eine Pending Order). ticket='all' schliesst alle (optional nur fuer ein Symbol). Nur nach Bestaetigung des Nutzers.",
    inputSchema: {
      ticket: z.union([z.number().int().positive(), z.literal("all")]),
      symbol: z.string().regex(/^[A-Za-z0-9._#\-]{2,20}$/).optional().describe("Nur bei ticket='all': auf dieses Symbol beschraenken"),
    },
    annotations: { destructiveHint: true, openWorldHint: true },
  },
  tool(async ({ ticket, symbol }) => {
    requireTrading();
    return ok(await bridge("close", { ticket, symbol }, { timeoutMs: 30000 }));
  })
);

server.registerTool(
  "mt4_modify_trade",
  {
    title: "SL/TP aendern",
    description: "Aendert Stop Loss und/oder Take Profit (als Preis) eines offenen Trades. Nur nach Bestaetigung des Nutzers.",
    inputSchema: {
      ticket: z.number().int().positive(),
      sl: z.number().min(0).optional().describe("Neuer Stop-Loss-Preis (0 = entfernen)"),
      tp: z.number().min(0).optional().describe("Neuer Take-Profit-Preis (0 = entfernen)"),
    },
    annotations: { destructiveHint: true, openWorldHint: true },
  },
  tool(async ({ ticket, sl, tp }) => {
    requireTrading();
    if (sl === undefined && tp === undefined) throw new Error("sl oder tp angeben.");
    return ok(await bridge("modify", { ticket, sl, tp }, { timeoutMs: 20000 }));
  })
);

await server.connect(new StdioServerTransport());
