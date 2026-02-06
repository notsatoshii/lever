# LEVER Architecture - The North Star

**Source:** Eric's architecture doc shared 2026-02-06 13:55 UTC  
**Status:** CANONICAL REFERENCE — All implementations must match this

---

## Module 1: Architecture Overview

### Objectives
1. Establish the separation of concerns that prevents "Wick Hunting" and market manipulation
2. Understand the core data flow and the separation of concerns that prevents manipulation

### 1.1 High-Level Data Flow

The system is a pipeline that transforms noisy external data into a solvent financial instrument:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   INGEST    │ → │   SMOOTH    │ → │   EXECUTE   │ → │   SECURE    │ → │    BACK     │
│             │    │             │    │             │    │             │    │             │
│  External   │    │  Smoothing  │    │    vAMM     │    │   Margin    │    │  Unified    │
│  Oracles    │    │   Engine    │    │             │    │   Engine    │    │  LP Pool    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
      ↓                  ↓                  ↓                  ↓                  ↓
   P_raw            PI (Prob.          Entry Price       Mark Price         Single
                    Index)            (slippage)        (solvency)       counterparty
```

**Step by step:**
1. **Ingest:** External Oracles provide Raw Probability (P_raw)
2. **Smooth:** Smoothing Engine removes noise to create Probability Index (PI)
3. **Execute:** The vAMM uses Virtual Liquidity to determine Entry Price (slippage)
4. **Secure:** The Margin Engine uses PI to determine Mark Price (solvency)
5. **Back:** The Unified LP Pool acts as the single counterparty for all trades

### 1.2 The Core Decoupling Principle

> ⚠️ **IMPORTANT AF:**
> ## Entry Price ≠ Mark Price!!!

| Concept | Entry Price | Mark Price |
|---------|-------------|------------|
| **Determined by** | vAMM (e × g = k) | Probability Index (PI) |
| **Includes** | Slippage | NO slippage |
| **Reflects** | Immediate demand | Fair probability |
| **Used for** | Trade execution | PnL, Margin, Liquidations |
| **Manipulable?** | YES (flash loans) | NO (smoothed) |

**Why this matters:**
- A flash loan attack CAN manipulate the vAMM (Entry Price)
- A flash loan attack CANNOT manipulate the PI (Mark Price)
- Therefore, an attacker CANNOT force unjust liquidations
- Solvency is checked against the stable PI, not the volatile vAMM price

---

## Module 2: Phase 1 - Get the Probability Index (PI)

**Goal:** Build a manipulation-resistant price signal P_smooth before processing a single dollar

### Input Layer: The Anti-Manipulation Shield

The PI is the "God Mode" price for liquidations, protecting users from flash crashes.

```
Raw Polymarket ──────────────────────────┐
                                         │
         ╭─────────────────────────╮     │
         │   Validation Layer      │     │
         │   - Spread check        │     │
         │   - Tick movement check │     │
         │   - Liquidity check     │     │
         ╰─────────────────────────╯     │
                    │                    │
                    ▼                    │
         ╭─────────────────────────╮     │
         │   Smoothing Engine      │ ←───┘
         │   - Volatility damping  │
         │   - Time weighting      │
         ╰─────────────────────────╯
                    │
                    ▼
              Smoothed PI
         (Manipulation-Resistant)
```

### 2.1 External Price Input Layer

**Requirement:** Connections to external markets (e.g., Polymarket, Kalshi) to fetch:
- Orderbook Midpoints, OR
- Last Traded Prices

**Validation Logic — Discard updates if:**

| Check | Condition | Rationale |
|-------|-----------|-----------|
| Spread | `spread > threshold` | Wide spread = low confidence |
| Tick Movement | `Δprice > maxDeviation per block` | Large jump = potential manipulation |
| Liquidity Depth | `depth < minThreshold` | Thin book = easy to manipulate |

### 2.2 The Smoothing Engine

Three formulas combine to create manipulation resistance:

#### Formula 1: Volatility Dampening

```
w_vol = 1 / (1 + σ)
```

- **σ** = current volatility estimate
- As volatility (σ) **increases**, the weight (w_vol) **decreases**
- Result: Price becomes "stickier" and resistant to spikes
- High vol = slow to move = manipulation resistant

#### Formula 2: Time-Weighted Smoothing

```
w_time = √(τ / τ_max)
```

- **τ** = time to resolution (expiry)
- **τ_max** = maximum time horizon (e.g., 30 days)
- As time-to-resolution **approaches 0**, the smoothing factor **increases**
- Result: Price locks in stability near market expiry
- Prevents last-minute manipulation before settlement

#### Formula 3: The Update Logic

```
P_smooth(t) = P_smooth(t-1) + α × w_vol × (P_raw(t) - P_smooth(t-1))
```

**Breaking it down:**
- `P_smooth(t-1)` = previous smoothed price
- `P_raw(t)` = new raw price from oracle
- `α` = base smoothing factor (e.g., 0.1 = 10%)
- `w_vol` = volatility weight from Formula 1
- `(P_raw - P_smooth)` = the "error" to correct

**Effective smoothing:**
- Normal conditions: `α × w_vol` might be ~0.1 (responsive)
- High volatility: `α × w_vol` might be ~0.02 (sticky)
- Near expiry: Additional time weight reduces responsiveness further

---

## Module 3: Phase 2 - Pricing & Execution (The Trade)

**Goal:** Allow users to open positions with deterministic slippage while protecting the system from arbitrage

### The Decoupled Pricing Engine (Visual)

```
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│   Execution Price (vAMM)        │    │   Mark Price (Probability Index)│
│                                 │    │                                 │
│         Price                   │    │           ⚖️                    │
│           │    ╭────            │    │         ╱   ╲                   │
│    Point B│   ╱                 │    │        ╱     ╲                  │
│      ●────┼──╯  Entry Price     │    │       ╱       ╲                 │
│           │     Mark Price (PI) │    │      ╱─────────╲                │
│    Point A●─────────────────    │    │                                 │
│           │         x·y=k       │    │                                 │
│           └─────────────────    │    │                                 │
│              vQ (Virtual Quote) │    │                                 │
│                                 │    │                                 │
│  Logic: x * y = k               │    │  Logic: Output of Smoothing     │
│  Purpose: Entry Price & Slippage│    │  Purpose: Solvency & Liquidations│
│                                 │    │                                 │
│  JIT Keepers re-center price    │    │  Prevents Toxic Flow            │
│  to Oracle before execution     │    │  manipulation                   │
└─────────────────────────────────┘    └─────────────────────────────────┘
```

### 3.1 The Virtual AMM (vAMM)

**Mechanism:** Constant Product formula
```
x · y = k
```

**Virtual Liquidity:** The vAMM holds **zero real capital**
- It is purely a calculator for slippage and price discovery
- Real capital lives in the LP Pool, not the vAMM

**Initialization:** Set virtual reserves vQ and vB such that starting price matches PI:
```
vQ / vB = PI_initial
```

Where:
- vQ = Virtual Quote (e.g., virtual USDT)
- vB = Virtual Base (e.g., virtual YES tokens)

### 3.2 Anti-Arbitrage Mechanics (The "Hardened" Architecture)

#### JIT Keepers (Price Pegging)

**Requirement:** Bots must re-center the vAMM curve to the Oracle Price **before every block** to ensure traders enter at a fair price.

- This prevents "stale" execution prices
- vAMM price should always start each block at PI
- Slippage is then purely a function of trade size

#### Volatility Spread Guard

**Problem:** "Time-Travel Arbitrage" — bots trade on a fast external signal before the smoothed PI updates

**Fix:** If raw price deviates too much from smoothed:
```
If |P_raw - P_smooth| > Threshold:
    → Automatically widen the bid-ask spread on vAMM
    → Covers the uncertainty gap
```

This makes it unprofitable to front-run PI updates.

---

## Module 4: Phase 3 - Risk & Solvency (The Shield)

**Goal:** Protect the LP Pool from bad debt (insolvency)

### The Golden Rule

> ⚠️ **ALWAYS liquidate against PI, never vAMM.**

This is non-negotiable. Liquidations must use the manipulation-resistant Mark Price (PI), never the potentially-manipulated Entry Price from vAMM.

### Risk & Liquidation Logic Flow

```
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│  Initial Margin  │   │ Maintenance Margin│   │ Solvency Check   │
│       (IM)       │   │       (MM)       │   │                  │
│                  │   │                  │   │ If Equity < MM   │
│ Position Notional│   │    m × Notional  │   │ THEN Liquidate   │
│    / Leverage    │   │                  │   │                  │
│ Cost to open     │   │ Liquidation floor│   │ Equity = Collat +│
│                  │   │                  │   │ Unrealized PnL   │
└────────┬─────────┘   └────────┬─────────┘   └────────┬─────────┘
         │                      │                      │
         ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                     LIQUIDATION FLOW                            │
│                                                                 │
│  User Position    Check Health     Unhealthy?    Still Bad?    │
│  & Equity    ──▶  against PI  ──▶  (Equity<MM)  ──▶ Full Liq   │
│                       │                │              │        │
│                       ▼                ▼              ▼        │
│                   Healthy?      Partial Liq     Position       │
│                   Position      (Close 50%)     Closed         │
│                   Active                                       │
│                                                                 │
│  ⚠️ Includes 2% Liquidation Buffer to prevent micro-liquidations│
└─────────────────────────────────────────────────────────────────┘
```

### 4.1 Margin Engine - Protecting the House

**Account Health Zones:**
| Zone | Margin Level | Status |
|------|--------------|--------|
| Safe | > 10% | Position healthy |
| Warning | 5-10% | At risk |
| Liquidation | < 5% | Keeper triggered |

**Equity Calculation:**
```
Equity = Collateral + (Current_PI - Entry_Price) × Size
```

**Key:** Uses **Current PI** (Mark Price), NOT vAMM price!

**Liquidation Trigger:**
```
If Equity < Maintenance_Margin → Keeper Triggered
```

Keeper Bots automate liquidations, using PI as the oracle for execution.

### Margin Formulas

#### Initial Margin (IM) - Cost to Enter

Scales with volatility σ:
```
IM = (Notional / Leverage) × (1 + α × σ)
```

Where:
- Notional = Position size in USD
- Leverage = User's selected leverage
- α = volatility scaling factor
- σ = current market volatility

**Effect:** Higher volatility → higher initial margin required → safer

#### Maintenance Margin (MM) - Liquidation Floor

```
MM = m × Notional
```

Where:
- m = maintenance margin ratio (e.g., 0.05 = 5%)
- Notional = Position size

#### Solvency Check

```
If Equity ≤ MM → LIQUIDATE
```

### Liquidation Process

1. **Check:** Equity vs MM (using PI, never vAMM)
2. **Buffer:** 2% buffer prevents micro-liquidations
3. **Partial First:** Attempt 50% close to restore health
4. **Full if Needed:** If still unhealthy after partial, full liquidation
5. **Execution:** Keeper bots execute, LP Pool absorbs position

### 4.2 Liquidation Engine

> **Golden Rule:** ALWAYS liquidate against PI (Mark Price). NEVER liquidate against vAMM (Entry Price).

**Liquidation Hierarchy:**

| Type | Action | Goal | When |
|------|--------|------|------|
| **Partial** (Preferred) | Close 25-50% of position | Restore MR > m | First attempt |
| **Full** (Fallback) | Close 100% of position | Recover what's left | If partial fails |

**Why Partial First?**
- Avoids full closure on minor volatility
- Better for user (keeps partial position)
- Better for LP (less slippage on smaller liquidation)

**Full Liquidation:**
- Close 100% and transfer remaining collateral to LP Pool
- Only when partial liquidation fails to restore health

### 4.3 Global Open Interest (OI) Limits

**Hard Cap:** No single market can exceed e.g., **5% of Total LP Liquidity**

**Four OI Limit Types:**
1. **Platform-wide** — Total OI across all markets
2. **Per market** — Max OI for any single market
3. **Per user** — Max OI any single user can hold
4. **Per side** — Max long OI or short OI per market

**Dynamic Scaling Formula:**
```
OI_max = β × L_total × (1 / w_market)
```

Where:
- β = base scaling factor
- L_total = Total LP liquidity
- w_market = market weight/volatility factor

**Implementation Note:** High volatility markets get **lower** caps.

**Correlation Caps:**
- Enforce caps on **categories** (e.g., "US Election 2028")
- Prevents correlated wipeouts where multiple related markets move together
- Example: If 5 election markets all resolve the same way, capped exposure limits damage

---

## Module 5: LP Pool Mechanics

### 5.1 Shared LP Mechanics

**Concept:** One USDC pool acts as the counterparty for **all** markets

**Risk Netting:**
- Gains in Market A (e.g., Sports) offset losses in Market B (e.g., Politics)
- Diversification across uncorrelated markets reduces overall risk

**Bad Debt Socialization:**
```
If Equity < 0 → LP Pool absorbs the deficit
```
- Traders can't go negative — LP is the backstop
- This is why OI limits and proper liquidations matter

### 5.2 The Insurance Fund (Gap Risk Protection)

**Purpose:** Covers **Gap Risk** — the slippage between liquidation trigger and actual closing price

**Problem:** Binary markets "teleport" from 0.99 to 1.0 at settlement, potentially creating instant bad debt

**Solution:** Divert a portion of trading fees (e.g., 10%) to a segregated Insurance Fund
- This fund absorbs settlement shocks **before** the LP Pool
- LP Pool is second line of defense

**Funding:**
```
Insurance Fund += 10% × Trading Fees
```

---

## Module 6: Phase 5 - Settlement & Lifecycle

**Goal:** Handle the transition from continuous trading to binary finality

### Edge Case: The "Liquidity Trap"

**Problem:** AMM curves are asymptotic
- Cannot reach exactly 1.0 or 0.0 without infinite slippage
- Users get "stuck" at 0.99 — can't exit winning positions

**Visual:**
```
                    Track A (BLOCKED)
                    vAMM Mode Disabled
                    (Asymptotic Curve)
                         🚫
                          │
IF Probability > 95%      │
OR Time < 24 Hours  ──────┤
                          │
                         ✅
                    Track B (ACTIVE)
                    RFQ Mode
                    LPs buy out positions
```

### 6.1 The "Liquidity Trap" Fix (RFQ Mode)

**Trigger Conditions:**
- Probability > 95%, OR
- Time to expiry < 24 hours

**Solution:**
1. **Disable vAMM trading** — no more slippage-based execution
2. **Switch to RFQ (Request for Quote) mode**
3. **LPs buy out winning positions at a fixed discount**
   - Example: Buy 0.99 position for 0.98
   - Result: User exits without infinite slippage
   - LP profits on the discount if they're right

**Mechanism:** LPs submit limit orders
- Example: "I'll buy any YES position for 0.97"
- Users can hit these bids to exit

### 6.2 Settlement Logic

**Input:** External Oracle pushes Outcome (1 or 0)

**Actions:**
1. **Force PI_final = Outcome** (Override smoothing)
   ```
   PI_final = 1.0  (if YES wins)
   PI_final = 0.0  (if NO wins)
   ```

2. **Calculate Final PnL:**
   ```
   PnL_final = (PI_final - PI_entry) × Size
   ```

3. **Reset Market OI to 0** — market is closed

---

## Module 8: Borrow Fee Engine

**Goal:** Charge leveraged positions for consumption of shared LP capital, scaling costs dynamically based on risk.

**Reference:** [Google Sheet with all formulas](https://docs.google.com/spreadsheets/d/1aWCgodz1YzKsZxCMiTObuS_GDRGukdtuw0uIj4fvc2M/edit?usp=sharing)

### 8.0 What the Borrow Fee Charges

The borrow fee is the cost a trader pays for using shared LP capital to hold a leveraged position over time.
- Charged on position notional (= borrowed notional)
- Accrues hourly

### 8.1 Core Borrow Fee Formula

For position *i* during hour *h*:
```
BorrowFee_{i,h} = r_h × N_i
```

Where:
- r_h = hourly borrow rate (dynamic)
- N_i = position notional (size)

**Base Rate:**
```
r_base = 0.0002 (= 0.02% per hour)
```

### 8.2 Dynamic Borrow Rate Logic

Rate increases under stress via multiplicative risk multipliers:

```
r_h = min( r_max, r_base × M_util × M_imb × M_vol × M_ttR × M_conc )
```

**Hard Bounds (Safety Rails):**
- Min: 0.02% / hour
- Max: 0.10% / hour (capped to prevent predatory pricing)

### 8.3 Risk Multipliers

#### A) Utilization Multiplier (M_util)

**Logic:** If LP pool is depleted, borrowing costs skyrocket.

**Utilization Ratio:**
```
U = OI_global / OI_cap_global
```

**Multiplier Curve:**
```
M_util = {
  1                              if U ≤ 0.6
  1 + a(U - 0.6)²                if 0.6 < U < 1.0
  1 + a(0.4)² + b(U - 1.0)       if U ≥ 1.0
}
```
Constants: a = 10 (gentle ramp), b = 8 (punitive overflow)

- Below 60%: stays near base
- Above 60%: ramps nonlinearly
- Above cap: aggressively punitive

#### B) Imbalance Multiplier (M_imb)

**Logic:** One-sided markets = LP tail risk. Crowded side pays more.

**Imbalance Ratio:**
```
S = |OI_long - OI_short| / (OI_long + OI_short + ε)
```

**Multiplier:**
```
M_imb = 1 + c × S²
```
Constant: c = 6

Example: S = 0.8 (highly one-sided) → M_imb = 1 + 6 × 0.64 = 4.84×

#### C) Volatility Multiplier (M_vol)

**Logic:** Higher volatility = higher liquidation/oracle risk = higher cost.

**Volatility Measure:**
```
σ = stdev(Δp) over rolling window
```

**Multiplier:**
```
M_vol = 1 + d × max(0, (σ - σ_0) / σ_0)
```
Constant: d = 1.5

#### D) Time-to-Resolution Multiplier (M_ttR)

**Logic:** Binary markets unstable near expiry. Holding leverage late is taxed heavily.

**Time Variable:** T = hours to resolution

**Multiplier:**
```
M_ttR = {
  1                                    if T ≥ 48
  1 + e × ((48 - T) / 36)²            if 12 < T < 48
  1 + e + f × ((12 - T) / 12)         if T ≤ 12
}
```
Constants: e = 2, f = 3

#### E) Concentration Multiplier (M_conc)

**Logic:** Prevents excessive exposure to single market.

**Concentration Ratio:**
```
C = OI_market / (OI_global + ε)
```

**Multiplier:**
```
M_conc = 1 + g × max(0, C - C_0)
```
Constants: C_0 = 0.15 (threshold), g = 8

### 8.4 Rate Smoothing & Anti-Gaming

**EMA Smoothing:**
```
r_h = α × r_h_raw + (1 - α) × r_{h-1}
```
Where α = 0.15

**Anti-Gaming:** Rate may not increase by more than +25% per hour.

### 8.5 Hard Rate Bounds

```
r_min = 0.02% / hour
r_max = 0.10% / hour

r_h = clip(r_h, r_min, r_max)
```

### 8.6 Concrete Examples

**Example 1: Normal Conditions**
```
r = 0.02% × 1.06 = 0.0212% / hour
```

**Example 2: High Stress Market**
```
Raw multipliers: 1.9 × 3.16 × 1.3 × 2.0 × 1.2 ≈ 18.7
Raw rate: 0.02% × 18.7 = 0.374% / hour
Final rate: 0.10% / hour (capped at max)
```

### 8.7 On-Chain Accounting

**Key:** We do NOT iterate through positions hourly. Use Global Borrow Index (like Aave/Compound).

**Global Borrow Index:**
```
B(t) = B(t_0) × e^(r × (t - t_0))
```

**User Debt Calculation:**
```
Debt_current = N × (B(t) / B_entry - 1)
```

Where:
- N = position notional
- B(t) = current global index
- B_entry = index when position opened

---

## Fee Architecture — Full Overview

**Three distinct fee types, each with a different purpose. This separation is intentional and critical for stability.**

> No single fee does more than one job.

### 1️⃣ Trading Fee (Execution Fee)

**What it is:** A one-time fee charged when a position is opened or closed.

**Why it exists:**
- Pays for execution
- Scales with volume
- Predictable revenue source
- Familiar to traders

**How it's charged:**
- Applied to notional size
- Charged on: open, close (or round-trip)

**Example:**
```
Trading fee: 0.10%
$10,000 position open → $10 fee
$10,000 close → $10 fee
Total round-trip: $20
```

**Distribution:**
| Recipient | Share |
|-----------|-------|
| LPs | 50% |
| Protocol | 30% |
| Insurance Fund | 20% |

**Behavioral effect:**
- Discourages spam trading
- Encourages meaningful position sizing
- Rewards liquidity providers as volume grows

---

### 2️⃣ Borrow Fee (Cost of Leverage)

**What it is:** A time-based fee for using LP capital to hold a leveraged position. **This is the most important fee in the system.**

**Why it exists:**
- Prices risk over time
- Protects LPs
- Discourages excessive holding
- Scales under stress

**How it's charged:**
- Charged hourly
- Based on position notional
- Accrued continuously via borrow index

**Base rate:** 0.02% per hour

**Dynamic behavior — rate increases when:**
- System utilization rises
- One side is crowded
- Volatility spikes
- Resolution approaches
- Exposure becomes concentrated

**Properties:**
- Published in advance
- Fixed for the next hour
- Changed within hard bounds (0.02% - 0.10%)

**Distribution:**
| Recipient | Share |
|-----------|-------|
| LPs | 50% |
| Protocol | 30% |
| Insurance Fund | 20% |

**Behavioral effect:**
- Penalizes slow, crowded positions
- Encourages faster, information-driven trades
- Automatically pushes traders out when risk increases

> This is how the protocol "pushes back" instead of absorbing risk.

---

### 3️⃣ Funding Fee (Trader → Trader)

**What it is:** A periodic payment between traders, **not a protocol fee.**

**Why it exists:**
- Balances long vs short open interest
- Penalizes crowding
- Reduces LP directional exposure

**How it works:**
- If longs are crowded → longs pay shorts
- If shorts are crowded → shorts pay longs

Funding rate is derived from **OI imbalance**, not price direction.

**Key property:**
- **Zero-sum** — what longs pay, shorts receive (and vice versa)
- Protocol does NOT earn funding
- LPs do NOT earn funding

**Behavioral effect:**
- Nudges traders to the less crowded side
- Prevents runaway one-sided markets
- Improves capital efficiency

> Funding corrects behavior. Borrow fees price risk.

---

## Position Ledger (Core State / Source of Truth)

### What It Is

The Position Ledger is the protocol's **single source of truth** for every user's open exposure.

It answers ONLY: "What does this trader currently own, what collateral backs it, and what fees have accrued?"

**Key Principle:** All other engines (pricing, borrow, funding, margin, liquidation) only READ the ledger and compute against it. Only core trading/liquidation flows are allowed to MUTATE it.

This separation keeps the system auditable and prevents hidden risk from being stored in off-chain services or pricing oracles.

### Responsibilities

The Position Ledger must:
1. Store each user's open position state per market (or per position ID)
2. Track collateral, notional exposure, entry price, and side (long/short)
3. Track fee accrual indices at time of last settlement:
   - Borrow index
   - Funding index
4. Support **lazy settlement** (fees/PnL computed on interaction, not continuously)
5. Provide deterministic reads for:
   - Current position health (equity, maintenance margin, liquidation eligibility)
   - Current exposure for OI/margin enforcement
6. Emit events for indexers/UI

### Data Model (Minimum Fields)

**Position struct (MVP):**
```solidity
struct Position {
    address owner;
    uint256 marketId;
    Side side;                        // enum: Long/Short
    bool isOpen;
    uint256 size;                     // position size in USDC notional
    uint256 collateral;               // margin posted in USDC
    uint256 entryPI;                  // fixed-point probability (e.g., 1e18 = 1.0)
    uint256 entryBorrowIndex;         // (optional, for debugging)
    uint256 lastBorrowIndexSnapshot;  // global borrow index at last settlement
    int256 lastFundingIndexSnapshot;  // global funding index at last settlement (signed)
    uint256 lastSettledTimestamp;
    uint256 closedAt;
    uint256 closedPI;
    int256 pnlRealized;
}
```

**Global/Market Aggregates:**
```solidity
uint256 totalLongOI;          // total long OI for market
uint256 totalShortOI;         // total short OI for market
uint256 totalGlobalOI;        // total OI across all markets
```

### Ledger Invariants (Must Always Be True)

1. **No negative balances:** `collateral >= 0` always
2. **OI accounting consistency:**
   - Position opens/increases → totalLongOI/totalShortOI increase by delta
   - Position closes/decreases/liquidates → they decrease by delta
3. **Fee settlement consistency:**
   - After settlement, snapshots update to latest indices
   - Snapshots never move backwards in time
4. **No logical overflow**
5. **Any state change that increases notional must pass cap/leverage checks**

### Ledger Operations (Required Functions)

#### 1. Open / Increase Position

**Inputs:** marketId, side, collateralAmount, leverage, maxSlippage

**Steps:**
1. Settle accrued fees on existing position (if open)
2. Compute new notional delta
3. Enforce caps + leverage
4. Update position: snapshots, notional, entryPrice (weighted avg if increasing)
5. Update snapshots → lastBorrowIndexSnapshot, etc.
6. Update OI aggregates
7. Emit events

#### 2. Close / Decrease Position

**Inputs:** marketId, closeAmountOrPercent (or close all)

**Steps:**
1. Settle accrued fees
2. Compute PnL from current price
3. Reduce position notional, return collateral + PnL (if any)
4. Update snapshots + OI aggregates
5. If fully closed: set `isOpen = false`
6. Emit events

#### 3. Settle Fees (Lazy Accrual)

Called internally on open/close/liq/update. Does nothing if already settled this block/tx.

```
borrow_owed = notional × (borrowIndexNow / borrowIndexSnapshot - 1)
funding_owed = notional × (fundingIndexNow - fundingIndexSnapshot)
```

Applies to collateral (debit/credit), scales fees appropriately, updates snapshots.

#### 4. Liquidation

**Inputs:** marketId, user

**Steps:**
1. Settle fees
2. Derive equity and check liquidation condition
3. Close position (full liquidation in MVP)
4. Apply liquidation penalty
5. Route penalty (to LP/Insurance)
6. Emit events

### Interaction With Other Engines

| Engine | Interaction | Read/Write |
|--------|-------------|------------|
| **Price Engine** | Provides markPrice, entryPrice | READ only |
| **Risk & Capital** | Provides caps, max leverage, borrow index | READ (ledger stores snapshots) |
| **Funding Engine** | Ledger stores funding snapshots, redraws on settlement | READ (stores snapshots) |
| **Margin Engine** | Reads ledger + mark price + fees → compute equity/MM | READ only |
| **Liquidation Engine** | Calls ledger mutation path when condition met | WRITE (via liquidate()) |

**Key:** Ledger stores `entryPI`, does NOT depend on pricing oracle for state.

### Events (Minimum)

```solidity
event PositionOpened(address user, uint256 marketId, Side side, uint256 notional, uint256 leverage, uint256 entryPrice);
event PositionIncreased(...);
event PositionDecreased(...);
event PositionClosed(address user, uint256 marketId, Side side, uint256 notional, uint256 entryPrice, uint256 exitPrice, int256 pnl, uint256 fees);
event FeesSettled(address user, uint256 marketId, uint256 borrowFee, int256 fundingPayment, uint256 newCollateral);
event Liquidated(address user, uint256 marketId, uint256 notional, uint256 penalty, address liquidator);
```

---

## Implementation Checklist

### PriceEngineV2.sol (Smoothing Engine) ✅
- [x] Market expiry timestamps
- [x] Volatility calculation from price history
- [x] Formula 1: `w_vol = 1/(1+σ)`
- [x] Formula 2: `w_time = √(τ/τ_max)`
- [x] Formula 3: Combined update logic
- [x] Input validation (spread, tick, liquidity)
- [x] Settlement function for expired markets

### vAMM.sol (NEW - needs creation)
- [ ] Constant product formula: x · y = k
- [ ] Virtual reserves (vQ, vB) - no real capital
- [ ] Initialize: vQ/vB = PI_initial
- [ ] Re-centering function for JIT keepers
- [ ] Volatility Spread Guard: widen spread when |P_raw - P_smooth| > threshold
- [ ] Calculate execution price with slippage
- [ ] Separate from Mark Price completely

### Keeper V2 ✅
- [x] Fetch from Polymarket CLOB (orderbook)
- [x] Calculate spread from bid/ask
- [x] Calculate liquidity depth
- [x] Pass validation data to contract
- [x] Skip expired markets

### JIT Keeper (NEW - needs creation)
- [ ] Re-center vAMM to PI before each block
- [ ] Triggered before user trades execute
- [ ] Ensures fair entry prices

### Frontend
- [x] LP APY display
- [ ] **Market Page must show:**
  - LIVE Price: Real-time Polymarket (raw) — shown on chart
  - Mark Price: Smoothed PI from PriceEngineV2 — shown as label/indicator
  - Market Expiry: Date + countdown (e.g., "Expires: Nov 5, 2028 (892 days)")
  - Users see both prices to understand why liquidations use Mark Price

### RiskEngine Updates (from Module 4)
- [ ] Equity calculation: `Collateral + (PI - Entry) × Size`
- [ ] Initial Margin: `(Notional/Leverage) × (1 + α × σ)` — scales with volatility
- [ ] Maintenance Margin: `m × Notional`
- [ ] Solvency check: `Equity ≤ MM → LIQUIDATE`
- [ ] 2% liquidation buffer to prevent micro-liquidations
- [ ] Partial liquidation (25-50%) before full liquidation
- [ ] **MUST use PI (PriceEngineV2.getMarkPrice()), never vAMM**

### OI Limits (from Module 4.3)
- [ ] Platform-wide OI cap
- [ ] Per-market OI cap (e.g., 5% of LP liquidity)
- [ ] Per-user OI cap
- [ ] Per-side OI cap (long/short)
- [ ] Dynamic scaling: `OI_max = β × L_total × (1/w_market)`
- [ ] Correlation caps for market categories

### Insurance Fund (from Module 5.2)
- [ ] Segregated vault for gap risk protection
- [ ] 10% of trading fees diverted to insurance
- [ ] Insurance absorbs settlement shocks before LP Pool

### Settlement & RFQ Mode (from Module 6)
- [ ] Detect when Probability > 95% OR Time < 24hr
- [ ] Disable vAMM, enable RFQ mode
- [ ] LP limit order system for RFQ
- [ ] Settlement: Force PI_final = Outcome (1 or 0)
- [ ] Final PnL: `(PI_final - PI_entry) × Size`
- [ ] Reset market OI to 0 on settlement

### Position Ledger (Source of Truth)
- [ ] Position struct with all fields (owner, marketId, side, size, collateral, entryPI, snapshots)
- [ ] Global aggregates (totalLongOI, totalShortOI, totalGlobalOI)
- [ ] Lazy fee settlement (borrow + funding)
- [ ] Operations: open, increase, close, decrease, liquidate
- [ ] Invariants enforced (no negative, OI consistency, caps)
- [ ] Events for indexers
- [ ] Read-only interface for other engines

### Borrow Fee Engine (from Module 8)
- [ ] Core formula: `BorrowFee = r_h × N_i`
- [ ] Dynamic rate: `r_h = min(r_max, r_base × M_util × M_imb × M_vol × M_ttR × M_conc)`
- [ ] 5 multipliers: Utilization, Imbalance, Volatility, Time-to-Resolution, Concentration
- [ ] EMA smoothing (α = 0.15)
- [ ] Hard bounds: 0.02% - 0.10% per hour
- [ ] +25% max increase per hour (anti-gaming)
- [ ] Global Borrow Index: `B(t) = B(t_0) × e^(r × (t - t_0))`
- [ ] User debt: `N × (B(t) / B_entry - 1)`

### Contracts to Update
- [ ] RiskEngine: Implement Module 4 formulas, use PI only
- [ ] Router: Use vAMM for entry price, PriceEngineV2 for mark price
- [ ] FundingEngine: Use PI for funding calculations
- [ ] LPPool: Add insurance fund split (10% of fees)
- [ ] Settlement contract: Oracle-triggered market resolution
- [ ] BorrowFeeEngine: Implement Module 8 formulas

---

## Key Invariants

1. **Liquidations ONLY use Mark Price (PI)** — never Entry Price
2. **Entry Price can deviate from Mark Price** — this is expected (slippage)
3. **Flash loans cannot trigger liquidations** — PI is smoothed
4. **Near expiry, price becomes very sticky** — prevents last-minute manipulation
5. **High volatility = slow price movement** — self-stabilizing

---

*Last updated: 2026-02-06 14:00 UTC*
*Source: Eric's architecture doc*
