'use client';

import { ConnectKitButton } from 'connectkit';
import { useAccount } from 'wagmi';
import { TradingPanel } from '@/components/TradingPanel';
import { PositionPanel } from '@/components/PositionPanel';
import { MarketStats } from '@/components/MarketStats';
import { LPPanel } from '@/components/LPPanel';

export default function Home() {
  const { isConnected } = useAccount();

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="border-b border-gray-800 px-6 py-4">
        <div className="max-w-7xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-2xl font-bold text-lever-green">⚡ LEVER</span>
            <span className="text-sm text-gray-500">Testnet</span>
          </div>
          <ConnectKitButton />
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
            <ConnectKitButton />
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Left Column - Market Stats & Position */}
            <div className="lg:col-span-2 space-y-6">
              <MarketStats />
              <PositionPanel />
            </div>

            {/* Right Column - Trading & LP */}
            <div className="space-y-6">
              <TradingPanel />
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
              className="text-lever-green hover:underline"
            >
              GitHub
            </a>
            {' • '}
            <a 
              href="https://testnet.bnbchain.org/faucet-smart" 
              target="_blank" 
              rel="noopener noreferrer"
              className="text-lever-green hover:underline"
            >
              Get Testnet BNB
            </a>
          </p>
        </div>
      </footer>
    </div>
  );
}
