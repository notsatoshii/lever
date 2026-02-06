import { createPublicClient, http } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';

// Try various common state getters
const checks = [
  'paused',
  'isPaused',
  'owner',
  'priceEngine',
  'positionLedger',
  'lpPool',
  'usdt',
  'collateralToken',
];

async function main() {
  console.log('Checking Router state...\n');
  
  for (const fn of checks) {
    try {
      const result = await publicClient.readContract({
        address: ROUTER,
        abi: [{ name: fn, type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] }],
        functionName: fn,
      });
      console.log(`${fn}: ${result}`);
    } catch (e) {
      try {
        const result = await publicClient.readContract({
          address: ROUTER,
          abi: [{ name: fn, type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'bool' }] }],
          functionName: fn,
        });
        console.log(`${fn}: ${result}`);
      } catch (e2) {
        // Skip
      }
    }
  }
  
  // Also try to call getMarkPrice on the Router directly to see what happens
  try {
    const result = await publicClient.readContract({
      address: ROUTER,
      abi: [{ name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] }],
      functionName: 'getMarkPrice',
      args: [2n],
    });
    console.log(`\nRouter.getMarkPrice(2): ${result}`);
  } catch (e: any) {
    console.log(`\nRouter.getMarkPrice(2): ${e.message?.slice(0, 100)}`);
  }
}

main().catch(console.error);
