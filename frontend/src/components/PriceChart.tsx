'use client';

import { useEffect, useRef, useState } from 'react';
import { createChart, IChartApi, ISeriesApi, CandlestickData, Time, CandlestickSeries } from 'lightweight-charts';
import { createPublicClient, http, formatUnits } from 'viem';
import { bscTestnet } from 'viem/chains';
import { CONTRACTS, PRICE_ENGINE_ABI } from '@/config/contracts';

const client = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

interface PriceChartProps {
  marketId: number;
  polymarketPrice?: number | null;
  marketQuestion?: string;
}

export function PriceChart({ marketId, polymarketPrice, marketQuestion }: PriceChartProps) {
  const chartContainerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const candleSeriesRef = useRef<ISeriesApi<'Candlestick'> | null>(null);
  const [currentPrice, setCurrentPrice] = useState<number>(0.5);
  const priceHistoryRef = useRef<CandlestickData<Time>[]>([]);
  const contracts = CONTRACTS[97];

  // Initialize chart
  useEffect(() => {
    if (!chartContainerRef.current) return;

    const chart = createChart(chartContainerRef.current, {
      layout: {
        background: { color: '#1f2937' },
        textColor: '#9ca3af',
      },
      grid: {
        vertLines: { color: '#374151' },
        horzLines: { color: '#374151' },
      },
      width: chartContainerRef.current.clientWidth,
      height: 300,
      timeScale: {
        timeVisible: true,
        secondsVisible: false,
        borderColor: '#374151',
      },
      rightPriceScale: {
        borderColor: '#374151',
        scaleMargins: {
          top: 0.1,
          bottom: 0.1,
        },
      },
      crosshair: {
        mode: 1,
        vertLine: {
          color: '#6b7280',
          width: 1,
          style: 2,
        },
        horzLine: {
          color: '#6b7280',
          width: 1,
          style: 2,
        },
      },
    });

    const candleSeries = chart.addSeries(CandlestickSeries, {
      upColor: '#22c55e',
      downColor: '#ef4444',
      borderUpColor: '#22c55e',
      borderDownColor: '#ef4444',
      wickUpColor: '#22c55e',
      wickDownColor: '#ef4444',
    });

    chartRef.current = chart;
    candleSeriesRef.current = candleSeries;

    // Generate initial historical data based on polymarket price or default
    const basePrice = polymarketPrice ?? 0.5;
    const now = Math.floor(Date.now() / 1000);
    const interval = 60; // 1 minute candles
    const historyLength = 60; // 1 hour of history
    
    // Work backwards from current price to create believable history
    let price = basePrice;
    const prices: number[] = [price];
    
    // Generate price path backwards (small random walk)
    for (let i = 0; i < historyLength; i++) {
      const variance = (Math.random() - 0.5) * 0.008; // ±0.4% per candle
      price = Math.min(0.95, Math.max(0.05, price - variance)); // Subtract to go backwards
      prices.unshift(price);
    }

    const initialData: CandlestickData<Time>[] = [];
    for (let i = 0; i < prices.length; i++) {
      const time = (now - (prices.length - 1 - i) * interval) as Time;
      const open = prices[i];
      const close = i < prices.length - 1 ? prices[i + 1] : open;
      const high = Math.max(open, close) + Math.random() * 0.003;
      const low = Math.min(open, close) - Math.random() * 0.003;

      initialData.push({
        time,
        open: open * 100,
        high: high * 100,
        low: low * 100,
        close: close * 100,
      });
    }

    priceHistoryRef.current = initialData;
    candleSeries.setData(initialData);
    setCurrentPrice(basePrice);

    // Handle resize
    const handleResize = () => {
      if (chartContainerRef.current) {
        chart.applyOptions({ width: chartContainerRef.current.clientWidth });
      }
    };
    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('resize', handleResize);
      chart.remove();
    };
  }, [polymarketPrice]);

  // Fetch and update price
  useEffect(() => {
    async function fetchPrice() {
      try {
        const price = await client.readContract({
          address: contracts.PRICE_ENGINE as `0x${string}`,
          abi: PRICE_ENGINE_ABI,
          functionName: 'getMarkPrice',
          args: [BigInt(marketId)],
        });
        const priceNum = Number(formatUnits(price as bigint, 18));
        setCurrentPrice(priceNum);

        // Update chart with new candle
        if (candleSeriesRef.current && priceHistoryRef.current.length > 0) {
          const now = Math.floor(Date.now() / 1000);
          const lastCandle = priceHistoryRef.current[priceHistoryRef.current.length - 1];
          const lastTime = lastCandle.time as number;
          const currentMinute = Math.floor(now / 60) * 60;

          if (currentMinute > lastTime) {
            // New candle
            const newCandle: CandlestickData<Time> = {
              time: currentMinute as Time,
              open: priceNum * 100,
              high: priceNum * 100,
              low: priceNum * 100,
              close: priceNum * 100,
            };
            priceHistoryRef.current.push(newCandle);
            candleSeriesRef.current.update(newCandle);
          } else {
            // Update current candle
            const updatedCandle: CandlestickData<Time> = {
              ...lastCandle,
              high: Math.max(lastCandle.high, priceNum * 100),
              low: Math.min(lastCandle.low, priceNum * 100),
              close: priceNum * 100,
            };
            priceHistoryRef.current[priceHistoryRef.current.length - 1] = updatedCandle;
            candleSeriesRef.current.update(updatedCandle);
          }
        }
      } catch (e) {
        console.error('Error fetching price:', e);
      }
    }

    fetchPrice();
    const interval = setInterval(fetchPrice, 5000); // Update every 5s
    return () => clearInterval(interval);
  }, [marketId, contracts]);

  return (
    <div className="bg-gray-800 rounded-xl p-4 border border-gray-700">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-lg font-semibold">Price Chart</h3>
        <div className="text-right">
          <span className="text-2xl font-bold text-green-500">
            {(currentPrice * 100).toFixed(2)}%
          </span>
          <span className="text-gray-400 text-sm ml-2">Mark Price</span>
        </div>
      </div>
      <div ref={chartContainerRef} className="w-full" />
    </div>
  );
}
