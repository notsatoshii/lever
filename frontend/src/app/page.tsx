'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';
import { CONTRACTS, PRICE_ENGINE_ABI, LEDGER_ABI } from '@/config/contracts';
const CATEGORIES = ['All', 'Crypto', 'Politics', 'Finance', 'Sports', 'General'];

interface MarketConfig {
  id: number;
  name: string;
  question: string;
  slug: string;
  category: 'Crypto' | 'Politics' | 'Finance' | 'Sports' | 'General';
  icon: string;
  active: boolean;
}

// 10 Trending Polymarket markets (Updated 2026-02-06)
const LEVER_MARKETS: MarketConfig[] = [
  {
    id: 1,
    name: 'Fed No Change March',
    question: 'Will there be no change in Fed interest rates after the March 2026 meeting?',
    slug: 'will-there-be-no-change-in-fed-interest-rates-after-the-march-2026-meeting',
    category: 'Finance',
    icon: '🏦',
    active: true,
  },
  {
    id: 2,
    name: 'Kevin Warsh Fed Chair',
    question: 'Will Trump nominate Kevin Warsh as the next Fed chair?',
    slug: 'will-trump-nominate-kevin-warsh-as-the-next-fed-chair',
    category: 'Politics',
    icon: '🏛️',
    active: true,
  },
  {
    id: 3,
    name: 'Bitcoin $85K Feb',
    question: 'Will Bitcoin reach $85,000 in February?',
    slug: 'will-bitcoin-reach-85k-in-february-2026',
    category: 'Crypto',
    icon: '₿',
    active: true,
  },
  {
    id: 4,
    name: 'Bitcoin Dip $55K',
    question: 'Will Bitcoin dip to $55,000 in February?',
    slug: 'will-bitcoin-dip-to-55k-in-february-2026',
    category: 'Crypto',
    icon: '📉',
    active: true,
  },
  {
    id: 5,
    name: 'Russia-Ukraine Ceasefire',
    question: 'Russia x Ukraine ceasefire by March 31, 2026?',
    slug: 'russia-x-ukraine-ceasefire-by-march-31-2026',
    category: 'Politics',
    icon: '🕊️',
    active: true,
  },
  {
    id: 6,
    name: 'Seahawks vs Patriots',
    question: 'Seahawks vs. Patriots - Who wins?',
    slug: 'nfl-sea-ne-2026-02-08',
    category: 'Sports',
    icon: '🏈',
    active: true,
  },
  {
    id: 7,
    name: 'Trump Says Kamala',
    question: 'Will Trump say "Kamala" this week? (February 8)',
    slug: 'will-trump-say-kamala-this-week-february-8',
    category: 'Politics',
    icon: '🎤',
    active: true,
  },
  {
    id: 8,
    name: 'Bitcoin Up/Down Feb 6',
    question: 'Bitcoin Up or Down on February 6?',
    slug: 'bitcoin-up-or-down-on-february-6',
    category: 'Crypto',
    icon: '📊',
    active: true,
  },
  {
    id: 9,
    name: 'Hillary 2028 Dem',
    question: 'Will Hillary Clinton win the 2028 Democratic presidential nomination?',
    slug: 'will-hillary-clinton-win-the-2028-democratic-presidential-nomination',
    category: 'Politics',
    icon: '🗳️',
    active: true,
  },
  {
    id: 10,
    name: 'Greg Abbott 2028',
    question: 'Will Greg Abbott win the 2028 US Presidential Election?',
    slug: 'will-greg-abbott-win-the-2028-us-presidential-election',
    category: 'Politics',
    icon: '🇺🇸',
    active: true,
  },
];

interface MarketWithPrice extends MarketConfig {
  yesPrice: number;
  noPrice: number;
  totalOI: number;
  isLive: boolean;
}

// Market card component
function MarketCard({ market }: { market: MarketWithPrice }) {
  const yesPercent = (market.yesPrice * 100).toFixed(0);
  const noPercent = (market.noPrice * 100).toFixed(0);
  
  return (
    <Link 
      href={`/markets/${market.id}?slug=${market.slug}`}
      className="block bg-gray-800 rounded-xl border border-gray-700 p-5 hover:border-gray-600 transition-all"
    >
      <div className="flex items-start gap-3 mb-4">
        <div className="w-10 h-10 rounded-full bg-gray-700 flex items-center justify-center text-lg">
          {market.icon}
        </div>
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
        {market.totalOI > 0 && (
          <div className="ml-auto text-right">
            <span className="text-gray-500 text-xs">Open Interest</span>
            <p className="font-semibold text-sm">
              ${market.totalOI >= 1000 
                ? `${(market.totalOI / 1000).toFixed(1)}K`
                : market.totalOI.toFixed(0)
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

      {/* Category & Status */}
      <div className="mt-3 flex justify-between text-xs text-gray-500">
        <span className="px-2 py-1 bg-gray-700 rounded">{market.category}</span>
        <span className={market.isLive ? 'text-green-400' : 'text-gray-500'}>
          {market.isLive ? '● Live' : '○ Inactive'}
        </span>
      </div>
    </Link>
  );
}

// Create initial markets data
const INITIAL_MARKETS: MarketWithPrice[] = LEVER_MARKETS
  .filter(m => m.active)
  .map(m => ({
    ...m,
    yesPrice: 0.5,
    noPrice: 0.5,
    totalOI: 0,
    isLive: true,
  }));

export default function HomePage() {
  const [markets, setMarkets] = useState<MarketWithPrice[]>(INITIAL_MARKETS);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('All');
  const contracts = CONTRACTS[97];

  // Fetch on-chain prices to update
  useEffect(() => {

    // Then fetch real prices from chain
    async function fetchPrices() {
      try {
        const client = createPublicClient({
          chain: bscTestnet,
          transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
        });

        const updated = await Promise.all(
          INITIAL_MARKETS.map(async (market) => {
            try {
              const [price, marketData] = await Promise.all([
                client.readContract({
                  address: contracts.PRICE_ENGINE as `0x${string}`,
                  abi: PRICE_ENGINE_ABI,
                  functionName: 'getMarkPrice',
                  args: [BigInt(market.id)],
                }),
                client.readContract({
                  address: contracts.LEDGER as `0x${string}`,
                  abi: LEDGER_ABI,
                  functionName: 'getMarket',
                  args: [BigInt(market.id)],
                }),
              ]);
              
              const yesPrice = Number(formatUnits(price as bigint, 18));
              const mkt = marketData as any;
              const totalOI = Number(formatUnits(
                BigInt(mkt.totalLongOI || 0) + BigInt(mkt.totalShortOI || 0), 
                18
              ));
              
              return {
                ...market,
                yesPrice: Math.max(0.01, Math.min(0.99, yesPrice)),
                noPrice: Math.max(0.01, Math.min(0.99, 1 - yesPrice)),
                totalOI,
                isLive: mkt.active ?? true,
              };
            } catch (e) {
              console.error(`Market ${market.id} fetch error:`, e);
              return market; // Keep defaults
            }
          })
        );
        
        setMarkets(updated);
      } catch (e) {
        console.error('Price fetch failed:', e);
      }
    }
    
    fetchPrices();
    const interval = setInterval(fetchPrices, 15000);
    return () => clearInterval(interval);
  }, [contracts]);

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

      {/* Markets grid */}
      <div className="grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
        {filteredMarkets.length > 0 ? (
          filteredMarkets.map((market) => (
            <MarketCard key={market.id} market={market} />
          ))
        ) : (
          <div className="col-span-full text-center py-12 text-gray-500">
            <p>No markets available.</p>
          </div>
        )}
      </div>

      {/* Data source attribution */}
      <div className="mt-8 text-center text-xs text-gray-600">
        Prices from LEVER Protocol • Underlying markets via{' '}
        <a href="https://polymarket.com" target="_blank" rel="noopener noreferrer" className="text-blue-500 hover:underline">
          Polymarket
        </a>
      </div>
    </div>
  );
}
