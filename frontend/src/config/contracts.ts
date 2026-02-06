// Contract addresses - BSC Testnet
// Last updated: 2026-02-06 21:45 UTC
export const CONTRACTS = {
  // BSC Testnet (Chain ID 97)
  97: {
    // Core tokens
    USDT: '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58',
    
    // Main contracts (V4/V6 - Position ID model)
    ROUTER: '0xF8d1b25b8cdf5C5e9a55f6E34f97e4E86ea387bB',       // RouterV6 - Position IDs
    LEDGER: '0x63477383dcA29747790b46dD5052fCA333D6A985',       // PositionLedgerV4 (Position IDs, multiple per market)
    VAMM: '0xAb015aE92092996ad3dc95a8874183c0Fb5f9938',         // vAMM (entry price)
    PRICE_ENGINE: '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC', // PriceEngineV2 (smoothed PI)
    RISK_ENGINE: '0x543ccaD81A2EDEd2dc785272fCba899512a161B4',  // SimpleRiskEngine
    BORROW_FEE_ENGINE: '0xc68e5b17f286624E31c468147360D36eA672BD35', // BorrowFeeEngineV2
    FUNDING_ENGINE: '0xa6Ec543C82c564F9Cdb9a7e7682C68A43D1af802',
    LP_POOL: '0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1',
    INSURANCE_FUND: '0xB8CA10ADbE4c0666eF701e0D0aeB27cFC5b81932',
    
    // Deprecated V5/V3 (kept for reference)
    ROUTER_V5: '0xee92ef898a0eabca96cad863cb0303b6d13cc023',
    LEDGER_V3: '0x74b24940c76c53cb0e9f0194cc79f6c08cf79f73',
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
  // RouterV6 signatures - Position ID model
  { name: 'openPosition', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'marketId', type: 'uint256' }, { name: 'isLong', type: 'bool' }, { name: 'collateralAmount', type: 'uint256' }, { name: 'leverage', type: 'uint256' }, { name: 'maxSlippage', type: 'uint256' }], outputs: [{ name: 'positionId', type: 'uint256' }, { name: 'positionSize', type: 'uint256' }, { name: 'entryPrice', type: 'uint256' }] },
  { name: 'closePosition', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'positionId', type: 'uint256' }, { name: 'minAmountOut', type: 'uint256' }], outputs: [{ name: 'pnl', type: 'int256' }, { name: 'amountOut', type: 'uint256' }] },
  { name: 'decreasePosition', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'positionId', type: 'uint256' }, { name: 'closePercent', type: 'uint256' }, { name: 'minAmountOut', type: 'uint256' }], outputs: [{ name: 'pnl', type: 'int256' }, { name: 'amountOut', type: 'uint256' }] },
  { name: 'addCollateral', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'positionId', type: 'uint256' }, { name: 'amount', type: 'uint256' }], outputs: [] },
  { name: 'removeCollateral', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'positionId', type: 'uint256' }, { name: 'amount', type: 'uint256' }], outputs: [] },
  { name: 'previewOpenPosition', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }, { name: 'isLong', type: 'bool' }, { name: 'collateral', type: 'uint256' }, { name: 'leverage', type: 'uint256' }], outputs: [{ name: 'positionSize', type: 'uint256' }, { name: 'expectedEntryPrice', type: 'uint256' }, { name: 'markPrice', type: 'uint256' }, { name: 'priceImpact', type: 'uint256' }, { name: 'estimatedDailyFee', type: 'uint256' }] },
  { name: 'getPositionDetails', type: 'function', stateMutability: 'view', inputs: [{ name: 'positionId', type: 'uint256' }], outputs: [{ name: 'position', type: 'tuple', components: [{ name: 'id', type: 'uint256' }, { name: 'owner', type: 'address' }, { name: 'marketId', type: 'uint256' }, { name: 'side', type: 'uint8' }, { name: 'size', type: 'uint256' }, { name: 'entryPrice', type: 'uint256' }, { name: 'collateral', type: 'uint256' }, { name: 'openTimestamp', type: 'uint256' }, { name: 'isOpen', type: 'bool' }, { name: 'lastFeeUpdate', type: 'uint256' }, { name: 'settledFees', type: 'uint256' }, { name: 'lastBorrowIndex', type: 'uint256' }, { name: 'lastFundingIndex', type: 'int256' }] }, { name: 'markPrice', type: 'uint256' }, { name: 'unrealizedPnL', type: 'int256' }, { name: 'pendingFees', type: 'uint256' }, { name: 'equity', type: 'int256' }, { name: 'liquidationPrice', type: 'uint256' }] },
  { name: 'getUserOpenPositions', type: 'function', stateMutability: 'view', inputs: [{ name: 'user', type: 'address' }], outputs: [{ name: 'positions', type: 'tuple[]', components: [{ name: 'id', type: 'uint256' }, { name: 'owner', type: 'address' }, { name: 'marketId', type: 'uint256' }, { name: 'side', type: 'uint8' }, { name: 'size', type: 'uint256' }, { name: 'entryPrice', type: 'uint256' }, { name: 'collateral', type: 'uint256' }, { name: 'openTimestamp', type: 'uint256' }, { name: 'isOpen', type: 'bool' }, { name: 'lastFeeUpdate', type: 'uint256' }, { name: 'settledFees', type: 'uint256' }, { name: 'lastBorrowIndex', type: 'uint256' }, { name: 'lastFundingIndex', type: 'int256' }] }] },
  { name: 'getUserMarketPositionIds', type: 'function', stateMutability: 'view', inputs: [{ name: 'user', type: 'address' }, { name: 'marketId', type: 'uint256' }], outputs: [{ name: 'positionIds', type: 'uint256[]' }] },
] as const;

export const LEDGER_ABI = [
  { 
    name: 'getPosition', 
    type: 'function', 
    stateMutability: 'view', 
    inputs: [{ name: 'positionId', type: 'uint256' }], 
    outputs: [{ 
      type: 'tuple', 
      components: [
        { name: 'id', type: 'uint256' },
        { name: 'owner', type: 'address' },
        { name: 'marketId', type: 'uint256' },
        { name: 'side', type: 'uint8' },
        { name: 'size', type: 'uint256' },
        { name: 'entryPrice', type: 'uint256' },
        { name: 'collateral', type: 'uint256' },
        { name: 'openTimestamp', type: 'uint256' },
        { name: 'isOpen', type: 'bool' },
        { name: 'lastFeeUpdate', type: 'uint256' },
        { name: 'settledFees', type: 'uint256' },
        { name: 'lastBorrowIndex', type: 'uint256' },
        { name: 'lastFundingIndex', type: 'int256' },
      ]
    }] 
  },
  {
    name: 'getUserOpenPositions',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ 
      type: 'tuple[]', 
      components: [
        { name: 'id', type: 'uint256' },
        { name: 'owner', type: 'address' },
        { name: 'marketId', type: 'uint256' },
        { name: 'side', type: 'uint8' },
        { name: 'size', type: 'uint256' },
        { name: 'entryPrice', type: 'uint256' },
        { name: 'collateral', type: 'uint256' },
        { name: 'openTimestamp', type: 'uint256' },
        { name: 'isOpen', type: 'bool' },
        { name: 'lastFeeUpdate', type: 'uint256' },
        { name: 'settledFees', type: 'uint256' },
        { name: 'lastBorrowIndex', type: 'uint256' },
        { name: 'lastFundingIndex', type: 'int256' },
      ]
    }]
  },
  {
    name: 'getUserMarketPositionIds',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }, { name: 'marketId', type: 'uint256' }],
    outputs: [{ type: 'uint256[]' }]
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
        { name: 'borrowIndex', type: 'uint256' },
        { name: 'fundingIndex', type: 'int256' },
        { name: 'resolutionTime', type: 'uint256' },
        { name: 'liveStartTime', type: 'uint256' },
        { name: 'isLive', type: 'bool' },
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
