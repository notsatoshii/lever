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

const LEDGER = '0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3';
const LP_POOL = '0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1';
const USDT = '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58';
const PRICE_ENGINE_V2 = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';

const LEDGER_ABI = [
  { name: 'setEngineAuthorization', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'engine', type: 'address' }, { name: 'authorized', type: 'bool' }], outputs: [] },
  { name: 'owner', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] },
  { name: 'authorizedEngines', type: 'function', stateMutability: 'view', inputs: [{ name: '', type: 'address' }], outputs: [{ type: 'bool' }] },
  { name: 'openPosition', type: 'function', stateMutability: 'nonpayable', 
    inputs: [
      { name: 'trader', type: 'address' },
      { name: 'marketId', type: 'uint256' },
      { name: 'sizeDelta', type: 'int256' },
      { name: 'price', type: 'uint256' },
      { name: 'collateralDelta', type: 'uint256' },
    ], 
    outputs: [] 
  },
] as const;

const LP_ABI = [
  { name: 'setAllocatorAuthorization', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'allocator', type: 'address' }, { name: 'authorized', type: 'bool' }], outputs: [] },
  { name: 'allocate', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'amount', type: 'uint256' }], outputs: [] },
] as const;

const USDT_ABI = [
  { name: 'transfer', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
] as const;

const PRICE_ABI = [
  { name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
] as const;

async function main() {
  console.log('Setting up direct position creation...\n');
  
  // Check if we're the Ledger owner
  const owner = await publicClient.readContract({
    address: LEDGER,
    abi: LEDGER_ABI,
    functionName: 'owner',
  });
  console.log('Ledger owner:', owner);
  
  // Check if our wallet is authorized as engine
  let isAuthorized = await publicClient.readContract({
    address: LEDGER,
    abi: LEDGER_ABI,
    functionName: 'authorizedEngines',
    args: [account.address],
  });
  console.log('Our wallet authorized as engine:', isAuthorized);
  
  if (!isAuthorized) {
    console.log('Authorizing our wallet as engine...');
    const hash = await walletClient.writeContract({
      address: LEDGER,
      abi: LEDGER_ABI,
      functionName: 'setEngineAuthorization',
      args: [account.address, true],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    console.log('Authorized!');
  }
  
  // Also authorize as LP allocator
  console.log('\nAuthorizing as LP allocator...');
  try {
    const hash = await walletClient.writeContract({
      address: LP_POOL,
      abi: LP_ABI,
      functionName: 'setAllocatorAuthorization',
      args: [account.address, true],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    console.log('LP authorization done!');
  } catch (e: any) {
    console.log('Already authorized or error:', e.message?.slice(0, 50));
  }
  
  // Get current price for market 1
  const price = await publicClient.readContract({
    address: PRICE_ENGINE_V2,
    abi: PRICE_ABI,
    functionName: 'getMarkPrice',
    args: [1n],
  });
  console.log('\nMarket 1 price:', formatUnits(price, 18));
  
  // Now try to open a position directly
  console.log('\nOpening position on market 1...');
  
  const collateral = parseUnits('100', 18);
  const leverage = 3n;
  const positionSize = collateral * leverage / parseUnits('1', 18);
  
  try {
    // First transfer collateral to Ledger
    console.log('Transferring collateral to Ledger...');
    const transferHash = await walletClient.writeContract({
      address: USDT,
      abi: USDT_ABI,
      functionName: 'transfer',
      args: [LEDGER, collateral],
    });
    await publicClient.waitForTransactionReceipt({ hash: transferHash });
    console.log('Transfer done!');
    
    // Allocate LP
    console.log('Allocating from LP Pool...');
    const allocateHash = await walletClient.writeContract({
      address: LP_POOL,
      abi: LP_ABI,
      functionName: 'allocate',
      args: [positionSize * price / parseUnits('1', 18)],
    });
    await publicClient.waitForTransactionReceipt({ hash: allocateHash });
    console.log('LP allocated!');
    
    // Open position
    console.log('Opening position in Ledger...');
    const openHash = await walletClient.writeContract({
      address: LEDGER,
      abi: LEDGER_ABI,
      functionName: 'openPosition',
      args: [account.address, 1n, positionSize, price, collateral],
    });
    await publicClient.waitForTransactionReceipt({ hash: openHash });
    console.log('✅ Position opened!');
    
  } catch (e: any) {
    console.log('Error:', e.message?.slice(0, 200));
  }
}

main().catch(console.error);
