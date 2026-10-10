//+------------------------------------------------------------------+
//|                                                MartingaleGrid.mq4 |
//|   Nachkauf-Gitter: bei jedem Nachkauf wird die Lotgroesse        |
//|   verdoppelt, der ganze Korb wird gemeinsam mit Gewinn geschlossen|
//+------------------------------------------------------------------+
//| Ablauf (Kauf, Verkauf spiegelbildlich):                          |
//|   1. Start mit StartLots (0.01) in Richtung des Filters          |
//|   2. Laeuft der Kurs GridStep gegen den Korb -> Nachkauf mit     |
//|      LotMultiplier x letzte Lots (0.01, 0.02, 0.04, 0.08 ...)    |
//|      Der Abstand waechst je Stufe um StepMultiplier               |
//|   3. Korb-Ziel: Durchschnittspreis + TakeProfit (netto, inkl.     |
//|      Kommission und Swap) -> alle Positionen schliessen           |
//|   4. Notbremsen: nach MaxLevels kein Nachkauf mehr, Korb-Stop     |
//|      eine weitere Stufe hinter dem letzten Nachkauf, Equity-Stop  |
//|      in % des Kontos, danach Pause                                |
//|                                                                  |
//| Abstand und Ziel wahlweise in Pips oder als Anteil der Tages-ATR |
//| (StepMode = ATR). Im ATR-Modus gilt fuer den ganzen Korb die ATR |
//| des Vortags vor dem Start - so passt sich das Gitter an jedes    |
//| Paar an (EURUSD 0.4 x ATR ~ 25 Pips, EURGBP ~ 15 Pips).          |
//|                                                                  |
//| Standard (EURUSD, 6 Stufen, 25 Pips x 1.2):                       |
//|   Nachkaeufe bei 0 / 25 / 55 / 91 / 134 / 186 Pips               |
//|   Lots 0.01 / 0.02 / 0.04 / 0.08 / 0.16 / 0.32 = 0.63 Lots       |
//|   Korb-Stop bei 248 Pips -> Verlust ca. 650 USD (inkl. Kosten     |
//|   etwas mehr). Empfohlenes Konto: ab 10'000 USD bei 0.01 Start.  |
//|                                                                  |
//| WARNUNG: Verdoppeln erhoeht die Trefferquote, nicht die          |
//| Erwartung. Viele kleine Gewinne werden selten von einem grossen  |
//| Verlust aufgezehrt (research/ERGEBNIS.md). Standardmaessig nur   |
//| auf Demokonten aktiv.                                            |
//| Je Symbol ein Chart, Zeitrahmen egal (H1 empfohlen).             |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor"
#property version   "1.11"
#property strict
#property description "Nachkauf-Gitter mit Lot-Verdopplung, Korb-Ziel und Notbremsen."
#property description "Experiment - standardmaessig nur auf Demokonten aktiv."

input string InpSepGeneral       = "===== Allgemein =====";   // -----
input int    InpMagicNumber      = 280201;     // Magic Number
input string InpTradeComment     = "MartGrid"; // Order-Kommentar
input bool   InpAllowRealAccount = false;      // Auf Echtgeld-Konto handeln (NICHT empfohlen)
input double InpSlippagePips     = 1.0;        // Max. Slippage (Pips)
input double InpMaxSpreadPips    = 2.5;        // Max. Spread fuer Einstieg/Nachkauf (Pips)

input string InpSepGrid          = "===== Gitter ====="; // -----
input double InpStartLots        = 0.01;       // Start-Lotgroesse
input double InpLotMultiplier    = 2.0;        // Lot-Faktor je Nachkauf (2.0 = verdoppeln)
enum ENUM_STEP_MODE
{
   STEP_PIPS = 0,   // in Pips
   STEP_ATR  = 1    // als Anteil der Tages-ATR
};
input ENUM_STEP_MODE InpStepMode = STEP_PIPS;  // Abstand und Ziel berechnen
input double InpGridStepPips     = 25.0;       // Pips: Abstand zum 1. Nachkauf
input double InpGridStepAtr      = 0.4;        // ATR: Abstand zum 1. Nachkauf (x Tages-ATR)
input int    InpAtrPeriod        = 14;         // ATR: Periode (Tageskerzen)
input double InpStepMultiplier   = 1.2;        // Abstand waechst je Stufe um diesen Faktor (1.0 = gleich)
input int    InpMaxLevels        = 6;          // Max. Positionen im Korb (inkl. Start)
input double InpTakeProfitPips   = 10.0;       // Pips: Korb-Ziel ueber/unter Durchschnittspreis (netto)
input double InpTakeProfitAtr    = 0.15;       // ATR: Korb-Ziel (x Tages-ATR, netto)
input double InpCommissionPerLot = 7.0;        // Kommission pro Lot Hin+Rueck (nur fuer Anzeige/Planung)

input string InpSepDir           = "===== Richtung ====="; // -----
enum ENUM_GRID_DIR
{
   DIR_TREND     = 0,   // Trend (EMA)
   DIR_BUY_ONLY  = 1,   // nur Kauf
   DIR_SELL_ONLY = 2    // nur Verkauf
};
input ENUM_GRID_DIR InpDirection = DIR_TREND;  // Richtung
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H4;  // Zeitrahmen Trendfilter
input int    InpTrendEma         = 200;        // EMA-Periode Trendfilter

input string InpSepSafety        = "===== Notbremsen ====="; // -----
input bool   InpFinalStop        = true;       // Korb schliessen eine Stufe hinter dem letzten Nachkauf
input double InpEquityStopPct    = 10.0;       // Korb schliessen bei Verlust >= x % des Kontostands (0 = aus)
input int    InpPauseHours       = 24;         // Pause nach Notbremse (Stunden)
input int    InpFridayStopHour   = 18;         // Freitags ab dieser Stunde kein neuer Korb (Serverzeit, -1 = aus)

//--- Korb-Zustand (wird aus offenen Orders gelesen)
int      g_count     = 0;     // offene Positionen
int      g_dir       = -1;    // OP_BUY / OP_SELL / -1
double   g_lots      = 0.0;   // Summe Lots
double   g_avg       = 0.0;   // gewichteter Durchschnittspreis
double   g_firstPrice= 0.0;   // Einstiegskurs der Start-Position
double   g_net       = 0.0;   // Gewinn + Swap + Kommission
double   g_step      = 0.0;   // Abstand zum 1. Nachkauf (Pips) fuer den aktuellen Korb
double   g_tp        = 0.0;   // Korb-Ziel (Pips) fuer den aktuellen Korb

double   g_pip       = 0.0;
int      g_slip      = 0;
datetime g_pauseUntil= 0;
string   g_status    = "";

//+------------------------------------------------------------------+
int OnInit()
{
   g_pip  = (Digits == 3 || Digits == 5) ? Point * 10.0 : Point;
   g_slip = (int)MathRound(InpSlippagePips * g_pip / Point);

   if(!IsDemo() && !InpAllowRealAccount && !IsTesting())
   {
      Alert("MartingaleGrid: Echtgeld-Konto erkannt - der EA bleibt inaktiv (Experiment).");
      return INIT_FAILED;
   }
   if(InpMaxLevels < 1 || InpStartLots <= 0 || InpLotMultiplier < 1.0 || InpStepMultiplier < 1.0 ||
      (InpStepMode == STEP_PIPS && InpGridStepPips <= 0) ||
      (InpStepMode == STEP_ATR && (InpGridStepAtr <= 0 || InpAtrPeriod < 1)))
   {
      Alert("MartingaleGrid: ungueltige Gitter-Einstellungen.");
      return INIT_PARAMETERS_INCORRECT;
   }
   PrintPlan();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Comment(""); }

//+------------------------------------------------------------------+
void OnTick()
{
   RefreshRates();
   ReadBasket();

   if(g_count > 0)
      ManageBasket();
   else
      TryStart();

   UpdatePanel();
}

//+------------------------------------------------------------------+
double PipValuePerLot()
{
   double tv = MarketInfo(Symbol(), MODE_TICKVALUE);
   double ts = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tv <= 0 || ts <= 0) return 0.0;
   return tv * g_pip / ts;
}

double SpreadPips() { return (Ask - Bid) / g_pip; }

// Abstand (Pips) vom Start bis zur Stufe 'level' (0 = Start)
double LevelDistance(int level)
{
   double d = 0.0;
   for(int i = 0; i < level; i++)
      d += g_step * MathPow(InpStepMultiplier, i);
   return d;
}

//+------------------------------------------------------------------+
//| Abstand und Ziel in Pips festlegen. ATR-Modus: ATR des Vortags   |
//| vor Korb-Start (basketStart = 0 -> kein Korb, aktuelle Vortags-  |
//| ATR). So bleibt das Gitter eines Korbs fest, auch nach Neustart. |
//+------------------------------------------------------------------+
bool UpdateGridSize(datetime basketStart)
{
   if(InpStepMode == STEP_PIPS)
   {
      g_step = InpGridStepPips;
      g_tp   = InpTakeProfitPips;
      return true;
   }
   int shift = 1;
   if(basketStart > 0)
   {
      shift = iBarShift(NULL, PERIOD_D1, basketStart) + 1;
      if(shift < 1) shift = 1;
   }
   double atr = iATR(NULL, PERIOD_D1, InpAtrPeriod, shift) / g_pip;
   if(atr <= 0) return false;
   g_step = InpGridStepAtr * atr;
   g_tp   = InpTakeProfitAtr * atr;
   return true;
}

double LevelLots(int level) { return InpStartLots * MathPow(InpLotMultiplier, level); }

double NormalizeLots(double lots)
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minL = MarketInfo(Symbol(), MODE_MINLOT);
   double maxL = MarketInfo(Symbol(), MODE_MAXLOT);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step + 0.5) * step;
   return MathMax(minL, MathMin(maxL, lots));
}

//+------------------------------------------------------------------+
//| Planung ins Journal: Stufen, Lots, Verlust beim Korb-Stop        |
//+------------------------------------------------------------------+
void PrintPlan()
{
   if(!UpdateGridSize(0)) { Print("MartingaleGrid: noch keine Tages-ATR - Plan folgt beim Start des Korbs"); return; }
   double pv = PipValuePerLot();
   double stopDist = LevelDistance(InpMaxLevels);   // eine Stufe hinter dem letzten Nachkauf
   double loss = 0.0, total = 0.0;
   string levels = "";
   for(int i = 0; i < InpMaxLevels; i++)
   {
      double lots = NormalizeLots(LevelLots(i));
      total += lots;
      loss  += (stopDist - LevelDistance(i)) * lots * pv + lots * InpCommissionPerLot;
      levels += StringFormat("%s%.0f Pips/%.2f", i > 0 ? ", " : "", LevelDistance(i), lots);
   }
   Print(StringFormat("MartingaleGrid Plan (Abstand %.1f Pips, Ziel %.1f Pips): ", g_step, g_tp), levels);
   Print(StringFormat("MartingaleGrid: max. %.2f Lots, Korb-Stop bei %.0f Pips -> Verlust ca. %.0f %s (%.1f %% des Kontos)",
                      total, stopDist, loss, AccountCurrency(), 100.0 * loss / MathMax(AccountBalance(), 1.0)));
}

//+------------------------------------------------------------------+
//| Offene Positionen dieses EAs auf diesem Symbol einlesen          |
//+------------------------------------------------------------------+
void ReadBasket()
{
   g_count = 0; g_dir = -1; g_lots = 0.0; g_avg = 0.0; g_net = 0.0;
   g_firstPrice = 0.0;
   datetime firstT = 0;
   double sum = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() > OP_SELL) continue;

      g_count++;
      g_dir   = OrderType();
      g_lots += OrderLots();
      sum    += OrderLots() * OrderOpenPrice();
      g_net  += OrderProfit() + OrderSwap() + OrderCommission();
      if(firstT == 0 || OrderOpenTime() < firstT)
      {
         firstT = OrderOpenTime();
         g_firstPrice = OrderOpenPrice();
      }
   }
   if(g_lots > 0) g_avg = sum / g_lots;
   UpdateGridSize(firstT);
}

//+------------------------------------------------------------------+
//| Neuen Korb starten                                               |
//+------------------------------------------------------------------+
void TryStart()
{
   if(TimeCurrent() < g_pauseUntil)
   {
      g_status = "Pause nach Notbremse bis " + TimeToString(g_pauseUntil, TIME_DATE | TIME_MINUTES);
      return;
   }
   if(InpFridayStopHour >= 0 && DayOfWeek() == 5 && Hour() >= InpFridayStopHour)
   {
      g_status = "Freitag - kein neuer Korb";
      return;
   }
   if(SpreadPips() > InpMaxSpreadPips)
   {
      g_status = StringFormat("Spread %.1f Pips zu hoch", SpreadPips());
      return;
   }

   if(!UpdateGridSize(0) || g_step <= 0)
   {
      g_status = "Warte auf Daten Tages-ATR";
      return;
   }

   int type = -1;
   if(InpDirection == DIR_BUY_ONLY)       type = OP_BUY;
   else if(InpDirection == DIR_SELL_ONLY) type = OP_SELL;
   else
   {
      double ema = iMA(NULL, InpTrendTF, InpTrendEma, 0, MODE_EMA, PRICE_CLOSE, 1);
      double cl  = iClose(NULL, InpTrendTF, 1);
      if(ema <= 0 || cl <= 0) { g_status = "Warte auf Daten Trendfilter"; return; }
      type = (cl > ema) ? OP_BUY : OP_SELL;
   }
   g_status = "Starte Korb";
   OpenPosition(type, NormalizeLots(InpStartLots), 0);
}

//+------------------------------------------------------------------+
//| Offenen Korb verwalten: Ziel, Nachkauf, Notbremsen               |
//+------------------------------------------------------------------+
void ManageBasket()
{
   double pv = PipValuePerLot();
   double target = g_tp * pv * g_lots;

   // 1. Korb-Ziel erreicht (netto inkl. Kommission und Swap)
   if(g_net >= target && target > 0)
   {
      CloseBasket(StringFormat("Ziel erreicht (%.2f %s)", g_net, AccountCurrency()));
      return;
   }

   // Wie weit liegt der Kurs gegen den Start-Einstieg? (positiv = gegen den Korb)
   double against = (g_dir == OP_BUY) ? (g_firstPrice - Bid) / g_pip : (Ask - g_firstPrice) / g_pip;

   // 2. Notbremse: Equity-Stop
   if(InpEquityStopPct > 0 && -g_net >= InpEquityStopPct / 100.0 * AccountBalance())
   {
      CloseBasket(StringFormat("Equity-Stop (%.2f %s)", g_net, AccountCurrency()));
      g_pauseUntil = TimeCurrent() + InpPauseHours * 3600;
      return;
   }

   // 3. Notbremse: Korb-Stop eine Stufe hinter dem letzten Nachkauf
   if(InpFinalStop && g_step > 0 && g_count >= InpMaxLevels && against >= LevelDistance(InpMaxLevels))
   {
      CloseBasket(StringFormat("Korb-Stop nach %d Stufen (%.2f %s)", g_count, g_net, AccountCurrency()));
      g_pauseUntil = TimeCurrent() + InpPauseHours * 3600;
      return;
   }

   // 4. Nachkauf
   if(g_step <= 0)
      g_status = "Warte auf Daten Tages-ATR";
   else if(g_count < InpMaxLevels)
   {
      double need = LevelDistance(g_count);
      g_status = StringFormat("Stufe %d/%d, naechster Nachkauf bei %.0f Pips (aktuell %.0f)",
                              g_count, InpMaxLevels, need, against);
      if(against >= need && SpreadPips() <= InpMaxSpreadPips)
         OpenPosition(g_dir, NormalizeLots(LevelLots(g_count)), g_count);
   }
   else
      g_status = StringFormat("Alle %d Stufen offen - Korb-Stop bei %.0f Pips (aktuell %.0f)",
                              g_count, LevelDistance(InpMaxLevels), against);
}

//+------------------------------------------------------------------+
bool OpenPosition(int type, double lots, int level)
{
   ResetLastError();
   if(AccountFreeMarginCheck(Symbol(), type, lots) <= 0 || GetLastError() == ERR_NOT_ENOUGH_MONEY)
   {
      g_status = StringFormat("Zu wenig Margin fuer %.2f Lots (Stufe %d)", lots, level + 1);
      return false;
   }
   double price = (type == OP_BUY) ? Ask : Bid;
   string cmt = StringFormat("%s L%d", InpTradeComment, level + 1);
   int ticket = OrderSend(Symbol(), type, lots, NormalizeDouble(price, Digits), g_slip, 0, 0,
                          cmt, InpMagicNumber, 0, type == OP_BUY ? clrDodgerBlue : clrOrangeRed);
   if(ticket < 0)
   {
      Print("OrderSend fehlgeschlagen, Fehler ", GetLastError());
      return false;
   }
   Print(StringFormat("MartingaleGrid: %s Stufe %d, %.2f Lots @ %s",
                      type == OP_BUY ? "Kauf" : "Verkauf", level + 1, lots, DoubleToString(price, Digits)));
   return true;
}

//+------------------------------------------------------------------+
void CloseBasket(string reason)
{
   Print("MartingaleGrid: Korb schliessen - ", reason);
   for(int attempt = 0; attempt < 3; attempt++)
   {
      bool left = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
         if(OrderType() > OP_SELL) continue;
         RefreshRates();
         double price = (OrderType() == OP_BUY) ? Bid : Ask;
         if(!OrderClose(OrderTicket(), OrderLots(), NormalizeDouble(price, Digits), g_slip, clrYellow))
         {
            Print("OrderClose fehlgeschlagen, Fehler ", GetLastError());
            left = true;
         }
      }
      if(!left) break;
      Sleep(500);
   }
   g_status = reason;
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   string dir = (g_dir == OP_BUY) ? "Kauf" : (g_dir == OP_SELL) ? "Verkauf" : "-";
   double pv = PipValuePerLot();
   Comment("\n  Martingale-Grid  [EXPERIMENT]\n",
           StringFormat("  Korb: %s, %d/%d Positionen, %.2f Lots\n", dir, g_count, InpMaxLevels, g_lots),
           StringFormat("  Durchschnitt: %s   Ergebnis netto: %.2f %s\n",
                        g_count > 0 ? DoubleToString(g_avg, Digits) : "-", g_net, AccountCurrency()),
           StringFormat("  Ziel: %.2f %s   Equity-Stop: %.2f %s\n",
                        g_tp * pv * g_lots, AccountCurrency(),
                        InpEquityStopPct / 100.0 * AccountBalance(), AccountCurrency()),
           StringFormat("  Abstand: %.1f Pips   Ziel: %.1f Pips   Spread: %.1f Pips\n", g_step, g_tp, SpreadPips()),
           "  ", g_status, "\n");
}
//+------------------------------------------------------------------+
