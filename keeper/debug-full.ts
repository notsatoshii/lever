import { createPublicClient, http, parseUnits, formatUnits, decodeErrorResult } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';

const ROUTER_ABI = [
  { name: 'openPosition', type: 'function', stateMutability: 'nonpayable', 
    inputs: [
      { name: 'marketId', type: 'uint256' }, 
      { name: 'isLong', type: 'bool' }, 
      { name: 'collateralAmount', type: 'uint256' }, 
      { name: 'leverage', type: 'uint256' }, 
      { name: 'maxSlippage', type: 'uint256' }
    ], 
    outputs: [{ name: 'positionSize', type: 'uint256' }, { name: 'entryPrice', type: 'uint256' }] 
  },
] as const;

async function main() {
  console.log('Simulating openPosition...');
  
  try {
    const result = await publicClient.simulateContract({
      address: ROUTER,
      abi: ROUTER_ABI,
      functionName: 'openPosition',
      args: [2n, true, parseUnits('100', 18), parseUnits('3', 18), parseUnits('0.1', 18)],
      account: '0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc',
    });
    console.log('Success:', result);
  } catch (e: any) {
    console.log('Full error:');
    console.log(e.message);
    if (e.cause?.data) {
      console.log('Error data:', e.cause.data);
    }
    if (e.cause?.reason) {
      console.log('Reason:', e.cause.reason);
    }
  }
}

main().catch(console.error);
