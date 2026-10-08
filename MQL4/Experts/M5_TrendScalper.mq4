//+------------------------------------------------------------------+
//|                                              M5_TrendScalper.mq4 |
//|        Trendfolgender Pullback-Scalper fuer MetaTrader 4 (M5)    |
//+------------------------------------------------------------------+
//| Strategie (Kurzfassung):                                         |
//|  1. Trendfilter : EMA 50 / EMA 200 auf M5 + EMA 50 auf H1        |
//|  2. Einstieg    : Ruecksetzer gegen den Trend, erkannt ueber      |
//|                   Bollinger-Band-Beruehrung + RSI(7), der aus     |
//|                   ueberverkauft/ueberkauft zurueckkreuzt          |
//|  3. Bestaetigung: Schlusskerze in Trendrichtung                   |
//|  4. Risiko      : SL/TP auf ATR-Basis, Positionsgroesse nach      |
//|                   Risiko-%, Break-Even, Trailing-Stop, Zeit-Exit  |
//|  5. Schutz      : Spread-, Volatilitaets-, Sessions-Filter,       |
//|                   Tagesverlust-Limit, Pause nach Verlustserie     |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor"
#property version   "1.00"
#property strict
#property description "M5 Trend-Pullback-Scalper: EMA-Trendfilter, Bollinger Bands + RSI Einstieg,"
#property description "ATR-basierte Stops, risikobasierte Lotgroesse und mehrere Schutzmechanismen."

//--- Allgemein
input string           InpSepGeneral       = "===== Allgemein =====";   // -----
input int              InpMagicNumber      = 250501;     // Magic Number
input string           InpTradeComment     = "M5Scalper"; // Order-Kommentar
input double           InpSlippagePips     = 1.5;        // Max. Slippage (Pips)

//--- Money Management
input string           InpSepMM            = "===== Money Management ====="; // -----
input double           InpRiskPercent      = 0.5;        // Risiko pro Trade in % des Kontos (0 = feste Lots)
input double           InpFixedLots        = 0.01;       // Feste Lotgroesse (wenn Risiko = 0)
input double           InpMaxLots          = 5.0;        // Maximale Lotgroesse
input int              InpMaxOpenTrades    = 1;          // Max. gleichzeitige Trades (dieses Symbol)
input int              InpMaxTradesPerDay  = 30;         // Max. Trades pro Tag

//--- Trendfilter
input string           InpSepTrend         = "===== Trendfilter ====="; // -----
input int              InpEmaFast          = 50;         // Schnelle EMA (Chart-TF)
input int              InpEmaSlow          = 200;        // Langsame EMA (Chart-TF)
input int              InpEmaSlopeBars     = 5;          // Steigung der langsamen EMA ueber X Bars (0 = aus)
input bool             InpUseHTFFilter     = true;       // Hoeheren Zeitrahmen als Filter nutzen
input ENUM_TIMEFRAMES  InpHTF              = PERIOD_H1;  // Hoeherer Zeitrahmen
input int              InpHTFEma           = 50;         // EMA-Periode hoeherer Zeitrahmen

//--- Einstieg
input string           InpSepEntry         = "===== Einstieg ====="; // -----
input int              InpRsiPeriod        = 7;          // RSI Periode
input double           InpRsiOversold      = 30.0;       // RSI ueberverkauft (Long)
input double           InpRsiOverbought    = 70.0;       // RSI ueberkauft (Short)
input bool             InpUseBBFilter      = true;       // Bollinger-Band-Beruehrung verlangen
input int              InpBBPeriod         = 20;         // Bollinger Periode
input double           InpBBDeviation      = 2.0;        // Bollinger Abweichung
input int              InpBBLookback       = 3;          // Band-Beruehrung innerhalb der letzten X Bars
input bool             InpRequireCandle    = true;       // Bestaetigungskerze in Trendrichtung verlangen

//--- Exits
input string           InpSepExit          = "===== Stop Loss / Take Profit ====="; // -----
input int              InpAtrPeriod        = 14;         // ATR Periode
input double           InpSLAtrMult        = 1.5;        // Stop Loss = ATR x Faktor
input double           InpTPAtrMult        = 1.2;        // Take Profit = ATR x Faktor
input double           InpMinSLPips        = 5.0;        // Minimaler Stop Loss (Pips)
input double           InpMaxSLPips        = 20.0;       // Maximaler Stop Loss (Pips) - sonst kein Trade
input bool             InpUseBreakEven     = true;       // Break-Even aktivieren
input double           InpBEAtrMult        = 0.7;        // Break-Even ab Gewinn = ATR x Faktor
input double           InpBELockPips       = 0.5;        // Gesicherte Pips bei Break-Even
input bool             InpUseTrailing      = true;       // Trailing-Stop aktivieren
input double           InpTrailStartAtr    = 0.9;        // Trailing ab Gewinn = ATR x Faktor
input double           InpTrailDistAtr     = 0.6;        // Trailing-Abstand = ATR x Faktor
input int              InpMaxBarsInTrade   = 48;         // Trade nach X Bars schliessen (0 = aus)

//--- Filter
input string           InpSepFilter        = "===== Filter ====="; // -----
input double           InpMaxSpreadPips    = 2.0;        // Maximaler Spread (Pips)
input double           InpMinAtrPips       = 2.0;        // Minimale ATR (Pips) - zu ruhiger Markt
input double           InpMaxAtrPips       = 15.0;       // Maximale ATR (Pips) - zu wilder Markt
input bool             InpUseSession       = true;       // Handelszeiten-Filter (Server-Zeit)
input int              InpSessionStartHour = 8;          // Handelsbeginn (Stunde, Server-Zeit)
input int              InpSessionEndHour   = 20;         // Handelsende (Stunde, Server-Zeit)
input int              InpFridayStopHour   = 18;         // Freitag: keine neuen Trades ab (Stunde)
input bool             InpFridayCloseAll   = true;       // Freitag: alle Trades schliessen
input int              InpFridayCloseHour  = 21;         // Freitag: Schliessen ab (Stunde)

//--- Kontoschutz
input string           InpSepProtect       = "===== Kontoschutz ====="; // -----
input double           InpDailyLossPct     = 3.0;        // Tagesverlust-Limit in % (0 = aus)
input double           InpDailyProfitPct   = 0.0;        // Tagesgewinn-Ziel in % (0 = aus)
input int              InpMaxConsecLosses  = 3;          // Pause nach X Verlusten in Folge (0 = aus)
input int              InpPauseMinutes     = 60;         // Pausendauer (Minuten)
input bool             InpShowPanel        = true;       // Info-Panel im Chart anzeigen

//--- globale Variablen
double   g_pip      = 0.0;   // Wert eines Pips in Preis-Einheiten
int      g_slippage = 0;     // Slippage in Punkten
datetime g_lastBar  = 0;
string   g_status   = "";

//+------------------------------------------------------------------+
int OnInit()
{
   g_pip      = (Digits == 3 || Digits == 5) ? Point * 10.0 : Point;
   g_slippage = (int)MathRound(InpSlippagePips * g_pip / Point);

   if(InpEmaFast >= InpEmaSlow)
   {
      Print("Fehler: Schnelle EMA muss kleiner als langsame EMA sein.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpSLAtrMult <= 0 || InpTPAtrMult <= 0 || InpRsiOversold >= InpRsiOverbought)
   {
      Print("Fehler: Ungueltige SL/TP- oder RSI-Parameter.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(Period() != PERIOD_M5)
      Print("Hinweis: Der EA ist fuer M5 optimiert. Aktueller Zeitrahmen: M", Period());

   g_lastBar = Time[0];   // nicht sofort beim Start handeln
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
   if(Bars < InpEmaSlow + 10)
      return;

   double atr = iATR(NULL, 0, InpAtrPeriod, 1);

   //--- offene Trades verwalten (jeden Tick)
   ManageOpenTrades(atr);

   //--- Freitag: alles schliessen
   if(InpFridayCloseAll && DayOfWeek() == 5 && Hour() >= InpFridayCloseHour)
   {
      CloseAllTrades("Wochenend-Schliessung");
      UpdatePanel(atr);
      return;
   }

   //--- nur bei neuer Kerze nach Signalen suchen
   if(!IsNewBar())
   {
      UpdatePanel(atr);
      return;
   }

   if(!CanOpenNewTrade(atr))
   {
      UpdatePanel(atr);
      return;
   }

   int signal = GetSignal();
   if(signal == OP_BUY || signal == OP_SELL)
      OpenTrade(signal, atr);

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
//| Signal-Logik: -1 = kein Signal, OP_BUY oder OP_SELL              |
//+------------------------------------------------------------------+
int GetSignal()
{
   //--- Trend auf dem Chart-Zeitrahmen (abgeschlossene Kerze)
   double emaFast = iMA(NULL, 0, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaSlow = iMA(NULL, 0, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double close1  = Close[1];

   bool trendUp   = (close1 > emaSlow && emaFast > emaSlow);
   bool trendDown = (close1 < emaSlow && emaFast < emaSlow);

   if(InpEmaSlopeBars > 0)
   {
      double emaSlowPrev = iMA(NULL, 0, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE, 1 + InpEmaSlopeBars);
      trendUp   = trendUp   && (emaSlow > emaSlowPrev);
      trendDown = trendDown && (emaSlow < emaSlowPrev);
   }

   //--- Trend auf hoeherem Zeitrahmen
   if(InpUseHTFFilter)
   {
      double htfEma   = iMA(NULL, InpHTF, InpHTFEma, 0, MODE_EMA, PRICE_CLOSE, 1);
      double htfClose = iClose(NULL, InpHTF, 1);
      if(htfEma <= 0 || htfClose <= 0)
         return -1;
      trendUp   = trendUp   && (htfClose > htfEma);
      trendDown = trendDown && (htfClose < htfEma);
   }

   if(!trendUp && !trendDown)
      return -1;

   //--- RSI kreuzt aus Extremzone zurueck
   double rsi1 = iRSI(NULL, 0, InpRsiPeriod, PRICE_CLOSE, 1);
   double rsi2 = iRSI(NULL, 0, InpRsiPeriod, PRICE_CLOSE, 2);

   if(trendUp)
   {
      bool rsiOk    = (rsi2 < InpRsiOversold && rsi1 >= InpRsiOversold);
      bool bbOk     = !InpUseBBFilter || TouchedBand(MODE_LOWER);
      bool candleOk = !InpRequireCandle || (Close[1] > Open[1]);
      if(rsiOk && bbOk && candleOk)
         return OP_BUY;
   }
   else if(trendDown)
   {
      bool rsiOk    = (rsi2 > InpRsiOverbought && rsi1 <= InpRsiOverbought);
      bool bbOk     = !InpUseBBFilter || TouchedBand(MODE_UPPER);
      bool candleOk = !InpRequireCandle || (Close[1] < Open[1]);
      if(rsiOk && bbOk && candleOk)
         return OP_SELL;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Hat der Kurs in den letzten X Bars das Bollinger Band beruehrt? |
//+------------------------------------------------------------------+
bool TouchedBand(int mode)
{
   int lookback = MathMax(1, InpBBLookback);
   for(int i = 1; i <= lookback; i++)
   {
      double band = iBands(NULL, 0, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, mode, i);
      if(mode == MODE_LOWER && Low[i]  <= band) return true;
      if(mode == MODE_UPPER && High[i] >= band) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Pruefung aller Filter vor einem neuen Trade                      |
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

   //--- Tages-P/L (geschlossen + offen)
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

   //--- Pause nach Verlustserie
   if(InpMaxConsecLosses > 0)
   {
      datetime lastLossTime = 0;
      int losses = ConsecutiveLosses(lastLossTime);
      if(losses >= InpMaxConsecLosses && TimeCurrent() - lastLossTime < InpPauseMinutes * 60)
      { g_status = StringFormat("Pause nach %d Verlusten", losses); return false; }
   }

   g_status = "Bereit - warte auf Signal";
   return true;
}

//+------------------------------------------------------------------+
bool InSession()
{
   int h = Hour();
   if(InpSessionStartHour == InpSessionEndHour)
      return true;
   if(InpSessionStartHour < InpSessionEndHour)
      return (h >= InpSessionStartHour && h < InpSessionEndHour);
   return (h >= InpSessionStartHour || h < InpSessionEndHour);   // ueber Mitternacht
}

//+------------------------------------------------------------------+
//| Trade eroeffnen (ECN-kompatibel: erst Order, dann SL/TP setzen)  |
//+------------------------------------------------------------------+
bool OpenTrade(int type, double atr)
{
   double slDist = MathMax(atr * InpSLAtrMult, InpMinSLPips * g_pip);
   double tpDist = atr * InpTPAtrMult;

   if(slDist > InpMaxSLPips * g_pip)
   {
      Print("Kein Trade: Stop Loss waere zu gross (", DoubleToString(slDist / g_pip, 1), " Pips)");
      return false;
   }

   //--- Mindestabstand des Brokers beachten
   double minDist = (MarketInfo(Symbol(), MODE_STOPLEVEL) + 1) * Point;
   slDist = MathMax(slDist, minDist);
   tpDist = MathMax(tpDist, minDist);

   double lots = CalculateLots(slDist);
   if(lots <= 0)
      return false;

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
      color  clr   = (type == OP_BUY) ? clrDodgerBlue : clrOrangeRed;
      ticket = OrderSend(Symbol(), type, lots, NormalizeDouble(price, Digits), g_slippage,
                         0, 0, InpTradeComment, InpMagicNumber, 0, clr);
      if(ticket < 0)
      {
         Print("OrderSend fehlgeschlagen, Fehler ", GetLastError(), " - Versuch ", attempt + 1);
         Sleep(500);
      }
   }
   if(ticket < 0)
      return false;

   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return false;

   double open = OrderOpenPrice();
   double sl, tp;
   if(type == OP_BUY) { sl = open - slDist; tp = open + tpDist; }
   else               { sl = open + slDist; tp = open - tpDist; }
   sl = NormalizeDouble(sl, Digits);
   tp = NormalizeDouble(tp, Digits);

   bool modified = false;
   for(int attempt = 0; attempt < 5 && !modified; attempt++)
   {
      modified = OrderModify(ticket, open, sl, tp, 0, clrNONE);
      if(!modified)
      {
         Print("SL/TP setzen fehlgeschlagen, Fehler ", GetLastError(), " - Versuch ", attempt + 1);
         Sleep(500);
         RefreshRates();
      }
   }

   //--- Sicherheit: niemals ohne Stop Loss im Markt bleiben
   if(!modified)
   {
      Print("ACHTUNG: SL/TP konnte nicht gesetzt werden - Trade wird geschlossen.");
      CloseTrade(ticket);
      return false;
   }

   PrintFormat("%s eroeffnet: %.2f Lots @ %s, SL %s (%.1f Pips), TP %s (%.1f Pips)",
               (type == OP_BUY ? "BUY" : "SELL"), lots, DoubleToString(open, Digits),
               DoubleToString(sl, Digits), slDist / g_pip, DoubleToString(tp, Digits), tpDist / g_pip);
   return true;
}

//+------------------------------------------------------------------+
//| Lotgroesse aus Risiko-% und SL-Abstand                           |
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
      double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
      double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
      if(tickValue <= 0 || tickSize <= 0 || slDist <= 0)
      {
         Print("Lotberechnung nicht moeglich (TickValue/TickSize ungueltig).");
         return 0.0;
      }
      double capital    = MathMin(AccountBalance(), AccountEquity());
      double riskMoney  = capital * InpRiskPercent / 100.0;
      double lossPerLot = slDist / tickSize * tickValue;
      lots = riskMoney / lossPerLot;
   }

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMin(lots, MathMin(maxLot, InpMaxLots));

   if(lots < minLot)
   {
      Print("Kein Trade: Berechnete Lotgroesse (", DoubleToString(lots, 3),
            ") unter Mindestlot ", DoubleToString(minLot, 2), " - Risiko waere zu hoch.");
      return 0.0;
   }
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Break-Even, Trailing-Stop und Zeit-Exit                          |
//+------------------------------------------------------------------+
void ManageOpenTrades(double atr)
{
   if(atr <= 0) return;
   double minDist = (MarketInfo(Symbol(), MODE_STOPLEVEL) + 1) * Point;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      //--- Zeit-Exit
      if(InpMaxBarsInTrade > 0 && iBarShift(NULL, 0, OrderOpenTime()) >= InpMaxBarsInTrade)
      {
         Print("Zeit-Exit fuer Ticket ", OrderTicket());
         CloseTrade(OrderTicket());
         continue;
      }

      RefreshRates();
      double open  = OrderOpenPrice();
      double curSL = OrderStopLoss();
      double newSL = curSL;

      if(OrderType() == OP_BUY)
      {
         double profit = Bid - open;
         if(InpUseBreakEven && profit >= atr * InpBEAtrMult)
         {
            double be = open + InpBELockPips * g_pip;
            if(newSL < be) newSL = be;
         }
         if(InpUseTrailing && profit >= atr * InpTrailStartAtr)
         {
            double ts = Bid - atr * InpTrailDistAtr;
            if(ts > newSL) newSL = ts;
         }
         newSL = NormalizeDouble(newSL, Digits);
         if(newSL > curSL + Point * 5 && Bid - newSL >= minDist)
         {
            if(!OrderModify(OrderTicket(), open, newSL, OrderTakeProfit(), 0, clrNONE))
               Print("Stop-Anpassung fehlgeschlagen, Fehler ", GetLastError());
         }
      }
      else // OP_SELL
      {
         double profit = open - Ask;
         if(InpUseBreakEven && profit >= atr * InpBEAtrMult)
         {
            double be = open - InpBELockPips * g_pip;
            if(newSL == 0 || newSL > be) newSL = be;
         }
         if(InpUseTrailing && profit >= atr * InpTrailStartAtr)
         {
            double ts = Ask + atr * InpTrailDistAtr;
            if(newSL == 0 || ts < newSL) newSL = ts;
         }
         newSL = NormalizeDouble(newSL, Digits);
         if((curSL == 0 || newSL < curSL - Point * 5) && newSL > 0 && newSL - Ask >= minDist)
         {
            if(!OrderModify(OrderTicket(), open, newSL, OrderTakeProfit(), 0, clrNONE))
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
      Sleep(500);
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
//| Hilfsfunktionen fuer Statistiken                                 |
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
//| Anzahl Verluste in Folge (neueste zuerst) + Zeit des letzten     |
//+------------------------------------------------------------------+
int ConsecutiveLosses(datetime &lastLossTime)
{
   double trades[][2];   // [i][0] = Schliesszeit, [i][1] = Ergebnis
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

   string txt = "\n  M5 Trend-Scalper v1.00\n";
   txt += "  ------------------------------\n";
   txt += StringFormat("  Status        : %s\n", g_status);
   txt += StringFormat("  Spread        : %.1f Pips\n", (Ask - Bid) / g_pip);
   txt += StringFormat("  ATR(%d)       : %.1f Pips\n", InpAtrPeriod, atr / g_pip);
   txt += StringFormat("  Offene Trades : %d / %d\n", CountOpenTrades(), InpMaxOpenTrades);
   txt += StringFormat("  Trades heute  : %d / %d\n", CountTradesToday(), InpMaxTradesPerDay);
   txt += StringFormat("  P/L heute     : %.2f %s\n", ClosedProfitToday() + FloatingProfit(), AccountCurrency());
   txt += StringFormat("  Risiko/Trade  : %.2f %%\n", InpRiskPercent);
   Comment(txt);
}
//+------------------------------------------------------------------+
