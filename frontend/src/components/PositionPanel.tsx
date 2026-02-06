'use client';

import { useAccount, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatUnits } from 'viem';
import { CONTRACTS, LEDGER_ABI, PRICE_ENGINE_ABI, ROUTER_ABI } from '@/config/contracts';

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
  const { isLoading: isClosing } = useWaitForTransactionReceipt({ 
    hash: closeHash,
    onSuccess: () => refetch(),
  });

  const handleClose = () => {
    if (!position?.size) return;
    
    const sizeDelta = -position.size; // Close entire position
    closePosition({
      address: contracts.ROUTER as `0x${string}`,
      abi: ROUTER_ABI,
      functionName: 'closePosition',
      args: [MARKET_ID, sizeDelta, 0n, BigInt(1e18)],
    });
  };

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
      ? 'text-green-400' 
      : 'text-red-400';

  if (!contracts.LEDGER) {
    return null;
  }

  return (
    <div className="bg-lever-gray rounded-xl p-6 border border-gray-800">
      <h2 className="text-lg font-semibold mb-4">Your Position</h2>

      {isLoading ? (
        <div className="animate-pulse space-y-3">
          <div className="h-6 bg-gray-700 rounded w-1/2"></div>
          <div className="h-4 bg-gray-700 rounded w-2/3"></div>
        </div>
      ) : !hasPosition ? (
        <div className="text-center py-8 text-gray-500">
          <p>No open position</p>
          <p className="text-sm mt-1">Open a trade to get started</p>
        </div>
      ) : (
        <div className="space-y-4">
          {/* Position Header */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className={`px-2 py-1 rounded text-sm font-semibold ${
                isLong ? 'bg-green-600/20 text-green-400' : 'bg-red-600/20 text-red-400'
              }`}>
                {isLong ? 'LONG' : 'SHORT'}
              </span>
              <span className="text-xl font-bold">
                {Number(formatUnits(absSize, 18)).toLocaleString()} units
              </span>
            </div>
            <div className={`text-xl font-bold ${pnlColor}`}>
              {formatPnL(unrealizedPnL)}
            </div>
          </div>

          {/* Position Details */}
          <div className="grid grid-cols-2 gap-4 bg-gray-800 rounded-lg p-4">
            <div>
              <p className="text-gray-400 text-sm">Entry Price</p>
              <p className="font-semibold">{formatPrice(position?.entryPrice)}</p>
            </div>
            <div>
              <p className="text-gray-400 text-sm">Mark Price</p>
              <p className="font-semibold">{formatPrice(markPrice)}</p>
            </div>
            <div>
              <p className="text-gray-400 text-sm">Collateral</p>
              <p className="font-semibold">
                {position?.collateral 
                  ? `${Number(formatUnits(position.collateral, 18)).toLocaleString()} USDT`
                  : '—'
                }
              </p>
            </div>
            <div>
              <p className="text-gray-400 text-sm">Leverage</p>
              <p className="font-semibold">
                {position?.collateral && position.collateral > 0n
                  ? `${(Number(formatUnits(absSize, 18)) * Number(formatUnits(markPrice || 0n, 18)) / Number(formatUnits(position.collateral, 18))).toFixed(1)}x`
                  : '—'
                }
              </p>
            </div>
          </div>

          {/* PnL Bar */}
          {unrealizedPnL !== undefined && position?.collateral && (
            <div>
              <div className="flex justify-between text-sm mb-1">
                <span className="text-gray-400">ROI</span>
                <span className={pnlColor}>
                  {((Number(unrealizedPnL) / Number(position.collateral)) * 100).toFixed(2)}%
                </span>
              </div>
              <div className="h-2 bg-gray-700 rounded-full overflow-hidden">
                <div 
                  className={`h-full ${unrealizedPnL >= 0n ? 'bg-green-500' : 'bg-red-500'}`}
                  style={{ 
                    width: `${Math.min(100, Math.abs(Number(unrealizedPnL) / Number(position.collateral) * 100))}%`
                  }}
                />
              </div>
            </div>
          )}

          {/* Close Button */}
          <button
            onClick={handleClose}
            disabled={isClosing}
            className="w-full py-3 rounded-lg font-semibold bg-gray-700 hover:bg-gray-600 disabled:opacity-50"
          >
            {isClosing ? 'Closing...' : 'Close Position'}
          </button>
        </div>
      )}
    </div>
  );
}
