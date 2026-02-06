// LEVER Protocol Markets Configuration
// Maps on-chain market IDs to Polymarket slugs and metadata
// Last updated: 2026-02-06 - Migrated to LedgerV3 (markets 0-9)

export interface MarketConfig {
  id: number;
  name: string;
  question: string;
  slug: string; // Polymarket slug
  category: 'Crypto' | 'Politics' | 'Finance' | 'Sports' | 'General';
  icon: string;
  active: boolean;
  expiry: string; // ISO date string
}

// On-chain markets with their Polymarket mappings
// IMPORTANT: Market IDs changed from 1-10 to 0-9 after LedgerV3 migration
export const LEVER_MARKETS: MarketConfig[] = [
  {
    id: 0,
    name: 'Indiana Pacers NBA',
    question: 'Will the Indiana Pacers win the 2026 NBA Finals?',
    slug: 'will-the-indiana-pacers-win-the-2026-nba-finals',
    category: 'Sports',
    icon: '🏀',
    active: true,
    expiry: '2026-07-01',
  },
  {
    id: 1,
    name: 'Patriots Super Bowl',
    question: 'Will the New England Patriots win Super Bowl 2026?',
    slug: 'will-the-new-england-patriots-win-super-bowl-2026',
    category: 'Sports',
    icon: '🏈',
    active: true,
    expiry: '2026-02-08', // 2 days!
  },
  {
    id: 2,
    name: 'Seahawks Super Bowl',
    question: 'Will the Seattle Seahawks win Super Bowl 2026?',
    slug: 'will-the-seattle-seahawks-win-super-bowl-2026',
    category: 'Sports',
    icon: '🏈',
    active: true,
    expiry: '2026-02-08', // 2 days!
  },
  {
    id: 3,
    name: 'Jesus/GTA VI',
    question: 'Will Jesus Christ return before GTA VI?',
    slug: 'will-jesus-christ-return-before-gta-vi-665',
    category: 'General',
    icon: '✝️',
    active: true,
    expiry: '2026-07-31',
  },
  {
    id: 4,
    name: 'Celtics NBA',
    question: 'Will the Boston Celtics win the 2026 NBA Finals?',
    slug: 'will-the-boston-celtics-win-the-2026-nba-finals',
    category: 'Sports',
    icon: '🍀',
    active: true,
    expiry: '2026-07-01',
  },
  {
    id: 5,
    name: 'Thunder NBA',
    question: 'Will the Oklahoma City Thunder win the 2026 NBA Finals?',
    slug: 'will-the-oklahoma-city-thunder-win-the-2026-nba-finals',
    category: 'Sports',
    icon: '⚡',
    active: true,
    expiry: '2026-07-01',
  },
  {
    id: 6,
    name: 'BTC $1M/GTA VI',
    question: 'Will Bitcoin hit $1M before GTA VI?',
    slug: 'will-bitcoin-hit-1m-before-gta-vi-872',
    category: 'Crypto',
    icon: '₿',
    active: true,
    expiry: '2026-07-31',
  },
  {
    id: 7,
    name: 'van der Plas PM',
    question: 'Will Caroline van der Plas become the next Prime Minister of the Netherlands?',
    slug: 'will-caroline-van-der-plas-become-the-next-prime-minister-of-the-netherlands',
    category: 'Politics',
    icon: '🇳🇱',
    active: true,
    expiry: '2026-12-31',
  },
  {
    id: 8,
    name: 'GTA 6 $100+',
    question: 'Will GTA 6 cost $100+?',
    slug: 'will-gta-6-cost-100',
    category: 'General',
    icon: '🎮',
    active: true,
    expiry: '2026-02-28',
  },
  {
    id: 9,
    name: 'Timberwolves NBA',
    question: 'Will the Minnesota Timberwolves win the 2026 NBA Finals?',
    slug: 'will-the-minnesota-timberwolves-win-the-2026-nba-finals',
    category: 'Sports',
    icon: '🐺',
    active: true,
    expiry: '2026-07-01',
  },
];

// Get market by ID
export function getMarketById(id: number): MarketConfig | undefined {
  return LEVER_MARKETS.find(m => m.id === id);
}

// Get all active markets
export function getActiveMarkets(): MarketConfig[] {
  return LEVER_MARKETS.filter(m => m.active);
}

// Get market by Polymarket slug
export function getMarketBySlug(slug: string): MarketConfig | undefined {
  return LEVER_MARKETS.find(m => m.slug === slug);
}

// Check if market is expiring soon (within 7 days)
export function isExpiringSoon(market: MarketConfig): boolean {
  const expiryDate = new Date(market.expiry);
  const now = new Date();
  const diffDays = (expiryDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24);
  return diffDays <= 7 && diffDays > 0;
}
