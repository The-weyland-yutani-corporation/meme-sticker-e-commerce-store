// @vitest-environment jsdom
import "@testing-library/jest-dom/vitest";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Storefront } from "@/components/storefront";
import type { Product } from "@/domain/catalog";

const fixtureProducts: readonly Product[] = [
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

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("Storefront", () => {
  it("opens the cart panel and shows the correct item and quantity when Add is clicked", () => {
    render(<Storefront products={fixtureProducts} />);

    const card = screen.getByText("This Is Fine").closest("article")!;
    fireEvent.click(within(card).getByRole("button", { name: /add/i }));

    const cartPanel = screen.getByLabelText("Shopping cart");
    expect(within(cartPanel).getByText("This Is Fine")).toBeInTheDocument();
    expect(within(cartPanel).getByText("1")).toBeInTheDocument();
  });

  it("updates quantity and subtotal with +/- controls, removing the item at 0", () => {
    render(<Storefront products={fixtureProducts} />);

    const card = screen.getByText("Stonks Only").closest("article")!;
    fireEvent.click(within(card).getByRole("button", { name: /add/i }));

    const cartPanel = screen.getByLabelText("Shopping cart");
    const increment = within(cartPanel).getByRole("button", {
      name: "Add one Stonks Only",
    });
    const decrement = within(cartPanel).getByRole("button", {
      name: "Remove one Stonks Only",
    });

    fireEvent.click(increment);
    expect(within(cartPanel).getByText("2")).toBeInTheDocument();
    expect(within(cartPanel).getByText("$11.98")).toBeInTheDocument();

    fireEvent.click(decrement);
    fireEvent.click(decrement);
    expect(
      within(cartPanel).queryByText("Stonks Only"),
    ).not.toBeInTheDocument();
    expect(
      screen.getByText("The cart is suspiciously reasonable."),
    ).toBeInTheDocument();
  });

  describe("checkout errors", () => {
    beforeEach(() => {
      vi.stubGlobal("fetch", vi.fn());
    });

    it("shows an alert when the checkout response is not OK", async () => {
      vi.mocked(fetch).mockResolvedValue(
        new Response(JSON.stringify({ error: "Checkout is closed." }), {
          status: 500,
        }),
      );

      render(<Storefront products={fixtureProducts} />);
      const card = screen.getByText("This Is Fine").closest("article")!;
      fireEvent.click(within(card).getByRole("button", { name: /add/i }));

      const cartPanel = screen.getByLabelText("Shopping cart");
      fireEvent.click(
        within(cartPanel).getByRole("button", { name: /secure checkout/i }),
      );

      const alert = await screen.findByRole("alert");
      expect(alert).toHaveTextContent("Checkout is closed.");
    });

    it("shows an alert when the checkout response is missing a url", async () => {
      vi.mocked(fetch).mockResolvedValue(
        new Response(JSON.stringify({}), { status: 200 }),
      );

      render(<Storefront products={fixtureProducts} />);
      const card = screen.getByText("This Is Fine").closest("article")!;
      fireEvent.click(within(card).getByRole("button", { name: /add/i }));

      const cartPanel = screen.getByLabelText("Shopping cart");
      fireEvent.click(
        within(cartPanel).getByRole("button", { name: /secure checkout/i }),
      );

      const alert = await screen.findByRole("alert");
      expect(alert).toHaveTextContent("Checkout could not be started.");
    });
  });
});
