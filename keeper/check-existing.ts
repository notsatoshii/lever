import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const LEDGER = '0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3';

const LEDGER_ABI = [
  { name: 'getMarket', type: 'function', stateMutability: 'view', 
    inputs: [{ name: 'marketId', type: 'uint256' }], 
    outputs: [{ type: 'tuple', components: [
      { name: 'totalLongOI', type: 'uint256' },
      { name: 'totalShortOI', type: 'uint256' },
      { name: 'fundingIndex', type: 'int256' },
      { name: 'borrowIndex', type: 'uint256' },
      { name: 'active', type: 'bool' },
    ]}] 
  },
] as const;

async function main() {
  console.log('Checking market data in Ledger:\n');
  
  for (let i = 1; i <= 10; i++) {
    try {
      const market = await publicClient.readContract({
        address: LEDGER,
        abi: LEDGER_ABI,
        functionName: 'getMarket',
        args: [BigInt(i)],
      });
      console.log(`Market ${i}: active=${market.active}, longOI=${formatUnits(market.totalLongOI, 18)}, shortOI=${formatUnits(market.totalShortOI, 18)}`);
    } catch (e: any) {
      console.log(`Market ${i}: ERROR - ${e.message?.slice(0, 50)}`);
    }
  }
}

main().catch(console.error);
