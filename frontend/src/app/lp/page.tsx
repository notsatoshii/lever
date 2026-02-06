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

export default function LPPage() {
  const { address, isConnected } = useAccount();
  const contracts = CONTRACTS[97];

  const [mode, setMode] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');

  // Pool stats
  const [totalAssets, setTotalAssets] = useState<bigint | null>(null);
  const [totalAllocated, setTotalAllocated] = useState<bigint | null>(null);
  const [sharePrice, setSharePrice] = useState<bigint | null>(null);
  const [utilization, setUtilization] = useState<bigint | null>(null);
  const [cumulativeFees, setCumulativeFees] = useState<bigint | null>(null);

  // User stats
  const [usdtBalance, setUsdtBalance] = useState<bigint | null>(null);
  const [lpBalance, setLpBalance] = useState<bigint | null>(null);
  const [allowance, setAllowance] = useState<bigint | null>(null);
  const [pendingFees, setPendingFees] = useState<bigint | null>(null);

  // Write functions
  const { writeContract: approve, data: approveHash } = useWriteContract();
  const { writeContract: deposit, data: depositHash } = useWriteContract();
  const { writeContract: withdraw, data: withdrawHash } = useWriteContract();
  const { writeContract: claimFees, data: claimHash } = useWriteContract();

  const { isLoading: isApproving, isSuccess: approveSuccess } = useWaitForTransactionReceipt({ hash: approveHash });
  const { isLoading: isDepositing } = useWaitForTransactionReceipt({ hash: depositHash });
  const { isLoading: isWithdrawing } = useWaitForTransactionReceipt({ hash: withdrawHash });
  const { isLoading: isClaiming } = useWaitForTransactionReceipt({ hash: claimHash });

  const [pendingDepositAmount, setPendingDepositAmount] = useState<bigint | null>(null);

  // Fetch pool stats
  useEffect(() => {
    async function fetchPoolStats() {
      try {
        const [assets, allocated, price, util, cumFees] = await Promise.all([
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'totalAssets',
          }),
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'totalAllocated',
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
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'cumulativeFeePerShare',
          }),
        ]);
        setTotalAssets(assets as bigint);
        setTotalAllocated(allocated as bigint);
        setSharePrice(price as bigint);
        setUtilization(util as bigint);
        setCumulativeFees(cumFees as bigint);
      } catch (e) {
        console.error('Error fetching pool stats:', e);
      }
    }
    fetchPoolStats();
    const interval = setInterval(fetchPoolStats, 10000);
    return () => clearInterval(interval);
  }, [contracts]);

  // Fetch user balances
  useEffect(() => {
    async function fetchUserStats() {
      if (!address) return;
      try {
        const [usdt, lp, allow, fees] = await Promise.all([
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
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'pendingFeesOf',
            args: [address],
          }),
        ]);
        setUsdtBalance(usdt as bigint);
        setLpBalance(lp as bigint);
        setAllowance(allow as bigint);
        setPendingFees(fees as bigint);
      } catch (e) {
        console.error('Error fetching user stats:', e);
      }
    }
    fetchUserStats();
    const interval = setInterval(fetchUserStats, 5000);
    return () => clearInterval(interval);
  }, [address, contracts]);

  // Auto-deposit after approval
  useEffect(() => {
    if (approveSuccess && pendingDepositAmount && address) {
      deposit({
        address: contracts.LP_POOL as `0x${string}`,
        abi: LP_POOL_ABI,
        functionName: 'deposit',
        args: [pendingDepositAmount, address],
      });
      setPendingDepositAmount(null);
    }
  }, [approveSuccess, pendingDepositAmount, address, contracts.LP_POOL, deposit]);

  const amountWei = amount ? parseUnits(amount, 18) : 0n;
  const needsApproval = mode === 'deposit' && allowance !== null && amountWei > allowance;

  const handleApprove = () => {
    setPendingDepositAmount(amountWei);
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

  const handleClaimFees = () => {
    claimFees({
      address: contracts.LP_POOL as `0x${string}`,
      abi: LP_POOL_ABI,
      functionName: 'claimFees',
    });
  };

  const utilizationPercent = utilization ? Number(formatUnits(utilization, 18)) * 100 : 0;
  const estimatedAPY = utilizationPercent * 0.15; // Rough estimate

  return (
    <div className="px-6 py-8">
      <h1 className="text-2xl font-bold mb-6">Liquidity Pool</h1>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        {/* Pool Stats */}
        <div className="xl:col-span-2">
          <div className="bg-gray-800 rounded-xl border border-gray-700 p-6 mb-6">
            <h2 className="text-lg font-semibold mb-4">Pool Overview</h2>
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 lg:gap-6">
              <div>
                <p className="text-gray-400 text-sm mb-1">Total Value Locked</p>
                <p className="text-2xl font-bold">
                  ${totalAssets ? Number(formatUnits(totalAssets, 18)).toLocaleString() : '—'}
                </p>
              </div>
              <div>
                <p className="text-gray-400 text-sm mb-1">Capital Deployed</p>
                <p className="text-2xl font-bold">
                  ${totalAllocated ? Number(formatUnits(totalAllocated, 18)).toLocaleString() : '0'}
                </p>
              </div>
              <div>
                <p className="text-gray-400 text-sm mb-1">Utilization</p>
                <p className="text-2xl font-bold">
                  {utilization !== null ? `${utilizationPercent.toFixed(1)}%` : '—'}
                </p>
              </div>
              <div>
                <p className="text-gray-400 text-sm mb-1">Share Price</p>
                <p className="text-2xl font-bold">
                  ${sharePrice ? Number(formatUnits(sharePrice, 18)).toFixed(4) : '—'}
                </p>
              </div>
            </div>
            
            {/* Fee Stats */}
            <div className="mt-4 pt-4 border-t border-gray-700">
              <h3 className="text-sm font-semibold text-gray-400 mb-2">Fee Distribution</h3>
              <p className="text-sm text-gray-500">
                Fees from trading, borrow interest, and liquidations are distributed pro-rata to LP token holders.
                {cumulativeFees && cumulativeFees > 0n && (
                  <span className="block mt-1 text-lever-green">
                    Cumulative fees per share: {Number(formatUnits(cumulativeFees, 18)).toFixed(6)} USDT
                  </span>
                )}
              </p>
            </div>
          </div>

          {/* Utilization Bar */}
          <div className="bg-gray-800 rounded-xl border border-gray-700 p-6">
            <h3 className="text-sm font-semibold text-gray-400 mb-3">Pool Utilization</h3>
            <div className="w-full bg-gray-700 rounded-full h-4 mb-2">
              <div
                className="bg-gradient-to-r from-green-500 to-yellow-500 h-4 rounded-full transition-all"
                style={{ width: `${Math.min(utilizationPercent, 100)}%` }}
              />
            </div>
            <div className="flex justify-between text-xs text-gray-500">
              <span>0%</span>
              <span>50%</span>
              <span>100%</span>
            </div>
            <p className="mt-4 text-sm text-gray-400">
              Higher utilization = higher APY for LPs, but less available liquidity for new positions.
            </p>
          </div>
        </div>

        {/* Deposit/Withdraw Panel */}
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-6">
          <h2 className="text-lg font-semibold mb-4">
            {mode === 'deposit' ? 'Deposit' : 'Withdraw'}
          </h2>

          {/* Your Position */}
          {isConnected && (
            <div className="bg-gray-700 rounded-lg p-4 mb-4">
              <p className="text-sm text-gray-400 mb-2">Your Position</p>
              <div className="flex justify-between">
                <span>LP Tokens</span>
                <span className="font-semibold">
                  {lpBalance ? Number(formatUnits(lpBalance, 18)).toLocaleString() : '0'} lvUSDT
                </span>
              </div>
              <div className="flex justify-between mt-1">
                <span>Value</span>
                <span className="font-semibold">
                  ${lpBalance && sharePrice
                    ? (Number(formatUnits(lpBalance, 18)) * Number(formatUnits(sharePrice, 18))).toLocaleString()
                    : '0'}
                </span>
              </div>
              {pendingFees && pendingFees > 0n && (
                <>
                  <div className="flex justify-between mt-2 pt-2 border-t border-gray-600">
                    <span className="text-lever-green">Unclaimed Fees</span>
                    <span className="font-semibold text-lever-green">
                      {Number(formatUnits(pendingFees, 18)).toFixed(4)} USDT
                    </span>
                  </div>
                  <button
                    onClick={handleClaimFees}
                    disabled={isClaiming}
                    className="w-full mt-2 py-2 rounded-lg text-sm font-semibold bg-lever-green/20 text-lever-green hover:bg-lever-green/30 disabled:opacity-50"
                  >
                    {isClaiming ? 'Claiming...' : 'Claim Fees'}
                  </button>
                </>
              )}
            </div>
          )}

          {/* Mode Toggle */}
          <div className="flex gap-2 mb-4">
            <button
              onClick={() => setMode('deposit')}
              className={`flex-1 py-2 rounded-lg font-semibold transition ${
                mode === 'deposit'
                  ? 'bg-green-600 text-white'
                  : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
              }`}
            >
              Deposit
            </button>
            <button
              onClick={() => setMode('withdraw')}
              className={`flex-1 py-2 rounded-lg font-semibold transition ${
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
            <label className="text-sm text-gray-400 mb-1 block">Amount (USDT)</label>
            <div className="relative">
              <input
                type="number"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0.00"
                className="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-3 text-lg focus:outline-none focus:border-blue-500"
              />
              <button
                onClick={() => {
                  const max = mode === 'deposit' ? usdtBalance : lpBalance;
                  if (max) setAmount(formatUnits(max, 18));
                }}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-blue-500 hover:underline"
              >
                MAX
              </button>
            </div>
            <p className="text-xs text-gray-500 mt-1">
              {mode === 'deposit'
                ? `Balance: ${usdtBalance ? Number(formatUnits(usdtBalance, 18)).toLocaleString() : '0'} USDT`
                : `LP Balance: ${lpBalance ? Number(formatUnits(lpBalance, 18)).toLocaleString() : '0'} lvUSDT`}
            </p>
          </div>

          {/* Quick Amount Buttons */}
          <div className="flex gap-2 mb-4">
            {['10%', '25%', '50%', '75%', 'MAX'].map((pct) => (
              <button
                key={pct}
                onClick={() => {
                  const max = mode === 'deposit' ? usdtBalance : lpBalance;
                  if (!max) return;
                  const multiplier = pct === 'MAX' ? 1 : parseInt(pct) / 100;
                  const val = Number(formatUnits(max, 18)) * multiplier;
                  setAmount(val.toString());
                }}
                className="flex-1 py-1.5 text-xs bg-gray-700 hover:bg-gray-600 rounded transition"
              >
                {pct}
              </button>
            ))}
          </div>

          {/* Action Button */}
          {!isConnected ? (
            <p className="text-center text-gray-400 py-3">Connect wallet to continue</p>
          ) : mode === 'deposit' && needsApproval ? (
            <button
              onClick={handleApprove}
              disabled={isApproving || pendingDepositAmount !== null || !amount}
              className="w-full py-3 rounded-lg font-semibold bg-yellow-600 hover:bg-yellow-500 disabled:opacity-50"
            >
              {isApproving ? 'Approving...' : pendingDepositAmount ? 'Depositing...' : 'Approve & Deposit'}
            </button>
          ) : (
            <button
              onClick={mode === 'deposit' ? handleDeposit : handleWithdraw}
              disabled={!amount || isDepositing || isWithdrawing}
              className="w-full py-3 rounded-lg font-semibold bg-blue-600 hover:bg-blue-500 disabled:opacity-50"
            >
              {isDepositing || isWithdrawing
                ? mode === 'deposit' ? 'Depositing...' : 'Withdrawing...'
                : mode === 'deposit' ? 'Deposit' : 'Withdraw'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
