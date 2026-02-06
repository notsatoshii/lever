# Deployment Guide

## Target Network: BSC Testnet

| Property | Value |
|----------|-------|
| Chain ID | 97 |
| RPC | https://data-seed-prebsc-1-s1.binance.org:8545 |
| Explorer | https://testnet.bscscan.com |
| USDT | 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd |
| Faucet | https://testnet.bnbchain.org/faucet-smart |

## Prerequisites

- Foundry installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- Node.js 18+ (for scripts)
- Deployer wallet with BNB for gas (get from faucet)

## Environment Setup

```bash
# Clone repo
git clone https://github.com/notsatoshii/lever.git
cd lever/contracts

# Install dependencies
forge install foundry-rs/forge-std

# Create .env file
cat > .env << EOF
DEPLOYER_PRIVATE_KEY=0x_your_private_key_here
DEPLOYER_ADDRESS=0x_your_address_here
BSC_TESTNET_RPC=https://data-seed-prebsc-1-s1.binance.org:8545
BSCSCAN_API_KEY=your_bscscan_api_key
EOF
```

## Quick Deploy (BSC Testnet)

```bash
# Load environment
source .env

# Deploy all contracts
forge script script/Deploy.s.sol \
    --rpc-url $BSC_TESTNET_RPC \
    --broadcast \
    --verify \
    --etherscan-api-key $BSCSCAN_API_KEY

# Create a market (after deployment)
export LEDGER_ADDRESS=0x...
export PRICE_ENGINE_ADDRESS=0x...
export FUNDING_ENGINE_ADDRESS=0x...
export RISK_ENGINE_ADDRESS=0x...
export LP_POOL_ADDRESS=0x...
export ORACLE_ADDRESS=0x...  # Your price oracle

forge script script/Deploy.s.sol:CreateMarketScript \
    --rpc-url $BSC_TESTNET_RPC \
    --broadcast
```

## Manual Deployment Order

Contracts must be deployed in this order due to dependencies:

### 1. Position Ledger

```solidity
// USDT on BSC Testnet: 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd
PositionLedger ledger = new PositionLedger(USDT_ADDRESS);
```

The ledger is the core data store. All other contracts depend on it.

### 2. Price Engine

```solidity
PriceEngine priceEngine = new PriceEngine(address(ledger));

// Authorize keeper(s)
priceEngine.setKeeperAuthorization(KEEPER_ADDRESS, true);
```

### 3. Funding Engine

```solidity
FundingEngine fundingEngine = new FundingEngine(address(ledger));

// Authorize keeper(s)
fundingEngine.setKeeperAuthorization(KEEPER_ADDRESS, true);
```

### 4. Risk Engine

```solidity
RiskEngine riskEngine = new RiskEngine(address(ledger));
```

### 5. LP Pool

```solidity
LPPool lpPool = new LPPool(USDC_ADDRESS);
```

### 6. Liquidation Engine

```solidity
LiquidationEngine liquidationEngine = new LiquidationEngine(
    address(ledger),
    USDC_ADDRESS,
    PROTOCOL_FEE_RECIPIENT,
    address(lpPool)
);

// Connect to other engines
liquidationEngine.setEngines(address(riskEngine), address(priceEngine));
```

### 7. Router

```solidity
Router router = new Router(
    address(ledger),
    address(priceEngine),
    address(riskEngine),
    USDC_ADDRESS
);
```

## Authorization Setup

After deployment, configure access control:

```solidity
// Authorize engines on Position Ledger
ledger.setEngineAuthorization(address(router), true);
ledger.setEngineAuthorization(address(liquidationEngine), true);
ledger.setEngineAuthorization(address(fundingEngine), true);
ledger.setEngineAuthorization(address(riskEngine), true);

// Authorize LP Pool allocators
lpPool.setAllocatorAuthorization(address(router), true);
lpPool.setAllocatorAuthorization(address(liquidationEngine), true);
```

## Market Configuration

### Create Market

```solidity
// Create market on ledger
uint256 marketId = ledger.createMarket(
    ORACLE_ADDRESS,  // Price oracle
    1_000_000e18     // Max OI per side
);
```

### Configure Price Engine

```solidity
priceEngine.configurePricing(
    marketId,
    ORACLE_ADDRESS,
    3600,           // EMA period (1 hour)
    500,            // Max deviation (5%)
    10_000_000e18   // vAMM depth
);
```

### Configure Funding Engine

```solidity
fundingEngine.configureFunding(
    marketId,
    0.001e18,       // Max funding rate per period (0.1%)
    8 hours,        // Funding period
    100_000e18      // Imbalance threshold for max rate
);
```

### Configure Risk Engine

```solidity
riskEngine.setRiskParams(
    marketId,
    1000,           // Initial margin: 10%
    500,            // Maintenance margin: 5%
    10,             // Max leverage: 10x
    0.05e18,        // Base borrow rate: 5% APR
    0.50e18,        // Max borrow rate: 50% APR
    0.8e18,         // Optimal utilization: 80%
    500             // Liquidation penalty: 5%
);

// Set LP capital (from LP Pool)
riskEngine.setLPCapital(marketId, lpPool.totalAssets());
```

## Initialization

### Set Initial Price

```solidity
// Keeper sets initial price
priceEngine.updatePrice(marketId, INITIAL_PROBABILITY);
```

### Seed LP Pool

```solidity
// Initial LPs deposit
usdc.approve(address(lpPool), amount);
lpPool.deposit(amount, depositor);
```

## Verification

After deployment, verify contracts on block explorer:

```bash
forge verify-contract \
    --chain-id <CHAIN_ID> \
    --constructor-args $(cast abi-encode "constructor(address)" $USDC_ADDRESS) \
    <LEDGER_ADDRESS> \
    src/PositionLedger.sol:PositionLedger

# Repeat for all contracts...
```

## Testnet Deployment

For testnet (Sepolia, Goerli, etc.):

1. Use testnet USDC or deploy mock
2. Use lower OI caps
3. Use shorter time periods for testing
4. Fund keeper wallet

```bash
# Deploy to Sepolia
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify
```

## Mainnet Deployment Checklist

- [ ] All contracts audited
- [ ] Multisig set as owner
- [ ] Timelock for parameter changes
- [ ] Emergency pause tested
- [ ] Keeper infrastructure ready
- [ ] Monitoring/alerting configured
- [ ] Initial LP capital ready
- [ ] Oracle integration tested
- [ ] Slippage parameters tuned
- [ ] Documentation published

## Post-Deployment

1. **Transfer Ownership**: Move ownership to multisig
2. **Set Up Keepers**: Configure keeper bots for price/funding updates
3. **Monitor**: Set up monitoring for liquidations, utilization, etc.
4. **Seed Liquidity**: Initial LP deposits

## Emergency Procedures

### Pause Single Market

```solidity
riskEngine.setMarketPaused(marketId, true);
```

### Global Pause

```solidity
riskEngine.setGlobalPause(true);
```

### Disable Market

```solidity
ledger.setMarketActive(marketId, false);
```
