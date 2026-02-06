'use client';

import { useState, useEffect } from 'react';
import { useParams, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';
import { CONTRACTS, PRICE_ENGINE_ABI, PRICE_ENGINE_V2_ABI, LEDGER_ABI, FUNDING_ENGINE_ABI } from '@/config/contracts';
import { TradingPanel } from '@/components/TradingPanel';
import { PriceChart } from '@/components/PriceChart';
import { PositionPanel } from '@/components/PositionPanel';
import { getMarketById, getMarketBySlug, MarketConfig } from '@/config/markets';

const client = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

// Recent trades component - fetches from blockchain events
function RecentTrades({ marketId }: { marketId: number }) {
  const [trades, setTrades] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    // TODO: Fetch actual trade events from blockchain/indexer
    // For now, simulate loading and show placeholder
    const fetchTrades = async () => {
      setIsLoading(true);
      try {
        // In production: fetch from subgraph or indexer
        // const response = await fetch(`/api/trades?marketId=${marketId}`);
        // const data = await response.json();
        // setTrades(data);
        
        // Placeholder - no trades yet
        setTrades([]);
      } catch (e) {
        console.error('Failed to fetch trades:', e);
      }
      setIsLoading(false);
    };
    fetchTrades();
    const interval = setInterval(fetchTrades, 30000);
    return () => clearInterval(interval);
  }, [marketId]);

  return (
    <div className="bg-gray-800 rounded-xl border border-gray-700">
      <div className="p-4 border-b border-gray-700 flex justify-between items-center">
        <h3 className="font-semibold">Recent Trades</h3>
        <span className="text-xs text-gray-500">Market #{marketId}</span>
      </div>
      
      {isLoading ? (
        <div className="p-4 space-y-2">
          {[1,2,3].map(i => (
            <div key={i} className="animate-pulse flex justify-between">
              <div className="h-4 bg-gray-700 rounded w-1/4"></div>
              <div className="h-4 bg-gray-700 rounded w-1/4"></div>
              <div className="h-4 bg-gray-700 rounded w-1/4"></div>
            </div>
          ))}
        </div>
      ) : trades.length === 0 ? (
        <div className="p-6 text-center text-gray-500">
          <svg className="w-8 h-8 mx-auto mb-2 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
          </svg>
          <p className="text-sm">No trades yet</p>
          <p className="text-xs text-gray-600 mt-1">Be the first to trade!</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-gray-500 text-xs border-b border-gray-700">
              <tr>
                <th className="text-left p-3">Time</th>
                <th className="text-left p-3">Side</th>
                <th className="text-right p-3">Size</th>
                <th className="text-right p-3">Price</th>
                <th className="text-right p-3">TX</th>
              </tr>
            </thead>
            <tbody>
              {trades.map((trade, i) => (
                <tr key={i} className="border-b border-gray-700/50 hover:bg-gray-700/30">
                  <td className="p-3 text-gray-400">{trade.time}</td>
                  <td className={`p-3 font-medium ${trade.side === 'LONG' ? 'text-lever-green' : 'text-lever-red'}`}>
                    {trade.side}
                  </td>
                  <td className="p-3 text-right">{trade.size}</td>
                  <td className="p-3 text-right">{trade.price}</td>
                  <td className="p-3 text-right">
                    <a href={`https://testnet.bscscan.com/tx/${trade.txHash}`} 
                       target="_blank" 
                       rel="noopener noreferrer"
                       className="text-blue-400 hover:underline font-mono">
                      {trade.txHash?.slice(0, 8)}...
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

export default function MarketPage() {
  const params = useParams();
  const searchParams = useSearchParams();
  const marketId = Number(params.id) ?? 0; // Default to market 0
  const polymarketSlug = searchParams.get('polymarket');
  const initialSide = searchParams.get('side') as 'long' | 'short' | null;
  
  const contracts = CONTRACTS[97];

  // Get market config from our config
  const marketConfig = getMarketById(marketId) || getMarketBySlug(polymarketSlug || '');
  
  // On-chain data
  const [livePrice, setLivePrice] = useState<bigint | null>(null);  // From old PriceEngine (execution)
  const [markPrice, setMarkPrice] = useState<bigint | null>(null);  // From PriceEngineV2 (PI - smoothed)
  const [marketExpiry, setMarketExpiry] = useState<bigint | null>(null);
  const [marketData, setMarketData] = useState<any>(null);
  const [fundingRate, setFundingRate] = useState<bigint | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Fetch on-chain data
  useEffect(() => {
    async function fetchOnChainData() {
      try {
        const [livePriceData, mktData, funding] = await Promise.all([
          // LIVE price from old PriceEngine (used for execution/chart)
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
        setLivePrice(livePriceData as bigint);
        setMarketData(mktData);
        setFundingRate(funding as bigint);
        
        // Fetch Mark Price (PI) and expiry from PriceEngineV2
        if (contracts.PRICE_ENGINE) {
          try {
            const [markPriceData, configData] = await Promise.all([
              client.readContract({
                address: contracts.PRICE_ENGINE as `0x${string}`,
                abi: PRICE_ENGINE_V2_ABI,
                functionName: 'getMarkPrice',
                args: [BigInt(marketId)],
              }),
              client.readContract({
                address: contracts.PRICE_ENGINE as `0x${string}`,
                abi: PRICE_ENGINE_V2_ABI,
                functionName: 'getMarketConfig',
                args: [BigInt(marketId)],
              }),
            ]);
            setMarkPrice(markPriceData as bigint);
            // configData[0] is expiryTimestamp
            const config = configData as readonly [bigint, bigint, bigint, bigint, bigint, boolean];
            setMarketExpiry(config[0]);
          } catch (e) {
            // PriceEngineV2 might not have this market configured yet
            setMarkPrice(livePriceData as bigint); // Fallback to live price
          }
        }
      } catch (e) {
        console.error('Error fetching on-chain data:', e);
      }
      setIsLoading(false);
    }
    fetchOnChainData();
    const interval = setInterval(fetchOnChainData, 5000);
    return () => clearInterval(interval);
  }, [marketId, contracts]);

  // Dual prices: LIVE (for chart/execution) and MARK (for PnL/liquidations)
  const livePriceNum = livePrice !== null ? Number(formatUnits(livePrice, 18)) : 0.5;
  const markPriceNum = markPrice !== null ? Number(formatUnits(markPrice, 18)) : livePriceNum;
  const displayPrice = livePriceNum;  // Chart shows LIVE
  const displayNoPrice = 1 - livePriceNum;
  
  // Format expiry
  const formatExpiry = (timestamp: bigint | null) => {
    if (!timestamp || timestamp === 0n) return null;
    const date = new Date(Number(timestamp) * 1000);
    const now = new Date();
    const diffMs = date.getTime() - now.getTime();
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
    return {
      date: date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }),
      daysLeft: diffDays,
    };
  };
  const expiry = formatExpiry(marketExpiry);

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

  // Determine market info from config
  const marketQuestion = marketConfig?.question || `Market #${marketId}`;
  const marketIcon = marketConfig?.icon || '📊';
  const marketCategory = marketConfig?.category || 'General';

  return (
    <div className="px-4 sm:px-6 py-6">
      {/* Market Header */}
      <div className="flex items-center gap-4 mb-6">
        <Link href="/" className="text-gray-400 hover:text-white">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </Link>
        <div className="w-10 h-10 rounded-full bg-gray-700 flex items-center justify-center text-xl">
          {marketIcon}
        </div>
        <div className="flex-1">
          <h1 className="text-base sm:text-lg font-semibold">{marketQuestion}</h1>
          <p className="text-xs text-gray-500 mt-1">
            Category: {marketCategory} • Market ID: {marketId}
            {expiry && (
              <span className="ml-2">
                • Expires: {expiry.date} ({expiry.daysLeft} days)
              </span>
            )}
          </p>
        </div>
      </div>

      {/* Dual Price Display */}
      <div className="grid grid-cols-2 gap-4 mb-4 p-4 bg-gray-800/50 rounded-xl border border-gray-700">
        <div>
          <span className="text-gray-500 text-xs">LIVE (Polymarket)</span>
          <p className="text-2xl font-bold text-lever-green">{(livePriceNum * 100).toFixed(2)}%</p>
          <span className="text-xs text-gray-600">Execution price</span>
        </div>
        <div>
          <span className="text-gray-500 text-xs">MARK PRICE (PI)</span>
          <p className="text-2xl font-bold text-blue-400">{(markPriceNum * 100).toFixed(2)}%</p>
          <span className="text-xs text-gray-600">Used for PnL & liquidations</span>
        </div>
      </div>
      
      {/* Stats Bar - Responsive Grid */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3 sm:gap-4 mb-6 pb-4 border-b border-gray-800">
        <div>
          <span className="text-gray-500 text-xs sm:text-sm">Yes / No</span>
          <p className="text-sm sm:text-lg font-semibold">
            <span className="text-lever-green">{formatPrice(displayPrice)}</span>
            {' / '}
            <span className="text-lever-red">{formatPrice(displayNoPrice)}</span>
          </p>
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
      {marketConfig?.slug && (
        <div className="mb-4 p-3 bg-blue-900/20 border border-blue-700/30 rounded-lg text-sm">
          <span className="text-gray-400">Underlying market: </span>
          <a 
            href={`https://polymarket.com/event/${marketConfig.slug}`} 
            target="_blank" 
            rel="noopener noreferrer"
            className="text-blue-400 hover:underline"
          >
            View on Polymarket →
          </a>
        </div>
      )}

      {/* Main Content - Vertical Stack Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        
        {/* Left side: Chart + Recent Trades + Positions (stacked) */}
        <div className="lg:col-span-9 space-y-4">
          {/* Chart - Full width */}
          <PriceChart 
            marketId={marketId} 
            polymarketPrice={displayPrice}
            marketQuestion={marketConfig?.question}
          />
          
          {/* Recent Trades (below chart) */}
          <RecentTrades marketId={marketId} />
          
          {/* Positions List (below trades) */}
          <PositionPanel marketId={marketId} />
        </div>

        {/* Right side: Trading Panel */}
        <div className="lg:col-span-3">
          <div className="sticky top-4">
            <TradingPanel 
              marketId={marketId} 
              initialSide={initialSide || undefined}
              polymarketPrice={displayPrice}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
