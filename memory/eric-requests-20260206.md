# Eric's Frontend Requests - 2026-02-06

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
