import { createPublicClient, createWalletClient, http } from 'viem';
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

const LP_POOL = '0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1';
const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';

const LP_ABI = [
  { name: 'owner', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] },
  { name: 'setAllocatorAuthorization', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'allocator', type: 'address' }, { name: 'authorized', type: 'bool' }], outputs: [] },
] as const;

async function main() {
  // Check owner
  const owner = await publicClient.readContract({
    address: LP_POOL,
    abi: LP_ABI,
    functionName: 'owner',
  });
  console.log(`LP Pool owner: ${owner}`);
  console.log(`Our address: ${account.address}`);
  
  if (owner.toLowerCase() !== account.address.toLowerCase()) {
    console.log('We are not the owner - need deployer key');
    return;
  }
  
  // Authorize Router
  console.log('Authorizing Router on LP Pool...');
  const hash = await walletClient.writeContract({
    address: LP_POOL,
    abi: LP_ABI,
    functionName: 'setAllocatorAuthorization',
    args: [ROUTER, true],
  });
  console.log(`TX: ${hash}`);
  await publicClient.waitForTransactionReceipt({ hash });
  console.log('✅ Router authorized on LP Pool');
}

main().catch(console.error);
