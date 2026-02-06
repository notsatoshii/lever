# LEVER Protocol - Quick Test Guide

## Fastest Path to Prove It Works

### Option 1: Simulation Mode (No deployment needed)

```bash
cd scripts
npm install
npx ts-node demo.ts
```

This runs a simulation showing:
- Opening leveraged positions
- PnL calculations  
- Liquidation scenarios
- All the math working correctly

### Option 2: Full BSC Testnet Deployment

#### Step 1: Get Testnet Funds

1. Create a new wallet or use existing
2. Get testnet BNB: https://testnet.bnbchain.org/faucet-smart
3. Get testnet USDT: (use a DEX on testnet or ask in Discord)

#### Step 2: Setup Environment

```bash
cd scripts
npm install
cp .env.example .env
# Edit .env with your private key
```

#### Step 3: Deploy Contracts

```bash
cd ../contracts
forge install
forge build

# Deploy all contracts
forge script script/Deploy.s.sol \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --broadcast \
  --private-key $DEPLOYER_PRIVATE_KEY
```

Copy the deployed addresses to your `.env` file.

#### Step 4: Run Demo

```bash
cd ../scripts
npx ts-node demo.ts
```

This will:
1. ✅ Connect to your deployed contracts
2. ✅ Open a real leveraged position
3. ✅ Update price (simulate market movement)
4. ✅ Show real PnL
5. ✅ Close position and realize profit

## What Gets Tested

| Feature | Simulation | Testnet |
|---------|------------|---------|
| Margin calculations | ✅ | ✅ |
| Leverage limits | ✅ | ✅ |
| PnL calculations | ✅ | ✅ |
| Liquidation triggers | ✅ | ✅ |
| Actual token transfers | ❌ | ✅ |
| Gas costs | ❌ | ✅ |
| Contract interactions | ❌ | ✅ |

## Expected Output

```
🚀 LEVER Protocol - Live Demo

📍 Network: BSC Testnet (Chain ID 97)
👛 Wallet: 0x...
💰 BNB Balance: 0.5 BNB
💵 USDT Balance: 1000.00 USDT

[1/6] Checking current market price...
  Current probability: 50.00%

[2/6] Approving USDT for Router...
  ✅ Approved 100.00 USDT

[3/6] Opening LONG position...
  Size: 500.00 (long)
  Collateral: 100.00 USDT
  ✅ Position opened!

[4/6] Checking position...
  Size: 500.00 (LONG)
  Entry Price: 50.00%
  Collateral: 100.00 USDT

[5/6] Simulating price increase...
  ✅ Price updated to 60.00%
  📈 Unrealized PnL: +50.00 USDT
  Liquidatable: ✅ NO

[6/6] Closing position...
  ✅ Position closed!

📊 RESULTS:
  Initial USDT: 1000.00
  Final USDT: 1050.00
  Profit: +50.00 USDT

✅ Demo complete! The protocol works.
```

## Troubleshooting

**"Insufficient BNB for gas"**
→ Get more from faucet: https://testnet.bnbchain.org/faucet-smart

**"Contracts not deployed"**
→ Run the forge deploy script first, then add addresses to .env

**"Transaction reverted"**
→ Check that you have enough USDT and it's approved for the Router

## Next Steps After Demo

1. **Try different scenarios:**
   - Open SHORT position (negative size)
   - Get liquidated (set low collateral, move price against)
   - Check funding rates after time passes

2. **Build a simple UI:**
   - Use the same ethers.js code
   - Add React/Next.js frontend
   - Connect wallet with wagmi

3. **Run keeper bot:**
   - cd keeper && npm install
   - Configure .env with deployed addresses
   - npm run dev
