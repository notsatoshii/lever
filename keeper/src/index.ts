import { loadConfig } from './config';
import { Keeper } from './keeper';
import { createPriceFeed, ManualPriceFeed } from './priceFeed';
import { logger } from './logger';

async function main() {
  logger.info('🚀 Starting LEVER Keeper Bot...');
  
  // Load configuration
  const config = loadConfig();
  logger.info(`Network: Chain ID ${config.chainId}`);
  logger.info(`Price update interval: ${config.priceUpdateIntervalMs / 1000}s`);
  logger.info(`Funding update interval: ${config.fundingUpdateIntervalMs / 1000 / 60}min`);
  
  // Create price feed
  const isTestMode = process.env.TEST_MODE === 'true';
  const priceFeed = createPriceFeed(isTestMode);
  logger.info(`Price feed: ${priceFeed.getName()}`);
  
  // Create keeper
  const keeper = new Keeper(config, priceFeed);
  
  // Initial balance check
  await keeper.checkBalance();
  
  // If using manual feed in test mode, initialize with config prices
  if (priceFeed instanceof ManualPriceFeed) {
    for (const market of config.markets) {
      if (market.manualPrice !== undefined) {
        priceFeed.setPrice(market.marketId, market.manualPrice);
      }
    }
  }
  
  // Price update loop
  const priceLoop = async () => {
    try {
      await keeper.updatePrices();
    } catch (error) {
      logger.error(`Price loop error: ${error}`);
    }
  };
  
  // Funding update loop
  const fundingLoop = async () => {
    try {
      await keeper.updateFunding();
    } catch (error) {
      logger.error(`Funding loop error: ${error}`);
    }
  };
  
  // Status loop (every 5 minutes)
  const statusLoop = async () => {
    try {
      await keeper.logStatus();
    } catch (error) {
      logger.error(`Status loop error: ${error}`);
    }
  };
  
  // Simulate price movement for testing
  const simulationLoop = () => {
    if (priceFeed instanceof ManualPriceFeed && isTestMode) {
      for (const market of config.markets) {
        priceFeed.simulatePriceMovement(market.marketId, 0.005);
      }
    }
  };
  
  // Run immediately on start
  await priceLoop();
  
  // Schedule loops
  setInterval(priceLoop, config.priceUpdateIntervalMs);
  setInterval(fundingLoop, config.fundingUpdateIntervalMs);
  setInterval(statusLoop, 5 * 60 * 1000); // Every 5 minutes
  
  if (isTestMode) {
    setInterval(simulationLoop, config.priceUpdateIntervalMs);
    logger.info('🧪 Test mode: Simulating price movements');
  }
  
  // Handle shutdown
  const shutdown = async () => {
    logger.info('Shutting down keeper...');
    const stats = keeper.getStats();
    logger.info(`Final stats: ${JSON.stringify(stats)}`);
    process.exit(0);
  };
  
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
  
  logger.info('✅ Keeper bot running. Press Ctrl+C to stop.');
}

main().catch((error) => {
  logger.error(`Fatal error: ${error}`);
  process.exit(1);
});
