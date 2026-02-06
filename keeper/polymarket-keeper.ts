import { createWalletClient, createPublicClient, http, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

// Config
const PRICE_ENGINE = '0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33';
const RPC_URL = 'https://data-seed-prebsc-1-s1.binance.org:8545';
const POLYMARKET_API = 'https://gamma-api.polymarket.com';
const UPDATE_INTERVAL = 30_000; // 30 seconds

// Market mappings: Our market ID → Polymarket slug
const MARKET_MAPPINGS: { id: number; name: string; slug: string }[] = [
  { id: 1, name: 'MicroStrategy BTC Sale', slug: 'will-microstrategy-sell-any-bitcoin-before-2027' },
  { id: 2, name: 'Trump Deportations 250-500k', slug: 'will-trump-deport-250000-500000-people' },
  { id: 3, name: 'GTA 6 $100+', slug: 'will-gta-6-cost-100' },
  // New markets (to be added via AddMarketsV2)
  { id: 4, name: 'US Revenue <$100b', slug: 'will-the-us-collect-less-than-100b-in-revenue-in-2025' },
  { id: 5, name: 'Tariffs >$250b', slug: 'will-tariffs-generate-250b-in-2025' },
  { id: 6, name: 'US Revenue $500b-$1t', slug: 'will-the-us-collect-between-500b-and-1t-in-revenue-in-2025' },
  { id: 7, name: 'US Revenue $100b-$200b', slug: 'will-the-us-collect-between-100b-and-200b-in-revenue-in-2025' },
  { id: 8, name: 'Trump Deport <250k', slug: 'will-trump-deport-less-than-250000' },
];

const PRICE_ENGINE_ABI = [
  {
    name: 'updatePrice',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'newOraclePrice', type: 'uint256' },
    ],
    outputs: [],
  },
] as const;

interface PolymarketMarket {
  slug: string;
  outcomePrices: string;
}

// Fetch price from Polymarket
async function fetchPolymarketPrice(slug: string): Promise<number | null> {
  try {
    const response = await fetch(`${POLYMARKET_API}/markets?slug=${slug}`);
    if (!response.ok) return null;
    
    const markets: PolymarketMarket[] = await response.json();
    if (markets.length === 0) return null;
    
    const prices = JSON.parse(markets[0].outcomePrices || '["0.5", "0.5"]');
    return parseFloat(prices[0]) || 0.5;
  } catch (error) {
    console.error(`Failed to fetch ${slug}:`, error);
    return null;
  }
}

async function main() {
  let privateKey = process.env.KEEPER_PRIVATE_KEY;
  if (!privateKey) {
    console.error('KEEPER_PRIVATE_KEY not set');
    console.error('Usage: KEEPER_PRIVATE_KEY=0x... npx ts-node polymarket-keeper.ts');
    process.exit(1);
  }

  // Clean up the key
  privateKey = privateKey.trim().replace(/['"]/g, '');
  if (!privateKey.startsWith('0x')) {
    privateKey = '0x' + privateKey;
  }

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

  console.log('🔮 Polymarket → LEVER Price Keeper');
  console.log(`🔑 Keeper address: ${account.address}`);
  console.log(`📊 Syncing ${MARKET_MAPPINGS.length} markets every ${UPDATE_INTERVAL / 1000}s`);
  console.log('');

  async function syncPrices() {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] Syncing prices from Polymarket...`);
    
    for (const market of MARKET_MAPPINGS) {
      try {
        // Fetch from Polymarket
        const price = await fetchPolymarketPrice(market.slug);
        
        if (price === null) {
          console.log(`  ⚠️  Market ${market.id} (${market.name}): No data from Polymarket`);
          continue;
        }

        // Clamp price to valid range
        const clampedPrice = Math.min(0.99, Math.max(0.01, price));
        const priceWei = parseUnits(clampedPrice.toFixed(18), 18);

        console.log(`  📈 Market ${market.id} (${market.name}): ${(clampedPrice * 100).toFixed(2)}%`);

        // Update on-chain
        const hash = await walletClient.writeContract({
          address: PRICE_ENGINE,
          abi: PRICE_ENGINE_ABI,
          functionName: 'updatePrice',
          args: [BigInt(market.id), priceWei],
        });

        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        console.log(`     ✅ TX: ${hash.slice(0, 18)}... Block: ${receipt.blockNumber}`);
        
        // Small delay between updates to avoid nonce issues
        await new Promise(resolve => setTimeout(resolve, 1000));
        
      } catch (error: any) {
        console.error(`  ❌ Market ${market.id}: ${error.message?.slice(0, 80)}`);
      }
    }
    console.log('');
  }

  // Initial sync
  await syncPrices();

  // Schedule syncs
  setInterval(syncPrices, UPDATE_INTERVAL);
  
  console.log('⏰ Keeper running. Press Ctrl+C to stop.');
}

main().catch(console.error);
