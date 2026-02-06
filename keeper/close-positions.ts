/**
 * Close all existing positions
 * Run: npx tsx close-positions.ts
 */

import { createPublicClient, createWalletClient, http, formatEther, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

// Contract addresses from frontend/src/config/contracts.ts
const CONTRACTS = {
  USDT: '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58',
  ROUTER: '0xee92ef898a0eabca96cad863cb0303b6d13cc023',       // RouterV5
  LEDGER: '0x74b24940c76c53cb0e9f0194cc79f6c08cf79f73',       // PositionLedgerV3
  PRICE_ENGINE: '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC',
};

// ABIs
const LEDGER_ABI = [
  {
    name: 'getPosition',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'trader', type: 'address' }, { name: 'marketId', type: 'uint256' }],
    outputs: [{
      type: 'tuple',
      components: [
        { name: 'marketId', type: 'uint256' },
        { name: 'size', type: 'int256' },
        { name: 'entryPrice', type: 'uint256' },
        { name: 'collateral', type: 'uint256' },
        { name: 'openTimestamp', type: 'uint256' },
        { name: 'lastFundingIndex', type: 'uint256' },
        { name: 'lastBorrowIndex', type: 'uint256' },
      ]
    }]
  },
] as const;

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

const PRICE_ENGINE_ABI = [
  { name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
] as const;

async function main() {
  console.log('\n=== Closing All Old Positions ===\n');

  const privateKey = process.env.KEEPER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    console.error('❌ Missing KEEPER_PRIVATE_KEY or PRIVATE_KEY in .env');
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

  // Check positions on markets 0-9
  console.log('\nScanning markets 0-9 for positions...\n');
  const positionsToClose: { marketId: number; size: bigint; collateral: bigint }[] = [];

  for (let marketId = 0; marketId < 10; marketId++) {
    try {
      const position = await publicClient.readContract({
        address: CONTRACTS.LEDGER as `0x${string}`,
        abi: LEDGER_ABI,
        functionName: 'getPosition',
        args: [account.address, BigInt(marketId)],
      });

      if (position.size !== 0n) {
        console.log(`Market ${marketId}: Size=${formatEther(position.size)} Collateral=${formatEther(position.collateral)}`);
        positionsToClose.push({
          marketId,
          size: position.size,
          collateral: position.collateral,
        });
      } else {
        console.log(`Market ${marketId}: No position`);
      }
    } catch (e: any) {
      console.log(`Market ${marketId}: Error reading - ${e.message?.slice(0, 50)}`);
    }
  }

  if (positionsToClose.length === 0) {
    console.log('\n✅ No positions to close!');
    return;
  }

  console.log(`\nFound ${positionsToClose.length} positions to close.\n`);

  // Close each position
  for (const pos of positionsToClose) {
    console.log(`Closing market ${pos.marketId}...`);
    try {
      const hash = await walletClient.writeContract({
        address: CONTRACTS.ROUTER as `0x${string}`,
        abi: ROUTER_ABI,
        functionName: 'closePosition',
        args: [BigInt(pos.marketId), parseEther('1'), 0n], // 100% close, no min output
      });
      console.log(`  ✅ Tx: ${hash}`);

      // Wait for confirmation
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      console.log(`  ✅ Confirmed in block ${receipt.blockNumber}`);
    } catch (e: any) {
      console.log(`  ❌ Failed: ${e.message?.slice(0, 100)}`);
    }
  }

  console.log('\n=== Done ===\n');
}

main().catch(console.error);
