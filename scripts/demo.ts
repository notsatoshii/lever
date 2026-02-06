/**
 * LEVER Protocol - End-to-End Demo
 * 
 * This script:
 * 1. Deploys all contracts to BSC Testnet
 * 2. Creates a test market
 * 3. Opens a leveraged position
 * 4. Simulates price movement
 * 5. Shows PnL updating
 * 6. Closes position (or gets liquidated)
 * 
 * Run: npx ts-node scripts/demo.ts
 */

import { ethers } from 'ethers';
import * as dotenv from 'dotenv';
dotenv.config();

// Contract ABIs (minimal for demo)
const POSITION_LEDGER_ABI = [
  "constructor(address _collateralToken)",
  "function createMarket(address oracle, uint256 maxOI) returns (uint256)",
  "function setEngineAuthorization(address engine, bool authorized)",
  "function getPosition(address trader, uint256 marketId) view returns (tuple(uint256 marketId, int256 size, uint256 entryPrice, uint256 collateral, uint256 openTimestamp, uint256 lastFundingIndex, uint256 lastBorrowIndex))",
  "function getMarket(uint256 marketId) view returns (tuple(address oracle, uint256 totalLongOI, uint256 totalShortOI, uint256 maxOI, uint256 fundingIndex, uint256 borrowIndex, bool active))",
  "function getUnrealizedPnL(address trader, uint256 marketId, uint256 currentPrice) view returns (int256)",
  "function getOIImbalance(uint256 marketId) view returns (int256)",
];

const PRICE_ENGINE_ABI = [
  "constructor(address _ledger)",
  "function setKeeperAuthorization(address keeper, bool authorized)",
  "function configurePricing(uint256 marketId, address oracle, uint256 emaPeriod, uint256 maxDeviation, uint256 vammDepth)",
  "function updatePrice(uint256 marketId, uint256 newOraclePrice)",
  "function getMarkPrice(uint256 marketId) view returns (uint256)",
  "function getExecutionPrice(uint256 marketId, int256 sizeDelta) view returns (uint256)",
];

const RISK_ENGINE_ABI = [
  "constructor(address _ledger)",
  "function setRiskParams(uint256 marketId, uint256 im, uint256 mm, uint256 maxLev, uint256 baseRate, uint256 maxRate, uint256 optUtil, uint256 liqPenalty)",
  "function setLPCapital(uint256 marketId, uint256 capital)",
  "function checkInitialMargin(uint256 marketId, uint256 size, uint256 collateral, uint256 price) view returns (bool)",
  "function isLiquidatable(address trader, uint256 marketId, uint256 currentPrice) view returns (bool, uint256)",
  "function accrueInterest(uint256 marketId)",
];

const ROUTER_ABI = [
  "constructor(address _ledger, address _priceEngine, address _riskEngine, address _collateralToken)",
  "function openPosition(uint256 marketId, int256 sizeDelta, uint256 collateralAmount, uint256 maxPrice, uint256 minPrice)",
  "function closePosition(uint256 marketId, int256 sizeDelta, uint256 minPrice, uint256 maxPrice)",
  "function getPositionWithPnL(address trader, uint256 marketId) view returns (tuple(uint256 marketId, int256 size, uint256 entryPrice, uint256 collateral, uint256 openTimestamp, uint256 lastFundingIndex, uint256 lastBorrowIndex), int256, uint256, bool)",
];

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function decimals() view returns (uint8)",
];

// Bytecode would normally be imported from artifacts
// For demo, we'll use pre-deployed contracts or compile on the fly

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

const formatPrice = (price: bigint) => `${(Number(price) / 1e18 * 100).toFixed(2)}%`;
const formatAmount = (amount: bigint, decimals = 18) => `${(Number(amount) / 10**decimals).toFixed(2)}`;
const formatPnL = (pnl: bigint) => {
  const value = Number(pnl) / 1e18;
  return value >= 0 ? `+${value.toFixed(2)}` : `${value.toFixed(2)}`;
};

async function main() {
  console.log("\n🚀 LEVER Protocol - Live Demo\n");
  console.log("=".repeat(50));
  
  // Setup
  const rpcUrl = process.env.BSC_TESTNET_RPC || "https://data-seed-prebsc-1-s1.binance.org:8545";
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  
  if (!privateKey) {
    console.error("❌ Missing DEPLOYER_PRIVATE_KEY in .env");
    console.log("\nCreate a .env file with:");
    console.log("  DEPLOYER_PRIVATE_KEY=0x...");
    console.log("  BSC_TESTNET_RPC=https://data-seed-prebsc-1-s1.binance.org:8545");
    console.log("\nGet testnet BNB from: https://testnet.bnbchain.org/faucet-smart");
    process.exit(1);
  }
  
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log(`📍 Network: BSC Testnet (Chain ID 97)`);
  console.log(`👛 Wallet: ${wallet.address}`);
  
  const balance = await provider.getBalance(wallet.address);
  console.log(`💰 BNB Balance: ${ethers.formatEther(balance)} BNB`);
  
  if (balance < ethers.parseEther("0.05")) {
    console.error("\n❌ Insufficient BNB for gas. Get testnet BNB from faucet.");
    process.exit(1);
  }
  
  // Check if contracts are already deployed (use env vars)
  let ledgerAddress = process.env.LEDGER_ADDRESS;
  let priceEngineAddress = process.env.PRICE_ENGINE_ADDRESS;
  let riskEngineAddress = process.env.RISK_ENGINE_ADDRESS;
  let routerAddress = process.env.ROUTER_ADDRESS;
  
  // BSC Testnet USDT
  const USDT_ADDRESS = "0x337610d27c682E347C9cD60BD4b3b107C9d34dDd";
  const usdt = new ethers.Contract(USDT_ADDRESS, ERC20_ABI, wallet);
  
  const usdtBalance = await usdt.balanceOf(wallet.address);
  console.log(`💵 USDT Balance: ${formatAmount(usdtBalance)} USDT`);
  
  // If contracts not deployed, we need to compile and deploy
  // For quick demo, assume they're deployed and addresses are in env
  
  if (!ledgerAddress || !routerAddress) {
    console.log("\n⚠️  Contracts not deployed yet.");
    console.log("\nTo deploy, run:");
    console.log("  cd contracts");
    console.log("  forge script script/Deploy.s.sol --rpc-url $BSC_TESTNET_RPC --broadcast");
    console.log("\nThen set these in .env:");
    console.log("  LEDGER_ADDRESS=0x...");
    console.log("  PRICE_ENGINE_ADDRESS=0x...");
    console.log("  RISK_ENGINE_ADDRESS=0x...");
    console.log("  ROUTER_ADDRESS=0x...");
    
    console.log("\n📝 For now, running in SIMULATION MODE...\n");
    await runSimulation();
    return;
  }
  
  // Connect to deployed contracts
  const ledger = new ethers.Contract(ledgerAddress, POSITION_LEDGER_ABI, wallet);
  const priceEngine = new ethers.Contract(priceEngineAddress!, PRICE_ENGINE_ABI, wallet);
  const riskEngine = new ethers.Contract(riskEngineAddress!, RISK_ENGINE_ABI, wallet);
  const router = new ethers.Contract(routerAddress, ROUTER_ABI, wallet);
  
  console.log("\n📋 Contracts:");
  console.log(`  Ledger: ${ledgerAddress}`);
  console.log(`  PriceEngine: ${priceEngineAddress}`);
  console.log(`  Router: ${routerAddress}`);
  
  // Demo parameters
  const MARKET_ID = 0;
  const COLLATERAL = ethers.parseEther("100");  // 100 USDT
  const SIZE = ethers.parseEther("500");        // 500 size units (5x leverage at 50%)
  
  console.log("\n" + "=".repeat(50));
  console.log("📊 DEMO: Open Long Position, Price Goes Up, Take Profit");
  console.log("=".repeat(50));
  
  // Step 1: Check current price
  console.log("\n[1/6] Checking current market price...");
  const currentPrice = await priceEngine.getMarkPrice(MARKET_ID);
  console.log(`  Current probability: ${formatPrice(currentPrice)}`);
  
  // Step 2: Approve USDT
  console.log("\n[2/6] Approving USDT for Router...");
  const approveTx = await usdt.approve(routerAddress, COLLATERAL);
  await approveTx.wait();
  console.log(`  ✅ Approved ${formatAmount(COLLATERAL)} USDT`);
  
  // Step 3: Open long position
  console.log("\n[3/6] Opening LONG position...");
  console.log(`  Size: ${formatAmount(SIZE)} (long)`);
  console.log(`  Collateral: ${formatAmount(COLLATERAL)} USDT`);
  
  const openTx = await router.openPosition(
    MARKET_ID,
    SIZE,           // positive = long
    COLLATERAL,
    ethers.parseEther("0.6"),  // max price (slippage protection)
    0                          // min price (not used for longs)
  );
  await openTx.wait();
  console.log(`  ✅ Position opened! Tx: ${openTx.hash}`);
  
  // Step 4: Check position
  console.log("\n[4/6] Checking position...");
  const position = await ledger.getPosition(wallet.address, MARKET_ID);
  console.log(`  Size: ${formatAmount(position.size)} (${position.size > 0 ? 'LONG' : 'SHORT'})`);
  console.log(`  Entry Price: ${formatPrice(position.entryPrice)}`);
  console.log(`  Collateral: ${formatAmount(position.collateral)} USDT`);
  
  // Step 5: Simulate price increase (keeper updates price)
  console.log("\n[5/6] Simulating price increase (keeper update)...");
  const newPrice = ethers.parseEther("0.6");  // 50% -> 60%
  const updateTx = await priceEngine.updatePrice(MARKET_ID, newPrice);
  await updateTx.wait();
  console.log(`  ✅ Price updated to ${formatPrice(newPrice)}`);
  
  // Check unrealized PnL
  const pnl = await ledger.getUnrealizedPnL(wallet.address, MARKET_ID, newPrice);
  console.log(`  📈 Unrealized PnL: ${formatPnL(pnl)} USDT`);
  
  // Check if liquidatable
  const [isLiq, shortfall] = await riskEngine.isLiquidatable(wallet.address, MARKET_ID, newPrice);
  console.log(`  Liquidatable: ${isLiq ? '⚠️ YES' : '✅ NO'}`);
  
  // Step 6: Close position (take profit)
  console.log("\n[6/6] Closing position (taking profit)...");
  const closeTx = await router.closePosition(
    MARKET_ID,
    -SIZE,          // negative = close long
    ethers.parseEther("0.55"),  // min price (slippage protection)
    ethers.parseEther("1")      // max price (not used)
  );
  await closeTx.wait();
  console.log(`  ✅ Position closed! Tx: ${closeTx.hash}`);
  
  // Final balance
  const finalBalance = await usdt.balanceOf(wallet.address);
  const profit = finalBalance - usdtBalance;
  console.log(`\n📊 RESULTS:`);
  console.log(`  Initial USDT: ${formatAmount(usdtBalance)}`);
  console.log(`  Final USDT: ${formatAmount(finalBalance)}`);
  console.log(`  Profit: ${formatPnL(profit)} USDT`);
  
  console.log("\n✅ Demo complete! The protocol works.\n");
}

/**
 * Simulation mode - demonstrates the logic without actual deployment
 */
async function runSimulation() {
  console.log("=".repeat(50));
  console.log("🧪 SIMULATION MODE - Demonstrating Protocol Logic");
  console.log("=".repeat(50));
  
  // Simulated state
  let price = 0.5;  // 50% probability
  let position = {
    size: 0,
    entryPrice: 0,
    collateral: 0,
  };
  let balance = 1000;  // 1000 USDT
  
  const IM_RATE = 0.10;  // 10% initial margin
  const MM_RATE = 0.05;  // 5% maintenance margin
  const MAX_LEVERAGE = 10;
  
  console.log(`\n📊 Initial State:`);
  console.log(`  Balance: ${balance} USDT`);
  console.log(`  Price: ${(price * 100).toFixed(1)}%`);
  
  // Open position
  console.log(`\n[1] Opening LONG position...`);
  const collateral = 100;
  const size = 500;  // 5x leverage at 50%
  const notional = size * price;
  const leverage = notional / collateral;
  
  console.log(`  Collateral: ${collateral} USDT`);
  console.log(`  Size: ${size} units`);
  console.log(`  Notional: ${notional} USDT`);
  console.log(`  Leverage: ${leverage.toFixed(1)}x`);
  
  // Check margin
  const requiredMargin = notional * IM_RATE;
  console.log(`  Required margin (10%): ${requiredMargin} USDT`);
  console.log(`  Margin OK: ${collateral >= requiredMargin ? '✅ YES' : '❌ NO'}`);
  
  position = { size, entryPrice: price, collateral };
  balance -= collateral;
  
  console.log(`\n  ✅ Position opened!`);
  console.log(`  Remaining balance: ${balance} USDT`);
  
  // Price increases
  console.log(`\n[2] Price increases 50% → 60%...`);
  price = 0.6;
  
  const pnl = position.size * (price - position.entryPrice);
  const equity = position.collateral + pnl;
  const newNotional = position.size * price;
  const maintenanceMargin = newNotional * MM_RATE;
  
  console.log(`  New price: ${(price * 100).toFixed(1)}%`);
  console.log(`  PnL: ${pnl >= 0 ? '+' : ''}${pnl.toFixed(2)} USDT`);
  console.log(`  Equity: ${equity.toFixed(2)} USDT`);
  console.log(`  Maintenance margin: ${maintenanceMargin.toFixed(2)} USDT`);
  console.log(`  Liquidatable: ${equity < maintenanceMargin ? '⚠️ YES' : '✅ NO'}`);
  
  // Close position
  console.log(`\n[3] Closing position...`);
  balance += equity;
  const profit = equity - collateral;
  
  console.log(`  Returned: ${equity.toFixed(2)} USDT`);
  console.log(`  Profit: ${profit >= 0 ? '+' : ''}${profit.toFixed(2)} USDT`);
  console.log(`  ROI: ${((profit / collateral) * 100).toFixed(1)}%`);
  
  position = { size: 0, entryPrice: 0, collateral: 0 };
  
  console.log(`\n📊 Final State:`);
  console.log(`  Balance: ${balance.toFixed(2)} USDT`);
  console.log(`  Profit: ${profit.toFixed(2)} USDT (${((profit / 100) * 100).toFixed(1)}% on collateral)`);
  
  // Liquidation scenario
  console.log(`\n${"=".repeat(50)}`);
  console.log(`🔴 LIQUIDATION SCENARIO`);
  console.log(`${"=".repeat(50)}`);
  
  price = 0.5;
  position = { size: 900, entryPrice: 0.5, collateral: 50 };  // ~9x leverage
  
  console.log(`\n📊 Risky Position:`);
  console.log(`  Size: ${position.size} units (LONG)`);
  console.log(`  Entry: ${(position.entryPrice * 100).toFixed(1)}%`);
  console.log(`  Collateral: ${position.collateral} USDT`);
  console.log(`  Leverage: ${((position.size * position.entryPrice) / position.collateral).toFixed(1)}x`);
  
  // Price drops
  console.log(`\n[1] Price drops 50% → 44%...`);
  price = 0.44;
  
  const pnl2 = position.size * (price - position.entryPrice);
  const equity2 = position.collateral + pnl2;
  const newNotional2 = position.size * price;
  const maintenanceMargin2 = newNotional2 * MM_RATE;
  
  console.log(`  New price: ${(price * 100).toFixed(1)}%`);
  console.log(`  PnL: ${pnl2.toFixed(2)} USDT`);
  console.log(`  Equity: ${equity2.toFixed(2)} USDT`);
  console.log(`  Maintenance margin: ${maintenanceMargin2.toFixed(2)} USDT`);
  console.log(`  Liquidatable: ${equity2 < maintenanceMargin2 ? '🔴 YES' : '✅ NO'}`);
  
  if (equity2 < maintenanceMargin2) {
    console.log(`\n[2] ⚡ LIQUIDATION TRIGGERED!`);
    const penalty = position.collateral * 0.05;  // 5% penalty
    const liquidatorReward = penalty * 0.5;
    const insuranceFund = penalty * 0.4;
    const protocolFee = penalty * 0.1;
    
    console.log(`  Penalty (5%): ${penalty.toFixed(2)} USDT`);
    console.log(`  → Liquidator reward: ${liquidatorReward.toFixed(2)} USDT`);
    console.log(`  → Insurance fund: ${insuranceFund.toFixed(2)} USDT`);
    console.log(`  → Protocol fee: ${protocolFee.toFixed(2)} USDT`);
    console.log(`  Position closed, trader loses collateral.`);
  }
  
  console.log(`\n${"=".repeat(50)}`);
  console.log(`✅ Simulation complete!`);
  console.log(`\nThis demonstrates:`);
  console.log(`  • Leveraged position opening`);
  console.log(`  • PnL calculation based on price movement`);
  console.log(`  • Margin requirements and leverage limits`);
  console.log(`  • Liquidation triggers and penalty distribution`);
  console.log(`\nTo run with real contracts, deploy to BSC Testnet first.`);
  console.log(`${"=".repeat(50)}\n`);
}

main().catch(console.error);
