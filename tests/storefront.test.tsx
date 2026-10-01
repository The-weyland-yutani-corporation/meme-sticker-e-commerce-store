// @vitest-environment jsdom
import "@testing-library/jest-dom/vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { Storefront } from "@/components/storefront";
import { formatMoney, type Product } from "@/domain/catalog";

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
    slug: "ship-it",
    name: "Ship It",
    tagline: "Green checks are a personality trait.",
    description: "A durable vinyl badge for people who merge before the coffee cools.",
    price: 449,
    emoji: "🚀",
    accent: "#7c5cff",
    badge: "Factory pick",
  },
];

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

function clickAddForProduct(productName: string) {
  const productCard = screen.getByRole("heading", { name: productName }).closest("article");
  expect(productCard).not.toBeNull();
  const addButton = within(productCard as HTMLElement).getByRole("button", {
    name: /add/i,
  });
  fireEvent.click(addButton);
}

describe("Storefront cart interactions", () => {
  it("opens the cart panel and shows the added item with quantity 1 when Add is clicked", () => {
    render(<Storefront products={fixtureProducts} />);

    clickAddForProduct("This Is Fine");

    const cartPanel = screen.getByRole("complementary", { name: "Shopping cart" });
    expect(cartPanel).toBeInTheDocument();

    const cartItem = within(cartPanel).getByText("This Is Fine").closest(".cart-item") as HTMLElement;
    expect(cartItem).not.toBeNull();
    expect(within(cartItem).getByText("1")).toBeInTheDocument();
    // Unit price and subtotal both render as formatMoney(499) at quantity 1, so
    // target the unit-price paragraph directly instead of an ambiguous text query.
    expect(cartItem.querySelector("p")).toHaveTextContent(
      formatMoney(fixtureProducts[0].price),
    );
    expect(cartItem.querySelector("strong")).toHaveTextContent(
      formatMoney(fixtureProducts[0].price),
    );
  });

  it("updates quantity and subtotal with +/- controls, and removes the item at 0", () => {
    render(<Storefront products={fixtureProducts} />);

    clickAddForProduct("This Is Fine");

    const cartPanel = screen.getByRole("complementary", { name: "Shopping cart" });

    const incrementButton = within(cartPanel).getByRole("button", {
      name: "Add one This Is Fine",
    });
    fireEvent.click(incrementButton);

    const cartItem = within(cartPanel).getByText("This Is Fine").closest(".cart-item") as HTMLElement;
    expect(within(cartItem).getByText("2")).toBeInTheDocument();
    expect(
      within(cartItem).getByText(formatMoney(fixtureProducts[0].price * 2)),
    ).toBeInTheDocument();

    const decrementButton = within(cartPanel).getByRole("button", {
      name: "Remove one This Is Fine",
    });
    fireEvent.click(decrementButton);
    fireEvent.click(decrementButton);

    expect(within(cartPanel).queryByText("This Is Fine")).not.toBeInTheDocument();
    expect(
      within(cartPanel).getByText("The cart is suspiciously reasonable."),
    ).toBeInTheDocument();
  });
});

describe("Storefront checkout error handling", () => {
  beforeEach(() => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response(JSON.stringify({ error: "Order service unavailable" }), {
          status: 500,
        }),
      ),
    );
  });

  it("shows an alert when checkout fetch resolves with a non-OK response", async () => {
    render(<Storefront products={fixtureProducts} />);

    clickAddForProduct("This Is Fine");

    const cartPanel = screen.getByRole("complementary", { name: "Shopping cart" });
    fireEvent.click(within(cartPanel).getByRole("button", { name: /create test order/i }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Order service unavailable");
  });

  it("shows an alert when checkout fetch resolves OK but is missing a confirmation URL", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify({}), { status: 200 })),
    );

    render(<Storefront products={fixtureProducts} />);

    clickAddForProduct("This Is Fine");

    const cartPanel = screen.getByRole("complementary", { name: "Shopping cart" });
    fireEvent.click(within(cartPanel).getByRole("button", { name: /create test order/i }));

    await waitFor(() => {
      expect(screen.getByRole("alert")).toHaveTextContent(
        "Checkout could not be started.",
      );
    });
  });
});
