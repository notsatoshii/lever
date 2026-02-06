'use client';

import { useState } from 'react';
import { useAccount, useConnect, useDisconnect } from 'wagmi';
import { TradingPanel } from '@/components/TradingPanel';
import { PositionPanel } from '@/components/PositionPanel';
import { MarketStats } from '@/components/MarketStats';
import { LPPanel } from '@/components/LPPanel';

function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected) {
    return (
      <button
        onClick={() => disconnect()}
        className="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg text-sm"
      >
        {address?.slice(0, 6)}...{address?.slice(-4)}
      </button>
    );
  }

  return (
    <button
      onClick={() => connect({ connector: connectors[0] })}
      className="px-4 py-2 bg-green-600 hover:bg-green-500 rounded-lg font-medium"
    >
      Connect Wallet
    </button>
  );
}

export default function Home() {
  const { isConnected } = useAccount();
  const [selectedMarket, setSelectedMarket] = useState(1); // Start with MicroStrategy market

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="border-b border-gray-800 px-6 py-4">
        <div className="max-w-7xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-2xl font-bold text-green-500">⚡ LEVER</span>
            <span className="text-sm text-gray-500">BSC Testnet</span>
          </div>
          <ConnectButton />
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-6 py-8">
        {!isConnected ? (
          <div className="text-center py-20">
            <h1 className="text-4xl font-bold mb-4">
              Leveraged Trading on Prediction Markets
            </h1>
            <p className="text-gray-400 mb-8 max-w-xl mx-auto">
              Trade up to 10x leverage on any prediction market outcome. 
              Connect your wallet to start trading on BSC Testnet.
            </p>
            <div className="mb-8">
              <ConnectButton />
            </div>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 max-w-3xl mx-auto text-left">
              <div className="bg-gray-800 p-4 rounded-lg">
                <div className="text-2xl mb-2">📈</div>
                <h3 className="font-semibold mb-1">Up to 10x Leverage</h3>
                <p className="text-gray-400 text-sm">Trade prediction outcomes with leverage</p>
              </div>
              <div className="bg-gray-800 p-4 rounded-lg">
                <div className="text-2xl mb-2">🎯</div>
                <h3 className="font-semibold mb-1">Real Polymarket Data</h3>
                <p className="text-gray-400 text-sm">Prices from live prediction markets</p>
              </div>
              <div className="bg-gray-800 p-4 rounded-lg">
                <div className="text-2xl mb-2">💰</div>
                <h3 className="font-semibold mb-1">Earn as LP</h3>
                <p className="text-gray-400 text-sm">Provide liquidity, earn trading fees</p>
              </div>
            </div>
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Left Column - Market Stats & Position */}
            <div className="lg:col-span-2 space-y-6">
              <MarketStats 
                selectedMarket={selectedMarket} 
                onSelectMarket={setSelectedMarket} 
              />
              <PositionPanel marketId={selectedMarket} />
            </div>

            {/* Right Column - Trading & LP */}
            <div className="space-y-6">
              <TradingPanel marketId={selectedMarket} />
              <LPPanel />
            </div>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-800 px-6 py-4 mt-8">
        <div className="max-w-7xl mx-auto text-center text-gray-500 text-sm">
          <p>LEVER Protocol - BSC Testnet Demo</p>
          <p className="mt-1">
            <a 
              href="https://github.com/notsatoshii/lever" 
              target="_blank" 
              rel="noopener noreferrer"
              className="text-green-500 hover:underline"
            >
              GitHub
            </a>
            {' • '}
            <a 
              href="https://testnet.bnbchain.org/faucet-smart" 
              target="_blank" 
              rel="noopener noreferrer"
              className="text-green-500 hover:underline"
            >
              Get Testnet BNB
            </a>
          </p>
        </div>
      </footer>
    </div>
  );
}
