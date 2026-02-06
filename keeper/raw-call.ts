import { createPublicClient, http, encodeFunctionData, decodeFunctionResult, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const PRICE_ENGINE_V2 = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';

async function main() {
  // Raw call exactly like Router does
  const calldata = encodeFunctionData({
    abi: [{ name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] }],
    functionName: 'getMarkPrice',
    args: [2n],
  });
  
  console.log('Calldata:', calldata);
  
  const result = await publicClient.call({
    to: PRICE_ENGINE_V2,
    data: calldata,
  });
  
  console.log('Raw result:', result.data);
  console.log('Result length:', result.data?.length);
  
  if (result.data) {
    const decoded = decodeFunctionResult({
      abi: [{ name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] }],
      functionName: 'getMarkPrice',
      data: result.data,
    });
    console.log('Decoded price:', formatUnits(decoded as bigint, 18));
  }
  
  // Also check if Router call works
  const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';
  
  const routerResult = await publicClient.call({
    to: ROUTER,
    data: calldata,
  });
  
  console.log('\nRouter result:', routerResult.data);
}

main().catch(console.error);
