'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { fetchPolymarketMarkets, ParsedMarket } from '@/lib/polymarket';

const CATEGORIES = ['All', 'Crypto', 'Politics', 'Finance', 'Sports', 'General'];

// Skeleton loader for market cards
function MarketCardSkeleton() {
  return (
    <div className="bg-gray-800 rounded-xl border border-gray-700 p-5 animate-pulse">
      <div className="flex items-start gap-3 mb-4">
        <div className="w-10 h-10 bg-gray-700 rounded-full" />
        <div className="flex-1 h-12 bg-gray-700 rounded" />
      </div>
      <div className="flex gap-4 mb-3">
        <div className="h-10 w-20 bg-gray-700 rounded" />
        <div className="h-10 w-20 bg-gray-700 rounded" />
      </div>
      <div className="h-12 w-full bg-gray-700 rounded mb-4" />
      <div className="flex gap-2">
        <div className="h-10 flex-1 bg-gray-700 rounded" />
        <div className="h-10 flex-1 bg-gray-700 rounded" />
      </div>
    </div>
  );
}

// Market card component
function MarketCard({ market }: { market: ParsedMarket }) {
  const yesPercent = (market.yesPrice * 100).toFixed(0);
  const noPercent = (market.noPrice * 100).toFixed(0);
  
  return (
    <Link 
      href={`/markets/${market.id}?polymarket=${market.slug}`}
      className="block bg-gray-800 rounded-xl border border-gray-700 p-5 hover:border-gray-600 transition-all"
    >
      <div className="flex items-start gap-3 mb-4">
        {market.image ? (
          <img 
            src={market.image} 
            alt=""
            className="w-10 h-10 rounded-full object-cover"
            onError={(e) => {
              (e.target as HTMLImageElement).style.display = 'none';
            }}
          />
        ) : (
          <div className="w-10 h-10 rounded-full bg-gray-700 flex items-center justify-center text-lg">
            📊
          </div>
        )}
        <h3 className="text-white font-medium text-sm leading-tight flex-1 line-clamp-2">
          {market.question}
        </h3>
      </div>

      {/* Prices */}
      <div className="flex items-center gap-4 mb-4">
        <div>
          <span className="text-gray-500 text-xs">Yes</span>
          <p className="font-bold text-lg text-lever-green">{yesPercent}¢</p>
        </div>
        <div>
          <span className="text-gray-500 text-xs">No</span>
          <p className="font-bold text-lg text-lever-red">{noPercent}¢</p>
        </div>
        {market.volume > 0 && (
          <div className="ml-auto text-right">
            <span className="text-gray-500 text-xs">Volume</span>
            <p className="font-semibold text-sm">
              ${market.volume >= 1000000 
                ? `${(market.volume / 1000000).toFixed(1)}M`
                : market.volume >= 1000
                  ? `${(market.volume / 1000).toFixed(0)}K`
                  : market.volume.toFixed(0)
              }
            </p>
          </div>
        )}
      </div>

      {/* Price bar */}
      <div className="h-2 bg-gray-700 rounded-full overflow-hidden mb-4">
        <div 
          className="h-full bg-lever-green"
          style={{ width: `${market.yesPrice * 100}%` }}
        />
      </div>

      {/* Action buttons */}
      <div className="flex gap-2">
        <span className="flex-1 py-2 text-center rounded-lg border border-lever-green text-lever-green font-medium text-sm">
          LONG
        </span>
        <span className="flex-1 py-2 text-center rounded-lg bg-lever-red text-white font-medium text-sm">
          SHORT
        </span>
      </div>

      {/* Category */}
      <div className="mt-3 flex justify-between text-xs text-gray-500">
        <span className="px-2 py-1 bg-gray-700 rounded">{market.category}</span>
        <span>via Polymarket</span>
      </div>
    </Link>
  );
}

export default function HomePage() {
  const [markets, setMarkets] = useState<ParsedMarket[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('All');

  useEffect(() => {
    async function loadMarkets() {
      try {
        setIsLoading(true);
        const data = await fetchPolymarketMarkets(30);
        setMarkets(data);
        setError(null);
      } catch (e) {
        console.error('Failed to load markets:', e);
        setError('Failed to load markets from Polymarket');
      } finally {
        setIsLoading(false);
      }
    }
    loadMarkets();
    
    // Refresh every 60 seconds
    const interval = setInterval(loadMarkets, 60000);
    return () => clearInterval(interval);
  }, []);

  const filteredMarkets = markets.filter((market) => {
    const matchesSearch = market.question.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesCategory = selectedCategory === 'All' || market.category === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  return (
    <div className="px-4 sm:px-6 py-6">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-white mb-2">Markets</h1>
        <p className="text-gray-400 text-sm">Trade prediction markets with up to 5x leverage</p>
      </div>

      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-3 mb-6">
        <div className="relative flex-1">
          <input
            type="text"
            placeholder="Search markets..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-gray-800 border border-gray-700 rounded-lg pl-10 pr-4 py-2 text-sm focus:outline-none focus:border-blue-500"
          />
          <svg
            className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>
        <select
          value={selectedCategory}
          onChange={(e) => setSelectedCategory(e.target.value)}
          className="bg-gray-800 border border-gray-700 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-blue-500"
        >
          {CATEGORIES.map((cat) => (
            <option key={cat} value={cat}>{cat}</option>
          ))}
        </select>
      </div>

      {/* Error state */}
      {error && (
        <div className="bg-red-900/30 border border-red-700 rounded-lg p-4 mb-6">
          <p className="text-red-400">{error}</p>
          <p className="text-sm text-gray-400 mt-1">Showing cached data or try refreshing.</p>
        </div>
      )}

      {/* Markets grid */}
      <div className="grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
        {isLoading ? (
          // Skeleton loaders
          Array.from({ length: 6 }).map((_, i) => (
            <MarketCardSkeleton key={i} />
          ))
        ) : filteredMarkets.length > 0 ? (
          filteredMarkets.map((market) => (
            <MarketCard key={market.polymarketId} market={market} />
          ))
        ) : (
          <div className="col-span-full text-center py-12 text-gray-500">
            <p>No markets found matching your criteria.</p>
          </div>
        )}
      </div>

      {/* Data source attribution */}
      <div className="mt-8 text-center text-xs text-gray-600">
        Market data from{' '}
        <a href="https://polymarket.com" target="_blank" rel="noopener noreferrer" className="text-blue-500 hover:underline">
          Polymarket
        </a>
        {' '}• LEVER provides leverage, not the underlying markets
      </div>
    </div>
  );
}
