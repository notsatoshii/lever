import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const PRICE_ENGINE = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';
const LEDGER = '0x74b24940c76c53cb0e9f0194cc79f6c08cf79f73';

const PRICE_ENGINE_ABI = [
  { name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { name: 'getMarketConfig', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ name: 'expiryTimestamp', type: 'uint256' }, { name: 'maxSpread', type: 'uint256' }, { name: 'maxTickMovement', type: 'uint256' }, { name: 'minLiquidityDepth', type: 'uint256' }, { name: 'alpha', type: 'uint256' }, { name: 'active', type: 'bool' }] },
] as const;

const LEDGER_ABI = [
  { name: 'getMarket', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'tuple', components: [{ name: 'oracle', type: 'address' }, { name: 'totalLongOI', type: 'uint256' }, { name: 'totalShortOI', type: 'uint256' }, { name: 'maxOI', type: 'uint256' }, { name: 'borrowIndex', type: 'uint256' }, { name: 'fundingIndex', type: 'int256' }, { name: 'resolutionTime', type: 'uint256' }, { name: 'liveStartTime', type: 'uint256' }, { name: 'isLive', type: 'bool' }, { name: 'active', type: 'bool' }] }] },
] as const;

const MARKETS = [
  'Indiana Pacers NBA',
  'Patriots Super Bowl',
  'Seahawks Super Bowl', 
  'Jesus/GTA VI',
  'Celtics NBA',
  'Thunder NBA',
  'BTC $1M/GTA VI',
  'van der Plas PM',
  'GTA 6 $100+',
  'Timberwolves NBA',
];

async function main() {
  const client = createPublicClient({
    chain: bscTestnet,
    transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
  });

  console.log('Market Status Check\n' + '='.repeat(60));
  
  for (let i = 0; i < 10; i++) {
    try {
      const [price, marketConfig, ledgerData] = await Promise.all([
        client.readContract({ address: PRICE_ENGINE, abi: PRICE_ENGINE_ABI, functionName: 'getMarkPrice', args: [BigInt(i)] }),
        client.readContract({ address: PRICE_ENGINE, abi: PRICE_ENGINE_ABI, functionName: 'getMarketConfig', args: [BigInt(i)] }).catch(() => null),
        client.readContract({ address: LEDGER, abi: LEDGER_ABI, functionName: 'getMarket', args: [BigInt(i)] }),
      ]);
      
      const priceNum = Number(formatUnits(price as bigint, 18));
      const ledger = ledgerData as any;
      const config = marketConfig as any;
      
      console.log(`\nMarket ${i}: ${MARKETS[i]}`);
      console.log(`  Price: ${(priceNum * 100).toFixed(2)}%`);
      console.log(`  Ledger active: ${ledger.active}`);
      console.log(`  Ledger isLive: ${ledger.isLive}`);
      console.log(`  PriceEngine active: ${config?.active ?? 'N/A'}`);
      console.log(`  Total OI: $${Number(formatUnits(BigInt(ledger.totalLongOI) + BigInt(ledger.totalShortOI), 18)).toFixed(2)}`);
    } catch (e: any) {
      console.log(`\nMarket ${i}: ${MARKETS[i]}`);
      console.log(`  ERROR: ${e.message?.slice(0, 80)}`);
    }
  }
}

main();
