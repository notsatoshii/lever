# Eric's Requests - 2026-02-06

## MASTER ACTION ITEMS (from 13:55-14:16 UTC)

### Requested by Eric:
1. ✅ **LP APY Display** — Show APY on LP page (DONE - frontend updated)
2. ✅ **Market Expiry** — Add expiry dates to all markets (DONE - PriceEngineV2 has expiry)
3. ✅ **Fix Pricing Engine** — Implement correct smoothing/PI per architecture (DONE - PriceEngineV2)
4. ✅ **Fix Keeper** — Update to match architecture (DONE - polymarket-keeper-v2.ts)
5. ✅ **Log Architecture** — Full architecture doc logged (DONE - memory/ARCHITECTURE.md)

### Critical Bugs Reported (14:24 UTC):

**BUG 1: Leverage Not Enforced**
- User has 10x $20k position open
- Collateral is below $2k
- Max leverage was supposed to be 5x
- **Impact:** Positions opened with illegal leverage, system at risk

**BUG 2: Borrow Fees Not Charging**
- Borrow fees are NOT being charged hourly
- Fees NOT being sent to LP pool
- **Impact:** LPs not earning, positions held for free

---

### Additional UI Request (14:21 UTC):
6. **Dual Price Display on Market Page:**
   - **LIVE Price** — Real-time from Polymarket (raw, unsmoothed)
   - **Mark Price** — Our PI from PriceEngineV2 (smoothed)
   - Both displayed side-by-side so users see the difference
   - Chart shows LIVE (Polymarket), Mark Price shown as indicator/label

### Deployment Pending (has private key):
- [ ] Deploy PriceEngineV2
- [ ] Configure markets with real expiry dates
- [ ] Update other contracts to use PriceEngineV2
- [ ] Start keeper-v2

### Architecture Logged (memory/ARCHITECTURE.md):
- Module 1-2: Data flow, PI, Smoothing Engine
- Module 3: vAMM, JIT Keepers
- Module 4: Risk & Solvency, Liquidations, OI Limits
- Module 5-6: LP Mechanics, Insurance Fund, Settlement, RFQ
- Module 8: Borrow Fee Engine (5 multipliers)
- Fee Architecture: Trading/Borrow/Funding fees
- Position Ledger: Core state/source of truth

---

# Historical Requests (Earlier in Day)

## Completed ✅

## Completed ✅

1. **Polymarket Integration** - Fetch real market data from Polymarket API instead of hardcoded markets
2. **USDC → USDT** - Change all references from USDC to USDT throughout the frontend
3. **LP Pool Fee Display** - Show borrow fees/trading fees in the LP pool page (added cumulative fees, pending fees, claim button)
4. **Market Cards** - Display real Polymarket questions, prices, volume, categories
5. **Navigation Connect Button** - Fixed to say "Connect Wallet" instead of "Deposit"
6. **Navigation USDT Balance** - Now shows actual balance from contract
7. **Portfolio PnL** - Now calculates from actual position data (not random)
8. **Portfolio Markets** - Removed hardcoded names, uses dynamic data
9. **Portfolio Fees** - Fetches unclaimed fees from LP contract
10. **PriceChart** - Uses Polymarket price for chart generation
11. **TradingPanel Liquidation** - Calculates based on leverage and margin
12. **Polymarket URLs** - Fixed to correct format

## Open Questions 🔄

- **LP Pool Utilization** - Shows 0% (correct, no positions). Want mock stats for demo?
- **LP APY** - Currently simple formula (utilization * 0.15). Want more sophisticated?

## Technical Notes

- Frontend live at: http://165.245.186.254:3001
- Contracts deployed on BSC Testnet (chain 97)
- LP Pool address: 0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1
- Using Polymarket gamma API: https://gamma-api.polymarket.com

## Bug Audit Log

Full audit performed 2026-02-06 ~12:30 UTC
- Found 9 critical/medium bugs
- Fixed 8 of 9 (LP APY formula kept simple for now)
- Details in: `memory/bug-audit-20260206.md`

## Context for Future Sessions

- This is for LEVER Protocol demo/investor presentations
- Eric wants it to look polished and functional
- Real Polymarket data integration is working
- On-chain contracts are deployed and functional
- Main gap: no actual trading activity yet (empty utilization/volume)

---

## 13:55 UTC - Architecture Doc Shared (IMPORTANT)

> **Full breakdown saved to: `memory/ARCHITECTURE.md`**
> This is the CANONICAL reference for all implementations.

Eric shared architecture overview showing the full system design:

### Module 1: Architecture Overview (The "North Star")

**1.1 High-Level Data Flow:**
1. **Ingest:** External Oracles provide Raw Probability P_raw
2. **Smooth:** Smoothing Engine removes noise → Probability Index (PI)
3. **Execute:** The vAMM uses Virtual Liquidity to determine Entry Price (slippage)
4. **Secure:** The Margin Engine uses PI to determine Mark Price (solvency)
5. **Back:** The Unified LP Pool acts as single counterparty for all trades

**1.2 Core Decoupling Principle - CRITICAL:**
```
Entry Price ≠ Mark Price!!!
```
- **Entry Price:** Determined by vAMM (e × g = k), includes slippage, reflects immediate demand
- **Mark Price:** Determined by Probability Index (PI), used for PnL, Margin, Liquidations
- **WHY:** Flash loan attacks can manipulate vAMM (Entry Price) but CANNOT manipulate PI (Mark Price). Solvency is checked against stable PI, not volatile vAMM.

### Module 2: Phase 1 - The Probability Index (PI)

**Goal:** Build manipulation-resistant price signal P_smooth

**Input Layer: Anti-Manipulation Shield**
- Connects to external markets (Polymarket, Kalshi) for Orderbook Midpoints/Last Traded
- **Validation Logic - Discard if:**
  - Spread > Threshold
  - Tick movement > Max allowed deviation per block
  - Liquidity depth < Minimum safe threshold

**2.2 The Smoothing Engine Formulas:**

1. **Volatility Dampening:**
   ```
   w_vol = 1 / (1 + σ)
   ```
   As volatility ↑, weight ↓, price becomes "stickier"

2. **Time-Weighted Smoothing:**
   ```
   w_time = √(τ / τ_max)
   ```
   As time-to-resolution → 0, smoothing ↑ to lock stability near expiry

3. **Update Logic:**
   ```
   P_smooth(t) = P_smooth(t-1) + α × w_vol × (P_raw(t) - P_smooth(t-1))
   ```

---

## 13:55 UTC - Eric's Action Items (PRIORITY)

1. **Market Expiry** - Needs to be added to contracts/frontend
2. **LP APY Display** - Show actual APY calculation on LP page
3. **Pricing Engine WRONG** - Current implementation doesn't match architecture:
   - Smoothing engine not implemented correctly
   - PI (Probability Index) logic is off
   - Need to audit PriceEngine.sol against the spec above

### Progress (13:57 UTC):

**✅ PriceEngineV2.sol CREATED** - Full rewrite implementing:
- Volatility dampening: `w_vol = 1/(1+σ)`
- Time-weighted smoothing: `w_time = √(τ/τ_max)`
- Correct smoothing formula: `P_smooth(t) = P_smooth(t-1) + α × w_vol × w_time × (P_raw - P_smooth(t-1))`
- Input validation layer (spread, tick movement, liquidity checks)
- Market expiry timestamps
- Settlement function for expired markets

**✅ DeployPriceEngineV2.s.sol CREATED**

**⏳ STILL TODO:**
- Update other contracts to use PriceEngineV2
- Set real expiry dates for markets

### Progress (13:58 UTC):

**✅ LP APY Display DONE** - Frontend now shows:
- Estimated APY prominently
- Breakdown of borrow fees vs trading fees
- Share price appreciation if available

**✅ Keeper V2 CREATED** (`keeper/polymarket-keeper-v2.ts`):
- Implements Input Layer from architecture
- Fetches from Polymarket CLOB (orderbook) with Gamma fallback
- Tracks spread, liquidity depth for validation
- Batch updates to PriceEngineV2
- Skips expired markets
- Shows volatility (σ) from on-chain state
