/**
 * Check positions on OLD LedgerV2 (RouterV4 deployment)
 */

import { createPublicClient, http, formatEther } from 'viem';
import { bscTestnet } from 'viem/chains';

// OLD contract addresses (RouterV4 era)
const OLD_LEDGER = '0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3'; // PositionLedgerV2
const OLD_ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23'; // RouterV4

const WALLET = '0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc';

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
  console.log('\n=== Checking OLD LedgerV2 Positions ===');
  console.log(`Old Ledger: ${OLD_LEDGER}`);
  console.log(`Wallet: ${WALLET}\n`);

  const publicClient = createPublicClient({
    chain: bscTestnet,
    transport: http('https://data-seed-prebsc-1-s1.binance.org:8545/'),
  });

  // Old market IDs were 1-10 (not 0-9)
  console.log('Scanning markets 1-10 (old numbering)...\n');

  for (let marketId = 1; marketId <= 10; marketId++) {
    try {
      const position = await publicClient.readContract({
        address: OLD_LEDGER as `0x${string}`,
        abi: LEDGER_ABI,
        functionName: 'getPosition',
        args: [WALLET as `0x${string}`, BigInt(marketId)],
      });

      if (position.size !== 0n) {
        console.log(`Market ${marketId}: Size=${formatEther(position.size)} Collateral=${formatEther(position.collateral)} Entry=${formatEther(position.entryPrice)}`);
      } else {
        console.log(`Market ${marketId}: No position`);
      }
    } catch (e: any) {
      console.log(`Market ${marketId}: Error - ${e.message?.slice(0, 60)}`);
    }
  }

  console.log('\n=== Done ===\n');
}

main().catch(console.error);
