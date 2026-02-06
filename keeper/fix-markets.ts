import { createPublicClient, createWalletClient, http, formatUnits } from 'viem';
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
const PRICE_ENGINE_V2 = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';

const LEDGER_ABI = [
  { name: 'owner', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] },
  { name: 'markets', type: 'function', stateMutability: 'view', inputs: [{ name: '', type: 'uint256' }], 
    outputs: [
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
    ] 
  },
  { name: 'addMarket', type: 'function', stateMutability: 'nonpayable', 
    inputs: [
      { name: 'oracle', type: 'address' }, 
      { name: 'maxOI', type: 'uint256' }, 
      { name: 'resolutionTime', type: 'uint256' }
    ], 
    outputs: [] 
  },
  { name: 'setMarketActive', type: 'function', stateMutability: 'nonpayable', 
    inputs: [{ name: 'marketId', type: 'uint256' }, { name: 'active', type: 'bool' }], 
    outputs: [] 
  },
] as const;

async function main() {
  console.log('Checking Ledger markets...\n');
  
  const owner = await publicClient.readContract({
    address: LEDGER,
    abi: LEDGER_ABI,
    functionName: 'owner',
  });
  console.log(`Ledger owner: ${owner}`);
  console.log(`Our address: ${account.address}\n`);
  
  for (let i = 1; i <= 10; i++) {
    try {
      const market = await publicClient.readContract({
        address: LEDGER,
        abi: LEDGER_ABI,
        functionName: 'markets',
        args: [BigInt(i)],
      });
      console.log(`Market ${i}:`);
      console.log(`  oracle: ${market[0]}`);
      console.log(`  active: ${market[9]}, isLive: ${market[8]}`);
      console.log(`  longOI: ${formatUnits(market[1], 18)}, shortOI: ${formatUnits(market[2], 18)}`);
      
      // If oracle is zero or not set, need to add market
      if (market[0] === '0x0000000000000000000000000000000000000000') {
        console.log(`  ⚠️ Market ${i} not configured!`);
      }
    } catch (e: any) {
      console.log(`Market ${i}: ERROR - ${e.message?.slice(0, 60)}`);
    }
  }
}

main().catch(console.error);
