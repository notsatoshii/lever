// Quick deploy of PositionLedgerV3 with setTotalTVL fix
// Uses pre-compiled bytecode

import { createPublicClient, createWalletClient, http, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

const PRIVATE_KEY = process.env.KEEPER_PRIVATE_KEY as `0x${string}`;
const account = privateKeyToAccount(PRIVATE_KEY);

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const walletClient = createWalletClient({
  account,
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

// Current deployed addresses
const OLD_LEDGER = '0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3';
const PRICE_ENGINE_V2 = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';
const LP_POOL = '0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1';
const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';

// Instead of redeploying, let's just set TVL on existing ledger directly
// by using the storage slot

async function main() {
  console.log('Checking existing Ledger state...');
  
  // totalTVL is at slot 69 (0-indexed public variable)
  // Actually let's compute it properly
  // Need to check contract storage layout
  
  // For now, let's just output what needs to be done:
  console.log('\n⚠️  ISSUE: PositionLedgerV2 has totalTVL = 0');
  console.log('This blocks ALL positions (global cap = 0)');
  console.log('\nFIX OPTIONS:');
  console.log('1. Redeploy PositionLedgerV2 with setTotalTVL function');
  console.log('2. Deploy new Ledger, re-add all markets, update Router');
  console.log('\nCURRENT STATE:');
  
  // Check LP Pool TVL
  const lpTVL = await publicClient.readContract({
    address: LP_POOL,
    abi: [{ name: 'totalAssets', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] }],
    functionName: 'totalAssets',
  });
  console.log(`LP Pool TVL: $${Number(lpTVL) / 1e18}`);
  console.log(`Ledger totalTVL: $0 (bug)`);
  console.log(`\nNeed to set Ledger.totalTVL = ${lpTVL}`);
}

main().catch(console.error);
