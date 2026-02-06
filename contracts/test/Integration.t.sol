// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {PositionLedger} from "../src/PositionLedger.sol";
import {PriceEngine} from "../src/PriceEngine.sol";
import {FundingEngine} from "../src/FundingEngine.sol";
import {RiskEngine} from "../src/RiskEngine.sol";
import {LiquidationEngine} from "../src/LiquidationEngine.sol";
import {Router} from "../src/Router.sol";

/**
 * @title Integration Tests
 * @notice Full flow tests for the LEVER protocol on BSC with USDT
 */
contract IntegrationTest is Test {
    // Contracts
    PositionLedger public ledger;
    PriceEngine public priceEngine;
    FundingEngine public fundingEngine;
    RiskEngine public riskEngine;
    LiquidationEngine public liquidationEngine;
    Router public router;
    
    // Mock USDT (18 decimals on BSC)
    MockERC20 public usdt;
    
    // Addresses
    address public owner = address(this);
    address public keeper = address(0x100);
    address public trader1 = address(0x1);
    address public trader2 = address(0x2);
    address public liquidator = address(0x3);
    address public lpPool = address(0x4);
    address public oracle = address(0x5);
    address public protocolFeeRecipient = address(0x6);
    
    // Market params
    uint256 public constant MARKET_ID = 0;
    uint256 public constant MAX_OI = 1_000_000e18;
    uint256 public constant LP_CAPITAL = 500_000e18; // 500k USDT
    
    // Risk params
    uint256 public constant IM_BPS = 1000;      // 10%
    uint256 public constant MM_BPS = 500;       // 5%
    uint256 public constant MAX_LEVERAGE = 10;
    uint256 public constant BASE_BORROW = 0.05e18;  // 5% APR
    uint256 public constant MAX_BORROW = 0.50e18;   // 50% APR
    uint256 public constant OPTIMAL_UTIL = 0.8e18;  // 80%
    uint256 public constant LIQ_PENALTY = 500;      // 5%
    
    function setUp() public {
        // Deploy mock USDT (18 decimals on BSC)
        usdt = new MockERC20("Tether USD", "USDT", 18);
        
        // Deploy core contracts
        ledger = new PositionLedger(address(usdt));
        priceEngine = new PriceEngine(address(ledger));
        fundingEngine = new FundingEngine(address(ledger));
        riskEngine = new RiskEngine(address(ledger));
        liquidationEngine = new LiquidationEngine(
            address(ledger),
            address(usdt),
            protocolFeeRecipient,
            lpPool
        );
        router = new Router(
            address(ledger),
            address(priceEngine),
            address(riskEngine),
            address(usdt)
        );
        
        // Configure liquidation engine
        liquidationEngine.setEngines(address(riskEngine), address(priceEngine));
        
        // Authorize engines on ledger
        ledger.setEngineAuthorization(address(router), true);
        ledger.setEngineAuthorization(address(liquidationEngine), true);
        ledger.setEngineAuthorization(address(fundingEngine), true);
        ledger.setEngineAuthorization(address(riskEngine), true);
        
        // Authorize keepers
        priceEngine.setKeeperAuthorization(keeper, true);
        fundingEngine.setKeeperAuthorization(keeper, true);
        
        // Create market
        ledger.createMarket(oracle, MAX_OI);
        
        // Configure price engine
        priceEngine.configurePricing(
            MARKET_ID,
            oracle,
            3600,       // 1 hour EMA
            500,        // 5% max deviation
            10_000_000e18  // vAMM depth
        );
        
        // Configure funding engine (1 hour periods)
        fundingEngine.configureFunding(
            MARKET_ID,
            0.000125e18,  // 0.0125% max funding per hour (0.1% per 8h equivalent)
            1 hours,      // 1 hour funding period
            100_000e18    // Imbalance threshold
        );
        
        // Configure risk engine
        riskEngine.setRiskParams(
            MARKET_ID,
            IM_BPS,
            MM_BPS,
            MAX_LEVERAGE,
            BASE_BORROW,
            MAX_BORROW,
            OPTIMAL_UTIL,
            LIQ_PENALTY
        );
        riskEngine.setLPCapital(MARKET_ID, LP_CAPITAL);
        
        // Set initial price (50% probability)
        vm.prank(keeper);
        priceEngine.updatePrice(MARKET_ID, 0.5e18);
        
        // Fund traders (100k USDT each)
        usdt.mint(trader1, 100_000e18);
        usdt.mint(trader2, 100_000e18);
        usdt.mint(liquidator, 10_000e18);
        
        // Approve router
        vm.prank(trader1);
        usdt.approve(address(router), type(uint256).max);
        vm.prank(trader2);
        usdt.approve(address(router), type(uint256).max);
    }
    
    // ============ Happy Path Tests ============
    
    function test_FullTradeFlow_OpenAndClose() public {
        // Trader1 opens 10x long position
        // 10,000 USDT collateral, 100,000 notional at 50% = 200,000 size
        uint256 collateral = 10_000e18;
        int256 size = 100_000e18;  // Long
        
        vm.prank(trader1);
        router.openPosition(MARKET_ID, size, collateral, 0.6e18, 0);
        
        // Verify position
        PositionLedger.Position memory pos = ledger.getPosition(trader1, MARKET_ID);
        assertEq(pos.size, size);
        assertEq(pos.collateral, collateral);
        assertTrue(pos.entryPrice > 0);
        
        // Price increases to 60%
        vm.prank(keeper);
        priceEngine.updatePrice(MARKET_ID, 0.6e18);
        
        // Check PnL (should be profitable)
        int256 pnl = ledger.getUnrealizedPnL(trader1, MARKET_ID, 0.6e18);
        assertTrue(pnl > 0, "Should be profitable");
        
        // Close position
        vm.prank(trader1);
        router.closePosition(MARKET_ID, -size, 0.55e18, 1e18);
        
        // Verify closed
        pos = ledger.getPosition(trader1, MARKET_ID);
        assertEq(pos.size, 0);
        
        // Trader should have more USDT than started
        assertTrue(usdt.balanceOf(trader1) > 100_000e18, "Should have profit");
    }
    
    function test_LongAndShortOpposite() public {
        // Trader1 goes long
        vm.prank(trader1);
        router.openPosition(MARKET_ID, 50_000e18, 5_000e18, 0.6e18, 0);
        
        // Trader2 goes short
        vm.prank(trader2);
        router.openPosition(MARKET_ID, -50_000e18, 5_000e18, 1e18, 0.4e18);
        
        // Check OI
        PositionLedger.Market memory market = ledger.getMarket(MARKET_ID);
        assertEq(market.totalLongOI, 50_000e18);
        assertEq(market.totalShortOI, 50_000e18);
        
        // OI should be balanced
        assertEq(ledger.getOIImbalance(MARKET_ID), 0);
    }
    
    function test_AddCollateral() public {
        // Open position
        vm.prank(trader1);
        router.openPosition(MARKET_ID, 50_000e18, 5_000e18, 0.6e18, 0);
        
        // Add more collateral
        vm.prank(trader1);
        router.depositCollateral(MARKET_ID, 2_000e18);
        
        // Verify
        PositionLedger.Position memory pos = ledger.getPosition(trader1, MARKET_ID);
        assertEq(pos.collateral, 7_000e18);
    }
    
    function test_WithdrawCollateral() public {
        // Open position with extra margin
        vm.prank(trader1);
        router.openPosition(MARKET_ID, 20_000e18, 5_000e18, 0.6e18, 0);
        
        // Withdraw some (still maintaining margin)
        vm.prank(trader1);
        router.withdrawCollateral(MARKET_ID, 1_000e18);
        
        // Verify
        PositionLedger.Position memory pos = ledger.getPosition(trader1, MARKET_ID);
        assertEq(pos.collateral, 4_000e18);
    }
    
    // ============ Funding Tests ============
    
    function test_FundingFlow() public {
        // Create imbalanced OI - more longs than shorts
        vm.prank(trader1);
        router.openPosition(MARKET_ID, 80_000e18, 8_000e18, 0.6e18, 0);
        
        vm.prank(trader2);
        router.openPosition(MARKET_ID, -20_000e18, 2_000e18, 1e18, 0.4e18);
        
        // Check imbalance
        int256 imbalance = ledger.getOIImbalance(MARKET_ID);
        assertEq(imbalance, 60_000e18); // Longs are crowded
        
        // Advance time and update funding
        vm.warp(block.timestamp + 8 hours);
        
        vm.prank(keeper);
        fundingEngine.updateFunding(MARKET_ID);
        
        // Funding rate should be positive (longs pay shorts)
        int256 rate = fundingEngine.getCurrentFundingRate(MARKET_ID);
        assertTrue(rate > 0, "Longs should pay");
    }
    
    // ============ Liquidation Tests ============
    
    function test_Liquidation() public {
        // Open risky position (high leverage)
        vm.prank(trader1);
        router.openPosition(MARKET_ID, 90_000e18, 5_000e18, 0.6e18, 0);
        
        // Price crashes
        vm.prank(keeper);
        priceEngine.updatePrice(MARKET_ID, 0.42e18);
        
        // Check if liquidatable
        bool canLiq = liquidationEngine.canLiquidate(trader1, MARKET_ID);
        assertTrue(canLiq, "Should be liquidatable");
        
        // Execute liquidation
        vm.prank(liquidator);
        LiquidationEngine.LiquidationResult memory result = liquidationEngine.liquidate(trader1, MARKET_ID);
        
        // Verify liquidation happened
        assertEq(result.trader, trader1);
        assertTrue(result.penalty > 0);
        assertTrue(result.liquidatorReward > 0);
        
        // Position should be closed
        PositionLedger.Position memory pos = ledger.getPosition(trader1, MARKET_ID);
        assertEq(pos.size, 0);
    }
    
    function test_NotLiquidatableWhenHealthy() public {
        // Open safe position (low leverage)
        vm.prank(trader1);
        router.openPosition(MARKET_ID, 20_000e18, 5_000e18, 0.6e18, 0);
        
        // Small price move
        vm.prank(keeper);
        priceEngine.updatePrice(MARKET_ID, 0.48e18);
        
        // Should not be liquidatable
        bool canLiq = liquidationEngine.canLiquidate(trader1, MARKET_ID);
        assertFalse(canLiq, "Should not be liquidatable");
        
        // Liquidation should revert
        vm.prank(liquidator);
        vm.expectRevert(LiquidationEngine.NotLiquidatable.selector);
        liquidationEngine.liquidate(trader1, MARKET_ID);
    }
    
    // ============ Risk Engine Tests ============
    
    function test_MarginRequirements() public {
        uint256 size = 100_000e18;
        uint256 price = 0.5e18;
        
        (uint256 im, uint256 mm) = riskEngine.getRequiredCollateral(MARKET_ID, size, price);
        
        // Notional = 100,000 * 0.5 = 50,000
        // IM = 50,000 * 10% = 5,000
        // MM = 50,000 * 5% = 2,500
        assertEq(im, 5_000e18);
        assertEq(mm, 2_500e18);
    }
    
    function test_UtilizationBasedBorrowRate() public {
        // Open position to increase utilization
        vm.prank(trader1);
        router.openPosition(MARKET_ID, 200_000e18, 20_000e18, 0.6e18, 0);
        
        // Check utilization
        RiskEngine.UtilizationData memory data = riskEngine.getUtilization(MARKET_ID);
        
        // 200,000 OI vs 500,000 LP capital = 40% utilization
        assertTrue(data.utilization > 0);
        assertTrue(data.currentBorrowRate >= BASE_BORROW);
    }
    
    // ============ Edge Cases ============
    
    function test_RevertInsufficientMargin() public {
        // Try to open overleveraged position
        vm.prank(trader1);
        vm.expectRevert(Router.InsufficientMargin.selector);
        router.openPosition(MARKET_ID, 500_000e18, 1_000e18, 1e18, 0); // Way too leveraged
    }
    
    function test_RevertStalePrice() public {
        // Advance time past staleness threshold
        vm.warp(block.timestamp + 2 minutes);
        
        vm.prank(trader1);
        vm.expectRevert(Router.StalePrice.selector);
        router.openPosition(MARKET_ID, 50_000e18, 5_000e18, 0.6e18, 0);
    }
    
    function test_PartialClose() public {
        // Open position
        vm.prank(trader1);
        router.openPosition(MARKET_ID, 100_000e18, 10_000e18, 0.6e18, 0);
        
        // Partial close (50%)
        vm.prank(trader1);
        router.closePosition(MARKET_ID, -50_000e18, 0, 1e18);
        
        // Verify partial close
        PositionLedger.Position memory pos = ledger.getPosition(trader1, MARKET_ID);
        assertEq(pos.size, 50_000e18);
    }
    
    function test_FlipPosition() public {
        // Open long
        vm.prank(trader1);
        router.openPosition(MARKET_ID, 50_000e18, 5_000e18, 0.6e18, 0);
        
        // Flip to short (close long + open short)
        vm.prank(trader1);
        router.openPosition(MARKET_ID, -100_000e18, 5_000e18, 1e18, 0.4e18);
        
        // Should now be short
        PositionLedger.Position memory pos = ledger.getPosition(trader1, MARKET_ID);
        assertEq(pos.size, -50_000e18);
    }
    
    // ============ Price Engine Tests ============
    
    function test_PriceSlippage() public {
        // Large buy should have higher execution price
        uint256 markPrice = priceEngine.getMarkPrice(MARKET_ID);
        uint256 execPriceBuy = priceEngine.getExecutionPrice(MARKET_ID, 500_000e18);
        uint256 execPriceSell = priceEngine.getExecutionPrice(MARKET_ID, -500_000e18);
        
        assertTrue(execPriceBuy > markPrice, "Buy should have slippage up");
        assertTrue(execPriceSell < markPrice, "Sell should have slippage down");
    }
    
    function test_EMASmoothing() public {
        // First price
        vm.prank(keeper);
        priceEngine.updatePrice(MARKET_ID, 0.5e18);
        
        (,uint256 ema1,,) = priceEngine.getPriceData(MARKET_ID);
        
        // Jump in oracle price
        vm.warp(block.timestamp + 30 minutes);
        vm.prank(keeper);
        priceEngine.updatePrice(MARKET_ID, 0.7e18);
        
        (,uint256 ema2,,) = priceEngine.getPriceData(MARKET_ID);
        
        // EMA should be smoothed, not jump to 0.7
        assertTrue(ema2 > ema1, "EMA should increase");
        assertTrue(ema2 < 0.7e18, "EMA should be smoothed");
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
