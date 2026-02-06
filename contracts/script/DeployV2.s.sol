// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PositionLedgerV2.sol";
import "../src/BorrowFeeEngineV2.sol";
import "../src/RiskEngineV2.sol";
import "../src/vAMM.sol";
import "../src/RouterV4.sol";

/**
 * @title DeployV2
 * @notice Deploys all V2 contracts for LEVER Protocol
 * @dev Run with: forge script script/DeployV2.s.sol --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployV2 is Script {
    
    // Existing deployed contracts (BSC Testnet)
    address constant USDT = 0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58;
    address constant PRICE_ENGINE_V2 = 0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC;
    address constant LP_POOL = 0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1;
    
    // Protocol wallets (using deployer for testnet - replace for mainnet)
    address PROTOCOL_TREASURY;
    address INSURANCE_FUND;
    
    // Deployed addresses (filled after deployment)
    address public positionLedgerV2;
    address public borrowFeeEngineV2;
    address public riskEngineV2;
    address public vAMMAddress;
    address public routerV4;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying V2 contracts with deployer:", deployer);
        
        // For testnet, use deployer as treasury/insurance (replace for mainnet)
        PROTOCOL_TREASURY = deployer;
        INSURANCE_FUND = deployer;
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy PositionLedgerV2
        PositionLedgerV2 ledger = new PositionLedgerV2(
            USDT,
            PROTOCOL_TREASURY,
            INSURANCE_FUND
        );
        positionLedgerV2 = address(ledger);
        console.log("PositionLedgerV2 deployed at:", positionLedgerV2);
        
        // 2. Deploy BorrowFeeEngineV2
        BorrowFeeEngineV2 borrowEngine = new BorrowFeeEngineV2(
            positionLedgerV2,
            PRICE_ENGINE_V2
        );
        borrowFeeEngineV2 = address(borrowEngine);
        console.log("BorrowFeeEngineV2 deployed at:", borrowFeeEngineV2);
        
        // 3. Deploy RiskEngineV2
        RiskEngineV2 riskEngine = new RiskEngineV2(
            PRICE_ENGINE_V2,
            positionLedgerV2,
            borrowFeeEngineV2
        );
        riskEngineV2 = address(riskEngine);
        console.log("RiskEngineV2 deployed at:", riskEngineV2);
        
        // 4. Deploy vAMM
        vAMM amm = new vAMM(PRICE_ENGINE_V2);
        vAMMAddress = address(amm);
        console.log("vAMM deployed at:", vAMMAddress);
        
        // 5. Deploy RouterV4
        RouterV4 router = new RouterV4(USDT);
        routerV4 = address(router);
        console.log("RouterV4 deployed at:", routerV4);
        
        // ============ Configure Connections ============
        
        // Configure RouterV4 with all V2 contracts
        router.setContracts(
            vAMMAddress,
            PRICE_ENGINE_V2,
            positionLedgerV2,
            riskEngineV2,
            borrowFeeEngineV2,
            LP_POOL
        );
        router.setTradingEnabled(true);
        console.log("RouterV4 configured");
        
        // Authorize RouterV4 in PositionLedgerV2
        ledger.setEngineAuthorization(routerV4, true);
        ledger.setEngineAuthorization(riskEngineV2, true);
        console.log("PositionLedgerV2 authorizations set");
        
        // Configure vAMM
        amm.setRouter(routerV4);
        amm.setKeeper(deployer); // TODO: Change to actual keeper
        console.log("vAMM configured");
        
        // Configure RiskEngineV2 with market configs
        // TODO: Add markets
        // riskEngine.setMarketConfig(0, 5e18, 1e16); // Market 0: 5x leverage, 1% vol
        
        // Initialize BorrowFeeEngine markets
        // TODO: Add markets
        // borrowEngine.initializeMarket(0);
        // borrowEngine.setGlobalOICap(1000000e18); // $1M cap
        
        vm.stopBroadcast();
        
        // Log summary
        console.log("\n=== Deployment Summary ===");
        console.log("PositionLedgerV2:", positionLedgerV2);
        console.log("BorrowFeeEngineV2:", borrowFeeEngineV2);
        console.log("RiskEngineV2:", riskEngineV2);
        console.log("vAMM:", vAMMAddress);
        console.log("RouterV4:", routerV4);
        console.log("\nNext steps:");
        console.log("1. Add market configs to RiskEngineV2");
        console.log("2. Initialize markets in BorrowFeeEngineV2");
        console.log("3. Initialize pools in vAMM");
        console.log("4. Update frontend with new addresses");
        console.log("5. Start JIT keeper for vAMM recentering");
    }
}
