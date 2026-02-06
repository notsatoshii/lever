'use client';

import { useState, useEffect } from 'react';
import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';
import { CONTRACTS, PRICE_ENGINE_ABI, LEDGER_ABI, FUNDING_ENGINE_ABI } from '@/config/contracts';

const client = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const MARKETS = [
  { id: 0, name: 'Test Market', description: 'Initial test market' },
  { id: 1, name: 'MicroStrategy BTC Sale', description: 'Will MicroStrategy sell Bitcoin?' },
  { id: 2, name: 'Trump Deportations 250-500k', description: 'Trump deports 250k-500k in 2025' },
  { id: 3, name: 'GTA 6 $100+', description: 'Will GTA 6 cost $100 or more?' },
];

interface MarketStatsProps {
  selectedMarket: number;
  onSelectMarket: (id: number) => void;
}

export function MarketStats({ selectedMarket, onSelectMarket }: MarketStatsProps) {
  const contracts = CONTRACTS[97];
  const [markPrice, setMarkPrice] = useState<bigint | null>(null);
  const [market, setMarket] = useState<any>(null);
  const [fundingRate, setFundingRate] = useState<bigint | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    async function fetchData() {
      setIsLoading(true);
      try {
        const [price, mkt, funding] = await Promise.all([
          client.readContract({
            address: contracts.PRICE_ENGINE as `0x${string}`,
            abi: PRICE_ENGINE_ABI,
            functionName: 'getMarkPrice',
            args: [BigInt(selectedMarket)],
          }),
          client.readContract({
            address: contracts.LEDGER as `0x${string}`,
            abi: LEDGER_ABI,
            functionName: 'getMarket',
            args: [BigInt(selectedMarket)],
          }),
          client.readContract({
            address: contracts.FUNDING_ENGINE as `0x${string}`,
            abi: FUNDING_ENGINE_ABI,
            functionName: 'getCurrentFundingRate',
            args: [BigInt(selectedMarket)],
          }),
        ]);
        setMarkPrice(price as bigint);
        setMarket(mkt);
        setFundingRate(funding as bigint);
      } catch (e) {
        console.error('Error fetching market data:', e);
      }
      setIsLoading(false);
    }
    fetchData();
    const interval = setInterval(fetchData, 10000); // Refresh every 10s
    return () => clearInterval(interval);
  }, [selectedMarket, contracts]);

  const formatPrice = (price: bigint | null) => {
    if (!price) return '—';
    return `${(Number(formatUnits(price, 18)) * 100).toFixed(2)}%`;
  };

  const formatOI = (oi: bigint | undefined) => {
    if (!oi) return '0';
    return `${Number(formatUnits(oi, 18)).toLocaleString()}`;
  };

  const formatFunding = (rate: bigint | null) => {
    if (rate === null) return '0.00%/h';
    const rateNum = Number(rate) / 1e18 * 100;
    const prefix = rateNum >= 0 ? '+' : '';
    return `${prefix}${rateNum.toFixed(4)}%/h`;
  };

  const currentMarket = MARKETS.find(m => m.id === selectedMarket) || MARKETS[0];

  return (
    <div className="bg-gray-800 rounded-xl p-6 border border-gray-700">
      {/* Market Selector */}
      <div className="flex flex-wrap gap-2 mb-6">
        {MARKETS.map((m) => (
          <button
            key={m.id}
            onClick={() => onSelectMarket(m.id)}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
              selectedMarket === m.id
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
