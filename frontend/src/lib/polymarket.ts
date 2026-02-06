// Polymarket API integration
// Fetches real market data from Polymarket's gamma API

export interface PolymarketMarket {
  id: string;
  question: string;
  slug: string;
  outcomePrices: string; // JSON string like '["0.55", "0.45"]'
  volume: string;
  liquidity: string;
  endDate: string;
  image: string;
  icon: string;
  active: boolean;
  closed: boolean;
}

export interface ParsedMarket {
  id: number;
  polymarketId: string;
  name: string;
  question: string;
  yesPrice: number;
  noPrice: number;
  volume: number;
  icon: string;
  image: string;
  endDate: string | null;
  category: string;
  slug: string;
}

const GAMMA_API = 'https://gamma-api.polymarket.com';

// Categories based on keywords
function categorizeMarket(question: string): string {
  const q = question.toLowerCase();
  if (q.includes('bitcoin') || q.includes('btc') || q.includes('eth') || q.includes('crypto') || q.includes('solana')) {
    return 'Crypto';
  }
  if (q.includes('trump') || q.includes('biden') || q.includes('election') || q.includes('congress') || q.includes('senate')) {
    return 'Politics';
  }
  if (q.includes('fed') || q.includes('rate') || q.includes('inflation') || q.includes('recession') || q.includes('gdp')) {
    return 'Finance';
  }
  if (q.includes('nfl') || q.includes('nba') || q.includes('ufc') || q.includes('super bowl') || q.includes('championship')) {
    return 'Sports';
  }
  return 'General';
}

export async function fetchPolymarketMarkets(limit: number = 20): Promise<ParsedMarket[]> {
  try {
    const response = await fetch(
      `${GAMMA_API}/markets?active=true&closed=false&limit=${limit}&order=volume&ascending=false`,
      { next: { revalidate: 60 } } // Cache for 60 seconds
    );
    
    if (!response.ok) {
      throw new Error(`Polymarket API error: ${response.status}`);
    }
    
    const markets: PolymarketMarket[] = await response.json();
    
    return markets.map((m, index) => {
      let yesPrice = 0.5;
      let noPrice = 0.5;
      
      try {
        const prices = JSON.parse(m.outcomePrices || '["0.5", "0.5"]');
        yesPrice = parseFloat(prices[0]) || 0.5;
        noPrice = parseFloat(prices[1]) || 0.5;
      } catch {
        // Keep defaults
      }
      
      return {
        id: index + 1, // Internal ID for our system
        polymarketId: m.id || m.slug,
        name: m.question.slice(0, 30) + (m.question.length > 30 ? '...' : ''),
        question: m.question,
        yesPrice,
        noPrice,
        volume: parseFloat(m.volume) || 0,
        icon: m.icon || '📊',
        image: m.image || '',
        endDate: m.endDate || null,
        category: categorizeMarket(m.question),
        slug: m.slug,
      };
    });
  } catch (error) {
    console.error('Failed to fetch Polymarket data:', error);
    return [];
  }
}

export async function fetchMarketBySlug(slug: string): Promise<ParsedMarket | null> {
  try {
    const response = await fetch(
      `${GAMMA_API}/markets?slug=${slug}`,
      { next: { revalidate: 30 } }
    );
    
    if (!response.ok) return null;
    
    const markets: PolymarketMarket[] = await response.json();
    if (markets.length === 0) return null;
    
    const m = markets[0];
    let yesPrice = 0.5;
    let noPrice = 0.5;
    
    try {
      const prices = JSON.parse(m.outcomePrices || '["0.5", "0.5"]');
      yesPrice = parseFloat(prices[0]) || 0.5;
      noPrice = parseFloat(prices[1]) || 0.5;
    } catch {
      // Keep defaults
    }
    
    return {
      id: 1,
      polymarketId: m.id || m.slug,
      name: m.question.slice(0, 30),
      question: m.question,
      yesPrice,
      noPrice,
      volume: parseFloat(m.volume) || 0,
      icon: m.icon || '📊',
      image: m.image || '',
      endDate: m.endDate || null,
      category: categorizeMarket(m.question),
      slug: m.slug,
    };
  } catch (error) {
    console.error('Failed to fetch market:', error);
    return null;
  }
}
