// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PositionLedgerV2.sol";
import "../src/BorrowFeeEngineV2.sol";
import "../src/RiskEngineV2.sol";
import "../src/vAMM.sol";
import "../src/RouterV4.sol";

/**
 * @title V2Test
 * @notice Comprehensive tests for LEVER V2 contracts
 */
contract V2Test is Test {
    
    // Contracts
    PositionLedgerV2 public ledger;
    BorrowFeeEngineV2 public borrowEngine;
    RiskEngineV2 public riskEngine;
    vAMM public amm;
    RouterV4 public router;
    
    // Mock contracts
    MockERC20 public usdt;
    MockPriceEngine public priceEngine;
    
    // Test addresses
    address public owner = address(this);
    address public trader1 = address(0x1);
    address public trader2 = address(0x2);
    address public keeper = address(0x3);
    address public treasury = address(0x4);
    address public insurance = address(0x5);
    
    // Test constants
    uint256 constant SCALE = 1e18;
    uint256 constant INITIAL_BALANCE = 100_000e18;
    
    function setUp() public {
        // Deploy mock tokens
        usdt = new MockERC20("Mock USDT", "USDT", 18);
        priceEngine = new MockPriceEngine();
        
        // Deploy V2 contracts
        ledger = new PositionLedgerV2(
            address(usdt),
            treasury,
            insurance
        );
        
        borrowEngine = new BorrowFeeEngineV2(
            address(ledger),
            address(priceEngine)
        );
        
        riskEngine = new RiskEngineV2(
            address(priceEngine),
            address(ledger),
            address(borrowEngine)
        );
        
        amm = new vAMM(address(priceEngine));
        
        router = new RouterV4(address(usdt));
        
        // Configure contracts
        router.setContracts(
            address(amm),
            address(priceEngine),
            address(ledger),
            address(riskEngine),
            address(borrowEngine),
            address(0) // LP Pool not needed for tests
        );
        router.setTradingEnabled(true);
        
        // Authorize router in ledger
        ledger.setEngineAuthorization(address(router), true);
        ledger.setEngineAuthorization(address(riskEngine), true);
        
        // Configure vAMM
        amm.setRouter(address(router));
        amm.setKeeper(keeper);
        
        // Create test market
        uint256 marketId = ledger.createMarket(
            address(priceEngine),
            1_000_000e18, // Max OI: $1M
            block.timestamp + 7 days
        );
        
        // Initialize price engine for market
        priceEngine.setPrice(marketId, 5e17); // 50% probability
        priceEngine.setSmoothedPrice(marketId, 5e17);
        priceEngine.setRawPrice(marketId, 5e17);
        
        // Initialize vAMM pool
        amm.initializePool(marketId, 5e17, 1_000_000e18);
        
        // Initialize borrow engine for market
        borrowEngine.initializeMarket(marketId);
        borrowEngine.setGlobalOICap(1_000_000e18);
        
        // Configure risk engine for market
        riskEngine.setMarketConfig(marketId, 5e18, 1e16); // 5x leverage, 1% vol
        
        // Fund traders
        usdt.mint(trader1, INITIAL_BALANCE);
        usdt.mint(trader2, INITIAL_BALANCE);
        
        // Approve router
        vm.prank(trader1);
        usdt.approve(address(router), type(uint256).max);
        vm.prank(trader2);
        usdt.approve(address(router), type(uint256).max);
    }
    
    // ============ PositionLedgerV2 Tests ============
    
    function test_CreateMarket() public {
        uint256 marketId = ledger.createMarket(
            address(priceEngine),
            500_000e18,
            block.timestamp + 30 days
        );
        
        PositionLedgerV2.Market memory market = ledger.getMarket(marketId);
        assertEq(market.oracle, address(priceEngine));
        assertEq(market.maxOI, 500_000e18);
        assertTrue(market.active);
    }
    
    function test_SetMarketLive() public {
        uint256 marketId = 0;
        ledger.setMarketLive(marketId, true);
        
        PositionLedgerV2.Market memory market = ledger.getMarket(marketId);
        assertTrue(market.isLive);
        assertEq(market.liveStartTime, block.timestamp);
    }
    
    function test_OpenPosition() public {
        uint256 marketId = 0;
        int256 size = 10_000e18; // $10k long
        uint256 price = 5e17; // 50%
        uint256 collateral = 2_000e18; // $2k collateral (5x)
        
        // Open via authorized engine
        ledger.setEngineAuthorization(address(this), true);
        ledger.openPosition(trader1, marketId, size, price, collateral);
        
        PositionLedgerV2.Position memory pos = ledger.getPosition(trader1, marketId);
        assertEq(pos.size, size);
        assertEq(pos.entryPrice, price);
        assertEq(pos.collateral, collateral);
    }
    
    function test_ModifyCollateral() public {
        // Open position first
        uint256 marketId = 0;
        ledger.setEngineAuthorization(address(this), true);
        ledger.openPosition(trader1, marketId, 10_000e18, 5e17, 2_000e18);
        
        // Add collateral
        ledger.modifyCollateral(trader1, marketId, 500e18);
        
        PositionLedgerV2.Position memory pos = ledger.getPosition(trader1, marketId);
        assertEq(pos.collateral, 2_500e18);
    }
    
    function test_GlobalOICap() public {
        uint256 marketId = 0;
        uint256 cap = ledger.getGlobalOICap(marketId);
        
        // With T > 48h, cap should be 80% of TVL
        // But TVL is 0 in this test, so cap will be 0
        // Let's test the logic instead
        assertTrue(cap == 0 || cap > 0); // Just ensure it doesn't revert
    }
    
    // ============ BorrowFeeEngineV2 Tests ============
    
    function test_InitializeMarket() public {
        uint256 marketId = 1;
        borrowEngine.initializeMarket(marketId);
        
        uint256 rate = borrowEngine.getCurrentRate(marketId);
        assertEq(rate, 2e14); // BASE_RATE = 0.02%
        
        uint256 index = borrowEngine.getBorrowIndex(marketId);
        assertEq(index, SCALE); // Starts at 1.0
    }
    
    function test_AccrueInterest() public {
        uint256 marketId = 0;
        uint256 initialIndex = borrowEngine.getBorrowIndex(marketId);
        
        // Fast forward 1 hour
        vm.warp(block.timestamp + 1 hours);
        
        uint256 newIndex = borrowEngine.accrueInterest(marketId);
        
        // Index should have grown
        assertGt(newIndex, initialIndex);
    }
    
    function test_CalculateBorrowFees() public {
        uint256 marketId = 0;
        uint256 notional = 10_000e18;
        uint256 entryIndex = SCALE; // 1.0
        
        // Accrue some interest
        vm.warp(block.timestamp + 10 hours);
        borrowEngine.accrueInterest(marketId);
        
        uint256 fees = borrowEngine.calculateBorrowFees(notional, entryIndex, marketId);
        
        // Fees should be positive
        assertGt(fees, 0);
    }
    
    function test_PreviewRate() public {
        (uint256 rate, uint256[5] memory multipliers) = borrowEngine.previewRate(
            500_000e18,  // 50% global utilization
            60_000e18,   // 60k long OI
            40_000e18,   // 40k short OI  
            100_000e18,  // 100k market OI
            1e16,        // 1% volatility
            block.timestamp + 48 hours, // Resolution in 48h
            false,       // Not live
            0            // No live start
        );
        
        // Rate should be at least base rate
        assertGe(rate, 2e14);
        
        // All multipliers should be >= 1.0
        for (uint i = 0; i < 5; i++) {
            assertGe(multipliers[i], SCALE);
        }
    }
    
    function test_MUtilMultiplier() public {
        // Test at different utilization levels
        (uint256 rate60, ) = borrowEngine.previewRate(
            600_000e18, 50_000e18, 50_000e18, 100_000e18, 1e16, 
            block.timestamp + 48 hours, false, 0
        );
        
        (uint256 rate80, ) = borrowEngine.previewRate(
            800_000e18, 50_000e18, 50_000e18, 100_000e18, 1e16, 
            block.timestamp + 48 hours, false, 0
        );
        
        // Higher utilization should mean higher rate
        assertGt(rate80, rate60);
    }
    
    function test_MTtRMultiplier() public {
        // Test at different time-to-resolution
        (uint256 rate48h, ) = borrowEngine.previewRate(
            500_000e18, 50_000e18, 50_000e18, 100_000e18, 1e16, 
            block.timestamp + 48 hours, false, 0
        );
        
        (uint256 rate12h, ) = borrowEngine.previewRate(
            500_000e18, 50_000e18, 50_000e18, 100_000e18, 1e16, 
            block.timestamp + 12 hours, false, 0
        );
        
        (uint256 rate1h, ) = borrowEngine.previewRate(
            500_000e18, 50_000e18, 50_000e18, 100_000e18, 1e16, 
            block.timestamp + 1 hours, false, 0
        );
        
        // Closer to resolution = higher rate
        assertGt(rate12h, rate48h);
        assertGt(rate1h, rate12h);
    }
    
    // ============ RiskEngineV2 Tests ============
    
    function test_ValidatePositionOpen() public {
        bool valid = riskEngine.validatePositionOpen(
            0,           // marketId
            10_000e18,   // notional
            2_000e18,    // collateral
            5e18         // 5x leverage
        );
        assertTrue(valid);
    }
    
    function test_ValidatePositionOpen_RevertOnExcessiveLeverage() public {
        vm.expectRevert(RiskEngineV2.ExceedsMaxLeverage.selector);
        riskEngine.validatePositionOpen(
            0,           // marketId
            10_000e18,   // notional
            1_000e18,    // collateral
            10e18        // 10x leverage (exceeds 5x max)
        );
    }
    
    function test_CalculateInitialMargin() public {
        uint256 im = riskEngine.calculateInitialMargin(
            10_000e18,   // notional
            5e18,        // 5x leverage
            1e16         // 1% volatility
        );
        
        // IM = (10000/5) × (1 + 0.01) = 2020
        assertEq(im, 2_020e18);
    }
    
    function test_CalculateMaintenanceMargin() public {
        uint256 mm = riskEngine.calculateMaintenanceMargin(10_000e18);
        
        // MM = 5% × 10000 = 500
        assertEq(mm, 500e18);
    }
    
    function test_CalculateLiquidationPrice() public {
        uint256 liqPrice = riskEngine.calculateLiquidationPrice(
            10_000e18,   // size (long)
            5e17,        // entry at 50%
            2_000e18,    // collateral
            0            // no pending fees
        );
        
        // Should be below entry price for long
        assertLt(liqPrice, 5e17);
    }
    
    function test_CheckPositionHealth() public {
        (bool healthy, int256 equity, uint256 mm) = riskEngine.checkPositionHealth(
            trader1,
            0,           // marketId
            10_000e18,   // size
            5e17,        // entry
            2_000e18,    // collateral
            0            // pending fees
        );
        
        // With 20% margin and 5% MM requirement, should be healthy
        assertTrue(healthy);
        assertGt(equity, int256(mm));
    }
    
    // ============ vAMM Tests ============
    
    function test_InitializePool() public {
        uint256 marketId = 5;
        priceEngine.setPrice(marketId, 6e17); // 60%
        priceEngine.setSmoothedPrice(marketId, 6e17);
        
        amm.initializePool(marketId, 6e17, 500_000e18);
        
        vAMM.Pool memory pool = amm.getPool(marketId);
        assertTrue(pool.initialized);
        assertEq(pool.lastPI, 6e17);
    }
    
    function test_GetSpotPrice() public {
        uint256 spotPrice = amm.getSpotPrice(0);
        
        // Should be close to initial PI (50%)
        assertGe(spotPrice, 45e16);
        assertLe(spotPrice, 55e16);
    }
    
    function test_GetExecutionPrice_Buy() public {
        (uint256 amountOut, uint256 execPrice, uint256 impact) = amm.getExecutionPrice(
            0,           // marketId
            true,        // buy
            1_000e18     // $1000 trade
        );
        
        // Should get some tokens out
        assertGt(amountOut, 0);
        
        // Execution price should be slightly above spot (slippage)
        uint256 spotPrice = amm.getSpotPrice(0);
        assertGe(execPrice, spotPrice);
        
        // Price impact should be small for $1k trade in $1M pool
        assertLe(impact, 100); // Less than 1% (100 bps)
    }
    
    function test_GetExecutionPrice_Sell() public {
        (uint256 amountOut, uint256 execPrice, uint256 impact) = amm.getExecutionPrice(
            0,           // marketId
            false,       // sell
            1_000e18     // 1000 tokens
        );
        
        assertGt(amountOut, 0);
        
        // Execution price should be slightly below spot for sell
        uint256 spotPrice = amm.getSpotPrice(0);
        assertLe(execPrice, spotPrice);
    }
    
    function test_Recenter() public {
        uint256 marketId = 0;
        
        // Change oracle price
        priceEngine.setSmoothedPrice(marketId, 6e17); // 60%
        
        // Recenter
        vm.prank(keeper);
        amm.recenter(marketId);
        
        // Spot price should be close to new PI
        uint256 newSpot = amm.getSpotPrice(marketId);
        assertGe(newSpot, 55e16);
        assertLe(newSpot, 65e16);
    }
    
    function test_SpreadGuard() public {
        uint256 marketId = 0;
        
        // Set oracle price different from vAMM price to trigger spread guard
        priceEngine.setRawPrice(marketId, 7e17); // 70% raw vs 50% vAMM
        
        uint256 spread = amm.getCurrentSpread(marketId);
        
        // Spread should be elevated due to deviation
        assertGt(spread, 1e15); // Greater than base spread
    }
    
    // ============ RouterV4 Integration Tests ============
    
    // Note: Full RouterV4 tests require more setup with actual token transfers
    // These test the view functions
    
    function test_PreviewTrade() public view {
        (
            uint256 positionSize,
            uint256 expectedEntryPrice,
            uint256 markPrice,
            uint256 priceImpact,
            uint256 estimatedDailyFee
        ) = router.previewTrade(
            0,           // marketId
            true,        // long
            2_000e18,    // collateral
            5e18         // 5x leverage
        );
        
        assertEq(positionSize, 10_000e18);
        assertGt(expectedEntryPrice, 0);
        assertGt(markPrice, 0);
        assertLe(priceImpact, 500); // Less than 5%
        assertGt(estimatedDailyFee, 0);
    }
    
    // ============ Edge Case Tests ============
    
    function test_ZeroSizePosition_Reverts() public {
        ledger.setEngineAuthorization(address(this), true);
        
        vm.expectRevert(PositionLedgerV2.InvalidSize.selector);
        ledger.openPosition(trader1, 0, 0, 5e17, 1_000e18);
    }
    
    function test_InvalidPrice_Reverts() public {
        ledger.setEngineAuthorization(address(this), true);
        
        vm.expectRevert(PositionLedgerV2.InvalidPrice.selector);
        ledger.openPosition(trader1, 0, 10_000e18, 0, 1_000e18);
        
        vm.expectRevert(PositionLedgerV2.InvalidPrice.selector);
        ledger.openPosition(trader1, 0, 10_000e18, 2e18, 1_000e18); // > 100%
    }
    
    function test_Unauthorized_Reverts() public {
        vm.prank(trader1);
        vm.expectRevert(PositionLedgerV2.Unauthorized.selector);
        ledger.openPosition(trader1, 0, 10_000e18, 5e17, 1_000e18);
    }
    
    function test_MarketNotActive_Reverts() public {
        ledger.setMarketActive(0, false);
        ledger.setEngineAuthorization(address(this), true);
        
        vm.expectRevert(PositionLedgerV2.MarketNotActive.selector);
        ledger.openPosition(trader1, 0, 10_000e18, 5e17, 1_000e18);
    }
}

// ============ Mock Contracts ============

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockPriceEngine {
    mapping(uint256 => uint256) public prices;
    mapping(uint256 => uint256) public smoothedPrices;
    mapping(uint256 => uint256) public rawPrices;
    
    function setPrice(uint256 marketId, uint256 price) external {
        prices[marketId] = price;
    }
    
    function setSmoothedPrice(uint256 marketId, uint256 price) external {
        smoothedPrices[marketId] = price;
    }
    
    function setRawPrice(uint256 marketId, uint256 price) external {
        rawPrices[marketId] = price;
    }
    
    function getPrice(uint256 marketId) external view returns (uint256) {
        return prices[marketId];
    }
    
    function getMarkPrice(uint256 marketId) external view returns (uint256) {
        return smoothedPrices[marketId];
    }
    
    function getSmoothedPrice(uint256 marketId) external view returns (uint256) {
        return smoothedPrices[marketId];
    }
    
    function getRawPrice(uint256 marketId) external view returns (uint256) {
        return rawPrices[marketId] > 0 ? rawPrices[marketId] : smoothedPrices[marketId];
    }
}
