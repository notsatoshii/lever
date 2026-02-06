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

const MARKETS = [
  { id: 0, expiry: 1782864000 },
  { id: 1, expiry: 1770552000 },
  { id: 2, expiry: 1770552000 },
  { id: 3, expiry: 1785499200 },
  { id: 4, expiry: 1782864000 },
  { id: 5, expiry: 1782864000 },
  { id: 6, expiry: 1785499200 },
  { id: 7, expiry: 1798675200 },
  { id: 8, expiry: 1772280000 },
  { id: 9, expiry: 1782864000 },
];

async function main() {
  const account = privateKeyToAccount(process.env.KEEPER_PRIVATE_KEY as `0x${string}`);
  const client = createPublicClient({ chain: bscTestnet, transport: http('https://data-seed-prebsc-1-s1.binance.org:8545') });
  const walletClient = createWalletClient({ account, chain: bscTestnet, transport: http('https://data-seed-prebsc-1-s1.binance.org:8545') });

  console.log('Setting alpha=1.0 (instant convergence) for all markets...');

  for (const m of MARKETS) {
    const hash = await walletClient.writeContract({
      address: PRICE_ENGINE,
      abi: ABI,
      functionName: 'configureMarket',
      args: [
        BigInt(m.id),
        BigInt(m.expiry),
        parseUnits('0.1', 18),       // 10% max spread
        parseUnits('1', 18),         // 100% max tick (no limit for instant fix)
        parseUnits('100', 18),       // $100 min liquidity
        parseUnits('1', 18),         // alpha=1.0 (100% = instant)
        3600n,
      ],
    });
    await client.waitForTransactionReceipt({ hash });
    process.stdout.write(m.id + ' ');
  }
  console.log('\n✓ Done! Next keeper update will set correct prices.');
}

main().catch(console.error);
