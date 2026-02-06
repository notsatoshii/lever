# LEVER Frontend - Testing Guide

## Quick Start Testing

### 1. Mobile Responsiveness Test (5 minutes)

**In Chrome DevTools:**
1. Open DevTools (F12)
2. Click device toggle (Ctrl+Shift+M)
3. Test these viewports:
   - iPhone SE (375px) ✓
   - iPhone 12 Pro (390px) ✓
   - iPad (768px) ✓
   - Desktop (1440px) ✓

**Pages to test:**
- `/` - Home/Markets list
- `/markets/1` - Market detail
- `/portfolio` - Portfolio page
- `/lp` - LP page

**What to check:**
- ✅ No horizontal scroll
- ✅ All text readable
- ✅ Buttons tappable (44px min)
- ✅ Forms usable
- ✅ Navigation works

---

### 2. Loading States Test (3 minutes)

**Throttle network in DevTools:**
1. Open DevTools Network tab
2. Select "Slow 3G" from dropdown
3. Reload pages

**What to check:**
- ✅ Skeleton loaders appear immediately
- ✅ No "flash of empty content"
- ✅ Smooth transition to loaded state
- ✅ Button loading states show text

---

### 3. Error Handling Test (5 minutes)

**Scenarios to test:**

#### Invalid Input:
1. Go to market detail page
2. Trading panel:
   - Enter negative number → Should prevent
   - Enter too many decimals → Should round
   - Enter more than balance → Warning shows
   - Leave empty and click trade → Tooltip explains

#### Network Errors:
1. Open DevTools Network tab
2. Select "Offline"
3. Try to approve/trade
4. Check toast notifications appear

#### Wallet Errors:
1. Disconnect wallet
2. Try to trade → Button says "Connect Wallet"
3. Connect wallet
4. Try to trade with 0 balance → Error toast

**What to check:**
- ✅ Toast notifications appear
- ✅ Error messages are user-friendly
- ✅ No silent failures
- ✅ Buttons show loading state

---

### 4. Visual Consistency Test (2 minutes)

**Check these colors match:**

| Element | Expected Color | Hex |
|---------|---------------|-----|
| Long positions | Green | #22c55e |
| Short positions | Red | #ef4444 |
| Primary buttons | Blue | #3b82f6 |
| Cards background | Gray-800 | #1f2937 |
| Borders | Gray-700 | #374151 |

**Check spacing:**
- All cards: `padding: 1.5rem` (p-6)
- Section gaps: `gap: 1.5rem` (gap-6)
- Consistent throughout

---

### 5. Accessibility Test (3 minutes)

**Keyboard navigation:**
1. Unplug mouse (or don't use it)
2. Press Tab repeatedly
3. Check:
   - ✅ All interactive elements focusable
   - ✅ Focus indicator visible (blue ring)
   - ✅ Tab order makes sense
   - ✅ Can navigate entire app

**Focus indicators:**
- All buttons should show blue ring on focus
- All links should show blue ring on focus
- All inputs should show blue ring on focus

---

## Automated Testing Commands

```bash
# Install dependencies (if not already)
npm install

# Run linter
npm run lint

# Build for production
npm run build

# Check TypeScript
npx tsc --noEmit

# Run development server
npm run dev
```

---

## Browser Testing Checklist

### Desktop Browsers:
- [ ] Chrome (latest)
- [ ] Firefox (latest)
- [ ] Safari (latest)
- [ ] Edge (latest)

### Mobile Browsers:
- [ ] iOS Safari (most important for Web3)
- [ ] Chrome Android
- [ ] Firefox Mobile

---

## Wallet Testing Checklist

### Wallets to test:
- [ ] MetaMask
- [ ] WalletConnect
- [ ] Coinbase Wallet
- [ ] Trust Wallet

### Scenarios:
1. [ ] Connect wallet
2. [ ] Switch networks (to BSC Testnet)
3. [ ] Approve token
4. [ ] Open position
5. [ ] Close position
6. [ ] Deposit LP
7. [ ] Withdraw LP
8. [ ] Disconnect wallet
9. [ ] Reject transaction
10. [ ] Out of gas

---

## Known Issues to Verify

1. **Logo 404** - Check if /public/lever-logo.svg exists
   - If not, fallback shows "LEVER" text ✅

2. **Toast stacking** - Open 10+ toasts quickly
   - Should auto-dismiss, not overflow ✅

3. **Mobile menu** - Click outside menu
   - Currently doesn't close (minor issue) ⚠️

4. **Table scroll** - Portfolio on mobile
   - Should scroll horizontally ✅

---

## User Flow Testing

### Complete Trading Flow:
1. [ ] Browse markets (home page)
2. [ ] Click on a market
3. [ ] See price chart and stats
4. [ ] Connect wallet
5. [ ] Enter collateral amount
6. [ ] Select leverage
7. [ ] Approve USDC (if needed)
8. [ ] Open long/short position
9. [ ] See success toast
10. [ ] Navigate to portfolio
11. [ ] See open position
12. [ ] Go back to market
13. [ ] Close position
14. [ ] See success toast

### Complete LP Flow:
1. [ ] Navigate to /lp
2. [ ] See pool stats
3. [ ] Connect wallet
4. [ ] Enter deposit amount
5. [ ] Approve USDC
6. [ ] Deposit
7. [ ] See success toast
8. [ ] See LP balance update
9. [ ] Navigate to portfolio
10. [ ] See LP position
11. [ ] Return to /lp
12. [ ] Withdraw
13. [ ] See success toast

---

## Performance Testing

### Lighthouse Audit:
1. Open DevTools
2. Go to Lighthouse tab
3. Run audit (mobile + desktop)
4. Target scores:
   - Performance: > 90
   - Accessibility: > 90
   - Best Practices: > 90
   - SEO: > 80

### Bundle Size:
```bash
npm run build
# Check .next/static folder size
# Should be < 500KB for main bundle
```

---

## Regression Testing

After any changes, verify:
1. [ ] All pages still load
2. [ ] No console errors
3. [ ] Wallet connection works
4. [ ] Trades execute
5. [ ] LP deposits/withdraws work
6. [ ] Mobile layout intact
7. [ ] Toasts appear
8. [ ] Colors consistent

---

## Bug Reporting Template

When you find an issue, report it like this:

```markdown
**Title:** [Component] Brief description

**Severity:** Critical / High / Medium / Low

**Steps to Reproduce:**
1. Go to [page]
2. Click [button]
3. See [error]

**Expected Behavior:**
Should [do what]

**Actual Behavior:**
Instead [does what]

**Screenshots:**
[Attach if visual]

**Environment:**
- Browser: Chrome 120
- Device: iPhone 14
- Network: BSC Testnet
- Wallet: MetaMask
```

---

## Success Criteria

Before considering testing complete, verify:

### Critical (Must Pass):
- ✅ All pages load without errors
- ✅ Wallet connection works
- ✅ Trades can be executed
- ✅ LP deposits work
- ✅ Mobile responsive on iPhone
- ✅ No console errors

### Important (Should Pass):
- ✅ Loading states show
- ✅ Error toasts appear
- ✅ Colors consistent
- ✅ Spacing consistent
- ✅ Keyboard navigation works

### Nice to Have:
- ⚠️ Perfect Lighthouse scores
- ⚠️ Works on all browsers
- ⚠️ All animations smooth

---

## Contact

If you find issues during testing:
1. Check CHANGELOG.md for known issues
2. Check UX-AUDIT.md for documented gaps
3. Report new issues to the team

---

*Happy Testing! 🧪*
