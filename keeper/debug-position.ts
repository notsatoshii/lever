import { createPublicClient, http, parseUnits, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';
const LEDGER = '0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3';
const LP_POOL = '0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1';

async function main() {
  // Check if Router is authorized on Ledger
  const LEDGER_ABI = [
    { name: 'authorizedEngines', type: 'function', stateMutability: 'view', inputs: [{ name: '', type: 'address' }], outputs: [{ type: 'bool' }] },
  ] as const;
  
  const LP_ABI = [
    { name: 'authorizedAllocators', type: 'function', stateMutability: 'view', inputs: [{ name: '', type: 'address' }], outputs: [{ type: 'bool' }] },
    { name: 'totalAssets', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
    { name: 'totalAllocated', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  ] as const;

  console.log('Checking Router authorization...');
  
  const isAuthorizedLedger = await publicClient.readContract({
    address: LEDGER,
    abi: LEDGER_ABI,
    functionName: 'authorizedEngines',
    args: [ROUTER],
  });
  console.log(`Router authorized on Ledger: ${isAuthorizedLedger}`);
  
  const isAuthorizedLP = await publicClient.readContract({
    address: LP_POOL,
    abi: LP_ABI,
    functionName: 'authorizedAllocators',
    args: [ROUTER],
  });
  console.log(`Router authorized on LP Pool: ${isAuthorizedLP}`);
  
  const totalAssets = await publicClient.readContract({
    address: LP_POOL,
    abi: LP_ABI,
    functionName: 'totalAssets',
  });
  console.log(`LP Total Assets: ${formatUnits(totalAssets, 18)}`);
  
  const totalAllocated = await publicClient.readContract({
    address: LP_POOL,
    abi: LP_ABI,
    functionName: 'totalAllocated',
  });
  console.log(`LP Total Allocated: ${formatUnits(totalAllocated, 18)}`);
  
  // Try simulate the call to get exact error
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
  
  try {
    const result = await publicClient.simulateContract({
      address: ROUTER,
      abi: ROUTER_ABI,
      functionName: 'openPosition',
      args: [2n, true, parseUnits('100', 18), parseUnits('3', 18), parseUnits('0.1', 18)],
      account: '0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc',
    });
    console.log('Simulation result:', result);
  } catch (e: any) {
    console.log('Simulation error:', e.message);
  }
}

main();
