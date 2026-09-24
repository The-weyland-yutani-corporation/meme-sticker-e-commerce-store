import { describe, expect, it } from "vitest";
import { canTransitionOrder } from "@/domain/order";

describe("order transitions", () => {
  it("allows the happy path", () => {
    expect(canTransitionOrder("PENDING", "PAID")).toBe(true);
    expect(canTransitionOrder("PAID", "FULFILLMENT_PENDING")).toBe(true);
    expect(canTransitionOrder("FULFILLMENT_PENDING", "FULFILLED")).toBe(true);
  });

  it("blocks invalid terminal transitions", () => {
    expect(canTransitionOrder("CANCELED", "PAID")).toBe(false);
    expect(canTransitionOrder("REFUNDED", "FULFILLED")).toBe(false);
  });
});
