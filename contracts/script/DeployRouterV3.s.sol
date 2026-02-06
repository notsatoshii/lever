// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {RouterV3} from "../src/RouterV3.sol";

interface IPositionLedger {
    function setEngineAuthorization(address engine, bool authorized) external;
}

interface ILPPool {
    function setAllocatorAuthorization(address allocator, bool authorized) external;
}

/**
 * @title DeployRouterV3
 * @notice Deploys RouterV3 with complete fee implementation
 */
contract DeployRouterV3 is Script {
    // Existing deployment addresses (BSC Testnet)
    address constant LEDGER = 0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c;
    address constant PRICE_ENGINE = 0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33;
    address constant RISK_ENGINE = 0x833D02521a41f175c389ec2A8c86F22E3de524DB;
    address constant FUNDING_ENGINE = 0xa6Ec543C82c564F9Cdb9a7e7682C68A43D1af802;
    address constant USDT = 0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58;
    address constant LP_POOL = 0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1;
    
    // Previous routers (for reference/deauthorization)
    address constant ROUTER_V1 = 0x510Ba12a9B32b2032f1A7B5C483afc1255B7436e;
    address constant ROUTER_V2 = 0xd04469ADb9617E3efd830137Fd42FdbB43B6bDfa;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   Deploying RouterV3 (Complete Fee Implementation)");
        console2.log("=======================================================");
        console2.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy RouterV3
        RouterV3 router = new RouterV3(
            LEDGER,
            PRICE_ENGINE,
            RISK_ENGINE,
            FUNDING_ENGINE,
            USDT,
            LP_POOL
        );
        console2.log("RouterV3 deployed at:", address(router));
        
        // Authorize new router on Ledger
        IPositionLedger ledger = IPositionLedger(LEDGER);
        ledger.setEngineAuthorization(address(router), true);
        console2.log("RouterV3 authorized on Ledger");
        
        // Authorize new router on LP Pool
        ILPPool lpPool = ILPPool(LP_POOL);
        lpPool.setAllocatorAuthorization(address(router), true);
        console2.log("RouterV3 authorized on LP Pool");
        
        // Deauthorize old routers
        ledger.setEngineAuthorization(ROUTER_V1, false);
        ledger.setEngineAuthorization(ROUTER_V2, false);
        lpPool.setAllocatorAuthorization(ROUTER_V1, false);
        lpPool.setAllocatorAuthorization(ROUTER_V2, false);
        console2.log("Old routers deauthorized");
        
        vm.stopBroadcast();
        
        console2.log("\n");
        console2.log("=======================================================");
        console2.log("   ROUTERV3 DEPLOYED!");
        console2.log("=======================================================");
        console2.log("New Router:", address(router));
        console2.log("");
        console2.log("Features:");
        console2.log("  - LP allocation/deallocation");
        console2.log("  - Trading fees (10 bps)");
        console2.log("  - Borrow fee charging");
        console2.log("  - Funding payment settlement");
        console2.log("");
        console2.log("UPDATE frontend/src/config/contracts.ts:");
        console2.log("  ROUTER:", address(router));
        console2.log("=======================================================");
    }
}
