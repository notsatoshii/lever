import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const LEDGER = '0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3';
const TRADER = '0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc';

const LEDGER_ABI = [
  { name: 'getPosition', type: 'function', stateMutability: 'view', 
    inputs: [{ name: 'trader', type: 'address' }, { name: 'marketId', type: 'uint256' }], 
    outputs: [{ type: 'tuple', components: [
      { name: 'marketId', type: 'uint256' },
      { name: 'size', type: 'int256' },
      { name: 'entryPrice', type: 'uint256' },
      { name: 'collateral', type: 'uint256' },
      { name: 'openTimestamp', type: 'uint256' },
      { name: 'lastFundingIndex', type: 'uint256' },
      { name: 'lastBorrowIndex', type: 'uint256' },
    ]}] 
  },
] as const;

async function main() {
  console.log('Checking existing positions for', TRADER, '\n');
  
  for (let i = 1; i <= 10; i++) {
    try {
      const position = await publicClient.readContract({
        address: LEDGER,
        abi: LEDGER_ABI,
        functionName: 'getPosition',
        args: [TRADER, BigInt(i)],
      });
      
      const hasPosition = position.size !== 0n;
      if (hasPosition) {
        console.log(`Market ${i}: SIZE=${formatUnits(position.size, 18)}, collateral=${formatUnits(position.collateral, 18)}`);
      } else {
        console.log(`Market ${i}: No position`);
      }
    } catch (e: any) {
      console.log(`Market ${i}: ERROR`);
    }
  }
}

main().catch(console.error);
