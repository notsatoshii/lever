# LEVER Protocol API Reference

## Router (User-Facing)

The Router is the main entry point for traders.

### openPosition

Opens or increases a position.

```solidity
function openPosition(
    uint256 marketId,      // Market to trade
    int256 sizeDelta,      // Size change (+ = long, - = short)
    uint256 collateralAmount,  // USDC to deposit
    uint256 maxPrice,      // Slippage protection for longs
    uint256 minPrice       // Slippage protection for shorts
) external
```

**Example: Open 10x Long**
```solidity
// Deposit 1000 USDC, get ~10,000 notional exposure at 50% probability
router.openPosition(
    0,              // marketId
    20_000e18,      // size (positive = long)
    1_000e6,        // 1000 USDC collateral
    0.55e18,        // max price (55%)
    0               // min price (not used for longs)
);
```

### closePosition

Closes or reduces a position.

```solidity
function closePosition(
    uint256 marketId,
    int256 sizeDelta,      // Opposite sign to close
    uint256 minPrice,      // Min price for closing longs
    uint256 maxPrice       // Max price for closing shorts
) external
```

**Example: Close Long**
```solidity
router.closePosition(
    0,              // marketId
    -20_000e18,     // negative = reduce/close long
    0.45e18,        // min price to receive
    type(uint256).max  // max price (not used)
);
```

### depositCollateral

Add collateral to existing position.

```solidity
function depositCollateral(uint256 marketId, uint256 amount) external
```

### withdrawCollateral

Remove collateral (if margin allows).

```solidity
function withdrawCollateral(uint256 marketId, uint256 amount) external
```

### getPositionWithPnL

View current position with PnL.

```solidity
function getPositionWithPnL(
    address trader,
    uint256 marketId
) external view returns (
    Position memory position,
    int256 unrealizedPnL,
    uint256 currentPrice,
    bool isLiquidatable
)
```

### previewTrade

Preview execution before trading.

```solidity
function previewTrade(
    uint256 marketId,
    int256 sizeDelta,
    uint256 collateral
) external view returns (
    uint256 executionPrice,
    uint256 requiredMargin,
    uint256 maxLeverage,
    bool marginOk
)
```

---

## LP Pool

For liquidity providers.

### deposit

Deposit USDT, receive LP tokens.

```solidity
function deposit(uint256 assets, address receiver) external returns (uint256 shares)
```

**Example:**
```solidity
usdt.approve(address(lpPool), 10_000e18);
uint256 shares = lpPool.deposit(10_000e18, msg.sender);
```

### withdraw

Instant withdrawal (if liquidity available).

```solidity
function withdraw(uint256 shares, address receiver) external returns (uint256 assets)
```

### requestWithdrawal / processWithdrawal

Queued withdrawal for large amounts.

```solidity
function requestWithdrawal(uint256 shares) external
function processWithdrawal(address receiver) external returns (uint256 assets)
```

### View Functions

```solidity
function sharePrice() external view returns (uint256)
function availableLiquidity() external view returns (uint256)
function utilization() external view returns (uint256)
function pendingFeesOf(address user) external view returns (uint256)
function convertToShares(uint256 assets) external view returns (uint256)
function convertToAssets(uint256 shares) external view returns (uint256)
```

---

## Position Ledger (Read-Only for Users)

### getPosition

```solidity
function getPosition(
    address trader,
    uint256 marketId
) external view returns (Position memory)

struct Position {
    uint256 marketId;
    int256 size;           // Positive = long, negative = short
    uint256 entryPrice;    // Entry probability (0-1e18)
    uint256 collateral;    // USDC deposited
    uint256 openTimestamp;
    uint256 lastFundingIndex;
    uint256 lastBorrowIndex;
}
```

### getMarket

```solidity
function getMarket(uint256 marketId) external view returns (Market memory)

struct Market {
    address oracle;
    uint256 totalLongOI;
    uint256 totalShortOI;
    uint256 maxOI;
    uint256 fundingIndex;
    uint256 borrowIndex;
    bool active;
}
```

### getOIImbalance

```solidity
function getOIImbalance(uint256 marketId) external view returns (int256)
// Positive = more longs, Negative = more shorts
```

### getUnrealizedPnL

```solidity
function getUnrealizedPnL(
    address trader,
    uint256 marketId,
    uint256 currentPrice
) external view returns (int256 pnl)
```

---

## Price Engine

### getMarkPrice

Current mark price for a market.

```solidity
function getMarkPrice(uint256 marketId) external view returns (uint256)
```

### getExecutionPrice

Price after slippage for a given trade size.

```solidity
function getExecutionPrice(
    uint256 marketId,
    int256 sizeDelta
) external view returns (uint256 executionPrice)
```

### getPriceData

Full price information.

```solidity
function getPriceData(uint256 marketId) external view returns (
    uint256 oraclePrice,
    uint256 emaPrice,
    uint256 markPrice,
    uint256 lastUpdate
)
```

### isPriceStale

Check if price is too old.

```solidity
function isPriceStale(uint256 marketId, uint256 maxAge) external view returns (bool)
```

---

## Risk Engine

### isLiquidatable

Check if position can be liquidated.

```solidity
function isLiquidatable(
    address trader,
    uint256 marketId,
    uint256 currentPrice
) external view returns (bool liquidatable, uint256 shortfall)
```

### getRequiredCollateral

Get margin requirements for a position size.

```solidity
function getRequiredCollateral(
    uint256 marketId,
    uint256 size,
    uint256 price
) external view returns (uint256 initial, uint256 maintenance)
```

### getUtilization

Current pool utilization and borrow rate.

```solidity
function getUtilization(uint256 marketId) external view returns (UtilizationData memory)

struct UtilizationData {
    uint256 totalOI;
    uint256 totalLPCapital;
    uint256 utilization;
    uint256 currentBorrowRate;
}
```

### getPendingBorrowFee

Borrow fees owed by a position.

```solidity
function getPendingBorrowFee(
    address trader,
    uint256 marketId
) external view returns (uint256 fee)
```

### getMaxPositionSize

Max size for given collateral.

```solidity
function getMaxPositionSize(
    uint256 marketId,
    uint256 collateral,
    uint256 price
) external view returns (uint256)
```

---

## Funding Engine

### getCurrentFundingRate

Current funding rate (annualized).

```solidity
function getCurrentFundingRate(uint256 marketId) external view returns (int256)
// Positive = longs pay, Negative = shorts pay
```

### getPendingFunding

Funding owed/receivable by a position.

```solidity
function getPendingFunding(
    address trader,
    uint256 marketId
) external view returns (int256 payment)
// Positive = owes, Negative = receives
```

---

## Liquidation Engine

### canLiquidate

Check if position is liquidatable.

```solidity
function canLiquidate(address trader, uint256 marketId) external view returns (bool)
```

### previewLiquidation

Preview liquidation result.

```solidity
function previewLiquidation(
    address trader,
    uint256 marketId
) external view returns (LiquidationResult memory)

struct LiquidationResult {
    address trader;
    uint256 marketId;
    int256 positionSize;
    uint256 collateral;
    int256 pnl;
    uint256 penalty;
    uint256 liquidatorReward;
    uint256 protocolFee;
    uint256 lpRecovery;
}
```

### liquidate

Execute liquidation (anyone can call).

```solidity
function liquidate(
    address trader,
    uint256 marketId
) external returns (LiquidationResult memory)
```

---

## Events

### Position Events
```solidity
event PositionOpened(address indexed trader, uint256 indexed marketId, int256 size, uint256 entryPrice, uint256 collateral);
event PositionModified(address indexed trader, uint256 indexed marketId, int256 sizeDelta, uint256 newCollateral);
event PositionClosed(address indexed trader, uint256 indexed marketId, int256 realizedPnL);
event PositionLiquidated(address indexed trader, uint256 indexed marketId, address liquidator, uint256 penalty);
```

### Price Events
```solidity
event PriceUpdated(uint256 indexed marketId, uint256 oraclePrice, uint256 emaPrice, uint256 markPrice);
```

### Funding Events
```solidity
event FundingUpdated(uint256 indexed marketId, int256 fundingRate, int256 cumulativeFunding);
```

### LP Events
```solidity
event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
event FeesAccrued(uint256 amount, uint256 newCumulativeFeePerShare);
```

---

## Error Codes

```solidity
error Unauthorized();           // Caller not authorized
error MarketNotActive();        // Market is paused/disabled
error MarketNotFound();         // Market doesn't exist
error PositionNotFound();       // No position exists
error ExceedsMaxOI();          // Would exceed OI cap
error InsufficientCollateral(); // Not enough collateral
error InsufficientMargin();     // Below margin requirement
error InvalidSize();            // Size is zero or invalid
error InvalidPrice();           // Price out of range
error StalePrice();            // Price too old
error NotLiquidatable();       // Position is healthy
error InsufficientLiquidity(); // LP pool can't cover
error ReentrantCall();         // Reentrancy detected
```
