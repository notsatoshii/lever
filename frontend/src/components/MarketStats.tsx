'use client';

import { useState } from 'react';
import { useReadContracts } from 'wagmi';
import { formatUnits } from 'viem';
import { CONTRACTS, PRICE_ENGINE_ABI, LEDGER_ABI, FUNDING_ENGINE_ABI } from '@/config/contracts';

// Market definitions - from Polymarket
const MARKETS = [
  { id: 0n, name: 'Test Market', description: 'Initial test market' },
  { id: 1n, name: 'MicroStrategy BTC Sale', description: 'Will MicroStrategy sell Bitcoin?' },
  { id: 2n, name: 'Trump Deportations 250-500k', description: 'Trump deports 250k-500k in 2025' },
  { id: 3n, name: 'GTA 6 $100+', description: 'Will GTA 6 cost $100 or more?' },
];

interface MarketStatsProps {
  selectedMarket: number;
  onSelectMarket: (id: number) => void;
}

export function MarketStats({ selectedMarket, onSelectMarket }: MarketStatsProps) {
  const chainId = 97;
  const contracts = CONTRACTS[chainId];
  const marketId = BigInt(selectedMarket);

  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: contracts.PRICE_ENGINE as `0x${string}`,
        abi: PRICE_ENGINE_ABI,
        functionName: 'getMarkPrice',
        args: [marketId],
      },
      {
        address: contracts.LEDGER as `0x${string}`,
        abi: LEDGER_ABI,
        functionName: 'getMarket',
        args: [marketId],
      },
      {
        address: contracts.FUNDING_ENGINE as `0x${string}`,
        abi: FUNDING_ENGINE_ABI,
        functionName: 'getCurrentFundingRate',
        args: [marketId],
      },
    ],
  });

  const markPrice = data?.[0]?.result as bigint | undefined;
  const market = data?.[1]?.result as any;
  const fundingRate = data?.[2]?.result as bigint | undefined;

  const formatPrice = (price: bigint | undefined) => {
    if (!price) return '—';
    return `${(Number(formatUnits(price, 18)) * 100).toFixed(2)}%`;
  };

  const formatOI = (oi: bigint | undefined) => {
    if (!oi) return '0';
    return `${Number(formatUnits(oi, 18)).toLocaleString()}`;
  };

  const formatFunding = (rate: bigint | undefined) => {
    if (!rate) return '0.00%/h';
    const rateNum = Number(rate) / 1e18 * 100;
    const prefix = rateNum >= 0 ? '+' : '';
    return `${prefix}${rateNum.toFixed(4)}%/h`;
  };

  const currentMarket = MARKETS.find(m => Number(m.id) === selectedMarket) || MARKETS[0];

  if (!contracts.PRICE_ENGINE) {
    return (
      <div className="bg-gray-800 rounded-xl p-6 border border-gray-700">
        <p className="text-yellow-500">⚠️ Contracts not configured</p>
      </div>
    );
  }

  return (
    <div className="bg-gray-800 rounded-xl p-6 border border-gray-700">
      {/* Market Selector */}
      <div className="flex flex-wrap gap-2 mb-6">
        {MARKETS.map((m) => (
          <button
            key={Number(m.id)}
            onClick={() => onSelectMarket(Number(m.id))}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
              selectedMarket === Number(m.id)
                ? 'bg-green-600 text-white'
                : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
            }`}
          >
            {m.name}
          </button>
        ))}
      </div>

      {/* Market Info */}
      <div className="mb-4">
        <h2 className="text-xl font-bold">{currentMarket.name}</h2>
        <p className="text-gray-400 text-sm">{currentMarket.description}</p>
      </div>
      
      {isLoading ? (
        <div className="animate-pulse space-y-3">
          <div className="h-8 bg-gray-700 rounded w-1/3"></div>
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div>
            <p className="text-gray-400 text-sm">Mark Price</p>
            <p className="text-2xl font-bold text-green-500">
              {formatPrice(markPrice)}
            </p>
          </div>
          
          <div>
            <p className="text-gray-400 text-sm">Long OI</p>
            <p className="text-xl font-semibold text-green-400">
              {formatOI(market?.totalLongOI)} USDT
            </p>
          </div>
          
          <div>
            <p className="text-gray-400 text-sm">Short OI</p>
            <p className="text-xl font-semibold text-red-400">
              {formatOI(market?.totalShortOI)} USDT
            </p>
          </div>
          
          <div>
            <p className="text-gray-400 text-sm">Funding Rate</p>
            <p className={`text-xl font-semibold ${
              fundingRate && fundingRate > 0n ? 'text-green-400' : 'text-red-400'
            }`}>
              {formatFunding(fundingRate)}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
