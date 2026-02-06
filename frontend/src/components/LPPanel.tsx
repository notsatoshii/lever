'use client';

import { useState } from 'react';
import { useAccount, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits, formatUnits } from 'viem';
import { CONTRACTS, USDT_ABI, LP_POOL_ABI } from '@/config/contracts';

export function LPPanel() {
  const { address } = useAccount();
  const chainId = 97;
  const contracts = CONTRACTS[chainId];

  const [mode, setMode] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');

  // Read balances and pool stats
  const { data, refetch } = useReadContracts({
    contracts: [
      {
        address: contracts.USDT as `0x${string}`,
        abi: USDT_ABI,
        functionName: 'balanceOf',
        args: [address!],
      },
      {
        address: contracts.LP_POOL as `0x${string}`,
        abi: LP_POOL_ABI,
        functionName: 'balanceOf',
        args: [address!],
      },
      {
        address: contracts.LP_POOL as `0x${string}`,
        abi: LP_POOL_ABI,
        functionName: 'totalAssets',
      },
      {
        address: contracts.LP_POOL as `0x${string}`,
        abi: LP_POOL_ABI,
        functionName: 'sharePrice',
      },
      {
        address: contracts.LP_POOL as `0x${string}`,
        abi: LP_POOL_ABI,
        functionName: 'utilization',
      },
      {
        address: contracts.USDT as `0x${string}`,
        abi: USDT_ABI,
        functionName: 'allowance',
        args: [address!, contracts.LP_POOL as `0x${string}`],
      },
    ],
  });

  const usdtBalance = data?.[0]?.result as bigint | undefined;
  const lpBalance = data?.[1]?.result as bigint | undefined;
  const totalAssets = data?.[2]?.result as bigint | undefined;
  const sharePrice = data?.[3]?.result as bigint | undefined;
  const utilization = data?.[4]?.result as bigint | undefined;
  const allowance = data?.[5]?.result as bigint | undefined;

  const amountWei = amount ? parseUnits(amount, 18) : 0n;
  const needsApproval = mode === 'deposit' && allowance !== undefined && amountWei > allowance;

  // Write functions
  const { writeContract: approve, data: approveHash } = useWriteContract();
  const { writeContract: deposit, data: depositHash } = useWriteContract();
  const { writeContract: withdraw, data: withdrawHash } = useWriteContract();

  const { isLoading: isApproving } = useWaitForTransactionReceipt({ hash: approveHash });
  const { isLoading: isDepositing } = useWaitForTransactionReceipt({ 
    hash: depositHash,
    onSuccess: () => { refetch(); setAmount(''); },
  });
  const { isLoading: isWithdrawing } = useWaitForTransactionReceipt({ 
    hash: withdrawHash,
    onSuccess: () => { refetch(); setAmount(''); },
  });

  const handleApprove = () => {
    approve({
      address: contracts.USDT as `0x${string}`,
      abi: USDT_ABI,
      functionName: 'approve',
      args: [contracts.LP_POOL as `0x${string}`, amountWei * 2n],
    });
  };

  const handleDeposit = () => {
    deposit({
      address: contracts.LP_POOL as `0x${string}`,
      abi: LP_POOL_ABI,
      functionName: 'deposit',
      args: [amountWei, address!],
    });
  };

  const handleWithdraw = () => {
    withdraw({
      address: contracts.LP_POOL as `0x${string}`,
      abi: LP_POOL_ABI,
      functionName: 'withdraw',
      args: [amountWei, address!],
    });
  };

  if (!contracts.LP_POOL) {
    return null;
  }

  return (
    <div className="bg-lever-gray rounded-xl p-6 border border-gray-800">
      <h2 className="text-lg font-semibold mb-4">LP Pool</h2>

      {/* Pool Stats */}
      <div className="grid grid-cols-2 gap-3 mb-4 text-sm">
        <div className="bg-gray-800 rounded-lg p-3">
          <p className="text-gray-400">TVL</p>
          <p className="font-semibold">
            {totalAssets 
              ? `${Number(formatUnits(totalAssets, 18)).toLocaleString()} USDT`
              : '—'
            }
          </p>
        </div>
        <div className="bg-gray-800 rounded-lg p-3">
          <p className="text-gray-400">Utilization</p>
          <p className="font-semibold">
            {utilization 
              ? `${(Number(formatUnits(utilization, 18)) * 100).toFixed(1)}%`
              : '—'
            }
          </p>
        </div>
        <div className="bg-gray-800 rounded-lg p-3">
          <p className="text-gray-400">Share Price</p>
          <p className="font-semibold">
            {sharePrice 
              ? `${Number(formatUnits(sharePrice, 18)).toFixed(4)}`
              : '—'
            }
          </p>
        </div>
        <div className="bg-gray-800 rounded-lg p-3">
          <p className="text-gray-400">Your LP</p>
          <p className="font-semibold">
            {lpBalance 
              ? `${Number(formatUnits(lpBalance, 18)).toLocaleString()}`
              : '0'
            }
          </p>
        </div>
      </div>

      {/* Mode Toggle */}
      <div className="flex gap-2 mb-4">
        <button
          onClick={() => setMode('deposit')}
          className={`flex-1 py-2 rounded-lg text-sm font-semibold transition ${
            mode === 'deposit'
              ? 'bg-lever-green text-white'
              : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
          }`}
        >
          Deposit
        </button>
        <button
          onClick={() => setMode('withdraw')}
          className={`flex-1 py-2 rounded-lg text-sm font-semibold transition ${
            mode === 'withdraw'
              ? 'bg-lever-green text-white'
              : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
          }`}
        >
          Withdraw
        </button>
      </div>

      {/* Amount Input */}
      <div className="mb-4">
        <div className="relative">
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-4 py-3 focus:outline-none focus:border-lever-green"
          />
          <button
            onClick={() => {
              const max = mode === 'deposit' ? usdtBalance : lpBalance;
              if (max) setAmount(formatUnits(max, 18));
            }}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-lever-green hover:underline"
          >
            MAX
          </button>
        </div>
        <p className="text-xs text-gray-500 mt-1">
          {mode === 'deposit' 
            ? `Balance: ${usdtBalance ? Number(formatUnits(usdtBalance, 18)).toLocaleString() : '0'} USDT`
            : `LP Balance: ${lpBalance ? Number(formatUnits(lpBalance, 18)).toLocaleString() : '0'} lvUSDT`
          }
        </p>
      </div>

      {/* Action Button */}
      {mode === 'deposit' && needsApproval ? (
        <button
          onClick={handleApprove}
          disabled={isApproving}
          className="w-full py-3 rounded-lg font-semibold bg-yellow-600 hover:bg-yellow-500 disabled:opacity-50"
        >
          {isApproving ? 'Approving...' : 'Approve USDT'}
        </button>
      ) : (
        <button
          onClick={mode === 'deposit' ? handleDeposit : handleWithdraw}
          disabled={!amount || isDepositing || isWithdrawing}
          className="w-full py-3 rounded-lg font-semibold bg-lever-green hover:bg-green-500 disabled:opacity-50"
        >
          {isDepositing || isWithdrawing 
            ? (mode === 'deposit' ? 'Depositing...' : 'Withdrawing...')
            : (mode === 'deposit' ? 'Deposit' : 'Withdraw')
          }
        </button>
      )}
    </div>
  );
}
