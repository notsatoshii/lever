'use client';

import { useState, useEffect } from 'react';
import { useParams, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { useAccount } from 'wagmi';
import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';
import { CONTRACTS, PRICE_ENGINE_ABI, LEDGER_ABI, FUNDING_ENGINE_ABI } from '@/config/contracts';
import { TradingPanel } from '@/components/TradingPanel';
import { PriceChart } from '@/components/PriceChart';

const client = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const MARKETS: Record<number, { name: string; question: string; icon: string }> = {
  0: { name: 'Test Market', question: 'Testnet demo market', icon: '🧪' },
  1: { name: 'BTC $150K', question: 'Will Bitcoin exceed $150,000 by end of 2026?', icon: '₿' },
  2: { name: 'Fed Rate Cut', question: 'Will the Fed cut rates by 50+ bps in 2026?', icon: '🏦' },
  3: { name: 'ETH Flippening', question: 'Will ETH market cap exceed BTC in 2026?', icon: '💎' },
  4: { name: 'US Recession', question: 'Will the US enter a recession in 2026?', icon: '📉' },
  5: { name: 'Champions League', question: 'Will Real Madrid win Champions League 2026?', icon: '⚽' },
  6: { name: 'SOL $500', question: 'Will Solana exceed $500 in 2026?', icon: '◎' },
};

// Recent trades - would come from indexer in production
function RecentTrades() {
  return (
    <div className="bg-gray-800 rounded-xl border border-gray-700 h-full">
      <div className="p-4 border-b border-gray-700">
        <h3 className="font-semibold">Recent Trades</h3>
      </div>
      <div className="flex items-center justify-center h-48 text-gray-500 text-sm">
        <div className="text-center">
          <p>No trades yet</p>
          <p className="text-xs text-gray-600 mt-1">Be the first to trade!</p>
        </div>
      </div>
    </div>
  );
}

export default function MarketPage() {
  const params = useParams();
  const searchParams = useSearchParams();
  const marketId = Number(params.id) || 1;
  const initialSide = searchParams.get('side') as 'long' | 'short' | null;
  
  const contracts = CONTRACTS[97];
  const market = MARKETS[marketId] || MARKETS[1];

  const [price, setPrice] = useState<bigint | null>(null);
  const [marketData, setMarketData] = useState<any>(null);
  const [fundingRate, setFundingRate] = useState<bigint | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    async function fetchData() {
      try {
        const [priceData, mktData, funding] = await Promise.all([
          client.readContract({
            address: contracts.PRICE_ENGINE as `0x${string}`,
            abi: PRICE_ENGINE_ABI,
            functionName: 'getMarkPrice',
            args: [BigInt(marketId)],
          }),
          client.readContract({
            address: contracts.LEDGER as `0x${string}`,
            abi: LEDGER_ABI,
            functionName: 'getMarket',
            args: [BigInt(marketId)],
          }),
          client.readContract({
            address: contracts.FUNDING_ENGINE as `0x${string}`,
            abi: FUNDING_ENGINE_ABI,
            functionName: 'getCurrentFundingRate',
            args: [BigInt(marketId)],
          }),
        ]);
        setPrice(priceData as bigint);
        setMarketData(mktData);
        setFundingRate(funding as bigint);
      } catch (e) {
        console.error('Error fetching market data:', e);
      }
      setIsLoading(false);
    }
    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, [marketId, contracts]);

  const formatPrice = (p: bigint | null) => {
    if (!p) return '—';
    return `${(Number(formatUnits(p, 18)) * 100).toFixed(1)}¢`;
  };

  const formatOI = (oi: bigint | undefined) => {
    if (!oi) return '$0';
    const val = Number(formatUnits(oi, 18));
    if (val >= 1000) return `$${(val / 1000).toFixed(1)}K`;
    return `$${val.toFixed(0)}`;
  };

  const formatFunding = (rate: bigint | null) => {
    if (rate === null) return '0.00%/h';
    const rateNum = Number(rate) / 1e18 * 100;
    const prefix = rateNum >= 0 ? '+' : '';
    return `${prefix}${rateNum.toFixed(4)}%/h`;
  };

  return (
    <div className="px-6 py-6">
      {/* Market Header */}
      <div className="flex items-center gap-4 mb-6">
        <Link href="/" className="text-gray-400 hover:text-white">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </Link>
        <div className="w-10 h-10 rounded-full bg-gray-700 flex items-center justify-center text-xl">
          {market.icon}
        </div>
        <div className="flex-1">
          <h1 className="text-lg font-semibold">{market.question}</h1>
        </div>
      </div>

      {/* Stats Bar - Responsive Grid */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-6 pb-4 border-b border-gray-800">
        <div>
          <span className="text-gray-500 text-sm">Price</span>
          <p className="text-xl font-bold">{isLoading ? '—' : formatPrice(price)}</p>
        </div>
        <div>
          <span className="text-gray-500 text-sm">No Price</span>
          <p className="text-lg font-semibold">{isLoading || !price ? '—' : `${(100 - Number(formatUnits(price, 18)) * 100).toFixed(1)}¢`}</p>
        </div>
        <div>
          <span className="text-gray-500 text-sm">OI (L/S)</span>
          <p className="text-lg font-semibold">
            <span className="text-green-400">{formatOI(marketData?.totalLongOI)}</span>
            {' / '}
            <span className="text-red-400">{formatOI(marketData?.totalShortOI)}</span>
          </p>
        </div>
        <div>
          <span className="text-gray-500 text-sm">Funding Rate</span>
          <p className={`text-lg font-semibold ${fundingRate && fundingRate > 0n ? 'text-green-400' : 'text-red-400'}`}>
            {formatFunding(fundingRate)}
          </p>
        </div>
        <div>
          <span className="text-gray-500 text-sm">Max Leverage</span>
          <p className="text-lg font-semibold">5x</p>
        </div>
        <div>
          <span className="text-gray-500 text-sm">Status</span>
          <p className="text-lg font-semibold text-green-400">Live</p>
        </div>
      </div>

      {/* Main Content - Responsive Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        {/* Chart - Full width on mobile, 7 cols on desktop */}
        <div className="lg:col-span-7">
          <PriceChart marketId={marketId} />
        </div>

        {/* Recent Trades - Hidden on mobile, 2 cols on desktop */}
        <div className="hidden lg:block lg:col-span-2">
          <RecentTrades />
        </div>

        {/* Trading Panel - Full width on mobile, 3 cols on desktop */}
        <div className="lg:col-span-3">
          <TradingPanel marketId={marketId} initialSide={initialSide || undefined} />
        </div>
      </div>
    </div>
  );
}
