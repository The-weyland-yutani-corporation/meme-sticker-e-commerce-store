import { describe, expect, it } from "vitest";
import { formatMoney, getProduct, products } from "@/domain/catalog";

describe("catalog", () => {
  it("contains unique product slugs", () => {
    expect(new Set(products.map((product) => product.slug)).size).toBe(
      products.length,
    );
  });

  it("looks up products by slug", () => {
    expect(getProduct("ship-it")?.name).toBe("Ship It");
    expect(getProduct("does-not-exist")).toBeUndefined();
  });

  it("formats integer minor units as money", () => {
    expect(formatMoney(499)).toBe("$4.99");
  });
});
