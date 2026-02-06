import { createPublicClient, http } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';
const EXPECTED_USDT = '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58';

async function main() {
  const collateralToken = await publicClient.readContract({
    address: ROUTER,
    abi: [{ name: 'collateralToken', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] }],
    functionName: 'collateralToken',
  });
  console.log('Router.collateralToken:', collateralToken);
  console.log('Expected USDT:', EXPECTED_USDT);
  console.log('Match:', collateralToken.toLowerCase() === EXPECTED_USDT.toLowerCase());
}

main().catch(console.error);
