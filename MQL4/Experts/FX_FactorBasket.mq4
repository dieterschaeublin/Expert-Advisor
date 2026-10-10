//+------------------------------------------------------------------+
//|                                              FX_FactorBasket.mq4 |
//|   Waehrungs-Faktor-Portfolio: Carry + Momentum + Value-Umkehr     |
//+------------------------------------------------------------------+
//| Grundlage (research/RECHERCHE_STRATEGIEN.md):                    |
//|   Barroso/Santa-Clara (JFQA 2015): Carry, Momentum und Value-    |
//|   Umkehr zusammen schlagen den reinen Carry-Trade auch Out-of-   |
//|   Sample. Moreira/Muir: Volatilitaets-Steuerung verbessert Carry. |
//|                                                                  |
//| Ablauf (einmal pro Monat, 1. Handelstag ab InpRebalanceHour):    |
//|   1. Waehrungen: USD + je eine pro Paar (EURUSD -> EUR,          |
//|      USDJPY -> JPY). Alle Signale gegen USD, USD selbst = 0.     |
//|   2. Carry    = Zinsdifferenz zum USD (aus den Swaps des Brokers |
//|                 oder manuell eingetragenen Leitzinsen)           |
//|      Momentum = Rendite der letzten 63 Handelstage               |
//|      Value    = -(Rendite der letzten 756 Handelstage)           |
//|   3. Je Signal z-Wert ueber alle Waehrungen, Mittelwert bilden,  |
//|      Gewicht = Abweichung vom Mittel (Summe aller Gewichte = 0)  |
//|   4. Gewichte so skalieren, dass das Portfolio ca. InpTargetVol  |
//|      % Schwankung pro Jahr hat (letzte 60 Tage), Hebel begrenzt  |
//|   5. Positionen in den USD-Paaren auf das Ziel anpassen          |
//|                                                                  |
//| Schutz: Notfall-Stop je Position (x Tages-ATR), Konto-Rueckgang- |
//|   Schalter (alles schliessen, Handel stoppen).                   |
//|                                                                  |
//| Nur EIN Chart (beliebiges Symbol/Zeitrahmen), der EA handelt     |
//| alle Paare aus InpPairs. Der MT4-Strategietester kann keine      |
//| Mehr-Paar-EAs pruefen -> Backtest: research/fx_factor.py         |
//| Standardmaessig nur auf Demokonten aktiv.                        |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor"
#property version   "1.00"
#property strict
#property description "Waehrungs-Faktor-Portfolio (Carry + Momentum + Value), monatliche Umschichtung."
#property description "Ein Chart genuegt - der EA handelt alle Paare aus der Liste. Standardmaessig nur Demo."

input string InpSepGeneral       = "===== Allgemein =====";   // -----
input int    InpMagicNumber      = 290101;     // Magic Number
input string InpTradeComment     = "FXFactor"; // Order-Kommentar
input bool   InpAllowRealAccount = false;      // Auf Echtgeld-Konto handeln
input bool   InpTradeEnabled     = true;       // Handeln (false = nur berechnen und anzeigen)
input string InpPairs            = "EURUSD,GBPUSD,AUDUSD,NZDUSD,USDJPY,USDCHF,USDCAD"; // Paare (alle gegen USD)
input string InpSymbolSuffix     = "";         // Symbol-Endung des Brokers (z. B. ".r" oder "m")
input double InpSlippagePips     = 2.0;        // Max. Slippage (Pips)

input string InpSepSignals       = "===== Signale ====="; // -----
enum ENUM_CARRY_SRC { CARRY_SWAP = 0, CARRY_MANUAL = 1 };
input bool   InpUseCarry         = true;       // Carry verwenden
input bool   InpUseMomentum      = true;       // Momentum verwenden
input bool   InpUseValue         = true;       // Value-Umkehr verwenden
input ENUM_CARRY_SRC InpCarrySource = CARRY_SWAP; // Carry-Quelle: Swaps des Brokers / manuelle Leitzinsen
input string InpManualRates      = "USD=3.75,EUR=2.00,GBP=4.00,JPY=0.50,CHF=0.00,AUD=3.60,NZD=2.25,CAD=2.25"; // Leitzinsen in % (bei manuell)
input int    InpMomentumDays     = 63;         // Momentum-Rueckblick (Handelstage, 63 = 3 Monate)
input int    InpValueDays        = 756;        // Value-Rueckblick (Handelstage, 756 = 36 Monate)

input string InpSepRisk          = "===== Risiko ====="; // -----
input double InpTargetVol        = 6.0;        // Ziel-Volatilitaet des Portfolios (% pro Jahr)
input int    InpVolDays          = 60;         // Volatilitaets-Rueckblick (Handelstage)
input double InpMaxGross         = 3.0;        // Max. Summe aller Positionen / Kapital (Hebel)
input double InpRebalanceBand    = 0.25;       // Anpassen erst ab Abweichung > Anteil der Zielgroesse
input double InpEmergencyStopAtr = 8.0;        // Notfall-Stop je Position (x Tages-ATR 20, 0 = aus)
input double InpMaxDrawdown      = 20.0;       // Konto-Rueckgang vom Hoechststand in % -> alles schliessen
input bool   InpResetHalt        = false;      // Gestoppten Handel wieder freigeben (einmalig auf true)
input int    InpRebalanceHour    = 10;         // Umschichtung ab dieser Stunde (Server-Zeit)

#define MAXC 16

string g_pairs[];          // Symbolnamen inkl. Endung
string g_ccy[];            // Waehrung je Paar (ohne USD)
int    g_sign[];           // +1: Paar long = Waehrung long (EURUSD), -1: USDJPY
int    g_n = 0;            // Anzahl Paare
double g_carry[MAXC], g_mom[MAXC], g_val[MAXC], g_score[MAXC], g_w[MAXC];
bool   g_haveMom = false, g_haveVal = false;
double g_vol = 0.0, g_scale = 0.0;
string g_status = "";
string g_gvMonth, g_gvPeak, g_gvHalt;

//+------------------------------------------------------------------+
int OnInit()
{
   if(!IsDemo() && !InpAllowRealAccount && !IsTesting())
   {
      Alert("FX_FactorBasket: Echtgeld-Konto erkannt - der EA bleibt inaktiv (InpAllowRealAccount).");
      return INIT_FAILED;
   }
   if(IsTesting())
      Print("Hinweis: Der MT4-Strategietester kann keine Mehr-Paar-EAs pruefen. Backtest: research/fx_factor.py");

   string parts[];
   int k = StringSplit(InpPairs, ',', parts);
   g_n = 0;
   ArrayResize(g_pairs, k); ArrayResize(g_ccy, k); ArrayResize(g_sign, k);
   for(int i = 0; i < k && g_n < MAXC - 1; i++)
   {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p); StringToUpper(p);
      if(StringLen(p) != 6) continue;
      if(StringSubstr(p, 0, 3) == "USD")      { g_ccy[g_n] = StringSubstr(p, 3, 3); g_sign[g_n] = -1; }
      else if(StringSubstr(p, 3, 3) == "USD") { g_ccy[g_n] = StringSubstr(p, 0, 3); g_sign[g_n] = 1; }
      else { Alert("FX_FactorBasket: ", p, " ist kein USD-Paar - wird ignoriert."); continue; }
      g_pairs[g_n] = p + InpSymbolSuffix;
      if(!SymbolSelect(g_pairs[g_n], true) || MarketInfo(g_pairs[g_n], MODE_POINT) <= 0)
      {
         Alert("FX_FactorBasket: Symbol ", g_pairs[g_n], " nicht gefunden (Symbol-Endung pruefen).");
         return INIT_FAILED;
      }
      g_n++;
   }
   if(g_n < 3)
   {
      Alert("FX_FactorBasket: Mindestens 3 USD-Paare noetig.");
      return INIT_FAILED;
   }

   string pre = "FXF_" + IntegerToString(InpMagicNumber) + "_";
   g_gvMonth = pre + "month";
   g_gvPeak  = pre + "peak";
   g_gvHalt  = pre + "halt";
   if(InpResetHalt)
   {
      GlobalVariableDel(g_gvHalt);
      GlobalVariableSet(g_gvPeak, AccountEquity());
   }
   if(!GlobalVariableCheck(g_gvPeak))
      GlobalVariableSet(g_gvPeak, AccountEquity());

   EventSetTimer(60);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); Comment(""); }
void OnTick()  { Process(); }
void OnTimer() { Process(); }

//+------------------------------------------------------------------+
void Process()
{
   if(!CheckDrawdown()) { UpdatePanel(); return; }

   int month = TimeYear(TimeCurrent()) * 100 + TimeMonth(TimeCurrent());
   int dow   = TimeDayOfWeek(TimeCurrent());
   bool due  = (int)GlobalVariableGet(g_gvMonth) != month && dow >= 1 && dow <= 5 &&
               TimeHour(TimeCurrent()) >= InpRebalanceHour;

   if(due)
   {
      if(ComputeTargets())
      {
         if(!InpTradeEnabled || Rebalance())
         {
            GlobalVariableSet(g_gvMonth, month);
            g_status = "Umgeschichtet am " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) +
                       (InpTradeEnabled ? "" : " (nur Berechnung)");
         }
      }
   }
   else if(g_scale == 0.0)
      ComputeTargets();   // nach Neustart: Ziele fuer die Anzeige berechnen
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Konto-Rueckgang-Schalter                                         |
//+------------------------------------------------------------------+
bool CheckDrawdown()
{
   if(GlobalVariableCheck(g_gvHalt))
   {
      g_status = "GESTOPPT: max. Rueckgang erreicht - zum Fortsetzen InpResetHalt = true";
      return false;
   }
   double eq = AccountEquity();
   double peak = MathMax(GlobalVariableGet(g_gvPeak), eq);
   GlobalVariableSet(g_gvPeak, peak);
   if(InpMaxDrawdown > 0 && eq < peak * (1.0 - InpMaxDrawdown / 100.0))
   {
      Print("Max. Rueckgang erreicht (", DoubleToString(100 * (1 - eq / peak), 1), " %) - alle Positionen werden geschlossen.");
      for(int i = 0; i < g_n; i++) CloseAll(g_pairs[i]);
      GlobalVariableSet(g_gvHalt, 1);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Waehrungskurs in USD (Tages-Schluss, shift)                      |
//+------------------------------------------------------------------+
double CcyPrice(int i, int shift)
{
   double c = iClose(g_pairs[i], PERIOD_D1, shift);
   if(c <= 0) return 0.0;
   return g_sign[i] > 0 ? c : 1.0 / c;
}

//+------------------------------------------------------------------+
//| Carry je Waehrung: Zinsvorteil gegenueber USD in % p.a.          |
//+------------------------------------------------------------------+
double CarryFromSwap(int i)
{
   string s = g_pairs[i];
   double sl = MarketInfo(s, MODE_SWAPLONG), ss = MarketInfo(s, MODE_SWAPSHORT);
   double mid = (sl - ss) / 2.0;   // Aufschlag des Brokers faellt bei der Mitte heraus
   double pct = 0.0;
   int type = (int)MarketInfo(s, MODE_SWAPTYPE);
   double price = MarketInfo(s, MODE_BID), cs = MarketInfo(s, MODE_LOTSIZE);
   if(type == 0)      pct = mid * MarketInfo(s, MODE_POINT) / price * 365.0 * 100.0;   // Punkte
   else if(type == 2) pct = mid;                                                       // Zins % p.a.
   else               pct = mid / cs * 365.0 * 100.0;                                  // Geld in Basis-/Marginwaehrung
   return g_sign[i] * pct;          // Paar long = Basis long; fuer USDxxx umdrehen
}

double ManualRate(string ccy)
{
   string parts[];
   int k = StringSplit(InpManualRates, ',', parts);
   for(int i = 0; i < k; i++)
   {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p); StringToUpper(p);
      if(StringSubstr(p, 0, 3) == ccy && StringFind(p, "=") == 3)
         return StringToDouble(StringSubstr(p, 4));
   }
   Print("Kein manueller Leitzins fuer ", ccy, " - 0 angenommen.");
   return 0.0;
}

//+------------------------------------------------------------------+
//| z-Werte ueber alle Waehrungen (n Paare + USD mit Wert 0)         |
//+------------------------------------------------------------------+
void AddZ(const double &x[], double &acc[])
{
   int m = g_n + 1;
   double v[MAXC];
   for(int i = 0; i < g_n; i++) v[i] = x[i];
   v[g_n] = 0.0;
   double mean = 0, sd = 0;
   for(int i = 0; i < m; i++) mean += v[i];
   mean /= m;
   for(int i = 0; i < m; i++) sd += (v[i] - mean) * (v[i] - mean);
   sd = MathSqrt(sd / m);
   if(sd <= 0) return;
   for(int i = 0; i < m; i++) acc[i] += (v[i] - mean) / sd;
}

//+------------------------------------------------------------------+
//| Signale und Zielgewichte berechnen                               |
//+------------------------------------------------------------------+
bool ComputeTargets()
{
   int need = MathMax(InpMomentumDays, InpVolDays) + 2;
   for(int i = 0; i < g_n; i++)
      if(iBars(g_pairs[i], PERIOD_D1) < need || CcyPrice(i, 1) <= 0)
      {
         g_status = "Lade Tages-Historie fuer " + g_pairs[i] + " ...";
         return false;
      }

   double usdRate = (InpCarrySource == CARRY_MANUAL) ? ManualRate("USD") : 0.0;
   g_haveMom = InpUseMomentum;
   g_haveVal = InpUseValue;
   for(int i = 0; i < g_n; i++)
   {
      double p1 = CcyPrice(i, 1);
      g_carry[i] = (InpCarrySource == CARRY_MANUAL) ? ManualRate(g_ccy[i]) - usdRate : CarryFromSwap(i);
      double pm = CcyPrice(i, 1 + InpMomentumDays);
      g_mom[i] = pm > 0 ? p1 / pm - 1.0 : 0.0;
      if(pm <= 0) g_haveMom = false;
      double pv = (iBars(g_pairs[i], PERIOD_D1) > InpValueDays + 2) ? CcyPrice(i, 1 + InpValueDays) : 0.0;
      g_val[i] = pv > 0 ? -(p1 / pv - 1.0) : 0.0;
      if(pv <= 0) g_haveVal = false;          // zu wenig Historie -> Value fuer alle aus
   }

   double acc[MAXC];
   ArrayInitialize(acc, 0.0);
   int used = 0;
   if(InpUseCarry) { AddZ(g_carry, acc); used++; }
   if(g_haveMom)   { AddZ(g_mom, acc);   used++; }
   if(g_haveVal)   { AddZ(g_val, acc);   used++; }
   if(used == 0)
   {
      g_status = "Kein Signal aktiv";
      return false;
   }
   double mean = 0;
   for(int i = 0; i <= g_n; i++) { acc[i] /= used; mean += acc[i]; }
   mean /= (g_n + 1);
   for(int i = 0; i <= g_n; i++) g_score[i] = acc[i] - mean;

   //--- Volatilitaet des Portfolios mit diesen Gewichten (letzte InpVolDays Tage)
   double sum = 0, sum2 = 0;
   for(int d = 1; d <= InpVolDays; d++)
   {
      double r = 0;
      for(int i = 0; i < g_n; i++)
      {
         double a = CcyPrice(i, d), b = CcyPrice(i, d + 1);
         if(a <= 0 || b <= 0) { g_status = "Luecke in der Historie von " + g_pairs[i]; return false; }
         r += g_score[i] * (a / b - 1.0);
      }
      sum += r; sum2 += r * r;
   }
   double var = sum2 / InpVolDays - (sum / InpVolDays) * (sum / InpVolDays);
   g_vol = MathSqrt(MathMax(var, 0.0)) * MathSqrt(260.0);
   if(g_vol <= 0) { g_status = "Volatilitaet = 0"; return false; }

   g_scale = InpTargetVol / 100.0 / g_vol;
   double gross = 0;
   for(int i = 0; i < g_n; i++) gross += MathAbs(g_score[i]) * g_scale;
   if(gross > InpMaxGross) g_scale *= InpMaxGross / gross;
   for(int i = 0; i < g_n; i++) g_w[i] = g_score[i] * g_scale;
   return true;
}

//+------------------------------------------------------------------+
//| Lots fuer einen Nominalwert (Anteil am Kapital) im Paar          |
//+------------------------------------------------------------------+
double LotsForWeight(string s, double w)
{
   double tv = MarketInfo(s, MODE_TICKVALUE), ts = MarketInfo(s, MODE_TICKSIZE);
   double price = MarketInfo(s, MODE_BID);
   if(tv <= 0 || ts <= 0 || price <= 0) return 0.0;
   double lotValue = price * tv / ts;          // Nominal eines Lots in Kontowaehrung
   return w * AccountEquity() / lotValue;
}

double NetLots(string s)
{
   double net = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != s || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() == OP_BUY)  net += OrderLots();
      if(OrderType() == OP_SELL) net -= OrderLots();
   }
   return net;
}

//+------------------------------------------------------------------+
//| Alle Paare auf ihr Ziel bringen                                  |
//+------------------------------------------------------------------+
bool Rebalance()
{
   bool ok = true;
   for(int i = 0; i < g_n; i++)
   {
      string s = g_pairs[i];
      if(MarketInfo(s, MODE_TRADEALLOWED) == 0) { g_status = s + ": Handel geschlossen"; return false; }
      double step = MarketInfo(s, MODE_LOTSTEP), minLot = MarketInfo(s, MODE_MINLOT);
      if(step <= 0) step = 0.01;
      double target = LotsForWeight(s, g_sign[i] * g_w[i]);     // USDxxx: Waehrung long = Paar short
      target = MathRound(target / step) * step;
      if(MathAbs(target) < minLot) target = 0.0;
      double cur = NetLots(s);
      double diff = target - cur;

      if(MathAbs(diff) < step / 2) continue;
      if(target != 0 && cur != 0 && target * cur > 0 && MathAbs(diff) <= InpRebalanceBand * MathAbs(target))
         continue;   // Abweichung klein -> Kosten sparen

      if(cur != 0 && (target == 0 || target * cur < 0))
      {
         if(!CloseAll(s)) ok = false;
         cur = 0;
      }
      if(MathAbs(target) < MathAbs(cur))
         { if(!Reduce(s, MathAbs(cur) - MathAbs(target), step)) ok = false; }
      else if(MathAbs(target) > MathAbs(cur))
         { if(!Open(s, target > 0 ? OP_BUY : OP_SELL, MathAbs(target) - MathAbs(cur), step, minLot)) ok = false; }
   }
   return ok;
}

//+------------------------------------------------------------------+
bool Open(string s, int type, double lots, double step, double minLot)
{
   lots = MathFloor(lots / step + 1e-9) * step;
   lots = MathMin(lots, MarketInfo(s, MODE_MAXLOT));
   if(lots < minLot) return true;
   int digits = (int)MarketInfo(s, MODE_DIGITS);
   double point = MarketInfo(s, MODE_POINT);
   double pip = (digits == 3 || digits == 5) ? point * 10 : point;
   int slip = (int)MathRound(InpSlippagePips * pip / point);
   double price = (type == OP_BUY) ? MarketInfo(s, MODE_ASK) : MarketInfo(s, MODE_BID);

   int ticket = OrderSend(s, type, NormalizeDouble(lots, 2), NormalizeDouble(price, digits), slip, 0, 0,
                          InpTradeComment, InpMagicNumber, 0, type == OP_BUY ? clrDodgerBlue : clrOrangeRed);
   if(ticket < 0)
   {
      Print(s, ": OrderSend fehlgeschlagen, Fehler ", GetLastError());
      return false;
   }
   if(InpEmergencyStopAtr <= 0 || !OrderSelect(ticket, SELECT_BY_TICKET)) return true;

   double dist = InpEmergencyStopAtr * iATR(s, PERIOD_D1, 20, 1);
   if(dist <= 0) dist = 0.05 * OrderOpenPrice();
   double sl = NormalizeDouble(type == OP_BUY ? OrderOpenPrice() - dist : OrderOpenPrice() + dist, digits);
   for(int a = 0; a < 5; a++)
   {
      if(OrderModify(ticket, OrderOpenPrice(), sl, 0, 0, clrNONE)) return true;
      Print(s, ": Notfall-Stop setzen fehlgeschlagen, Fehler ", GetLastError());
      Sleep(300);
   }
   Print("ACHTUNG: ", s, " Notfall-Stop nicht gesetzt - Position wird geschlossen.");
   CloseTicket(ticket, OrderLots());
   return false;
}

//+------------------------------------------------------------------+
bool Reduce(string s, double lots, double step)
{
   lots = MathRound(lots / step) * step;
   for(int i = OrdersTotal() - 1; i >= 0 && lots >= step / 2; i--)   // neueste zuerst
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != s || OrderMagicNumber() != InpMagicNumber || OrderType() > OP_SELL) continue;
      double part = MathMin(OrderLots(), lots);
      if(part < MarketInfo(s, MODE_MINLOT)) break;
      if(!CloseTicket(OrderTicket(), part)) return false;
      lots -= part;
   }
   return true;
}

bool CloseAll(string s)
{
   bool ok = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != s || OrderMagicNumber() != InpMagicNumber || OrderType() > OP_SELL) continue;
      if(!CloseTicket(OrderTicket(), OrderLots())) ok = false;
   }
   return ok;
}

bool CloseTicket(int ticket, double lots)
{
   for(int a = 0; a < 3; a++)
   {
      if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() != 0) return true;
      string s = OrderSymbol();
      int digits = (int)MarketInfo(s, MODE_DIGITS);
      double point = MarketInfo(s, MODE_POINT);
      double pip = (digits == 3 || digits == 5) ? point * 10 : point;
      double price = OrderType() == OP_BUY ? MarketInfo(s, MODE_BID) : MarketInfo(s, MODE_ASK);
      if(OrderClose(ticket, NormalizeDouble(lots, 2), NormalizeDouble(price, digits),
                    (int)MathRound(InpSlippagePips * pip / point), clrYellow))
         return true;
      Print(s, ": OrderClose fehlgeschlagen, Fehler ", GetLastError());
      Sleep(300);
      RefreshRates();
   }
   return false;
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(IsTesting() && !IsVisualMode()) return;
   string txt = "\n  FX Faktor-Portfolio (Carry + Momentum + Value)\n"
                "  ------------------------------------------------------\n"
                "  Status : " + g_status + "\n"
                "  Signale: Carry " + (InpUseCarry ? (InpCarrySource == CARRY_SWAP ? "(Swap)" : "(manuell)") : "aus") +
                " | Momentum " + (g_haveMom ? "an" : "aus") + " | Value " + (g_haveVal ? "an" : "aus (Historie?)") + "\n"
                "  Vol. (Gewichte ungeskaliert) " + DoubleToString(g_vol * 100, 2) + " %  ->  Faktor " +
                DoubleToString(g_scale, 2) + "  (Ziel " + DoubleToString(InpTargetVol, 1) + " %)\n\n"
                "  Waehrung  Carry%   Mom%   Value%   Ziel%   Lots ist\n";
   double gross = 0;
   for(int i = 0; i < g_n; i++)
   {
      gross += MathAbs(g_w[i]);
      txt += StringFormat("  %s      %+6.2f  %+6.1f  %+7.1f  %+6.0f   %+.2f (%s)\n", g_ccy[i], g_carry[i],
                          g_mom[i] * 100, g_val[i] * 100, g_w[i] * 100, NetLots(g_pairs[i]), g_pairs[i]);
   }
   double wUsd = 0;
   for(int i = 0; i < g_n; i++) wUsd -= g_w[i];
   txt += StringFormat("  USD                                    %+6.0f\n", wUsd * 100);
   txt += "\n  Brutto-Hebel " + DoubleToString(gross, 2) + "  |  Konto " + (IsDemo() ? "Demo" : "ECHTGELD") +
          "  |  Hoechststand " + DoubleToString(GlobalVariableGet(g_gvPeak), 2);
   Comment(txt);
}
//+------------------------------------------------------------------+
