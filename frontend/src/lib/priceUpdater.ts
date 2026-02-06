import { createWalletClient, createPublicClient, http, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bscTestnet } from 'viem/chains';

// Keeper wallet for price updates (testnet only - in production use proper oracle)
const KEEPER_KEY = '0x4165dec4fb068de68c290670b28870cbe54060d81f444959c9cd67445b3eb5c4';
const PRICE_ENGINE = '0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33';

const account = privateKeyToAccount(KEEPER_KEY);

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const walletClient = createWalletClient({
  account,
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const PRICE_ENGINE_ABI = [
  {
    name: 'updatePrice',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'newOraclePrice', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    name: 'getMarkPrice',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'marketId', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'isPriceStale',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'maxAge', type: 'uint256' },
    ],
    outputs: [{ type: 'bool' }],
  },
] as const;

/**
 * Update price for a market if stale
 * Returns true if price was updated, false if already fresh
 */
export async function ensureFreshPrice(marketId: number): Promise<boolean> {
  try {
    // Check if price is stale (older than 60 seconds)
    const isStale = await publicClient.readContract({
      address: PRICE_ENGINE,
      abi: PRICE_ENGINE_ABI,
      functionName: 'isPriceStale',
      args: [BigInt(marketId), 60n],
    });

    if (!isStale) {
      console.log(`Market ${marketId} price is fresh`);
      return false;
    }

    // Get current price and refresh it (small variance for realism)
    const currentPrice = await publicClient.readContract({
      address: PRICE_ENGINE,
      abi: PRICE_ENGINE_ABI,
      functionName: 'getMarkPrice',
      args: [BigInt(marketId)],
    });

    // Add tiny variance (±0.1%) to avoid "same price" issues
    const variance = 1 + (Math.random() - 0.5) * 0.002;
    const newPrice = BigInt(Math.floor(Number(currentPrice) * variance));

    console.log(`Updating market ${marketId} price...`);
    
    const hash = await walletClient.writeContract({
      address: PRICE_ENGINE,
      abi: PRICE_ENGINE_ABI,
      functionName: 'updatePrice',
      args: [BigInt(marketId), newPrice],
    });

    // Wait for confirmation
    await publicClient.waitForTransactionReceipt({ hash });
    console.log(`Market ${marketId} price updated: ${hash}`);
    
    return true;
  } catch (error) {
    console.error('Error updating price:', error);
    throw error;
  }
}

/**
 * Force update price regardless of staleness
 */
export async function forceUpdatePrice(marketId: number, price?: number): Promise<string> {
  const priceWei = price 
    ? parseUnits(price.toString(), 18)
    : await publicClient.readContract({
        address: PRICE_ENGINE,
        abi: PRICE_ENGINE_ABI,
        functionName: 'getMarkPrice',
        args: [BigInt(marketId)],
      });

  const hash = await walletClient.writeContract({
    address: PRICE_ENGINE,
    abi: PRICE_ENGINE_ABI,
    functionName: 'updatePrice',
    args: [BigInt(marketId), priceWei as bigint],
  });

  await publicClient.waitForTransactionReceipt({ hash });
  return hash;
}
