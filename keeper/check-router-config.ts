import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';
const PRICE_ENGINE_OLD = '0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33';
const PRICE_ENGINE_V2 = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';

// Check Router's configured PriceEngine
const ROUTER_ABI = [
  { name: 'priceEngine', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] },
  { name: 'ledger', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] },
  { name: 'lpPool', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] },
] as const;

const PRICE_ENGINE_ABI = [
  { name: 'getMarkPrice', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { name: 'isMarketActive', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'uint256' }], outputs: [{ type: 'bool' }] },
] as const;

async function main() {
  console.log('Router config:');
  
  const priceEngine = await publicClient.readContract({
    address: ROUTER,
    abi: ROUTER_ABI,
    functionName: 'priceEngine',
  });
  console.log(`  priceEngine: ${priceEngine}`);
  console.log(`  (Expected old: ${PRICE_ENGINE_OLD})`);
  console.log(`  (Expected new: ${PRICE_ENGINE_V2})`);
  
  const ledger = await publicClient.readContract({
    address: ROUTER,
    abi: ROUTER_ABI,
    functionName: 'ledger',
  });
  console.log(`  ledger: ${ledger}`);
  
  const lpPool = await publicClient.readContract({
    address: ROUTER,
    abi: ROUTER_ABI,
    functionName: 'lpPool',
  });
  console.log(`  lpPool: ${lpPool}`);
  
  // Check price on both PriceEngines
  console.log('\nPrice check for market 2:');
  
  try {
    const priceOld = await publicClient.readContract({
      address: PRICE_ENGINE_OLD,
      abi: PRICE_ENGINE_ABI,
      functionName: 'getMarkPrice',
      args: [2n],
    });
    console.log(`  Old PriceEngine: ${formatUnits(priceOld, 18)} (${Number(formatUnits(priceOld, 18)) * 100}%)`);
  } catch (e: any) {
    console.log(`  Old PriceEngine: ERROR - ${e.message?.slice(0, 50)}`);
  }
  
  try {
    const priceNew = await publicClient.readContract({
      address: PRICE_ENGINE_V2,
      abi: PRICE_ENGINE_ABI,
      functionName: 'getMarkPrice',
      args: [2n],
    });
    console.log(`  New PriceEngine: ${formatUnits(priceNew, 18)} (${Number(formatUnits(priceNew, 18)) * 100}%)`);
  } catch (e: any) {
    console.log(`  New PriceEngine: ERROR - ${e.message?.slice(0, 50)}`);
  }
  
  // Check configured priceEngine
  try {
    const priceConfigured = await publicClient.readContract({
      address: priceEngine,
      abi: PRICE_ENGINE_ABI,
      functionName: 'getMarkPrice',
      args: [2n],
    });
    console.log(`  Router's PriceEngine: ${formatUnits(priceConfigured, 18)} (${Number(formatUnits(priceConfigured, 18)) * 100}%)`);
  } catch (e: any) {
    console.log(`  Router's PriceEngine: ERROR - ${e.message?.slice(0, 50)}`);
  }
}

main().catch(console.error);
