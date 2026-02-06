import { http, createConfig } from 'wagmi';
import { bscTestnet } from 'wagmi/chains';
import { getDefaultConfig } from 'connectkit';

export const config = createConfig(
  getDefaultConfig({
    chains: [bscTestnet],
    transports: {
      [bscTestnet.id]: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
    },
    walletConnectProjectId: process.env.NEXT_PUBLIC_WC_PROJECT_ID || '',
    appName: 'LEVER Protocol',
    appDescription: 'Leveraged trading on prediction markets',
  })
);

declare module 'wagmi' {
  interface Register {
    config: typeof config;
  }
}
