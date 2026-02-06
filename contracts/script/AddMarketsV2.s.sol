// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

interface IPositionLedger {
    function createMarket(address oracle, uint256 maxOI) external returns (uint256);
    function setMarketActive(uint256 marketId, bool active) external;
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
 * @title AddMarketsV2
 * @notice Adds 5 new Polymarket-based markets (Markets 4-8)
 * 
 * Top 5 by volume (excluding existing markets):
 *   4. US Revenue <$100b (83.6%)
 *   5. Tariffs >$250b (1.8%)
 *   6. US Revenue $500b-$1t (0.6%)
 *   7. US Revenue $100b-$200b (6.45%)
 *   8. Trump Deport <250k (5.15%)
 */
contract AddMarketsV2 is Script {
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
        console2.log("   Adding 5 New Polymarket-Based Markets (V2)");
        console2.log("=======================================================");
        
        vm.startBroadcast(deployerPrivateKey);
        
        IPositionLedger ledger = IPositionLedger(LEDGER);
        IPriceEngine priceEngine = IPriceEngine(PRICE_ENGINE);
        IFundingEngine fundingEngine = IFundingEngine(FUNDING_ENGINE);
        IRiskEngine riskEngine = IRiskEngine(RISK_ENGINE);
        
        // ============ Market 4: US Revenue <$100b ============
        console2.log("\n[1/5] Creating: US Revenue <$100b in 2025");
        uint256 market4 = ledger.createMarket(deployer, 5_000_000e18);
        
        priceEngine.configurePricing(market4, deployer, 3600, 1000, 50_000_000e18);
        fundingEngine.configureFunding(market4, 0.000125e18, 1 hours, 500_000e18);
        riskEngine.setRiskParams(market4, 1000, 500, 10, 0.05e18, 0.50e18, 0.8e18, 500);
        riskEngine.setLPCapital(market4, 1_000_000e18);
        
        // Set price: 83.6% (from Polymarket)
        priceEngine.updatePrice(market4, 0.836e18);
        console2.log("  Market ID:", market4);
        console2.log("  Price: 83.6%");
        
        // ============ Market 5: Tariffs >$250b ============
        console2.log("\n[2/5] Creating: Tariffs >$250b in 2025");
        uint256 market5 = ledger.createMarket(deployer, 5_000_000e18);
        
        priceEngine.configurePricing(market5, deployer, 3600, 1000, 50_000_000e18);
        fundingEngine.configureFunding(market5, 0.000125e18, 1 hours, 500_000e18);
        riskEngine.setRiskParams(market5, 1000, 500, 10, 0.05e18, 0.50e18, 0.8e18, 500);
        riskEngine.setLPCapital(market5, 1_000_000e18);
        
        // Set price: 1.8% (from Polymarket)
        priceEngine.updatePrice(market5, 0.018e18);
        console2.log("  Market ID:", market5);
        console2.log("  Price: 1.8%");
        
        // ============ Market 6: US Revenue $500b-$1t ============
        console2.log("\n[3/5] Creating: US Revenue $500b-$1t in 2025");
        uint256 market6 = ledger.createMarket(deployer, 5_000_000e18);
        
        priceEngine.configurePricing(market6, deployer, 3600, 1000, 50_000_000e18);
        fundingEngine.configureFunding(market6, 0.000125e18, 1 hours, 500_000e18);
        riskEngine.setRiskParams(market6, 1000, 500, 10, 0.05e18, 0.50e18, 0.8e18, 500);
        riskEngine.setLPCapital(market6, 1_000_000e18);
        
        // Set price: 0.6% (from Polymarket)
        priceEngine.updatePrice(market6, 0.006e18);
        console2.log("  Market ID:", market6);
        console2.log("  Price: 0.6%");
        
        // ============ Market 7: US Revenue $100b-$200b ============
        console2.log("\n[4/5] Creating: US Revenue $100b-$200b in 2025");
        uint256 market7 = ledger.createMarket(deployer, 5_000_000e18);
        
        priceEngine.configurePricing(market7, deployer, 3600, 1000, 50_000_000e18);
        fundingEngine.configureFunding(market7, 0.000125e18, 1 hours, 500_000e18);
        riskEngine.setRiskParams(market7, 1000, 500, 10, 0.05e18, 0.50e18, 0.8e18, 500);
        riskEngine.setLPCapital(market7, 1_000_000e18);
        
        // Set price: 6.45% (from Polymarket)
        priceEngine.updatePrice(market7, 0.0645e18);
        console2.log("  Market ID:", market7);
        console2.log("  Price: 6.45%");
        
        // ============ Market 8: Trump Deport <250k ============
        console2.log("\n[5/5] Creating: Trump Deport <250k");
        uint256 market8 = ledger.createMarket(deployer, 5_000_000e18);
        
        priceEngine.configurePricing(market8, deployer, 3600, 1000, 50_000_000e18);
        fundingEngine.configureFunding(market8, 0.000125e18, 1 hours, 500_000e18);
        riskEngine.setRiskParams(market8, 1000, 500, 10, 0.05e18, 0.50e18, 0.8e18, 500);
        riskEngine.setLPCapital(market8, 1_000_000e18);
        
        // Set price: 5.15% (from Polymarket)
        priceEngine.updatePrice(market8, 0.0515e18);
        console2.log("  Market ID:", market8);
        console2.log("  Price: 5.15%");
        
        vm.stopBroadcast();
        
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   5 NEW MARKETS ADDED!");
        console2.log("=======================================================");
        console2.log("");
        console2.log("MARKET 4: US Revenue <$100b");
        console2.log("  Polymarket: will-the-us-collect-less-than-100b-in-revenue-in-2025");
        console2.log("  Price: 83.6%");
        console2.log("");
        console2.log("MARKET 5: Tariffs >$250b");
        console2.log("  Polymarket: will-tariffs-generate-250b-in-2025");
        console2.log("  Price: 1.8%");
        console2.log("");
        console2.log("MARKET 6: US Revenue $500b-$1t");
        console2.log("  Polymarket: will-the-us-collect-between-500b-and-1t-in-revenue-in-2025");
        console2.log("  Price: 0.6%");
        console2.log("");
        console2.log("MARKET 7: US Revenue $100b-$200b");
        console2.log("  Polymarket: will-the-us-collect-between-100b-and-200b-in-revenue-in-2025");
        console2.log("  Price: 6.45%");
        console2.log("");
        console2.log("MARKET 8: Trump Deport <250k");
        console2.log("  Polymarket: will-trump-deport-less-than-250000");
        console2.log("  Price: 5.15%");
        console2.log("=======================================================");
    }
}
