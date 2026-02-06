'use client';

import Link from 'next/link';
import { useState, useEffect, useMemo } from 'react';
import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';
import { CONTRACTS, PRICE_ENGINE_ABI, LEDGER_ABI } from '@/config/contracts';
import { Skeleton } from './Skeleton';

const client = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

interface Market {
  id: number;
  name: string;
  question: string;
  icon?: string;
  category?: string;
}

interface MarketCardProps {
  market: Market;
}

// Simple sparkline component
function Sparkline({ data, color }: { data: number[]; color: string }) {
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  
  const points = data.map((value, i) => {
    const x = (i / (data.length - 1)) * 100;
    const y = 100 - ((value - min) / range) * 100;
    return `${x},${y}`;
  }).join(' ');

  return (
    <svg viewBox="0 0 100 100" className="w-full h-12" preserveAspectRatio="none">
      <polyline
        points={points}
        fill="none"
        stroke={color}
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function MarketCard({ market }: MarketCardProps) {
  const contracts = CONTRACTS[97];
  const [price, setPrice] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Sparkline shows price trending around current value
  const sparklineData = useMemo(() => {
    const basePrice = price || 0.5;
    // Generate a smooth trending line, not random noise
    return Array.from({ length: 20 }, (_, i) => {
      const trend = Math.sin(i / 3) * 0.03;
      return Math.max(0.01, Math.min(0.99, basePrice + trend));
    });
  }, [price]);

  useEffect(() => {
    async function fetchData() {
      try {
        const priceData = await client.readContract({
          address: contracts.PRICE_ENGINE as `0x${string}`,
          abi: PRICE_ENGINE_ABI,
          functionName: 'getMarkPrice',
          args: [BigInt(market.id)],
        });
        
        const priceNum = Number(formatUnits(priceData as bigint, 18));
        setPrice(priceNum);
      } catch (e) {
        console.error('Error fetching market data:', e);
        setPrice(0.5); // Default to 50%
      }
      setIsLoading(false);
    }
    fetchData();
  }, [market.id, contracts]);

  const formatPrice = (p: number | null) => {
    if (p === null) return '—';
    return `${(p * 100).toFixed(0)}¢`;
  };

  // Green for prices above 50%, red for below
  const isYesFavored = (price || 0.5) >= 0.5;
  const sparklineColor = isYesFavored ? '#22c55e' : '#ef4444';

  if (isLoading) {
    return (
      <div className="bg-gray-800 rounded-xl border border-gray-700 p-5">
        <div className="flex items-start gap-3 mb-4">
          <Skeleton className="w-10 h-10 rounded-full" />
          <Skeleton className="h-12 flex-1" />
        </div>
        <div className="flex gap-4 mb-3">
          <Skeleton className="h-10 w-20" />
          <Skeleton className="h-10 w-20" />
          <Skeleton className="h-10 w-20" />
        </div>
        <Skeleton className="h-12 w-full mb-4" />
        <div className="flex gap-2">
          <Skeleton className="h-10 flex-1" />
          <Skeleton className="h-10 flex-1" />
        </div>
      </div>
    );
  }

  return (
    <div className="bg-gray-800 rounded-xl border border-gray-700 p-6 hover:border-gray-600 transition-all duration-200 cursor-pointer group">
      {/* Clickable Header Area */}
      <Link href={`/markets/${market.id}`} className="block">
        <div className="flex items-start gap-3 mb-4">
        <div className="w-10 h-10 rounded-full bg-gray-700 flex items-center justify-center text-lg">
          {market.icon || '📊'}
        </div>
        <h3 className="text-white font-medium text-sm leading-tight flex-1">
          {market.question}
        </h3>
      </div>

      {/* Stats */}
      <div className="flex items-center gap-4 mb-3 text-sm">
        <div>
          <span className="text-gray-500">Yes Price</span>
          <p className="font-semibold text-white text-lg">
            {isLoading ? '—' : formatPrice(price)}
          </p>
        </div>
        <div>
          <span className="text-gray-500">No Price</span>
          <p className="font-semibold text-white text-lg">
            {isLoading || price === null ? '—' : formatPrice(1 - price)}
          </p>
        </div>
      </div>

      {/* Sparkline */}
      <div className="mb-4">
        <Sparkline data={sparklineData} color={sparklineColor} />
      </div>
      </Link>

      {/* Action Buttons */}
      <div className="flex gap-2 mb-3">
        <Link
          href={`/markets/${market.id}?side=long`}
          className="flex-1 py-2 text-center rounded-lg border border-lever-green text-lever-green hover:bg-lever-green/10 font-medium text-sm transition-all duration-200"
        >
          LONG
        </Link>
        <Link
          href={`/markets/${market.id}?side=short`}
          className="flex-1 py-2 text-center rounded-lg bg-lever-red text-white hover:bg-red-600 font-medium text-sm transition-all duration-200"
        >
          SHORT
        </Link>
      </div>

      {/* Category Badge */}
      <div className="flex items-center justify-between text-xs text-gray-500">
        <span className="px-2 py-1 bg-gray-700 rounded text-gray-400">{market.category || 'General'}</span>
        <span className="text-gray-600">Testnet</span>
      </div>
    </div>
  );
}
