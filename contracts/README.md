# LEVER Protocol - Smart Contracts

## Overview

Synthetic perpetuals layer for prediction markets. Trade leveraged positions on any prediction market outcome (Polymarket, Kalshi, etc.) without affecting underlying market liquidity.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         ROUTER                               │
│              User-facing entry point                         │
└─────────────────┬───────────────────────────────────────────┘
                  │
    ┌─────────────┼─────────────┬─────────────┬──────────────┐
    ▼             ▼             ▼             ▼              ▼
┌────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐  ┌────────────┐
│ PRICE  │  │ FUNDING  │  │   RISK   │  │LIQUIDAT.│  │  POSITION  │
│ ENGINE │  │  ENGINE  │  │  ENGINE  │  │ ENGINE  │  │   LEDGER   │
└────────┘  └──────────┘  └──────────┘  └─────────┘  └────────────┘
    │             │             │             │              ▲
    │             │             │             │              │
    └─────────────┴─────────────┴─────────────┴──────────────┘
                    All engines read from Ledger
```

## Contracts (All Complete ✅)

### Core
| Contract | Description | Size |
|----------|-------------|------|
| `PositionLedger.sol` | Position storage, OI tracking, market state | 12.6KB |
| `PriceEngine.sol` | Oracle integration, EMA smoothing, vAMM slippage | 10.4KB |
| `FundingEngine.sol` | OI imbalance detection, zero-sum redistribution | 8.4KB |
| `RiskEngine.sol` | Margin calculations, borrow fees, utilization | 13.7KB |
| `LiquidationEngine.sol` | Forced closures, penalty distribution | 12.3KB |
| `Router.sol` | User-facing trading operations | 11.5KB |

### Interfaces
- `IPositionLedger.sol` - Position and market data access
- `IPriceEngine.sol` - Price queries and updates
- `IRiskEngine.sol` - Margin checks and risk params
- `IFundingEngine.sol` - Funding rate queries
- `IERC20.sol` - Standard token interface

## Engine Responsibilities

### Position Ledger
- Single source of truth for all position data
- Tracks: size, entry price, collateral, timestamps, fee indices
- Manages: OI per side, market caps, active/inactive state
- Only authorized engines can modify positions

### Price Engine
- **Question:** "What is the fair price right now?"
- Oracle integration with EMA smoothing
- vAMM pricing curve for slippage
- Mark price calculation based on OI imbalance

### Funding Engine
- **Question:** "Which side is crowded?"
- Zero-sum between traders (LPs not involved)
- Positive imbalance → longs pay shorts
- Negative imbalance → shorts pay longs

### Risk Engine
- **Question:** "How expensive is LP capital?"
- Initial/maintenance margin requirements
- Borrow fee based on utilization curve
- Leverage limits, OI caps
- Emergency pause controls

### Liquidation Engine
- Executes forced closures when equity < maintenance margin
- Distributes penalty: liquidator reward, protocol fee, LP recovery
- Supports partial liquidations

### Router
- User-facing entry point
- Coordinates all engines for atomic operations
- Handles collateral transfers
- Slippage protection

## Setup

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std

# Build
forge build

# Test
forge test -vvv
```

## Key Design Decisions

1. **Probability as Price**: 0-1e18 range (0% to 100%)
2. **Signed Size**: Positive = long, negative = short
3. **Engine Authorization**: Ledger enforces access control
4. **Zero-Sum Funding**: LPs don't take funding risk
5. **Cumulative Indices**: Gas-efficient fee tracking
6. **Utilization-Based Borrow**: Higher usage = higher fees

## Position PnL

```
PnL = size × (currentPrice - entryPrice)

Long 100 @ 50%, now 60%:  PnL = 100 × (0.6 - 0.5) = +10
Short 100 @ 50%, now 40%: PnL = -100 × (0.4 - 0.5) = +10
```

## Typical Trade Flow

1. User calls `Router.openPosition(marketId, size, collateral, maxPrice, minPrice)`
2. Router checks price freshness via PriceEngine
3. Router gets execution price with slippage
4. Router validates margin via RiskEngine
5. Router accrues interest
6. Router executes on PositionLedger
7. Events emitted for indexing

## Risk Parameters (Example)

```solidity
// 10x max leverage market
initialMarginBps: 1000      // 10% initial margin
maintenanceMarginBps: 500   // 5% maintenance margin
maxLeverage: 10             // 10x max
baseBorrowRate: 0.05e18     // 5% base APR
maxBorrowRate: 0.50e18      // 50% max APR
optimalUtilization: 0.8e18  // 80% target
liquidationPenaltyBps: 500  // 5% penalty
```

## Testnet Deployment (BSC Testnet)

**Network:** BSC Testnet (Chain ID 97)
**Deployed:** 2026-02-06

| Contract | Address |
|----------|---------|
| MockUSDT | `0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58` |
| PositionLedger | `0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c` |
| PriceEngine | `0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33` |
| FundingEngine | `0xa6Ec543C82c564F9Cdb9a7e7682C68A43D1af802` |
| RiskEngine | `0x833D02521a41f175c389ec2A8c86F22E3de524DB` |
| LiquidationEngine | `0xa02B8456cd2b2C0C2dD8A41690700171950D839F` |
| Router | `0x34A73a10a953A69d9Ee8453BFef0d6fB12c105a7` |
| LPPool | `0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1` |
| InsuranceFund | `0xB8CA10ADbE4c0666eF701e0D0aeB27cFC5b81932` |

**Test Market (ID: 0):**
- Initial Price: 50%
- Max Leverage: 10x
- LP Capital: 1,000,000 USDT
- Insurance Fund: 100,000 USDT

**Deployer Wallet:** `0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc`
- USDT Balance: 8,900,000 USDT
- LP Tokens: 1,000,000 lvUSDT

### Interact via BSCScan

- [Router](https://testnet.bscscan.com/address/0x34A73a10a953A69d9Ee8453BFef0d6fB12c105a7)
- [PositionLedger](https://testnet.bscscan.com/address/0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c)
- [LPPool](https://testnet.bscscan.com/address/0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1)

### Quick Start (Testnet)

```bash
# 1. Get testnet BNB from faucet
# https://testnet.bnbchain.org/faucet-smart

# 2. Copy addresses to .env
cp scripts/.env.example scripts/.env
# Fill in the addresses above

# 3. Run demo script
cd scripts && npx ts-node demo.ts
```

## Next Steps

- [x] ~~Integration tests (full flow)~~
- [x] ~~LP Pool contract~~
- [x] ~~BNB Testnet deployment~~
- [ ] Oracle adapter (Polymarket/UMA)
- [ ] Keeper bot specs
- [ ] Gas optimization
- [ ] Contract verification (BSCScan)
- [ ] Audit prep

## License

MIT
