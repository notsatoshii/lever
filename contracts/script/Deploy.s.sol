// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {PositionLedger} from "../src/PositionLedger.sol";
import {PriceEngine} from "../src/PriceEngine.sol";
import {FundingEngine} from "../src/FundingEngine.sol";
import {RiskEngine} from "../src/RiskEngine.sol";
import {LiquidationEngine} from "../src/LiquidationEngine.sol";
import {Router} from "../src/Router.sol";
import {LPPool} from "../src/LPPool.sol";

/**
 * @title Deploy Script for BSC Testnet
 * @notice Deploys all LEVER Protocol contracts
 * 
 * Usage:
 *   forge script script/Deploy.s.sol --rpc-url $BSC_TESTNET_RPC --broadcast --verify
 * 
 * Environment Variables:
 *   DEPLOYER_PRIVATE_KEY - Private key for deployment
 *   BSC_TESTNET_RPC - BSC Testnet RPC URL
 */
contract DeployScript is Script {
    // BSC Testnet addresses
    address constant USDT = 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd; // BSC Testnet USDT
    
    // Deployed contracts
    PositionLedger public ledger;
    PriceEngine public priceEngine;
    FundingEngine public fundingEngine;
    RiskEngine public riskEngine;
    LiquidationEngine public liquidationEngine;
    Router public router;
    LPPool public lpPool;
    
    // Config
    address public deployer;
    address public keeper;
    address public protocolFeeRecipient;
    
    function setUp() public {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        keeper = deployer; // Initially deployer is keeper
        protocolFeeRecipient = deployer; // Initially deployer receives fees
    }
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console2.log("Deploying LEVER Protocol to BSC Testnet...");
        console2.log("Deployer:", deployer);
        console2.log("USDT:", USDT);
        
        // 1. Deploy Position Ledger
        ledger = new PositionLedger(USDT);
        console2.log("PositionLedger:", address(ledger));
        
        // 2. Deploy Price Engine
        priceEngine = new PriceEngine(address(ledger));
        console2.log("PriceEngine:", address(priceEngine));
        
        // 3. Deploy Funding Engine
        fundingEngine = new FundingEngine(address(ledger));
        console2.log("FundingEngine:", address(fundingEngine));
        
        // 4. Deploy Risk Engine
        riskEngine = new RiskEngine(address(ledger));
        console2.log("RiskEngine:", address(riskEngine));
        
        // 5. Deploy LP Pool
        lpPool = new LPPool(USDT);
        console2.log("LPPool:", address(lpPool));
        
        // 6. Deploy Liquidation Engine
        liquidationEngine = new LiquidationEngine(
            address(ledger),
            USDT,
            protocolFeeRecipient,
            address(lpPool)
        );
        console2.log("LiquidationEngine:", address(liquidationEngine));
        
        // 7. Deploy Router
        router = new Router(
            address(ledger),
            address(priceEngine),
            address(riskEngine),
            USDT
        );
        console2.log("Router:", address(router));
        
        // ============ Configure Authorizations ============
        
        console2.log("\nConfiguring authorizations...");
        
        // Authorize engines on Position Ledger
        ledger.setEngineAuthorization(address(router), true);
        ledger.setEngineAuthorization(address(liquidationEngine), true);
        ledger.setEngineAuthorization(address(fundingEngine), true);
        ledger.setEngineAuthorization(address(riskEngine), true);
        
        // Authorize keepers
        priceEngine.setKeeperAuthorization(keeper, true);
        fundingEngine.setKeeperAuthorization(keeper, true);
        
        // Configure Liquidation Engine
        liquidationEngine.setEngines(address(riskEngine), address(priceEngine));
        
        // Authorize LP Pool allocators
        lpPool.setAllocatorAuthorization(address(router), true);
        lpPool.setAllocatorAuthorization(address(liquidationEngine), true);
        
        console2.log("Authorizations configured!");
        
        vm.stopBroadcast();
        
        // Print summary
        console2.log("\n============ DEPLOYMENT COMPLETE ============");
        console2.log("Network: BSC Testnet (Chain ID: 97)");
        console2.log("");
        console2.log("Contracts:");
        console2.log("  PositionLedger:    ", address(ledger));
        console2.log("  PriceEngine:       ", address(priceEngine));
        console2.log("  FundingEngine:     ", address(fundingEngine));
        console2.log("  RiskEngine:        ", address(riskEngine));
        console2.log("  LiquidationEngine: ", address(liquidationEngine));
        console2.log("  Router:            ", address(router));
        console2.log("  LPPool:            ", address(lpPool));
        console2.log("");
        console2.log("Next steps:");
        console2.log("  1. Create market: ledger.createMarket(oracleAddress, maxOI)");
        console2.log("  2. Configure pricing: priceEngine.configurePricing(...)");
        console2.log("  3. Configure funding: fundingEngine.configureFunding(...)");
        console2.log("  4. Configure risk: riskEngine.setRiskParams(...)");
        console2.log("  5. Set initial price: priceEngine.updatePrice(marketId, price)");
        console2.log("  6. Seed LP pool: lpPool.deposit(amount, receiver)");
        console2.log("=============================================");
    }
}

/**
 * @title Create Market Script
 * @notice Creates and configures a new market after deployment
 */
contract CreateMarketScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        // Get deployed addresses from env
        address ledgerAddr = vm.envAddress("LEDGER_ADDRESS");
        address priceEngineAddr = vm.envAddress("PRICE_ENGINE_ADDRESS");
        address fundingEngineAddr = vm.envAddress("FUNDING_ENGINE_ADDRESS");
        address riskEngineAddr = vm.envAddress("RISK_ENGINE_ADDRESS");
        address lpPoolAddr = vm.envAddress("LP_POOL_ADDRESS");
        address oracleAddr = vm.envAddress("ORACLE_ADDRESS");
        
        PositionLedger ledger = PositionLedger(ledgerAddr);
        PriceEngine priceEngine = PriceEngine(priceEngineAddr);
        FundingEngine fundingEngine = FundingEngine(fundingEngineAddr);
        RiskEngine riskEngine = RiskEngine(riskEngineAddr);
        LPPool lpPool = LPPool(lpPoolAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Create market
        uint256 maxOI = 1_000_000e18; // 1M max OI per side
        uint256 marketId = ledger.createMarket(oracleAddr, maxOI);
        console2.log("Created market ID:", marketId);
        
        // Configure price engine
        priceEngine.configurePricing(
            marketId,
            oracleAddr,
            3600,           // 1 hour EMA period
            500,            // 5% max deviation
            10_000_000e18   // vAMM depth
        );
        console2.log("Price engine configured");
        
        // Configure funding engine (1 hour periods)
        fundingEngine.configureFunding(
            marketId,
            0.000125e18,    // 0.0125% max funding per hour
            1 hours,        // 1 hour funding period
            100_000e18      // Imbalance threshold
        );
        console2.log("Funding engine configured (1h periods)");
        
        // Configure risk engine
        riskEngine.setRiskParams(
            marketId,
            1000,           // 10% initial margin
            500,            // 5% maintenance margin
            10,             // 10x max leverage
            0.05e18,        // 5% base borrow rate
            0.50e18,        // 50% max borrow rate
            0.8e18,         // 80% optimal utilization
            500             // 5% liquidation penalty
        );
        console2.log("Risk engine configured");
        
        // Set LP capital (read from pool)
        riskEngine.setLPCapital(marketId, lpPool.totalAssets());
        console2.log("LP capital set");
        
        vm.stopBroadcast();
        
        console2.log("\n============ MARKET CREATED ============");
        console2.log("Market ID:", marketId);
        console2.log("Max OI:", maxOI / 1e18, "tokens per side");
        console2.log("Max Leverage: 10x");
        console2.log("Initial Margin: 10%");
        console2.log("Maintenance Margin: 5%");
        console2.log("=========================================");
    }
}
