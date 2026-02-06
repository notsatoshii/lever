'use client';

import { useState, useEffect } from 'react';
import { useAccount } from 'wagmi';
import Link from 'next/link';
import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';
import { CONTRACTS, LEDGER_ABI, LP_POOL_ABI, PRICE_ENGINE_ABI, ROUTER_ABI } from '@/config/contracts';
import { parseAbiItem } from 'viem';

const client = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

// Event ABIs for trade history
const POSITION_OPENED_ABI = parseAbiItem('event PositionOpened(address indexed trader, uint256 indexed marketId, int256 size, uint256 executionPrice, uint256 collateral, uint256 tradingFee)');
const POSITION_CLOSED_ABI = parseAbiItem('event PositionClosed(address indexed trader, uint256 indexed marketId, int256 size, uint256 executionPrice, int256 realizedPnL, uint256 tradingFee)');

interface TradeEvent {
  type: 'open' | 'close';
  marketId: number;
  size: bigint;
  price: bigint;
  collateral?: bigint;
  pnl?: bigint;
  fee: bigint;
  timestamp: number;
  txHash: string;
  blockNumber: bigint;
}

// Trade History Component
function TradeHistoryTab({ address, contracts }: { address: string | undefined; contracts: typeof CONTRACTS[97] }) {
  const [trades, setTrades] = useState<TradeEvent[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    async function fetchTradeHistory() {
      if (!address || !contracts.ROUTER) {
        setIsLoading(false);
        return;
      }

      try {
        // Fetch last 1000 blocks of events (~50 mins on BSC)
        const currentBlock = await client.getBlockNumber();
        const fromBlock = currentBlock - 1000n;

        // Fetch PositionOpened events
        const openedLogs = await client.getLogs({
          address: contracts.ROUTER as `0x${string}`,
          event: POSITION_OPENED_ABI,
          args: { trader: address as `0x${string}` },
          fromBlock,
          toBlock: 'latest',
        });

        // Fetch PositionClosed events  
        const closedLogs = await client.getLogs({
          address: contracts.ROUTER as `0x${string}`,
          event: POSITION_CLOSED_ABI,
          args: { trader: address as `0x${string}` },
          fromBlock,
          toBlock: 'latest',
        });

        // Get block timestamps
        const allBlocks = [...new Set([...openedLogs, ...closedLogs].map(l => l.blockNumber))];
        const blockTimestamps: Record<string, number> = {};
        
        await Promise.all(
          allBlocks.map(async (blockNum) => {
            try {
              const block = await client.getBlock({ blockNumber: blockNum });
              blockTimestamps[blockNum.toString()] = Number(block.timestamp);
            } catch {
              blockTimestamps[blockNum.toString()] = 0;
            }
          })
        );

        // Parse events
        const openTrades: TradeEvent[] = openedLogs.map((log) => ({
          type: 'open' as const,
          marketId: Number(log.args.marketId),
          size: log.args.size as bigint,
          price: log.args.executionPrice as bigint,
          collateral: log.args.collateral as bigint,
          fee: log.args.tradingFee as bigint,
          timestamp: blockTimestamps[log.blockNumber.toString()] || 0,
          txHash: log.transactionHash,
          blockNumber: log.blockNumber,
        }));

        const closeTrades: TradeEvent[] = closedLogs.map((log) => ({
          type: 'close' as const,
          marketId: Number(log.args.marketId),
          size: log.args.size as bigint,
          price: log.args.executionPrice as bigint,
          pnl: log.args.realizedPnL as bigint,
          fee: log.args.tradingFee as bigint,
          timestamp: blockTimestamps[log.blockNumber.toString()] || 0,
          txHash: log.transactionHash,
          blockNumber: log.blockNumber,
        }));

        // Combine and sort by block (newest first)
        const allTrades = [...openTrades, ...closeTrades].sort(
          (a, b) => Number(b.blockNumber) - Number(a.blockNumber)
        );

        setTrades(allTrades);
      } catch (e) {
        console.error('Failed to fetch trade history:', e);
      }
      setIsLoading(false);
    }

    fetchTradeHistory();
  }, [address, contracts]);

  if (isLoading) {
    return (
      <div className="bg-gray-800 rounded-xl border border-gray-700 p-8 text-center">
        <p className="text-gray-400">Loading trade history...</p>
      </div>
    );
  }

  if (trades.length === 0) {
    return (
      <div className="bg-gray-800 rounded-xl border border-gray-700 p-8 text-center">
        <p className="text-gray-400 mb-2">No recent trades</p>
        <p className="text-gray-500 text-sm">
          Your trade history from the last ~1000 blocks will appear here
        </p>
      </div>
    );
  }

  return (
    <div className="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[800px]">
          <thead className="bg-gray-700/50 text-gray-400 text-sm">
            <tr>
              <th className="text-left p-4">Time</th>
              <th className="text-left p-4">Type</th>
              <th className="text-left p-4">Market</th>
              <th className="text-right p-4">Size</th>
              <th className="text-right p-4">Price</th>
              <th className="text-right p-4">PnL</th>
              <th className="text-right p-4">Fee</th>
              <th className="text-right p-4">Tx</th>
            </tr>
          </thead>
          <tbody>
            {trades.map((trade, idx) => {
              const isLong = trade.size > 0n;
              const absSize = isLong ? trade.size : -trade.size;
              const pnlNum = trade.pnl ? Number(formatUnits(trade.pnl, 18)) : null;
              const timeStr = trade.timestamp 
                ? new Date(trade.timestamp * 1000).toLocaleString()
                : 'Unknown';

              return (
                <tr key={`${trade.txHash}-${idx}`} className="border-t border-gray-700">
                  <td className="p-4 text-gray-400 text-sm whitespace-nowrap">
                    {timeStr}
                  </td>
                  <td className="p-4">
                    <span className={`px-2 py-1 rounded text-xs font-semibold ${
                      trade.type === 'open'
                        ? 'bg-blue-500/20 text-blue-400'
                        : 'bg-purple-500/20 text-purple-400'
                    }`}>
                      {trade.type === 'open' ? 'OPEN' : 'CLOSE'}
                    </span>
                  </td>
                  <td className="p-4">
                    <span className="flex items-center gap-2">
                      <span className={`px-1.5 py-0.5 rounded text-xs ${
                        isLong ? 'bg-lever-green/20 text-lever-green' : 'bg-lever-red/20 text-lever-red'
                      }`}>
                        {isLong ? 'L' : 'S'}
                      </span>
                      <span>Market #{trade.marketId}</span>
                    </span>
                  </td>
                  <td className="p-4 text-right whitespace-nowrap">
                    {Number(formatUnits(absSize, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 })}
                  </td>
                  <td className="p-4 text-right whitespace-nowrap">
                    {(Number(formatUnits(trade.price, 18)) * 100).toFixed(2)}¢
                  </td>
                  <td className={`p-4 text-right whitespace-nowrap font-medium ${
                    pnlNum === null ? 'text-gray-500' :
                    pnlNum >= 0 ? 'text-lever-green' : 'text-lever-red'
                  }`}>
                    {pnlNum === null ? '—' : `${pnlNum >= 0 ? '+' : ''}${pnlNum.toFixed(2)}`}
                  </td>
                  <td className="p-4 text-right text-gray-400 whitespace-nowrap">
                    {Number(formatUnits(trade.fee, 18)).toFixed(4)}
                  </td>
                  <td className="p-4 text-right">
                    <a
                      href={`https://testnet.bscscan.com/tx/${trade.txHash}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-blue-500 hover:underline text-sm"
                    >
                      View ↗
                    </a>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

interface Position {
  id: bigint;
  marketId: number;
  side: number; // 0 = Long, 1 = Short
  size: bigint;
  collateral: bigint;
  entryPrice: bigint;
  currentPrice: bigint;
  pnl: bigint;
}

export default function PortfolioPage() {
  const { address, isConnected } = useAccount();
  const contracts = CONTRACTS[97];

  const [positions, setPositions] = useState<Position[]>([]);
  const [lpBalance, setLpBalance] = useState<bigint | null>(null);
  const [sharePrice, setSharePrice] = useState<bigint | null>(null);
  const [pendingFees, setPendingFees] = useState<bigint | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'positions' | 'lp' | 'history'>('positions');

  // Fetch user data
  useEffect(() => {
    async function fetchData() {
      if (!address) {
        setIsLoading(false);
        return;
      }

      try {
        // Fetch all open positions using V4 getUserOpenPositions
        const openPositions = await client.readContract({
          address: contracts.LEDGER as `0x${string}`,
          abi: LEDGER_ABI,
          functionName: 'getUserOpenPositions',
          args: [address],
        }) as any[];

        // Get current prices for all markets with positions
        const marketIds = [...new Set(openPositions.map((p: any) => Number(p.marketId)))];
        const pricePromises = marketIds.map(async (marketId) => {
          const price = await client.readContract({
            address: contracts.PRICE_ENGINE as `0x${string}`,
            abi: PRICE_ENGINE_ABI,
            functionName: 'getMarkPrice',
            args: [BigInt(marketId)],
          });
          return { marketId, price: price as bigint };
        });
        const prices = await Promise.all(pricePromises);
        const priceMap = Object.fromEntries(prices.map(p => [p.marketId, p.price]));

        // Process positions with PnL
        const processedPositions = openPositions
          .filter((p: any) => p.isOpen && p.size > 0n)
          .map((pos: any) => {
            const marketId = Number(pos.marketId);
            const currentPrice = priceMap[marketId] || 0n;
            const size = BigInt(pos.size);
            const entryPrice = BigInt(pos.entryPrice);
            const collateral = BigInt(pos.collateral);
            const isLong = pos.side === 0;
            
            // Calculate PnL
            let pnl: bigint;
            if (isLong) {
              pnl = (size * (currentPrice - entryPrice)) / BigInt(1e18);
            } else {
              pnl = (size * (entryPrice - currentPrice)) / BigInt(1e18);
            }
            
            return {
              id: BigInt(pos.id),
              marketId,
              side: pos.side,
              size,
              collateral,
              entryPrice,
              currentPrice,
              pnl,
            };
          });

        const [lp, price, fees] = await Promise.all([
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'balanceOf',
            args: [address],
          }),
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'sharePrice',
          }),
          client.readContract({
            address: contracts.LP_POOL as `0x${string}`,
            abi: LP_POOL_ABI,
            functionName: 'pendingFeesOf',
            args: [address],
          }),
        ]);

        setPositions(processedPositions);
        setLpBalance(lp as bigint);
        setSharePrice(price as bigint);
        setPendingFees(fees as bigint);
      } catch (e) {
        console.error('Error fetching portfolio:', e);
      }
      setIsLoading(false);
    }

    fetchData();
    const interval = setInterval(fetchData, 10000);
    return () => clearInterval(interval);
  }, [address, contracts]);

  const totalLPValue = lpBalance && sharePrice
    ? Number(formatUnits(lpBalance, 18)) * Number(formatUnits(sharePrice, 18))
    : 0;

  const totalPendingFees = pendingFees ? Number(formatUnits(pendingFees, 18)) : 0;

  // Calculate total unrealized PnL from actual positions
  const totalUnrealizedPnL = positions.reduce((acc, pos) => {
    return acc + Number(formatUnits(pos.pnl, 18));
  }, 0);

  // Total collateral in positions
  const totalCollateral = positions.reduce((acc, pos) => {
    return acc + Number(formatUnits(pos.collateral, 18));
  }, 0);

  if (!isConnected) {
    return (
      <div className="px-6 py-8">
        <div className="text-center py-20">
          <h1 className="text-2xl font-bold mb-4">Portfolio</h1>
          <p className="text-gray-400 mb-8">Connect your wallet to view your positions</p>
        </div>
      </div>
    );
  }

  return (
    <div className="px-6 py-8">
      <h1 className="text-2xl font-bold mb-6">Portfolio</h1>

      {/* Account Summary */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <p className="text-gray-400 text-sm mb-1">Total Equity</p>
          <p className="text-2xl font-bold">
            ${(totalLPValue + totalCollateral + totalUnrealizedPnL).toLocaleString(undefined, { maximumFractionDigits: 2 })}
          </p>
        </div>
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <p className="text-gray-400 text-sm mb-1">Open Positions</p>
          <p className="text-2xl font-bold">{positions.length}</p>
        </div>
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <p className="text-gray-400 text-sm mb-1">Unrealized PnL</p>
          <p className={`text-2xl font-bold ${totalUnrealizedPnL >= 0 ? 'text-green-400' : 'text-red-400'}`}>
            {totalUnrealizedPnL >= 0 ? '+' : ''}{totalUnrealizedPnL.toFixed(2)} USDT
          </p>
        </div>
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <p className="text-gray-400 text-sm mb-1">LP Value</p>
          <p className="text-2xl font-bold">${totalLPValue.toLocaleString(undefined, { maximumFractionDigits: 2 })}</p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 mb-6 border-b border-gray-800 pb-2">
        {(['positions', 'lp', 'history'] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2 rounded-t-lg font-medium capitalize transition ${
              activeTab === tab
                ? 'bg-gray-800 text-white'
                : 'text-gray-400 hover:text-white'
            }`}
          >
            {tab === 'lp' ? 'LP Positions' : tab}
          </button>
        ))}
      </div>

      {/* Positions Tab */}
      {activeTab === 'positions' && (
        <div className="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
          {isLoading ? (
            <div className="p-8 text-center text-gray-400">Loading positions...</div>
          ) : positions.length === 0 ? (
            <div className="p-8 text-center">
              <p className="text-gray-400 mb-4">No open positions</p>
              <Link href="/" className="text-blue-500 hover:underline">
                Browse markets →
              </Link>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[800px]">
                <thead className="bg-gray-700/50 text-gray-400 text-sm">
                  <tr>
                    <th className="text-left p-4">Market</th>
                    <th className="text-left p-4">Side</th>
                    <th className="text-right p-4">Size</th>
                    <th className="text-right p-4">Entry Price</th>
                    <th className="text-right p-4">Mark Price</th>
                    <th className="text-right p-4">PnL</th>
                    <th className="text-right p-4">Collateral</th>
                    <th className="text-right p-4">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {positions.map((pos) => {
                    const isLong = pos.side === 0;
                    const pnlNum = Number(formatUnits(pos.pnl, 18));

                    return (
                      <tr key={pos.id.toString()} className="border-t border-gray-700">
                        <td className="p-4">
                          <div className="flex items-center gap-2">
                            <span>📊</span>
                            <span className="font-medium whitespace-nowrap">Market #{pos.marketId}</span>
                            <span className="text-xs text-gray-500">(#{pos.id.toString()})</span>
                          </div>
                        </td>
                        <td className="p-4">
                          <span className={`px-2 py-1 rounded text-xs font-semibold whitespace-nowrap ${
                            isLong ? 'bg-lever-green/20 text-lever-green' : 'bg-lever-red/20 text-lever-red'
                          }`}>
                            {isLong ? 'LONG' : 'SHORT'}
                          </span>
                        </td>
                        <td className="p-4 text-right whitespace-nowrap">
                          ${Number(formatUnits(pos.size, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 })}
                        </td>
                        <td className="p-4 text-right whitespace-nowrap">
                          {(Number(formatUnits(pos.entryPrice, 18)) * 100).toFixed(1)}¢
                        </td>
                        <td className="p-4 text-right whitespace-nowrap">
                          {(Number(formatUnits(pos.currentPrice, 18)) * 100).toFixed(1)}¢
                        </td>
                        <td className={`p-4 text-right font-medium whitespace-nowrap ${pnlNum >= 0 ? 'text-lever-green' : 'text-lever-red'}`}>
                          {pnlNum >= 0 ? '+' : ''}{pnlNum.toFixed(2)} USDT
                        </td>
                        <td className="p-4 text-right whitespace-nowrap">
                          {Number(formatUnits(pos.collateral, 18)).toFixed(2)} USDT
                        </td>
                        <td className="p-4 text-right">
                          <Link
                            href={`/markets/${pos.marketId}`}
                            className="text-blue-500 hover:underline text-sm whitespace-nowrap"
                          >
                            Manage
                          </Link>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* LP Positions Tab */}
      {activeTab === 'lp' && (
        <div className="bg-gray-800 rounded-xl border border-gray-700 p-6">
          {lpBalance && lpBalance > 0n ? (
            <div>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                <div>
                  <p className="text-gray-400 text-sm mb-1">LP Tokens</p>
                  <p className="text-xl font-bold">
                    {Number(formatUnits(lpBalance, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 })} lvUSDT
                  </p>
                </div>
                <div>
                  <p className="text-gray-400 text-sm mb-1">Value</p>
                  <p className="text-xl font-bold">${totalLPValue.toLocaleString(undefined, { maximumFractionDigits: 2 })}</p>
                </div>
                <div>
                  <p className="text-gray-400 text-sm mb-1">Share Price</p>
                  <p className="text-xl font-bold">
                    ${sharePrice ? Number(formatUnits(sharePrice, 18)).toFixed(4) : '—'}
                  </p>
                </div>
                <div>
                  <p className="text-gray-400 text-sm mb-1">Unclaimed Fees</p>
                  <p className={`text-xl font-bold ${totalPendingFees > 0 ? 'text-green-400' : 'text-gray-400'}`}>
                    {totalPendingFees > 0 ? '+' : ''}${totalPendingFees.toFixed(4)}
                  </p>
                </div>
              </div>
              <Link
                href="/lp"
                className="inline-block px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg font-medium"
              >
                Manage LP Position
              </Link>
            </div>
          ) : (
            <div className="text-center py-8">
              <p className="text-gray-400 mb-4">No LP positions</p>
              <Link href="/lp" className="text-blue-500 hover:underline">
                Provide liquidity →
              </Link>
            </div>
          )}
        </div>
      )}

      {/* History Tab */}
      {activeTab === 'history' && (
        <TradeHistoryTab address={address} contracts={contracts} />
      )}
    </div>
  );
}
