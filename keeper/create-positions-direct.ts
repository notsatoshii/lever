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
  { name: 'allocate', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'amount', type: 'uint256' }], outputs: [] },
] as const;

const USDT_ABI = [
  { name: 'transfer', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
] as const;

const PRICE_ABI = [
  { name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
] as const;

// Positions to create
const POSITIONS = [
  { marketId: 2, isLong: true, collateral: '100', leverage: 3, name: 'Patriots SB LONG' },
  { marketId: 2, isLong: false, collateral: '80', leverage: 2, name: 'Patriots SB SHORT' },
  { marketId: 3, isLong: true, collateral: '150', leverage: 4, name: 'Seahawks SB LONG' },
  { marketId: 3, isLong: false, collateral: '120', leverage: 3, name: 'Seahawks SB SHORT' },
  { marketId: 1, isLong: true, collateral: '50', leverage: 5, name: 'Pacers NBA LONG' },
  { marketId: 5, isLong: false, collateral: '75', leverage: 2, name: 'Celtics NBA SHORT' },
  { marketId: 6, isLong: true, collateral: '100', leverage: 3, name: 'Thunder NBA LONG' },
  { marketId: 4, isLong: true, collateral: '90', leverage: 2, name: 'Jesus/GTA LONG' },
  { marketId: 7, isLong: false, collateral: '110', leverage: 3, name: 'BTC $1M SHORT' },
  { marketId: 9, isLong: true, collateral: '70', leverage: 5, name: 'GTA 6 $100 LONG' },
  { marketId: 8, isLong: true, collateral: '40', leverage: 2, name: 'van der Plas LONG' },
];

async function main() {
  console.log('╔════════════════════════════════════════════════════════════╗');
  console.log('║     🎯 Creating Positions Directly via Ledger              ║');
  console.log('╚════════════════════════════════════════════════════════════╝\n');
  
  let successCount = 0;
  let failCount = 0;
  
  for (const pos of POSITIONS) {
    try {
      // Get price
      const price = await publicClient.readContract({
        address: PRICE_ENGINE_V2,
        abi: PRICE_ABI,
        functionName: 'getMarkPrice',
        args: [BigInt(pos.marketId)],
      });
      
      const collateral = parseUnits(pos.collateral, 18);
      const leverage = BigInt(pos.leverage);
      const positionSize = collateral * leverage;
      const signedSize = pos.isLong ? positionSize : -positionSize;
      
      const notional = positionSize * price / parseUnits('1', 18);
      
      console.log(`📊 ${pos.name}:`);
      console.log(`   Collateral: $${pos.collateral}, Size: ${formatUnits(positionSize, 18)}, Notional: $${formatUnits(notional, 18)}`);
      
      // Transfer collateral to Ledger
      const transferHash = await walletClient.writeContract({
        address: USDT,
        abi: USDT_ABI,
        functionName: 'transfer',
        args: [LEDGER, collateral],
      });
      await publicClient.waitForTransactionReceipt({ hash: transferHash });
      
      // Allocate from LP
      try {
        const allocateHash = await walletClient.writeContract({
          address: LP_POOL,
          abi: LP_ABI,
          functionName: 'allocate',
          args: [notional],
        });
        await publicClient.waitForTransactionReceipt({ hash: allocateHash });
      } catch (e: any) {
        console.log(`   ⚠️ LP allocate failed (continuing): ${e.message?.slice(0, 50)}`);
      }
      
      // Open position
      const openHash = await walletClient.writeContract({
        address: LEDGER,
        abi: LEDGER_ABI,
        functionName: 'openPosition',
        args: [account.address, BigInt(pos.marketId), signedSize, price, collateral],
      });
      await publicClient.waitForTransactionReceipt({ hash: openHash });
      
      console.log(`   ✅ Success! TX: ${openHash.slice(0, 20)}...`);
      successCount++;
      
      // Small delay
      await new Promise(r => setTimeout(r, 500));
      
    } catch (e: any) {
      console.log(`   ❌ Failed: ${e.message?.slice(0, 80)}`);
      failCount++;
    }
  }
  
  console.log('\n╔════════════════════════════════════════════════════════════╗');
  console.log(`║  ✅ Success: ${successCount}  |  ❌ Failed: ${failCount}  |  Total: ${POSITIONS.length}       ║`);
  console.log('╚════════════════════════════════════════════════════════════╝');
}

main().catch(console.error);
