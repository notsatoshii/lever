import { createWalletClient, createPublicClient, http, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

// Config
const PRICE_ENGINE = '0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33';
const RPC_URL = 'https://data-seed-prebsc-1-s1.binance.org:8545';
const UPDATE_INTERVAL = 60_000; // 1 minute

// Markets and their mock prices
// Starting at 50% and will drift with variance over time
// (Initial setup was 50%, can't deviate more than 10% at once)
const MARKETS = [
  { id: 1, name: 'MicroStrategy BTC Sale', price: 0.50 },
  { id: 2, name: 'Trump Deportations', price: 0.50 },
  { id: 3, name: 'GTA 6 $100+', price: 0.50 },
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

async function main() {
  let privateKey = process.env.KEEPER_PRIVATE_KEY;
  if (!privateKey) {
    console.error('KEEPER_PRIVATE_KEY not set');
    console.error('Usage: KEEPER_PRIVATE_KEY=0x... npm start');
    process.exit(1);
  }

  // Clean up the key - remove quotes, add 0x if missing
  privateKey = privateKey.trim().replace(/['"]/g, '');
  if (!privateKey.startsWith('0x')) {
    privateKey = '0x' + privateKey;
  }

  console.log(`🔑 Key length: ${privateKey.length} chars`);
  
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

  console.log(`🔑 Keeper address: ${account.address}`);
  console.log(`📊 Updating ${MARKETS.length} markets every ${UPDATE_INTERVAL / 1000}s`);

  async function updatePrices() {
    const timestamp = new Date().toISOString();
    console.log(`\n[${timestamp}] Updating prices...`);
    
    for (const market of MARKETS) {
      try {
        // Add some random variance to simulate price movement (±2%)
        const variance = 1 + (Math.random() - 0.5) * 0.04;
        const price = Math.min(0.99, Math.max(0.01, market.price * variance));
        const priceWei = parseUnits(price.toFixed(18), 18);

        console.log(`  Market ${market.id} (${market.name}): ${(price * 100).toFixed(2)}%`);

        const hash = await walletClient.writeContract({
          address: PRICE_ENGINE,
          abi: PRICE_ENGINE_ABI,
          functionName: 'updatePrice',
          args: [BigInt(market.id), priceWei],
        });

        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        console.log(`    ✅ Confirmed in block ${receipt.blockNumber}`);
        
      } catch (error: any) {
        console.error(`    ❌ Market ${market.id} error: ${error.message?.slice(0, 100)}`);
      }
    }
  }

  // Initial update
  await updatePrices();

  // Schedule updates
  setInterval(updatePrices, UPDATE_INTERVAL);
  
  console.log('\n⏰ Keeper running. Press Ctrl+C to stop.');
}

main().catch(console.error);
