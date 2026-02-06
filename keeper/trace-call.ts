import { createPublicClient, http, encodeFunctionData, parseUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';

async function main() {
  // Encode openPosition call
  const calldata = encodeFunctionData({
    abi: [{ 
      name: 'openPosition', 
      type: 'function', 
      stateMutability: 'nonpayable',
      inputs: [
        { name: 'marketId', type: 'uint256' }, 
        { name: 'isLong', type: 'bool' }, 
        { name: 'collateralAmount', type: 'uint256' }, 
        { name: 'leverage', type: 'uint256' }, 
        { name: 'maxSlippage', type: 'uint256' }
      ], 
      outputs: [{ type: 'uint256' }, { type: 'uint256' }] 
    }],
    functionName: 'openPosition',
    args: [2n, true, parseUnits('100', 18), parseUnits('3', 18), parseUnits('0.1', 18)],
  });
  
  console.log('Calldata:', calldata);
  
  // Try debug_traceCall
  try {
    const response = await fetch('https://data-seed-prebsc-1-s1.binance.org:8545', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'debug_traceCall',
        params: [
          {
            from: '0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc',
            to: ROUTER,
            data: calldata,
            gas: '0x1000000',
          },
          'latest',
          { tracer: 'callTracer' }
        ],
        id: 1,
      }),
    });
    const result = await response.json();
    console.log('Trace result:', JSON.stringify(result, null, 2).slice(0, 2000));
  } catch (e: any) {
    console.log('Trace failed:', e.message);
  }
}

main().catch(console.error);
