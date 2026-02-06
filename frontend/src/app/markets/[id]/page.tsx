'use client';

import { useState, useEffect } from 'react';
import { useParams, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';
import { CONTRACTS, PRICE_ENGINE_ABI, LEDGER_ABI, FUNDING_ENGINE_ABI } from '@/config/contracts';
import { TradingPanel } from '@/components/TradingPanel';
import { PriceChart } from '@/components/PriceChart';
import { fetchMarketBySlug, ParsedMarket } from '@/lib/polymarket';

const client = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

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
  const polymarketSlug = searchParams.get('polymarket');
  const initialSide = searchParams.get('side') as 'long' | 'short' | null;
  
  const contracts = CONTRACTS[97];

  // Polymarket data
  const [polymarket, setPolymarket] = useState<ParsedMarket | null>(null);
  
  // On-chain data
  const [price, setPrice] = useState<bigint | null>(null);
  const [marketData, setMarketData] = useState<any>(null);
  const [fundingRate, setFundingRate] = useState<bigint | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Fetch Polymarket data
  useEffect(() => {
    async function fetchPolymarket() {
      if (!polymarketSlug) return;
      try {
        const data = await fetchMarketBySlug(polymarketSlug);
        if (data) setPolymarket(data);
      } catch (e) {
        console.error('Error fetching Polymarket data:', e);
      }
    }
    fetchPolymarket();
    const interval = setInterval(fetchPolymarket, 30000); // Refresh every 30s
    return () => clearInterval(interval);
  }, [polymarketSlug]);

  // Fetch on-chain data
  useEffect(() => {
    async function fetchOnChainData() {
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
        console.error('Error fetching on-chain data:', e);
      }
      setIsLoading(false);
    }
    fetchOnChainData();
    const interval = setInterval(fetchOnChainData, 5000);
    return () => clearInterval(interval);
  }, [marketId, contracts]);

  // Use Polymarket price if available, otherwise on-chain
  const displayPrice = polymarket?.yesPrice ?? (price ? Number(formatUnits(price, 18)) : null);
  const displayNoPrice = polymarket?.noPrice ?? (price ? 1 - Number(formatUnits(price, 18)) : null);

  const formatPrice = (p: number | null) => {
    if (p === null) return '—';
    return `${(p * 100).toFixed(1)}¢`;
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

  const formatVolume = (v: number) => {
    if (v >= 1000000) return `$${(v / 1000000).toFixed(1)}M`;
    if (v >= 1000) return `$${(v / 1000).toFixed(0)}K`;
    return `$${v.toFixed(0)}`;
  };

  // Determine market info
  const marketQuestion = polymarket?.question || `Market #${marketId}`;
  const marketImage = polymarket?.image;

  return (
    <div className="px-4 sm:px-6 py-6">
      {/* Market Header */}
      <div className="flex items-center gap-4 mb-6">
        <Link href="/" className="text-gray-400 hover:text-white">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </Link>
        {marketImage ? (
          <img 
            src={marketImage} 
            alt=""
            className="w-10 h-10 rounded-full object-cover"
            onError={(e) => {
              (e.target as HTMLImageElement).style.display = 'none';
            }}
          />
        ) : (
          <div className="w-10 h-10 rounded-full bg-gray-700 flex items-center justify-center text-xl">
            📊
          </div>
        )}
        <div className="flex-1">
          <h1 className="text-base sm:text-lg font-semibold">{marketQuestion}</h1>
          {polymarket && (
            <p className="text-xs text-gray-500 mt-1">
              Category: {polymarket.category}
              {polymarket.volume > 0 && ` • Volume: ${formatVolume(polymarket.volume)}`}
            </p>
          )}
        </div>
      </div>

      {/* Stats Bar - Responsive Grid */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 sm:gap-4 mb-6 pb-4 border-b border-gray-800">
        <div>
          <span className="text-gray-500 text-xs sm:text-sm">Yes Price</span>
          <p className="text-lg sm:text-xl font-bold text-lever-green">{formatPrice(displayPrice)}</p>
        </div>
        <div>
          <span className="text-gray-500 text-xs sm:text-sm">No Price</span>
          <p className="text-lg sm:text-xl font-bold text-lever-red">{formatPrice(displayNoPrice)}</p>
        </div>
        <div>
          <span className="text-gray-500 text-xs sm:text-sm">OI (L/S)</span>
          <p className="text-sm sm:text-lg font-semibold">
            <span className="text-green-400">{formatOI(marketData?.totalLongOI)}</span>
            {' / '}
            <span className="text-red-400">{formatOI(marketData?.totalShortOI)}</span>
          </p>
        </div>
        <div>
          <span className="text-gray-500 text-xs sm:text-sm">Funding Rate</span>
          <p className={`text-sm sm:text-lg font-semibold ${fundingRate && fundingRate > 0n ? 'text-green-400' : 'text-red-400'}`}>
            {formatFunding(fundingRate)}
          </p>
        </div>
        <div>
          <span className="text-gray-500 text-xs sm:text-sm">Max Leverage</span>
          <p className="text-lg sm:text-xl font-semibold">5x</p>
        </div>
        <div>
          <span className="text-gray-500 text-xs sm:text-sm">Status</span>
          <p className="text-lg sm:text-xl font-semibold text-green-400">Live</p>
        </div>
      </div>

      {/* Polymarket source link */}
      {polymarket && (
        <div className="mb-4 p-3 bg-blue-900/20 border border-blue-700/30 rounded-lg text-sm">
          <span className="text-gray-400">Underlying market: </span>
          <a 
            href={`https://polymarket.com/market/${polymarket.slug}`} 
            target="_blank" 
            rel="noopener noreferrer"
            className="text-blue-400 hover:underline"
          >
            View on Polymarket →
          </a>
        </div>
      )}

      {/* Main Content - Responsive Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        {/* Chart - Full width on mobile, 7 cols on desktop */}
        <div className="lg:col-span-7">
          <PriceChart 
            marketId={marketId} 
            polymarketPrice={displayPrice}
            marketQuestion={polymarket?.question}
          />
        </div>

        {/* Recent Trades - Hidden on mobile, 2 cols on desktop */}
        <div className="hidden lg:block lg:col-span-2">
          <RecentTrades />
        </div>

        {/* Trading Panel - Full width on mobile, 3 cols on desktop */}
        <div className="lg:col-span-3">
          <TradingPanel 
            marketId={marketId} 
            initialSide={initialSide || undefined}
            polymarketPrice={displayPrice}
          />
        </div>
      </div>
    </div>
  );
}
