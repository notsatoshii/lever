# LEVER Implementation Plan
**Last Updated:** 2026-02-06 14:43 UTC  
**Goal:** Full system matching ARCHITECTURE.md + Lazy Fee Accrual spec

---

## 📊 CURRENT STATUS

### ✅ COMPLETED
| Item | Details | Date |
|------|---------|------|
| PriceEngineV2.sol | Deployed: `0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC` | 02-06 |
| Leverage Fix | All markets now 5x max | 02-06 |
| Keeper-v2 | Running: prices + interest accrual | 02-06 |
| Frontend | Dual price display + expiry countdown | 02-06 |
| PositionLedgerV2.sol | Created with lazy fee accrual | 02-06 14:42 |
| Lazy Fee Spec | Logged to Notion (Borrow Fee Engine Spec) | 02-06 14:38 |
| BorrowFeeEngineV2.sol | Created with 5 multipliers + M_live | 02-06 14:44 |
| RiskEngineV2.sol | Created with PI-only liq, partial liq | 02-06 14:46 |
| vAMM.sol | Created with spread guard, JIT recenter | 02-06 14:48 |
| RouterV4.sol | Created - integrates all V2 contracts | 02-06 14:50 |

### 🔄 IN PROGRESS
| Item | Status | Blocker |
|------|--------|---------|
| Testing & Deployment | Next | Need to compile and test all V2 contracts |

### ❌ NOT STARTED
- RiskEngineV2 (PI-only liquidations)
- vAMM.sol (entry price calculator)
- RouterV4 (integration of all V2 contracts)
- JIT Keeper
- Settlement/RFQ system

---

## 🎯 PRIORITY QUEUE (Execute in Order)

### PRIORITY 1: BorrowFeeEngineV2 ✅ DONE
**File:** `contracts/src/BorrowFeeEngineV2.sol`

**Tasks:**
- [x] Create BorrowFeeEngineV2.sol
- [x] Implement M_util (utilization multiplier)
- [x] Implement M_imb (imbalance multiplier)  
- [x] Implement M_vol (volatility multiplier)
- [x] Implement M_ttR (time-to-resolution multiplier)
- [x] Implement M_conc (concentration multiplier)
- [x] Implement M_live (live event multiplier) — BONUS
- [x] Dynamic rate: `r = min(r_max, r_base × M_util × M_imb × M_vol × M_ttR × M_conc)`
- [x] EMA smoothing (α = 0.15)
- [x] Hard bounds: 0.02% - 0.20% per hour
- [x] Global Borrow Index calculation
- [ ] Integration with PositionLedgerV2 (at deploy time)

### PRIORITY 2: RiskEngineV2 ✅ DONE
**File:** `contracts/src/RiskEngineV2.sol`

**Tasks:**
- [x] Create RiskEngineV2.sol
- [x] Equity: `Collateral + (PI - Entry) × Size - PendingFees`
- [x] Initial Margin: `(Notional/Leverage) × (1 + α × σ)`
- [x] Maintenance Margin: `m × Notional`
- [x] Liquidation check: `Equity ≤ MM`
- [x] 2% liquidation buffer
- [x] Partial liquidation (50%) before full
- [x] **Uses PriceEngineV2.getMarkPrice()** - never vAMM
- [x] Liquidation price calculator
- [x] Effective leverage & margin ratio views
- [ ] Integration with PositionLedgerV2 (at deploy time)

### PRIORITY 3: vAMM.sol ✅ DONE
**File:** `contracts/src/vAMM.sol`

**Tasks:**
- [x] Create vAMM.sol
- [x] Constant product: `x · y = k`
- [x] Virtual reserves (vQ, vB) - no real capital
- [x] Initialize: `vQ/vB = PI_initial`
- [x] JIT recenter function for keepers
- [x] Volatility Spread Guard (widens spread on deviation)
- [x] Calculate execution price with slippage
- [x] Swap execution with slippage protection
- [x] Spot price, spread, pool state views

### PRIORITY 4: RouterV4 (Integration) ✅ DONE
**File:** `contracts/src/RouterV4.sol`

**Tasks:**
- [x] Entry price from vAMM
- [x] Mark price from PriceEngineV2
- [x] Position management via PositionLedgerV2
- [x] Risk checks via RiskEngineV2
- [x] Fee calculation via BorrowFeeEngineV2
- [x] Open/close/modify positions
- [x] Add/remove collateral
- [x] Preview trades
- [x] Position details view

### PRIORITY 5: Testing & Deployment ⏳ NEXT
**Status:** All V2 contracts created + tests written. Ready for local compile.

**To compile and test locally:**
```bash
cd contracts
forge build
forge test -vvv
```

**Tasks:**
- [ ] Compile all V2 contracts (forge not in sandbox)
- [ ] Fix any compilation errors
- [x] Create deployment script: `DeployV2.s.sol` ✅ Fixed addresses
- [x] Unit tests created: `test/V2.t.sol` (40+ tests)
- [ ] Run tests locally
- [ ] Deploy to BSC Testnet:
  - PositionLedgerV2
  - BorrowFeeEngineV2
  - RiskEngineV2
  - vAMM
  - RouterV4
- [ ] Configure contract connections
- [ ] Update frontend to use new contracts

### PRIORITY 6: Settlement & RFQ (Later)
**Tasks:**
- [ ] RFQ mode when P > 95% or T < 24h
- [ ] Oracle-triggered settlement
- [ ] Market closure logic

---

## 📁 FILES STATUS

| File | Status | Notes |
|------|--------|-------|
| `contracts/src/PriceEngineV2.sol` | ✅ DEPLOYED | Smoothing engine working |
| `contracts/src/PositionLedgerV2.sol` | ✅ CREATED | Lazy fee accrual, needs deploy |
| `contracts/src/BorrowFeeEngineV2.sol` | ✅ CREATED | 5 multipliers + M_live |
| `contracts/src/RiskEngineV2.sol` | ✅ CREATED | PI-only liquidations, partial liq |
| `contracts/src/vAMM.sol` | ✅ CREATED | Entry price, spread guard, JIT recenter |
| `contracts/src/RouterV4.sol` | ✅ CREATED | Integration layer complete |
| `keeper/polymarket-keeper-v2.ts` | ✅ RUNNING | Price feeds working |
| `keeper/jit-keeper.ts` | ❌ TODO | vAMM re-centering |

---

## 🔧 ARCHITECTURE REFERENCE

### Core Decoupling (CRITICAL)
```
Entry Price ≠ Mark Price

Entry Price: From vAMM (slippage) - used for trade execution
Mark Price:  From PriceEngineV2 (smoothed PI) - used for liquidations
```

### Borrow Rate Formula
```
r = min(r_max, r_base × M_util × M_imb × M_vol × M_ttR × M_conc)

Base: 0.02%/hour
Max:  0.20%/hour
```

### Fee Distribution
```
50% → LP Pool (settledFeePool)
30% → Protocol Treasury
20% → Insurance Fund
```

### Global OI Caps
```
T ≥ 48h:    80% × TVL (Phase A)
12h < T:    65% × TVL (Phase B)
Live:       50% × TVL (Phase C)
Post-event: 35% × TVL (Phase D)
```

### Lazy Fee Settlement Triggers
- Position closed
- Position size modified
- Collateral added/removed
- Liquidation occurs
- LP withdraws

---

## 📝 CHANGE LOG

| Time (UTC) | Change |
|------------|--------|
| 15:00 | Created comprehensive test suite: `test/V2.t.sol` (40+ tests) |
| 14:55 | Fixed DeployV2.s.sol with correct addresses (USDT, LP_POOL, etc.) |
| 14:52 | Created DeployV2.s.sol deployment script |
| 14:50 | Created RouterV4.sol (full V2 integration) |
| 14:48 | Created vAMM.sol (virtual AMM, spread guard, JIT recenter) |
| 14:46 | Created RiskEngineV2.sol (PI-only liquidations, partial liq) |
| 14:44 | Created BorrowFeeEngineV2.sol (5 multipliers + M_live) |
| 14:43 | Reorganized plan, added priority queue |
| 14:42 | Created PositionLedgerV2.sol |
| 14:38 | Logged lazy fee spec to Notion |
| 14:30 | Frontend dual price display done |
| 14:27 | PriceEngineV2 deployed |
| 14:24 | Leverage bug fixed (5x max) |

---

## ⏭️ IMMEDIATE NEXT ACTION

**Compile and test all V2 contracts, then create deployment scripts**

After completion:
1. Update this file with [x] marks
2. Add to CHANGE LOG
3. Move to next priority

---

*Re-read ARCHITECTURE.md and this file before each task to stay aligned.*
