# LEVER Protocol Architecture

## Overview

LEVER is a synthetic perpetuals layer for prediction markets. It enables leveraged trading on any prediction market outcome (Polymarket, Kalshi, etc.) without affecting the underlying market's liquidity.

## Core Insight

Prediction markets have a fundamental limitation: large trades move prices significantly due to limited liquidity. LEVER solves this by creating a synthetic derivatives layer where:

1. **LPs provide capital** that backs leveraged positions
2. **Traders get leverage** without touching underlying market liquidity
3. **Prices track external oracles** (the actual prediction market prices)
4. **Risk is managed** through margin requirements, funding rates, and liquidations

## System Architecture

```
                                    ┌─────────────────┐
                                    │   EXTERNAL      │
                                    │   ORACLES       │
                                    │  (Polymarket,   │
                                    │   UMA, etc.)    │
                                    └────────┬────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                              ROUTER                                  │
│                    (User-facing entry point)                         │
│                                                                      │
│  • openPosition()    • closePosition()                               │
│  • depositCollateral()    • withdrawCollateral()                     │
└──────────┬──────────────────┬──────────────────┬───────────────────┘
           │                  │                  │
           ▼                  ▼                  ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│   PRICE ENGINE   │  │   RISK ENGINE    │  │  FUNDING ENGINE  │
│                  │  │                  │  │                  │
│ • Oracle price   │  │ • Margin calcs   │  │ • OI imbalance   │
│ • EMA smoothing  │  │ • Borrow fees    │  │ • Rate calc      │
│ • vAMM slippage  │  │ • Leverage caps  │  │ • Zero-sum       │
│ • Mark price     │  │ • Liquidation    │  │   redistribution │
│                  │  │   thresholds     │  │                  │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                     │
         │                     ▼                     │
         │            ┌──────────────────┐           │
         │            │   LIQUIDATION    │           │
         │            │     ENGINE       │           │
         │            │                  │           │
         │            │ • Force close    │           │
         │            │ • Penalty dist   │           │
         │            │ • LP protection  │           │
         │            └────────┬─────────┘           │
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │  POSITION LEDGER │
                    │                  │
                    │ • Single source  │
                    │   of truth       │
                    │ • Position data  │
                    │ • OI tracking    │
                    │ • Market state   │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │     LP POOL      │
                    │                  │
                    │ • Capital source │
                    │ • Fee collection │
                    │ • LP tokens      │
                    └──────────────────┘
```

## Contract Responsibilities

### Position Ledger (`PositionLedger.sol`)
**The single source of truth for all position data.**

- Stores position structs: size, entry price, collateral (USDT), timestamps, fee indices
- Tracks open interest per side (long/short)
- Manages market configuration (oracle, OI caps, active status)
- Enforces engine authorization (only approved contracts can modify positions)

Key design decisions:
- Signed size: positive = long, negative = short
- Probability as price: 0-1e18 (0% to 100%)
- Cumulative indices for gas-efficient fee tracking

### Price Engine (`PriceEngine.sol`)
**Answers: "What is the fair price right now?"**

Components:
1. **Oracle Integration**: Fetches external probability from Polymarket/UMA
2. **EMA Smoothing**: Prevents price manipulation via exponential moving average
3. **vAMM Slippage**: Calculates execution price based on trade size
4. **Mark Price**: Adjusts for OI imbalance (more longs → higher mark)

The price engine determines WHERE trades happen, not what they cost to hold.

### Funding Engine (`FundingEngine.sol`)
**Answers: "Which side is crowded, and how do we rebalance?"**

Key principles:
- **Zero-sum**: Funding flows between traders only (protocol takes nothing)
- **LPs not involved**: LPs don't take funding risk
- **Imbalance correction**: Crowded side pays the other side

Rate calculation:
```
fundingRate = maxRate × (imbalance / threshold)

If more longs than shorts → positive rate → longs pay shorts
If more shorts than longs → negative rate → shorts pay longs
```

### Risk Engine (`RiskEngine.sol`)
**Answers: "How expensive is it to use LP capital right now?"**

Controls:
- **Initial Margin (IM)**: Required to open position (e.g., 10%)
- **Maintenance Margin (MM)**: Required to keep position open (e.g., 5%)
- **Max Leverage**: Per-market cap (e.g., 10x)
- **Borrow Fees**: Based on utilization curve
- **Emergency Pause**: Per-market and global kill switches

Utilization-based borrow rate:
```
if utilization <= optimal:
    rate = base + (optimal_rate - base) × (utilization / optimal)
else:
    rate = optimal_rate + (max - optimal_rate) × (excess / max_excess)
```

### Liquidation Engine (`LiquidationEngine.sol`)
**Executes forced position closures when equity < maintenance margin.**

Process:
1. Check if position equity is below maintenance margin
2. Calculate liquidation penalty
3. Distribute penalty: liquidator reward (50%), protocol fee (10%), LP recovery (40%)
4. Close position on ledger
5. Update OI

Supports both full and partial liquidations.

### Router (`Router.sol`)
**User-facing entry point for all trading operations.**

Coordinates between all engines for atomic operations:
1. Validates price freshness
2. Gets execution price with slippage
3. Checks margin requirements
4. Accrues interest
5. Executes on ledger
6. Handles collateral transfers

### LP Pool (`LPPool.sol`)
**Liquidity provider pool that backs all positions.**

LPs:
- Deposit USDT, receive LP tokens (lvUSDT)
- Earn fees from trading, borrowing, and liquidations
- Share in losses (bad debt socialization)

Features:
- Withdrawal queue for large exits (prevents bank runs)
- Cumulative fee distribution (gas-efficient)
- Utilization tracking
- Capital allocation/deallocation for position backing

## Data Flow Examples

### Opening a Long Position

```
1. User calls Router.openPosition(marketId=0, size=100e18, collateral=10e6, ...)

2. Router checks:
   - Price freshness via PriceEngine.isPriceStale()
   - Gets execution price via PriceEngine.getExecutionPrice()
   - Validates margin via RiskEngine.checkInitialMargin()

3. Router executes:
   - Transfers USDC from user
   - Calls PositionLedger.openPosition()

4. PositionLedger updates:
   - Creates/modifies position struct
   - Updates totalLongOI
   - Emits PositionOpened event
```

### Liquidation Flow

```
1. Keeper monitors positions via RiskEngine.isLiquidatable()

2. When position.equity < maintenanceMargin:
   - Liquidator calls LiquidationEngine.liquidate(trader, marketId)

3. LiquidationEngine:
   - Verifies liquidatable via RiskEngine
   - Calculates penalty
   - Calls PositionLedger.liquidatePosition()
   - Distributes penalty (liquidator/protocol/LP)

4. PositionLedger:
   - Clears position
   - Updates OI
   - Emits PositionLiquidated event
```

## Security Model

### Access Control

```
Owner (multisig) ──► Admin functions (params, pauses)
     │
     ▼
Engines (contracts) ──► Position modifications
     │
     ▼
Keepers (EOAs) ──► Price updates, funding updates
     │
     ▼
Users (EOAs) ──► Trading via Router only
```

### Risk Mitigations

1. **Reentrancy Guards**: All state-modifying functions
2. **Price Staleness Checks**: Reject trades on stale prices
3. **Max Deviation Limits**: Reject oracle updates that deviate too much
4. **OI Caps**: Limit exposure per market
5. **Emergency Pauses**: Per-market and global
6. **Withdrawal Delays**: Prevent LP bank runs

## Gas Optimization Notes

1. **Cumulative Indices**: Funding and borrow fees use cumulative indices instead of per-position updates
2. **Packed Structs**: Position data fits in minimal storage slots
3. **Batch Operations**: Keepers can batch price/funding updates
4. **View Functions**: Heavy computations in view functions (off-chain)

## Deployment Order

1. Deploy USDC (or use existing)
2. Deploy PositionLedger
3. Deploy PriceEngine, FundingEngine, RiskEngine
4. Deploy LiquidationEngine
5. Deploy Router
6. Deploy LPPool
7. Configure authorizations
8. Create markets
9. Initialize prices

## Upgrade Path

Contracts are not upgradeable by default. To upgrade:

1. Deploy new version
2. Migrate state (if needed)
3. Update authorizations
4. Point Router to new engines
5. Deprecate old contracts

For critical fixes, emergency pause + migrate pattern.
