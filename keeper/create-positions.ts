// Create 10+ positions across all markets
import { createPublicClient, createWalletClient, http, parseUnits, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

const PRIVATE_KEY = process.env.KEEPER_PRIVATE_KEY as `0x${string}`;
if (!PRIVATE_KEY) {
  console.error('❌ KEEPER_PRIVATE_KEY not set');
  process.exit(1);
}

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

// Contracts
const USDT = '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58';
const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';

const USDT_ABI = [
  { name: 'balanceOf', type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'approve', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
  { name: 'allowance', type: 'function', stateMutability: 'view', inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'mint', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [] },
] as const;

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

// Positions to create - mix of longs and shorts across all markets
const POSITIONS = [
  // Super Bowl markets - high volume, expiring soon
  { marketId: 2, isLong: true, collateral: '100', leverage: 3, name: 'Patriots SB LONG' },
  { marketId: 2, isLong: false, collateral: '80', leverage: 2, name: 'Patriots SB SHORT' },
  { marketId: 3, isLong: true, collateral: '150', leverage: 4, name: 'Seahawks SB LONG' },
  { marketId: 3, isLong: false, collateral: '120', leverage: 3, name: 'Seahawks SB SHORT' },
  
  // NBA markets
  { marketId: 1, isLong: true, collateral: '50', leverage: 5, name: 'Pacers NBA LONG' },
  { marketId: 5, isLong: false, collateral: '75', leverage: 2, name: 'Celtics NBA SHORT' },
  { marketId: 6, isLong: true, collateral: '100', leverage: 3, name: 'Thunder NBA LONG' },
  { marketId: 10, isLong: true, collateral: '60', leverage: 4, name: 'Wolves NBA LONG' },
  
  // Crypto/Fun markets
  { marketId: 4, isLong: true, collateral: '90', leverage: 2, name: 'Jesus/GTA LONG' },
  { marketId: 7, isLong: false, collateral: '110', leverage: 3, name: 'BTC $1M SHORT' },
  { marketId: 9, isLong: true, collateral: '70', leverage: 5, name: 'GTA 6 $100 LONG' },
  
  // Politics
  { marketId: 8, isLong: true, collateral: '40', leverage: 2, name: 'van der Plas LONG' },
];

async function main() {
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║     🎯 LEVER Position Creator - Creating 12 Positions      ║');
  console.log('╚════════════════════════════════════════════════════════════╝\n');
  
  console.log(`  🔑 Wallet: ${account.address}`);
  
  // Check USDT balance
  const balance = await publicClient.readContract({
    address: USDT,
    abi: USDT_ABI,
    functionName: 'balanceOf',
    args: [account.address],
  });
  
  console.log(`  💰 USDT Balance: ${formatUnits(balance, 18)} USDT`);
  
  // Calculate total needed
  const totalNeeded = POSITIONS.reduce((sum, p) => sum + Number(p.collateral), 0);
  console.log(`  📊 Total Collateral Needed: ${totalNeeded} USDT\n`);
  
  if (Number(formatUnits(balance, 18)) < totalNeeded) {
    console.log('  ⚠️  Insufficient balance. Attempting to mint test USDT...');
    try {
      const mintAmount = parseUnits((totalNeeded * 2).toString(), 18);
      const mintHash = await walletClient.writeContract({
        address: USDT,
        abi: USDT_ABI,
        functionName: 'mint',
        args: [account.address, mintAmount],
      });
      console.log(`  ✅ Minted ${totalNeeded * 2} USDT: ${mintHash.slice(0, 20)}...`);
      await publicClient.waitForTransactionReceipt({ hash: mintHash });
    } catch (e: any) {
      console.log(`  ❌ Mint failed: ${e.message?.slice(0, 50)}`);
      console.log('  Continuing with existing balance...');
    }
  }
  
  // Check and set allowance
  const allowance = await publicClient.readContract({
    address: USDT,
    abi: USDT_ABI,
    functionName: 'allowance',
    args: [account.address, ROUTER],
  });
  
  const requiredAllowance = parseUnits((totalNeeded * 2).toString(), 18);
  
  if (allowance < requiredAllowance) {
    console.log('  📝 Approving USDT spending...');
    const approveHash = await walletClient.writeContract({
      address: USDT,
      abi: USDT_ABI,
      functionName: 'approve',
      args: [ROUTER, requiredAllowance],
    });
    console.log(`  ✅ Approved: ${approveHash.slice(0, 20)}...`);
    await publicClient.waitForTransactionReceipt({ hash: approveHash });
  }
  
  console.log('\n  📈 Opening Positions:\n');
  
  let successCount = 0;
  let failCount = 0;
  
  for (const pos of POSITIONS) {
    const collateralWei = parseUnits(pos.collateral, 18);
    const leverageWei = parseUnits(pos.leverage.toString(), 18);
    const maxSlippage = parseUnits('0.1', 18); // 10% max slippage
    
    try {
      const hash = await walletClient.writeContract({
        address: ROUTER,
        abi: ROUTER_ABI,
        functionName: 'openPosition',
        args: [BigInt(pos.marketId), pos.isLong, collateralWei, leverageWei, maxSlippage],
      });
      
      console.log(`  ✅ ${pos.name}: $${pos.collateral} @ ${pos.leverage}x`);
      console.log(`     TX: ${hash.slice(0, 20)}...`);
      
      // Wait for confirmation
      await publicClient.waitForTransactionReceipt({ hash });
      successCount++;
      
      // Small delay between txs
      await new Promise(r => setTimeout(r, 1000));
      
    } catch (e: any) {
      console.log(`  ❌ ${pos.name}: ${e.message?.slice(0, 60)}`);
      failCount++;
    }
  }
  
  console.log('\n╔════════════════════════════════════════════════════════════╗');
  console.log(`║  ✅ Success: ${successCount}  |  ❌ Failed: ${failCount}  |  Total: ${POSITIONS.length}       ║`);
  console.log('╚════════════════════════════════════════════════════════════╝');
}

main().catch(console.error);
