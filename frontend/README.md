# LEVER Protocol Frontend

React/Next.js frontend for LEVER Protocol - leveraged trading on prediction markets.

## Features

- 🔗 Wallet connection (MetaMask, WalletConnect)
- 📈 Open long/short positions with up to 10x leverage
- 📊 Real-time position tracking with PnL
- 💰 LP pool deposits/withdrawals
- 📉 Market stats (price, OI, funding rate)

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment

```bash
cp .env.example .env.local
```

Edit `.env.local` with:
- WalletConnect Project ID (get from https://cloud.walletconnect.com)
- Contract addresses (after deployment)

### 3. Run Development Server

```bash
npm run dev
```

Open http://localhost:3000

## After Contract Deployment

After running `forge script script/DeployTestnet.s.sol`, copy the addresses to your `.env.local`:

```env
NEXT_PUBLIC_USDT_ADDRESS=0x...
NEXT_PUBLIC_LEDGER_ADDRESS=0x...
NEXT_PUBLIC_PRICE_ENGINE_ADDRESS=0x...
NEXT_PUBLIC_FUNDING_ENGINE_ADDRESS=0x...
NEXT_PUBLIC_RISK_ENGINE_ADDRESS=0x...
NEXT_PUBLIC_ROUTER_ADDRESS=0x...
NEXT_PUBLIC_LP_POOL_ADDRESS=0x...
```

## Usage

### Trading

1. Connect wallet (BSC Testnet)
2. Select Long or Short
3. Enter collateral amount
4. Choose leverage (1-10x)
5. Click "Open Long" or "Open Short"

### LP Pool

1. Switch to LP Pool section
2. Enter USDT amount to deposit
3. Click "Deposit" to provide liquidity
4. Earn fees from traders

### Closing Positions

1. View your position in the Position panel
2. See real-time PnL
3. Click "Close Position" to exit

## Tech Stack

- **Next.js 14** - React framework
- **wagmi v2** - Ethereum hooks
- **viem** - TypeScript Ethereum library
- **ConnectKit** - Wallet connection UI
- **TailwindCSS** - Styling
- **Zustand** - State management

## Network

Currently configured for BSC Testnet (Chain ID 97).

To add mainnet support, update `src/config/wagmi.ts` and `src/config/contracts.ts`.

## Screenshots

(Add screenshots after deployment)

## Troubleshooting

**"Contracts not configured"**
→ Add contract addresses to `.env.local` and restart dev server

**"Chain not supported"**
→ Switch MetaMask to BSC Testnet

**Transaction fails**
→ Ensure you have testnet BNB for gas

## Development

```bash
# Run development server
npm run dev

# Build for production
npm run build

# Start production server
npm start

# Lint code
npm run lint
```
