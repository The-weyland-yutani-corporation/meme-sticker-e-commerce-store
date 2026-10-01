// @vitest-environment jsdom
import "@testing-library/jest-dom/vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

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
];

afterEach(() => {
  cleanup();
});

describe("Storefront decorative emoji accessibility", () => {
  it("hides the hero sticker decorations from assistive technology", () => {
    const { container } = render(<Storefront products={fixtureProducts} />);

    const heroStickers = container.querySelectorAll(
      ".sticker-fire, .sticker-stonks, .sticker-duck",
    );

    expect(heroStickers).toHaveLength(3);
    heroStickers.forEach((sticker) => {
      expect(sticker).toHaveAttribute("aria-hidden", "true");
    });
  });

  it("hides the cart item emoji art from assistive technology", () => {
    const { container } = render(<Storefront products={fixtureProducts} />);

    fireEvent.click(screen.getByRole("button", { name: /add/i }));

    const cartItemArt = container.querySelector(".cart-item-art");

    expect(cartItemArt).not.toBeNull();
    expect(cartItemArt).toHaveAttribute("aria-hidden", "true");
  });
});
