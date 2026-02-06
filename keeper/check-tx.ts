import { createPublicClient, http } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

async function main() {
  const txHash = '0x64853791af8942491a98ce1b129ec038b89e6e45f7cca40ae698295509a346dc';
  
  const receipt = await publicClient.getTransactionReceipt({ hash: txHash as `0x${string}` });
  console.log('Receipt:', JSON.stringify(receipt, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
  
  const tx = await publicClient.getTransaction({ hash: txHash as `0x${string}` });
  console.log('\nTransaction:', JSON.stringify(tx, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
}

main().catch(console.error);
