// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {RouterV2} from "../src/RouterV2.sol";

interface IPositionLedger {
    function setEngineAuthorization(address engine, bool authorized) external;
}

interface ILPPool {
    function setAllocatorAuthorization(address allocator, bool authorized) external;
}

/**
 * @title DeployRouterV2
 * @notice Deploys RouterV2 with LP allocation fix and updates authorizations
 */
contract DeployRouterV2 is Script {
    // Existing deployment addresses (BSC Testnet)
    address constant LEDGER = 0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c;
    address constant PRICE_ENGINE = 0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33;
    address constant RISK_ENGINE = 0x833D02521a41f175c389ec2A8c86F22E3de524DB;
    address constant USDT = 0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58;
    address constant LP_POOL = 0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1;
    address constant OLD_ROUTER = 0x510Ba12a9B32b2032f1A7B5C483afc1255B7436e;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   Deploying RouterV2 (LP Allocation Fix)");
        console2.log("=======================================================");
        console2.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new RouterV2
        RouterV2 router = new RouterV2(
            LEDGER,
            PRICE_ENGINE,
            RISK_ENGINE,
            USDT,
            LP_POOL
        );
        console2.log("RouterV2 deployed at:", address(router));
        
        // Authorize new router on Ledger
        IPositionLedger ledger = IPositionLedger(LEDGER);
        ledger.setEngineAuthorization(address(router), true);
        console2.log("RouterV2 authorized on Ledger");
        
        // Authorize new router on LP Pool for allocate/deallocate
        ILPPool lpPool = ILPPool(LP_POOL);
        lpPool.setAllocatorAuthorization(address(router), true);
        console2.log("RouterV2 authorized on LP Pool");
        
        // Deauthorize old router (optional - keep for safety)
        // ledger.setEngineAuthorization(OLD_ROUTER, false);
        // lpPool.setAllocatorAuthorization(OLD_ROUTER, false);
        
        vm.stopBroadcast();
        
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   ROUTERV2 DEPLOYED!");
        console2.log("=======================================================");
        console2.log("New Router:", address(router));
        console2.log("");
        console2.log("UPDATE frontend/src/config/contracts.ts:");
        console2.log("  ROUTER:", address(router));
        console2.log("=======================================================");
    }
}
