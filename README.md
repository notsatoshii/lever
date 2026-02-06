# LEVER Protocol

Synthetic perpetuals layer for prediction markets. Leverage for Polymarket, Kalshi, and more.

## Architecture

**Key Principle:** Entry Price ≠ Mark Price
- **Entry Price:** From vAMM (includes slippage)
- **Mark Price:** From PriceEngineV2 (smoothed Probability Index)

### Core Contracts (BSC Testnet)

| Contract | Address | Description |
|----------|---------|-------------|
| RouterV5 | `0x90f2e2dad537f8f8eaa9d659538b26cb4bb5eea0` | Main entry point with LP integration |
| PositionLedger | `0x6fd251dec261512f758768447489855e215352db` | Position state management |
| vAMM | `0xab015ae92092996ad3dc95a8874183c0fb5f9938` | Entry/exit price calculation |
| PriceEngineV2 | `0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC` | Smoothed mark price (PI) |
| SimpleRiskEngine | `0x543ccad81a2eded2dc785272fcba899512a161b4` | Margin validation |
| BorrowFeeEngineV2 | `0xc68e5b17f286624E31c468147360D36eA672BD35` | Dynamic borrow rates |
| LPPool | `0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1` | Liquidity provider pool |
| USDT | `0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58` | Test collateral token |

## Project Structure

```
├── contracts/          # Solidity smart contracts
│   └── src/
│       ├── RouterV5.sol         # Main router with LP integration
│       ├── PositionLedgerV2.sol # Position management
│       ├── PriceEngineV2.sol    # Smoothed price oracle
│       ├── BorrowFeeEngineV2.sol # Dynamic borrow rates
│       ├── LPPool.sol           # LP token & fee distribution
│       └── vAMM.sol             # Virtual AMM for entry prices
├── frontend/           # Next.js frontend
├── keeper/             # Keeper scripts
│   ├── polymarket-keeper-v3.ts  # Main price keeper
│   ├── price-keeper.ts          # Price updates
│   └── jit-keeper.ts            # JIT operations
└── vault/              # Documentation & research
```

## Key Features

### Price Smoothing (PriceEngineV2)
- **Volatility Dampening:** `w_vol = 1/(1+σ)` — stickier when volatile
- **Time-Weighted:** `w_time = √(τ/τ_max)` — locks near expiry
- **Anti-manipulation:** Input validation, tick limits, liquidity checks

### LP Pool Integration (RouterV5)
- Automatic capital allocation tracking
- Fee routing (borrow, trading, liquidations)
- Real utilization metrics

### Dynamic Borrow Rates (BorrowFeeEngineV2)
- 5 risk multipliers: Utilization, Imbalance, Volatility, Time-to-Resolution, Concentration
- EMA smoothing with rate caps
- Base rate: 0.02% per hour

## Development

```bash
# Frontend
cd frontend && npm install && npm run dev

# Contracts (requires Foundry)
cd contracts && forge build

# Keeper
cd keeper && npm install && npx ts-node polymarket-keeper-v3.ts
```

## Links

- Frontend: http://165.245.186.254:3001
- Network: BSC Testnet (Chain ID 97)
- Status: Pre-seed / Active Development

---

*Last updated: 2026-02-06*
