//+------------------------------------------------------------------+
//|                                                 ClaudeBridge.mq4 |
//|   Bruecke zwischen MetaTrader 4 und dem lokalen Claude-Connector |
//+------------------------------------------------------------------+
//| Funktionsweise:                                                  |
//|  Der Connector legt Befehlsdateien (*.cmd, key=value pro Zeile)  |
//|  in MQL4/Files/ClaudeBridge/ ab. Dieser EA liest sie per Timer,  |
//|  fuehrt sie aus und schreibt die Antwort als <id>.json zurueck.  |
//|  Zusaetzlich wird alle 2 Sekunden status.json aktualisiert.      |
//|                                                                  |
//|  Einmalig auf einen beliebigen Chart ziehen - der EA handelt     |
//|  selbst nicht, er fuehrt nur Befehle des Connectors aus.         |
//|  Trading-Befehle werden nur bei InpAllowTrading = true befolgt.  |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor"
#property version   "1.00"
#property strict
#property description "Verbindet MetaTrader 4 mit dem lokalen Claude-Connector (Claude Desktop)."
#property description "Trading-Befehle nur, wenn 'Trading ueber Claude erlauben' aktiviert ist."

input bool   InpAllowTrading = false;   // Trading ueber Claude erlauben
input double InpMaxLots      = 1.0;     // Max. Lotgroesse pro Order ueber Claude
input int    InpTimerMs      = 250;     // Abfrage-Intervall (ms)

#define BRIDGE_DIR     "ClaudeBridge"
#define BRIDGE_VERSION "1.0.0"

string   g_keys[];
string   g_vals[];
uint     g_lastStatus = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   FolderCreate(BRIDGE_DIR);
   if(!EventSetMillisecondTimer(MathMax(50, InpTimerMs)))
   {
      Print("ClaudeBridge: Timer konnte nicht gestartet werden.");
      return INIT_FAILED;
   }
   WriteStatus(true);
   Print("ClaudeBridge ", BRIDGE_VERSION, " gestartet. Datenordner: ", TerminalInfoString(TERMINAL_DATA_PATH),
         " | Trading ueber Claude: ", (InpAllowTrading ? "ERLAUBT" : "gesperrt"));
   Comment("ClaudeBridge aktiv  |  Trading ueber Claude: ", (InpAllowTrading ? "ERLAUBT" : "gesperrt"));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   WriteStatus(false);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick() {}

//+------------------------------------------------------------------+
void OnTimer()
{
   ProcessCommands();
   if(GetTickCount() - g_lastStatus >= 2000)
      WriteStatus(true);
}

//+------------------------------------------------------------------+
//| Befehlsverarbeitung                                              |
//+------------------------------------------------------------------+
void ProcessCommands()
{
   string names[];
   int    count = 0;
   string name;
   long   h = FileFindFirst(BRIDGE_DIR + "\\*.cmd", name);
   if(h == INVALID_HANDLE)
      return;
   do
   {
      ArrayResize(names, count + 1);
      names[count++] = name;
   }
   while(FileFindNext(h, name));
   FileFindClose(h);

   for(int i = 0; i < count; i++)
      HandleCommandFile(names[i]);
}

//+------------------------------------------------------------------+
void HandleCommandFile(string fileName)
{
   string path = BRIDGE_DIR + "\\" + fileName;
   string id   = StringSubstr(fileName, 0, StringLen(fileName) - 4);

   int fh = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE)
      return;   // evtl. noch in Bearbeitung - naechster Timer
   string lines[];
   int n = 0;
   while(!FileIsEnding(fh))
   {
      ArrayResize(lines, n + 1);
      lines[n++] = FileReadString(fh);
   }
   FileClose(fh);
   FileDelete(path);

   ParseParams(lines, n);
   string action = Param("action", "");
   string result;

   if(action == "ping")            result = StatusJson(true);
   else if(action == "account")    result = AccountJson();
   else if(action == "positions")  result = PositionsJson();
   else if(action == "history")    result = HistoryJson((int)StringToInteger(Param("days", "7")));
   else if(action == "quote")      result = QuoteJson(Param("symbol", Symbol()));
   else if(action == "charts")     result = ChartsJson();
   else if(action == "open")       result = DoOpen();
   else if(action == "close")      result = DoClose();
   else if(action == "modify")     result = DoModify();
   else if(action == "attach_ea")  result = DoAttach();
   else                            result = ErrorJson("Unbekannte Aktion: " + action);

   WriteResponse(id, result);
}

//+------------------------------------------------------------------+
void ParseParams(string &lines[], int n)
{
   ArrayResize(g_keys, 0);
   ArrayResize(g_vals, 0);
   int c = 0;
   for(int i = 0; i < n; i++)
   {
      int pos = StringFind(lines[i], "=");
      if(pos <= 0) continue;
      ArrayResize(g_keys, c + 1);
      ArrayResize(g_vals, c + 1);
      g_keys[c] = StringSubstr(lines[i], 0, pos);
      g_vals[c] = StringSubstr(lines[i], pos + 1);
      c++;
   }
}

//+------------------------------------------------------------------+
string Param(string key, string def)
{
   for(int i = 0; i < ArraySize(g_keys); i++)
      if(g_keys[i] == key)
         return g_vals[i];
   return def;
}

//+------------------------------------------------------------------+
void WriteResponse(string id, string json)
{
   string tmp = BRIDGE_DIR + "\\" + id + ".tmp";
   string dst = BRIDGE_DIR + "\\" + id + ".json";
   int fh = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE)
   {
      Print("ClaudeBridge: Antwort konnte nicht geschrieben werden, Fehler ", GetLastError());
      return;
   }
   FileWriteString(fh, json);
   FileClose(fh);
   if(!FileMove(tmp, 0, dst, FILE_REWRITE))
      Print("ClaudeBridge: FileMove fehlgeschlagen, Fehler ", GetLastError());
}

//+------------------------------------------------------------------+
void WriteStatus(bool running)
{
   g_lastStatus = GetTickCount();
   int fh = FileOpen(BRIDGE_DIR + "\\status.tmp", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE) return;
   FileWriteString(fh, StatusJson(running));
   FileClose(fh);
   FileMove(BRIDGE_DIR + "\\status.tmp", 0, BRIDGE_DIR + "\\status.json", FILE_REWRITE);
}

//+------------------------------------------------------------------+
//| JSON-Hilfsfunktionen                                             |
//+------------------------------------------------------------------+
string Esc(string s)
{
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\r", " ");
   StringReplace(s, "\n", " ");
   StringReplace(s, "\t", " ");
   return s;
}
string JS(string key, string val)          { return "\"" + key + "\":\"" + Esc(val) + "\""; }
string JN(string key, double val, int d)   { return "\"" + key + "\":" + DoubleToString(val, d); }
string JI(string key, long val)            { return "\"" + key + "\":" + IntegerToString(val); }
string JB(string key, bool val)            { return "\"" + key + "\":" + (val ? "true" : "false"); }
string JT(string key, datetime t)          { return JS(key, TimeToString(t, TIME_DATE | TIME_SECONDS)); }

string ErrorJson(string msg)
{
   return "{" + JB("ok", false) + "," + JS("error", msg) + "}";
}

string TypeName(int type)
{
   switch(type)
   {
      case OP_BUY:       return "buy";
      case OP_SELL:      return "sell";
      case OP_BUYLIMIT:  return "buy_limit";
      case OP_SELLLIMIT: return "sell_limit";
      case OP_BUYSTOP:   return "buy_stop";
      case OP_SELLSTOP:  return "sell_stop";
   }
   return "unknown";
}

//+------------------------------------------------------------------+
string StatusJson(bool running)
{
   return "{" + JB("ok", true) + "," + JB("running", running) + "," +
          JS("bridge_version", BRIDGE_VERSION) + "," +
          JS("data_path", TerminalInfoString(TERMINAL_DATA_PATH)) + "," +
          JS("terminal_path", TerminalInfoString(TERMINAL_PATH)) + "," +
          JI("build", TerminalInfoInteger(TERMINAL_BUILD)) + "," +
          JB("connected", IsConnected()) + "," +
          JB("terminal_trade_allowed", TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0) + "," +
          JB("bridge_trading_allowed", InpAllowTrading) + "," +
          JN("bridge_max_lots", InpMaxLots, 2) + "," +
          JI("account", AccountNumber()) + "," +
          JS("server", AccountServer()) + "," +
          JB("demo", IsDemo()) + "," +
          JT("server_time", TimeCurrent()) + "," +
          JI("gmt_unix", (long)TimeGMT()) + "}";
}

//+------------------------------------------------------------------+
string AccountJson()
{
   return "{" + JB("ok", true) + "," +
          JI("login", AccountNumber()) + "," +
          JS("name", AccountName()) + "," +
          JS("server", AccountServer()) + "," +
          JS("company", AccountCompany()) + "," +
          JS("currency", AccountCurrency()) + "," +
          JB("demo", IsDemo()) + "," +
          JI("leverage", AccountLeverage()) + "," +
          JN("balance", AccountBalance(), 2) + "," +
          JN("equity", AccountEquity(), 2) + "," +
          JN("margin", AccountMargin(), 2) + "," +
          JN("free_margin", AccountFreeMargin(), 2) + "," +
          JN("margin_level", AccountMargin() > 0 ? AccountEquity() / AccountMargin() * 100.0 : 0.0, 2) + "," +
          JN("profit", AccountProfit(), 2) + "," +
          JB("connected", IsConnected()) + "," +
          JB("terminal_trade_allowed", TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0) + "," +
          JB("bridge_trading_allowed", InpAllowTrading) + "}";
}

//+------------------------------------------------------------------+
string OrderJson()
{
   int d = (int)MarketInfo(OrderSymbol(), MODE_DIGITS);
   return "{" + JI("ticket", OrderTicket()) + "," +
          JS("symbol", OrderSymbol()) + "," +
          JS("type", TypeName(OrderType())) + "," +
          JN("lots", OrderLots(), 2) + "," +
          JN("open_price", OrderOpenPrice(), d) + "," +
          JN("sl", OrderStopLoss(), d) + "," +
          JN("tp", OrderTakeProfit(), d) + "," +
          JT("open_time", OrderOpenTime()) + "," +
          (OrderCloseTime() > 0 ? JN("close_price", OrderClosePrice(), d) + "," + JT("close_time", OrderCloseTime()) + "," : "") +
          JN("profit", OrderProfit(), 2) + "," +
          JN("swap", OrderSwap(), 2) + "," +
          JN("commission", OrderCommission(), 2) + "," +
          JI("magic", OrderMagicNumber()) + "," +
          JS("comment", OrderComment()) + "}";
}

//+------------------------------------------------------------------+
string PositionsJson()
{
   string items = "";
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(items != "") items += ",";
      items += OrderJson();
   }
   return "{" + JB("ok", true) + ",\"positions\":[" + items + "]}";
}

//+------------------------------------------------------------------+
string HistoryJson(int days)
{
   if(days <= 0) days = 7;
   datetime since = TimeCurrent() - days * 86400;
   string items = "";
   int count = 0;
   double total = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0 && count < 500; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(OrderCloseTime() < since) continue;
      if(items != "") items += ",";
      items += OrderJson();
      total += OrderProfit() + OrderSwap() + OrderCommission();
      count++;
   }
   return "{" + JB("ok", true) + "," + JI("count", count) + "," + JN("net_profit", total, 2) +
          ",\"trades\":[" + items + "]}";
}

//+------------------------------------------------------------------+
string QuoteJson(string sym)
{
   if(!SymbolSelect(sym, true))
      return ErrorJson("Symbol nicht gefunden: " + sym);
   int d = (int)MarketInfo(sym, MODE_DIGITS);
   return "{" + JB("ok", true) + "," + JS("symbol", sym) + "," +
          JN("bid", MarketInfo(sym, MODE_BID), d) + "," +
          JN("ask", MarketInfo(sym, MODE_ASK), d) + "," +
          JI("spread_points", (long)MarketInfo(sym, MODE_SPREAD)) + "," +
          JI("digits", d) + "," +
          JN("point", MarketInfo(sym, MODE_POINT), d) + "," +
          JN("min_lot", MarketInfo(sym, MODE_MINLOT), 2) + "," +
          JN("lot_step", MarketInfo(sym, MODE_LOTSTEP), 2) + "," +
          JI("stop_level_points", (long)MarketInfo(sym, MODE_STOPLEVEL)) + "," +
          JT("time", (datetime)MarketInfo(sym, MODE_TIME)) + "}";
}

//+------------------------------------------------------------------+
string ChartsJson()
{
   string items = "";
   long id = ChartFirst();
   while(id >= 0)
   {
      if(items != "") items += ",";
      items += "{" + JI("chart_id", id) + "," + JS("symbol", ChartSymbol(id)) + "," +
               JI("period", ChartPeriod(id)) + "," + JB("this_chart", id == ChartID()) + "}";
      id = ChartNext(id);
   }
   return "{" + JB("ok", true) + ",\"charts\":[" + items + "]}";
}

//+------------------------------------------------------------------+
//| Trading-Befehle                                                  |
//+------------------------------------------------------------------+
string TradingBlocked()
{
   if(!InpAllowTrading)
      return "Trading ueber Claude ist im ClaudeBridge-EA gesperrt (Eingabe 'Trading ueber Claude erlauben').";
   if(!IsTradeAllowed())
      return "Handel nicht erlaubt: AutoTrading im MT4 einschalten und 'Live-Trading erlauben' beim EA aktivieren.";
   if(IsTradeContextBusy())
      return "Trade-Kontext ist belegt, bitte erneut versuchen.";
   return "";
}

//+------------------------------------------------------------------+
string DoOpen()
{
   string blocked = TradingBlocked();
   if(blocked != "") return ErrorJson(blocked);

   string sym  = Param("symbol", Symbol());
   string side = Param("type", "");
   if(!SymbolSelect(sym, true)) return ErrorJson("Symbol nicht gefunden: " + sym);
   int type = (side == "buy") ? OP_BUY : (side == "sell") ? OP_SELL : -1;
   if(type < 0) return ErrorJson("type muss 'buy' oder 'sell' sein.");

   double lots    = StringToDouble(Param("lots", "0"));
   double minLot  = MarketInfo(sym, MODE_MINLOT);
   double lotStep = MarketInfo(sym, MODE_LOTSTEP);
   if(lotStep <= 0) lotStep = 0.01;
   lots = MathFloor(lots / lotStep + 1e-9) * lotStep;
   if(lots < minLot)    return ErrorJson("Lotgroesse unter Mindestlot " + DoubleToString(minLot, 2));
   if(lots > InpMaxLots) return ErrorJson("Lotgroesse ueber dem Bridge-Limit von " + DoubleToString(InpMaxLots, 2));

   int    digits = (int)MarketInfo(sym, MODE_DIGITS);
   double point  = MarketInfo(sym, MODE_POINT);
   double pip    = (digits == 3 || digits == 5) ? point * 10.0 : point;
   int    slip   = (int)StringToInteger(Param("slippage_points", "20"));
   int    magic  = (int)StringToInteger(Param("magic", "777000"));
   string cmt    = Param("comment", "Claude");

   RefreshRates();
   double price = (type == OP_BUY) ? MarketInfo(sym, MODE_ASK) : MarketInfo(sym, MODE_BID);
   int ticket = OrderSend(sym, type, NormalizeDouble(lots, 2), NormalizeDouble(price, digits), slip,
                          0, 0, cmt, magic, 0, (type == OP_BUY) ? clrDodgerBlue : clrOrangeRed);
   if(ticket < 0)
      return ErrorJson("OrderSend fehlgeschlagen, Fehler " + IntegerToString(GetLastError()));

   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return ErrorJson("Order eroeffnet (Ticket " + IntegerToString(ticket) + "), aber nicht auswaehlbar.");

   double open = OrderOpenPrice();
   double sl = StringToDouble(Param("sl", "0"));
   double tp = StringToDouble(Param("tp", "0"));
   double slPips = StringToDouble(Param("sl_pips", "0"));
   double tpPips = StringToDouble(Param("tp_pips", "0"));
   if(sl <= 0 && slPips > 0) sl = (type == OP_BUY) ? open - slPips * pip : open + slPips * pip;
   if(tp <= 0 && tpPips > 0) tp = (type == OP_BUY) ? open + tpPips * pip : open - tpPips * pip;

   string warn = "";
   if(sl > 0 || tp > 0)
   {
      if(!OrderModify(ticket, open, NormalizeDouble(sl, digits), NormalizeDouble(tp, digits), 0, clrNONE))
         warn = "SL/TP konnte nicht gesetzt werden, Fehler " + IntegerToString(GetLastError());
   }
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return ErrorJson("Order " + IntegerToString(ticket) + " nicht auswaehlbar.");
   return "{" + JB("ok", true) + "," + JS("warning", warn) + ",\"order\":" + OrderJson() + "}";
}

//+------------------------------------------------------------------+
bool CloseByTicket(int ticket, string &err)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() != 0)
   { err = "Offene Order " + IntegerToString(ticket) + " nicht gefunden"; return false; }

   if(OrderType() > OP_SELL)   // Pending Order
   {
      if(OrderDelete(ticket)) return true;
      err = "OrderDelete fehlgeschlagen, Fehler " + IntegerToString(GetLastError());
      return false;
   }
   RefreshRates();
   double price = (OrderType() == OP_BUY) ? MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK);
   if(OrderClose(ticket, OrderLots(), NormalizeDouble(price, (int)MarketInfo(OrderSymbol(), MODE_DIGITS)), 30, clrYellow))
      return true;
   err = "OrderClose fehlgeschlagen, Fehler " + IntegerToString(GetLastError());
   return false;
}

//+------------------------------------------------------------------+
string DoClose()
{
   string blocked = TradingBlocked();
   if(blocked != "") return ErrorJson(blocked);

   string t = Param("ticket", "");
   string err = "";
   if(t == "all")
   {
      string symFilter = Param("symbol", "");
      int closed = 0, failed = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(symFilter != "" && OrderSymbol() != symFilter) continue;
         if(CloseByTicket(OrderTicket(), err)) closed++;
         else failed++;
      }
      return "{" + JB("ok", failed == 0) + "," + JI("closed", closed) + "," + JI("failed", failed) + "," +
             JS("last_error", err) + "}";
   }

   int ticket = (int)StringToInteger(t);
   if(!CloseByTicket(ticket, err))
      return ErrorJson(err);
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
      return "{" + JB("ok", true) + "," + JI("ticket", ticket) + "}";
   return "{" + JB("ok", true) + ",\"order\":" + OrderJson() + "}";
}

//+------------------------------------------------------------------+
string DoModify()
{
   string blocked = TradingBlocked();
   if(blocked != "") return ErrorJson(blocked);

   int ticket = (int)StringToInteger(Param("ticket", "0"));
   if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() != 0)
      return ErrorJson("Offene Order " + IntegerToString(ticket) + " nicht gefunden");

   int digits = (int)MarketInfo(OrderSymbol(), MODE_DIGITS);
   double sl = StringToDouble(Param("sl", DoubleToString(OrderStopLoss(), digits)));
   double tp = StringToDouble(Param("tp", DoubleToString(OrderTakeProfit(), digits)));
   if(!OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(sl, digits), NormalizeDouble(tp, digits), 0, clrNONE))
      return ErrorJson("OrderModify fehlgeschlagen, Fehler " + IntegerToString(GetLastError()));
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return "{" + JB("ok", true) + "," + JI("ticket", ticket) + "}";
   return "{" + JB("ok", true) + ",\"order\":" + OrderJson() + "}";
}

//+------------------------------------------------------------------+
//| EA auf neuen Chart setzen (ueber eine Vorlage)                   |
//+------------------------------------------------------------------+
string DoAttach()
{
   string sym      = Param("symbol", Symbol());
   int    period   = (int)StringToInteger(Param("period", "5"));
   string tplName  = Param("template", "");
   if(tplName == "") return ErrorJson("Keine Vorlage angegeben.");
   if(!SymbolSelect(sym, true)) return ErrorJson("Symbol nicht gefunden: " + sym);

   long chart = ChartOpen(sym, period);
   if(chart <= 0)
      return ErrorJson("ChartOpen fehlgeschlagen, Fehler " + IntegerToString(GetLastError()));

   string tplPath = "\\Files\\" + BRIDGE_DIR + "\\" + tplName;
   if(!ChartApplyTemplate(chart, tplPath))
      return ErrorJson("ChartApplyTemplate fehlgeschlagen, Fehler " + IntegerToString(GetLastError()) +
                       " (Chart " + IntegerToString(chart) + " wurde geoeffnet)");

   return "{" + JB("ok", true) + "," + JI("chart_id", chart) + "," + JS("symbol", sym) + "," +
          JI("period", period) + "," + JS("template", tplPath) + "}";
}
//+------------------------------------------------------------------+
