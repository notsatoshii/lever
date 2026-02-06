// Contract addresses - BSC Testnet (Deployed 2026-02-06)
export const CONTRACTS = {
  // BSC Testnet (Chain ID 97)
  97: {
    USDT: process.env.NEXT_PUBLIC_USDT_ADDRESS || '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58',
    LEDGER: process.env.NEXT_PUBLIC_LEDGER_ADDRESS || '0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c',
    PRICE_ENGINE: process.env.NEXT_PUBLIC_PRICE_ENGINE_ADDRESS || '0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33',
    FUNDING_ENGINE: process.env.NEXT_PUBLIC_FUNDING_ENGINE_ADDRESS || '0xa6Ec543C82c564F9Cdb9a7e7682C68A43D1af802',
    RISK_ENGINE: process.env.NEXT_PUBLIC_RISK_ENGINE_ADDRESS || '0x833D02521a41f175c389ec2A8c86F22E3de524DB',
    ROUTER: process.env.NEXT_PUBLIC_ROUTER_ADDRESS || '0x34A73a10a953A69d9Ee8453BFef0d6fB12c105a7',
    LP_POOL: process.env.NEXT_PUBLIC_LP_POOL_ADDRESS || '0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1',
    INSURANCE_FUND: '0xB8CA10ADbE4c0666eF701e0D0aeB27cFC5b81932',
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
