'use client';

import { useState } from 'react';
import { useAccount, useWriteContract, useReadContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits, formatUnits } from 'viem';
import { CONTRACTS, USDT_ABI, ROUTER_ABI } from '@/config/contracts';
import { ensureFreshPrice } from '@/lib/priceUpdater';
import { useToast } from './Toast';

interface TradingPanelProps {
  marketId: number;
  initialSide?: 'long' | 'short';
}

export function TradingPanel({ marketId, initialSide }: TradingPanelProps) {
  const MARKET_ID = BigInt(marketId);
  const { address, isConnected } = useAccount();
  const chainId = 97;
  const contracts = CONTRACTS[chainId];
  const { showToast } = useToast();

  const [side, setSide] = useState<'long' | 'short'>(initialSide || 'long');
  const [orderType, setOrderType] = useState<'market' | 'limit'>('market');
  const [collateral, setCollateral] = useState('');
  const [leverage, setLeverage] = useState(2);
  const [isApproving, setIsApproving] = useState(false);
  const [isUpdatingPrice, setIsUpdatingPrice] = useState(false);

  const leverageOptions = [2, 3, 4, 5];

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
        args: [contracts.ROUTER as `0x${string}`, collateralWei * 2n],
      }, {
        onSuccess: () => {
          showToast('Approval successful! Opening position...', 'success');
        },
        onError: (error) => {
          showToast(`Approval failed: ${error.message.slice(0, 100)}`, 'error');
        },
      });
    } catch (e: any) {
      console.error(e);
      showToast('Failed to approve. Please try again.', 'error');
    } finally {
      setIsApproving(false);
    }
  };

  const handleTrade = async () => {
    if (!collateral || !leverage) {
      showToast('Please enter an amount and select leverage', 'warning');
      return;
    }

    if (Number(collateral) <= 0) {
      showToast('Amount must be greater than 0', 'warning');
      return;
    }

    try {
      setIsUpdatingPrice(true);
      await ensureFreshPrice(marketId);
      setIsUpdatingPrice(false);
    } catch (e) {
      console.error('Failed to update price:', e);
      setIsUpdatingPrice(false);
      showToast('Failed to update price. Please try again.', 'error');
      return;
    }

    const sizeMultiplier = BigInt(leverage) * 2n;
    const size = collateralWei * sizeMultiplier;
    const sizeDelta = side === 'long' ? size : -size;
    const maxPrice = parseUnits('0.99', 18);
    const minPrice = parseUnits('0.01', 18);

    try {
      openPosition({
        address: contracts.ROUTER as `0x${string}`,
        abi: ROUTER_ABI,
        functionName: 'openPosition',
        args: [MARKET_ID, sizeDelta, collateralWei, maxPrice, minPrice],
      }, {
        onSuccess: () => {
          showToast(`${side === 'long' ? 'Long' : 'Short'} position opened successfully!`, 'success');
          setCollateral('');
        },
        onError: (error) => {
          const message = error.message.includes('insufficient')
            ? 'Insufficient balance to open position'
            : `Transaction failed: ${error.message.slice(0, 100)}`;
          showToast(message, 'error');
        },
      });
    } catch (e: any) {
      console.error(e);
      showToast('Failed to open position. Please try again.', 'error');
    }
  };

  const setCollateralPercent = (percent: number) => {
    if (!usdtBalance) return;
    const val = Number(formatUnits(usdtBalance, 18)) * (percent / 100);
    setCollateral(val.toString());
  };

  if (!contracts.ROUTER) {
    return (
      <div className="bg-gray-800 rounded-xl border border-gray-700 h-full">
        <div className="p-4">
          <p className="text-yellow-500 text-sm">Configure contracts</p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-gray-800 rounded-xl border border-gray-700 h-full">
      {/* Long/Short Tabs */}
      <div className="flex border-b border-gray-700">
        <button
          onClick={() => setSide('long')}
          className={`flex-1 py-3 text-center font-semibold transition-colors ${
            side === 'long'
              ? 'text-lever-blue border-b-2 border-lever-blue bg-gray-800'
              : 'text-gray-400 hover:text-white'
          }`}
        >
          Long
        </button>
        <button
          onClick={() => setSide('short')}
          className={`flex-1 py-3 text-center font-semibold transition-colors ${
            side === 'short'
              ? 'text-lever-blue border-b-2 border-lever-blue bg-gray-800'
              : 'text-gray-400 hover:text-white'
          }`}
        >
          Short
        </button>
      </div>

      <div className="p-4">
        {/* Order Type Tabs */}
        <div className="flex gap-4 mb-4 text-sm">
          <button
            onClick={() => setOrderType('market')}
            className={`pb-1 border-b-2 transition-colors ${
              orderType === 'market'
                ? 'text-white border-white'
                : 'text-gray-500 border-transparent hover:text-gray-300'
            }`}
          >
            Market
          </button>
          <button
            disabled
            className="pb-1 text-gray-600 cursor-not-allowed"
          >
            Limit <span className="text-xs">(soon)</span>
          </button>
        </div>

        {/* Margin / Balance */}
        <div className="flex justify-between items-center mb-2 text-sm">
          <span className="text-gray-400">Margin</span>
          <span className="text-gray-500">
            Balance: {usdtBalance ? Number(formatUnits(usdtBalance, 18)).toFixed(2) : '0'}
          </span>
        </div>

        {/* USDT Amount Input */}
        <div className="relative mb-3">
          <input
            type="number"
            value={collateral}
            onChange={(e) => {
              const value = e.target.value;
              // Only allow positive numbers with up to 2 decimals
              if (value === '' || /^\d*\.?\d{0,2}$/.test(value)) {
                setCollateral(value);
              }
            }}
            placeholder="USDT Amount"
            min="0"
            step="0.01"
            className="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-3 pr-20 text-lg focus:outline-none focus:border-blue-500"
          />
          <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1">
            <span className="text-blue-400">◉</span>
            <span className="text-gray-400 text-sm">USDT</span>
          </div>
        </div>
        
        {/* Validation Messages */}
        {collateral && Number(collateral) > Number(formatUnits(usdtBalance || 0n, 18)) && (
          <p className="text-red-400 text-sm -mt-2 mb-3">Insufficient balance</p>
        )}
        {collateral && Number(collateral) <= 0 && (
          <p className="text-yellow-400 text-sm -mt-2 mb-3">Amount must be greater than 0</p>
        )}

        {/* Quick Percentage Buttons */}
        <div className="flex gap-2 mb-4">
          {[10, 25, 50, 75].map((pct) => (
            <button
              key={pct}
              onClick={() => setCollateralPercent(pct)}
              className="flex-1 py-1.5 text-xs bg-gray-700 hover:bg-gray-600 rounded transition text-gray-300"
            >
              {pct}%
            </button>
          ))}
          <button
            onClick={() => setCollateralPercent(100)}
            className="flex-1 py-1.5 text-xs bg-gray-700 hover:bg-gray-600 rounded transition text-gray-300"
          >
            MAX
          </button>
        </div>

        {/* Leverage */}
        <div className="mb-4">
          <div className="flex justify-between items-center mb-2 text-sm">
            <span className="text-gray-400">Leverage</span>
            <span className="text-white font-semibold">{leverage}x</span>
          </div>
          
          {/* Leverage Slider with discrete stops */}
          <div className="relative mb-2">
            <input
              type="range"
              min="2"
              max="5"
              step="1"
              value={leverage}
              onChange={(e) => setLeverage(Number(e.target.value))}
              className="w-full h-1 bg-gray-700 rounded-lg appearance-none cursor-pointer slider-thumb"
              style={{
                background: `linear-gradient(to right, #3b82f6 0%, #3b82f6 ${((leverage - 2) / 3) * 100}%, #374151 ${((leverage - 2) / 3) * 100}%, #374151 100%)`
              }}
            />
          </div>
          
          {/* Leverage Labels */}
          <div className="flex justify-between text-xs text-gray-500">
            {leverageOptions.map((lev) => (
              <button
                key={lev}
                onClick={() => setLeverage(lev)}
                className={`px-2 py-1 rounded ${
                  leverage === lev ? 'text-blue-500' : 'hover:text-gray-300'
                }`}
              >
                {lev}x
              </button>
            ))}
          </div>
        </div>

        {/* Position Info */}
        {collateral && Number(collateral) > 0 && (
          <div className="bg-gray-700/50 rounded-lg p-3 mb-4 text-sm space-y-2">
            <div className="flex justify-between">
              <span className="text-gray-400">Position Size</span>
              <span>${(Number(collateral) * leverage).toFixed(2)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Est. Liq. Price</span>
              <span className={side === 'long' ? 'text-red-400' : 'text-green-400'}>
                {side === 'long' ? '~35¢' : '~65¢'}
              </span>
            </div>
          </div>
        )}

        {/* Action Button */}
        {!isConnected ? (
          <button
            disabled
            className="w-full py-3 rounded-lg font-semibold bg-gray-600 text-gray-400 cursor-not-allowed"
            title="Connect your wallet to trade"
          >
            Connect Wallet
          </button>
        ) : needsApproval ? (
          <button
            onClick={handleApprove}
            disabled={isApproveLoading || isApproving || !collateral || Number(collateral) <= 0}
            className="w-full py-3 rounded-lg font-semibold bg-yellow-600 hover:bg-yellow-500 disabled:opacity-50 disabled:cursor-not-allowed transition"
            title={!collateral ? "Enter an amount to continue" : "Approve USDT spending"}
          >
            {isApproveLoading ? 'Approving...' : 'Approve USDT'}
          </button>
        ) : (
          <button
            onClick={handleTrade}
            disabled={
              !collateral || 
              Number(collateral) <= 0 || 
              Number(collateral) > Number(formatUnits(usdtBalance || 0n, 18)) ||
              isOpenLoading || 
              isUpdatingPrice
            }
            className={`w-full py-3 rounded-lg font-semibold disabled:opacity-50 disabled:cursor-not-allowed transition ${
              side === 'long'
                ? 'bg-lever-green hover:bg-green-400 text-white'
                : 'bg-lever-red hover:bg-red-400 text-white'
            }`}
            title={
              !collateral ? "Enter an amount" :
              Number(collateral) <= 0 ? "Amount must be greater than 0" :
              Number(collateral) > Number(formatUnits(usdtBalance || 0n, 18)) ? "Insufficient balance" :
              `Open ${side} position`
            }
          >
            {isUpdatingPrice
              ? 'Updating price...'
              : isOpenLoading
                ? 'Opening...'
                : side === 'long' ? 'Long' : 'Short'}
          </button>
        )}
      </div>
    </div>
  );
}
