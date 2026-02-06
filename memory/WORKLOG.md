# WORKLOG - Active Task Log

## Status as of 2026-02-06 21:50 UTC

### 🚀 MAJOR UPDATE: V4/V6 DEPLOYED AND LIVE

#### New Contracts (Position ID Model)
| Contract | Address |
|----------|---------|
| **PositionLedgerV4** | `0x63477383dcA29747790b46dD5052fCA333D6A985` |
| **RouterV6** | `0xF8d1b25b8cdf5C5e9a55f6E34f97e4E86ea387bB` |

#### What's New
- ✅ **Multiple positions per market** — Can have LONG and SHORT simultaneously
- ✅ **Position IDs** — Each position has unique ID
- ✅ **Explicit close** — `closePosition(positionId)` instead of marketId
- ✅ **7 positions migrated** from V3 to V4

#### Migration Complete
Positions migrated (positionIds 1-7):
- Market 1: SHORT $9k (ID: 1)
- Market 2: LONG $44k (ID: 2)
- Market 3: SHORT $9k (ID: 3)
- Market 5: SHORT $25k (ID: 4)
- Market 6: LONG $9.37k (ID: 5)
- Market 7: SHORT $9.6k (ID: 6)
- Market 9: SHORT $8.3k (ID: 7)

#### Frontend Updated
- ✅ `contracts.ts` — New Router/Ledger addresses
- ✅ `PositionPanel.tsx` — Works with position IDs, shows multiple positions
- ✅ `portfolio/page.tsx` — Uses getUserOpenPositions, shows position IDs
- ✅ `priceUpdater.ts` — Fixed PriceEngine address
- ✅ `RecentTrades` — Fixed to fetch real events

---

## Current Production Contracts (BSC Testnet)

### V6/V4 System (ACTIVE)
| Contract | Address |
|----------|---------|
| **USDT (Mock)** | `0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58` |
| **RouterV6** | `0xF8d1b25b8cdf5C5e9a55f6E34f97e4E86ea387bB` |
| **PositionLedgerV4** | `0x63477383dcA29747790b46dD5052fCA333D6A985` |
| **vAMM** | `0xAb015aE92092996ad3dc95a8874183c0Fb5f9938` |
| **PriceEngineV2** | `0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC` |
| **SimpleRiskEngine** | `0x543ccaD81A2EDEd2dc785272fCba899512a161B4` |
| **BorrowFeeEngineV2** | `0xc68e5b17f286624E31c468147360D36eA672BD35` |
| **FundingEngine** | `0xa6Ec543C82c564F9Cdb9a7e7682C68A43D1af802` |
| **LP Pool** | `0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1` |
| **Insurance Fund** | `0xB8CA10ADbE4c0666eF701e0D0aeB27cFC5b81932` |

### Deprecated V5/V3 (kept for reference)
| Contract | Address |
|----------|---------|
| RouterV5 | `0xee92ef898a0eabca96cad863cb0303b6d13cc023` |
| PositionLedgerV3 | `0x74b24940c76c53cb0e9f0194cc79f6c08cf79f73` |

### Deployer/Test Wallet
- **Address:** `0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc`
- **Is owner of:** All contracts

---

## Running Services
- **Frontend:** http://165.245.186.254:3001 (systemd: `lever-frontend`)
- **Keeper v3:** Syncing prices every 30s

---

## Live Markets (10) - Market IDs 0-9
| ID | Market | Category |
|----|--------|----------|
| 0 | Indiana Pacers NBA Finals | Sports |
| 1 | Patriots Super Bowl 2026 | Sports ⚠️ **Feb 8** |
| 2 | Seahawks Super Bowl 2026 | Sports ⚠️ **Feb 8** |
| 3 | Jesus returns before GTA VI | General |
| 4 | Celtics NBA Finals | Sports |
| 5 | Thunder NBA Finals | Sports |
| 6 | BTC $1M before GTA VI | Crypto |
| 7 | van der Plas PM Netherlands | Politics |
| 8 | GTA 6 costs $100+ | General |
| 9 | Timberwolves NBA Finals | Sports |

---

## Session Summary (21:11 - 21:50 UTC)

1. **Investigated why FE trades were failing** — Wrong PriceEngine address in priceUpdater.ts
2. **Created PositionLedgerV4 + RouterV6** — Position ID model for multiple positions per market
3. **Deployed V4/V6 contracts** — Via forge script
4. **Migrated 7 positions** from V3 to V4
5. **Updated frontend** — New ABIs, PositionPanel, portfolio page
6. **Fixed RecentTrades** — Now fetches real PositionOpened events

---

## GitHub
- **Repo:** https://github.com/notsatoshii/lever
- **Latest commit:** `bca9ecd` - feat: Position ID system (V4/V6) + Recent Trades fix

---

## Next Steps
- Test opening multiple positions in same market
- Test closing individual positions by ID
- Super Bowl markets expire **Feb 8** — 2 days!
