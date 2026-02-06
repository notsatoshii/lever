// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {PositionLedger} from "../src/PositionLedger.sol";
import {PriceEngine} from "../src/PriceEngine.sol";
import {FundingEngine} from "../src/FundingEngine.sol";
import {RiskEngine} from "../src/RiskEngine.sol";
import {LiquidationEngine} from "../src/LiquidationEngine.sol";
import {Router} from "../src/Router.sol";
import {LPPool} from "../src/LPPool.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";

/**
 * @title DeployTestnet
 * @notice Complete deployment script for BSC Testnet with MockUSDT
 * 
 * This script:
 * 1. Deploys MockUSDT and mints 10M tokens
 * 2. Deploys all protocol contracts
 * 3. Configures authorizations
 * 4. Creates a test market
 * 5. Seeds LP pool with 1M USDT
 * 
 * Usage:
 *   export PRIVATE_KEY=0x...
 *   forge script script/DeployTestnet.s.sol:DeployTestnet \
 *     --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
 *     --broadcast
 */
contract DeployTestnet is Script {
    // Deployed contracts
    MockUSDT public usdt;
    PositionLedger public ledger;
    PriceEngine public priceEngine;
    FundingEngine public fundingEngine;
    RiskEngine public riskEngine;
    LiquidationEngine public liquidationEngine;
    Router public router;
    LPPool public lpPool;
    InsuranceFund public insuranceFund;
    
    // Config
    address public deployer;
    
    // Amounts (18 decimals)
    uint256 constant TOTAL_MINT = 10_000_000e18;      // 10M USDT total
    uint256 constant LP_SEED = 1_000_000e18;          // 1M USDT to LP pool
    uint256 constant INSURANCE_SEED = 100_000e18;     // 100k USDT to insurance
    uint256 constant DEPLOYER_KEEP = 8_900_000e18;    // 8.9M USDT for testing
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   LEVER Protocol - BSC Testnet Deployment");
        console2.log("=======================================================");
        console2.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ Step 1: Deploy MockUSDT ============
        console2.log("\n[1/7] Deploying MockUSDT...");
        usdt = new MockUSDT();
        console2.log("  MockUSDT:", address(usdt));
        
        // Mint 10M USDT
        usdt.mint(deployer, TOTAL_MINT);
        console2.log("  Minted:", TOTAL_MINT / 1e18, "USDT");
        
        // ============ Step 2: Deploy Core Contracts ============
        console2.log("\n[2/7] Deploying core contracts...");
        
        ledger = new PositionLedger(address(usdt));
        console2.log("  PositionLedger:", address(ledger));
        
        priceEngine = new PriceEngine(address(ledger));
        console2.log("  PriceEngine:", address(priceEngine));
        
        fundingEngine = new FundingEngine(address(ledger));
        console2.log("  FundingEngine:", address(fundingEngine));
        
        riskEngine = new RiskEngine(address(ledger));
        console2.log("  RiskEngine:", address(riskEngine));
        
        // ============ Step 3: Deploy LP Pool & Insurance ============
        console2.log("\n[3/7] Deploying LP Pool & Insurance Fund...");
        
        lpPool = new LPPool(address(usdt));
        console2.log("  LPPool:", address(lpPool));
        
        insuranceFund = new InsuranceFund(address(usdt));
        console2.log("  InsuranceFund:", address(insuranceFund));
        
        // ============ Step 4: Deploy Liquidation Engine & Router ============
        console2.log("\n[4/7] Deploying Liquidation Engine & Router...");
        
        liquidationEngine = new LiquidationEngine(
            address(ledger),
            address(usdt),
            deployer,           // Protocol fee recipient
            address(lpPool)
        );
        console2.log("  LiquidationEngine:", address(liquidationEngine));
        
        router = new Router(
            address(ledger),
            address(priceEngine),
            address(riskEngine),
            address(usdt)
        );
        console2.log("  Router:", address(router));
        
        // ============ Step 5: Configure Authorizations ============
        console2.log("\n[5/7] Configuring authorizations...");
        
        // Ledger authorizations
        ledger.setEngineAuthorization(address(router), true);
        ledger.setEngineAuthorization(address(liquidationEngine), true);
        ledger.setEngineAuthorization(address(fundingEngine), true);
        ledger.setEngineAuthorization(address(riskEngine), true);
        console2.log("  Ledger authorizations set");
        
        // Liquidation engine setup
        liquidationEngine.setEngines(address(riskEngine), address(priceEngine));
        console2.log("  LiquidationEngine engines set");
        
        // Keeper authorizations (deployer is keeper for testing)
        priceEngine.setKeeperAuthorization(deployer, true);
        fundingEngine.setKeeperAuthorization(deployer, true);
        console2.log("  Keeper authorizations set");
        
        // LP Pool authorizations
        lpPool.setAllocatorAuthorization(address(router), true);
        lpPool.setAllocatorAuthorization(address(liquidationEngine), true);
        console2.log("  LP Pool authorizations set");
        
        // Insurance fund authorizations
        insuranceFund.setDepositorAuthorization(address(liquidationEngine), true);
        insuranceFund.setWithdrawerAuthorization(address(liquidationEngine), true);
        console2.log("  Insurance Fund authorizations set");
        
        // ============ Step 6: Create Test Market ============
        console2.log("\n[6/7] Creating test market...");
        
        uint256 marketId = ledger.createMarket(deployer, 10_000_000e18);  // 10M max OI
        console2.log("  Market ID:", marketId);
        
        // Configure price engine
        priceEngine.configurePricing(
            marketId,
            deployer,           // Oracle (deployer for testing)
            3600,               // 1 hour EMA period
            1000,               // 10% max deviation (relaxed for testing)
            100_000_000e18      // Large vAMM depth (low slippage for testing)
        );
        console2.log("  Price engine configured");
        
        // Configure funding engine (1 hour periods)
        fundingEngine.configureFunding(
            marketId,
            0.000125e18,        // 0.0125% max funding per hour
            1 hours,            // 1 hour funding period
            1_000_000e18        // Imbalance threshold
        );
        console2.log("  Funding engine configured (1h periods)");
        
        // Configure risk engine
        riskEngine.setRiskParams(
            marketId,
            1000,               // 10% initial margin
            500,                // 5% maintenance margin
            10,                 // 10x max leverage
            0.05e18,            // 5% base borrow rate
            0.50e18,            // 50% max borrow rate
            0.8e18,             // 80% optimal utilization
            500                 // 5% liquidation penalty
        );
        console2.log("  Risk engine configured");
        
        // Set initial price (50%)
        priceEngine.updatePrice(marketId, 0.5e18);
        console2.log("  Initial price set: 50%");
        
        // ============ Step 7: Seed LP Pool & Insurance ============
        console2.log("\n[7/7] Seeding LP Pool & Insurance Fund...");
        
        // Approve and seed LP Pool
        usdt.approve(address(lpPool), LP_SEED);
        lpPool.deposit(LP_SEED, deployer);
        console2.log("  LP Pool seeded:", LP_SEED / 1e18, "USDT");
        
        // Set LP capital in risk engine
        riskEngine.setLPCapital(marketId, LP_SEED);
        console2.log("  LP capital registered in RiskEngine");
        
        // Seed insurance fund
        usdt.approve(address(insuranceFund), INSURANCE_SEED);
        insuranceFund.deposit(INSURANCE_SEED);
        console2.log("  Insurance Fund seeded:", INSURANCE_SEED / 1e18, "USDT");
        
        vm.stopBroadcast();
        
        // ============ Print Summary ============
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   DEPLOYMENT COMPLETE!");
        console2.log("=======================================================");
        console2.log("");
        console2.log("Network: BSC Testnet (Chain ID 97)");
        console2.log("");
        console2.log("CONTRACTS:");
        console2.log("  MockUSDT:          ", address(usdt));
        console2.log("  PositionLedger:    ", address(ledger));
        console2.log("  PriceEngine:       ", address(priceEngine));
        console2.log("  FundingEngine:     ", address(fundingEngine));
        console2.log("  RiskEngine:        ", address(riskEngine));
        console2.log("  LiquidationEngine: ", address(liquidationEngine));
        console2.log("  Router:            ", address(router));
        console2.log("  LPPool:            ", address(lpPool));
        console2.log("  InsuranceFund:     ", address(insuranceFund));
        console2.log("");
        console2.log("MARKET:");
        console2.log("  Market ID:         ", marketId);
        console2.log("  Initial Price:      50%");
        console2.log("  Max Leverage:       10x");
        console2.log("  LP Capital:        ", LP_SEED / 1e18, "USDT");
        console2.log("  Insurance:         ", INSURANCE_SEED / 1e18, "USDT");
        console2.log("");
        console2.log("YOUR BALANCES:");
        console2.log("  USDT:              ", usdt.balanceOf(deployer) / 1e18, "USDT");
        console2.log("  LP Tokens:         ", lpPool.balanceOf(deployer) / 1e18, "lvUSDT");
        console2.log("");
        console2.log("COPY THESE TO .env:");
        console2.log("-------------------------------------------------------");
        console2.log("USDT_ADDRESS=", address(usdt));
        console2.log("LEDGER_ADDRESS=", address(ledger));
        console2.log("PRICE_ENGINE_ADDRESS=", address(priceEngine));
        console2.log("FUNDING_ENGINE_ADDRESS=", address(fundingEngine));
        console2.log("RISK_ENGINE_ADDRESS=", address(riskEngine));
        console2.log("LIQUIDATION_ENGINE_ADDRESS=", address(liquidationEngine));
        console2.log("ROUTER_ADDRESS=", address(router));
        console2.log("LP_POOL_ADDRESS=", address(lpPool));
        console2.log("INSURANCE_FUND_ADDRESS=", address(insuranceFund));
        console2.log("-------------------------------------------------------");
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("  1. Copy addresses to scripts/.env");
        console2.log("  2. Run: cd scripts && npx ts-node demo.ts");
        console2.log("  3. Or interact via BSCScan");
        console2.log("");
        console2.log("TO OPEN A POSITION:");
        console2.log("  1. Approve Router: usdt.approve(router, amount)");
        console2.log("  2. Open: router.openPosition(0, size, collateral, maxPrice, minPrice)");
        console2.log("");
        console2.log("=======================================================");
    }
}
