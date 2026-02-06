/**
 * Check ownership and authorization on original ledger
 */

import { createPublicClient, http } from 'viem';
import { bscTestnet } from 'viem/chains';

const OLD_LEDGER = '0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c';
const WALLET = '0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc';
const ROUTER_V3 = '0x346D9eC78F8437c2aa32375584B959ccCDc843E1';
const ROUTER_V2 = '0xd04469ADb9617E3efd830137Fd42FdbB43B6bDfa';

const LEDGER_ABI = [
  { name: 'owner', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] },
  { name: 'authorizedEngines', type: 'function', stateMutability: 'view', inputs: [{ name: 'engine', type: 'address' }], outputs: [{ type: 'bool' }] },
] as const;

async function main() {
  const publicClient = createPublicClient({
    chain: bscTestnet,
    transport: http('https://data-seed-prebsc-1-s1.binance.org:8545/'),
  });

  console.log('\n=== Original Ledger Authorization Check ===\n');
  console.log(`Ledger: ${OLD_LEDGER}`);
  console.log(`Our Wallet: ${WALLET}\n`);

  try {
    const owner = await publicClient.readContract({
      address: OLD_LEDGER as `0x${string}`,
      abi: LEDGER_ABI,
      functionName: 'owner',
    });
    console.log(`Owner: ${owner}`);
    console.log(`We are owner: ${owner.toLowerCase() === WALLET.toLowerCase() ? '✅ YES' : '❌ NO'}`);
  } catch (e: any) {
    console.log(`Owner check failed: ${e.message?.slice(0, 50)}`);
  }

  console.log('\nRouter authorizations:');
  for (const router of [{ name: 'RouterV3', address: ROUTER_V3 }, { name: 'RouterV2', address: ROUTER_V2 }, { name: 'Our Wallet', address: WALLET }]) {
    try {
      const authorized = await publicClient.readContract({
        address: OLD_LEDGER as `0x${string}`,
        abi: LEDGER_ABI,
        functionName: 'authorizedEngines',
        args: [router.address as `0x${string}`],
      });
      console.log(`  ${router.name}: ${authorized ? '✅ Authorized' : '❌ Not authorized'}`);
    } catch (e: any) {
      console.log(`  ${router.name}: Error - ${e.message?.slice(0, 40)}`);
    }
  }

  console.log('\n');
}

main().catch(console.error);
