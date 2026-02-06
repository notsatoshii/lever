# Eric's Frontend Requests - 2026-02-06

## Completed ✅

1. **Polymarket Integration** - Fetch real market data from Polymarket API instead of hardcoded markets
2. **USDC → USDT** - Change all references from USDC to USDT throughout the frontend
3. **LP Pool Fee Display** - Show borrow fees/trading fees in the LP pool page (added cumulative fees, pending fees, claim button)
4. **Market Cards** - Display real Polymarket questions, prices, volume, categories

## In Progress / Discussed 🔄

5. **LP Pool Utilization** - Currently shows 0% (correct, no positions open yet). Eric asked about this - options:
   - Keep honest (0% until real trades)
   - Add mock "demo" stats for investor presentations

## Not Yet Started ❌

(None explicitly requested beyond the above)

## Technical Notes

- Frontend live at: http://165.245.186.254:3001
- Contracts deployed on BSC Testnet (chain 97)
- LP Pool address: 0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1
- Using Polymarket gamma API: https://gamma-api.polymarket.com

## Context for Future Sessions

- This is for LEVER Protocol demo/investor presentations
- Eric wants it to look polished and functional
- Real Polymarket data integration is working
- On-chain contracts are deployed and functional
- Main gap: no actual trading activity yet (empty utilization/volume)
