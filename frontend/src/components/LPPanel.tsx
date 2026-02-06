'use client';

import { useState, useEffect } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { createPublicClient, http, parseUnits, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';
import { CONTRACTS, USDT_ABI, LP_POOL_ABI } from '@/config/contracts';

const client = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

export function LPPanel() {
  const { address, isConnected, chain } = useAccount();
  const contracts = CONTRACTS[97];
  
  // Debug connection
  console.log('LPPanel wallet:', { address, isConnected, chainId: chain?.id });

  const [mode, setMode] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');
  
  // Pool stats
  const [totalAssets, setTotalAssets] = useState<bigint | null>(null);
  const [sharePrice, setSharePrice] = useState<bigint | null>(null);
  const [utilization, setUtilization] = useState<bigint | null>(null);
  
  // User stats
  const [usdtBalance, setUsdtBalance] = useState<bigint | null>(null);
  const [lpBalance, setLpBalance] = useState<bigint | null>(null);
  const [allowance, setAllowance] = useState<bigint | null>(null);

  // Fetch pool stats (always)
  useEffect(() => {
    async function fetchPoolStats() {
      try {
        const [assets, price, util] = await Promise.all([
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'totalAssets',
          }),
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'sharePrice',
          }),
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'utilization',
          }),
        ]);
        setTotalAssets(assets as bigint);
        setSharePrice(price as bigint);
        setUtilization(util as bigint);
      } catch (e) {
        console.error('Error fetching pool stats:', e);
      }
    }
    fetchPoolStats();
    const interval = setInterval(fetchPoolStats, 10000);
    return () => clearInterval(interval);
  }, [contracts]);

  // Fetch user balances (when connected)
  useEffect(() => {
    async function fetchUserStats() {
      if (!address) return;
      try {
        const [usdt, lp, allow] = await Promise.all([
          client.readContract({
            address: contracts.USDT as `0x${string}`,
            abi: USDT_ABI,
            functionName: 'balanceOf',
            args: [address],
          }),
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'balanceOf',
            args: [address],
          }),
          client.readContract({
            address: contracts.USDT as `0x${string}`,
            abi: USDT_ABI,
            functionName: 'allowance',
            args: [address, contracts.LP_POOL as `0x${string}`],
          }),
        ]);
        setUsdtBalance(usdt as bigint);
        setLpBalance(lp as bigint);
        setAllowance(allow as bigint);
      } catch (e) {
        console.error('Error fetching user stats:', e);
      }
    }
    fetchUserStats();
    const interval = setInterval(fetchUserStats, 5000);
    return () => clearInterval(interval);
  }, [address, contracts]);

  const amountWei = amount ? parseUnits(amount, 18) : 0n;
  const needsApproval = mode === 'deposit' && allowance !== null && amountWei > allowance;
  
  // Track pending deposit after approval
  const [pendingDepositAmount, setPendingDepositAmount] = useState<bigint | null>(null);

  // Write functions
  const { writeContract: approve, data: approveHash } = useWriteContract();
  const { writeContract: deposit, data: depositHash } = useWriteContract();
  const { writeContract: withdraw, data: withdrawHash } = useWriteContract();

  const { isLoading: isApproving, isSuccess: approveSuccess } = useWaitForTransactionReceipt({ hash: approveHash });
  const { isLoading: isDepositing } = useWaitForTransactionReceipt({ hash: depositHash });
  const { isLoading: isWithdrawing } = useWaitForTransactionReceipt({ hash: withdrawHash });

  // Auto-deposit after approval confirmed
  useEffect(() => {
    if (approveSuccess && pendingDepositAmount && address) {
      console.log('Approval confirmed, auto-depositing:', pendingDepositAmount.toString());
      deposit({
        address: contracts.LP_POOL as `0x${string}`,
        abi: LP_POOL_ABI,
        functionName: 'deposit',
        args: [pendingDepositAmount, address],
      });
      setPendingDepositAmount(null);
    }
  }, [approveSuccess, pendingDepositAmount, address, contracts.LP_POOL, deposit]);

  const handleApprove = () => {
    console.log('Approving:', {
      token: contracts.USDT,
      spender: contracts.LP_POOL,
      amount: amountWei.toString(),
    });
    // Store amount to deposit after approval
    setPendingDepositAmount(amountWei);
    approve({
      address: contracts.USDT as `0x${string}`,
      abi: USDT_ABI,
      functionName: 'approve',
      args: [contracts.LP_POOL as `0x${string}`, amountWei * 2n],
    }, {
      onError: (e) => {
        console.error('Approve error:', e);
        setPendingDepositAmount(null);
      },
      onSuccess: (hash) => console.log('Approve tx:', hash),
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

  return (
    <div className="bg-gray-800 rounded-xl p-6 border border-gray-700">
      <h2 className="text-lg font-semibold mb-4">LP Pool</h2>

      {/* Pool Stats */}
      <div className="grid grid-cols-2 gap-3 mb-4 text-sm">
        <div className="bg-gray-700 rounded-lg p-3">
          <p className="text-gray-400">TVL</p>
          <p className="font-semibold text-lg">
            {totalAssets 
              ? `$${Number(formatUnits(totalAssets, 18)).toLocaleString()}`
              : '—'
            }
          </p>
        </div>
        <div className="bg-gray-700 rounded-lg p-3">
          <p className="text-gray-400">APY</p>
          <p className="font-semibold text-lg text-lever-green">
            {utilization !== null
              ? `${(Number(formatUnits(utilization, 18)) * 15).toFixed(1)}%`
              : '—'
            }
          </p>
        </div>
        <div className="bg-gray-700 rounded-lg p-3">
          <p className="text-gray-400">Utilization</p>
          <p className="font-semibold">
            {utilization !== null
              ? `${(Number(formatUnits(utilization, 18)) * 100).toFixed(1)}%`
              : '—'
            }
          </p>
        </div>
        <div className="bg-gray-700 rounded-lg p-3">
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
              ? 'bg-green-600 text-white'
              : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
          }`}
        >
          Deposit
        </button>
        <button
          onClick={() => setMode('withdraw')}
          className={`flex-1 py-2 rounded-lg text-sm font-semibold transition ${
            mode === 'withdraw'
              ? 'bg-green-600 text-white'
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
            className="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-3 focus:outline-none focus:border-green-500"
          />
          <button
            onClick={() => {
              const max = mode === 'deposit' ? usdtBalance : lpBalance;
              if (max) setAmount(formatUnits(max, 18));
            }}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-green-500 hover:underline"
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
      {!address ? (
        <p className="text-center text-gray-400 py-3">Connect wallet to interact</p>
      ) : mode === 'deposit' && needsApproval ? (
        <button
          onClick={handleApprove}
          disabled={isApproving || pendingDepositAmount !== null}
          className="w-full py-3 rounded-lg font-semibold bg-yellow-600 hover:bg-yellow-500 disabled:opacity-50"
        >
          {isApproving ? 'Approving...' : pendingDepositAmount ? 'Depositing...' : 'Approve & Deposit'}
        </button>
      ) : (
        <button
          onClick={mode === 'deposit' ? handleDeposit : handleWithdraw}
          disabled={!amount || isDepositing || isWithdrawing}
          className="w-full py-3 rounded-lg font-semibold bg-green-600 hover:bg-green-500 disabled:opacity-50"
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
