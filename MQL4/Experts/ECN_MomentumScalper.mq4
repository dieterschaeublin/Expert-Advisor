//+------------------------------------------------------------------+
//|                                          ECN_MomentumScalper.mq4 |
//|        Momentum-Breakout-Scalper fuer ECN-/Raw-Spread-Konten     |
//+------------------------------------------------------------------+
//| Idee: Nicht gegen kurzfristige Bewegungen handeln (Pullback),     |
//| sondern mit ihnen: Ausbruch aus der Spanne der letzten N Kerzen   |
//| in Richtung des H1-Trends, nur bei zunehmender Volatilitaet.      |
//|                                                                  |
//|  1. Trend     : H1 Kurs ueber/unter EMA 50 + M5 EMA 100           |
//|  2. Setup     : Donchian-Kanal (20 Kerzen) - frischer Ausbruch    |
//|  3. Momentum  : Ausbruchskerze mit Koerper >= 0,5 x ATR,          |
//|                 Schluss im oberen/unteren Drittel der Kerze       |
//|  4. Volatil.  : ATR(14) >= ATR(100) (Markt kommt in Bewegung)     |
//|  5. Kosten    : Spread + Kommission muessen klein gegen den SL    |
//|                 sein; Kommission fliesst in die Lotgroesse ein    |
//|  6. Exits     : SL 1,5 x ATR, TP 1,5 R, Break-Even ab 1 R inkl.   |
//|                 Kosten, optional Trailing, Zeit-Exit              |
//|  7. Schutz    : Sperre nach Verlust in gleicher Richtung,         |
//|                 Tagesverlust-Limit, Verlustserie-Pause, Sessions  |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor"
#property version   "1.00"
#property strict
#property description "Momentum-Breakout-Scalper fuer ECN-Konten (M5): Donchian-Ausbruch im H1-Trend,"
#property description "kostenbewusste Lotgroesse inkl. Kommission, R-basierte Exits und Kontoschutz."

//--- Allgemein
input string           InpSepGeneral       = "===== Allgemein =====";   // -----
input int              InpMagicNumber      = 260801;     // Magic Number
input string           InpTradeComment     = "ECNMomentum"; // Order-Kommentar
input double           InpSlippagePips     = 0.5;        // Max. Slippage (Pips)

//--- Kosten (ECN)
input string           InpSepCost          = "===== Kosten (ECN) ====="; // -----
input double           InpCommissionPerLot = 7.0;        // Kommission pro Lot (Hin+Rueck, Kontowaehrung)
input double           InpMaxSpreadPips    = 1.0;        // Maximaler Spread (Pips)
input double           InpMaxCostToSL      = 0.15;       // Max. Kosten (Spread+Kommission) im Verhaeltnis zum SL

//--- Money Management
input string           InpSepMM            = "===== Money Management ====="; // -----
input double           InpRiskPercent      = 0.5;        // Risiko pro Trade in % (inkl. Kommission, 0 = feste Lots)
input double           InpFixedLots        = 0.01;       // Feste Lotgroesse (wenn Risiko = 0)
input double           InpMaxLots          = 5.0;        // Maximale Lotgroesse
input int              InpMaxOpenTrades    = 1;          // Max. gleichzeitige Trades (dieses Symbol)
input int              InpMaxTradesPerDay  = 12;         // Max. Trades pro Tag

//--- Trend
input string           InpSepTrend         = "===== Trend ====="; // -----
input bool             InpUseHTFFilter     = true;       // H1-Trendfilter
input ENUM_TIMEFRAMES  InpHTF              = PERIOD_H1;  // Hoeherer Zeitrahmen
input int              InpHTFEma           = 50;         // EMA hoeherer Zeitrahmen
input int              InpTrendEma         = 100;        // EMA auf dem Chart-Zeitrahmen (0 = aus)

//--- Einstieg
input string           InpSepEntry         = "===== Einstieg (Breakout) ====="; // -----
input int              InpChannelBars      = 20;         // Donchian-Kanal: Anzahl Kerzen
input double           InpMinBodyAtr       = 0.5;        // Min. Kerzenkoerper der Ausbruchskerze (x ATR)
input double           InpCloseInRange     = 0.66;       // Schluss im oberen/unteren Anteil der Kerze (0.5-1.0)
input bool             InpUseAtrExpansion  = true;       // Nur bei steigender Volatilitaet
input int              InpAtrSlowPeriod    = 100;        // Langsame ATR fuer Volatilitaetsvergleich
input double           InpAtrExpansion     = 1.0;        // ATR(14) >= ATR(langsam) x Faktor

//--- Exits
input string           InpSepExit          = "===== Exits ====="; // -----
input int              InpAtrPeriod        = 14;         // ATR Periode
input double           InpSLAtrMult        = 1.5;        // Stop Loss = ATR x Faktor
input double           InpMinSLPips        = 6.0;        // Minimaler Stop Loss (Pips)
input double           InpMaxSLPips        = 20.0;       // Maximaler Stop Loss (Pips) - sonst kein Trade
input double           InpTPRatio          = 1.5;        // Take Profit in R (Vielfaches des SL)
input bool             InpUseBreakEven     = true;       // Break-Even aktivieren
input double           InpBETriggerR       = 1.0;        // Break-Even ab Gewinn in R
input double           InpBEExtraPips      = 0.3;        // Break-Even: zusaetzlich zu den Kosten gesicherte Pips
input bool             InpUseTrailing      = false;      // ATR-Trailing-Stop aktivieren
input double           InpTrailStartR      = 1.0;        // Trailing ab Gewinn in R
input double           InpTrailAtrMult     = 1.0;        // Trailing-Abstand = ATR x Faktor
input int              InpMaxBarsInTrade   = 36;         // Trade nach X Bars schliessen (0 = aus)

//--- Filter
input string           InpSepFilter        = "===== Filter ====="; // -----
input double           InpMinAtrPips       = 2.5;        // Minimale ATR (Pips)
input double           InpMaxAtrPips       = 20.0;       // Maximale ATR (Pips)
input bool             InpUseSession       = true;       // Handelszeiten-Filter (Server-Zeit)
input int              InpSessionStartHour = 9;          // Handelsbeginn (Stunde)
input int              InpSessionEndHour   = 19;         // Handelsende (Stunde)
input int              InpLossCooldownBars = 12;         // Nach Verlust: X Bars keine Trades in gleiche Richtung
input int              InpFridayStopHour   = 18;         // Freitag: keine neuen Trades ab (Stunde)
input bool             InpFridayCloseAll   = true;       // Freitag: alle Trades schliessen
input int              InpFridayCloseHour  = 21;         // Freitag: Schliessen ab (Stunde)

//--- Kontoschutz
input string           InpSepProtect       = "===== Kontoschutz ====="; // -----
input double           InpDailyLossPct     = 2.0;        // Tagesverlust-Limit in % (0 = aus)
input double           InpDailyProfitPct   = 0.0;        // Tagesgewinn-Ziel in % (0 = aus)
input int              InpMaxConsecLosses  = 4;          // Pause nach X Verlusten in Folge (0 = aus)
input int              InpPauseMinutes     = 120;        // Pausendauer (Minuten)
input bool             InpShowPanel        = true;       // Info-Panel im Chart anzeigen

//--- globale Variablen
double   g_pip      = 0.0;
int      g_slippage = 0;
datetime g_lastBar  = 0;
string   g_status   = "";

//+------------------------------------------------------------------+
int OnInit()
{
   g_pip      = (Digits == 3 || Digits == 5) ? Point * 10.0 : Point;
   g_slippage = (int)MathRound(InpSlippagePips * g_pip / Point);

   if(InpChannelBars < 5 || InpSLAtrMult <= 0 || InpTPRatio <= 0)
   {
      Print("Fehler: Ungueltige Parameter (Kanal >= 5, SL/TP > 0).");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(Period() != PERIOD_M5)
      Print("Hinweis: Der EA ist fuer M5 ausgelegt. Aktueller Zeitrahmen: M", Period());

   g_lastBar = Time[0];
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   int need = MathMax(MathMax(InpTrendEma, InpAtrSlowPeriod), InpChannelBars) + 10;
   if(Bars < need)
      return;

   double atr = iATR(NULL, 0, InpAtrPeriod, 1);

   ManageOpenTrades(atr);

   if(InpFridayCloseAll && DayOfWeek() == 5 && Hour() >= InpFridayCloseHour)
   {
      CloseAllTrades("Wochenend-Schliessung");
      UpdatePanel(atr);
      return;
   }

   if(!IsNewBar() || !CanOpenNewTrade(atr))
   {
      UpdatePanel(atr);
      return;
   }

   int signal = GetSignal(atr);
   if(signal == OP_BUY || signal == OP_SELL)
   {
      if(InDirectionCooldown(signal))
         g_status = "Sperre nach Verlust in gleicher Richtung";
      else
         OpenTrade(signal, atr);
   }

   UpdatePanel(atr);
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   if(Time[0] != g_lastBar)
   {
      g_lastBar = Time[0];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Kosten pro Lot und Pip                                           |
//+------------------------------------------------------------------+
double PipValuePerLot()
{
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickValue <= 0 || tickSize <= 0) return 0.0;
   return tickValue * g_pip / tickSize;
}

double CommissionPips()
{
   double pv = PipValuePerLot();
   return (pv > 0) ? InpCommissionPerLot / pv : 0.0;
}

double TotalCostPips()
{
   return (Ask - Bid) / g_pip + CommissionPips();
}

//+------------------------------------------------------------------+
//| Signal: frischer Donchian-Ausbruch in Trendrichtung              |
//+------------------------------------------------------------------+
int GetSignal(double atr)
{
   if(atr <= 0) return -1;

   //--- Trendrichtung
   bool trendUp = true, trendDown = true;
   if(InpUseHTFFilter)
   {
      double htfEma   = iMA(NULL, InpHTF, InpHTFEma, 0, MODE_EMA, PRICE_CLOSE, 1);
      double htfClose = iClose(NULL, InpHTF, 1);
      if(htfEma <= 0 || htfClose <= 0) return -1;
      trendUp   = htfClose > htfEma;
      trendDown = htfClose < htfEma;
   }
   if(InpTrendEma > 0)
   {
      double ema = iMA(NULL, 0, InpTrendEma, 0, MODE_EMA, PRICE_CLOSE, 1);
      trendUp   = trendUp   && Close[1] > ema;
      trendDown = trendDown && Close[1] < ema;
   }
   if(!trendUp && !trendDown) return -1;

   //--- Volatilitaet nimmt zu
   if(InpUseAtrExpansion)
   {
      double atrSlow = iATR(NULL, 0, InpAtrSlowPeriod, 1);
      if(atr < atrSlow * InpAtrExpansion) return -1;
   }

   //--- Kanal aus den Kerzen VOR der Signalkerze (Bars 2 .. N+1)
   double hh = High[iHighest(NULL, 0, MODE_HIGH, InpChannelBars, 2)];
   double ll = Low[iLowest(NULL, 0, MODE_LOW, InpChannelBars, 2)];

   double range = High[1] - Low[1];
   double body  = MathAbs(Close[1] - Open[1]);
   if(range <= 0 || body < InpMinBodyAtr * atr) return -1;
   double closePos = (Close[1] - Low[1]) / range;   // 0 = Tief, 1 = Hoch

   if(trendUp && Close[1] > hh && Close[2] <= hh && Close[1] > Open[1] && closePos >= InpCloseInRange)
      return OP_BUY;
   if(trendDown && Close[1] < ll && Close[2] >= ll && Close[1] < Open[1] && closePos <= 1.0 - InpCloseInRange)
      return OP_SELL;
   return -1;
}

//+------------------------------------------------------------------+
//| Letzter Trade in dieser Richtung war ein Verlust vor < X Bars?   |
//+------------------------------------------------------------------+
bool InDirectionCooldown(int type)
{
   if(InpLossCooldownBars <= 0) return false;
   datetime latest = 0;
   double   result = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != type) continue;
      if(OrderCloseTime() > latest)
      {
         latest = OrderCloseTime();
         result = OrderProfit() + OrderSwap() + OrderCommission();
      }
   }
   if(latest == 0 || result >= 0) return false;
   return iBarShift(NULL, 0, latest) < InpLossCooldownBars;
}

//+------------------------------------------------------------------+
bool CanOpenNewTrade(double atr)
{
   if(!IsTradeAllowed() || IsTradeContextBusy())
   { g_status = "Handel nicht erlaubt / Kontext belegt"; return false; }

   if(CountOpenTrades() >= InpMaxOpenTrades)
   { g_status = "Max. offene Trades erreicht"; return false; }

   if(CountTradesToday() >= InpMaxTradesPerDay)
   { g_status = "Max. Trades pro Tag erreicht"; return false; }

   double spreadPips = (Ask - Bid) / g_pip;
   if(spreadPips > InpMaxSpreadPips)
   { g_status = StringFormat("Spread zu hoch (%.1f Pips)", spreadPips); return false; }

   double atrPips = atr / g_pip;
   if(atrPips < InpMinAtrPips || atrPips > InpMaxAtrPips)
   { g_status = StringFormat("ATR ausserhalb Bereich (%.1f Pips)", atrPips); return false; }

   if(InpUseSession && !InSession())
   { g_status = "Ausserhalb der Handelszeit"; return false; }

   if(DayOfWeek() == 5 && Hour() >= InpFridayStopHour)
   { g_status = "Freitag - keine neuen Trades"; return false; }

   double closedToday = ClosedProfitToday();
   double floating    = FloatingProfit();
   double dayStartBal = AccountBalance() - closedToday;
   if(dayStartBal > 0)
   {
      double dayPct = (closedToday + floating) / dayStartBal * 100.0;
      if(InpDailyLossPct > 0 && dayPct <= -InpDailyLossPct)
      { g_status = StringFormat("Tagesverlust-Limit erreicht (%.2f%%)", dayPct); return false; }
      if(InpDailyProfitPct > 0 && dayPct >= InpDailyProfitPct)
      { g_status = StringFormat("Tagesziel erreicht (%.2f%%)", dayPct); return false; }
   }

   if(InpMaxConsecLosses > 0)
   {
      datetime lastLossTime = 0;
      int losses = ConsecutiveLosses(lastLossTime);
      if(losses >= InpMaxConsecLosses && TimeCurrent() - lastLossTime < InpPauseMinutes * 60)
      { g_status = StringFormat("Pause nach %d Verlusten", losses); return false; }
   }

   g_status = "Bereit - warte auf Ausbruch";
   return true;
}

//+------------------------------------------------------------------+
bool InSession()
{
   int h = Hour();
   if(InpSessionStartHour == InpSessionEndHour) return true;
   if(InpSessionStartHour < InpSessionEndHour)
      return (h >= InpSessionStartHour && h < InpSessionEndHour);
   return (h >= InpSessionStartHour || h < InpSessionEndHour);
}

//+------------------------------------------------------------------+
bool OpenTrade(int type, double atr)
{
   double slDist = MathMax(atr * InpSLAtrMult, InpMinSLPips * g_pip);
   if(slDist > InpMaxSLPips * g_pip)
   {
      g_status = StringFormat("SL zu gross (%.1f Pips)", slDist / g_pip);
      return false;
   }

   //--- Kosten muessen klein gegen den Stop sein
   double costPips = TotalCostPips();
   if(InpMaxCostToSL > 0 && costPips > InpMaxCostToSL * slDist / g_pip)
   {
      g_status = StringFormat("Kosten zu hoch: %.2f Pips bei SL %.1f Pips", costPips, slDist / g_pip);
      return false;
   }

   double minDist = (MarketInfo(Symbol(), MODE_STOPLEVEL) + 1) * Point;
   slDist = MathMax(slDist, minDist);
   double tpDist = MathMax(slDist * InpTPRatio, minDist);

   double lots = CalculateLots(slDist);
   if(lots <= 0) return false;

   ResetLastError();
   if(AccountFreeMarginCheck(Symbol(), type, lots) <= 0 || GetLastError() == ERR_NOT_ENOUGH_MONEY)
   {
      Print("Kein Trade: Nicht genuegend freie Margin fuer ", DoubleToString(lots, 2), " Lots");
      return false;
   }

   int ticket = -1;
   for(int attempt = 0; attempt < 3 && ticket < 0; attempt++)
   {
      RefreshRates();
      double price = (type == OP_BUY) ? Ask : Bid;
      ticket = OrderSend(Symbol(), type, lots, NormalizeDouble(price, Digits), g_slippage, 0, 0,
                         InpTradeComment, InpMagicNumber, 0, (type == OP_BUY) ? clrDodgerBlue : clrOrangeRed);
      if(ticket < 0)
      {
         Print("OrderSend fehlgeschlagen, Fehler ", GetLastError(), " - Versuch ", attempt + 1);
         Sleep(300);
      }
   }
   if(ticket < 0 || !OrderSelect(ticket, SELECT_BY_TICKET))
      return false;

   //--- SL/TP relativ zum tatsaechlichen Fuellkurs (ECN: Slippage moeglich)
   double open = OrderOpenPrice();
   double sl = NormalizeDouble((type == OP_BUY) ? open - slDist : open + slDist, Digits);
   double tp = NormalizeDouble((type == OP_BUY) ? open + tpDist : open - tpDist, Digits);

   bool modified = false;
   for(int attempt = 0; attempt < 5 && !modified; attempt++)
   {
      modified = OrderModify(ticket, open, sl, tp, 0, clrNONE);
      if(!modified)
      {
         Print("SL/TP setzen fehlgeschlagen, Fehler ", GetLastError(), " - Versuch ", attempt + 1);
         Sleep(300);
         RefreshRates();
      }
   }
   if(!modified)
   {
      Print("ACHTUNG: SL/TP konnte nicht gesetzt werden - Trade wird geschlossen.");
      CloseTrade(ticket);
      return false;
   }

   PrintFormat("%s %.2f Lots @ %s | SL %.1f Pips | TP %.1f Pips | Kosten %.2f Pips",
               (type == OP_BUY ? "BUY" : "SELL"), lots, DoubleToString(open, Digits),
               slDist / g_pip, tpDist / g_pip, costPips);
   return true;
}

//+------------------------------------------------------------------+
//| Lotgroesse: Risiko = SL-Verlust + Kommission                     |
//+------------------------------------------------------------------+
double CalculateLots(double slDist)
{
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(lotStep <= 0) lotStep = 0.01;

   double lots = InpFixedLots;
   if(InpRiskPercent > 0)
   {
      double pv = PipValuePerLot();
      if(pv <= 0)
      {
         Print("Lotberechnung nicht moeglich (TickValue/TickSize ungueltig).");
         return 0.0;
      }
      double capital    = MathMin(AccountBalance(), AccountEquity());
      double riskMoney  = capital * InpRiskPercent / 100.0;
      double lossPerLot = slDist / g_pip * pv + InpCommissionPerLot;
      lots = riskMoney / lossPerLot;
   }

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMin(lots, MathMin(maxLot, InpMaxLots));
   if(lots < minLot)
   {
      Print("Kein Trade: Lotgroesse (", DoubleToString(lots, 3), ") unter Mindestlot ", DoubleToString(minLot, 2));
      return 0.0;
   }
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Break-Even (inkl. Kosten), Trailing, Zeit-Exit                   |
//+------------------------------------------------------------------+
void ManageOpenTrades(double atr)
{
   if(atr <= 0) return;
   double minDist = (MarketInfo(Symbol(), MODE_STOPLEVEL) + 1) * Point;
   double bePips  = CommissionPips() + InpBEExtraPips;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      if(InpMaxBarsInTrade > 0 && iBarShift(NULL, 0, OrderOpenTime()) >= InpMaxBarsInTrade)
      {
         Print("Zeit-Exit fuer Ticket ", OrderTicket());
         CloseTrade(OrderTicket());
         continue;
      }

      double open  = OrderOpenPrice();
      double curSL = OrderStopLoss();
      double tp    = OrderTakeProfit();
      // 1 R aus dem urspruenglichen Abstand TP-Einstieg ableiten (TP = InpTPRatio x R)
      double r = (tp > 0) ? MathAbs(tp - open) / InpTPRatio : atr * InpSLAtrMult;
      if(r <= 0) continue;

      RefreshRates();
      double newSL = curSL;

      if(OrderType() == OP_BUY)
      {
         double profit = Bid - open;
         if(InpUseBreakEven && profit >= r * InpBETriggerR)
         {
            double be = open + bePips * g_pip;
            if(newSL < be) newSL = be;
         }
         if(InpUseTrailing && profit >= r * InpTrailStartR)
         {
            double ts = Bid - atr * InpTrailAtrMult;
            if(ts > newSL) newSL = ts;
         }
         newSL = NormalizeDouble(newSL, Digits);
         if(newSL > curSL + Point * 2 && Bid - newSL >= minDist)
         {
            if(!OrderModify(OrderTicket(), open, newSL, tp, 0, clrNONE))
               Print("Stop-Anpassung fehlgeschlagen, Fehler ", GetLastError());
         }
      }
      else
      {
         double profit = open - Ask;
         if(InpUseBreakEven && profit >= r * InpBETriggerR)
         {
            double be = open - bePips * g_pip;
            if(newSL == 0 || newSL > be) newSL = be;
         }
         if(InpUseTrailing && profit >= r * InpTrailStartR)
         {
            double ts = Ask + atr * InpTrailAtrMult;
            if(newSL == 0 || ts < newSL) newSL = ts;
         }
         newSL = NormalizeDouble(newSL, Digits);
         if((curSL == 0 || newSL < curSL - Point * 2) && newSL > 0 && newSL - Ask >= minDist)
         {
            if(!OrderModify(OrderTicket(), open, newSL, tp, 0, clrNONE))
               Print("Stop-Anpassung fehlgeschlagen, Fehler ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
bool CloseTrade(int ticket)
{
   for(int attempt = 0; attempt < 3; attempt++)
   {
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
      if(OrderCloseTime() != 0) return true;
      RefreshRates();
      double price = (OrderType() == OP_BUY) ? Bid : Ask;
      if(OrderClose(ticket, OrderLots(), NormalizeDouble(price, Digits), g_slippage, clrYellow))
         return true;
      Print("OrderClose fehlgeschlagen, Fehler ", GetLastError(), " - Versuch ", attempt + 1);
      Sleep(300);
   }
   return false;
}

//+------------------------------------------------------------------+
void CloseAllTrades(string reason)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      Print(reason, ": schliesse Ticket ", OrderTicket());
      CloseTrade(OrderTicket());
   }
}

//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber &&
         (OrderType() == OP_BUY || OrderType() == OP_SELL))
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
int CountTradesToday()
{
   datetime dayStart = iTime(NULL, PERIOD_D1, 0);
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber && OrderOpenTime() >= dayStart)
         count++;
   }
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber &&
         (OrderType() == OP_BUY || OrderType() == OP_SELL) && OrderOpenTime() >= dayStart)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
double ClosedProfitToday()
{
   datetime dayStart = iTime(NULL, PERIOD_D1, 0);
   double sum = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(OrderCloseTime() >= dayStart)
         sum += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return sum;
}

//+------------------------------------------------------------------+
double FloatingProfit()
{
   double sum = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return sum;
}

//+------------------------------------------------------------------+
int ConsecutiveLosses(datetime &lastLossTime)
{
   double trades[][2];
   int n = 0;
   datetime since = TimeCurrent() - 3 * 86400;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(OrderCloseTime() < since) continue;
      ArrayResize(trades, n + 1);
      trades[n][0] = (double)OrderCloseTime();
      trades[n][1] = OrderProfit() + OrderSwap() + OrderCommission();
      n++;
   }
   if(n == 0) return 0;

   ArraySort(trades, WHOLE_ARRAY, 0, MODE_DESCEND);
   int losses = 0;
   lastLossTime = (datetime)trades[0][0];
   for(int i = 0; i < n; i++)
   {
      if(trades[i][1] < 0) losses++;
      else break;
   }
   return losses;
}

//+------------------------------------------------------------------+
void UpdatePanel(double atr)
{
   if(!InpShowPanel || (IsTesting() && !IsVisualMode()))
      return;

   string txt = "\n  ECN Momentum-Scalper v1.00\n";
   txt += "  ------------------------------\n";
   txt += StringFormat("  Status        : %s\n", g_status);
   txt += StringFormat("  Spread        : %.2f Pips\n", (Ask - Bid) / g_pip);
   txt += StringFormat("  Kommission    : %.2f Pips\n", CommissionPips());
   txt += StringFormat("  ATR(%d)       : %.1f Pips\n", InpAtrPeriod, atr / g_pip);
   txt += StringFormat("  Offene Trades : %d / %d\n", CountOpenTrades(), InpMaxOpenTrades);
   txt += StringFormat("  Trades heute  : %d / %d\n", CountTradesToday(), InpMaxTradesPerDay);
   txt += StringFormat("  P/L heute     : %.2f %s\n", ClosedProfitToday() + FloatingProfit(), AccountCurrency());
   txt += StringFormat("  Risiko/Trade  : %.2f %%\n", InpRiskPercent);
   Comment(txt);
}
//+------------------------------------------------------------------+
