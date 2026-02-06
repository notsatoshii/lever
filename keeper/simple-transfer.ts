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
const USDT = '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58';

async function main() {
  // Check balance first
  const balance = await publicClient.readContract({
    address: USDT,
    abi: [{ name: 'balanceOf', type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] }],
    functionName: 'balanceOf',
    args: [account.address],
  });
  console.log('USDT Balance:', formatUnits(balance, 18));
  
  // Try a simple transfer
  console.log('Attempting transfer of 100 USDT to Ledger...');
  
  const amount = parseUnits('100', 18);
  
  try {
    const hash = await walletClient.writeContract({
      address: USDT,
      abi: [{ name: 'transfer', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] }],
      functionName: 'transfer',
      args: [LEDGER, amount],
    });
    console.log('TX:', hash);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    console.log('Status:', receipt.status);
  } catch (e: any) {
    console.log('Error:', e.message?.slice(0, 500));
    console.log('Error cause:', e.cause?.message?.slice(0, 500));
  }
}

main().catch(console.error);
