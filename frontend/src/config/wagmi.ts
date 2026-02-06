import { http, createConfig } from 'wagmi';
import { bscTestnet } from 'wagmi/chains';
import { injected } from 'wagmi/connectors';

// Simple config with just injected wallets (MetaMask, etc.)
// No WalletConnect to avoid SDK connection errors
export const config = createConfig({
  chains: [bscTestnet],
  connectors: [
    injected(),
  ],
  transports: {
    [bscTestnet.id]: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
  },
});

declare module 'wagmi' {
  interface Register {
    config: typeof config;
  }
}
