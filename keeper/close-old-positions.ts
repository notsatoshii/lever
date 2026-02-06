/**
 * Close positions on Original Ledger via old routers
 */

import { createPublicClient, createWalletClient, http, formatEther, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

// Old contracts
const OLD_LEDGER = '0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c';
const ROUTER_V3 = '0x346D9eC78F8437c2aa32375584B959ccCDc843E1';
const ROUTER_V2 = '0xd04469ADb9617E3efd830137Fd42FdbB43B6bDfa';

const POSITIONS_TO_CLOSE = [
  { marketId: 2, size: 20000n },
  { marketId: 9, size: 20000n },
];

const ROUTER_ABI = [
  {
    name: 'closePosition',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'closePercent', type: 'uint256' },
      { name: 'minAmountOut', type: 'uint256' }
    ],
    outputs: [
      { name: 'pnl', type: 'int256' },
      { name: 'amountOut', type: 'uint256' }
    ]
  },
] as const;

// Alternative ABI if signature differs
const ROUTER_ABI_ALT = [
  {
    name: 'closePosition',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'sizeDelta', type: 'int256' },
      { name: 'minPrice', type: 'uint256' },
      { name: 'maxPrice', type: 'uint256' }
    ],
    outputs: []
  },
] as const;

async function main() {
  console.log('\n=== Closing Old Positions on Original Ledger ===\n');

  const privateKey = process.env.KEEPER_PRIVATE_KEY;
  if (!privateKey) {
    console.error('❌ Missing KEEPER_PRIVATE_KEY');
    process.exit(1);
  }

  const account = privateKeyToAccount(privateKey as `0x${string}`);
  console.log(`Wallet: ${account.address}`);

  const publicClient = createPublicClient({
    chain: bscTestnet,
    transport: http('https://data-seed-prebsc-1-s1.binance.org:8545/'),
  });

  const walletClient = createWalletClient({
    account,
    chain: bscTestnet,
    transport: http('https://data-seed-prebsc-1-s1.binance.org:8545/'),
  });

  // Try RouterV3 first, then RouterV2
  const routers = [
    { name: 'RouterV3', address: ROUTER_V3 },
    { name: 'RouterV2', address: ROUTER_V2 },
  ];

  for (const pos of POSITIONS_TO_CLOSE) {
    console.log(`\nClosing Market ${pos.marketId} (size: ${pos.size})...`);

    let success = false;

    for (const router of routers) {
      if (success) break;

      console.log(`  Trying ${router.name}...`);
      
      // Try standard signature first
      try {
        const hash = await walletClient.writeContract({
          address: router.address as `0x${string}`,
          abi: ROUTER_ABI,
          functionName: 'closePosition',
          args: [BigInt(pos.marketId), parseEther('1'), 0n],
        });
        console.log(`    ✅ Tx sent: ${hash}`);
        
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        if (receipt.status === 'success') {
          console.log(`    ✅ Confirmed in block ${receipt.blockNumber}`);
          success = true;
        } else {
          console.log(`    ❌ Tx reverted`);
        }
      } catch (e: any) {
        const msg = e.message?.slice(0, 100) || 'Unknown error';
        console.log(`    ❌ Standard ABI failed: ${msg}`);
        
        // Try alternative signature
        try {
          const hash = await walletClient.writeContract({
            address: router.address as `0x${string}`,
            abi: ROUTER_ABI_ALT,
            functionName: 'closePosition',
            args: [BigInt(pos.marketId), -BigInt(pos.size) * parseEther('1') / 1n, 0n, parseEther('1')],
          });
          console.log(`    ✅ Alt ABI Tx sent: ${hash}`);
          
          const receipt = await publicClient.waitForTransactionReceipt({ hash });
          if (receipt.status === 'success') {
            console.log(`    ✅ Confirmed in block ${receipt.blockNumber}`);
            success = true;
          }
        } catch (e2: any) {
          console.log(`    ❌ Alt ABI also failed: ${e2.message?.slice(0, 80)}`);
        }
      }
    }

    if (!success) {
      console.log(`  ⚠️  Could not close Market ${pos.marketId} with available routers`);
    }
  }

  console.log('\n=== Done ===\n');
}

main().catch(console.error);
