import dotenv from 'dotenv';
dotenv.config();

export interface MarketConfig {
  marketId: number;
  name: string;
  polymarketSlug?: string;      // e.g., "will-trump-win-2024"
  polymarketConditionId?: string;
  manualPrice?: number;         // For testing without external API
}

export interface Config {
  // Network
  rpcUrl: string;
  chainId: number;
  
  // Contracts
  priceEngineAddress: string;
  fundingEngineAddress: string;
  
  // Keeper wallet
  privateKey: string;
  
  // Timing
  priceUpdateIntervalMs: number;
  fundingUpdateIntervalMs: number;
  
  // Markets to track
  markets: MarketConfig[];
  
  // Safety
  maxGasPrice: bigint;          // Max gas price in wei
  maxPriceDeviation: number;    // Max % change per update (sanity check)
}

export function loadConfig(): Config {
  const requiredEnvVars = [
    'RPC_URL',
    'KEEPER_PRIVATE_KEY',
    'PRICE_ENGINE_ADDRESS',
    'FUNDING_ENGINE_ADDRESS',
  ];
  
  for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
      throw new Error(`Missing required environment variable: ${envVar}`);
    }
  }
  
  // Parse markets from env (JSON array) or use defaults
  let markets: MarketConfig[] = [];
  if (process.env.MARKETS) {
    markets = JSON.parse(process.env.MARKETS);
  } else {
    // Default test market
    markets = [
      {
        marketId: 0,
        name: "Test Market",
        manualPrice: 0.5,  // 50% for testing
      }
    ];
  }
  
  return {
    rpcUrl: process.env.RPC_URL!,
    chainId: parseInt(process.env.CHAIN_ID || '97'),  // BSC Testnet default
    
    priceEngineAddress: process.env.PRICE_ENGINE_ADDRESS!,
    fundingEngineAddress: process.env.FUNDING_ENGINE_ADDRESS!,
    
    privateKey: process.env.KEEPER_PRIVATE_KEY!,
    
    priceUpdateIntervalMs: parseInt(process.env.PRICE_UPDATE_INTERVAL_MS || '30000'),  // 30s default
    fundingUpdateIntervalMs: parseInt(process.env.FUNDING_UPDATE_INTERVAL_MS || '3600000'),  // 1h default
    
    markets,
    
    maxGasPrice: BigInt(process.env.MAX_GAS_PRICE || '10000000000'),  // 10 gwei default
    maxPriceDeviation: parseFloat(process.env.MAX_PRICE_DEVIATION || '0.1'),  // 10% default
  };
}

// Contract ABIs (minimal)
export const PRICE_ENGINE_ABI = [
  "function updatePrice(uint256 marketId, uint256 newOraclePrice) external",
  "function batchUpdatePrices(uint256[] calldata marketIds, uint256[] calldata prices) external",
  "function getMarkPrice(uint256 marketId) external view returns (uint256)",
  "function getPriceData(uint256 marketId) external view returns (uint256 oraclePrice, uint256 emaPrice, uint256 markPrice, uint256 lastUpdate)",
  "function isPriceStale(uint256 marketId, uint256 maxAge) external view returns (bool)",
  "event PriceUpdated(uint256 indexed marketId, uint256 oraclePrice, uint256 emaPrice, uint256 markPrice)",
];

export const FUNDING_ENGINE_ABI = [
  "function updateFunding(uint256 marketId) external",
  "function batchUpdateFunding(uint256[] calldata marketIds) external",
  "function getCurrentFundingRate(uint256 marketId) external view returns (int256)",
  "function getFundingConfig(uint256 marketId) external view returns (tuple(uint256 maxFundingRate, uint256 fundingPeriod, uint256 imbalanceThreshold, uint256 lastFundingTime, int256 cumulativeFunding))",
  "event FundingUpdated(uint256 indexed marketId, int256 fundingRate, int256 cumulativeFunding)",
];
