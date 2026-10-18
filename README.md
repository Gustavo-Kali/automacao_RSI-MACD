# Automação Forex MT5: MACD + RSI Trend Pro (v2.00)

Robô de negociação (Expert Advisor) institucional desenvolvido para o **MetaTrader 5 (MQL5)** com execução em tempo real e backtest de alta velocidade. Suporta operações de **Compra** e **Venda**, Stop Loss dinâmico na mínima/máxima de 20 velas, Take Profit com relação 3:1, Trailing Stop conduzido pela SMA 20 e **Painel Visual Profissional (Dashboard HUD)** com métricas completas de desempenho em tempo real.

---

## 1. Painel Visual Profissional (Dashboard HUD)

O novo painel foi desenvolvido com objetos gráficos nativos (`OBJ_RECTANGLE_LABEL` e `OBJ_LABEL`), possuindo fundo sólido elegante (Dark Slate), cantos limpos e tipografia de alto contraste para permitir monitoramento rápido e intuitivo.

### Sistema de Cores Inteligente:
* 🟢 **Verde**: Condições confirmadas, operação com lucro (+P&L), posição vencedora, gatilho de compra armado, Win Rate $\ge 50\%$, vitórias e sequências positivas.
* 🔴 **Vermelho**: Condições negativas/baixa, operação com prejuízo (-P&L), posição perdedora, gatilho de venda armado, stop acionado, Win Rate $< 50\%$, derrotas.
* 🟡 **Amarelo / Laranja**: Condições intermediárias em análise, contagem de velas da correção (ex: `Queda: 2/3`), aguardando cruzamento de confirmação.
* 🔵 **Azul / Ciano**: Dados operacionais, identificação do ativo, títulos de seções, dados de risco e status geral do sistema.
* ⚪ **Branco**: Valores numéricos principais e dados de cotação.

---

## 2. Estrutura e Hierarquia das Informações

O painel é estruturado em 4 blocos organizados em ordem de prioridade:

```
┌────────────────────────────────────────────────────────┐
│               MACD + RSI TREND PRO (v2.00)             │
│            Ativo: XAUAUD (PERIOD_M15) | COMPRA & VENDA │
├────────────────────────────────────────────────────────┤
│ 1. STATUS DA ESTRATÉGIA & SINAIS (DESTAQUE PRINCIPAL)  │
│ ┌────────────────────────────────────────────────────┐ │
│ │  STATUS: GATILHO COMPRA ARMADO! (Verde) / EM OP... │ │
│ └────────────────────────────────────────────────────┘ │
│ • EMA 9 vs SMA 20: ALTA [EMA > SMA] (Verde / Vermelho) │
│ • MACD: +8.88 [Acima de Zero: Alta]                   │
│ • RSI: 69.90 [Região Neutra: 30 a 70]                 │
├────────────────────────────────────────────────────────┤
│ 2. POSIÇÃO ABERTA & P&L EM TEMPO REAL                  │
│ • Direção & Volume: COMPRA (BUY) 0.01                  │
│ • P&L Atual: +$142.50 (+142.5 pips) (Verde se lucro)   │
│ • Entrada: 6680.35 | Cotação Atual: 6822.85            │
│ • Stop Loss: 6802.85 | Take Profit: 6865.20            │
│ • Trailing SMA 20: ATIVO [CONDUZINDO PELA SMA 20]      │
├────────────────────────────────────────────────────────┤
│ 3. DESEMPENHO OPERACIONAL & WIN RATE (MÉTRICAS REAIS)  │
│ • Win Rate: 65.5% (Verde/Vermelho) | P&L Hoje: +$120.00│
│ • Total de Operações: 24                               │
│ • Vitórias: 16 (Verde) | Derrotas: 8 (Vermelho)        │
│ • Sequência Atual: 3 Vitória(s) consecutiva(s)         │
│ • Lucro Líquido Acumulado: +$580.40                    │
├────────────────────────────────────────────────────────┤
│ 4. GERENCIAMENTO DE RISCO & SISTEMA                    │
│ • Lote: 0.01 | Risco:Retorno: 3:1 | SL Velas: 20       │
│ • Trailing SMA 20: 20.0 pips | Break-Even: SIM         │
│ • Direção: COMPRA E VENDA | Sistema: OPERACIONAL       │
└────────────────────────────────────────────────────────┘
```

---

## 3. Como Atualizar no MetaTrader 5

1. Caso a janela preta do **Testador Visual (Visualization)** esteja aberta, **feche-a**.
2. Na janela principal do MetaTrader 5, abra o Testador de Estratégias (**`Ctrl + R`**).
3. Clique em **Iniciar**.
4. O novo painel gráfico profissional aparecerá fixado no canto superior esquerdo com fundo sólido, cores vivas e atualização instantânea a cada variação de preço e fechamento de vela.

---

## 4. Arquivos do Projeto

* [MACD_RSI_Trend_EA.mq5](file:///c:/Users/Gustavo%20Kali/Desktop/automacao-MACD+RSI/MACD_RSI_Trend_EA.mq5) (v2.00)
* [MACD_RSI_Trend_EA.ex5](file:///c:/Users/Gustavo%20Kali/Desktop/automacao-MACD+RSI/MACD_RSI_Trend_EA.ex5) *(Compilado com 0 erros e 0 avisos)*
* Arquivo instalado diretamente na pasta `MQL5\Experts` do seu MetaTrader 5.
