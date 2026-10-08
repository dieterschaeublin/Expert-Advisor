//+------------------------------------------------------------------+
//|                                               WeekendGapFill.mq4 |
//|   Wochen-Eroeffnungsluecke handeln, sobald der Spread es zulaesst |
//+------------------------------------------------------------------+
//| Hintergrund (research/ERGEBNIS.md, Bid-Daten 2016-2026):         |
//|   Luecken schliessen sich meist in der 1. Stunde - genau dann    |
//|   sind die Spreads am hoechsten. Ab der 2. Stunde war der Ansatz |
//|   negativ. Entscheidend ist also der echte Spread kurz nach der  |
//|   Eroeffnung. Dieser EA wartet auf einen guenstigen Spread und   |
//|   PROTOKOLLIERT jede Wochen-Eroeffnung (Spread minutenweise),    |
//|   damit sich auf einem ECN-Demokonto messen laesst, ob ein       |
//|   Vorteil nach Kosten uebrig bleibt.                             |
//|                                                                  |
//| Ablauf:                                                          |
//|   1. Montag-Eroeffnung: Luecke = Eroeffnung - Freitags-Schluss   |
//|   2. Luecke < MinGapAtr x Tages-ATR -> keine Aktion              |
//|   3. Bis MaxWaitMinutes warten, bis Spread+Kommission            |
//|      <= MaxCostToGap x Restluecke                                |
//|   4. Restluecke >= MinRemainingGap x Luecke -> Trade gegen Luecke |
//|      Ziel FillTarget x Restluecke, Stop StopGapMult x Luecke     |
//|   5. Zeit-Exit nach MaxHoldHours                                 |
//|                                                                  |
//| Standardmaessig nur auf Demokonten aktiv.                        |
//| Je Symbol ein Chart, Zeitrahmen egal (H1 empfohlen).             |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor"
#property version   "1.00"
#property strict
#property description "Weekend-Gap-Fill mit Spread-Waechter und Messprotokoll (CSV in MQL4/Files)."
#property description "Experiment - standardmaessig nur auf Demokonten aktiv."

input string InpSepGeneral       = "===== Allgemein =====";   // -----
input int    InpMagicNumber      = 280101;     // Magic Number
input string InpTradeComment     = "GapFill";  // Order-Kommentar
input bool   InpAllowRealAccount = false;      // Auf Echtgeld-Konto handeln (NICHT empfohlen)
input bool   InpTradeEnabled     = true;       // Handeln (false = nur messen/protokollieren)
input double InpSlippagePips     = 1.0;        // Max. Slippage (Pips)

input string InpSepRisk          = "===== Risiko & Kosten ====="; // -----
input double InpRiskPercent      = 0.5;        // Risiko pro Trade in % (inkl. Kommission)
input double InpMaxLots          = 2.0;        // Maximale Lotgroesse
input double InpCommissionPerLot = 7.0;        // Kommission pro Lot Hin+Rueck (Kontowaehrung)

input string InpSepRules         = "===== Regeln ====="; // -----
input double InpMinGapAtr        = 0.25;       // Min. Luecke (x Tages-ATR 14)
input double InpMaxCostToGap     = 0.15;       // Max. Kosten (Spread+Kommission) / Restluecke
input int    InpMaxWaitMinutes   = 60;         // Max. Wartezeit auf guenstigen Spread (Minuten)
input double InpMinRemainingGap  = 0.6;        // Min. offene Restluecke (Anteil der Luecke)
input double InpFillTarget       = 0.5;        // Ziel: Anteil der Restluecke (1.0 = Freitags-Schluss)
input double InpStopGapMult      = 2.0;        // Stop-Abstand = Luecke x Faktor
input int    InpMaxHoldHours     = 24;         // Zeit-Exit nach Stunden

input string InpSepLog           = "===== Protokoll ====="; // -----
input bool   InpWriteLog         = true;       // Messprotokoll schreiben (MQL4/Files/WeekendGap_<Symbol>.csv)

//--- Zustand der aktuellen Woche
datetime g_week        = 0;     // Beginn der bearbeiteten Woche (W1-Kerze)
datetime g_weekOpenT   = 0;     // Zeit der ersten Kerze der Woche
double   g_friClose    = 0.0;
double   g_weekOpen    = 0.0;
double   g_gap         = 0.0;   // vorzeichenbehaftet: > 0 = Luecke nach oben
double   g_atrD        = 0.0;
int      g_state       = 0;     // 0 = inaktiv, 1 = wartet, 2 = gehandelt, 3 = verworfen
int      g_lastLogMin  = -1;
double   g_minSpread   = 0.0;
double   g_pip         = 0.0;
int      g_slip        = 0;
string   g_status      = "";

//+------------------------------------------------------------------+
int OnInit()
{
   g_pip  = (Digits == 3 || Digits == 5) ? Point * 10.0 : Point;
   g_slip = (int)MathRound(InpSlippagePips * g_pip / Point);

   if(!IsDemo() && !InpAllowRealAccount && !IsTesting())
   {
      Alert("WeekendGapFill: Echtgeld-Konto erkannt - der EA bleibt inaktiv (Experiment).");
      return INIT_FAILED;
   }
   EventSetTimer(1);   // Spread auch ohne neue Ticks sekuendlich pruefen
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); Comment(""); }
void OnTick()  { Process(); }
void OnTimer() { Process(); }

//+------------------------------------------------------------------+
double CommissionPips()
{
   double tv = MarketInfo(Symbol(), MODE_TICKVALUE);
   double ts = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tv <= 0 || ts <= 0) return 0.0;
   return InpCommissionPerLot / (tv * g_pip / ts);
}

//+------------------------------------------------------------------+
void Process()
{
   RefreshRates();
   ManageOpenTrade();

   datetime week = iTime(NULL, PERIOD_W1, 0);
   if(week != g_week)
      StartWeek(week);

   if(g_state == 1)
      WaitForEntry();

   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Neue Woche: Freitags-Schluss und Eroeffnung bestimmen            |
//+------------------------------------------------------------------+
void StartWeek(datetime week)
{
   g_week = week;
   g_state = 3;
   g_lastLogMin = -1;
   g_minSpread = 1e9;

   // Erste H1-Kerze der Woche und letzte Kerze der Vorwoche suchen
   int first = -1;
   for(int i = 0; i < 300; i++)
   {
      datetime t = iTime(NULL, PERIOD_H1, i);
      if(t == 0) break;
      if(t < week) { first = i - 1; break; }
   }
   if(first < 0)
   {
      g_week = 0;   // H1-Kerze der neuen Woche noch nicht da - beim naechsten Aufruf erneut versuchen
      g_status = "Warte auf Daten der neuen Woche";
      return;
   }
   g_weekOpenT = iTime(NULL, PERIOD_H1, first);
   g_weekOpen  = iOpen(NULL, PERIOD_H1, first);
   g_friClose  = iClose(NULL, PERIOD_H1, first + 1);
   g_atrD      = iATR(NULL, PERIOD_D1, 14, 1);
   g_gap       = g_weekOpen - g_friClose;

   double gapPips = MathAbs(g_gap) / g_pip;
   double gapAtr  = (g_atrD > 0) ? MathAbs(g_gap) / g_atrD : 0.0;
   int    minutes = (int)((TimeCurrent() - g_weekOpenT) / 60);

   if(minutes > InpMaxWaitMinutes)
   {
      g_status = "EA nach dem Warte-Fenster gestartet - naechste Woche";
      return;
   }
   if(AlreadyTradedThisWeek())
   {
      g_state = 2;
      g_status = "Diese Woche bereits gehandelt";
      return;
   }

   Log("WEEK", StringFormat("%.1f;%.2f;%s;%s", gapPips, gapAtr,
       DoubleToString(g_friClose, Digits), DoubleToString(g_weekOpen, Digits)));

   if(gapAtr < InpMinGapAtr)
   {
      g_status = StringFormat("Luecke zu klein: %.1f Pips (%.2f ATR)", gapPips, gapAtr);
      Log("SKIP", "gap_too_small");
      return;
   }
   g_state = 1;
   g_status = StringFormat("Luecke %.1f Pips (%.2f ATR) - warte auf Spread", gapPips, gapAtr);
}

//+------------------------------------------------------------------+
bool AlreadyTradedThisWeek()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() &&
         OrderMagicNumber() == InpMagicNumber && OrderOpenTime() >= g_week)
         return true;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && OrderSymbol() == Symbol() &&
         OrderMagicNumber() == InpMagicNumber && OrderOpenTime() >= g_week)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Spread-Waechter: Einstieg, sobald die Kosten klein genug sind    |
//+------------------------------------------------------------------+
void WaitForEntry()
{
   int    minutes  = (int)((TimeCurrent() - g_weekOpenT) / 60);
   bool   sell     = g_gap > 0;                 // Luecke nach oben -> verkaufen
   double spread   = (Ask - Bid) / g_pip;
   double cost     = spread + CommissionPips();
   double entry    = sell ? Bid : Ask;
   double rest     = sell ? (Bid - g_friClose) : (g_friClose - Ask);   // offene Restluecke (Preis)
   double restPips = rest / g_pip;
   double gapPips  = MathAbs(g_gap) / g_pip;
   g_minSpread = MathMin(g_minSpread, spread);

   if(minutes != g_lastLogMin)   // Messprotokoll einmal pro Minute
   {
      g_lastLogMin = minutes;
      Log("MIN", StringFormat("%d;%.2f;%.2f;%.1f", minutes, spread, cost, restPips));
   }

   if(minutes > InpMaxWaitMinutes)
   {
      g_state = 3;
      g_status = StringFormat("Kein guenstiger Spread in %d Min. (min. %.1f Pips)", InpMaxWaitMinutes, g_minSpread);
      Log("SKIP", "spread_never_ok");
      return;
   }
   if(restPips < InpMinRemainingGap * gapPips)
   {
      g_state = 3;
      g_status = StringFormat("Luecke schon zu weit geschlossen (Rest %.1f von %.1f Pips)", restPips, gapPips);
      Log("SKIP", "gap_already_filled");
      return;
   }
   g_status = StringFormat("Warte: Kosten %.1f Pips, erlaubt %.1f (Rest %.1f Pips)",
                           cost, InpMaxCostToGap * restPips, restPips);
   if(cost > InpMaxCostToGap * restPips)
      return;

   //--- Einstiegsbedingung erfuellt
   double stopDist = InpStopGapMult * MathAbs(g_gap);
   double sl = sell ? entry + stopDist : entry - stopDist;
   double tp = sell ? entry - InpFillTarget * rest : entry + InpFillTarget * rest;
   Log("SIGNAL", StringFormat("%d;%.2f;%.1f;%s;%s;%s", minutes, spread, restPips,
       DoubleToString(entry, Digits), DoubleToString(sl, Digits), DoubleToString(tp, Digits)));

   if(!InpTradeEnabled)
   {
      g_state = 2;
      g_status = "Signal (nur Messung, Handel aus)";
      return;
   }
   if(OpenTrade(sell ? OP_SELL : OP_BUY, stopDist, sl, tp))
      g_state = 2;
   else
      g_state = 3;
}

//+------------------------------------------------------------------+
bool OpenTrade(int type, double stopDist, double sl, double tp)
{
   double tv = MarketInfo(Symbol(), MODE_TICKVALUE);
   double ts = MarketInfo(Symbol(), MODE_TICKSIZE);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(tv <= 0 || ts <= 0 || stopDist <= 0) return false;
   if(step <= 0) step = 0.01;
   double risk = MathMin(AccountBalance(), AccountEquity()) * InpRiskPercent / 100.0;
   double lots = risk / (stopDist / ts * tv + InpCommissionPerLot);
   lots = MathMin(MathFloor(lots / step) * step, MathMin(MarketInfo(Symbol(), MODE_MAXLOT), InpMaxLots));
   if(lots < MarketInfo(Symbol(), MODE_MINLOT))
   {
      g_status = "Lotgroesse unter Mindestlot";
      return false;
   }

   double price = (type == OP_BUY) ? Ask : Bid;
   int ticket = OrderSend(Symbol(), type, NormalizeDouble(lots, 2), NormalizeDouble(price, Digits), g_slip, 0, 0,
                          InpTradeComment, InpMagicNumber, 0, type == OP_BUY ? clrDodgerBlue : clrOrangeRed);
   if(ticket < 0)
   {
      Print("OrderSend fehlgeschlagen, Fehler ", GetLastError());
      return false;
   }
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;

   // SL/TP relativ zum tatsaechlichen Fuellkurs verschieben
   double shift = OrderOpenPrice() - price;
   sl = NormalizeDouble(sl + shift, Digits);
   tp = NormalizeDouble(tp + shift, Digits);
   bool ok = false;
   for(int a = 0; a < 5 && !ok; a++)
   {
      ok = OrderModify(ticket, OrderOpenPrice(), sl, tp, 0, clrNONE);
      if(!ok) { Print("SL/TP setzen fehlgeschlagen, Fehler ", GetLastError()); Sleep(300); RefreshRates(); }
   }
   if(!ok)
   {
      Print("ACHTUNG: SL/TP nicht gesetzt - Trade wird geschlossen.");
      CloseTrade(ticket, "no_sl");
      return false;
   }
   Log("OPEN", StringFormat("%d;%s;%.2f;%s", ticket, type == OP_BUY ? "buy" : "sell", lots,
       DoubleToString(OrderOpenPrice(), Digits)));
   g_status = "Trade offen";
   return true;
}

//+------------------------------------------------------------------+
void ManageOpenTrade()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber || OrderType() > OP_SELL) continue;
      if(TimeCurrent() - OrderOpenTime() >= InpMaxHoldHours * 3600)
         CloseTrade(OrderTicket(), "time_exit");
   }
}

//+------------------------------------------------------------------+
void CloseTrade(int ticket, string reason)
{
   for(int a = 0; a < 3; a++)
   {
      if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() != 0) return;
      RefreshRates();
      double price = OrderType() == OP_BUY ? Bid : Ask;
      if(OrderClose(ticket, OrderLots(), NormalizeDouble(price, Digits), g_slip, clrYellow))
      {
         Log("CLOSE", StringFormat("%d;%s", ticket, reason));
         return;
      }
      Print("OrderClose fehlgeschlagen, Fehler ", GetLastError());
      Sleep(300);
   }
}

//+------------------------------------------------------------------+
//| CSV-Protokoll: Zeit;Typ;Daten...                                 |
//|  WEEK  : gap_pips;gap_atr;fri_close;week_open                    |
//|  MIN   : minute;spread;cost;rest_gap_pips                        |
//|  SIGNAL: minute;spread;rest_gap;entry;sl;tp                      |
//|  OPEN/CLOSE/SKIP                                                 |
//+------------------------------------------------------------------+
void Log(string type, string data)
{
   if(!InpWriteLog || IsOptimization()) return;
   string file = "WeekendGap_" + Symbol() + ".csv";
   int fh = FileOpen(file, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);
   FileWriteString(fh, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + ";" + type + ";" + data + "\r\n");
   FileClose(fh);
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(IsTesting() && !IsVisualMode()) return;
   Comment("\n  Weekend-Gap-Fill  [EXPERIMENT]\n",
           "  ---------------------------------\n",
           "  Status   : ", g_status, "\n",
           "  Spread   : ", DoubleToString((Ask - Bid) / g_pip, 1), " Pips + Kommission ",
           DoubleToString(CommissionPips(), 1), " Pips\n",
           "  Luecke   : ", DoubleToString(g_gap / g_pip, 1), " Pips  (Fr-Schluss ", DoubleToString(g_friClose, Digits), ")\n",
           "  Konto    : ", (IsDemo() ? "Demo" : "ECHTGELD"), "  |  Handel: ", (InpTradeEnabled ? "an" : "nur Messung"));
}
//+------------------------------------------------------------------+
