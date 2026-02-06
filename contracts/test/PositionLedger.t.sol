// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {PositionLedger} from "../src/PositionLedger.sol";

contract PositionLedgerTest is Test {
    PositionLedger public ledger;
    
    address public owner = address(this);
    address public engine = address(0x1);
    address public trader1 = address(0x2);
    address public trader2 = address(0x3);
    address public oracle = address(0x4);
    address public usdc = address(0x5);
    
    uint256 public constant MAX_OI = 1_000_000e18;
    
    function setUp() public {
        ledger = new PositionLedger(usdc);
        ledger.setEngineAuthorization(engine, true);
        ledger.createMarket(oracle, MAX_OI);
    }
    
    // ============ Market Tests ============
    
    function test_CreateMarket() public {
        PositionLedger.Market memory market = ledger.getMarket(0);
        assertEq(market.oracle, oracle);
        assertEq(market.maxOI, MAX_OI);
        assertTrue(market.active);
        assertEq(market.fundingIndex, 1e18);
        assertEq(market.borrowIndex, 1e18);
    }
    
    function test_CreateMultipleMarkets() public {
        uint256 marketId = ledger.createMarket(address(0x10), 500_000e18);
        assertEq(marketId, 1);
        
        PositionLedger.Market memory market = ledger.getMarket(1);
        assertEq(market.oracle, address(0x10));
    }
    
    function test_RevertUnauthorizedMarketCreation() public {
        vm.prank(trader1);
        vm.expectRevert(PositionLedger.Unauthorized.selector);
        ledger.createMarket(oracle, MAX_OI);
    }
    
    // ============ Position Opening Tests ============
    
    function test_OpenLongPosition() public {
        vm.prank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        
        PositionLedger.Position memory pos = ledger.getPosition(trader1, 0);
        assertEq(pos.size, 100e18);
        assertEq(pos.entryPrice, 0.5e18);
        assertEq(pos.collateral, 50e6);
    }
    
    function test_OpenShortPosition() public {
        vm.prank(engine);
        ledger.openPosition(trader1, 0, -100e18, 0.5e18, 50e6);
        
        PositionLedger.Position memory pos = ledger.getPosition(trader1, 0);
        assertEq(pos.size, -100e18);
    }
    
    function test_OIUpdatesOnOpen() public {
        vm.startPrank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        ledger.openPosition(trader2, 0, -50e18, 0.5e18, 25e6);
        vm.stopPrank();
        
        PositionLedger.Market memory market = ledger.getMarket(0);
        assertEq(market.totalLongOI, 100e18);
        assertEq(market.totalShortOI, 50e18);
        
        assertEq(ledger.getOIImbalance(0), 50e18);
    }
    
    function test_RevertUnauthorizedOpen() public {
        vm.prank(trader1);
        vm.expectRevert(PositionLedger.Unauthorized.selector);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
    }
    
    function test_RevertInvalidSize() public {
        vm.prank(engine);
        vm.expectRevert(PositionLedger.InvalidSize.selector);
        ledger.openPosition(trader1, 0, 0, 0.5e18, 50e6);
    }
    
    function test_RevertInvalidPrice() public {
        vm.prank(engine);
        vm.expectRevert(PositionLedger.InvalidPrice.selector);
        ledger.openPosition(trader1, 0, 100e18, 0, 50e6);
        
        vm.prank(engine);
        vm.expectRevert(PositionLedger.InvalidPrice.selector);
        ledger.openPosition(trader1, 0, 100e18, 1.1e18, 50e6); // > 100%
    }
    
    function test_RevertExceedsMaxOI() public {
        vm.prank(engine);
        vm.expectRevert(PositionLedger.ExceedsMaxOI.selector);
        ledger.openPosition(trader1, 0, int256(MAX_OI + 1), 0.5e18, 50e6);
    }
    
    // ============ Position Modification Tests ============
    
    function test_AddToExistingLong() public {
        vm.startPrank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        ledger.openPosition(trader1, 0, 100e18, 0.6e18, 50e6);
        vm.stopPrank();
        
        PositionLedger.Position memory pos = ledger.getPosition(trader1, 0);
        assertEq(pos.size, 200e18);
        // Weighted average: (100 * 0.5 + 100 * 0.6) / 200 = 0.55
        assertEq(pos.entryPrice, 0.55e18);
        assertEq(pos.collateral, 100e6);
    }
    
    function test_PartialClose() public {
        vm.startPrank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        ledger.openPosition(trader1, 0, -50e18, 0.6e18, 0);
        vm.stopPrank();
        
        PositionLedger.Position memory pos = ledger.getPosition(trader1, 0);
        assertEq(pos.size, 50e18);
    }
    
    function test_FullClose() public {
        vm.startPrank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        ledger.openPosition(trader1, 0, -100e18, 0.6e18, 0);
        vm.stopPrank();
        
        PositionLedger.Position memory pos = ledger.getPosition(trader1, 0);
        assertEq(pos.size, 0);
    }
    
    function test_FlipDirection() public {
        vm.startPrank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        ledger.openPosition(trader1, 0, -150e18, 0.6e18, 30e6);
        vm.stopPrank();
        
        PositionLedger.Position memory pos = ledger.getPosition(trader1, 0);
        assertEq(pos.size, -50e18);
        assertEq(pos.entryPrice, 0.6e18);
    }
    
    // ============ Collateral Tests ============
    
    function test_AddCollateral() public {
        vm.startPrank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        ledger.modifyCollateral(trader1, 0, 25e6);
        vm.stopPrank();
        
        PositionLedger.Position memory pos = ledger.getPosition(trader1, 0);
        assertEq(pos.collateral, 75e6);
    }
    
    function test_RemoveCollateral() public {
        vm.startPrank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        ledger.modifyCollateral(trader1, 0, -25e6);
        vm.stopPrank();
        
        PositionLedger.Position memory pos = ledger.getPosition(trader1, 0);
        assertEq(pos.collateral, 25e6);
    }
    
    function test_RevertInsufficientCollateral() public {
        vm.startPrank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        vm.expectRevert(PositionLedger.InsufficientCollateral.selector);
        ledger.modifyCollateral(trader1, 0, -51e6);
        vm.stopPrank();
    }
    
    // ============ PnL Tests ============
    
    function test_LongProfitOnPriceIncrease() public {
        vm.prank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        
        // Price goes from 50% to 60%
        int256 pnl = ledger.getUnrealizedPnL(trader1, 0, 0.6e18);
        // PnL = 100 * (0.6 - 0.5) = 10
        assertEq(pnl, 10e18);
    }
    
    function test_LongLossOnPriceDecrease() public {
        vm.prank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        
        // Price goes from 50% to 40%
        int256 pnl = ledger.getUnrealizedPnL(trader1, 0, 0.4e18);
        // PnL = 100 * (0.4 - 0.5) = -10
        assertEq(pnl, -10e18);
    }
    
    function test_ShortProfitOnPriceDecrease() public {
        vm.prank(engine);
        ledger.openPosition(trader1, 0, -100e18, 0.5e18, 50e6);
        
        // Price goes from 50% to 40%
        int256 pnl = ledger.getUnrealizedPnL(trader1, 0, 0.4e18);
        // PnL = -100 * (0.4 - 0.5) = 10
        assertEq(pnl, 10e18);
    }
    
    // ============ Liquidation Tests ============
    
    function test_Liquidation() public {
        vm.startPrank(engine);
        ledger.openPosition(trader1, 0, 100e18, 0.5e18, 50e6);
        ledger.liquidatePosition(trader1, 0, address(0x100), 5e6);
        vm.stopPrank();
        
        PositionLedger.Position memory pos = ledger.getPosition(trader1, 0);
        assertEq(pos.size, 0);
        
        // OI should be reduced
        PositionLedger.Market memory market = ledger.getMarket(0);
        assertEq(market.totalLongOI, 0);
    }
    
    // ============ Index Update Tests ============
    
    function test_UpdateIndices() public {
        vm.prank(engine);
        ledger.updateIndices(0, 1.05e18, 1.02e18);
        
        PositionLedger.Market memory market = ledger.getMarket(0);
        assertEq(market.fundingIndex, 1.05e18);
        assertEq(market.borrowIndex, 1.02e18);
    }
    
    // ============ Fuzz Tests ============
    
    function testFuzz_OpenPosition(int256 size, uint256 price, uint256 collateral) public {
        // Bound inputs
        size = bound(size, -int256(MAX_OI), int256(MAX_OI));
        vm.assume(size != 0);
        price = bound(price, 1, 1e18);
        collateral = bound(collateral, 0, type(uint128).max);
        
        vm.prank(engine);
        ledger.openPosition(trader1, 0, size, price, collateral);
        
        PositionLedger.Position memory pos = ledger.getPosition(trader1, 0);
        assertEq(pos.size, size);
        assertEq(pos.entryPrice, price);
    }
}
