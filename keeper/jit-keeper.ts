/**
 * JIT Keeper - Recenters vAMM pools to oracle prices
 * 
 * Runs continuously and recenters all active pools every N seconds
 * to keep vAMM prices aligned with PriceEngine oracle prices.
 */

import { createPublicClient, createWalletClient, http, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';
import { readFileSync } from 'fs';

// Load .env manually
const envContent = readFileSync('.env', 'utf8');
const envVars = Object.fromEntries(
  envContent.split('\n')
    .filter(line => line && !line.startsWith('#'))
    .map(line => line.split('=').map(s => s.trim()))
);
process.env.KEEPER_PRIVATE_KEY = envVars.KEEPER_PRIVATE_KEY;

// Config
const RECENTER_INTERVAL_MS = 30_000; // Recenter every 30 seconds
const MARKETS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

// Contract addresses
const VAMM = '0xccf023064bed8aae7c858ed7b2a884f172a74f81';
const PRICE_ENGINE = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';

// ABIs
const VAMM_ABI = [
  { name: 'recenter', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [] },
  { name: 'getSpotPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { name: 'getPool', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'tuple', components: [{ name: 'vQ', type: 'uint256' }, { name: 'vB', type: 'uint256' }, { name: 'k', type: 'uint256' }, { name: 'lastPI', type: 'uint256' }, { name: 'lastUpdate', type: 'uint256' }, { name: 'initialized', type: 'bool' }] }] },
] as const;

const PRICE_ENGINE_ABI = [
  { name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
] as const;

// Setup clients
const account = privateKeyToAccount(process.env.KEEPER_PRIVATE_KEY as `0x${string}`);
const client = createPublicClient({ chain: bscTestnet, transport: http('https://data-seed-prebsc-1-s1.binance.org:8545') });
const wallet = createWalletClient({ account, chain: bscTestnet, transport: http('https://data-seed-prebsc-1-s1.binance.org:8545') });

interface RecenterResult {
  marketId: number;
  success: boolean;
  oraclePrice?: string;
  vammPrice?: string;
  deviation?: string;
  error?: string;
}

async function recenterMarket(marketId: number): Promise<RecenterResult> {
  try {
    // Get oracle price
    const oraclePrice = await client.readContract({
      address: PRICE_ENGINE,
      abi: PRICE_ENGINE_ABI,
      functionName: 'getMarkPrice',
      args: [BigInt(marketId)],
    });

    // Get vAMM price
    const vammPrice = await client.readContract({
      address: VAMM,
      abi: VAMM_ABI,
      functionName: 'getSpotPrice',
      args: [BigInt(marketId)],
    });

    // Calculate deviation
    const oraclePriceNum = Number(formatUnits(oraclePrice, 18));
    const vammPriceNum = Number(formatUnits(vammPrice, 18));
    const deviation = Math.abs(oraclePriceNum - vammPriceNum) / oraclePriceNum * 100;

    // Only recenter if deviation > 0.1%
    if (deviation < 0.1) {
      return {
        marketId,
        success: true,
        oraclePrice: oraclePriceNum.toFixed(4),
        vammPrice: vammPriceNum.toFixed(4),
        deviation: deviation.toFixed(2) + '%',
      };
    }

    // Recenter
    const hash = await wallet.writeContract({
      address: VAMM,
      abi: VAMM_ABI,
      functionName: 'recenter',
      args: [BigInt(marketId)],
    });
    await client.waitForTransactionReceipt({ hash });

    // Get new vAMM price
    const newVammPrice = await client.readContract({
      address: VAMM,
      abi: VAMM_ABI,
      functionName: 'getSpotPrice',
      args: [BigInt(marketId)],
    });

    return {
      marketId,
      success: true,
      oraclePrice: oraclePriceNum.toFixed(4),
      vammPrice: Number(formatUnits(newVammPrice, 18)).toFixed(4),
      deviation: '0.00% (recentered)',
    };
  } catch (error) {
    return {
      marketId,
      success: false,
      error: (error as Error).message?.slice(0, 100),
    };
  }
}

async function recenterAllMarkets() {
  console.log(`\n[${new Date().toISOString()}] Recentering markets...`);
  
  const results: RecenterResult[] = [];
  
  for (const marketId of MARKETS) {
    const result = await recenterMarket(marketId);
    results.push(result);
  }
  
  // Print summary
  const successful = results.filter(r => r.success).length;
  const recentered = results.filter(r => r.deviation?.includes('recentered')).length;
  
  console.log(`  Checked: ${results.length} | Recentered: ${recentered} | OK: ${successful - recentered}`);
  
  // Print any with significant deviation or errors
  for (const r of results) {
    if (!r.success) {
      console.log(`  ❌ Market ${r.marketId}: ${r.error}`);
    } else if (r.deviation?.includes('recentered')) {
      console.log(`  🔄 Market ${r.marketId}: ${r.oraclePrice} (was off, recentered)`);
    }
  }
}

async function main() {
  console.log('=== JIT Keeper Started ===');
  console.log('vAMM:', VAMM);
  console.log('PriceEngine:', PRICE_ENGINE);
  console.log('Keeper:', account.address);
  console.log(`Interval: ${RECENTER_INTERVAL_MS / 1000}s`);
  console.log('Markets:', MARKETS.join(', '));
  
  // Initial recenter
  await recenterAllMarkets();
  
  // Schedule recurring recenters
  setInterval(recenterAllMarkets, RECENTER_INTERVAL_MS);
}

main().catch(console.error);
