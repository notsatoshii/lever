'use client';

import { useState } from 'react';
import { MarketCard } from '@/components/MarketCard';

// Mock markets data - in production would come from contract/API
const MARKETS = [
  { 
    id: 1, 
    name: 'MicroStrategy BTC Sale', 
    question: 'Will MicroStrategy sell Bitcoin before end of 2025?',
    icon: '🪙',
    category: 'Crypto'
  },
  { 
    id: 2, 
    name: 'Trump Deportations', 
    question: 'Trump deports 250k-500k people in 2025?',
    icon: '🇺🇸',
    category: 'Politics'
  },
  { 
    id: 3, 
    name: 'GTA 6 Price', 
    question: 'Will GTA 6 cost $100 or more at launch?',
    icon: '🎮',
    category: 'Gaming'
  },
  { 
    id: 4, 
    name: 'Fed Rate Cut', 
    question: 'Will the Fed decrease interest rates by 25 bps after the March 2026 meeting?',
    icon: '🏦',
    category: 'Finance'
  },
  { 
    id: 5, 
    name: 'Arsenal Premier League', 
    question: 'Will Arsenal win the 2025-26 English Premier League?',
    icon: '⚽',
    category: 'Sports'
  },
  { 
    id: 6, 
    name: 'ETH Price', 
    question: 'Will ETH exceed $10,000 in 2025?',
    icon: '💎',
    category: 'Crypto'
  },
];

const CATEGORIES = ['All', 'Crypto', 'Politics', 'Gaming', 'Finance', 'Sports'];

export default function HomePage() {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('All');
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');

  const filteredMarkets = MARKETS.filter((market) => {
    const matchesSearch = market.question.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         market.name.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesCategory = selectedCategory === 'All' || market.category === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  return (
    <div className="px-4 sm:px-6 py-6">
      {/* Page Header - Responsive */}
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-white mb-4">Markets</h1>
        
        <div className="flex flex-col sm:flex-row gap-3">
          {/* Search - Full width on mobile */}
          <div className="relative flex-1">
            <input
              type="text"
              placeholder="Search markets"
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

          {/* Category Filter */}
          <select
            value={selectedCategory}
            onChange={(e) => setSelectedCategory(e.target.value)}
            className="bg-gray-800 border border-gray-700 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-blue-500"
          >
            {CATEGORIES.map((cat) => (
              <option key={cat} value={cat}>{cat}</option>
            ))}
          </select>

          {/* View Toggle - Hide on mobile */}
          <div className="hidden sm:flex items-center bg-gray-800 rounded-lg p-1">
            <button
              onClick={() => setViewMode('grid')}
              className={`p-1.5 rounded ${viewMode === 'grid' ? 'bg-gray-700' : ''}`}
              aria-label="Grid view"
            >
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path d="M5 3a2 2 0 00-2 2v2a2 2 0 002 2h2a2 2 0 002-2V5a2 2 0 00-2-2H5zM5 11a2 2 0 00-2 2v2a2 2 0 002 2h2a2 2 0 002-2v-2a2 2 0 00-2-2H5zM11 5a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V5zM11 13a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
              </svg>
            </button>
            <button
              onClick={() => setViewMode('list')}
              className={`p-1.5 rounded ${viewMode === 'list' ? 'bg-gray-700' : ''}`}
              aria-label="List view"
            >
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M3 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z" clipRule="evenodd" />
              </svg>
            </button>
          </div>
        </div>
      </div>

      {/* Markets Grid */}
      <div className={`grid gap-4 ${viewMode === 'grid' ? 'grid-cols-1 md:grid-cols-2 lg:grid-cols-3' : 'grid-cols-1'}`}>
        {filteredMarkets.map((market) => (
          <MarketCard key={market.id} market={market} />
        ))}
      </div>

      {filteredMarkets.length === 0 && (
        <div className="text-center py-12 text-gray-500">
          No markets found matching your criteria.
        </div>
      )}
    </div>
  );
}
