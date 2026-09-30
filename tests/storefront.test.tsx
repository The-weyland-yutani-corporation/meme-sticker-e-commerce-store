// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import { Storefront } from "@/components/storefront";
import type { Product } from "@/domain/catalog";

const products: readonly Product[] = [
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
];

function getCartPanel() {
  return screen.getByLabelText("Shopping cart");
}

describe("Storefront", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
    vi.stubGlobal("location", { ...window.location, assign: vi.fn() });
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("opens the cart panel with the correct item and quantity when Add is clicked", () => {
    render(<Storefront products={products} />);

    const card = screen.getByText("This Is Fine").closest("article")!;
    fireEvent.click(within(card).getByRole("button", { name: /add/i }));

    const cartPanel = getCartPanel();
    expect(cartPanel).toBeInTheDocument();
    expect(within(cartPanel).getByText("This Is Fine")).toBeInTheDocument();
    expect(within(cartPanel).getByText("1")).toBeInTheDocument();
  });

  it("updates quantity and subtotal with +/- controls, and removes the item at 0", () => {
    render(<Storefront products={products} />);

    const card = screen.getByText("This Is Fine").closest("article")!;
    fireEvent.click(within(card).getByRole("button", { name: /add/i }));

    const cartPanel = getCartPanel();
    const increment = within(cartPanel).getByRole("button", {
      name: /add one this is fine/i,
    });
    const decrement = within(cartPanel).getByRole("button", {
      name: /remove one this is fine/i,
    });

    fireEvent.click(increment);
    expect(within(cartPanel).getByText("2")).toBeInTheDocument();
    expect(within(cartPanel).getByText("$9.98")).toBeInTheDocument();

    fireEvent.click(decrement);
    fireEvent.click(decrement);
    expect(
      within(cartPanel).getByText("The cart is suspiciously reasonable."),
    ).toBeInTheDocument();
  });

  it("shows an alert with the checkout error when the response is not OK", async () => {
    vi.mocked(fetch).mockResolvedValueOnce({
      ok: false,
      json: async () => ({ error: "Card declined." }),
    } as Response);

    render(<Storefront products={products} />);

    const card = screen.getByText("This Is Fine").closest("article")!;
    fireEvent.click(within(card).getByRole("button", { name: /add/i }));

    const cartPanel = getCartPanel();
    fireEvent.click(
      within(cartPanel).getByRole("button", { name: /secure checkout/i }),
    );

    const alert = await within(cartPanel).findByRole("alert");
    expect(alert).toHaveTextContent("Card declined.");
  });

  it("shows an alert with a fallback message when the response is OK but has no url", async () => {
    vi.mocked(fetch).mockResolvedValueOnce({
      ok: true,
      json: async () => ({}),
    } as Response);

    render(<Storefront products={products} />);

    const card = screen.getByText("This Is Fine").closest("article")!;
    fireEvent.click(within(card).getByRole("button", { name: /add/i }));

    const cartPanel = getCartPanel();
    fireEvent.click(
      within(cartPanel).getByRole("button", { name: /secure checkout/i }),
    );

    const alert = await within(cartPanel).findByRole("alert");
    expect(alert).toHaveTextContent("Checkout could not be started.");
  });
});
