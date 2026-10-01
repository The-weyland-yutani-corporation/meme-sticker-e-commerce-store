import { describe, expect, it } from "vitest";
import { buildCheckoutDraft } from "@/domain/checkout";

describe("payment-free checkout", () => {
  it("calculates authoritative catalog totals", () => {
    const draft = buildCheckoutDraft([
      { slug: "this-is-fine", quantity: 2 },
      { slug: "ship-it", quantity: 1 },
    ]);

    expect(draft).toBeDefined();
    expect(draft?.amountTotal).toBe(1447);
    expect(draft?.lines).toHaveLength(2);
  });

  it("rejects products that are not in the server catalog", () => {
    expect(
      buildCheckoutDraft([{ slug: "client-invented-product", quantity: 1 }]),
    ).toBeUndefined();
  });
});
