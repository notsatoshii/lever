'use client';

import { useState } from 'react';
import { useAccount, useWriteContract, useReadContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits, formatUnits } from 'viem';
import { CONTRACTS, USDT_ABI, ROUTER_ABI } from '@/config/contracts';

interface TradingPanelProps {
  marketId: number;
}

export function TradingPanel({ marketId }: TradingPanelProps) {
  const MARKET_ID = BigInt(marketId);
  const { address } = useAccount();
  const chainId = 97;
  const contracts = CONTRACTS[chainId];

  const [side, setSide] = useState<'long' | 'short'>('long');
  const [collateral, setCollateral] = useState('');
  const [leverage, setLeverage] = useState(5);
  const [isApproving, setIsApproving] = useState(false);

  // Read USDT balance
  const { data: usdtBalance } = useReadContract({
    address: contracts.USDT as `0x${string}`,
    abi: USDT_ABI,
    functionName: 'balanceOf',
    args: [address!],
  });

  // Read allowance
  const { data: allowance } = useReadContract({
    address: contracts.USDT as `0x${string}`,
    abi: USDT_ABI,
    functionName: 'allowance',
    args: [address!, contracts.ROUTER as `0x${string}`],
  });

  // Write functions
  const { writeContract: approve, data: approveHash } = useWriteContract();
  const { writeContract: openPosition, data: openHash } = useWriteContract();

  const { isLoading: isApproveLoading } = useWaitForTransactionReceipt({ hash: approveHash });
  const { isLoading: isOpenLoading } = useWaitForTransactionReceipt({ hash: openHash });

  const collateralWei = collateral ? parseUnits(collateral, 18) : 0n;
  const needsApproval = allowance !== undefined && collateralWei > allowance;

  const handleApprove = async () => {
    setIsApproving(true);
    try {
      approve({
        address: contracts.USDT as `0x${string}`,
        abi: USDT_ABI,
        functionName: 'approve',
        args: [contracts.ROUTER as `0x${string}`, collateralWei * 2n], // Approve 2x for future trades
      });
    } catch (e) {
      console.error(e);
    }
    setIsApproving(false);
  };

  const handleTrade = async () => {
    if (!collateral || !leverage) return;

    // Calculate size based on collateral and leverage
    // size = collateral * leverage / price (assuming 50% = 0.5)
    // For simplicity, we use a rough estimate
    const sizeMultiplier = BigInt(leverage) * 2n; // At 50% price
    const size = collateralWei * sizeMultiplier;

    const sizeDelta = side === 'long' ? size : -size;
    const maxPrice = parseUnits('0.99', 18);  // Slippage protection
    const minPrice = parseUnits('0.01', 18);

    try {
      openPosition({
        address: contracts.ROUTER as `0x${string}`,
        abi: ROUTER_ABI,
        functionName: 'openPosition',
        args: [MARKET_ID, sizeDelta, collateralWei, maxPrice, minPrice],
      });
    } catch (e) {
      console.error(e);
    }
  };

  if (!contracts.ROUTER) {
    return (
      <div className="bg-lever-gray rounded-xl p-6 border border-gray-800">
        <h2 className="text-lg font-semibold mb-4">Trade</h2>
        <p className="text-yellow-500 text-sm">Configure contract addresses first</p>
      </div>
    );
  }

  return (
    <div className="bg-lever-gray rounded-xl p-6 border border-gray-800">
      <h2 className="text-lg font-semibold mb-4">Open Position</h2>

      {/* Side Toggle */}
      <div className="flex gap-2 mb-4">
        <button
          onClick={() => setSide('long')}
          className={`flex-1 py-2 rounded-lg font-semibold transition ${
            side === 'long'
              ? 'bg-green-600 text-white'
              : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
          }`}
        >
          Long
        </button>
        <button
          onClick={() => setSide('short')}
          className={`flex-1 py-2 rounded-lg font-semibold transition ${
            side === 'short'
              ? 'bg-red-600 text-white'
              : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
          }`}
        >
          Short
        </button>
      </div>

      {/* Collateral Input */}
      <div className="mb-4">
        <label className="text-sm text-gray-400 mb-1 block">Collateral (USDT)</label>
        <div className="relative">
          <input
            type="number"
            value={collateral}
            onChange={(e) => setCollateral(e.target.value)}
            placeholder="0.00"
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-4 py-3 text-lg focus:outline-none focus:border-lever-green"
          />
          <button
            onClick={() => usdtBalance && setCollateral(formatUnits(usdtBalance, 18))}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-lever-green hover:underline"
          >
            MAX
          </button>
        </div>
        <p className="text-xs text-gray-500 mt-1">
          Balance: {usdtBalance ? Number(formatUnits(usdtBalance, 18)).toLocaleString() : '0'} USDT
        </p>
      </div>

      {/* Leverage Slider */}
      <div className="mb-6">
        <div className="flex justify-between text-sm text-gray-400 mb-1">
          <span>Leverage</span>
          <span className="text-white font-semibold">{leverage}x</span>
        </div>
        <input
          type="range"
          min="1"
          max="10"
          value={leverage}
          onChange={(e) => setLeverage(Number(e.target.value))}
          className="w-full accent-lever-green"
        />
        <div className="flex justify-between text-xs text-gray-500">
          <span>1x</span>
          <span>5x</span>
          <span>10x</span>
        </div>
      </div>

      {/* Position Size Estimate */}
      {collateral && (
        <div className="bg-gray-800 rounded-lg p-3 mb-4 text-sm">
          <div className="flex justify-between">
            <span className="text-gray-400">Position Size</span>
            <span>~{(Number(collateral) * leverage * 2).toLocaleString()} units</span>
          </div>
          <div className="flex justify-between mt-1">
            <span className="text-gray-400">Liquidation Price</span>
            <span className={side === 'long' ? 'text-red-400' : 'text-green-400'}>
              ~{side === 'long' ? '45%' : '55%'}
            </span>
          </div>
        </div>
      )}

      {/* Action Button */}
      {needsApproval ? (
        <button
          onClick={handleApprove}
          disabled={isApproveLoading || isApproving}
          className="w-full py-3 rounded-lg font-semibold bg-yellow-600 hover:bg-yellow-500 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {isApproveLoading ? 'Approving...' : 'Approve USDT'}
        </button>
      ) : (
        <button
          onClick={handleTrade}
          disabled={!collateral || isOpenLoading}
          className={`w-full py-3 rounded-lg font-semibold disabled:opacity-50 disabled:cursor-not-allowed ${
            side === 'long'
              ? 'bg-green-600 hover:bg-green-500'
              : 'bg-red-600 hover:bg-red-500'
          }`}
        >
          {isOpenLoading ? 'Opening...' : `Open ${side === 'long' ? 'Long' : 'Short'}`}
        </button>
      )}
    </div>
  );
}
