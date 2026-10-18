//+------------------------------------------------------------------+
//|                                           MACD_RSI_Trend_EA.mq5  |
//|                    Estratégia Bidirecional (Compra e Venda)       |
//|               Tendência EMA9/SMA20 + Confirmação MACD/RSI + RR 3:1|
//|               Trailing Stop Conduzido pela SMA 20 após 1:1 Lucro  |
//|               Painel Visual Gráfico Profissional (Dashboard HUD)  |
//+------------------------------------------------------------------+
#property copyright "Desenvolvido para automação Forex MT5"
#property link      ""
#property version   "2.00"
#property description "Estratégia Completa Compra e Venda MACD + RSI"
#property description "EMA9/SMA20 + MACD/RSI + RR 3:1 + Trailing SMA20"
#property description "Painel Visual Gráfico Profissional com Métricas em Tempo Real"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Modos de Operação
enum ENUM_TRADE_DIRECTION
{
   DIRECTION_BOTH      = 0, // Comprar e Vender
   DIRECTION_BUY_ONLY  = 1, // Apenas Compras
   DIRECTION_SELL_ONLY = 2  // Apenas Vendas
};

//--- Estados da Estratégia de Compra
enum ENUM_BUY_STATE
{
   BUY_STATE_IDLE                  = 0,
   BUY_STATE_WAITING_BEARISH_CROSS = 1,
   BUY_STATE_COUNTING_DOWN_BARS    = 2,
   BUY_STATE_ARMED                 = 3
};

//--- Estados da Estratégia de Venda
enum ENUM_SELL_STATE
{
   SELL_STATE_IDLE                  = 0,
   SELL_STATE_WAITING_BULLISH_CROSS = 1,
   SELL_STATE_COUNTING_UP_BARS      = 2,
   SELL_STATE_ARMED                 = 3
};

//--- Estrutura para estatísticas de desempenho
struct SPerformanceMetrics
{
   int    totalTrades;
   int    wins;
   int    losses;
   double winRate;
   int    winStreak;
   int    lossStreak;
   double todayProfit;
   double totalNetProfit;
};

//+------------------------------------------------------------------+
//| INPUTS / PARÂMETROS                                              |
//+------------------------------------------------------------------+
input group "=== Direção Operacional ==="
input ENUM_TRADE_DIRECTION InpTradeDirection = DIRECTION_BOTH; // Direção permitida

input group "=== Configurações de Lote & Risco ==="
input bool   InpUseMoneyManagement  = false;     // Usar Risco Percentual (%)
input double InpRiskPercent         = 1.0;       // Risco por operação (% da conta)
input double InpFixedLot            = 0.01;      // Lote Fixo
input ulong  InpMagicNumber         = 987654;    // Magic Number do EA
input ulong  InpSlippage            = 10;        // Desvio máximo de preço (pontos)
input string InpTradeCommentBuy     = "MACD_RSI_Buy";  // Comentário Compra
input string InpTradeCommentSell    = "MACD_RSI_Sell"; // Comentário Venda

input group "=== Médias Móveis ==="
input int                InpEMA_Period  = 9;           // Período EMA Rápida
input ENUM_MA_METHOD     InpEMA_Method  = MODE_EMA;    // Método EMA
input int                InpSMA_Period  = 20;          // Período SMA Lenta
input ENUM_MA_METHOD     InpSMA_Method  = MODE_SMA;    // Método SMA
input ENUM_APPLIED_PRICE InpMA_Applied  = PRICE_CLOSE; // Preço Aplicado

input group "=== MACD ==="
input int                InpMACD_Fast    = 12;          // Fast EMA
input int                InpMACD_Slow    = 26;          // Slow EMA
input int                InpMACD_Signal  = 9;           // Signal SMA
input ENUM_APPLIED_PRICE InpMACD_Applied = PRICE_CLOSE; // Preço Aplicado

input group "=== RSI ==="
input int                InpRSI_Period         = 14;          // Período RSI
input ENUM_APPLIED_PRICE InpRSI_Applied        = PRICE_CLOSE; // Preço Aplicado
input double             InpRSI_Threshold_Buy  = 70.0;        // Nível Compra (> 70)
input double             InpRSI_Threshold_Sell = 30.0;        // Nível Venda (< 30)

input group "=== Regras da Estratégia ==="
input int    InpMinCorrectionBars    = 3;        // Mínimo de barras na correção
input int    InpLookbackBarsSL       = 20;       // Velas para Stop Loss (Mín/Máx)
input double InpRiskRewardRatio      = 3.0;      // Relação Risco:Retorno (3:1)
input int    InpMaxBarsTimeout       = 60;       // Timeout de velas (0 = sem timeout)
input bool   InpAllowOnlyOnePosition = true;     // Apenas 1 posição por vez

input group "=== Stop Loss Móvel (Trailing SMA 20) ==="
input bool   InpUseTrailingSMA       = true;     // Ativar Trailing Stop SMA 20
input double InpTrailingTriggerRR    = 1.0;      // Ativar quando lucro atingir 1:1
input double InpTrailingDistancePips = 20.0;     // Distância do Stop atrás da SMA20 (pips)
input bool   InpProtectBreakEven     = true;     // Nunca deixar SL atrás da entrada

input group "=== Painel Visual (Dashboard) ==="
input bool   InpShowDashboard        = true;     // Ativar Painel Visual Profissional
input int    InpDashboardX           = 15;       // Posição X (pixels)
input int    InpDashboardY           = 15;       // Posição Y (pixels)
input bool   InpVerboseLogs          = false;    // Logs detalhados no Diário

//+------------------------------------------------------------------+
//| VARIÁVEIS GLOBAIS                                                |
//+------------------------------------------------------------------+
CTrade        trade;
CPositionInfo positionInfo;

int handleEMA  = INVALID_HANDLE;
int handleSMA  = INVALID_HANDLE;
int handleMACD = INVALID_HANDLE;
int handleRSI  = INVALID_HANDLE;

datetime lastBarTime = 0;
ulong    lastDashboardUpdate = 0;

ENUM_BUY_STATE  buyState  = BUY_STATE_IDLE;
ENUM_SELL_STATE sellState = SELL_STATE_IDLE;

int buyDownBarsCounter   = 0;
int buyBarsSinceSignal1  = 0;
int sellUpBarsCounter    = 0;
int sellBarsSinceSignal1 = 0;

double cacheEMA = 0, cacheSMA = 0, cacheMACDMain = 0, cacheMACDSignal = 0, cacheRSI = 0;
bool   isVisualAllowed = true;
bool   dashboardCreated = false;

// Cores temáticas da identidade visual moderna (Dark Slate)
#define COLOR_PANEL_BG       C'18,22,32'     // Fundo principal escuro
#define COLOR_PANEL_BORDER   C'45,55,75'     // Borda sutil do painel
#define COLOR_HEADER_BG      C'26,34,50'     // Fundo do cabeçalho
#define COLOR_CARD_BG        C'24,30,44'     // Fundo de cada bloco/card
#define COLOR_CARD_BORDER    C'38,48,68'     // Borda dos blocos

// Cores de status conforme classificação solicitada:
#define COLOR_GREEN_TEXT     C'0,225,120'    // Verde: condições confirmadas, vitórias, lucro
#define COLOR_RED_TEXT       C'255,85,85'    // Vermelho: negativas, perdas, stops, venda
#define COLOR_AMBER_TEXT     C'255,185,50'   // Amarelo/Laranja: em análise, gatilho armado
#define COLOR_BLUE_TEXT      C'64,196,255'   // Azul/Ciano: neutro, dados do sistema, títulos
#define COLOR_WHITE_TEXT     C'240,244,250'  // Branco: valores principais
#define COLOR_GRAY_TEXT      C'140,152,172'  // Cinza: rótulos secundários

// Prefixo único para os objetos gráficos do painel
#define DASH_PREFIX "DASH_MR_"

//+------------------------------------------------------------------+
//| Retorna tamanho de 1 pip adaptado para qualquer ativo            |
//+------------------------------------------------------------------+
double GetPipSize()
{
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(digits == 2 || digits == 3 || digits == 5)
      return point * 10.0;
   return point;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   bool isTester = (bool)MQLInfoInteger(MQL_TESTER);
   bool isVisual = (bool)MQLInfoInteger(MQL_VISUAL_MODE);
   isVisualAllowed = (!isTester || isVisual) && InpShowDashboard;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   handleEMA = iMA(_Symbol, _Period, InpEMA_Period, 0, InpEMA_Method, InpMA_Applied);
   if(handleEMA == INVALID_HANDLE) { Print("Erro ao criar EMA"); return INIT_FAILED; }

   handleSMA = iMA(_Symbol, _Period, InpSMA_Period, 0, InpSMA_Method, InpMA_Applied);
   if(handleSMA == INVALID_HANDLE) { Print("Erro ao criar SMA"); return INIT_FAILED; }

   handleMACD = iMACD(_Symbol, _Period, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, InpMACD_Applied);
   if(handleMACD == INVALID_HANDLE) { Print("Erro ao criar MACD"); return INIT_FAILED; }

   handleRSI = iRSI(_Symbol, _Period, InpRSI_Period, InpRSI_Applied);
   if(handleRSI == INVALID_HANDLE) { Print("Erro ao criar RSI"); return INIT_FAILED; }

   // Constrói os objetos visuais se permitido
   if(isVisualAllowed)
   {
      DestroyDashboard();
      CreateDashboardUI();
   }

   PrintFormat("EA MACD+RSI v2.00 (Dashboard Profissional) iniciado em %s %s", _Symbol, EnumToString(_Period));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA  != INVALID_HANDLE) IndicatorRelease(handleEMA);
   if(handleSMA  != INVALID_HANDLE) IndicatorRelease(handleSMA);
   if(handleMACD != INVALID_HANDLE) IndicatorRelease(handleMACD);
   if(handleRSI  != INVALID_HANDLE) IndicatorRelease(handleRSI);

   DestroyDashboard();
   Comment("");
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   bool hasPosition = HasOpenPosition();

   datetime barTime = iTime(_Symbol, _Period, 0);
   bool isNewBar    = (barTime != 0 && barTime != lastBarTime);

   // Gerencia o Trailing Stop imediatamente quando há posição aberta
   if(hasPosition && InpUseTrailingSMA)
   {
      ManageTrailingStop(isNewBar);
   }

   // Atualização em tempo real do painel visual quando há posição aberta (a cada 250ms)
   if(isVisualAllowed && hasPosition)
   {
      ulong now = GetTickCount64();
      if(now - lastDashboardUpdate >= 250)
      {
         lastDashboardUpdate = now;
         UpdateDashboardUI();
      }
   }

   // Se não é nova barra, encerra o tick aqui para economizar processamento
   if(!isNewBar)
      return;

   lastBarTime = barTime;

   // Atualiza os indicadores para nova barra
   UpdateIndicatorValues();

   // Se só é permitida 1 posição e já temos posição aberta:
   if(InpAllowOnlyOnePosition && hasPosition)
   {
      if(buyState  != BUY_STATE_IDLE)  { buyState  = BUY_STATE_IDLE;  buyDownBarsCounter=0;  buyBarsSinceSignal1=0;  }
      if(sellState != SELL_STATE_IDLE) { sellState = SELL_STATE_IDLE; sellUpBarsCounter=0; sellBarsSinceSignal1=0; }
      if(isVisualAllowed) UpdateDashboardUI();
      return;
   }

   // Processa estratégia no candle recém-fechado
   ProcessStrategyLogic();

   // Atualiza o painel visual
   if(isVisualAllowed)
   {
      UpdateDashboardUI();
   }
}

//+------------------------------------------------------------------+
//| Atualiza valores dos indicadores no candle fechado (shift=1)     |
//+------------------------------------------------------------------+
void UpdateIndicatorValues()
{
   double tmp[1];
   if(CopyBuffer(handleEMA,  0, 1, 1, tmp) > 0) cacheEMA       = tmp[0];
   if(CopyBuffer(handleSMA,  0, 1, 1, tmp) > 0) cacheSMA       = tmp[0];
   if(CopyBuffer(handleMACD, 0, 1, 1, tmp) > 0) cacheMACDMain  = tmp[0];
   if(CopyBuffer(handleMACD, 1, 1, 1, tmp) > 0) cacheMACDSignal= tmp[0];
   if(CopyBuffer(handleRSI,  0, 1, 1, tmp) > 0) cacheRSI       = tmp[0];
}

//+------------------------------------------------------------------+
//| Verifica se há posições abertas pelo EA                          |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && (positionInfo.Magic() == InpMagicNumber || positionInfo.Magic() == 0))
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| TRAILING STOP MÓVEL — Conduzido pela SMA 20 após lucro 1:1       |
//+------------------------------------------------------------------+
void ManageTrailingStop(bool isNewBar)
{
   // Lê o valor da SMA 20 em tempo real (shift 0)
   double smaBuf[1];
   if(CopyBuffer(handleSMA, 0, 0, 1, smaBuf) < 1) return;

   double sma      = smaBuf[0];
   int    digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pipSize  = GetPipSize();
   double offset   = InpTrailingDistancePips * pipSize;
   double stoplvl  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(positionInfo.Symbol() != _Symbol) continue;
      if(positionInfo.Magic() != InpMagicNumber && positionInfo.Magic() != 0) continue;

      ulong              ticket   = positionInfo.Ticket();
      ENUM_POSITION_TYPE posType  = positionInfo.PositionType();
      double             openPr   = positionInfo.PriceOpen();
      double             currSL   = positionInfo.StopLoss();
      double             currTP   = positionInfo.TakeProfit();

      double initRisk = 0.0;
      if(currTP > 0.0)      initRisk = MathAbs(currTP - openPr) / InpRiskRewardRatio;
      else if(currSL > 0.0) initRisk = MathAbs(openPr - currSL);
      if(initRisk <= 0.0) continue;

      //-------------------------------------------------------------
      // COMPRA (LONG)
      //-------------------------------------------------------------
      if(posType == POSITION_TYPE_BUY)
      {
         double profit = bid - openPr;
         bool reached1to1 = (profit >= (initRisk * InpTrailingTriggerRR)) || (currSL >= openPr);

         if(reached1to1)
         {
            double newSL = NormalizeDouble(sma - offset, digits);
            if(InpProtectBreakEven && newSL < openPr)
               newSL = openPr;

            if(newSL > (currSL + point) && (bid - newSL) > stoplvl)
            {
               if(trade.PositionModify(ticket, newSL, currTP))
               {
                  if(InpVerboseLogs)
                     PrintFormat("[TRAILING BUY] Ticket #%d: SL movido de %.*f para %.*f (SMA20=%.*f)",
                                 ticket, digits, currSL, digits, newSL, digits, sma);
               }
            }
         }
      }
      //-------------------------------------------------------------
      // VENDA (SHORT)
      //-------------------------------------------------------------
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit = openPr - ask;
         bool reached1to1 = (profit >= (initRisk * InpTrailingTriggerRR)) || (currSL > 0.0 && currSL <= openPr);

         if(reached1to1)
         {
            double newSL = NormalizeDouble(sma + offset, digits);
            if(InpProtectBreakEven && newSL > openPr)
               newSL = openPr;

            if((currSL == 0.0 || newSL < (currSL - point)) && (newSL - ask) > stoplvl)
            {
               if(trade.PositionModify(ticket, newSL, currTP))
               {
                  if(InpVerboseLogs)
                     PrintFormat("[TRAILING SELL] Ticket #%d: SL movido de %.*f para %.*f (SMA20=%.*f)",
                                 ticket, digits, currSL, digits, newSL, digits, sma);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Processa a lógica de Compra e Venda nos candles fechados         |
//+------------------------------------------------------------------+
void ProcessStrategyLogic()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int neededRates = InpLookbackBarsSL + 2;
   if(CopyRates(_Symbol, _Period, 1, neededRates, rates) < neededRates)
      return;

   double emaBuf[], smaBuf[], macdMainBuf[], macdSigBuf[], rsiBuf[];
   ArraySetAsSeries(emaBuf, true);
   ArraySetAsSeries(smaBuf, true);
   ArraySetAsSeries(macdMainBuf, true);
   ArraySetAsSeries(macdSigBuf, true);
   ArraySetAsSeries(rsiBuf, true);

   if(CopyBuffer(handleEMA,  0, 1, 3, emaBuf)      < 3) return;
   if(CopyBuffer(handleSMA,  0, 1, 3, smaBuf)      < 3) return;
   if(CopyBuffer(handleMACD, 0, 1, 3, macdMainBuf) < 3) return;
   if(CopyBuffer(handleMACD, 1, 1, 3, macdSigBuf)  < 3) return;
   if(CopyBuffer(handleRSI,  0, 1, 3, rsiBuf)      < 3) return;

   double close1    = rates[0].close;
   double ema1      = emaBuf[0];
   double sma1      = smaBuf[0];
   double macdMain1 = macdMainBuf[0];
   double macdSig1  = macdSigBuf[0];
   double rsi1      = rsiBuf[0];

   double macdMain2 = macdMainBuf[1];
   double macdSig2  = macdSigBuf[1];

   //================================================================
   // LÓGICA DE COMPRA (LONG)
   //================================================================
   if(InpTradeDirection == DIRECTION_BOTH || InpTradeDirection == DIRECTION_BUY_ONLY)
   {
      if(buyState != BUY_STATE_IDLE)
      {
         buyBarsSinceSignal1++;
         if(InpMaxBarsTimeout > 0 && buyBarsSinceSignal1 > InpMaxBarsTimeout)
            buyState = BUY_STATE_IDLE;
         else if(macdMain1 <= 0.0)
            buyState = BUY_STATE_IDLE;
      }

      switch(buyState)
      {
         case BUY_STATE_IDLE:
         {
            if(close1 > ema1 && ema1 > sma1 && macdMain1 > 0.0 && rsi1 > InpRSI_Threshold_Buy)
            {
               buyState = BUY_STATE_WAITING_BEARISH_CROSS;
               buyBarsSinceSignal1 = 0;
               buyDownBarsCounter = 0;
            }
            break;
         }
         case BUY_STATE_WAITING_BEARISH_CROSS:
         {
            if(macdMain1 < macdSig1 && macdMain2 >= macdSig2)
            {
               buyState = BUY_STATE_COUNTING_DOWN_BARS;
               buyDownBarsCounter = (macdMain1 < macdMain2) ? 1 : 0;
            }
            break;
         }
         case BUY_STATE_COUNTING_DOWN_BARS:
         {
            if(macdMain1 < macdMain2)
               buyDownBarsCounter++;

            if(macdMain1 > macdSig1 && macdMain2 <= macdSig2)
            {
               buyState = BUY_STATE_IDLE;
               break;
            }

            if(buyDownBarsCounter >= InpMinCorrectionBars)
               buyState = BUY_STATE_ARMED;
            break;
         }
         case BUY_STATE_ARMED:
         {
            if(macdMain1 > macdSig1 && macdMain2 <= macdSig2)
            {
               if(close1 > ema1)
               {
                  ExecuteBuyOrder(rates);
                  buyState = BUY_STATE_IDLE;
                  return;
               }
               else
               {
                  buyState = BUY_STATE_IDLE;
               }
            }
            break;
         }
      }
   }

   //================================================================
   // LÓGICA DE VENDA (SHORT)
   //================================================================
   if(InpTradeDirection == DIRECTION_BOTH || InpTradeDirection == DIRECTION_SELL_ONLY)
   {
      if(sellState != SELL_STATE_IDLE)
      {
         sellBarsSinceSignal1++;
         if(InpMaxBarsTimeout > 0 && sellBarsSinceSignal1 > InpMaxBarsTimeout)
            sellState = SELL_STATE_IDLE;
         else if(macdMain1 >= 0.0)
            sellState = SELL_STATE_IDLE;
      }

      switch(sellState)
      {
         case SELL_STATE_IDLE:
         {
            if(close1 < ema1 && ema1 < sma1 && macdMain1 < 0.0 && rsi1 < InpRSI_Threshold_Sell)
            {
               sellState = SELL_STATE_WAITING_BULLISH_CROSS;
               sellBarsSinceSignal1 = 0;
               sellUpBarsCounter = 0;
            }
            break;
         }
         case SELL_STATE_WAITING_BULLISH_CROSS:
         {
            if(macdMain1 > macdSig1 && macdMain2 <= macdSig2)
            {
               sellState = SELL_STATE_COUNTING_UP_BARS;
               sellUpBarsCounter = (macdMain1 > macdMain2) ? 1 : 0;
            }
            break;
         }
         case SELL_STATE_COUNTING_UP_BARS:
         {
            if(macdMain1 > macdMain2)
               sellUpBarsCounter++;

            if(macdMain1 < macdSig1 && macdMain2 >= macdSig2)
            {
               sellState = SELL_STATE_IDLE;
               break;
            }

            if(sellUpBarsCounter >= InpMinCorrectionBars)
               sellState = SELL_STATE_ARMED;
            break;
         }
         case SELL_STATE_ARMED:
         {
            if(macdMain1 < macdSig1 && macdMain2 >= macdSig2)
            {
               if(close1 < ema1)
               {
                  ExecuteSellOrder(rates);
                  sellState = SELL_STATE_IDLE;
                  return;
               }
               else
               {
                  sellState = SELL_STATE_IDLE;
               }
            }
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Executa COMPRA a mercado                                         |
//+------------------------------------------------------------------+
void ExecuteBuyOrder(const MqlRates &rates[])
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask <= 0.0) return;

   double low = rates[0].low;
   int lim = MathMin(InpLookbackBarsSL, ArraySize(rates));
   for(int i = 1; i < lim; i++) if(rates[i].low < low) low = rates[i].low;

   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double stoplvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double risk    = ask - low;

   if(risk <= stoplvl || risk <= 0.0)
   {
      risk = MathMax(stoplvl + 10*point, 20*point);
      low = NormalizeDouble(ask - risk, digits);
   }
   else low = NormalizeDouble(low, digits);

   double tp  = NormalizeDouble(ask + risk * InpRiskRewardRatio, digits);
   double lot = CalculateLotSize(risk);

   if(trade.Buy(lot, _Symbol, ask, low, tp, InpTradeCommentBuy))
      PrintFormat("[BUY] Lote=%.2f Preco=%.*f SL=%.*f TP=%.*f", lot, digits, ask, digits, low, digits, tp);
   else
      PrintFormat("[BUY ERRO] Retcode=%d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Executa VENDA a mercado                                          |
//+------------------------------------------------------------------+
void ExecuteSellOrder(const MqlRates &rates[])
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0) return;

   double high = rates[0].high;
   int lim = MathMin(InpLookbackBarsSL, ArraySize(rates));
   for(int i = 1; i < lim; i++) if(rates[i].high > high) high = rates[i].high;

   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double stoplvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double risk    = high - bid;

   if(risk <= stoplvl || risk <= 0.0)
   {
      risk = MathMax(stoplvl + 10*point, 20*point);
      high = NormalizeDouble(bid + risk, digits);
   }
   else high = NormalizeDouble(high, digits);

   double tp  = NormalizeDouble(bid - risk * InpRiskRewardRatio, digits);
   double lot = CalculateLotSize(risk);

   if(trade.Sell(lot, _Symbol, bid, high, tp, InpTradeCommentSell))
      PrintFormat("[SELL] Lote=%.2f Preco=%.*f SL=%.*f TP=%.*f", lot, digits, bid, digits, high, digits, tp);
   else
      PrintFormat("[SELL ERRO] Retcode=%d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Calcula o tamanho do lote                                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskDist)
{
   double lot = InpFixedLot;
   if(InpUseMoneyManagement)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmt = balance * (InpRiskPercent / 100.0);
      double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSz > 0.0 && tickVal > 0.0 && riskDist > 0.0)
         lot = riskAmt / ((riskDist / tickSz) * tickVal);
   }
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step > 0.0) lot = MathFloor(lot / step) * step;
   lot = MathMax(lot, minL);
   lot = MathMin(lot, maxL);
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Calcula Métricas Reais de Desempenho e Histórico                 |
//+------------------------------------------------------------------+
void CalculatePerformanceMetrics(SPerformanceMetrics &m)
{
   ZeroMemory(m);

   datetime todayStart = iTime(_Symbol, PERIOD_D1, 0);
   if(todayStart == 0)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      todayStart = StructToTime(dt);
   }

   if(!HistorySelect(0, TimeCurrent()))
      return;

   int totalDeals = HistoryDealsTotal();
   int currentStreak = 0;
   bool inWinStreak = false;

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
         continue;

      long   magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      string sym   = HistoryDealGetString(ticket, DEAL_SYMBOL);

      if(sym != _Symbol)
         continue;
      if(magic != InpMagicNumber && magic != 0 && !MQLInfoInteger(MQL_TESTER))
         continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

      m.totalTrades++;
      m.totalNetProfit += profit;

      if(dealTime >= todayStart)
         m.todayProfit += profit;

      if(profit > 0.0)
      {
         m.wins++;
         if(inWinStreak)
            currentStreak++;
         else
         {
            inWinStreak = true;
            currentStreak = 1;
         }
      }
      else if(profit < 0.0)
      {
         m.losses++;
         if(!inWinStreak)
            currentStreak++;
         else
         {
            inWinStreak = false;
            currentStreak = 1;
         }
      }
   }

   if(m.totalTrades > 0)
      m.winRate = ((double)m.wins / (double)m.totalTrades) * 100.0;

   if(m.totalTrades > 0)
   {
      if(inWinStreak)
      {
         m.winStreak = currentStreak;
         m.lossStreak = 0;
      }
      else
      {
         m.lossStreak = currentStreak;
         m.winStreak = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Funções de Criação e Gestão do Painel Visual Gráfico             |
//+------------------------------------------------------------------+
void CreateRect(string name, int x, int y, int w, int h, color bg, color border)
{
   string objName = DASH_PREFIX + name;
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_ZORDER, 1);
   }
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_COLOR, border);
}

void CreateLabel(string name, int x, int y, string text, int size, color clr, bool bold = false)
{
   string objName = DASH_PREFIX + name;
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, objName, OBJPROP_FONT, (bold ? "Segoe UI Semibold" : "Segoe UI"));
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_ZORDER, 2);
   }
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
}

void UpdateLabel(string name, string text, color clr)
{
   string objName = DASH_PREFIX + name;
   if(ObjectFind(0, objName) >= 0)
   {
      ObjectSetString(0, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   }
}

void UpdateRectBg(string name, color bg, color border)
{
   string objName = DASH_PREFIX + name;
   if(ObjectFind(0, objName) >= 0)
   {
      ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, objName, OBJPROP_BORDER_COLOR, border);
   }
}

//+------------------------------------------------------------------+
//| Constrói o Layout Estrutural do Dashboard                        |
//+------------------------------------------------------------------+
void CreateDashboardUI()
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   int w = 390;
   int h = 530;

   // 1. Fundo Geral
   CreateRect("BG_MAIN", x, y, w, h, COLOR_PANEL_BG, COLOR_PANEL_BORDER);

   // 2. Cabeçalho
   CreateRect("BG_HEADER", x, y, w, 44, COLOR_HEADER_BG, COLOR_PANEL_BORDER);
   CreateLabel("LBL_TITLE", x + 14, y + 6, "MACD + RSI TREND PRO", 10, COLOR_WHITE_TEXT, true);
   CreateLabel("LBL_SUBTITLE", x + 14, y + 24, "Ativo: " + _Symbol + " (" + EnumToString(_Period) + ")", 8, COLOR_BLUE_TEXT);

   // 3. BLOCO 1: Status da Estratégia e Sinais (Y: 52 a 160)
   int yB1 = y + 52;
   CreateRect("BG_SEC1", x + 8, yB1, w - 16, 105, COLOR_CARD_BG, COLOR_CARD_BORDER);
   CreateLabel("LBL_SEC1_HEAD", x + 16, yB1 + 6, "1. STATUS DA ESTRATÉGIA & SINAIS", 8, COLOR_BLUE_TEXT, true);
   
   CreateRect("BG_STATUS_BOX", x + 14, yB1 + 24, w - 28, 26, C'28,36,54', COLOR_PANEL_BORDER);
   CreateLabel("LBL_STRAT_STATUS", x + 20, yB1 + 28, "AGUARDANDO SINAL 1", 9, COLOR_BLUE_TEXT, true);

   CreateLabel("LBL_SIGNAL_EMA", x + 16, yB1 + 56, "EMA 9 vs SMA 20: ---", 8, COLOR_GRAY_TEXT);
   CreateLabel("LBL_SIGNAL_MACD", x + 16, yB1 + 72, "MACD vs Zero: ---", 8, COLOR_GRAY_TEXT);
   CreateLabel("LBL_SIGNAL_RSI", x + 16, yB1 + 88, "RSI (14): ---", 8, COLOR_GRAY_TEXT);

   // 4. BLOCO 2: Posição Aberta e Monitoramento (Y: 164 a 280)
   int yB2 = yB1 + 112;
   CreateRect("BG_SEC2", x + 8, yB2, w - 16, 114, COLOR_CARD_BG, COLOR_CARD_BORDER);
   CreateLabel("LBL_SEC2_HEAD", x + 16, yB2 + 6, "2. POSIÇÃO ABERTA & P&L", 8, COLOR_BLUE_TEXT, true);
   
   CreateLabel("LBL_POS_DIR_VOL", x + 16, yB2 + 25, "Nenhuma posição aberta", 9, COLOR_GRAY_TEXT, true);
   CreateLabel("LBL_POS_PNL", x + 16, yB2 + 43, "P&L: $0.00 (0.0 pips)", 9, COLOR_WHITE_TEXT, true);
   CreateLabel("LBL_POS_ENTRY", x + 16, yB2 + 63, "Entrada: --- | Atual: ---", 8, COLOR_GRAY_TEXT);
   CreateLabel("LBL_POS_SL_TP", x + 16, yB2 + 79, "SL: --- | TP: ---", 8, COLOR_GRAY_TEXT);
   CreateLabel("LBL_POS_TRAILING", x + 16, yB2 + 95, "Trailing SMA 20: Aguardando 1:1", 8, COLOR_AMBER_TEXT);

   // 5. BLOCO 3: Desempenho e Estatísticas (Y: 284 a 420)
   int yB3 = yB2 + 120;
   CreateRect("BG_SEC3", x + 8, yB3, w - 16, 130, COLOR_CARD_BG, COLOR_CARD_BORDER);
   CreateLabel("LBL_SEC3_HEAD", x + 16, yB3 + 6, "3. DESEMPENHO OPERACIONAL & WIN RATE", 8, COLOR_BLUE_TEXT, true);
   
   CreateLabel("LBL_METRIC_WR", x + 16, yB3 + 24, "Win Rate: 0.0%", 10, COLOR_WHITE_TEXT, true);
   CreateLabel("LBL_METRIC_TODAY", x + 210, yB3 + 24, "P&L Hoje: $0.00", 10, COLOR_WHITE_TEXT, true);

   CreateLabel("LBL_METRIC_TRADES", x + 16, yB3 + 46, "Total de Operações: 0", 8, COLOR_GRAY_TEXT);
   CreateLabel("LBL_METRIC_WINS", x + 16, yB3 + 62, "Operações Vencedoras: 0", 8, COLOR_GREEN_TEXT);
   CreateLabel("LBL_METRIC_LOSSES", x + 210, yB3 + 62, "Operações Perdedoras: 0", 8, COLOR_RED_TEXT);

   CreateLabel("LBL_METRIC_STREAK", x + 16, yB3 + 82, "Sequência Atual: 0", 8, COLOR_WHITE_TEXT);
   CreateLabel("LBL_METRIC_NET_PROFIT", x + 16, yB3 + 102, "Lucro Líquido Acumulado: $0.00", 9, COLOR_WHITE_TEXT, true);

   // 6. BLOCO 4: Risco e Informações do Sistema (Y: 426 a 515)
   int yB4 = yB3 + 138;
   CreateRect("BG_SEC4", x + 8, yB4, w - 16, 70, COLOR_CARD_BG, COLOR_CARD_BORDER);
   CreateLabel("LBL_SEC4_HEAD", x + 16, yB4 + 6, "4. GERENCIAMENTO DE RISCO & SISTEMA", 8, COLOR_BLUE_TEXT, true);

   CreateLabel("LBL_SYS_LOT_RR", x + 16, yB4 + 23, "Lote: 0.01 | Risco/Retorno: 3:1 | SL Velas: 20", 8, COLOR_GRAY_TEXT);
   CreateLabel("LBL_SYS_TRAILING_CFG", x + 16, yB4 + 38, "Trailing SMA20: 20 pips | Break-Even: ATIVO", 8, COLOR_GRAY_TEXT);
   CreateLabel("LBL_SYS_MODE", x + 16, yB4 + 53, "Modo: COMPRA E VENDA | Status: LIBERADO", 8, COLOR_GREEN_TEXT);

   dashboardCreated = true;
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Destrói o Dashboard e Limpa Objetos Gráficos                     |
//+------------------------------------------------------------------+
void DestroyDashboard()
{
   ObjectsDeleteAll(0, DASH_PREFIX);
   dashboardCreated = false;
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Atualiza Dinamicamente os Dados e Cores do Dashboard             |
//+------------------------------------------------------------------+
void UpdateDashboardUI()
{
   if(!dashboardCreated)
   {
      CreateDashboardUI();
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pipSize = GetPipSize();

   //-------------------------------------------------------------
   // 1. ATUALIZA BLOCO 1: STATUS DA ESTRATÉGIA E SINAIS
   //-------------------------------------------------------------
   string stratStatusText = "1. AGUARDANDO SINAL 1";
   color  stratStatusColor = COLOR_BLUE_TEXT;
   color  boxBgColor = C'24,34,50';

   if(HasOpenPosition())
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(positionInfo.SelectByIndex(i) && positionInfo.Symbol() == _Symbol && (positionInfo.Magic() == InpMagicNumber || positionInfo.Magic() == 0))
         {
            if(positionInfo.PositionType() == POSITION_TYPE_BUY)
            {
               stratStatusText = "EM OPERAÇÃO: COMPRA (BUY)";
               stratStatusColor = COLOR_GREEN_TEXT;
               boxBgColor = C'20,44,30';
            }
            else
            {
               stratStatusText = "EM OPERAÇÃO: VENDA (SELL)";
               stratStatusColor = COLOR_RED_TEXT;
               boxBgColor = C'48,22,22';
            }
            break;
         }
      }
   }
   else
   {
      if(buyState == BUY_STATE_WAITING_BEARISH_CROSS)
      {
         stratStatusText = "SINAL 1 OK (ALTA) -> AGUARDANDO CRUZAMENTO";
         stratStatusColor = COLOR_AMBER_TEXT;
         boxBgColor = C'45,38,20';
      }
      else if(buyState == BUY_STATE_COUNTING_DOWN_BARS)
      {
         stratStatusText = StringFormat("GATILHO COMPRA: MACD EM QUEDA (%d/%d)", buyDownBarsCounter, InpMinCorrectionBars);
         stratStatusColor = COLOR_AMBER_TEXT;
         boxBgColor = C'45,38,20';
      }
      else if(buyState == BUY_STATE_ARMED)
      {
         stratStatusText = ">>> GATILHO COMPRA ARMADO! <<<";
         stratStatusColor = COLOR_GREEN_TEXT;
         boxBgColor = C'20,48,28';
      }
      else if(sellState == SELL_STATE_WAITING_BULLISH_CROSS)
      {
         stratStatusText = "SINAL 1 OK (BAIXA) -> AGUARDANDO CRUZAMENTO";
         stratStatusColor = COLOR_AMBER_TEXT;
         boxBgColor = C'45,38,20';
      }
      else if(sellState == SELL_STATE_COUNTING_UP_BARS)
      {
         stratStatusText = StringFormat("GATILHO VENDA: MACD EM SUBIDA (%d/%d)", sellUpBarsCounter, InpMinCorrectionBars);
         stratStatusColor = COLOR_AMBER_TEXT;
         boxBgColor = C'45,38,20';
      }
      else if(sellState == SELL_STATE_ARMED)
      {
         stratStatusText = ">>> GATILHO VENDA ARMADO! <<<";
         stratStatusColor = COLOR_RED_TEXT;
         boxBgColor = C'48,22,22';
      }
   }

   UpdateRectBg("BG_STATUS_BOX", boxBgColor, COLOR_PANEL_BORDER);
   UpdateLabel("LBL_STRAT_STATUS", stratStatusText, stratStatusColor);

   // Detalhe das médias
   string emaText = StringFormat("EMA 9: %.*f | SMA 20: %.*f ", digits, cacheEMA, digits, cacheSMA);
   color  emaColor = COLOR_GRAY_TEXT;
   if(cacheEMA > cacheSMA)
   {
      emaText += "[EMA > SMA: TENDÊNCIA DE ALTA]";
      emaColor = COLOR_GREEN_TEXT;
   }
   else if(cacheEMA < cacheSMA)
   {
      emaText += "[EMA < SMA: TENDÊNCIA DE BAIXA]";
      emaColor = COLOR_RED_TEXT;
   }
   else
   {
      emaText += "[MÉDIAS NEUTRAS]";
      emaColor = COLOR_BLUE_TEXT;
   }
   UpdateLabel("LBL_SIGNAL_EMA", emaText, emaColor);

   // Detalhe MACD
   string macdText = StringFormat("MACD Main: %.*f | Sinal: %.*f ", digits, cacheMACDMain, digits, cacheMACDSignal);
   color  macdColor = COLOR_GRAY_TEXT;
   if(cacheMACDMain > 0.0)
   {
      macdText += "(Acima de Zero: Alta)";
      macdColor = COLOR_GREEN_TEXT;
   }
   else if(cacheMACDMain < 0.0)
   {
      macdText += "(Abaixo de Zero: Baixa)";
      macdColor = COLOR_RED_TEXT;
   }
   UpdateLabel("LBL_SIGNAL_MACD", macdText, macdColor);

   // Detalhe RSI
   string rsiText = StringFormat("RSI (14): %.2f ", cacheRSI);
   color  rsiColor = COLOR_BLUE_TEXT;
   if(cacheRSI > InpRSI_Threshold_Buy)
   {
      rsiText += StringFormat("[> %.0f: SOBRECOMPRA CONFIRMADA]", InpRSI_Threshold_Buy);
      rsiColor = COLOR_GREEN_TEXT;
   }
   else if(cacheRSI < InpRSI_Threshold_Sell)
   {
      rsiText += StringFormat("[< %.0f: SOBREVENDA CONFIRMADA]", InpRSI_Threshold_Sell);
      rsiColor = COLOR_RED_TEXT;
   }
   else
   {
      rsiText += "[Região Neutra: 30 a 70]";
      rsiColor = COLOR_BLUE_TEXT;
   }
   UpdateLabel("LBL_SIGNAL_RSI", rsiText, rsiColor);

   //-------------------------------------------------------------
   // 2. ATUALIZA BLOCO 2: POSIÇÃO ABERTA & P&L
   //-------------------------------------------------------------
   bool posFound = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(positionInfo.Symbol() != _Symbol) continue;
      if(positionInfo.Magic() != InpMagicNumber && positionInfo.Magic() != 0) continue;

      posFound = true;
      ENUM_POSITION_TYPE pType = positionInfo.PositionType();
      double pVolume  = positionInfo.Volume();
      double pOpen    = positionInfo.PriceOpen();
      double pSL      = positionInfo.StopLoss();
      double pTP      = positionInfo.TakeProfit();
      double pProfit  = positionInfo.Profit();
      double curPrice = (pType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double diffPips = 0.0;
      if(pipSize > 0.0)
      {
         diffPips = (pType == POSITION_TYPE_BUY) ? (curPrice - pOpen) / pipSize : (pOpen - curPrice) / pipSize;
      }

      string dirStr = (pType == POSITION_TYPE_BUY) ? "COMPRA (BUY)" : "VENDA (SELL)";
      color  dirClr = (pType == POSITION_TYPE_BUY) ? COLOR_GREEN_TEXT : COLOR_RED_TEXT;
      UpdateLabel("LBL_POS_DIR_VOL", StringFormat("Direção: %s | Volume: %.2f lote(s)", dirStr, pVolume), dirClr);

      string pnlSign = (pProfit >= 0.0) ? "+" : "";
      string pipSign = (diffPips >= 0.0) ? "+" : "";
      color  pnlClr  = (pProfit >= 0.0) ? COLOR_GREEN_TEXT : COLOR_RED_TEXT;
      UpdateLabel("LBL_POS_PNL", StringFormat("P&L Atual: %s$%.2f (%s%.1f pips)", pnlSign, pProfit, pipSign, diffPips), pnlClr);

      UpdateLabel("LBL_POS_ENTRY", StringFormat("Entrada: %.*f | Cotação Atual: %.*f", digits, pOpen, digits, curPrice), COLOR_WHITE_TEXT);

      string slStr = (pSL > 0.0) ? StringFormat("%.*f", digits, pSL) : "Sem SL";
      string tpStr = (pTP > 0.0) ? StringFormat("%.*f", digits, pTP) : "Sem TP";
      UpdateLabel("LBL_POS_SL_TP", StringFormat("Stop Loss: %s | Take Profit: %s (3:1 RR)", slStr, tpStr), COLOR_GRAY_TEXT);

      // Trailing status
      string trailStatus = "Trailing SMA 20: ";
      color  trailClr    = COLOR_AMBER_TEXT;
      if(!InpUseTrailingSMA)
      {
         trailStatus += "Desativado";
         trailClr = COLOR_GRAY_TEXT;
      }
      else
      {
         bool isBE = (pType == POSITION_TYPE_BUY && pSL >= pOpen) || (pType == POSITION_TYPE_SELL && pSL > 0.0 && pSL <= pOpen);
         if(isBE)
         {
            trailStatus += "ATIVO [CONDUZINDO PELA SMA 20]";
            trailClr = COLOR_GREEN_TEXT;
         }
         else
         {
            trailStatus += "Aguardando Lucro 1:1";
            trailClr = COLOR_AMBER_TEXT;
         }
      }
      UpdateLabel("LBL_POS_TRAILING", trailStatus, trailClr);
      break;
   }

   if(!posFound)
   {
      UpdateLabel("LBL_POS_DIR_VOL", "Nenhuma posição aberta no momento", COLOR_GRAY_TEXT);
      UpdateLabel("LBL_POS_PNL", "P&L Atual: $0.00 (0.0 pips)", COLOR_GRAY_TEXT);
      UpdateLabel("LBL_POS_ENTRY", "Entrada: --- | Cotação Atual: " + StringFormat("%.*f", digits, SymbolInfoDouble(_Symbol, SYMBOL_BID)), COLOR_GRAY_TEXT);
      UpdateLabel("LBL_POS_SL_TP", "Stop Loss: --- | Take Profit: ---", COLOR_GRAY_TEXT);
      UpdateLabel("LBL_POS_TRAILING", "Trailing SMA 20: Em espera", COLOR_GRAY_TEXT);
   }

   //-------------------------------------------------------------
   // 3. ATUALIZA BLOCO 3: DESEMPENHO E ESTATÍSTICAS REAIS
   //-------------------------------------------------------------
   SPerformanceMetrics metrics;
   CalculatePerformanceMetrics(metrics);

   color wrColor = (metrics.winRate >= 50.0) ? COLOR_GREEN_TEXT : (metrics.totalTrades > 0 ? COLOR_RED_TEXT : COLOR_WHITE_TEXT);
   UpdateLabel("LBL_METRIC_WR", StringFormat("Win Rate: %.1f%%", metrics.winRate), wrColor);

   string tdSign = (metrics.todayProfit >= 0.0) ? "+" : "";
   color  tdColor = (metrics.todayProfit >= 0.0) ? COLOR_GREEN_TEXT : COLOR_RED_TEXT;
   UpdateLabel("LBL_METRIC_TODAY", StringFormat("P&L Hoje: %s$%.2f", tdSign, metrics.todayProfit), tdColor);

   UpdateLabel("LBL_METRIC_TRADES", StringFormat("Total de Operações: %d", metrics.totalTrades), COLOR_WHITE_TEXT);
   UpdateLabel("LBL_METRIC_WINS", StringFormat("Vitórias: %d", metrics.wins), COLOR_GREEN_TEXT);
   UpdateLabel("LBL_METRIC_LOSSES", StringFormat("Derrotas: %d", metrics.losses), COLOR_RED_TEXT);

   string streakStr = "Sequência Atual: ";
   color  streakClr = COLOR_WHITE_TEXT;
   if(metrics.winStreak > 0)
   {
      streakStr += StringFormat("%d Vitória(s) consecutiva(s)", metrics.winStreak);
      streakClr = COLOR_GREEN_TEXT;
   }
   else if(metrics.lossStreak > 0)
   {
      streakStr += StringFormat("%d Derrota(s) consecutiva(s)", metrics.lossStreak);
      streakClr = COLOR_RED_TEXT;
   }
   else
   {
      streakStr += "Nenhuma";
      streakClr = COLOR_GRAY_TEXT;
   }
   UpdateLabel("LBL_METRIC_STREAK", streakStr, streakClr);

   string netSign = (metrics.totalNetProfit >= 0.0) ? "+" : "";
   color  netClr  = (metrics.totalNetProfit >= 0.0) ? COLOR_GREEN_TEXT : COLOR_RED_TEXT;
   UpdateLabel("LBL_METRIC_NET_PROFIT", StringFormat("Lucro Líquido Acumulado: %s$%.2f", netSign, metrics.totalNetProfit), netClr);

   //-------------------------------------------------------------
   // 4. ATUALIZA BLOCO 4: RISCO & SISTEMA
   //-------------------------------------------------------------
   string lotStr = InpUseMoneyManagement ? StringFormat("%.1f%% da Conta", InpRiskPercent) : StringFormat("%.2f Fixo", InpFixedLot);
   UpdateLabel("LBL_SYS_LOT_RR", StringFormat("Lote: %s | Risco:Retorno: 3:1 | SL: %d velas", lotStr, InpLookbackBarsSL), COLOR_GRAY_TEXT);

   string trDistStr = StringFormat("Trailing SMA20: %.1f pips | Break-Even: %s", InpTrailingDistancePips, (InpProtectBreakEven ? "SIM" : "NÃO"));
   UpdateLabel("LBL_SYS_TRAILING_CFG", trDistStr, COLOR_BLUE_TEXT);

   string dirOp = "COMPRA E VENDA";
   if(InpTradeDirection == DIRECTION_BUY_ONLY)  dirOp = "APENAS COMPRAS";
   if(InpTradeDirection == DIRECTION_SELL_ONLY) dirOp = "APENAS VENDAS";
   UpdateLabel("LBL_SYS_MODE", StringFormat("Direção: %s | Sistema: OPERACIONAL", dirOp), COLOR_GREEN_TEXT);

   ChartRedraw(0);
}
//+------------------------------------------------------------------+
