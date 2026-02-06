// Contract addresses - UPDATE THESE AFTER DEPLOYMENT
export const CONTRACTS = {
  // BSC Testnet (Chain ID 97)
  97: {
    USDT: process.env.NEXT_PUBLIC_USDT_ADDRESS || '',
    LEDGER: process.env.NEXT_PUBLIC_LEDGER_ADDRESS || '',
    PRICE_ENGINE: process.env.NEXT_PUBLIC_PRICE_ENGINE_ADDRESS || '',
    FUNDING_ENGINE: process.env.NEXT_PUBLIC_FUNDING_ENGINE_ADDRESS || '',
    RISK_ENGINE: process.env.NEXT_PUBLIC_RISK_ENGINE_ADDRESS || '',
    ROUTER: process.env.NEXT_PUBLIC_ROUTER_ADDRESS || '',
    LP_POOL: process.env.NEXT_PUBLIC_LP_POOL_ADDRESS || '',
  },
} as const;

// Contract ABIs
export const USDT_ABI = [
  'function balanceOf(address) view returns (uint256)',
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function decimals() view returns (uint8)',
] as const;

export const ROUTER_ABI = [
  'function openPosition(uint256 marketId, int256 sizeDelta, uint256 collateralAmount, uint256 maxPrice, uint256 minPrice)',
  'function closePosition(uint256 marketId, int256 sizeDelta, uint256 minPrice, uint256 maxPrice)',
  'function depositCollateral(uint256 marketId, uint256 amount)',
  'function withdrawCollateral(uint256 marketId, uint256 amount)',
  'function getPositionWithPnL(address trader, uint256 marketId) view returns (tuple(uint256 marketId, int256 size, uint256 entryPrice, uint256 collateral, uint256 openTimestamp, uint256 lastFundingIndex, uint256 lastBorrowIndex), int256, uint256, bool)',
  'function previewTrade(uint256 marketId, int256 sizeDelta, uint256 collateral) view returns (uint256, uint256, uint256, bool)',
] as const;

export const LEDGER_ABI = [
  'function getPosition(address trader, uint256 marketId) view returns (tuple(uint256 marketId, int256 size, uint256 entryPrice, uint256 collateral, uint256 openTimestamp, uint256 lastFundingIndex, uint256 lastBorrowIndex))',
  'function getMarket(uint256 marketId) view returns (tuple(address oracle, uint256 totalLongOI, uint256 totalShortOI, uint256 maxOI, uint256 fundingIndex, uint256 borrowIndex, bool active))',
  'function getUnrealizedPnL(address trader, uint256 marketId, uint256 currentPrice) view returns (int256)',
  'function getOIImbalance(uint256 marketId) view returns (int256)',
] as const;

export const PRICE_ENGINE_ABI = [
  'function getMarkPrice(uint256 marketId) view returns (uint256)',
  'function getExecutionPrice(uint256 marketId, int256 sizeDelta) view returns (uint256)',
  'function getPriceData(uint256 marketId) view returns (uint256 oraclePrice, uint256 emaPrice, uint256 markPrice, uint256 lastUpdate)',
] as const;

export const FUNDING_ENGINE_ABI = [
  'function getCurrentFundingRate(uint256 marketId) view returns (int256)',
  'function getPendingFunding(address trader, uint256 marketId) view returns (int256)',
] as const;

export const LP_POOL_ABI = [
  'function deposit(uint256 assets, address receiver) returns (uint256)',
  'function withdraw(uint256 shares, address receiver) returns (uint256)',
  'function balanceOf(address) view returns (uint256)',
  'function totalAssets() view returns (uint256)',
  'function totalSupply() view returns (uint256)',
  'function sharePrice() view returns (uint256)',
  'function convertToShares(uint256 assets) view returns (uint256)',
  'function convertToAssets(uint256 shares) view returns (uint256)',
  'function availableLiquidity() view returns (uint256)',
  'function utilization() view returns (uint256)',
] as const;
