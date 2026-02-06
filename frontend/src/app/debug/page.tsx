'use client';

import { useEffect, useState } from 'react';
import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';

const LP_POOL = '0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1';
const PRICE_ENGINE = '0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33';

export default function DebugPage() {
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function fetchData() {
      try {
        const client = createPublicClient({
          chain: bscTestnet,
          transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
        });

        // Test LP Pool totalAssets
        const totalAssets = await client.readContract({
          address: LP_POOL,
          abi: [{ name: 'totalAssets', type: 'function', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' }],
          functionName: 'totalAssets',
        });

        // Test mark price
        const markPrice = await client.readContract({
          address: PRICE_ENGINE,
          abi: [{ name: 'getMarkPrice', type: 'function', inputs: [{ type: 'uint256', name: 'marketId' }], outputs: [{ type: 'uint256' }], stateMutability: 'view' }],
          functionName: 'getMarkPrice',
          args: [1n],
        });

        setData({
          totalAssets: formatUnits(totalAssets as bigint, 18),
          markPrice: formatUnits(markPrice as bigint, 18),
          raw: {
            totalAssets: (totalAssets as bigint).toString(),
            markPrice: (markPrice as bigint).toString(),
          }
        });
      } catch (e: any) {
        setError(e.message);
        console.error('Debug error:', e);
      }
    }

    fetchData();
  }, []);

  return (
    <div className="p-8 bg-gray-900 min-h-screen text-white">
      <h1 className="text-2xl font-bold mb-4">Contract Debug</h1>
      
      {error && (
        <div className="bg-red-900 p-4 rounded mb-4">
          <p className="text-red-300">Error: {error}</p>
        </div>
      )}

      {data && (
        <div className="bg-gray-800 p-4 rounded">
          <p><strong>TVL (totalAssets):</strong> {Number(data.totalAssets).toLocaleString()} USDT</p>
          <p><strong>Mark Price (Market 1):</strong> {(Number(data.markPrice) * 100).toFixed(2)}%</p>
          <pre className="mt-4 text-xs text-gray-400">{JSON.stringify(data.raw, null, 2)}</pre>
        </div>
      )}

      {!data && !error && (
        <p className="text-gray-400">Loading...</p>
      )}
    </div>
  );
}
