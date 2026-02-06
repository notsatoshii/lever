import { createPublicClient, createWalletClient, http, parseUnits, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

const PRIVATE_KEY = process.env.KEEPER_PRIVATE_KEY as `0x${string}`;
const account = privateKeyToAccount(PRIVATE_KEY);

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const walletClient = createWalletClient({
  account,
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';
const USDT = '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58';

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

const USDT_ABI = [
  { name: 'approve', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
  { name: 'allowance', type: 'function', stateMutability: 'view', inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ type: 'uint256' }] },
] as const;

async function main() {
  console.log('Attempting to open position via actual transaction...\n');
  
  const collateral = parseUnits('50', 18);
  const leverage = parseUnits('2', 18);
  const maxSlippage = parseUnits('0.5', 18); // 50% slippage to be safe
  
  // Check allowance first
  const allowance = await publicClient.readContract({
    address: USDT,
    abi: USDT_ABI,
    functionName: 'allowance',
    args: [account.address, ROUTER],
  });
  
  if (allowance < collateral) {
    console.log('Approving USDT...');
    const approveHash = await walletClient.writeContract({
      address: USDT,
      abi: USDT_ABI,
      functionName: 'approve',
      args: [ROUTER, parseUnits('10000', 18)],
    });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });
    console.log('Approved:', approveHash);
  }
  
  console.log('Opening position: market 1, LONG, $50 collateral, 2x leverage...');
  
  try {
    const hash = await walletClient.writeContract({
      address: ROUTER,
      abi: ROUTER_ABI,
      functionName: 'openPosition',
      args: [1n, true, collateral, leverage, maxSlippage],
      gas: 2000000n, // High gas limit
    });
    
    console.log('TX submitted:', hash);
    
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    console.log('TX status:', receipt.status);
    console.log('Gas used:', receipt.gasUsed.toString());
    
    if (receipt.status === 'success') {
      console.log('✅ Position opened successfully!');
    } else {
      console.log('❌ Transaction reverted');
    }
  } catch (e: any) {
    console.log('Error:', e.message?.slice(0, 500));
    
    // If it fails, try to get more info from the revert
    if (e.cause?.data) {
      console.log('Error data:', e.cause.data);
    }
  }
}

main().catch(console.error);
