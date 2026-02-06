'use client';

import { useReadContracts } from 'wagmi';
import { formatUnits } from 'viem';
import { CONTRACTS, PRICE_ENGINE_ABI, LEDGER_ABI, FUNDING_ENGINE_ABI } from '@/config/contracts';

const MARKET_ID = 0n;

export function MarketStats() {
  const chainId = 97; // BSC Testnet
  const contracts = CONTRACTS[chainId];

  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: contracts.PRICE_ENGINE as `0x${string}`,
        abi: PRICE_ENGINE_ABI,
        functionName: 'getMarkPrice',
        args: [MARKET_ID],
      },
      {
        address: contracts.LEDGER as `0x${string}`,
        abi: LEDGER_ABI,
        functionName: 'getMarket',
        args: [MARKET_ID],
      },
      {
        address: contracts.FUNDING_ENGINE as `0x${string}`,
        abi: FUNDING_ENGINE_ABI,
        functionName: 'getCurrentFundingRate',
        args: [MARKET_ID],
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
    if (!oi) return '—';
    return `${Number(formatUnits(oi, 18)).toLocaleString()}`;
  };

  const formatFunding = (rate: bigint | undefined) => {
    if (!rate) return '—';
    const rateNum = Number(rate) / 1e18 * 100;
    const prefix = rateNum >= 0 ? '+' : '';
    return `${prefix}${rateNum.toFixed(4)}%/h`;
  };

  if (!contracts.PRICE_ENGINE) {
    return (
      <div className="bg-lever-gray rounded-xl p-6 border border-gray-800">
        <p className="text-yellow-500">⚠️ Contracts not configured. Deploy first and add addresses to .env</p>
      </div>
    );
  }

  return (
    <div className="bg-lever-gray rounded-xl p-6 border border-gray-800">
      <h2 className="text-lg font-semibold mb-4">Test Market</h2>
      
      {isLoading ? (
        <div className="animate-pulse space-y-3">
          <div className="h-8 bg-gray-700 rounded w-1/3"></div>
          <div className="h-4 bg-gray-700 rounded w-1/2"></div>
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div>
            <p className="text-gray-400 text-sm">Mark Price</p>
            <p className="text-2xl font-bold text-lever-green">
              {formatPrice(markPrice)}
            </p>
          </div>
          
          <div>
            <p className="text-gray-400 text-sm">Long OI</p>
            <p className="text-xl font-semibold text-green-400">
              {formatOI(market?.totalLongOI)}
            </p>
          </div>
          
          <div>
            <p className="text-gray-400 text-sm">Short OI</p>
            <p className="text-xl font-semibold text-red-400">
              {formatOI(market?.totalShortOI)}
            </p>
          </div>
          
          <div>
            <p className="text-gray-400 text-sm">Funding Rate</p>
            <p className={`text-xl font-semibold ${
              fundingRate && fundingRate > 0n ? 'text-green-400' : 'text-red-400'
            }`}>
              {formatFunding(fundingRate)}
            </p>
            <p className="text-xs text-gray-500">
              {fundingRate && fundingRate > 0n ? 'Longs pay shorts' : 'Shorts pay longs'}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
