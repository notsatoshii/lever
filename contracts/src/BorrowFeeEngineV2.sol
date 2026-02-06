// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BorrowFeeEngineV2
 * @author LEVER Protocol
 * @notice Dynamic borrow rate calculation with 5 risk multipliers
 * @dev Implements Module 8 from LEVER Architecture:
 *      r = min(r_max, r_base × M_util × M_imb × M_vol × M_ttR × M_conc)
 * 
 * Rate increases under stress via multiplicative risk multipliers:
 * - M_util: Utilization (LP pool depletion)
 * - M_imb: Imbalance (one-sided markets)
 * - M_vol: Volatility (oracle/liquidation risk)
 * - M_ttR: Time to Resolution (binary instability near expiry)
 * - M_conc: Concentration (single market exposure)
 */
contract BorrowFeeEngineV2 {
    
    // ============ Constants ============
    
    // Rate bounds (18 decimals, per hour)
    uint256 public constant BASE_RATE = 2e14;      // 0.02% = 0.0002
    uint256 public constant MIN_RATE = 2e14;       // 0.02%
    uint256 public constant MAX_RATE = 1e15;       // 0.10% = 0.001 (per architecture)
    
    // Multiplier constants (18 decimals = 1.0)
    uint256 public constant SCALE = 1e18;
    
    // M_util constants
    uint256 public constant UTIL_THRESHOLD = 6e17;     // 60%
    uint256 public constant UTIL_GENTLE_COEF = 10;     // a = 10
    uint256 public constant UTIL_PUNITIVE_COEF = 8;    // b = 8
    
    // M_imb constant
    uint256 public constant IMB_COEF = 6;              // c = 6
    
    // M_vol constant
    uint256 public constant VOL_COEF = 15e17;          // d = 1.5
    uint256 public constant VOL_BASELINE = 1e16;       // σ_0 = 1% (baseline vol)
    
    // M_ttR constants
    uint256 public constant TTR_THRESHOLD_HIGH = 48 hours;
    uint256 public constant TTR_THRESHOLD_LOW = 12 hours;
    uint256 public constant TTR_COEF_E = 2;            // e = 2
    uint256 public constant TTR_COEF_F = 3;            // f = 3
    
    // M_conc constants
    uint256 public constant CONC_THRESHOLD = 15e16;    // C_0 = 15%
    uint256 public constant CONC_COEF = 8;             // g = 8
    
    // EMA smoothing
    uint256 public constant EMA_ALPHA = 15e16;         // α = 0.15
    uint256 public constant MAX_RATE_INCREASE = 25e16; // Max +25% per hour
    
    // ============ State ============
    
    address public owner;
    address public positionLedger;
    address public priceEngine;
    
    // Per-market state
    mapping(uint256 => MarketBorrowState) public marketState;
    
    struct MarketBorrowState {
        uint256 currentRate;           // Current hourly borrow rate (EMA smoothed)
        uint256 borrowIndex;           // Global borrow index (grows over time)
        uint256 lastUpdateTime;        // Last index update timestamp
        uint256 volatility;            // Current volatility estimate (18 decimals)
    }
    
    // Global state
    uint256 public globalOICap;        // Total OI cap across all markets
    
    // ============ Events ============
    
    event RateUpdated(uint256 indexed marketId, uint256 newRate, uint256 rawRate, uint256 newIndex);
    event BorrowIndexUpdated(uint256 indexed marketId, uint256 newIndex, uint256 accruedTime);
    event VolatilityUpdated(uint256 indexed marketId, uint256 newVolatility);
    
    // ============ Errors ============
    
    error Unauthorized();
    error ZeroAddress();
    error MarketNotInitialized();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyAuthorized() {
        if (msg.sender != owner && msg.sender != positionLedger) revert Unauthorized();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _positionLedger, address _priceEngine) {
        if (_positionLedger == address(0)) revert ZeroAddress();
        if (_priceEngine == address(0)) revert ZeroAddress();
        
        owner = msg.sender;
        positionLedger = _positionLedger;
        priceEngine = _priceEngine;
    }
    
    // ============ Admin Functions ============
    
    function setGlobalOICap(uint256 _cap) external onlyOwner {
        globalOICap = _cap;
    }
    
    function initializeMarket(uint256 marketId) external onlyOwner {
        marketState[marketId] = MarketBorrowState({
            currentRate: BASE_RATE,
            borrowIndex: SCALE,  // Start at 1.0
            lastUpdateTime: block.timestamp,
            volatility: VOL_BASELINE
        });
    }
    
    // ============ Core Functions ============
    
    /**
     * @notice Update borrow index for a market (called by keeper or on interaction)
     * @dev Index grows exponentially: B(t) = B(t_0) × e^(r × Δt)
     *      Approximated as: B(t) = B(t_0) × (1 + r × Δt) for small Δt
     */
    function accrueInterest(uint256 marketId) external returns (uint256 newIndex) {
        MarketBorrowState storage state = marketState[marketId];
        if (state.borrowIndex == 0) revert MarketNotInitialized();
        
        uint256 elapsed = block.timestamp - state.lastUpdateTime;
        if (elapsed == 0) return state.borrowIndex;
        
        // Calculate accrued interest: index × (1 + rate × hours)
        uint256 hoursElapsed = elapsed / 1 hours;
        if (hoursElapsed == 0) hoursElapsed = 1; // Minimum 1 hour granularity
        
        uint256 accruedRate = state.currentRate * hoursElapsed;
        newIndex = state.borrowIndex + (state.borrowIndex * accruedRate / SCALE);
        
        state.borrowIndex = newIndex;
        state.lastUpdateTime = block.timestamp;
        
        emit BorrowIndexUpdated(marketId, newIndex, elapsed);
    }
    
    /**
     * @notice Calculate and update the dynamic borrow rate
     * @dev Called by keeper periodically (e.g., hourly)
     */
    function updateRate(
        uint256 marketId,
        uint256 globalOI,
        uint256 marketLongOI,
        uint256 marketShortOI,
        uint256 marketOI,
        uint256 resolutionTime,
        bool isLive,
        uint256 liveStartTime
    ) external onlyAuthorized returns (uint256 newRate) {
        MarketBorrowState storage state = marketState[marketId];
        if (state.borrowIndex == 0) revert MarketNotInitialized();
        
        // Calculate raw rate with all multipliers
        uint256 rawRate = _calculateRawRate(
            globalOI,
            marketLongOI,
            marketShortOI,
            marketOI,
            state.volatility,
            resolutionTime,
            isLive,
            liveStartTime
        );
        
        // Apply EMA smoothing
        newRate = _applyEMASmoothing(state.currentRate, rawRate);
        
        // Apply max increase cap (+25% per update)
        uint256 maxAllowed = state.currentRate + (state.currentRate * MAX_RATE_INCREASE / SCALE);
        if (newRate > maxAllowed) {
            newRate = maxAllowed;
        }
        
        // Clamp to bounds
        if (newRate < MIN_RATE) newRate = MIN_RATE;
        if (newRate > MAX_RATE) newRate = MAX_RATE;
        
        state.currentRate = newRate;
        
        emit RateUpdated(marketId, newRate, rawRate, state.borrowIndex);
    }
    
    /**
     * @notice Update volatility estimate for a market
     * @dev Called by price engine or keeper with new volatility data
     */
    function updateVolatility(uint256 marketId, uint256 newVolatility) external onlyAuthorized {
        marketState[marketId].volatility = newVolatility;
        emit VolatilityUpdated(marketId, newVolatility);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get current borrow rate for a market
     */
    function getCurrentRate(uint256 marketId) external view returns (uint256) {
        return marketState[marketId].currentRate;
    }
    
    /**
     * @notice Get current borrow index for a market
     */
    function getBorrowIndex(uint256 marketId) external view returns (uint256) {
        return marketState[marketId].borrowIndex;
    }
    
    /**
     * @notice Calculate pending borrow fees for a position
     * @param notional Position notional value
     * @param entryIndex Borrow index when position was opened
     * @param marketId Market ID
     */
    function calculateBorrowFees(
        uint256 notional,
        uint256 entryIndex,
        uint256 marketId
    ) external view returns (uint256 fees) {
        uint256 currentIndex = marketState[marketId].borrowIndex;
        if (entryIndex == 0 || currentIndex <= entryIndex) return 0;
        
        // Fees = notional × (currentIndex / entryIndex - 1)
        fees = notional * (currentIndex - entryIndex) / entryIndex;
    }
    
    /**
     * @notice Preview what the rate would be with given inputs (for frontend)
     */
    function previewRate(
        uint256 globalOI,
        uint256 marketLongOI,
        uint256 marketShortOI,
        uint256 marketOI,
        uint256 volatility,
        uint256 resolutionTime,
        bool isLive,
        uint256 liveStartTime
    ) external view returns (uint256 rate, uint256[5] memory multipliers) {
        (rate, multipliers) = _calculateRawRateWithMultipliers(
            globalOI,
            marketLongOI,
            marketShortOI,
            marketOI,
            volatility,
            resolutionTime,
            isLive,
            liveStartTime
        );
    }
    
    // ============ Internal Functions ============
    
    function _calculateRawRate(
        uint256 globalOI,
        uint256 marketLongOI,
        uint256 marketShortOI,
        uint256 marketOI,
        uint256 volatility,
        uint256 resolutionTime,
        bool isLive,
        uint256 liveStartTime
    ) internal view returns (uint256) {
        (uint256 rate, ) = _calculateRawRateWithMultipliers(
            globalOI, marketLongOI, marketShortOI, marketOI,
            volatility, resolutionTime, isLive, liveStartTime
        );
        return rate;
    }
    
    function _calculateRawRateWithMultipliers(
        uint256 globalOI,
        uint256 marketLongOI,
        uint256 marketShortOI,
        uint256 marketOI,
        uint256 volatility,
        uint256 resolutionTime,
        bool isLive,
        uint256 liveStartTime
    ) internal view returns (uint256 rate, uint256[5] memory multipliers) {
        // Calculate each multiplier
        multipliers[0] = _calcMUtil(globalOI);
        multipliers[1] = _calcMImb(marketLongOI, marketShortOI);
        multipliers[2] = _calcMVol(volatility);
        multipliers[3] = _calcMTtR(resolutionTime);
        multipliers[4] = _calcMLive(isLive, liveStartTime);
        
        // Note: M_conc would need globalOI passed in, simplified for now
        uint256 mConc = _calcMConc(marketOI, globalOI);
        
        // r = r_base × M_util × M_imb × M_vol × M_ttR × M_live × M_conc
        rate = BASE_RATE;
        rate = rate * multipliers[0] / SCALE;  // M_util
        rate = rate * multipliers[1] / SCALE;  // M_imb
        rate = rate * multipliers[2] / SCALE;  // M_vol
        rate = rate * multipliers[3] / SCALE;  // M_ttR
        rate = rate * multipliers[4] / SCALE;  // M_live
        rate = rate * mConc / SCALE;           // M_conc
        
        // Clamp to max
        if (rate > MAX_RATE) rate = MAX_RATE;
    }
    
    /**
     * @notice M_util: Utilization multiplier
     * @dev U ≤ 60%: 1.0
     *      60% < U < 100%: 1 + 10×(U-0.6)²
     *      U ≥ 100%: 2.6 + 8×(U-1)
     */
    function _calcMUtil(uint256 globalOI) internal view returns (uint256) {
        if (globalOICap == 0) return SCALE;
        
        uint256 U = globalOI * SCALE / globalOICap;
        
        if (U <= UTIL_THRESHOLD) {
            return SCALE; // 1.0
        } else if (U < SCALE) {
            // 1 + 10×(U-0.6)²
            uint256 diff = U - UTIL_THRESHOLD;
            uint256 squared = diff * diff / SCALE;
            return SCALE + UTIL_GENTLE_COEF * squared;
        } else {
            // 2.6 + 8×(U-1)
            // At U=100%, multiplier = 1 + 10×(0.4)² = 1 + 1.6 = 2.6
            uint256 baseAt100 = SCALE + UTIL_GENTLE_COEF * (4e17 * 4e17 / SCALE); // 2.6
            uint256 excess = U - SCALE;
            return baseAt100 + UTIL_PUNITIVE_COEF * excess;
        }
    }
    
    /**
     * @notice M_imb: Imbalance multiplier
     * @dev S = |longOI - shortOI| / totalOI
     *      multiplier = 1 + 6×S²
     */
    function _calcMImb(uint256 longOI, uint256 shortOI) internal pure returns (uint256) {
        uint256 totalOI = longOI + shortOI;
        if (totalOI == 0) return SCALE;
        
        uint256 imbalance = longOI > shortOI ? longOI - shortOI : shortOI - longOI;
        uint256 S = imbalance * SCALE / totalOI;
        
        // 1 + 6×S²
        uint256 sSquared = S * S / SCALE;
        return SCALE + IMB_COEF * sSquared;
    }
    
    /**
     * @notice M_vol: Volatility multiplier
     * @dev multiplier = 1 + 1.5 × max(0, (σ - σ_0) / σ_0)
     */
    function _calcMVol(uint256 volatility) internal pure returns (uint256) {
        if (volatility <= VOL_BASELINE) return SCALE;
        
        uint256 excessVol = volatility - VOL_BASELINE;
        uint256 normalized = excessVol * SCALE / VOL_BASELINE;
        
        return SCALE + VOL_COEF * normalized / SCALE;
    }
    
    /**
     * @notice M_ttR: Time to Resolution multiplier
     * @dev T ≥ 48h: 1.0
     *      12h < T < 48h: 1 + 2×((48-T)/36)²
     *      T ≤ 12h: 3 + 3×((12-T)/12)
     */
    function _calcMTtR(uint256 resolutionTime) internal view returns (uint256) {
        if (block.timestamp >= resolutionTime) {
            // Already resolved or at resolution
            return SCALE + TTR_COEF_E * SCALE + TTR_COEF_F * SCALE; // Max: 1 + 2 + 3 = 6
        }
        
        uint256 T = resolutionTime - block.timestamp;
        
        if (T >= TTR_THRESHOLD_HIGH) {
            return SCALE; // 1.0
        } else if (T > TTR_THRESHOLD_LOW) {
            // 1 + 2×((48-T)/36)²
            uint256 diff = TTR_THRESHOLD_HIGH - T;
            uint256 normalized = diff * SCALE / (TTR_THRESHOLD_HIGH - TTR_THRESHOLD_LOW);
            uint256 squared = normalized * normalized / SCALE;
            return SCALE + TTR_COEF_E * squared;
        } else {
            // 3 + 3×((12-T)/12)
            // At T=12h, this equals 3.0 (base from previous tier)
            uint256 baseAt12h = SCALE + TTR_COEF_E * SCALE; // 3.0
            uint256 diff = TTR_THRESHOLD_LOW - T;
            uint256 normalized = diff * SCALE / TTR_THRESHOLD_LOW;
            return baseAt12h + TTR_COEF_F * normalized;
        }
    }
    
    /**
     * @notice M_live: Live event multiplier
     * @dev Not live: 1.0
     *      Live, first 30 min: 2.0
     *      Live, after 30 min: 1.5
     */
    function _calcMLive(bool isLive, uint256 liveStartTime) internal view returns (uint256) {
        if (!isLive) return SCALE;
        
        uint256 liveElapsed = block.timestamp - liveStartTime;
        
        if (liveElapsed <= 30 minutes) {
            return 2 * SCALE; // 2.0
        } else {
            return 15e17; // 1.5
        }
    }
    
    /**
     * @notice M_conc: Concentration multiplier
     * @dev C = marketOI / globalOI
     *      C ≤ 15%: 1.0
     *      C > 15%: 1 + 8×(C-0.15)
     */
    function _calcMConc(uint256 marketOI, uint256 globalOI) internal pure returns (uint256) {
        if (globalOI == 0) return SCALE;
        
        uint256 C = marketOI * SCALE / globalOI;
        
        if (C <= CONC_THRESHOLD) {
            return SCALE;
        } else {
            uint256 excess = C - CONC_THRESHOLD;
            return SCALE + CONC_COEF * excess;
        }
    }
    
    /**
     * @notice Apply EMA smoothing to rate
     * @dev r_smoothed = α × r_raw + (1 - α) × r_prev
     */
    function _applyEMASmoothing(uint256 prevRate, uint256 rawRate) internal pure returns (uint256) {
        // r = 0.15 × raw + 0.85 × prev
        return (EMA_ALPHA * rawRate + (SCALE - EMA_ALPHA) * prevRate) / SCALE;
    }
}
