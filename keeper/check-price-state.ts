import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const PRICE_ENGINE_V2 = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';

const ABI = [
  { name: 'getPriceState', type: 'function', stateMutability: 'view', 
    inputs: [{ name: 'marketId', type: 'uint256' }], 
    outputs: [
      { name: 'rawPrice', type: 'uint256' },
      { name: 'smoothedPrice', type: 'uint256' },
      { name: 'lastUpdate', type: 'uint256' },
      { name: 'volatility', type: 'uint256' },
    ] 
  },
] as const;

async function main() {
  console.log('Price states for markets 1-10:\n');
  
  for (let i = 1; i <= 10; i++) {
    try {
      const state = await publicClient.readContract({
        address: PRICE_ENGINE_V2,
        abi: ABI,
        functionName: 'getPriceState',
        args: [BigInt(i)],
      });
      console.log(`Market ${i}:`);
      console.log(`  rawPrice: ${formatUnits(state[0], 18)} (${Number(formatUnits(state[0], 18)) * 100}%)`);
      console.log(`  smoothedPrice: ${formatUnits(state[1], 18)} (${Number(formatUnits(state[1], 18)) * 100}%)`);
      console.log(`  lastUpdate: ${state[2]} (${new Date(Number(state[2]) * 1000).toISOString()})`);
      console.log(`  volatility: ${state[3]}`);
    } catch (e: any) {
      console.log(`Market ${i}: ERROR - ${e.message?.slice(0, 50)}`);
    }
  }
}

main().catch(console.error);
