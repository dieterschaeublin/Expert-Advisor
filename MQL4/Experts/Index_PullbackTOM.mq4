//+------------------------------------------------------------------+
//|                                            Index_PullbackTOM.mq4 |
//|   Aktienindex-CFDs (US500, NAS100, GER40 ...), Tageschart, Long  |
//+------------------------------------------------------------------+
//| Idee: Nicht Devisen, sondern Aktienindizes handeln. Indizes      |
//| haben eine langfristige Aufwaertsdrift, kurzfristige Einbrueche  |
//| werden meist schnell aufgeholt, und zum Monatswechsel fliessen   |
//| regelmaessig neue Gelder in den Markt. Zwei Module, nur Long:    |
//|                                                                  |
//| 1. Ruecksetzer (Connors RSI(2)):                                 |
//|    Schluss > SMA(200) und RSI(2) < 10 -> Kauf zur Eroeffnung     |
//|    Ausstieg: Schluss > SMA(5), spaetestens nach 10 Tageskerzen   |
//| 2. Monatswechsel (Turn of the Month):                            |
//|    Kauf zur Eroeffnung des letzten Handelstags im Monat,         |
//|    Verkauf zur Eroeffnung des 4. Handelstags im neuen Monat      |
//|                                                                  |
//| Stop: 3 x ATR(14) als Notbremse, Lotgroesse ueber Risiko/Stop.   |
//| Pruefung mit research/indices.py auf dem eigenen MT4-Export.     |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor"
#property version   "1.00"
#property strict
#property description "Aktienindex-CFDs D1, nur Long: RSI(2)-Ruecksetzer im Aufwaertstrend + Monatswechsel."

input string InpSepGeneral       = "===== Allgemein =====";   // -----
input int    InpMagicNumber      = 280100;     // Magic Number (Ruecksetzer = +0, Monatswechsel = +1)
input string InpTradeComment     = "IdxPbTOM"; // Order-Kommentar
input int    InpSlippagePoints   = 50;         // Max. Slippage (Points)

input string InpSepRisk          = "===== Risiko ====="; // -----
input double InpRiskPercent      = 1.0;        // Risiko bis Notstop in % je Modul (0 = feste Lots)
input double InpFixedLots        = 0.1;        // Feste Lots (wenn Risiko = 0)
input double InpMaxLots          = 10.0;       // Maximale Lotgroesse
input double InpMaxSpreadPoints  = 0;          // Kein Einstieg bei Spread ueber (Points, 0 = aus)

input string InpSepPb            = "===== Modul 1: RSI(2)-Ruecksetzer ====="; // -----
input bool   InpUsePullback      = true;       // Modul aktiv
input int    InpRsiPeriod        = 2;          // RSI Periode
input double InpRsiLow           = 10.0;       // Kauf, wenn RSI unter
input int    InpTrendSma         = 200;        // Trend-SMA (Tageskerzen)
input int    InpExitSma          = 5;          // Ausstieg, wenn Schluss ueber SMA
input int    InpPbMaxBars        = 10;         // Max. Haltedauer (Tageskerzen)

input string InpSepTom           = "===== Modul 2: Monatswechsel ====="; // -----
input bool   InpUseTom           = true;       // Modul aktiv
input int    InpTomExitDay       = 4;          // Verkauf zur Eroeffnung von Handelstag Nr.
input bool   InpTomNeedTrend     = false;      // Nur wenn Schluss > Trend-SMA

input string InpSepStop          = "===== Notstop ====="; // -----
input int    InpAtrPeriod        = 14;         // ATR Periode
input double InpSLAtrMult        = 3.0;        // Stop = ATR x Faktor

datetime g_lastBar = 0;
string   g_status  = "";

//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_D1)
   {
      Alert("Index_PullbackTOM bitte auf einem Tageschart (D1) starten.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(Bars < InpTrendSma + 10)
      Print("Hinweis: Nur ", Bars, " Tageskerzen vorhanden, fuer SMA(", InpTrendSma, ") werden mehr benoetigt.");
   g_lastBar = Time[0];
   UpdatePanel();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Comment(""); }

//+------------------------------------------------------------------+
void OnTick()
{
   if(Time[0] == g_lastBar)
      return;
   // Sonntagskerzen einiger Broker ueberspringen (wie im Backtest)
   if(TimeDayOfWeek(Time[0]) == 0 || TimeDayOfWeek(Time[0]) == 6)
      return;
   g_lastBar = Time[0];

   if(Bars < InpTrendSma + 10)
   {
      g_status = "Zu wenig Historie";
      UpdatePanel();
      return;
   }

   double close1 = Close[1];
   double smaT   = iMA(NULL, 0, InpTrendSma, 0, MODE_SMA, PRICE_CLOSE, 1);
   double smaX   = iMA(NULL, 0, InpExitSma,  0, MODE_SMA, PRICE_CLOSE, 1);
   double rsi    = iRSI(NULL, 0, InpRsiPeriod, PRICE_CLOSE, 1);
   double atr    = iATR(NULL, 0, InpAtrPeriod, 1);
   int    dayNo  = TradingDayOfMonth();
   bool   lastDay = IsLastTradingDay(Time[0]);

   int magicPb  = InpMagicNumber;
   int magicTom = InpMagicNumber + 1;

   //--- Ausstiege zur Eroeffnung der neuen Tageskerze
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderType() != OP_BUY) continue;
      int held = iBarShift(NULL, 0, OrderOpenTime());
      if(OrderMagicNumber() == magicPb && (close1 > smaX || held >= InpPbMaxBars))
         CloseTrade(OrderTicket());
      else if(OrderMagicNumber() == magicTom && !lastDay && (dayNo >= InpTomExitDay || held >= 6))
         CloseTrade(OrderTicket());
   }

   //--- Modul 1: Ruecksetzer
   g_status = StringFormat("RSI(2) %.1f | Trend %s | Handelstag %d%s", rsi,
                           close1 > smaT ? "auf" : "ab", dayNo, lastDay ? " (letzter)" : "");
   if(InpUsePullback && CountOpen(magicPb) == 0 && close1 > smaT && rsi < InpRsiLow)
      OpenLong(magicPb, atr * InpSLAtrMult, "PB");

   //--- Modul 2: Monatswechsel
   if(InpUseTom && lastDay && CountOpen(magicTom) == 0 && (!InpTomNeedTrend || close1 > smaT))
      OpenLong(magicTom, atr * InpSLAtrMult, "TOM");

   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Handelstag im Monat fuer die aktuelle Kerze (1 = erster)         |
//+------------------------------------------------------------------+
int TradingDayOfMonth()
{
   int m = TimeMonth(Time[0]);
   int n = 0;
   for(int i = 0; i < Bars && TimeMonth(Time[i]) == m; i++)
   {
      int dow = TimeDayOfWeek(Time[i]);
      if(dow != 0 && dow != 6) n++;
   }
   return n;
}

//+------------------------------------------------------------------+
//| Letzter Handelstag: naechster Werktag liegt im neuen Monat       |
//| (Feiertage werden nicht beruecksichtigt - wie im Backtest)       |
//+------------------------------------------------------------------+
bool IsLastTradingDay(datetime t)
{
   datetime nxt = t + 86400;
   while(TimeDayOfWeek(nxt) == 0 || TimeDayOfWeek(nxt) == 6)
      nxt += 86400;
   return TimeMonth(nxt) != TimeMonth(t);
}

//+------------------------------------------------------------------+
int CountOpen(int magic)
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() &&
         OrderMagicNumber() == magic && OrderType() <= OP_SELL)
         n++;
   return n;
}

//+------------------------------------------------------------------+
double CalcLots(double slDist)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step   = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0) step = 0.01;
   double lots = InpFixedLots;
   if(InpRiskPercent > 0)
   {
      double tv = MarketInfo(Symbol(), MODE_TICKVALUE);
      double ts = MarketInfo(Symbol(), MODE_TICKSIZE);
      if(tv <= 0 || ts <= 0) return 0.0;
      double risk = MathMin(AccountBalance(), AccountEquity()) * InpRiskPercent / 100.0;
      lots = risk / (slDist / ts * tv);
   }
   lots = MathMin(MathFloor(lots / step) * step, MathMin(maxLot, InpMaxLots));
   if(lots < minLot)
   {
      Print("Kein Trade: Lotgroesse unter Mindestlot (", DoubleToString(minLot, 2), ").");
      return 0.0;
   }
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
void OpenLong(int magic, double slDist, string tag)
{
   if(slDist <= 0) return;
   RefreshRates();
   if(InpMaxSpreadPoints > 0 && (Ask - Bid) / Point > InpMaxSpreadPoints)
   {
      g_status = tag + "-Signal, aber Spread zu hoch";
      return;
   }
   double lots = CalcLots(slDist);
   if(lots <= 0) return;

   int ticket = OrderSend(Symbol(), OP_BUY, lots, NormalizeDouble(Ask, Digits), InpSlippagePoints, 0, 0,
                          InpTradeComment + "-" + tag, magic, 0, clrDodgerBlue);
   if(ticket < 0)
   {
      Print(tag, ": OrderSend fehlgeschlagen, Fehler ", GetLastError());
      return;
   }
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   double open = OrderOpenPrice();
   double sl = NormalizeDouble(open - slDist, Digits);
   bool ok = false;
   for(int a = 0; a < 5 && !ok; a++)
   {
      ok = OrderModify(ticket, open, sl, 0, 0, clrNONE);
      if(!ok) { Print("Stop setzen fehlgeschlagen, Fehler ", GetLastError()); Sleep(500); }
   }
   if(!ok)
   {
      Print("ACHTUNG: Stop konnte nicht gesetzt werden - Trade wird geschlossen.");
      CloseTrade(ticket);
      return;
   }
   PrintFormat("%s: BUY %.2f Lots @ %s, Notstop %s", tag, lots, DoubleToString(open, Digits),
               DoubleToString(sl, Digits));
}

//+------------------------------------------------------------------+
void CloseTrade(int ticket)
{
   for(int a = 0; a < 3; a++)
   {
      if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() != 0) return;
      RefreshRates();
      if(OrderClose(ticket, OrderLots(), NormalizeDouble(Bid, Digits), InpSlippagePoints, clrYellow)) return;
      Print("OrderClose fehlgeschlagen, Fehler ", GetLastError());
      Sleep(500);
   }
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(IsTesting() && !IsVisualMode()) return;
   Comment("\n  Index Ruecksetzer + Monatswechsel (Long)\n",
           "  -----------------------------------------\n",
           "  Status : ", g_status, "\n",
           "  Module : ", (InpUsePullback ? "RSI(2) " : ""), (InpUseTom ? "Monatswechsel" : ""), "\n",
           "  Offen  : PB ", CountOpen(InpMagicNumber), " | TOM ", CountOpen(InpMagicNumber + 1), "\n",
           "  Risiko : ", DoubleToString(InpRiskPercent, 2), " % je Modul bis Notstop");
}
//+------------------------------------------------------------------+
