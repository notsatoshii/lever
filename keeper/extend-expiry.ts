import dotenv from 'dotenv';
dotenv.config();
import { createWalletClient, createPublicClient, http, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

const PRICE_ENGINE = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';
const ABI = [{
  name: 'configureMarket',
  type: 'function',
  stateMutability: 'nonpayable',
  inputs: [
    { name: 'marketId', type: 'uint256' },
    { name: 'expiryTimestamp', type: 'uint256' },
    { name: 'maxSpread', type: 'uint256' },
    { name: 'maxTickMovement', type: 'uint256' },
    { name: 'minLiquidityDepth', type: 'uint256' },
    { name: 'alpha', type: 'uint256' },
    { name: 'volatilityWindow', type: 'uint256' },
  ],
  outputs: [],
}] as const;

// Set all markets to expire 90 days from now for full time weight
const FAR_EXPIRY = Math.floor(Date.now()/1000) + 90 * 24 * 60 * 60;

async function main() {
  const account = privateKeyToAccount(process.env.KEEPER_PRIVATE_KEY as `0x${string}`);
  const client = createPublicClient({ chain: bscTestnet, transport: http('https://data-seed-prebsc-1-s1.binance.org:8545') });
  const walletClient = createWalletClient({ account, chain: bscTestnet, transport: http('https://data-seed-prebsc-1-s1.binance.org:8545') });

  console.log('Extending expiry to 90 days out (full time weight)...');

  for (let i = 0; i < 10; i++) {
    const hash = await walletClient.writeContract({
      address: PRICE_ENGINE,
      abi: ABI,
      functionName: 'configureMarket',
      args: [
        BigInt(i),
        BigInt(FAR_EXPIRY),
        parseUnits('0.1', 18),
        parseUnits('1', 18),
        parseUnits('100', 18),
        parseUnits('1', 18),  // alpha=1.0
        3600n,
      ],
    });
    await client.waitForTransactionReceipt({ hash });
    process.stdout.write(i + ' ');
  }
  console.log('\n✓ All expiries extended. Next update will converge fast.');
}

main().catch(console.error);
