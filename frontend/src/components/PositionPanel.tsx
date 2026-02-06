'use client';

import { useState, useEffect } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatUnits } from 'viem';
import { CONTRACTS, LEDGER_ABI, PRICE_ENGINE_ABI, ROUTER_ABI } from '@/config/contracts';
import { ensureFreshPrice } from '@/lib/priceUpdater';

interface PositionPanelProps {
  marketId: number;
}

interface Position {
  id: bigint;
  owner: string;
  marketId: bigint;
  side: number; // 0 = Long, 1 = Short
  size: bigint;
  entryPrice: bigint;
  collateral: bigint;
  openTimestamp: bigint;
  isOpen: boolean;
}

export function PositionPanel({ marketId }: PositionPanelProps) {
  const MARKET_ID = BigInt(marketId);
  const { address } = useAccount();
  const chainId = 97;
  const contracts = CONTRACTS[chainId];

  const [lastTxHash, setLastTxHash] = useState<string | null>(null);
  const [isUpdatingPrice, setIsUpdatingPrice] = useState(false);
  const [closingPositionId, setClosingPositionId] = useState<bigint | null>(null);

  // Get position IDs for this user in this market
  const { data: positionIds, isLoading: loadingIds, refetch: refetchIds } = useReadContract({
    address: contracts.LEDGER as `0x${string}`,
    abi: LEDGER_ABI,
    functionName: 'getUserMarketPositionIds',
    args: address ? [address, MARKET_ID] : undefined,
  });

  // Get all user's open positions
  const { data: allPositions, isLoading: loadingPositions, refetch: refetchPositions } = useReadContract({
    address: contracts.LEDGER as `0x${string}`,
    abi: LEDGER_ABI,
    functionName: 'getUserOpenPositions',
    args: address ? [address] : undefined,
  });

  // Filter positions for this market
  const marketPositions = (allPositions as Position[] | undefined)?.filter(
    (p) => p.marketId === MARKET_ID && p.isOpen
  ) || [];

  // Get mark price for this market
  const { data: markPrice } = useReadContract({
    address: contracts.PRICE_ENGINE as `0x${string}`,
    abi: PRICE_ENGINE_ABI,
    functionName: 'getMarkPrice',
    args: [MARKET_ID],
  });

  // Close position
  const { writeContract: closePosition, data: closeHash } = useWriteContract();
  const { isLoading: isClosing, isSuccess: closeSuccess } = useWaitForTransactionReceipt({ 
    hash: closeHash,
  });

  // Refetch on successful close
  useEffect(() => {
    if (closeSuccess) {
      refetchIds();
      refetchPositions();
      setClosingPositionId(null);
    }
  }, [closeSuccess, refetchIds, refetchPositions]);

  // Track TX hash
  useEffect(() => {
    if (closeHash) {
      setLastTxHash(closeHash);
    }
  }, [closeHash]);

  const handleClose = async (positionId: bigint) => {
    try {
      setClosingPositionId(positionId);
      setIsUpdatingPrice(true);
      await ensureFreshPrice(marketId);
      setIsUpdatingPrice(false);
    } catch (e) {
      console.error('Failed to update price:', e);
      setIsUpdatingPrice(false);
      setClosingPositionId(null);
      return;
    }

    closePosition({
      address: contracts.ROUTER as `0x${string}`,
      abi: ROUTER_ABI,
      functionName: 'closePosition',
      args: [positionId, 0n], // positionId, minAmountOut
    });
  };

  const calculatePnL = (position: Position): bigint => {
    if (!markPrice) return 0n;
    const mp = markPrice as bigint;
    if (position.side === 0) {
      // Long: PnL = size * (markPrice - entryPrice) / 1e18
      return (position.size * (mp - position.entryPrice)) / BigInt(1e18);
    } else {
      // Short: PnL = size * (entryPrice - markPrice) / 1e18
      return (position.size * (position.entryPrice - mp)) / BigInt(1e18);
    }
  };

  if (!address) {
    return (
      <div className="bg-gray-800 rounded-xl border border-gray-700 p-4">
        <h3 className="font-semibold mb-2">Your Positions</h3>
        <p className="text-gray-500 text-sm">Connect wallet to view positions</p>
      </div>
    );
  }

  if (loadingIds || loadingPositions) {
    return (
      <div className="bg-gray-800 rounded-xl border border-gray-700 p-4">
        <h3 className="font-semibold mb-2">Your Positions</h3>
        <div className="animate-pulse space-y-2">
          <div className="h-4 bg-gray-700 rounded w-3/4"></div>
          <div className="h-4 bg-gray-700 rounded w-1/2"></div>
        </div>
      </div>
    );
  }

  if (marketPositions.length === 0) {
    return (
      <div className="bg-gray-800 rounded-xl border border-gray-700 p-4">
        <h3 className="font-semibold mb-2">Your Positions</h3>
        <p className="text-gray-500 text-sm">No open positions in this market</p>
      </div>
    );
  }

  return (
    <div className="bg-gray-800 rounded-xl border border-gray-700 p-4 space-y-4">
      <h3 className="font-semibold">Your Positions ({marketPositions.length})</h3>
      
      {marketPositions.map((position) => {
        const pnl = calculatePnL(position);
        const pnlPercent = position.collateral > 0n 
          ? (pnl * 10000n) / position.collateral 
          : 0n;
        const isProfitable = pnl >= 0n;
        const isThisClosing = closingPositionId === position.id;

        return (
          <div key={position.id.toString()} className="border border-gray-700 rounded-lg p-3 space-y-2">
            {/* Header */}
            <div className="flex justify-between items-center">
              <div className="flex items-center gap-2">
                <span className={`px-2 py-0.5 text-xs font-semibold rounded ${
                  position.side === 0 ? 'bg-lever-green/20 text-lever-green' : 'bg-lever-red/20 text-lever-red'
                }`}>
                  {position.side === 0 ? 'LONG' : 'SHORT'}
                </span>
                <span className="text-xs text-gray-500">ID: {position.id.toString()}</span>
              </div>
              <span className={`text-sm font-bold ${isProfitable ? 'text-lever-green' : 'text-lever-red'}`}>
                {isProfitable ? '+' : ''}{Number(formatUnits(pnl, 18)).toFixed(2)} USDT
                <span className="text-xs ml-1">({Number(pnlPercent) / 100}%)</span>
              </span>
            </div>

            {/* Details */}
            <div className="grid grid-cols-2 gap-2 text-sm">
              <div>
                <span className="text-gray-500">Size:</span>
                <span className="ml-2">${Number(formatUnits(position.size, 18)).toLocaleString()}</span>
              </div>
              <div>
                <span className="text-gray-500">Entry:</span>
                <span className="ml-2">{(Number(formatUnits(position.entryPrice, 18)) * 100).toFixed(2)}%</span>
              </div>
              <div>
                <span className="text-gray-500">Collateral:</span>
                <span className="ml-2">${Number(formatUnits(position.collateral, 18)).toLocaleString()}</span>
              </div>
              <div>
                <span className="text-gray-500">Mark:</span>
                <span className="ml-2">{markPrice ? (Number(formatUnits(markPrice as bigint, 18)) * 100).toFixed(2) : '-'}%</span>
              </div>
            </div>

            {/* Close Button */}
            <button
              onClick={() => handleClose(position.id)}
              disabled={isThisClosing || isUpdatingPrice}
              className="w-full py-2 bg-red-500/20 hover:bg-red-500/30 text-red-400 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
            >
              {isThisClosing && isUpdatingPrice && 'Updating price...'}
              {isThisClosing && isClosing && 'Closing...'}
              {!isThisClosing && 'Close Position'}
            </button>
          </div>
        );
      })}

      {/* Last TX Link */}
      {lastTxHash && (
        <div className="text-xs text-gray-500 flex items-center gap-1">
          Last TX: 
          <a 
            href={`https://testnet.bscscan.com/tx/${lastTxHash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-blue-400 hover:underline font-mono"
          >
            {lastTxHash.slice(0, 10)}...{lastTxHash.slice(-8)}
          </a>
        </div>
      )}
    </div>
  );
}
