export type Product = {
  slug: string;
  name: string;
  tagline: string;
  description: string;
  price: number;
  emoji: string;
  accent: string;
  badge: string;
};

export const products: readonly Product[] = [
  {
    slug: "this-is-fine",
    name: "This Is Fine",
    tagline: "For laptops surviving production deploys.",
    description: "A weatherproof reminder that the incident channel is totally calm.",
    price: 499,
    emoji: "🔥",
    accent: "#ff6b35",
    badge: "Bestseller",
  },
  {
    slug: "stonks-only",
    name: "Stonks Only",
    tagline: "Quarterly results, but make them vertical.",
    description: "Holographic optimism for notebooks, water bottles, and dashboards.",
    price: 599,
    emoji: "📈",
    accent: "#9cff57",
    badge: "Holographic",
  },
  {
    slug: "ship-it",
    name: "Ship It",
    tagline: "Green checks are a personality trait.",
    description: "A durable vinyl badge for people who merge before the coffee cools.",
    price: 449,
    emoji: "🚀",
    accent: "#7c5cff",
    badge: "Factory pick",
  },
  {
    slug: "works-on-my-machine",
    name: "Works On My Machine",
    tagline: "The classic distributed-systems diagnosis.",
    description: "Matte finish. Zero guarantees outside your laptop.",
    price: 499,
    emoji: "💻",
    accent: "#00d4ff",
    badge: "Classic",
  },
  {
    slug: "404-motivation",
    name: "404 Motivation",
    tagline: "Energy not found. Sticker found.",
    description: "A low-battery companion for the final meeting of the day.",
    price: 399,
    emoji: "🪫",
    accent: "#ff4d8d",
    badge: "Mood",
  },
  {
    slug: "rubber-duck-debugger",
    name: "Senior Duck Engineer",
    tagline: "Listens. Never interrupts. Finds the bug.",
    description: "Premium waterproof recognition for your most reliable teammate.",
    price: 549,
    emoji: "🦆",
    accent: "#ffd84d",
    badge: "Team favorite",
  },
] as const;

export function getProduct(slug: string): Product | undefined {
  return products.find((product) => product.slug === slug);
}

export function formatMoney(amount: number, currency = "USD"): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
  }).format(amount / 100);
}
