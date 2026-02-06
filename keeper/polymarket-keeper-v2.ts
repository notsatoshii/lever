/**
 * Polymarket → LEVER Price Keeper V2
 * 
 * Implements the Anti-Manipulation Shield from the architecture:
 * 1. Fetches raw prices from Polymarket
 * 2. Validates: spread, tick movement, liquidity depth
 * 3. Submits to PriceEngineV2 for smoothing (volatility + time-weighted)
 * 
 * The keeper is the "Input Layer" - PriceEngineV2 handles the "Smoothing Engine"
 */

import { createWalletClient, createPublicClient, http, parseUnits, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

// ============ CONFIG ============

const RPC_URL = 'https://data-seed-prebsc-1-s1.binance.org:8545';
const POLYMARKET_API = 'https://gamma-api.polymarket.com';
const POLYMARKET_CLOB_API = 'https://clob.polymarket.com';
const UPDATE_INTERVAL = 30_000; // 30 seconds
const INTEREST_ACCRUAL_INTERVAL = 3600_000; // 1 hour

// Contract addresses
const PRICE_ENGINE_V2 = process.env.PRICE_ENGINE_V2 || '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';
const RISK_ENGINE = process.env.RISK_ENGINE || '0x833D02521a41f175c389ec2A8c86F22E3de524DB';

// Market mappings with expiry dates
interface MarketConfig {
  id: number;
  name: string;
  slug: string;
  conditionId?: string;  // Polymarket condition ID for CLOB API
  expiry: number;        // Unix timestamp
}

const MARKET_MAPPINGS: MarketConfig[] = [
  { 
    id: 1, 
    name: 'MicroStrategy BTC Sale', 
    slug: 'will-microstrategy-sell-any-bitcoin-before-2027',
    expiry: 1798761600  // Jan 1, 2027
  },
  { 
    id: 2, 
    name: 'Trump Deportations 250-500k', 
    slug: 'will-trump-deport-250000-500000-people',
    expiry: 1767225600  // Jan 1, 2026
  },
  { 
    id: 3, 
    name: 'GTA 6 $100+', 
    slug: 'will-gta-6-cost-100',
    expiry: 1767225600  // Jan 1, 2026
  },
  { 
    id: 4, 
    name: 'US Revenue <$100b', 
    slug: 'will-the-us-collect-less-than-100b-in-revenue-in-2025',
    expiry: 1767225600  // Jan 1, 2026
  },
  { 
    id: 5, 
    name: 'Tariffs >$250b', 
    slug: 'will-tariffs-generate-250b-in-2025',
    expiry: 1767225600  // Jan 1, 2026
  },
];

// ============ ABIs ============

const RISK_ENGINE_ABI = [
  {
    name: 'accrueInterest',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'marketId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'borrowIndex',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'marketId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

const PRICE_ENGINE_V2_ABI = [
  {
    name: 'updatePrice',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'rawPrice', type: 'uint256' },
      { name: 'spread', type: 'uint256' },
      { name: 'liquidityDepth', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    name: 'updatePriceSimple',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'rawPrice', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    name: 'batchUpdatePrices',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketIds', type: 'uint256[]' },
      { name: 'rawPrices', type: 'uint256[]' },
    ],
    outputs: [],
  },
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
    ],
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
    ],
  },
  {
    name: 'isExpired',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'marketId', type: 'uint256' }],
    outputs: [{ name: '', type: 'bool' }],
  },
] as const;

// ============ TYPES ============

interface PolymarketMarket {
  slug: string;
  outcomePrices: string;
  volume: string;
  liquidity: string;
  spread?: number;
}

interface OrderbookData {
  bids: { price: string; size: string }[];
  asks: { price: string; size: string }[];
}

interface PriceData {
  price: number;
  spread: number;        // basis points
  liquidityDepth: number; // in dollars
  source: 'gamma' | 'clob';
}

// ============ POLYMARKET FETCHERS ============

/**
 * Fetch price from Polymarket Gamma API (simple, always available)
 */
async function fetchGammaPrice(slug: string): Promise<PriceData | null> {
  try {
    const response = await fetch(`${POLYMARKET_API}/markets?slug=${slug}`);
    if (!response.ok) return null;
    
    const markets: PolymarketMarket[] = await response.json();
    if (markets.length === 0) return null;
    
    const market = markets[0];
    const prices = JSON.parse(market.outcomePrices || '["0.5", "0.5"]');
    const price = parseFloat(prices[0]) || 0.5;
    
    // Gamma API doesn't give us spread directly, estimate from liquidity
    const liquidity = parseFloat(market.liquidity || '0');
    
    // Estimate spread: less liquidity = wider spread
    // $100k+ liquidity = ~50bp spread, $10k = ~200bp, <$1k = ~500bp
    let estimatedSpread = 500; // basis points
    if (liquidity > 100000) estimatedSpread = 50;
    else if (liquidity > 50000) estimatedSpread = 100;
    else if (liquidity > 10000) estimatedSpread = 200;
    else if (liquidity > 1000) estimatedSpread = 300;
    
    return {
      price,
      spread: estimatedSpread,
      liquidityDepth: liquidity,
      source: 'gamma'
    };
  } catch (error) {
    console.error(`[Gamma] Failed to fetch ${slug}:`, error);
    return null;
  }
}

/**
 * Fetch price from Polymarket CLOB API (more accurate, requires conditionId)
 */
async function fetchClobPrice(conditionId: string): Promise<PriceData | null> {
  try {
    // Fetch orderbook
    const response = await fetch(`${POLYMARKET_CLOB_API}/book?token_id=${conditionId}`);
    if (!response.ok) return null;
    
    const book: OrderbookData = await response.json();
    
    if (book.bids.length === 0 || book.asks.length === 0) return null;
    
    // Best bid/ask
    const bestBid = parseFloat(book.bids[0].price);
    const bestAsk = parseFloat(book.asks[0].price);
    
    // Mid price
    const price = (bestBid + bestAsk) / 2;
    
    // Spread in basis points
    const spread = ((bestAsk - bestBid) / price) * 10000;
    
    // Liquidity depth: sum of top 5 levels on each side
    let bidDepth = 0, askDepth = 0;
    for (let i = 0; i < Math.min(5, book.bids.length); i++) {
      bidDepth += parseFloat(book.bids[i].size) * parseFloat(book.bids[i].price);
    }
    for (let i = 0; i < Math.min(5, book.asks.length); i++) {
      askDepth += parseFloat(book.asks[i].size) * parseFloat(book.asks[i].price);
    }
    
    return {
      price,
      spread: Math.round(spread),
      liquidityDepth: Math.min(bidDepth, askDepth),
      source: 'clob'
    };
  } catch (error) {
    // CLOB API may not be available for all markets
    return null;
  }
}

/**
 * Fetch price with fallback: CLOB → Gamma
 */
async function fetchPrice(market: MarketConfig): Promise<PriceData | null> {
  // Try CLOB first if we have conditionId
  if (market.conditionId) {
    const clobData = await fetchClobPrice(market.conditionId);
    if (clobData) return clobData;
  }
  
  // Fallback to Gamma
  return fetchGammaPrice(market.slug);
}

// ============ MAIN ============

async function main() {
  // Setup
  let privateKey = process.env.KEEPER_PRIVATE_KEY;
  if (!privateKey) {
    console.error('❌ KEEPER_PRIVATE_KEY not set');
    console.error('Usage: KEEPER_PRIVATE_KEY=0x... PRICE_ENGINE_V2=0x... npx ts-node polymarket-keeper-v2.ts');
    process.exit(1);
  }

  if (PRICE_ENGINE_V2 === '0x0000000000000000000000000000000000000000') {
    console.error('❌ PRICE_ENGINE_V2 address not set');
    console.error('Set via env: PRICE_ENGINE_V2=0x...');
    process.exit(1);
  }

  privateKey = privateKey.trim().replace(/['"]/g, '');
  if (!privateKey.startsWith('0x')) privateKey = '0x' + privateKey;

  const account = privateKeyToAccount(privateKey as `0x${string}`);
  
  const publicClient = createPublicClient({
    chain: bscTestnet,
    transport: http(RPC_URL),
  });

  const walletClient = createWalletClient({
    account,
    chain: bscTestnet,
    transport: http(RPC_URL),
  });

  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║     🔮 LEVER Price Keeper V2 - Anti-Manipulation Shield    ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log(`  🔑 Keeper:      ${account.address}`);
  console.log(`  📍 PriceEngine: ${PRICE_ENGINE_V2}`);
  console.log(`  📊 Markets:     ${MARKET_MAPPINGS.length}`);
  console.log(`  ⏱️  Interval:    ${UPDATE_INTERVAL / 1000}s`);
  console.log('');
  console.log('  Architecture: Polymarket → Keeper (validate) → PriceEngineV2 (smooth) → Mark Price');
  console.log('');

  // Track stats
  let totalUpdates = 0;
  let rejectedUpdates = 0;

  async function syncPrices() {
    const timestamp = new Date().toISOString().replace('T', ' ').slice(0, 19);
    console.log(`[${timestamp}] ────────────────────────────────────────`);
    
    // Collect valid prices for batch update
    const validMarketIds: bigint[] = [];
    const validPrices: bigint[] = [];
    
    for (const market of MARKET_MAPPINGS) {
      try {
        // Check if market is expired on-chain
        const isExpired = await publicClient.readContract({
          address: PRICE_ENGINE_V2 as `0x${string}`,
          abi: PRICE_ENGINE_V2_ABI,
          functionName: 'isExpired',
          args: [BigInt(market.id)],
        });
        
        if (isExpired) {
          console.log(`  ⏰ Market ${market.id} (${market.name}): EXPIRED - skipping`);
          continue;
        }
        
        // Fetch price data
        const data = await fetchPrice(market);
        
        if (!data) {
          console.log(`  ⚠️  Market ${market.id} (${market.name}): No data`);
          continue;
        }
        
        // Clamp price to valid range (1% - 99%)
        const clampedPrice = Math.min(0.99, Math.max(0.01, data.price));
        
        // Get current on-chain state for comparison
        let currentPrice = 0;
        let currentVol = 0;
        try {
          const [rawPrice, smoothedPrice, , volatility] = await publicClient.readContract({
            address: PRICE_ENGINE_V2 as `0x${string}`,
            abi: PRICE_ENGINE_V2_ABI,
            functionName: 'getPriceState',
            args: [BigInt(market.id)],
          }) as [bigint, bigint, bigint, bigint];
          
          currentPrice = Number(smoothedPrice) / 1e18;
          currentVol = Number(volatility) / 1e18;
        } catch (e) {
          // First update for this market
        }
        
        // Log with details
        const priceChange = currentPrice > 0 
          ? ((clampedPrice - currentPrice) / currentPrice * 100).toFixed(2)
          : 'NEW';
        
        console.log(`  📈 Market ${market.id} (${market.name}):`);
        console.log(`     Price: ${(clampedPrice * 100).toFixed(2)}% (Δ${priceChange}%) | Spread: ${data.spread}bp | Liq: $${data.liquidityDepth.toLocaleString()} | σ: ${(currentVol * 100).toFixed(1)}%`);
        
        // Add to batch
        validMarketIds.push(BigInt(market.id));
        validPrices.push(parseUnits(clampedPrice.toFixed(18), 18));
        
      } catch (error: any) {
        console.error(`  ❌ Market ${market.id}: ${error.message?.slice(0, 60)}`);
        rejectedUpdates++;
      }
    }
    
    // Batch update all valid prices
    if (validMarketIds.length > 0) {
      try {
        console.log(`  📤 Submitting batch update for ${validMarketIds.length} markets...`);
        
        const hash = await walletClient.writeContract({
          address: PRICE_ENGINE_V2 as `0x${string}`,
          abi: PRICE_ENGINE_V2_ABI,
          functionName: 'batchUpdatePrices',
          args: [validMarketIds, validPrices],
        });
        
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        console.log(`  ✅ Batch TX: ${hash.slice(0, 20)}... Block: ${receipt.blockNumber}`);
        totalUpdates += validMarketIds.length;
        
      } catch (error: any) {
        // If batch fails, try individual updates
        console.log(`  ⚠️  Batch failed, trying individual updates...`);
        
        for (let i = 0; i < validMarketIds.length; i++) {
          try {
            const hash = await walletClient.writeContract({
              address: PRICE_ENGINE_V2 as `0x${string}`,
              abi: PRICE_ENGINE_V2_ABI,
              functionName: 'updatePriceSimple',
              args: [validMarketIds[i], validPrices[i]],
            });
            
            await publicClient.waitForTransactionReceipt({ hash });
            console.log(`     ✅ Market ${validMarketIds[i]}: ${hash.slice(0, 16)}...`);
            totalUpdates++;
            
            // Small delay between individual updates
            await new Promise(r => setTimeout(r, 500));
            
          } catch (e: any) {
            console.log(`     ❌ Market ${validMarketIds[i]}: ${e.message?.slice(0, 40)}`);
            rejectedUpdates++;
          }
        }
      }
    }
    
    console.log(`  📊 Stats: ${totalUpdates} updates | ${rejectedUpdates} rejected`);
    console.log('');
  }

  // ============ INTEREST ACCRUAL ============
  
  async function accrueInterestForAllMarkets() {
    if (RISK_ENGINE === '0x0000000000000000000000000000000000000000') {
      console.log('  ⚠️  RISK_ENGINE not set, skipping interest accrual');
      return;
    }
    
    const timestamp = new Date().toISOString().replace('T', ' ').slice(0, 19);
    console.log(`[${timestamp}] ──── INTEREST ACCRUAL ────`);
    
    for (const market of MARKET_MAPPINGS) {
      try {
        // Get current borrow index for logging
        const indexBefore = await publicClient.readContract({
          address: RISK_ENGINE as `0x${string}`,
          abi: RISK_ENGINE_ABI,
          functionName: 'borrowIndex',
          args: [BigInt(market.id)],
        });
        
        // Accrue interest
        const hash = await walletClient.writeContract({
          address: RISK_ENGINE as `0x${string}`,
          abi: RISK_ENGINE_ABI,
          functionName: 'accrueInterest',
          args: [BigInt(market.id)],
        });
        
        await publicClient.waitForTransactionReceipt({ hash });
        
        // Get new index
        const indexAfter = await publicClient.readContract({
          address: RISK_ENGINE as `0x${string}`,
          abi: RISK_ENGINE_ABI,
          functionName: 'borrowIndex',
          args: [BigInt(market.id)],
        });
        
        const growth = Number(indexAfter - indexBefore) / 1e18 * 100;
        console.log(`  📈 Market ${market.id}: Index ${Number(indexBefore)/1e18} → ${Number(indexAfter)/1e18} (+${growth.toFixed(4)}%)`);
        
      } catch (error: any) {
        // Might fail if market not configured, that's ok
        if (!error.message?.includes('not configured')) {
          console.log(`  ⚠️  Market ${market.id}: ${error.message?.slice(0, 50)}`);
        }
      }
    }
    console.log('');
  }

  // Initial sync
  await syncPrices();
  
  // Initial interest accrual
  await accrueInterestForAllMarkets();

  // Schedule price syncs (every 30s)
  setInterval(syncPrices, UPDATE_INTERVAL);
  
  // Schedule interest accrual (every hour)
  setInterval(accrueInterestForAllMarkets, INTEREST_ACCRUAL_INTERVAL);
  
  console.log('⏰ Keeper running:');
  console.log(`   - Price updates: every ${UPDATE_INTERVAL/1000}s`);
  console.log(`   - Interest accrual: every ${INTEREST_ACCRUAL_INTERVAL/1000/60} minutes`);
  console.log('');
  console.log('Press Ctrl+C to stop.');
  console.log('');
}

main().catch(console.error);
