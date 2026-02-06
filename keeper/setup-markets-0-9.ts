/**
 * Configure markets 0-9 in PriceEngineV2
 * Run once to initialize markets to match LedgerV3 IDs
 */
import dotenv from 'dotenv';
dotenv.config();

import { createWalletClient, createPublicClient, http, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

const PRICE_ENGINE = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';

const PRICE_ENGINE_ABI = [
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
] as const;

// Market configurations (same as keeper-v3)
const MARKETS = [
  { id: 0, name: 'Indiana Pacers NBA Finals', expiry: 1782864000 },  // 2026-07-01
  { id: 1, name: 'Patriots Super Bowl', expiry: 1770552000 },        // 2026-02-08
  { id: 2, name: 'Seahawks Super Bowl', expiry: 1770552000 },        // 2026-02-08
  { id: 3, name: 'Jesus before GTA VI', expiry: 1785499200 },        // 2026-07-31
  { id: 4, name: 'Celtics NBA Finals', expiry: 1782864000 },         // 2026-07-01
  { id: 5, name: 'Thunder NBA Finals', expiry: 1782864000 },         // 2026-07-01
  { id: 6, name: 'BTC $1M before GTA VI', expiry: 1785499200 },      // 2026-07-31
  { id: 7, name: 'van der Plas PM', expiry: 1798675200 },            // 2026-12-31
  { id: 8, name: 'GTA 6 $100+', expiry: 1772280000 },                // 2026-02-28
  { id: 9, name: 'Timberwolves NBA Finals', expiry: 1782864000 },    // 2026-07-01
];

// Default config params
const DEFAULT_CONFIG = {
  maxSpread: parseUnits('0.02', 18),        // 2% max spread
  maxTickMovement: parseUnits('0.1', 18),   // 10% max tick movement
  minLiquidityDepth: parseUnits('10000', 18), // $10k min liquidity
  alpha: parseUnits('0.1', 18),             // 10% EMA weight
  volatilityWindow: 3600n,                  // 1 hour
};

async function main() {
  const privateKey = process.env.KEEPER_PRIVATE_KEY;
  if (!privateKey) {
    console.error('❌ KEEPER_PRIVATE_KEY not set');
    process.exit(1);
  }

  const account = privateKeyToAccount(privateKey as `0x${string}`);
  
  const client = createPublicClient({
    chain: bscTestnet,
    transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
  });
  
  const walletClient = createWalletClient({
    account,
    chain: bscTestnet,
    transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
  });

  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║     🔧 PriceEngineV2 Market Setup (0-9)                    ║');
  console.log('╚════════════════════════════════════════════════════════════╝');
  console.log(`\n  Wallet: ${account.address}`);
  console.log(`  PriceEngine: ${PRICE_ENGINE}\n`);

  for (const market of MARKETS) {
    console.log(`\n[Market ${market.id}] ${market.name}`);
    
    // Check if already configured
    try {
      const config = await client.readContract({
        address: PRICE_ENGINE,
        abi: PRICE_ENGINE_ABI,
        functionName: 'getMarketConfig',
        args: [BigInt(market.id)],
      });
      
      if (config.active) {
        console.log(`  ✓ Already active, expiry=${config.expiryTimestamp}`);
        continue;
      }
    } catch (e) {
      // Not configured
    }
    
    console.log(`  → Configuring with expiry=${market.expiry}...`);
    
    const hash = await walletClient.writeContract({
      address: PRICE_ENGINE,
      abi: PRICE_ENGINE_ABI,
      functionName: 'configureMarket',
      args: [
        BigInt(market.id),
        BigInt(market.expiry),
        DEFAULT_CONFIG.maxSpread,
        DEFAULT_CONFIG.maxTickMovement,
        DEFAULT_CONFIG.minLiquidityDepth,
        DEFAULT_CONFIG.alpha,
        DEFAULT_CONFIG.volatilityWindow,
      ],
    });
    
    console.log(`  ✓ TX: ${hash.slice(0, 18)}...`);
    
    // Wait for confirmation
    const receipt = await client.waitForTransactionReceipt({ hash });
    console.log(`  ✓ Confirmed in block ${receipt.blockNumber}`);
  }

  console.log('\n✅ All markets configured! Keeper can now update prices.');
}

main().catch(console.error);
