import axios from 'axios';
import { logger } from './logger';
import { MarketConfig } from './config';

/**
 * Price feed interface - implement for different data sources
 */
export interface PriceFeed {
  getPrice(market: MarketConfig): Promise<number>;
  getName(): string;
}

/**
 * Polymarket price feed
 * Fetches live probabilities from Polymarket's CLOB API
 */
export class PolymarketPriceFeed implements PriceFeed {
  private baseUrl = 'https://clob.polymarket.com';
  
  getName(): string {
    return 'Polymarket';
  }
  
  async getPrice(market: MarketConfig): Promise<number> {
    if (!market.polymarketConditionId) {
      throw new Error(`No Polymarket condition ID for market ${market.name}`);
    }
    
    try {
      // Fetch market data from Polymarket CLOB
      const response = await axios.get(
        `${this.baseUrl}/markets/${market.polymarketConditionId}`,
        { timeout: 10000 }
      );
      
      const data = response.data;
      
      // Polymarket returns price as decimal (0-1)
      // For binary markets, we want the YES price
      const price = data.tokens?.[0]?.price || data.price || data.probability;
      
      if (typeof price !== 'number' || price < 0 || price > 1) {
        throw new Error(`Invalid price from Polymarket: ${price}`);
      }
      
      logger.debug(`Polymarket price for ${market.name}: ${price}`);
      return price;
      
    } catch (error) {
      if (axios.isAxiosError(error)) {
        logger.error(`Polymarket API error for ${market.name}: ${error.message}`);
      }
      throw error;
    }
  }
}

/**
 * Gamma Markets price feed (Polymarket alternative API)
 */
export class GammaMarketsPriceFeed implements PriceFeed {
  private baseUrl = 'https://gamma-api.polymarket.com';
  
  getName(): string {
    return 'Gamma Markets';
  }
  
  async getPrice(market: MarketConfig): Promise<number> {
    if (!market.polymarketSlug) {
      throw new Error(`No Polymarket slug for market ${market.name}`);
    }
    
    try {
      const response = await axios.get(
        `${this.baseUrl}/markets?slug=${market.polymarketSlug}`,
        { timeout: 10000 }
      );
      
      const data = response.data;
      if (!data || data.length === 0) {
        throw new Error(`Market not found: ${market.polymarketSlug}`);
      }
      
      // Get the best bid/ask midpoint
      const marketData = data[0];
      const price = marketData.outcomePrices?.[0] || marketData.bestBid;
      
      if (typeof price !== 'number' || price < 0 || price > 1) {
        throw new Error(`Invalid price from Gamma: ${price}`);
      }
      
      logger.debug(`Gamma price for ${market.name}: ${price}`);
      return price;
      
    } catch (error) {
      if (axios.isAxiosError(error)) {
        logger.error(`Gamma API error for ${market.name}: ${error.message}`);
      }
      throw error;
    }
  }
}

/**
 * Manual/Mock price feed for testing
 */
export class ManualPriceFeed implements PriceFeed {
  private prices: Map<number, number> = new Map();
  
  getName(): string {
    return 'Manual';
  }
  
  setPrice(marketId: number, price: number): void {
    this.prices.set(marketId, price);
  }
  
  async getPrice(market: MarketConfig): Promise<number> {
    // Check manual override first
    const manualPrice = this.prices.get(market.marketId);
    if (manualPrice !== undefined) {
      return manualPrice;
    }
    
    // Fall back to config
    if (market.manualPrice !== undefined) {
      return market.manualPrice;
    }
    
    throw new Error(`No manual price set for market ${market.name}`);
  }
  
  // Simulate price movement for testing
  simulatePriceMovement(marketId: number, volatility: number = 0.01): void {
    const currentPrice = this.prices.get(marketId) || 0.5;
    const change = (Math.random() - 0.5) * 2 * volatility;
    const newPrice = Math.max(0.01, Math.min(0.99, currentPrice + change));
    this.prices.set(marketId, newPrice);
    logger.debug(`Simulated price for market ${marketId}: ${newPrice.toFixed(4)}`);
  }
}

/**
 * Aggregated price feed - tries multiple sources with fallback
 */
export class AggregatedPriceFeed implements PriceFeed {
  private feeds: PriceFeed[];
  
  constructor(feeds: PriceFeed[]) {
    this.feeds = feeds;
  }
  
  getName(): string {
    return 'Aggregated';
  }
  
  async getPrice(market: MarketConfig): Promise<number> {
    const errors: Error[] = [];
    
    for (const feed of this.feeds) {
      try {
        const price = await feed.getPrice(market);
        logger.debug(`Got price from ${feed.getName()}: ${price}`);
        return price;
      } catch (error) {
        errors.push(error as Error);
        logger.warn(`${feed.getName()} failed for ${market.name}, trying next...`);
      }
    }
    
    throw new Error(
      `All price feeds failed for ${market.name}: ${errors.map(e => e.message).join(', ')}`
    );
  }
}

/**
 * Create the default price feed based on environment
 */
export function createPriceFeed(useTestMode: boolean = false): PriceFeed {
  if (useTestMode || process.env.USE_MANUAL_PRICES === 'true') {
    logger.info('Using manual price feed (test mode)');
    return new ManualPriceFeed();
  }
  
  // Production: try Polymarket, fall back to Gamma, then manual
  return new AggregatedPriceFeed([
    new PolymarketPriceFeed(),
    new GammaMarketsPriceFeed(),
    new ManualPriceFeed(),
  ]);
}
