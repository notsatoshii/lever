# WORKLOG - Active Task Log

## Status as of 2026-02-06 21:35 UTC

### Session Summary (21:11 - 21:35 UTC)

#### Contract Development - Position ID System (V4/V6)
Eric requested ability to have **multiple positions per market** (long AND short simultaneously). Current V3 system only allows one position per market per user.

**Created new contracts:**
- ✅ `PositionLedgerV4.sol` — Position ID model, each position has unique ID
- ✅ `RouterV6.sol` — Works with position IDs, returns positionId on open
- ✅ Both compile successfully

**Key changes in V4/V6:**
- `mapping(uint256 => Position) positions` — positionId-based, not (user, marketId)
- `openPosition()` returns `positionId`
- `closePosition(positionId)` — explicit close by ID
- Supports unlimited positions per market per user
- Long AND short can coexist in same market

**NOT DEPLOYED YET** — Scheduled for tomorrow (Feb 7)

#### Test Positions Opened
Eric provided testnet deployer key. Opened positions on correct router:

**Correct Router:** `0xee92ef898a0eabca96cad863cb0303b6d13cc023` (RouterV5)
**NOT the old one in WORKLOG:** ~~0x346D9eC78F8437c2aa32375584B959ccCDc843E1~~

**Positions opened ($3000 collateral, 3x leverage each):**
| Market | Result | Direction | Notional |
|--------|--------|-----------|----------|
| 0 | ❌ Failed | - | (existing) |
| 1 | ✅ Success | SHORT | $9,000 |
| 2 | ✅ Success | LONG | $9,000 |
| 3 | ✅ Success | SHORT | $9,000 |
| 4 | ❌ Failed | - | (existing) |
| 5 | ❌ Failed | - | (existing) |
| 6 | ✅ Success | LONG | $9,000 |
| 7 | ✅ Success | SHORT | $9,000 |
| 8 | ❌ Failed | - | (existing) |
| 9 | ✅ Success | SHORT | $9,000 |

**Total new positions:** 6 × $3,000 = $18,000 collateral, $54,000 notional
**4 failed** because markets already had positions (V3 limitation)

#### Frontend Fix - Recent Trades
Fixed `RecentTrades` component — was showing "No trades yet" because it had a TODO placeholder.

**Now fetches real data:**
- Reads `PositionOpened` events from Router contract
- Last ~2000 blocks (~1.5 hours)
- Shows: Time, Side, Size, Price, TX link
- Auto-refreshes every 30 seconds

**File changed:** `frontend/src/app/markets/[id]/page.tsx`
**Frontend restarted:** `sudo systemctl restart lever-frontend`

---

## Current Deployments (CORRECTED)

### Production Contracts (BSC Testnet)
| Contract | Address |
|----------|---------|
| **USDT (Mock)** | `0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58` |
| **RouterV5** | `0xee92ef898a0eabca96cad863cb0303b6d13cc023` |
| **PositionLedgerV3** | `0x74b24940c76c53cb0e9f0194cc79f6c08cf79f73` |
| **vAMM** | `0xab015ae92092996ad3dc95a8874183c0fb5f9938` |
| **PriceEngineV2** | `0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC` |
| **SimpleRiskEngine** | `0x543ccad81a2eded2dc785272fcba899512a161b4` |
| **BorrowFeeEngineV2** | `0xc68e5b17f286624E31c468147360D36eA672BD35` |
| **FundingEngine** | `0xa6Ec543C82c564F9Cdb9a7e7682C68A43D1af802` |
| **LP Pool** | `0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1` |
| **Insurance Fund** | `0xB8CA10ADbE4c0666eF701e0D0aeB27cFC5b81932` |

### Deployer/Test Wallet
- **Address:** `0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc`
- **USDT Balance:** ~8.7M (testnet)
- **Is owner of:** USDT, Router, Ledger, vAMM, RiskEngine

### Running Services
- **Frontend:** http://165.245.186.254:3001 (systemd: `lever-frontend`)
- **Keeper v3:** Syncing prices every 30s

### LP Pool Stats
- **TVL:** ~$1M USDT
- **Utilization:** Varies with position OI

---

## Live Markets (10) - Market IDs 0-9
| ID | Market | Category |
|----|--------|----------|
| 0 | Indiana Pacers NBA Finals | Sports |
| 1 | Patriots Super Bowl 2026 | Sports ⚠️ Feb 8 |
| 2 | Seahawks Super Bowl 2026 | Sports ⚠️ Feb 8 |
| 3 | Jesus returns before GTA VI | General |
| 4 | Celtics NBA Finals | Sports |
| 5 | Thunder NBA Finals | Sports |
| 6 | BTC $1M before GTA VI | Crypto |
| 7 | van der Plas PM Netherlands | Politics |
| 8 | GTA 6 costs $100+ | General |
| 9 | Timberwolves NBA Finals | Sports |

---

## Tomorrow's Tasks (Feb 7)
1. **Deploy PositionLedgerV4 + RouterV6** — Enable multiple positions per market
2. **Update frontend** — Support position IDs, display multiple positions
3. **Migrate any existing positions** if needed
4. **Test before Super Bowl** (Feb 8)

---

## GitHub
- **Repo:** https://github.com/notsatoshii/lever
- **New contracts added but not committed yet:**
  - `contracts/src/PositionLedgerV4.sol`
  - `contracts/src/RouterV6.sol`

---

## Key Findings This Session
1. **Address mismatch:** Old WORKLOG had wrong router address. Frontend config (`contracts.ts`) has the correct one.
2. **V3 limitation confirmed:** Can't have long+short in same market. User gets "failed" when trying to open opposite direction.
3. **Recent Trades was broken:** Just a placeholder, now fixed to fetch real events.
