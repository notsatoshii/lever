import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const PRICE_ENGINE_V2 = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';

const PRICE_ENGINE_V2_ABI = [
  { name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { name: 'getMarketConfig', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'tuple', components: [
    { name: 'expiryTimestamp', type: 'uint256' },
    { name: 'piAdjustmentSpeed', type: 'uint256' },
    { name: 'maxSpread', type: 'uint256' },
    { name: 'minLiquidity', type: 'uint256' },
    { name: 'lastUpdateTime', type: 'uint256' },
    { name: 'isActive', type: 'bool' },
  ]}] },
  { name: 'authorizedUpdaters', type: 'function', stateMutability: 'view', inputs: [{ name: '', type: 'address' }], outputs: [{ type: 'bool' }] },
] as const;

async function main() {
  console.log('Checking PriceEngineV2 for markets 1-10:\n');
  
  for (let i = 1; i <= 10; i++) {
    try {
      const price = await publicClient.readContract({
        address: PRICE_ENGINE_V2,
        abi: PRICE_ENGINE_V2_ABI,
        functionName: 'getMarkPrice',
        args: [BigInt(i)],
      });
      console.log(`Market ${i}: ${(Number(formatUnits(price, 18)) * 100).toFixed(2)}%`);
    } catch (e: any) {
      console.log(`Market ${i}: ERROR - ${e.message?.slice(0, 60)}`);
      
      // Check market config
      try {
        const config = await publicClient.readContract({
          address: PRICE_ENGINE_V2,
          abi: PRICE_ENGINE_V2_ABI,
          functionName: 'getMarketConfig',
          args: [BigInt(i)],
        });
        console.log(`  Config: expiry=${config.expiryTimestamp}, active=${config.isActive}, lastUpdate=${config.lastUpdateTime}`);
      } catch (e2: any) {
        console.log(`  Config: ERROR`);
      }
    }
  }
}

main().catch(console.error);
