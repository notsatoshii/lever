/**
 * Create 20 positions with >$3000 total collateral
 */
import dotenv from 'dotenv';
dotenv.config();

import { createWalletClient, createPublicClient, http, parseUnits, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

const USDT = '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58';
const ROUTER = '0xee92ef898a0eabca96cad863cb0303b6d13cc023';

const USDT_ABI = [
  { name: 'approve', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
  { name: 'allowance', type: 'function', stateMutability: 'view', inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ type: 'uint256' }] },
] as const;

const ROUTER_ABI = [
  { name: 'openPosition', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'marketId', type: 'uint256' }, { name: 'isLong', type: 'bool' }, { name: 'collateralAmount', type: 'uint256' }, { name: 'leverage', type: 'uint256' }, { name: 'maxSlippage', type: 'uint256' }], outputs: [{ name: 'positionSize', type: 'uint256' }, { name: 'entryPrice', type: 'uint256' }] },
] as const;

// 20 positions across 10 markets, mix of long/short
const POSITIONS = [
  { market: 0, isLong: true, collateral: 200, leverage: 3 },   // Pacers LONG
  { market: 0, isLong: false, collateral: 150, leverage: 2 },  // Pacers SHORT
  { market: 1, isLong: true, collateral: 180, leverage: 4 },   // Patriots LONG
  { market: 1, isLong: false, collateral: 160, leverage: 3 },  // Patriots SHORT
  { market: 2, isLong: true, collateral: 170, leverage: 5 },   // Seahawks LONG
  { market: 2, isLong: false, collateral: 140, leverage: 2 },  // Seahawks SHORT
  { market: 3, isLong: true, collateral: 190, leverage: 3 },   // Jesus LONG
  { market: 3, isLong: false, collateral: 130, leverage: 4 },  // Jesus SHORT
  { market: 4, isLong: true, collateral: 175, leverage: 2 },   // Celtics LONG
  { market: 4, isLong: false, collateral: 155, leverage: 5 },  // Celtics SHORT
  { market: 5, isLong: true, collateral: 165, leverage: 3 },   // Thunder LONG
  { market: 5, isLong: false, collateral: 145, leverage: 4 },  // Thunder SHORT
  { market: 6, isLong: true, collateral: 185, leverage: 2 },   // BTC LONG
  { market: 6, isLong: false, collateral: 135, leverage: 3 },  // BTC SHORT
  { market: 7, isLong: true, collateral: 195, leverage: 4 },   // vdPlas LONG
  { market: 7, isLong: false, collateral: 125, leverage: 5 },  // vdPlas SHORT
  { market: 8, isLong: true, collateral: 160, leverage: 3 },   // GTA LONG
  { market: 8, isLong: false, collateral: 140, leverage: 2 },  // GTA SHORT
  { market: 9, isLong: true, collateral: 170, leverage: 4 },   // Wolves LONG
  { market: 9, isLong: false, collateral: 155, leverage: 3 },  // Wolves SHORT
];

async function main() {
  const account = privateKeyToAccount(process.env.KEEPER_PRIVATE_KEY as `0x${string}`);
  
  const client = createPublicClient({
    chain: bscTestnet,
    transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
  });
  
  const walletClient = createWalletClient({
    account,
    chain: bscTestnet,
    transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
  });

  const totalCollateral = POSITIONS.reduce((sum, p) => sum + p.collateral, 0);
  console.log(`Creating ${POSITIONS.length} positions with $${totalCollateral} total collateral\n`);

  // Check and set approval
  const allowance = await client.readContract({
    address: USDT,
    abi: USDT_ABI,
    functionName: 'allowance',
    args: [account.address, ROUTER],
  });

  const needed = parseUnits(totalCollateral.toString(), 18);
  if (allowance < needed) {
    console.log('Approving USDT...');
    const approveTx = await walletClient.writeContract({
      address: USDT,
      abi: USDT_ABI,
      functionName: 'approve',
      args: [ROUTER, parseUnits('1000000', 18)],
    });
    await client.waitForTransactionReceipt({ hash: approveTx });
    console.log('✓ Approved\n');
  }

  let success = 0;
  let failed = 0;

  for (let i = 0; i < POSITIONS.length; i++) {
    const p = POSITIONS[i];
    const side = p.isLong ? 'LONG' : 'SHORT';
    
    try {
      const hash = await walletClient.writeContract({
        address: ROUTER,
        abi: ROUTER_ABI,
        functionName: 'openPosition',
        args: [
          BigInt(p.market),
          p.isLong,
          parseUnits(p.collateral.toString(), 18),
          parseUnits(p.leverage.toString(), 18),
          parseUnits('0.05', 18), // 5% max slippage
        ],
      });
      
      const receipt = await client.waitForTransactionReceipt({ hash });
      console.log(`${i+1}. Market ${p.market} ${side} $${p.collateral} ${p.leverage}x ✓`);
      success++;
    } catch (e: any) {
      console.log(`${i+1}. Market ${p.market} ${side} $${p.collateral} ${p.leverage}x ❌ ${e.message?.slice(0, 50)}`);
      failed++;
    }
  }

  console.log(`\n✓ Done: ${success} success, ${failed} failed`);
  console.log(`Total collateral deployed: $${POSITIONS.slice(0, success).reduce((s, p) => s + p.collateral, 0)}`);
}

main().catch(console.error);
