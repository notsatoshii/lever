'use client';

import { useState, useEffect } from 'react';
import { useAccount, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatUnits } from 'viem';
import { CONTRACTS, LEDGER_ABI, PRICE_ENGINE_ABI, ROUTER_ABI } from '@/config/contracts';
import { ensureFreshPrice } from '@/lib/priceUpdater';

interface PositionPanelProps {
  marketId: number;
}

export function PositionPanel({ marketId }: PositionPanelProps) {
  const MARKET_ID = BigInt(marketId);
  const { address } = useAccount();
  const chainId = 97;
  const contracts = CONTRACTS[chainId];

  const { data, isLoading, refetch } = useReadContracts({
    contracts: [
      {
        address: contracts.LEDGER as `0x${string}`,
        abi: LEDGER_ABI,
        functionName: 'getPosition',
        args: [address!, MARKET_ID],
      },
      {
        address: contracts.PRICE_ENGINE as `0x${string}`,
        abi: PRICE_ENGINE_ABI,
        functionName: 'getMarkPrice',
        args: [MARKET_ID],
      },
    ],
  });

  const position = data?.[0]?.result as any;
  const markPrice = data?.[1]?.result as bigint | undefined;

  // Calculate unrealized PnL
  const { data: pnlData } = useReadContracts({
    contracts: position?.size && position.size !== 0n ? [
      {
        address: contracts.LEDGER as `0x${string}`,
        abi: LEDGER_ABI,
        functionName: 'getUnrealizedPnL',
        args: [address!, MARKET_ID, markPrice!],
      },
    ] : [],
  });

  const unrealizedPnL = pnlData?.[0]?.result as bigint | undefined;

  // Close position
  const { writeContract: closePosition, data: closeHash } = useWriteContract();
  const { isLoading: isClosing, isSuccess: closeSuccess } = useWaitForTransactionReceipt({ 
    hash: closeHash,
  });

  // Refetch on successful close
  useEffect(() => {
    if (closeSuccess) {
      refetch();
    }
  }, [closeSuccess, refetch]);

  const [isUpdatingPrice, setIsUpdatingPrice] = useState(false);
  const [lastTxHash, setLastTxHash] = useState<string | null>(null);

  const handleClose = async () => {
    if (!position?.size) return;
    
    try {
      setIsUpdatingPrice(true);
      console.log('Ensuring fresh price for market', marketId);
      await ensureFreshPrice(marketId);
      setIsUpdatingPrice(false);
    } catch (e) {
      console.error('Failed to update price:', e);
      setIsUpdatingPrice(false);
      return;
    }

    const closePercent = BigInt(1e18);
    const minAmountOut = 0n;
    
    closePosition({
      address: contracts.ROUTER as `0x${string}`,
      abi: ROUTER_ABI,
      functionName: 'closePosition',
      args: [MARKET_ID, closePercent, minAmountOut],
    });
  };

  // Track TX hash
  useEffect(() => {
    if (closeHash) {
      setLastTxHash(closeHash);
    }
  }, [closeHash]);

  const hasPosition = position?.size && position.size !== 0n;
  const isLong = position?.size > 0n;
  const absSize = hasPosition ? (isLong ? position.size : -position.size) : 0n;

  const formatPrice = (price: bigint | undefined) => {
    if (!price) return '—';
    return `${(Number(formatUnits(price, 18)) * 100).toFixed(2)}%`;
  };

  const formatPnL = (pnl: bigint | undefined) => {
    if (pnl === undefined) return '—';
    const value = Number(formatUnits(pnl, 18));
    const prefix = value >= 0 ? '+' : '';
    return `${prefix}${value.toFixed(2)} USDT`;
  };

  const pnlColor = unrealizedPnL === undefined 
    ? 'text-gray-400' 
    : unrealizedPnL >= 0n 
      ? 'text-lever-green' 
      : 'text-lever-red';

  if (!contracts.LEDGER) {
    return null;
  }

  return (
    <div className="bg-gray-800 rounded-xl border border-gray-700">
      <div className="p-4 border-b border-gray-700 flex justify-between items-center">
        <h3 className="font-semibold">Your Positions</h3>
        <span className="text-xs text-gray-500">Market #{marketId}</span>
      </div>

      {isLoading ? (
        <div className="p-4 space-y-2">
          <div className="animate-pulse flex justify-between">
            <div className="h-4 bg-gray-700 rounded w-1/4"></div>
            <div className="h-4 bg-gray-700 rounded w-1/4"></div>
          </div>
        </div>
      ) : !hasPosition ? (
        <div className="p-6 text-center text-gray-500">
          <svg className="w-8 h-8 mx-auto mb-2 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
          </svg>
          <p className="text-sm">No open positions</p>
          <p className="text-xs text-gray-600 mt-1">Open a trade to get started</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          {/* Position as list/table row */}
          <table className="w-full text-sm">
            <thead className="text-gray-500 text-xs border-b border-gray-700">
              <tr>
                <th className="text-left p-3">Side</th>
                <th className="text-right p-3">Size</th>
                <th className="text-right p-3">Entry</th>
                <th className="text-right p-3">PnL</th>
                <th className="text-right p-3">Action</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-gray-700/50">
                <td className="p-3">
                  <span className={`px-2 py-1 rounded text-xs font-semibold ${
                    isLong ? 'bg-lever-green/20 text-lever-green' : 'bg-lever-red/20 text-lever-red'
                  }`}>
                    {isLong ? 'LONG' : 'SHORT'}
                  </span>
                </td>
                <td className="p-3 text-right font-mono">
                  {Number(formatUnits(absSize, 18)).toFixed(2)}
                </td>
                <td className="p-3 text-right">
                  {formatPrice(position?.entryPrice)}
                </td>
                <td className={`p-3 text-right font-semibold ${pnlColor}`}>
                  {formatPnL(unrealizedPnL)}
                </td>
                <td className="p-3 text-right">
                  <button
                    onClick={handleClose}
                    disabled={isClosing || isUpdatingPrice}
                    className="px-3 py-1.5 rounded text-xs font-semibold bg-red-600 hover:bg-red-500 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    {isUpdatingPrice ? '...' : isClosing ? 'Closing' : 'Close'}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          
          {/* Position details below */}
          <div className="p-4 border-t border-gray-700/50 grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
            <div>
              <span className="text-gray-500">Mark Price</span>
              <p className="font-medium">{formatPrice(markPrice)}</p>
            </div>
            <div>
              <span className="text-gray-500">Collateral</span>
              <p className="font-medium">
                {position?.collateral 
                  ? `${Number(formatUnits(position.collateral, 18)).toFixed(2)} USDT`
                  : '—'
                }
              </p>
            </div>
            <div>
              <span className="text-gray-500">Leverage</span>
              <p className="font-medium">
                {position?.collateral && position.collateral > 0n && markPrice
                  ? `${(Number(formatUnits(absSize, 18)) * Number(formatUnits(markPrice, 18)) / Number(formatUnits(position.collateral, 18))).toFixed(1)}x`
                  : '—'
                }
              </p>
            </div>
            <div>
              <span className="text-gray-500">ROI</span>
              <p className={`font-medium ${pnlColor}`}>
                {unrealizedPnL !== undefined && position?.collateral && position.collateral > 0n
                  ? `${((Number(unrealizedPnL) / Number(position.collateral)) * 100).toFixed(2)}%`
                  : '—'
                }
              </p>
            </div>
          </div>
          
          {/* Show last TX hash if available */}
          {lastTxHash && (
            <div className="px-4 pb-4">
              <div className="p-2 bg-gray-700/50 rounded text-xs">
                <span className="text-gray-500">Last TX: </span>
                <a 
                  href={`https://testnet.bscscan.com/tx/${lastTxHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 hover:underline font-mono"
                >
                  {lastTxHash.slice(0, 10)}...{lastTxHash.slice(-8)}
                </a>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
