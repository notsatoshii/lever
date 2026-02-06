'use client';

import { useState, useEffect } from 'react';
import { useAccount } from 'wagmi';
import Link from 'next/link';
import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';
import { CONTRACTS, LEDGER_ABI, LP_POOL_ABI, PRICE_ENGINE_ABI } from '@/config/contracts';

const client = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const MARKETS: Record<number, { name: string; icon: string }> = {
  1: { name: 'MicroStrategy BTC', icon: '🪙' },
  2: { name: 'Deportations', icon: '🇺🇸' },
  3: { name: 'GTA 6', icon: '🎮' },
  4: { name: 'Fed Rate', icon: '🏦' },
  5: { name: 'Arsenal', icon: '⚽' },
  6: { name: 'ETH $10k', icon: '💎' },
};

interface Position {
  marketId: number;
  size: bigint;
  collateral: bigint;
  entryPrice: bigint;
  isLong: boolean;
}

export default function PortfolioPage() {
  const { address, isConnected } = useAccount();
  const contracts = CONTRACTS[97];

  const [positions, setPositions] = useState<Position[]>([]);
  const [lpBalance, setLpBalance] = useState<bigint | null>(null);
  const [sharePrice, setSharePrice] = useState<bigint | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'positions' | 'lp' | 'history'>('positions');

  // Fetch user data
  useEffect(() => {
    async function fetchData() {
      if (!address) {
        setIsLoading(false);
        return;
      }

      try {
        // Fetch positions for each market
        const positionPromises = Object.keys(MARKETS).map(async (id) => {
          try {
            const pos = await client.readContract({
              address: contracts.LEDGER as `0x${string}`,
              abi: LEDGER_ABI,
              functionName: 'getPosition',
              args: [address, BigInt(id)],
            });
            return { marketId: Number(id), ...(pos as any) };
          } catch {
            return null;
          }
        });

        const [posResults, lp, price] = await Promise.all([
          Promise.all(positionPromises),
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'balanceOf',
            args: [address],
          }),
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'sharePrice',
          }),
        ]);

        // Filter out null and zero positions
        const validPositions = posResults.filter(
          (p) => p && p.size && p.size !== 0n
        ) as Position[];
        setPositions(validPositions);
        setLpBalance(lp as bigint);
        setSharePrice(price as bigint);
      } catch (e) {
        console.error('Error fetching portfolio:', e);
      }
      setIsLoading(false);
    }

    fetchData();
    const interval = setInterval(fetchData, 10000);
    return () => clearInterval(interval);
  }, [address, contracts]);

  const totalLPValue = lpBalance && sharePrice
    ? Number(formatUnits(lpBalance, 18)) * Number(formatUnits(sharePrice, 18))
    : 0;

  // Calculate total PnL (mock for now - would need current prices)
  const totalUnrealizedPnL = positions.reduce((acc, pos) => {
    // Mock calculation
    return acc + (Math.random() - 0.5) * 100;
  }, 0);

  if (!isConnected) {
    return (
      <div className="px-6 py-8">
        <div className="text-center py-20">
          <h1 className="text-2xl font-bold mb-4">Portfolio</h1>
          <p className="text-gray-400 mb-8">Connect your wallet to view your positions</p>
        </div>
      </div>
    );
  }

  return (
    <div className="px-6 py-8">
      <h1 className="text-2xl font-bold mb-6">Portfolio</h1>

      {/* Account Summary */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <p className="text-gray-400 text-sm mb-1">Total Equity</p>
          <p className="text-2xl font-bold">${(totalLPValue + 1000).toLocaleString()}</p>
        </div>
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <p className="text-gray-400 text-sm mb-1">Open Positions</p>
          <p className="text-2xl font-bold">{positions.length}</p>
        </div>
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <p className="text-gray-400 text-sm mb-1">Unrealized PnL</p>
          <p className={`text-2xl font-bold ${totalUnrealizedPnL >= 0 ? 'text-green-400' : 'text-red-400'}`}>
            {totalUnrealizedPnL >= 0 ? '+' : ''}{totalUnrealizedPnL.toFixed(2)} USDC
          </p>
        </div>
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <p className="text-gray-400 text-sm mb-1">LP Value</p>
          <p className="text-2xl font-bold">${totalLPValue.toLocaleString()}</p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 mb-6 border-b border-gray-800 pb-2">
        {(['positions', 'lp', 'history'] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2 rounded-t-lg font-medium capitalize transition ${
              activeTab === tab
                ? 'bg-gray-800 text-white'
                : 'text-gray-400 hover:text-white'
            }`}
          >
            {tab === 'lp' ? 'LP Positions' : tab}
          </button>
        ))}
      </div>

      {/* Positions Tab */}
      {activeTab === 'positions' && (
        <div className="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
          {isLoading ? (
            <div className="p-8 text-center text-gray-400">Loading positions...</div>
          ) : positions.length === 0 ? (
            <div className="p-8 text-center">
              <p className="text-gray-400 mb-4">No open positions</p>
              <Link href="/" className="text-blue-500 hover:underline">
                Browse markets →
              </Link>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[800px]">
                <thead className="bg-gray-700/50 text-gray-400 text-sm">
                  <tr>
                    <th className="text-left p-4">Market</th>
                    <th className="text-left p-4">Side</th>
                    <th className="text-right p-4">Size</th>
                    <th className="text-right p-4">Entry Price</th>
                    <th className="text-right p-4">Mark Price</th>
                    <th className="text-right p-4">PnL</th>
                    <th className="text-right p-4">Liq. Price</th>
                    <th className="text-right p-4">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {positions.map((pos) => {
                    const market = MARKETS[pos.marketId] || { name: `Market ${pos.marketId}`, icon: '📊' };
                    const isLong = pos.size > 0n;
                    const mockPnL = (Math.random() - 0.5) * 50;

                    return (
                      <tr key={pos.marketId} className="border-t border-gray-700">
                        <td className="p-4">
                          <div className="flex items-center gap-2">
                            <span>{market.icon}</span>
                            <span className="font-medium whitespace-nowrap">{market.name}</span>
                          </div>
                        </td>
                        <td className="p-4">
                          <span className={`px-2 py-1 rounded text-xs font-semibold whitespace-nowrap ${
                            isLong ? 'bg-lever-green/20 text-lever-green' : 'bg-lever-red/20 text-lever-red'
                          }`}>
                            {isLong ? 'LONG' : 'SHORT'}
                          </span>
                        </td>
                        <td className="p-4 text-right whitespace-nowrap">
                          {Number(formatUnits(pos.size < 0n ? -pos.size : pos.size, 18)).toLocaleString()}
                        </td>
                        <td className="p-4 text-right whitespace-nowrap">
                          {(Number(formatUnits(pos.entryPrice, 18)) * 100).toFixed(1)}¢
                        </td>
                        <td className="p-4 text-right whitespace-nowrap">50.0¢</td>
                        <td className={`p-4 text-right font-medium whitespace-nowrap ${mockPnL >= 0 ? 'text-lever-green' : 'text-lever-red'}`}>
                          {mockPnL >= 0 ? '+' : ''}{mockPnL.toFixed(2)}
                        </td>
                        <td className="p-4 text-right text-gray-400 whitespace-nowrap">
                          {isLong ? '35.0¢' : '65.0¢'}
                        </td>
                        <td className="p-4 text-right">
                          <Link
                            href={`/markets/${pos.marketId}`}
                            className="text-blue-500 hover:underline text-sm whitespace-nowrap"
                          >
                            Manage
                          </Link>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* LP Positions Tab */}
      {activeTab === 'lp' && (
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-6">
          {lpBalance && lpBalance > 0n ? (
            <div>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                <div>
                  <p className="text-gray-400 text-sm mb-1">LP Tokens</p>
                  <p className="text-xl font-bold">
                    {Number(formatUnits(lpBalance, 18)).toLocaleString()} lvUSDT
                  </p>
                </div>
                <div>
                  <p className="text-gray-400 text-sm mb-1">Value</p>
                  <p className="text-xl font-bold">${totalLPValue.toLocaleString()}</p>
                </div>
                <div>
                  <p className="text-gray-400 text-sm mb-1">Share Price</p>
                  <p className="text-xl font-bold">
                    ${sharePrice ? Number(formatUnits(sharePrice, 18)).toFixed(4) : '—'}
                  </p>
                </div>
                <div>
                  <p className="text-gray-400 text-sm mb-1">Earned Fees</p>
                  <p className="text-xl font-bold text-green-400">+$0.00</p>
                </div>
              </div>
              <Link
                href="/lp"
                className="inline-block px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg font-medium"
              >
                Manage LP Position
              </Link>
            </div>
          ) : (
            <div className="text-center py-8">
              <p className="text-gray-400 mb-4">No LP positions</p>
              <Link href="/lp" className="text-blue-500 hover:underline">
                Provide liquidity →
              </Link>
            </div>
          )}
        </div>
      )}

      {/* History Tab */}
      {activeTab === 'history' && (
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-8 text-center">
          <p className="text-gray-400">Trade history coming soon</p>
          <p className="text-gray-500 text-sm mt-2">
            Historical trades will be indexed from on-chain events
          </p>
        </div>
      )}
    </div>
  );
}
