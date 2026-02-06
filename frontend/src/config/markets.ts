// LEVER Protocol Markets Configuration
// Maps on-chain market IDs to Polymarket slugs and metadata

export interface MarketConfig {
  id: number;
  name: string;
  question: string;
  slug: string; // Polymarket slug
  category: 'Crypto' | 'Politics' | 'Finance' | 'Sports' | 'General';
  icon: string;
  active: boolean;
}

// On-chain markets with their Polymarket mappings
export const LEVER_MARKETS: MarketConfig[] = [
  {
    id: 1,
    name: 'MicroStrategy BTC',
    question: 'Will MicroStrategy sell any Bitcoin before 2027?',
    slug: 'will-microstrategy-sell-any-bitcoin-before-2027',
    category: 'Crypto',
    icon: '₿',
    active: true,
  },
  {
    id: 2,
    name: 'Trump Deportations',
    question: 'Will Trump deport 250,000-500,000 people?',
    slug: 'will-trump-deport-250000-500000-people',
    category: 'Politics',
    icon: '🇺🇸',
    active: true,
  },
  {
    id: 3,
    name: 'GTA 6 $100+',
    question: 'Will GTA 6 cost $100+?',
    slug: 'will-gta-6-cost-100',
    category: 'General',
    icon: '🎮',
    active: true,
  },
  // New markets (deployed via AddMarketsV2)
  {
    id: 4,
    name: 'US Revenue <$100b',
    question: 'Will the U.S. collect less than $100b in tariff revenue in 2025?',
    slug: 'will-the-us-collect-less-than-100b-in-revenue-in-2025',
    category: 'Finance',
    icon: '💰',
    active: false, // Set to true after deployment
  },
  {
    id: 5,
    name: 'Tariffs >$250b',
    question: 'Will tariffs generate >$250b in 2025?',
    slug: 'will-tariffs-generate-250b-in-2025',
    category: 'Finance',
    icon: '📊',
    active: false,
  },
  {
    id: 6,
    name: 'US Revenue $500b-$1t',
    question: 'Will the U.S. collect between $500b and $1t in tariff revenue in 2025?',
    slug: 'will-the-us-collect-between-500b-and-1t-in-revenue-in-2025',
    category: 'Finance',
    icon: '💵',
    active: false,
  },
  {
    id: 7,
    name: 'US Revenue $100b-$200b',
    question: 'Will the U.S. collect between $100b and $200b in tariff revenue in 2025?',
    slug: 'will-the-us-collect-between-100b-and-200b-in-revenue-in-2025',
    category: 'Finance',
    icon: '📈',
    active: false,
  },
  {
    id: 8,
    name: 'Trump Deport <250k',
    question: 'Will Trump deport less than 250,000 people?',
    slug: 'will-trump-deport-less-than-250000',
    category: 'Politics',
    icon: '🏛️',
    active: false,
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
