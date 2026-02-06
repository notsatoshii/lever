import { ethers } from 'ethers';
import { Config, PRICE_ENGINE_ABI, FUNDING_ENGINE_ABI, MarketConfig } from './config';
import { PriceFeed } from './priceFeed';
import { logger } from './logger';

export class Keeper {
  private config: Config;
  private provider: ethers.JsonRpcProvider;
  private wallet: ethers.Wallet;
  private priceEngine: ethers.Contract;
  private fundingEngine: ethers.Contract;
  private priceFeed: PriceFeed;
  
  // Track last prices for sanity checks
  private lastPrices: Map<number, number> = new Map();
  
  // Stats
  private stats = {
    priceUpdates: 0,
    fundingUpdates: 0,
    errors: 0,
    startTime: Date.now(),
  };
  
  constructor(config: Config, priceFeed: PriceFeed) {
    this.config = config;
    this.priceFeed = priceFeed;
    
    // Setup provider and wallet
    this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
    this.wallet = new ethers.Wallet(config.privateKey, this.provider);
    
    // Setup contracts
    this.priceEngine = new ethers.Contract(
      config.priceEngineAddress,
      PRICE_ENGINE_ABI,
      this.wallet
    );
    
    this.fundingEngine = new ethers.Contract(
      config.fundingEngineAddress,
      FUNDING_ENGINE_ABI,
      this.wallet
    );
    
    logger.info(`Keeper initialized`);
    logger.info(`  Address: ${this.wallet.address}`);
    logger.info(`  PriceEngine: ${config.priceEngineAddress}`);
    logger.info(`  FundingEngine: ${config.fundingEngineAddress}`);
    logger.info(`  Markets: ${config.markets.length}`);
  }
  
  /**
   * Update prices for all markets
   */
  async updatePrices(): Promise<void> {
    logger.info('Starting price update cycle...');
    
    const marketIds: bigint[] = [];
    const prices: bigint[] = [];
    
    for (const market of this.config.markets) {
      try {
        // Fetch price from feed
        const price = await this.priceFeed.getPrice(market);
        
        // Sanity check: price should be between 0 and 1
        if (price <= 0 || price >= 1) {
          logger.warn(`Skipping ${market.name}: price ${price} out of bounds`);
          continue;
        }
        
        // Sanity check: price shouldn't deviate too much from last update
        const lastPrice = this.lastPrices.get(market.marketId);
        if (lastPrice !== undefined) {
          const deviation = Math.abs(price - lastPrice) / lastPrice;
          if (deviation > this.config.maxPriceDeviation) {
            logger.warn(
              `Skipping ${market.name}: deviation ${(deviation * 100).toFixed(2)}% exceeds max ${this.config.maxPriceDeviation * 100}%`
            );
            continue;
          }
        }
        
        // Convert to 18 decimals
        const priceWei = ethers.parseEther(price.toString());
        
        marketIds.push(BigInt(market.marketId));
        prices.push(priceWei);
        this.lastPrices.set(market.marketId, price);
        
        logger.info(`  ${market.name}: ${(price * 100).toFixed(2)}%`);
        
      } catch (error) {
        logger.error(`Failed to get price for ${market.name}: ${error}`);
        this.stats.errors++;
      }
    }
    
    if (marketIds.length === 0) {
      logger.warn('No valid prices to update');
      return;
    }
    
    // Check gas price
    const feeData = await this.provider.getFeeData();
    const gasPrice = feeData.gasPrice || 0n;
    
    if (gasPrice > this.config.maxGasPrice) {
      logger.warn(`Gas price ${gasPrice} exceeds max ${this.config.maxGasPrice}, skipping update`);
      return;
    }
    
    try {
      // Batch update if multiple markets, single update otherwise
      let tx: ethers.TransactionResponse;
      
      if (marketIds.length === 1) {
        tx = await this.priceEngine.updatePrice(marketIds[0], prices[0], {
          gasPrice,
        });
      } else {
        tx = await this.priceEngine.batchUpdatePrices(marketIds, prices, {
          gasPrice,
        });
      }
      
      logger.info(`Price update tx: ${tx.hash}`);
      
      // Wait for confirmation
      const receipt = await tx.wait();
      logger.info(`  Confirmed in block ${receipt?.blockNumber}, gas used: ${receipt?.gasUsed}`);
      
      this.stats.priceUpdates++;
      
    } catch (error) {
      logger.error(`Price update transaction failed: ${error}`);
      this.stats.errors++;
    }
  }
  
  /**
   * Update funding rates for all markets
   */
  async updateFunding(): Promise<void> {
    logger.info('Starting funding update cycle...');
    
    const marketIds = this.config.markets.map(m => BigInt(m.marketId));
    
    // Check gas price
    const feeData = await this.provider.getFeeData();
    const gasPrice = feeData.gasPrice || 0n;
    
    if (gasPrice > this.config.maxGasPrice) {
      logger.warn(`Gas price ${gasPrice} exceeds max ${this.config.maxGasPrice}, skipping update`);
      return;
    }
    
    try {
      const tx = await this.fundingEngine.batchUpdateFunding(marketIds, {
        gasPrice,
      });
      
      logger.info(`Funding update tx: ${tx.hash}`);
      
      const receipt = await tx.wait();
      logger.info(`  Confirmed in block ${receipt?.blockNumber}, gas used: ${receipt?.gasUsed}`);
      
      this.stats.fundingUpdates++;
      
      // Log current funding rates
      for (const market of this.config.markets) {
        try {
          const rate = await this.fundingEngine.getCurrentFundingRate(market.marketId);
          const ratePercent = Number(rate) / 1e18 * 100;
          logger.info(`  ${market.name} funding rate: ${ratePercent.toFixed(4)}%`);
        } catch (e) {
          // Ignore
        }
      }
      
    } catch (error) {
      logger.error(`Funding update transaction failed: ${error}`);
      this.stats.errors++;
    }
  }
  
  /**
   * Check keeper wallet balance
   */
  async checkBalance(): Promise<void> {
    const balance = await this.provider.getBalance(this.wallet.address);
    const balanceEth = ethers.formatEther(balance);
    
    logger.info(`Keeper balance: ${balanceEth} BNB`);
    
    // Warn if low
    if (balance < ethers.parseEther('0.1')) {
      logger.warn('⚠️ Keeper balance is low! Please fund the wallet.');
    }
  }
  
  /**
   * Get current stats
   */
  getStats() {
    const uptimeMs = Date.now() - this.stats.startTime;
    const uptimeHours = (uptimeMs / 1000 / 60 / 60).toFixed(2);
    
    return {
      ...this.stats,
      uptimeHours,
      address: this.wallet.address,
    };
  }
  
  /**
   * Log current status
   */
  async logStatus(): Promise<void> {
    const stats = this.getStats();
    
    logger.info('=== Keeper Status ===');
    logger.info(`  Uptime: ${stats.uptimeHours} hours`);
    logger.info(`  Price updates: ${stats.priceUpdates}`);
    logger.info(`  Funding updates: ${stats.fundingUpdates}`);
    logger.info(`  Errors: ${stats.errors}`);
    
    await this.checkBalance();
    
    // Log current prices
    logger.info('Current prices:');
    for (const market of this.config.markets) {
      try {
        const priceData = await this.priceEngine.getPriceData(market.marketId);
        const markPrice = Number(priceData.markPrice) / 1e18 * 100;
        logger.info(`  ${market.name}: ${markPrice.toFixed(2)}%`);
      } catch (e) {
        logger.info(`  ${market.name}: (not configured)`);
      }
    }
  }
}
