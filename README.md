# LEVER Protocol

**Synthetic Perpetuals for Prediction Markets**

Trade leveraged positions on any prediction market outcome without affecting the underlying market's liquidity.

## The Problem

Prediction markets (Polymarket, Kalshi, etc.) have limited liquidity. Large trades move prices significantly, making it impossible to:
- Take meaningful positions without massive slippage
- Trade with leverage
- Hedge effectively

## The Solution

LEVER creates a synthetic derivatives layer on top of prediction markets:

- **For Traders**: Get up to 10x leverage on any prediction market outcome
- **For LPs**: Earn yield by providing capital that backs leveraged positions
- **For Markets**: Prices track real prediction markets via oracles, but trades don't affect underlying liquidity

## How It Works

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  POLYMARKET │────►│   ORACLE    │────►│    LEVER    │
│  (or other) │     │  (price)    │     │  (trading)  │
└─────────────┘     └─────────────┘     └─────────────┘
                                              │
                    ┌─────────────────────────┴───────┐
                    │                                 │
              ┌─────▼─────┐                    ┌──────▼──────┐
              │  TRADERS  │                    │     LPs     │
              │ (leverage)│                    │ (yield)     │
              └───────────┘                    └─────────────┘
```

1. **Oracles** fetch real-time probabilities from prediction markets
2. **Traders** open leveraged long/short positions on outcomes
3. **LPs** provide USDC that backs trader positions
4. **Funding rates** balance long/short demand (zero-sum between traders)
5. **Liquidations** protect LP capital when positions go underwater

## Example

> "Will Bitcoin hit $100k by end of 2025?"

On Polymarket, this trades at 65% ($0.65 per share). You're bullish.

**Without LEVER:**
- Buy $10,000 of YES shares
- If probability goes to 80%, you make ~$2,300 (23%)
- Large order moves price significantly

**With LEVER:**
- Deposit $1,000 USDC as collateral
- Open 10x leveraged long at 65%
- If probability goes to 80%, you make ~$2,300 (230% on capital)
- No impact on underlying Polymarket liquidity

## Repository Structure

```
lever/
├── contracts/           # Solidity smart contracts
│   ├── src/            # Core contracts
│   │   ├── PositionLedger.sol
│   │   ├── PriceEngine.sol
│   │   ├── FundingEngine.sol
│   │   ├── RiskEngine.sol
│   │   ├── LiquidationEngine.sol
│   │   ├── Router.sol
│   │   └── LPPool.sol
│   ├── test/           # Foundry tests
│   └── docs/           # Technical documentation
├── app/                # Frontend (coming soon)
└── keeper/             # Keeper bot (coming soon)
```

## Quick Start

```bash
# Clone
git clone https://github.com/notsatoshii/lever.git
cd lever/contracts

# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install

# Build
forge build

# Test
forge test -vvv

# Deploy to BSC Testnet
forge script script/Deploy.s.sol --rpc-url $BSC_TESTNET_RPC --broadcast
```

## Network

**Target: BSC (Binance Smart Chain)**
- Testnet Chain ID: 97
- Collateral: USDT (18 decimals)
- Testnet USDT: `0x337610d27c682E347C9cD60BD4b3b107C9d34dDd`

## Documentation

- [Architecture](contracts/docs/ARCHITECTURE.md) - System design and data flows
- [Deployment](contracts/docs/DEPLOYMENT.md) - How to deploy
- [API Reference](contracts/docs/API.md) - Contract interfaces

## Key Features

| Feature | Description |
|---------|-------------|
| **Leverage** | Up to 10x on any prediction market |
| **Zero-Sum Funding** | Balanced between traders, LPs not exposed |
| **vAMM Slippage** | Fair execution prices based on size |
| **EMA Smoothing** | Manipulation-resistant pricing |
| **Instant Liquidations** | Protect LP capital |
| **LP Yield** | Earn from trading fees, borrow fees, liquidations |
| **BSC Native** | Low fees, fast finality, USDT collateral |

## Risk Parameters (Example)

| Parameter | Value | Description |
|-----------|-------|-------------|
| Initial Margin | 10% | Required to open position |
| Maintenance Margin | 5% | Required to keep position |
| Max Leverage | 10x | Per-market cap |
| Base Borrow Rate | 5% APR | When utilization is low |
| Max Borrow Rate | 50% APR | When utilization is high |
| Liquidation Penalty | 5% | Distributed to liquidator/protocol/LPs |

## Roadmap

- [x] Core smart contracts
- [x] Unit tests
- [x] Integration tests
- [x] Documentation
- [ ] Oracle adapters (Polymarket, UMA)
- [ ] Deploy scripts
- [ ] Testnet deployment
- [ ] Frontend
- [ ] Keeper bots
- [ ] Audit
- [ ] Mainnet launch

## Security

- All contracts include reentrancy guards
- Price staleness checks prevent stale oracle attacks
- OI caps limit maximum exposure
- Emergency pause functionality
- Withdrawal delays prevent LP bank runs

**Note:** These contracts have not been audited. Use at your own risk.

## Contributing

We welcome contributions! Please see our [contributing guidelines](CONTRIBUTING.md).

## License

MIT

---

Built by the LEVER team. Follow us on [Twitter](https://twitter.com/leverprotocol).
