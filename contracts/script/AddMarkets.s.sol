// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

interface IPositionLedger {
    function createMarket(address oracle, uint256 maxOI) external returns (uint256);
}

interface IPriceEngine {
    function configurePricing(uint256 marketId, address oracle, uint256 emaPeriod, uint256 maxDeviation, uint256 vammDepth) external;
    function updatePrice(uint256 marketId, uint256 price) external;
}

interface IFundingEngine {
    function configureFunding(uint256 marketId, uint256 maxRate, uint256 period, uint256 threshold) external;
}

interface IRiskEngine {
    function setRiskParams(uint256 marketId, uint256 im, uint256 mm, uint256 maxLev, uint256 baseRate, uint256 maxRate, uint256 optUtil, uint256 penalty) external;
    function setLPCapital(uint256 marketId, uint256 capital) external;
}

/**
 * @title AddMarkets
 * @notice Adds 3 Polymarket-based markets to existing deployment
 * 
 * Markets:
 *   1. MicroStrategy Bitcoin Sale (50% - balanced market)
 *   2. Trump Deportations 250-500k (89.1% - high probability)
 *   3. GTA 6 $100+ Price (1% - low probability)
 */
contract AddMarkets is Script {
    // Existing deployment addresses (BSC Testnet)
    address constant LEDGER = 0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c;
    address constant PRICE_ENGINE = 0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33;
    address constant FUNDING_ENGINE = 0xa6Ec543C82c564F9Cdb9a7e7682C68A43D1af802;
    address constant RISK_ENGINE = 0x833D02521a41f175c389ec2A8c86F22E3de524DB;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   Adding Polymarket-Based Markets");
        console2.log("=======================================================");
        
        vm.startBroadcast(deployerPrivateKey);
        
        IPositionLedger ledger = IPositionLedger(LEDGER);
        IPriceEngine priceEngine = IPriceEngine(PRICE_ENGINE);
        IFundingEngine fundingEngine = IFundingEngine(FUNDING_ENGINE);
        IRiskEngine riskEngine = IRiskEngine(RISK_ENGINE);
        
        // ============ Market 1: MicroStrategy Bitcoin Sale ============
        console2.log("\n[1/3] Creating: MicroStrategy Bitcoin Sale");
        uint256 market1 = ledger.createMarket(deployer, 5_000_000e18);
        
        priceEngine.configurePricing(market1, deployer, 3600, 1000, 50_000_000e18);
        fundingEngine.configureFunding(market1, 0.000125e18, 1 hours, 500_000e18);
        riskEngine.setRiskParams(market1, 1000, 500, 10, 0.05e18, 0.50e18, 0.8e18, 500);
        riskEngine.setLPCapital(market1, 1_000_000e18);
        
        // Set price: 50% (balanced market)
        priceEngine.updatePrice(market1, 0.50e18);
        console2.log("  Market ID:", market1);
        console2.log("  Price: 50%");
        
        // ============ Market 2: Trump Deportations 250-500k ============
        console2.log("\n[2/3] Creating: Trump Deportations 250-500k");
        uint256 market2 = ledger.createMarket(deployer, 5_000_000e18);
        
        priceEngine.configurePricing(market2, deployer, 3600, 1000, 50_000_000e18);
        fundingEngine.configureFunding(market2, 0.000125e18, 1 hours, 500_000e18);
        riskEngine.setRiskParams(market2, 1000, 500, 10, 0.05e18, 0.50e18, 0.8e18, 500);
        riskEngine.setLPCapital(market2, 1_000_000e18);
        
        // Set price: 89.1% (from Polymarket)
        priceEngine.updatePrice(market2, 0.891e18);
        console2.log("  Market ID:", market2);
        console2.log("  Price: 89.1%");
        
        // ============ Market 3: GTA 6 $100+ ============
        console2.log("\n[3/3] Creating: GTA 6 $100+ Price");
        uint256 market3 = ledger.createMarket(deployer, 5_000_000e18);
        
        priceEngine.configurePricing(market3, deployer, 3600, 1000, 50_000_000e18);
        fundingEngine.configureFunding(market3, 0.000125e18, 1 hours, 500_000e18);
        riskEngine.setRiskParams(market3, 1000, 500, 10, 0.05e18, 0.50e18, 0.8e18, 500);
        riskEngine.setLPCapital(market3, 1_000_000e18);
        
        // Set price: 1.05% (from Polymarket)
        priceEngine.updatePrice(market3, 0.0105e18);
        console2.log("  Market ID:", market3);
        console2.log("  Price: 1.05%");
        
        vm.stopBroadcast();
        
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   MARKETS ADDED!");
        console2.log("=======================================================");
        console2.log("");
        console2.log("MARKET 1: MicroStrategy Bitcoin Sale");
        console2.log("  ID: 1, Price: 50%");
        console2.log("");
        console2.log("MARKET 2: Trump Deportations 250-500k");
        console2.log("  ID: 2, Price: 89.1%");
        console2.log("");
        console2.log("MARKET 3: GTA 6 $100+");
        console2.log("  ID: 3, Price: 1.05%");
        console2.log("=======================================================");
    }
}
