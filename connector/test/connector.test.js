// Tests mit einem simulierten MT4-Datenordner und einer Fake-ClaudeBridge.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { findDataDirs, resolveDataDir, buildTemplate, decodeText, readLog, installExpert, bridgeDir } from "../server/mt4.js";
import { sendCommand } from "../server/bridge.js";
import { toWindowsPath, winePrefixOf, fromWindowsPath } from "../server/compile.js";

const here = path.dirname(fileURLToPath(import.meta.url));

function makeFakeMt4() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "mt4test-"));
  const dataDir = path.join(root, "net.metaquotes.wine.metatrader4", "drive_c", "Program Files (x86)", "MetaTrader 4");
  fs.mkdirSync(path.join(dataDir, "MQL4", "Experts"), { recursive: true });
  fs.mkdirSync(path.join(dataDir, "MQL4", "Logs"), { recursive: true });
  fs.mkdirSync(bridgeDir(dataDir), { recursive: true });
  return { root, dataDir };
}

/** Simuliert den ClaudeBridge-EA: liest *.cmd, antwortet mit <id>.json. */
function startFakeBridge(dataDir) {
  const dir = bridgeDir(dataDir);
  const writeStatus = () =>
    fs.writeFileSync(path.join(dir, "status.json"), JSON.stringify({ ok: true, running: true, terminal_path: "C:\\Program Files (x86)\\MetaTrader 4" }));
  writeStatus();
  const timer = setInterval(() => {
    writeStatus();
    for (const f of fs.readdirSync(dir).filter((x) => x.endsWith(".cmd"))) {
      const params = Object.fromEntries(
        fs.readFileSync(path.join(dir, f), "latin1").split(/\r?\n/).filter(Boolean).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)])
      );
      fs.rmSync(path.join(dir, f));
      const id = f.slice(0, -4);
      let res;
      if (params.action === "account") res = { ok: true, login: 123, balance: 1000.0, currency: "EUR" };
      else if (params.action === "attach_ea") res = { ok: fs.existsSync(path.join(dir, params.template)), template: params.template };
      else if (params.action === "open") res = { ok: true, echo: params };
      else res = { ok: false, error: `Unbekannte Aktion: ${params.action}` };
      fs.writeFileSync(path.join(dir, `${id}.tmp`), JSON.stringify(res));
      fs.renameSync(path.join(dir, `${id}.tmp`), path.join(dir, `${id}.json`));
    }
  }, 50);
  return () => clearInterval(timer);
}

test("findet Datenordner im Wine-Prefix und waehlt den mit aktiver Bruecke", () => {
  const { root, dataDir } = makeFakeMt4();
  const other = path.join(root, "broker", "drive_c", "MT4");
  fs.mkdirSync(path.join(other, "MQL4", "Experts"), { recursive: true });
  const found = findDataDirs([root]);
  assert.equal(found.length, 2);
  const stop = startFakeBridge(dataDir);
  try {
    const r = resolveDataDir("", { candidates: found });
    assert.equal(r.dataDir, dataDir);
    assert.equal(r.source, "aktive ClaudeBridge");
  } finally {
    stop();
  }
  assert.throws(() => resolveDataDir(path.join(root, "gibtsnicht")), /kein MT4-Datenordner/);
  assert.equal(resolveDataDir("${user_config.mt4_data_dir}", { candidates: [other] }).dataDir, other);
});

test("Befehl-Antwort-Roundtrip und Timeout-Hinweis", async () => {
  const { dataDir } = makeFakeMt4();
  const stop = startFakeBridge(dataDir);
  try {
    const res = await sendCommand(dataDir, "open", { symbol: "EURUSD", type: "buy", lots: 0.01, comment: "a=b\nc" });
    assert.equal(res.echo.symbol, "EURUSD");
    assert.equal(res.echo.comment, "a b c", "Zeilenumbrueche und = werden entschaerft");
  } finally {
    stop();
  }
  const { dataDir: dead } = makeFakeMt4();
  await assert.rejects(sendCommand(dead, "account", {}, { timeoutMs: 300 }), /noch nie gestartet/);
  assert.deepEqual(fs.readdirSync(bridgeDir(dead)), [], "nicht abgeholte Befehle werden aufgeraeumt");
});

test("Wine-Pfadumrechnung", () => {
  const p = "/Users/max/Library/Application Support/x/drive_c/Program Files (x86)/MetaTrader 4/metaeditor.exe";
  assert.equal(toWindowsPath(p), "C:\\Program Files (x86)\\MetaTrader 4\\metaeditor.exe");
  assert.equal(winePrefixOf(p), "/Users/max/Library/Application Support/x");
  assert.equal(fromWindowsPath("/pfx", "C:\\Program Files\\MT4"), "/pfx/drive_c/Program Files/MT4");
  assert.equal(fromWindowsPath("/pfx", "D:\\MT4"), null);
});

test("Vorlage, Logs und Installation", () => {
  const tpl = buildTemplate({ expert: "M5_TrendScalper", symbol: "EURUSD", periodMinutes: 5, inputs: { InpRiskPercent: 0.5, InpUseSession: false } });
  assert.match(tpl, /<expert>\r\nname=M5_TrendScalper/);
  assert.match(tpl, /InpRiskPercent=0.5\r\nInpUseSession=false/);
  assert.throws(() => buildTemplate({ expert: "X", symbol: "EURUSD", periodMinutes: 5, inputs: { "a\nb": 1 } }));

  assert.equal(decodeText(Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from("Hallo", "utf16le")])), "Hallo");

  const { dataDir } = makeFakeMt4();
  fs.writeFileSync(path.join(dataDir, "MQL4", "Logs", "20261007.log"), "alt\r\n");
  fs.writeFileSync(path.join(dataDir, "MQL4", "Logs", "20261008.log"), "a M5_TrendScalper\r\nb\r\nc M5_TrendScalper\r\n");
  assert.deepEqual(readLog(dataDir, { filter: "m5_trend" }).lines, ["a M5_TrendScalper", "c M5_TrendScalper"]);
  assert.deepEqual(readLog(dataDir, { date: "2026-10-07" }).lines, ["alt"]);

  const first = installExpert(dataDir, "Test", "v1");
  assert.equal(first.backup, null);
  assert.equal(installExpert(dataDir, "Test", "v1").unchanged, true);
  const second = installExpert(dataDir, "Test", "v2");
  assert.equal(fs.readFileSync(second.backup, "utf8"), "v1");
  assert.throws(() => installExpert(dataDir, "../boese", "x"), /Ungueltiger EA-Name/);
});

test("MCP-Server: Tools ueber stdio", async () => {
  const { dataDir } = makeFakeMt4();
  const stop = startFakeBridge(dataDir);
  const client = new Client({ name: "test", version: "1.0.0" });
  await client.connect(
    new StdioClientTransport({
      command: process.execPath,
      args: [path.join(here, "..", "server", "index.js")],
      env: { ...process.env, MT4_DATA_DIR: dataDir, MT4_ALLOW_TRADING: "false" },
    })
  );
  try {
    const names = (await client.listTools()).tools.map((t) => t.name);
    assert.ok(names.includes("mt4_install_ea") && names.includes("mt4_open_trade"));

    const status = JSON.parse((await client.callTool({ name: "mt4_status", arguments: {} })).content[0].text);
    assert.equal(status.data_dir, dataDir);
    assert.equal(status.bridge.running, true);
    assert.ok(status.bundled_experts.includes("M5_TrendScalper") && status.bundled_experts.includes("ClaudeBridge"));

    const inst = await client.callTool({ name: "mt4_install_ea", arguments: { name: "M5_TrendScalper", compile: false } });
    assert.ok(!inst.isError, inst.content[0].text);
    assert.ok(fs.existsSync(path.join(dataDir, "MQL4", "Experts", "M5_TrendScalper.mq4")));

    // ohne .ex4 kein Attach
    const att = await client.callTool({ name: "mt4_attach_ea", arguments: { name: "M5_TrendScalper", symbol: "EURUSD" } });
    assert.equal(att.isError, true);
    fs.writeFileSync(path.join(dataDir, "MQL4", "Experts", "M5_TrendScalper.ex4"), "bin");
    const att2 = await client.callTool({ name: "mt4_attach_ea", arguments: { name: "M5_TrendScalper", symbol: "EURUSD", inputs: { InpRiskPercent: 0.25 } } });
    assert.ok(!att2.isError, att2.content[0].text);
    assert.match(fs.readFileSync(path.join(bridgeDir(dataDir), "claude_M5_TrendScalper_EURUSD_5.tpl"), "latin1"), /InpRiskPercent=0.25/);

    const acc = JSON.parse((await client.callTool({ name: "mt4_account", arguments: {} })).content[0].text);
    assert.equal(acc.balance, 1000);

    const trade = await client.callTool({ name: "mt4_open_trade", arguments: { symbol: "EURUSD", type: "buy", lots: 0.01 } });
    assert.equal(trade.isError, true);
    assert.match(trade.content[0].text, /Trading ist im Connector deaktiviert/);
  } finally {
    await client.close();
    stop();
  }
});
