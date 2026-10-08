//+------------------------------------------------------------------+
//|                                       D1_RSI2_Reversion_DEMO.mq4 |
//|   EXPERIMENT - RSI(2)-Rueckkehr im langfristigen Trend (D1)      |
//+------------------------------------------------------------------+
//| Umsetzung des einzigen Kandidaten aus research/ERGEBNIS.md:      |
//|   Backtest 2016-2026, 5 Paare, ECN-Kosten:                       |
//|   2016-2022 +0,045 R/Trade, 2023-2026 +0,039 R/Trade, PF 1,19     |
//|   ca. 34 Trades/Jahr ueber 5 Paare, Haltedauer ~4 Tage            |
//|   STATISTISCH NICHT SIGNIFIKANT (t < 1) - kein Beleg fuer Gewinn  |
//|                                                                  |
//| Regeln (Tageschart, abgeschlossene Kerze):                        |
//|   Long : RSI(2) < 5  und Schluss > EMA(600)                       |
//|   Short: RSI(2) > 95 und Schluss < EMA(600)                       |
//|   Einstieg zur Eroeffnung der naechsten Tageskerze                |
//|   Stop : 2 x ATR(14) des Tageschart, kein Take Profit             |
//|   Exit : Schluss ueber (Long) / unter (Short) EMA(5),             |
//|          spaetestens nach 12 Tageskerzen                          |
//|                                                                  |
//| Standardmaessig NUR auf Demokonten aktiv (InpAllowRealAccount).  |
//| Auf je einen D1-Chart: EURUSD, GBPUSD, USDJPY, USDCHF, EURGBP.   |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor"
#property version   "1.00"
#property strict
#property description "EXPERIMENT: RSI(2)-Rueckkehr im Trend auf D1. Backtest ohne signifikanten Vorteil."
#property description "Standardmaessig nur auf Demokonten aktiv."

input string InpSepGeneral       = "===== Allgemein =====";   // -----
input int    InpMagicNumber      = 270101;     // Magic Number
input string InpTradeComment     = "RSI2-D1-DEMO"; // Order-Kommentar
input bool   InpAllowRealAccount = false;      // Auf Echtgeld-Konto handeln (NICHT empfohlen)
input double InpSlippagePips     = 2.0;        // Max. Slippage (Pips)

input string InpSepRisk          = "===== Risiko ====="; // -----
input double InpRiskPercent      = 0.5;        // Risiko pro Trade in % (0 = feste Lots)
input double InpFixedLots        = 0.01;       // Feste Lots (wenn Risiko = 0)
input double InpMaxLots          = 2.0;        // Maximale Lotgroesse
input double InpCommissionPerLot = 0.0;        // Kommission pro Lot (fuer Lotberechnung)

input string InpSepRules         = "===== Regeln (wie im Backtest) ====="; // -----
input int    InpRsiPeriod        = 2;          // RSI Periode
input double InpRsiLow           = 5.0;        // Long, wenn RSI unter
input double InpRsiHigh          = 95.0;       // Short, wenn RSI ueber
input int    InpTrendEma         = 600;        // Trend-EMA (Tageskerzen)
input int    InpExitEma          = 5;          // Exit-EMA
input int    InpAtrPeriod        = 14;         // ATR Periode
input double InpSLAtrMult        = 2.0;        // Stop Loss = ATR x Faktor
input int    InpMaxBars          = 12;         // Max. Haltedauer (Tageskerzen)
input double InpMaxSpreadPips    = 3.0;        // Kein Einstieg bei Spread ueber (Pips)

datetime g_lastBar = 0;
double   g_pip     = 0.0;
int      g_slip    = 0;
string   g_status  = "";

//+------------------------------------------------------------------+
int OnInit()
{
   g_pip  = (Digits == 3 || Digits == 5) ? Point * 10.0 : Point;
   g_slip = (int)MathRound(InpSlippagePips * g_pip / Point);

   if(Period() != PERIOD_D1)
   {
      Alert("D1_RSI2_Reversion_DEMO bitte auf einem Tageschart (D1) starten.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!IsDemo() && !InpAllowRealAccount && !IsTesting())
   {
      Alert("D1_RSI2_Reversion_DEMO: Echtgeld-Konto erkannt - der EA bleibt inaktiv (experimentell, kein belegter Vorteil).");
      return INIT_FAILED;
   }
   if(Bars < InpTrendEma + 10)
      Print("Hinweis: Nur ", Bars, " Tageskerzen vorhanden, fuer EMA(", InpTrendEma, ") werden mehr benoetigt. ",
            "Historie ueber F2 (History Center) laden.");
   g_lastBar = Time[0];
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Comment(""); }

//+------------------------------------------------------------------+
void OnTick()
{
   if(Time[0] == g_lastBar)
      return;
   g_lastBar = Time[0];

   if(Bars < InpTrendEma + 10)
   {
      g_status = "Zu wenig Historie fuer EMA(" + IntegerToString(InpTrendEma) + ")";
      UpdatePanel();
      return;
   }

   double close1 = Close[1];
   double emaExit = iMA(NULL, 0, InpExitEma, 0, MODE_EMA, PRICE_CLOSE, 1);

   //--- 1. Exits (Schluss gegen EMA(5) oder Zeitlimit)
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      bool exitNow = false;
      if(OrderType() == OP_BUY  && close1 > emaExit) exitNow = true;
      if(OrderType() == OP_SELL && close1 < emaExit) exitNow = true;
      if(iBarShift(NULL, 0, OrderOpenTime()) >= InpMaxBars) exitNow = true;
      if(exitNow)
         CloseTrade(OrderTicket());
   }

   //--- 2. Einstieg
   if(CountOpen() > 0)
   {
      g_status = "Position offen";
      UpdatePanel();
      return;
   }

   double rsi  = iRSI(NULL, 0, InpRsiPeriod, PRICE_CLOSE, 1);
   double emaT = iMA(NULL, 0, InpTrendEma, 0, MODE_EMA, PRICE_CLOSE, 1);
   double atr  = iATR(NULL, 0, InpAtrPeriod, 1);

   int type = -1;
   if(rsi < InpRsiLow  && close1 > emaT) type = OP_BUY;
   if(rsi > InpRsiHigh && close1 < emaT) type = OP_SELL;

   g_status = StringFormat("Warte auf Signal (RSI %.1f, Trend %s)", rsi, close1 > emaT ? "auf" : "ab");
   if(type >= 0)
   {
      if((Ask - Bid) / g_pip > InpMaxSpreadPips)
         g_status = "Signal, aber Spread zu hoch";
      else
         OpenTrade(type, atr * InpSLAtrMult);
   }
   UpdatePanel();
}

//+------------------------------------------------------------------+
int CountOpen()
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() &&
         OrderMagicNumber() == InpMagicNumber && OrderType() <= OP_SELL)
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
      lots = risk / (slDist / ts * tv + InpCommissionPerLot);
   }
   lots = MathMin(MathFloor(lots / step) * step, MathMin(maxLot, InpMaxLots));
   if(lots < minLot)
   {
      Print("Kein Trade: Lotgroesse unter Mindestlot.");
      return 0.0;
   }
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
void OpenTrade(int type, double slDist)
{
   if(slDist <= 0) return;
   double lots = CalcLots(slDist);
   if(lots <= 0) return;

   RefreshRates();
   double price = (type == OP_BUY) ? Ask : Bid;
   int ticket = OrderSend(Symbol(), type, lots, NormalizeDouble(price, Digits), g_slip, 0, 0,
                          InpTradeComment, InpMagicNumber, 0, type == OP_BUY ? clrDodgerBlue : clrOrangeRed);
   if(ticket < 0)
   {
      Print("OrderSend fehlgeschlagen, Fehler ", GetLastError());
      return;
   }
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   double open = OrderOpenPrice();
   double sl = NormalizeDouble(type == OP_BUY ? open - slDist : open + slDist, Digits);
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
   PrintFormat("%s %.2f Lots @ %s, Stop %.1f Pips", type == OP_BUY ? "BUY" : "SELL", lots,
               DoubleToString(open, Digits), slDist / g_pip);
}

//+------------------------------------------------------------------+
void CloseTrade(int ticket)
{
   for(int a = 0; a < 3; a++)
   {
      if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() != 0) return;
      RefreshRates();
      double price = OrderType() == OP_BUY ? Bid : Ask;
      if(OrderClose(ticket, OrderLots(), NormalizeDouble(price, Digits), g_slip, clrYellow)) return;
      Print("OrderClose fehlgeschlagen, Fehler ", GetLastError());
      Sleep(500);
   }
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(IsTesting() && !IsVisualMode()) return;
   Comment("\n  D1 RSI(2)-Rueckkehr  [EXPERIMENT / DEMO]\n",
           "  -----------------------------------------\n",
           "  Status : ", g_status, "\n",
           "  Konto  : ", (IsDemo() ? "Demo" : "ECHTGELD"), "\n",
           "  Risiko : ", DoubleToString(InpRiskPercent, 2), " % pro Trade\n",
           "  Backtest: kein statistisch belegter Vorteil");
}
//+------------------------------------------------------------------+
