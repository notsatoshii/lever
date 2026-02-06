// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {PositionLedger} from "../src/PositionLedger.sol";
import {PriceEngine} from "../src/PriceEngine.sol";
import {FundingEngine} from "../src/FundingEngine.sol";
import {DynamicRiskEngine} from "../src/DynamicRiskEngine.sol";
import {LiquidationEngine} from "../src/LiquidationEngine.sol";
import {Router} from "../src/Router.sol";
import {LPPool} from "../src/LPPool.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {ADLEngine} from "../src/ADLEngine.sol";

/**
 * @title DeployTestnetV2
 * @notice Complete deployment with DYNAMIC risk parameters
 * 
 * Key differences from V1:
 * - Uses DynamicRiskEngine instead of static RiskEngine
 * - Connects Insurance Fund + LP Pool for feedback loop
 * - Includes ADL Engine for bad debt handling
 * - Dynamic leverage adjusts based on:
 *   - LP Pool utilization
 *   - Insurance Fund health
 *   - Global OI vs TVL
 */
contract DeployTestnetV2 is Script {
    // Deployed contracts
    MockUSDT public usdt;
    PositionLedger public ledger;
    PriceEngine public priceEngine;
    FundingEngine public fundingEngine;
    DynamicRiskEngine public riskEngine;
    LiquidationEngine public liquidationEngine;
    ADLEngine public adlEngine;
    Router public router;
    LPPool public lpPool;
    InsuranceFund public insuranceFund;
    
    // Config
    address public deployer;
    
    // Amounts (18 decimals)
    uint256 constant TOTAL_MINT = 10_000_000e18;      // 10M USDT total
    uint256 constant LP_SEED = 1_000_000e18;          // 1M USDT to LP pool
    uint256 constant INSURANCE_SEED = 100_000e18;     // 100k USDT to insurance
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   LEVER Protocol V2 - Dynamic Risk Engine");
        console2.log("=======================================================");
        console2.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ Step 1: Deploy MockUSDT ============
        console2.log("\n[1/8] Deploying MockUSDT...");
        usdt = new MockUSDT();
        usdt.mint(deployer, TOTAL_MINT);
        console2.log("  MockUSDT:", address(usdt));
        
        // ============ Step 2: Deploy Core Contracts ============
        console2.log("\n[2/8] Deploying core contracts...");
        
        ledger = new PositionLedger(address(usdt));
        console2.log("  PositionLedger:", address(ledger));
        
        priceEngine = new PriceEngine(address(ledger));
        console2.log("  PriceEngine:", address(priceEngine));
        
        fundingEngine = new FundingEngine(address(ledger));
        console2.log("  FundingEngine:", address(fundingEngine));
        
        // DYNAMIC Risk Engine
        riskEngine = new DynamicRiskEngine(address(ledger));
        console2.log("  DynamicRiskEngine:", address(riskEngine));
        
        // ============ Step 3: Deploy LP Pool & Insurance ============
        console2.log("\n[3/8] Deploying LP Pool & Insurance Fund...");
        
        lpPool = new LPPool(address(usdt));
        console2.log("  LPPool:", address(lpPool));
        
        insuranceFund = new InsuranceFund(address(usdt));
        console2.log("  InsuranceFund:", address(insuranceFund));
        
        // ============ Step 4: Connect Risk Engine to LP & Insurance ============
        console2.log("\n[4/8] Connecting DynamicRiskEngine feedback loop...");
        
        riskEngine.setLPPool(address(lpPool));
        riskEngine.setInsuranceFund(address(insuranceFund));
        console2.log("  Risk engine connected to LP Pool");
        console2.log("  Risk engine connected to Insurance Fund");
        
        // ============ Step 5: Deploy Liquidation & ADL Engines ============
        console2.log("\n[5/8] Deploying Liquidation & ADL Engines...");
        
        liquidationEngine = new LiquidationEngine(
            address(ledger),
            address(usdt),
            deployer,
            address(lpPool)
        );
        console2.log("  LiquidationEngine:", address(liquidationEngine));
        
        adlEngine = new ADLEngine(address(ledger));
        adlEngine.setPriceEngine(address(priceEngine));
        adlEngine.setInsuranceFund(address(insuranceFund));
        console2.log("  ADLEngine:", address(adlEngine));
        
        // ============ Step 6: Deploy Router ============
        console2.log("\n[6/8] Deploying Router...");
        
        router = new Router(
            address(ledger),
            address(priceEngine),
            address(riskEngine),
            address(usdt)
        );
        console2.log("  Router:", address(router));
        
        // ============ Step 7: Configure Authorizations ============
        console2.log("\n[7/8] Configuring authorizations...");
        
        // Ledger authorizations
        ledger.setEngineAuthorization(address(router), true);
        ledger.setEngineAuthorization(address(liquidationEngine), true);
        ledger.setEngineAuthorization(address(fundingEngine), true);
        ledger.setEngineAuthorization(address(riskEngine), true);
        ledger.setEngineAuthorization(address(adlEngine), true);
        
        // Liquidation engine setup
        liquidationEngine.setEngines(address(riskEngine), address(priceEngine));
        
        // Keeper authorizations
        priceEngine.setKeeperAuthorization(deployer, true);
        fundingEngine.setKeeperAuthorization(deployer, true);
        
        // LP Pool authorizations
        lpPool.setAllocatorAuthorization(address(router), true);
        lpPool.setAllocatorAuthorization(address(liquidationEngine), true);
        
        // Insurance fund authorizations
        insuranceFund.setDepositorAuthorization(address(liquidationEngine), true);
        insuranceFund.setWithdrawerAuthorization(address(liquidationEngine), true);
        insuranceFund.setWithdrawerAuthorization(address(adlEngine), true);
        
        console2.log("  All authorizations configured");
        
        // ============ Step 8: Create Market with Dynamic Params ============
        console2.log("\n[8/8] Creating market with dynamic risk params...");
        
        uint256 marketId = ledger.createMarket(deployer, 10_000_000e18);
        
        // Configure price engine
        priceEngine.configurePricing(
            marketId,
            deployer,
            3600,
            1000,
            100_000_000e18
        );
        
        // Configure funding engine
        fundingEngine.configureFunding(
            marketId,
            0.000125e18,
            1 hours,
            1_000_000e18
        );
        
        // Configure BASE risk params (these are the maximums)
        riskEngine.setBaseParams(
            marketId,
            500,                // 5% initial margin (allows up to 20x at full health)
            250,                // 2.5% maintenance margin
            20,                 // 20x BASE max leverage (will be reduced dynamically)
            0.05e18,            // 5% base borrow rate
            0.50e18,            // 50% max borrow rate
            0.8e18,             // 80% optimal utilization
            500                 // 5% liquidation penalty
        );
        
        // Configure DYNAMIC params
        riskEngine.setDynamicParams(
            marketId,
            50,                 // 50% weight to utilization
            50,                 // 50% weight to insurance health
            30,                 // Min leverage = 30% of base (6x at worst)
            200,                // Max OI = 200% of TVL
            1000                // Max OI = 10x insurance fund
        );
        
        console2.log("  Base max leverage: 20x");
        console2.log("  Effective leverage adjusts based on:");
        console2.log("    - LP utilization (50% weight)");
        console2.log("    - Insurance health (50% weight)");
        console2.log("  Min leverage: 6x (at critical levels)");
        
        // Set initial price
        priceEngine.updatePrice(marketId, 0.5e18);
        
        // ============ Seed Pools ============
        usdt.approve(address(lpPool), LP_SEED);
        lpPool.deposit(LP_SEED, deployer);
        
        usdt.approve(address(insuranceFund), INSURANCE_SEED);
        insuranceFund.deposit(INSURANCE_SEED);
        
        vm.stopBroadcast();
        
        // ============ Print Summary ============
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   DEPLOYMENT V2 COMPLETE!");
        console2.log("=======================================================");
        console2.log("");
        console2.log("CONTRACTS:");
        console2.log("  MockUSDT:           ", address(usdt));
        console2.log("  PositionLedger:     ", address(ledger));
        console2.log("  PriceEngine:        ", address(priceEngine));
        console2.log("  FundingEngine:      ", address(fundingEngine));
        console2.log("  DynamicRiskEngine:  ", address(riskEngine));
        console2.log("  LiquidationEngine:  ", address(liquidationEngine));
        console2.log("  ADLEngine:          ", address(adlEngine));
        console2.log("  Router:             ", address(router));
        console2.log("  LPPool:             ", address(lpPool));
        console2.log("  InsuranceFund:      ", address(insuranceFund));
        console2.log("");
        console2.log("DYNAMIC LEVERAGE:");
        console2.log("  Base max:           20x");
        console2.log("  Adjusts based on:   Utilization + Insurance Health");
        console2.log("  Minimum:            6x (at critical levels)");
        console2.log("");
        console2.log("=======================================================");
    }
}
