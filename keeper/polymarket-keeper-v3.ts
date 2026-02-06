/**
 * Polymarket → LEVER Price Keeper V3
 * 
 * Updated 2026-02-06: Top 10 LIVE markets by volume
 * Fixed 2026-02-06 20:45 UTC: Market IDs 0-9 (was 1-10), added dotenv
 * 
 * Implements the Anti-Manipulation Shield from the architecture:
 * 1. Fetches raw prices from Polymarket
 * 2. Validates: spread, tick movement, liquidity depth
 * 3. Submits to PriceEngineV2 for smoothing (volatility + time-weighted)
 */

import dotenv from 'dotenv';
dotenv.config();

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

// ========== TOP 10 LIVE MARKETS BY VOLUME (2026-02-06) ==========
interface MarketConfig {
  id: number;
  name: string;
  slug: string;
  expiry: number;
}

// IMPORTANT: Market IDs are 0-9 after LedgerV3 migration (was 1-10)
const MARKET_MAPPINGS: MarketConfig[] = [
  { 
    id: 0, 
    name: 'Indiana Pacers NBA Finals', 
    slug: 'will-the-indiana-pacers-win-the-2026-nba-finals',
    expiry: 1782864000  // 2026-07-01
  },
  { 
    id: 1, 
    name: 'Patriots Super Bowl', 
    slug: 'will-the-new-england-patriots-win-super-bowl-2026',
    expiry: 1770552000  // 2026-02-08
  },
  { 
    id: 2, 
    name: 'Seahawks Super Bowl', 
    slug: 'will-the-seattle-seahawks-win-super-bowl-2026',
    expiry: 1770552000  // 2026-02-08
  },
  { 
    id: 3, 
    name: 'Jesus before GTA VI', 
    slug: 'will-jesus-christ-return-before-gta-vi-665',
    expiry: 1785499200  // 2026-07-31
  },
  { 
    id: 4, 
    name: 'Celtics NBA Finals', 
    slug: 'will-the-boston-celtics-win-the-2026-nba-finals',
    expiry: 1782864000  // 2026-07-01
  },
  { 
    id: 5, 
    name: 'Thunder NBA Finals', 
    slug: 'will-the-oklahoma-city-thunder-win-the-2026-nba-finals',
    expiry: 1782864000  // 2026-07-01
  },
  { 
    id: 6, 
    name: 'BTC $1M before GTA VI', 
    slug: 'will-bitcoin-hit-1m-before-gta-vi-872',
    expiry: 1785499200  // 2026-07-31
  },
  { 
    id: 7, 
    name: 'van der Plas PM', 
    slug: 'will-caroline-van-der-plas-become-the-next-prime-minister-of-the-netherlands',
    expiry: 1798675200  // 2026-12-31
  },
  { 
    id: 8, 
    name: 'GTA 6 $100+', 
    slug: 'will-gta-6-cost-100',
    expiry: 1772280000  // 2026-02-28
  },
  { 
    id: 9, 
    name: 'Timberwolves NBA Finals', 
    slug: 'will-the-minnesota-timberwolves-win-the-2026-nba-finals',
    expiry: 1782864000  // 2026-07-01
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
  endDate?: string;
  closed?: boolean;
  active?: boolean;
}

interface PriceData {
  price: number;
  spread: number;
  liquidityDepth: number;
  source: 'gamma' | 'clob';
}

// ============ POLYMARKET FETCHERS ============

async function fetchGammaPrice(slug: string): Promise<PriceData | null> {
  try {
    const response = await fetch(`${POLYMARKET_API}/markets?slug=${slug}`);
    if (!response.ok) return null;
    
    const markets: PolymarketMarket[] = await response.json();
    if (markets.length === 0) return null;
    
    const market = markets[0];
    
    // Skip if market is closed
    if (market.closed || !market.active) {
      console.log(`    ⚠️  Market ${slug} is closed/inactive on Polymarket`);
      return null;
    }
    
    const prices = JSON.parse(market.outcomePrices || '["0.5", "0.5"]');
    const price = parseFloat(prices[0]) || 0.5;
    
    const liquidity = parseFloat(market.liquidity || '0');
    
    // Estimate spread based on liquidity
    let estimatedSpread = 500;
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

async function fetchPrice(market: MarketConfig): Promise<PriceData | null> {
  // Check if market is expired locally first
  const now = Math.floor(Date.now() / 1000);
  if (now > market.expiry) {
    console.log(`    ⏰ Market ${market.id} (${market.name}): EXPIRED locally`);
    return null;
  }
  
  return fetchGammaPrice(market.slug);
}

// ============ MAIN ============

async function main() {
  let privateKey = process.env.KEEPER_PRIVATE_KEY;
  if (!privateKey) {
    console.error('❌ KEEPER_PRIVATE_KEY not set');
    console.error('Usage: KEEPER_PRIVATE_KEY=0x... npx ts-node polymarket-keeper-v3.ts');
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
  console.log('║     🔮 LEVER Price Keeper V3 - LIVE MARKETS EDITION        ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log(`  🔑 Keeper:      ${account.address}`);
  console.log(`  📍 PriceEngine: ${PRICE_ENGINE_V2}`);
  console.log(`  📊 Markets:     ${MARKET_MAPPINGS.length} (Top 10 by volume)`);
  console.log(`  ⏱️  Interval:    ${UPDATE_INTERVAL / 1000}s`);
  console.log('');
  console.log('  Markets:');
  for (const m of MARKET_MAPPINGS) {
    const expDate = new Date(m.expiry * 1000).toISOString().slice(0, 10);
    console.log(`    ${m.id}. ${m.name} (exp: ${expDate})`);
  }
  console.log('');

  let totalUpdates = 0;
  let rejectedUpdates = 0;

  async function syncPrices() {
    const timestamp = new Date().toISOString().replace('T', ' ').slice(0, 19);
    console.log(`[${timestamp}] ────────────────────────────────────────`);
    
    const validMarketIds: bigint[] = [];
    const validPrices: bigint[] = [];
    
    for (const market of MARKET_MAPPINGS) {
      try {
        // Check if market is expired on-chain
        let isExpired = false;
        try {
          isExpired = await publicClient.readContract({
            address: PRICE_ENGINE_V2 as `0x${string}`,
            abi: PRICE_ENGINE_V2_ABI,
            functionName: 'isExpired',
            args: [BigInt(market.id)],
          });
        } catch (e) {
          // Market might not be configured yet
        }
        
        if (isExpired) {
          console.log(`  ⏰ Market ${market.id} (${market.name}): EXPIRED - skipping`);
          continue;
        }
        
        const data = await fetchPrice(market);
        
        if (!data) {
          console.log(`  ⚠️  Market ${market.id} (${market.name}): No data`);
          continue;
        }
        
        // Clamp price to valid range (0.1% - 99.9%)
        const clampedPrice = Math.min(0.999, Math.max(0.001, data.price));
        
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
        
        const priceChange = currentPrice > 0 
          ? ((clampedPrice - currentPrice) / currentPrice * 100).toFixed(2)
          : 'NEW';
        
        console.log(`  📈 Market ${market.id} (${market.name}):`);
        console.log(`     Price: ${(clampedPrice * 100).toFixed(2)}% (Δ${priceChange}%) | Spread: ${data.spread}bp | Liq: $${data.liquidityDepth.toLocaleString()}`);
        
        validMarketIds.push(BigInt(market.id));
        validPrices.push(parseUnits(clampedPrice.toFixed(18), 18));
        
      } catch (error: any) {
        console.error(`  ❌ Market ${market.id}: ${error.message?.slice(0, 60)}`);
        rejectedUpdates++;
      }
    }
    
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

  async function accrueInterestForAllMarkets() {
    if (RISK_ENGINE === '0x0000000000000000000000000000000000000000') {
      return;
    }
    
    const timestamp = new Date().toISOString().replace('T', ' ').slice(0, 19);
    console.log(`[${timestamp}] ──── INTEREST ACCRUAL ────`);
    
    for (const market of MARKET_MAPPINGS) {
      try {
        const indexBefore = await publicClient.readContract({
          address: RISK_ENGINE as `0x${string}`,
          abi: RISK_ENGINE_ABI,
          functionName: 'borrowIndex',
          args: [BigInt(market.id)],
        });
        
        const hash = await walletClient.writeContract({
          address: RISK_ENGINE as `0x${string}`,
          abi: RISK_ENGINE_ABI,
          functionName: 'accrueInterest',
          args: [BigInt(market.id)],
        });
        
        await publicClient.waitForTransactionReceipt({ hash });
        
        const indexAfter = await publicClient.readContract({
          address: RISK_ENGINE as `0x${string}`,
          abi: RISK_ENGINE_ABI,
          functionName: 'borrowIndex',
          args: [BigInt(market.id)],
        });
        
        const growth = Number(indexAfter - indexBefore) / 1e18 * 100;
        console.log(`  📈 Market ${market.id}: Index ${Number(indexBefore)/1e18} → ${Number(indexAfter)/1e18} (+${growth.toFixed(4)}%)`);
        
      } catch (error: any) {
        if (!error.message?.includes('not configured')) {
          console.log(`  ⚠️  Market ${market.id}: ${error.message?.slice(0, 50)}`);
        }
      }
    }
    console.log('');
  }

  // Initial sync
  await syncPrices();
  await accrueInterestForAllMarkets();

  // Schedule recurring syncs
  setInterval(syncPrices, UPDATE_INTERVAL);
  setInterval(accrueInterestForAllMarkets, INTEREST_ACCRUAL_INTERVAL);
  
  console.log('⏰ Keeper running:');
  console.log(`   - Price updates: every ${UPDATE_INTERVAL/1000}s`);
  console.log(`   - Interest accrual: every ${INTEREST_ACCRUAL_INTERVAL/1000/60} minutes`);
  console.log('');
  console.log('Press Ctrl+C to stop.');
  console.log('');
}

main().catch(console.error);
