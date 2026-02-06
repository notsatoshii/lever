'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState, useEffect } from 'react';
import { useAccount, useConnect, useDisconnect, useReadContract } from 'wagmi';
import { formatUnits } from 'viem';
import { CONTRACTS, USDT_ABI } from '@/config/contracts';

function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();
  const [mounted, setMounted] = useState(false);
  const contracts = CONTRACTS[97];

  // Fetch USDT balance
  const { data: usdtBalance } = useReadContract({
    address: contracts.USDT as `0x${string}`,
    abi: USDT_ABI,
    functionName: 'balanceOf',
    args: [address!],
    query: {
      enabled: !!address,
      refetchInterval: 10000,
    },
  });

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted) {
    return (
      <button className="px-4 py-2 bg-blue-500 hover:bg-blue-400 rounded-lg font-medium text-sm">
        Connect
      </button>
    );
  }

  const formattedBalance = usdtBalance 
    ? Number(formatUnits(usdtBalance as bigint, 18)).toFixed(2)
    : '0.00';

  if (isConnected) {
    return (
      <div className="flex items-center gap-3">
        <span className="text-gray-400 text-sm">{formattedBalance} USDT</span>
        <button
          onClick={() => disconnect()}
          className="px-3 py-1.5 bg-gray-700 hover:bg-gray-600 rounded-lg text-sm"
        >
          {address?.slice(0, 6)}...{address?.slice(-4)}
        </button>
      </div>
    );
  }

  return (
    <button
      onClick={() => connect({ connector: connectors[0] })}
      className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg font-medium text-sm"
    >
      Connect Wallet
    </button>
  );
}

export function Navigation() {
  const pathname = usePathname();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const tabs = [
    { name: 'Home', href: '/' },
    { name: 'Markets', href: '/markets' },
    { name: 'LP', href: '/lp' },
    { name: 'Portfolio', href: '/portfolio' },
  ];

  const isActive = (href: string) => {
    if (href === '/') return pathname === '/';
    return pathname.startsWith(href);
  };

  return (
    <header className="border-b border-gray-800 bg-gray-900/95 backdrop-blur sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 py-3">
        <div className="flex items-center justify-between">
          {/* Logo */}
          <Link href="/" className="flex items-center">
            <img 
              src="/lever-logo.svg" 
              alt="LEVER" 
              className="h-8 w-auto invert" 
              onError={(e) => {
                // Fallback if logo doesn't exist
                e.currentTarget.style.display = 'none';
                e.currentTarget.insertAdjacentHTML('afterend', '<span class="text-xl font-bold">LEVER</span>');
              }}
            />
          </Link>

          {/* Desktop Nav */}
          <nav className="hidden md:flex items-center gap-1">
            {tabs.map((tab) => (
              <Link
                key={tab.name}
                href={tab.href}
                className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                  isActive(tab.href)
                    ? 'text-white bg-gray-800'
                    : 'text-gray-400 hover:text-white hover:bg-gray-800/50'
                }`}
              >
                {tab.name}
              </Link>
            ))}
          </nav>

          {/* Right side */}
          <div className="flex items-center gap-3">
            <ConnectButton />
            
            {/* Mobile menu button */}
            <button
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              className="md:hidden p-2 text-gray-400 hover:text-white"
              aria-label="Toggle menu"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                {mobileMenuOpen ? (
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                ) : (
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
                )}
              </svg>
            </button>
          </div>
        </div>

        {/* Mobile Nav */}
        {mobileMenuOpen && (
          <nav className="md:hidden mt-3 pb-3 flex flex-col gap-1">
            {tabs.map((tab) => (
              <Link
                key={tab.name}
                href={tab.href}
                onClick={() => setMobileMenuOpen(false)}
                className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                  isActive(tab.href)
                    ? 'text-white bg-gray-800'
                    : 'text-gray-400 hover:text-white hover:bg-gray-800/50'
                }`}
              >
                {tab.name}
              </Link>
            ))}
          </nav>
        )}
      </div>
    </header>
  );
}
