// Contract addresses - BSC Testnet (Deployed 2026-02-06)
export const CONTRACTS = {
  // BSC Testnet (Chain ID 97)
  97: {
    USDT: '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58',
    LEDGER: '0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c',
    PRICE_ENGINE: '0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33',       // Old - for execution price
    PRICE_ENGINE_V2: '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC',   // New - for mark price (PI)
    FUNDING_ENGINE: '0xa6Ec543C82c564F9Cdb9a7e7682C68A43D1af802',
    RISK_ENGINE: '0x833D02521a41f175c389ec2A8c86F22E3de524DB',
    ROUTER: '0x346D9eC78F8437c2aa32375584B959ccCDc843E1', // RouterV3 with complete fees
    LP_POOL: '0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1',
    INSURANCE_FUND: '0xB8CA10ADbE4c0666eF701e0D0aeB27cFC5b81932',
  },
} as const;

// Full ABIs with proper typing
export const USDT_ABI = [
  { name: 'balanceOf', type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'approve', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
  { name: 'allowance', type: 'function', stateMutability: 'view', inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'decimals', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint8' }] },
  { name: 'transfer', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
] as const;

export const ROUTER_ABI = [
  { name: 'openPosition', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'marketId', type: 'uint256' }, { name: 'sizeDelta', type: 'int256' }, { name: 'collateralAmount', type: 'uint256' }, { name: 'maxPrice', type: 'uint256' }, { name: 'minPrice', type: 'uint256' }], outputs: [] },
  { name: 'closePosition', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'marketId', type: 'uint256' }, { name: 'sizeDelta', type: 'int256' }, { name: 'minPrice', type: 'uint256' }, { name: 'maxPrice', type: 'uint256' }], outputs: [] },
  { name: 'depositCollateral', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'marketId', type: 'uint256' }, { name: 'amount', type: 'uint256' }], outputs: [] },
  { name: 'withdrawCollateral', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'marketId', type: 'uint256' }, { name: 'amount', type: 'uint256' }], outputs: [] },
] as const;

export const LEDGER_ABI = [
  { 
    name: 'getPosition', 
    type: 'function', 
    stateMutability: 'view', 
    inputs: [{ name: 'trader', type: 'address' }, { name: 'marketId', type: 'uint256' }], 
    outputs: [{ 
      type: 'tuple', 
      components: [
        { name: 'marketId', type: 'uint256' },
        { name: 'size', type: 'int256' },
        { name: 'entryPrice', type: 'uint256' },
        { name: 'collateral', type: 'uint256' },
        { name: 'openTimestamp', type: 'uint256' },
        { name: 'lastFundingIndex', type: 'uint256' },
        { name: 'lastBorrowIndex', type: 'uint256' },
      ]
    }] 
  },
  { 
    name: 'getMarket', 
    type: 'function', 
    stateMutability: 'view', 
    inputs: [{ name: 'marketId', type: 'uint256' }], 
    outputs: [{ 
      type: 'tuple', 
      components: [
        { name: 'oracle', type: 'address' },
        { name: 'totalLongOI', type: 'uint256' },
        { name: 'totalShortOI', type: 'uint256' },
        { name: 'maxOI', type: 'uint256' },
        { name: 'fundingIndex', type: 'uint256' },
        { name: 'borrowIndex', type: 'uint256' },
        { name: 'active', type: 'bool' },
      ]
    }] 
  },
  { name: 'getOIImbalance', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'int256' }] },
  { name: 'getUnrealizedPnL', type: 'function', stateMutability: 'view', inputs: [{ name: 'trader', type: 'address' }, { name: 'marketId', type: 'uint256' }, { name: 'price', type: 'uint256' }], outputs: [{ type: 'int256' }] },
] as const;

export const PRICE_ENGINE_ABI = [
  { name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { name: 'getExecutionPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }, { name: 'sizeDelta', type: 'int256' }], outputs: [{ type: 'uint256' }] },
  { 
    name: 'getPriceData', 
    type: 'function', 
    stateMutability: 'view', 
    inputs: [{ name: 'marketId', type: 'uint256' }], 
    outputs: [
      { name: 'oraclePrice', type: 'uint256' },
      { name: 'emaPrice', type: 'uint256' },
      { name: 'markPrice', type: 'uint256' },
      { name: 'lastUpdate', type: 'uint256' },
    ] 
  },
] as const;

export const FUNDING_ENGINE_ABI = [
  { name: 'getCurrentFundingRate', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'int256' }] },
  { name: 'getPendingFunding', type: 'function', stateMutability: 'view', inputs: [{ name: 'trader', type: 'address' }, { name: 'marketId', type: 'uint256' }], outputs: [{ type: 'int256' }] },
] as const;

// PriceEngineV2 - Smoothed Mark Price (PI)
export const PRICE_ENGINE_V2_ABI = [
  { name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { name: 'getRawPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { 
    name: 'getPriceState', 
    type: 'function', 
    stateMutability: 'view', 
    inputs: [{ name: 'marketId', type: 'uint256' }], 
    outputs: [
      { name: 'rawPrice', type: 'uint256' },
      { name: 'smoothedPrice', type: 'uint256' },
      { name: 'lastUpdate', type: 'uint256' },
      { name: 'volatility', type: 'uint256' },
    ] 
  },
  { 
    name: 'getMarketConfig', 
    type: 'function', 
    stateMutability: 'view', 
    inputs: [{ name: 'marketId', type: 'uint256' }], 
    outputs: [
      { name: 'expiryTimestamp', type: 'uint256' },
      { name: 'maxSpread', type: 'uint256' },
      { name: 'maxTickMovement', type: 'uint256' },
      { name: 'minLiquidityDepth', type: 'uint256' },
      { name: 'alpha', type: 'uint256' },
      { name: 'active', type: 'bool' },
    ] 
  },
  { name: 'getTimeToExpiry', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { name: 'isExpired', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'bool' }] },
] as const;

export const LP_POOL_ABI = [
  { name: 'deposit', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'assets', type: 'uint256' }, { name: 'receiver', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'withdraw', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'shares', type: 'uint256' }, { name: 'receiver', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'balanceOf', type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'totalAssets', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'totalSupply', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'totalAllocated', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'sharePrice', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'utilization', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'availableLiquidity', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'cumulativeFeePerShare', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'pendingFeesOf', type: 'function', stateMutability: 'view', inputs: [{ name: 'user', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'claimFees', type: 'function', stateMutability: 'nonpayable', inputs: [], outputs: [{ type: 'uint256' }] },
] as const;

export const RISK_ENGINE_ABI = [
  { name: 'getRequiredMargin', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }, { name: 'size', type: 'int256' }, { name: 'price', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { name: 'isLiquidatable', type: 'function', stateMutability: 'view', inputs: [{ name: 'trader', type: 'address' }, { name: 'marketId', type: 'uint256' }], outputs: [{ type: 'bool' }] },
] as const;
