/**
 * Check positions on ALL historical ledgers
 */

import { createPublicClient, http, formatEther } from 'viem';
import { bscTestnet } from 'viem/chains';

const WALLET = '0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc';

const LEDGERS = [
  { name: 'Original Ledger (RouterV2/V3)', address: '0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c' },
  { name: 'LedgerV2 (RouterV4)', address: '0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3' },
  { name: 'LedgerV3 (RouterV5)', address: '0x74b24940c76c53cb0e9f0194cc79f6c08cf79f73' },
];

const LEDGER_ABI = [
  {
    name: 'getPosition',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'trader', type: 'address' }, { name: 'marketId', type: 'uint256' }],
    outputs: [{
      type: 'tuple',
      components: [
        { name: 'marketId', type: 'uint256' },
        { name: 'size', type: 'int256' },
        { name: 'entryPrice', type: 'uint256' },
        { name: 'collateral', type: 'uint256' },
        { name: 'openTimestamp', type: 'uint256' },
        { name: 'lastFundingIndex', type: 'uint256' },
        { name: 'lastBorrowIndex', type: 'uint256' },
      ]
    }]
  },
] as const;

async function main() {
  console.log('\n=== Checking ALL Ledgers for Positions ===\n');

  const publicClient = createPublicClient({
    chain: bscTestnet,
    transport: http('https://data-seed-prebsc-1-s1.binance.org:8545/'),
  });

  for (const ledger of LEDGERS) {
    console.log(`\n--- ${ledger.name} ---`);
    console.log(`Address: ${ledger.address}\n`);

    let foundPositions = false;

    // Check markets 0-10 (covers both old and new numbering)
    for (let marketId = 0; marketId <= 10; marketId++) {
      try {
        const position = await publicClient.readContract({
          address: ledger.address as `0x${string}`,
          abi: LEDGER_ABI,
          functionName: 'getPosition',
          args: [WALLET as `0x${string}`, BigInt(marketId)],
        });

        if (position.size !== 0n) {
          console.log(`  Market ${marketId}: Size=${formatEther(position.size)} Collateral=${formatEther(position.collateral)}`);
          foundPositions = true;
        }
      } catch (e: any) {
        // Silently skip errors (market doesn't exist)
      }
    }

    if (!foundPositions) {
      console.log('  No positions found');
    }
  }

  console.log('\n=== Done ===\n');
}

main().catch(console.error);
