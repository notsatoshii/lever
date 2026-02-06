import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const LP_POOL = '0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1';
const LEDGER = '0x6fd251dec261512f758768447489855e215352db';

const LP_ABI = [
  { name: 'totalAssets', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'totalAllocated', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'utilization', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
] as const;

const LEDGER_ABI = [
  { name: 'getMarket', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'tuple', components: [
    { name: 'oracle', type: 'address' },
    { name: 'totalLongOI', type: 'uint256' },
    { name: 'totalShortOI', type: 'uint256' },
    { name: 'maxOI', type: 'uint256' },
    { name: 'borrowIndex', type: 'uint256' },
    { name: 'fundingIndex', type: 'int256' },
    { name: 'resolutionTime', type: 'uint256' },
    { name: 'liveStartTime', type: 'uint256' },
    { name: 'isLive', type: 'bool' },
    { name: 'active', type: 'bool' },
  ]}] },
] as const;

const client = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

async function check() {
  console.log('=== LP Pool ===');
  const [totalAssets, totalAllocated, utilization] = await Promise.all([
    client.readContract({ address: LP_POOL, abi: LP_ABI, functionName: 'totalAssets' }),
    client.readContract({ address: LP_POOL, abi: LP_ABI, functionName: 'totalAllocated' }),
    client.readContract({ address: LP_POOL, abi: LP_ABI, functionName: 'utilization' }),
  ]);
  
  console.log('totalAssets:', formatUnits(totalAssets, 18), 'USDT');
  console.log('totalAllocated (capital deployed):', formatUnits(totalAllocated, 18), 'USDT');
  console.log('utilization:', (Number(formatUnits(utilization, 18)) * 100).toFixed(4), '%');
  
  // Check actual OI from ledger
  console.log('\n=== Ledger OI (Markets 1-10) ===');
  let totalOI = 0n;
  for (let i = 1; i <= 10; i++) {
    try {
      const market = await client.readContract({ address: LEDGER, abi: LEDGER_ABI, functionName: 'getMarket', args: [BigInt(i)] });
      const marketOI = market.totalLongOI + market.totalShortOI;
      if (marketOI > 0n) {
        console.log(`Market ${i}: Long=${formatUnits(market.totalLongOI, 18)}, Short=${formatUnits(market.totalShortOI, 18)}, Total=${formatUnits(marketOI, 18)}`);
        totalOI += marketOI;
      }
    } catch (e) {
      // Market doesn't exist
    }
  }
  console.log('\nTotal OI across markets:', formatUnits(totalOI, 18), 'USDT');
  
  // Compare
  console.log('\n=== Comparison ===');
  console.log('LP totalAllocated:', formatUnits(totalAllocated, 18));
  console.log('Ledger total OI:', formatUnits(totalOI, 18));
  console.log('Match:', totalAllocated === totalOI ? 'YES' : 'NO - MISMATCH!');
}

check().catch(console.error);
