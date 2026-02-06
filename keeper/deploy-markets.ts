/**
 * Deploy/Reset Markets Script
 * Uses viem to send transactions to BSC Testnet
 */

import { createWalletClient, createPublicClient, http, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

const RPC_URL = 'https://data-seed-prebsc-1-s1.binance.org:8545';
const PRICE_ENGINE_V2 = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';

// Top 10 LIVE markets by volume (2026-02-06)
const MARKETS = [
  { id: 1, name: 'Indiana Pacers NBA', price: 0.0015, expiry: 1782864000 },
  { id: 2, name: 'Patriots Super Bowl', price: 0.318, expiry: 1770552000 },
  { id: 3, name: 'Seahawks Super Bowl', price: 0.6823, expiry: 1770552000 },
  { id: 4, name: 'Jesus/GTA VI', price: 0.485, expiry: 1785499200 },
  { id: 5, name: 'Celtics NBA', price: 0.0665, expiry: 1782864000 },
  { id: 6, name: 'Thunder NBA', price: 0.365, expiry: 1782864000 },
  { id: 7, name: 'BTC $1M/GTA VI', price: 0.485, expiry: 1785499200 },
  { id: 8, name: 'van der Plas PM', price: 0.001, expiry: 1798675200 },
  { id: 9, name: 'GTA 6 $100+', price: 0.0095, expiry: 1772280000 },
  { id: 10, name: 'Timberwolves NBA', price: 0.0363, expiry: 1782864000 },
];

const PRICE_ENGINE_ABI = [
  {
    name: 'deactivateMarket',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'marketId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'configureMarket',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'expiryTimestamp', type: 'uint256' },
      { name: 'maxSpread', type: 'uint256' },
      { name: 'maxTickMovement', type: 'uint256' },
      { name: 'minLiquidityDepth', type: 'uint256' },
      { name: 'alpha', type: 'uint256' },
      { name: 'volatilityWindow', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    name: 'forceSetPrice',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'price', type: 'uint256' },
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
] as const;

async function main() {
  let privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    console.error('❌ PRIVATE_KEY not set');
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
  console.log('║     🚀 LEVER Market Reset - Top 10 LIVE Markets            ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log(`  🔑 Deployer:    ${account.address}`);
  console.log(`  📍 PriceEngine: ${PRICE_ENGINE_V2}`);
  console.log('');

  // Check balance
  const balance = await publicClient.getBalance({ address: account.address });
  console.log(`  💰 Balance: ${Number(balance) / 1e18} BNB`);
  console.log('');

  // Step 1: Deactivate old markets 1-12
  console.log('=== Step 1: Deactivating old markets 1-12 ===');
  for (let i = 1; i <= 12; i++) {
    try {
      const hash = await walletClient.writeContract({
        address: PRICE_ENGINE_V2 as `0x${string}`,
        abi: PRICE_ENGINE_ABI,
        functionName: 'deactivateMarket',
        args: [BigInt(i)],
        gas: BigInt(100000),
      });
      console.log(`  ✅ Deactivated market ${i}: ${hash.slice(0, 20)}...`);
      await publicClient.waitForTransactionReceipt({ hash });
    } catch (e: any) {
      console.log(`  ⚠️  Market ${i}: ${e.message?.slice(0, 50) || 'failed'}`);
    }
    // Small delay
    await new Promise(r => setTimeout(r, 500));
  }

  // Step 2: Configure and set prices for new markets
  console.log('');
  console.log('=== Step 2: Configuring 10 new LIVE markets ===');
  
  for (const market of MARKETS) {
    console.log(`\n  📊 Market ${market.id}: ${market.name}`);
    
    // Configure market
    try {
      const configHash = await walletClient.writeContract({
        address: PRICE_ENGINE_V2 as `0x${string}`,
        abi: PRICE_ENGINE_ABI,
        functionName: 'configureMarket',
        args: [
          BigInt(market.id),
          BigInt(market.expiry),
          BigInt(500),          // 5% max spread
          BigInt(10000),        // 100% max tick
          BigInt(0),            // no min liquidity
          parseUnits('0.1', 18), // 0.1 alpha
          BigInt(3600),         // 1 hour volatility window
        ],
        gas: BigInt(200000),
      });
      console.log(`     Configured: ${configHash.slice(0, 20)}...`);
      await publicClient.waitForTransactionReceipt({ hash: configHash });
    } catch (e: any) {
      console.log(`     Config failed: ${e.message?.slice(0, 50)}`);
    }
    
    await new Promise(r => setTimeout(r, 500));
    
    // Force set price
    try {
      const priceWei = parseUnits(market.price.toString(), 18);
      const priceHash = await walletClient.writeContract({
        address: PRICE_ENGINE_V2 as `0x${string}`,
        abi: PRICE_ENGINE_ABI,
        functionName: 'forceSetPrice',
        args: [BigInt(market.id), priceWei],
        gas: BigInt(200000),
      });
      console.log(`     Price set to ${(market.price * 100).toFixed(2)}%: ${priceHash.slice(0, 20)}...`);
      await publicClient.waitForTransactionReceipt({ hash: priceHash });
    } catch (e: any) {
      console.log(`     Price failed: ${e.message?.slice(0, 50)}`);
    }
    
    await new Promise(r => setTimeout(r, 500));
  }

  // Step 3: Verify
  console.log('');
  console.log('=== Step 3: Verifying deployed prices ===');
  
  for (const market of MARKETS) {
    try {
      const [rawPrice, smoothedPrice] = await publicClient.readContract({
        address: PRICE_ENGINE_V2 as `0x${string}`,
        abi: PRICE_ENGINE_ABI,
        functionName: 'getPriceState',
        args: [BigInt(market.id)],
      }) as [bigint, bigint, bigint, bigint];
      
      const price = Number(smoothedPrice) / 1e18 * 100;
      console.log(`  Market ${market.id} (${market.name}): ${price.toFixed(2)}%`);
    } catch (e) {
      console.log(`  Market ${market.id}: Failed to read`);
    }
  }

  console.log('');
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║     ✅ MARKET RESET COMPLETE                               ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log('');
}

main().catch(console.error);
