import { createPublicClient, http } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';

async function main() {
  const bytecode = await publicClient.getCode({ address: ROUTER });
  console.log('Bytecode length:', bytecode?.length);
  console.log('First 100 chars:', bytecode?.slice(0, 100));
  console.log('Last 100 chars:', bytecode?.slice(-100));
  
  // Check function selector for openPosition
  // openPosition(uint256,bool,uint256,uint256,uint256) = 0x???
  console.log('\nChecking if openPosition selector exists...');
  
  // The selector for "openPosition(uint256,bool,uint256,uint256,uint256)"
  // Let me calculate it
  const selector = '0x' + 'openPosition(uint256,bool,uint256,uint256,uint256)'
    .split('')
    .map(c => c.charCodeAt(0).toString(16))
    .join('');
  
  // Actually, we need to use keccak256 to get the selector
}

main().catch(console.error);
