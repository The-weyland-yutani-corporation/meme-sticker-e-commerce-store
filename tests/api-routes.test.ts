import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const orderMocks = vi.hoisted(() => ({
  createPaymentFreeOrder: vi.fn(),
  verifyAndDeleteSyntheticOrder: vi.fn(),
}));

const databaseMocks = vi.hoisted(() => ({
  queryRaw: vi.fn(),
}));

vi.mock("@/application/orders", () => orderMocks);
vi.mock("@/infrastructure/db", () => ({
  getPrisma: () => ({
    $queryRaw: databaseMocks.queryRaw,
  }),
}));

import { POST as checkout } from "@/app/api/checkout/route";
import { GET as health } from "@/app/api/health/route";
import { POST as syntheticOrder } from "@/app/api/internal/synthetic-order/route";

function jsonRequest(
  url: string,
  body: unknown,
  headers?: Record<string, string>,
) {
  return new Request(url, {
    body: JSON.stringify(body),
    headers: {
      "content-type": "application/json",
      ...headers,
    },
    method: "POST",
  });
}

beforeEach(() => {
  orderMocks.createPaymentFreeOrder.mockReset();
  orderMocks.verifyAndDeleteSyntheticOrder.mockReset();
  databaseMocks.queryRaw.mockReset();
  vi.spyOn(console, "error").mockImplementation(() => undefined);
  vi.spyOn(console, "info").mockImplementation(() => undefined);
});

afterEach(() => {
  delete process.env.RELEASE_SHA;
  delete process.env.SYNTHETIC_PROBE_TOKEN;
  vi.restoreAllMocks();
});

describe("checkout route", () => {
  it("rejects malformed JSON as an invalid cart", async () => {
    const response = await checkout(
      new Request("http://localhost/api/checkout", {
        body: "{",
        headers: { "content-type": "application/json" },
        method: "POST",
      }),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Your cart contains invalid items.",
    });
  });

  it("creates a payment-free order and returns its confirmation URL", async () => {
    orderMocks.createPaymentFreeOrder.mockResolvedValue({
      confirmationToken: "confirm-123",
    });

    const response = await checkout(
      jsonRequest("http://localhost/api/checkout", {
        items: [{ quantity: 2, slug: "this-is-fine" }],
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      confirmationUrl: "/checkout/success?order_id=confirm-123",
      orderId: "confirm-123",
    });
    expect(orderMocks.createPaymentFreeOrder).toHaveBeenCalledWith([
      { quantity: 2, slug: "this-is-fine" },
    ]);
  });

  it("returns service unavailable when order persistence fails", async () => {
    orderMocks.createPaymentFreeOrder.mockRejectedValue(new Error("database down"));

    const response = await checkout(
      jsonRequest("http://localhost/api/checkout", {
        items: [{ quantity: 1, slug: "this-is-fine" }],
      }),
    );

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: "Checkout is temporarily unavailable.",
    });
  });
});

describe("synthetic order route", () => {
  beforeEach(() => {
    process.env.SYNTHETIC_PROBE_TOKEN = "probe-secret";
  });

  it("rejects requests without the configured bearer token", async () => {
    const response = await syntheticOrder(
      jsonRequest("http://localhost/api/internal/synthetic-order", {}),
    );

    expect(response.status).toBe(401);
    expect(orderMocks.createPaymentFreeOrder).not.toHaveBeenCalled();
  });

  it("creates, verifies, and deletes a tagged synthetic order", async () => {
    orderMocks.createPaymentFreeOrder.mockResolvedValue({ id: "order-1" });
    orderMocks.verifyAndDeleteSyntheticOrder.mockResolvedValue({
      amountTotal: 499,
      id: "order-1",
    });

    const response = await syntheticOrder(
      jsonRequest(
        "http://localhost/api/internal/synthetic-order",
        {},
        { authorization: "Bearer probe-secret" },
      ),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      amountTotal: 499,
      deleted: true,
      status: "ok",
    });
    expect(orderMocks.createPaymentFreeOrder).toHaveBeenCalledWith(
      [{ quantity: 1, slug: "this-is-fine" }],
      { synthetic: true },
    );
    expect(orderMocks.verifyAndDeleteSyntheticOrder).toHaveBeenCalledWith("order-1");
  });

  it("fails closed when verification or cleanup fails", async () => {
    orderMocks.createPaymentFreeOrder.mockResolvedValue({ id: "order-1" });
    orderMocks.verifyAndDeleteSyntheticOrder.mockRejectedValue(
      new Error("cleanup failed"),
    );

    const response = await syntheticOrder(
      jsonRequest(
        "http://localhost/api/internal/synthetic-order",
        {},
        { authorization: "Bearer probe-secret" },
      ),
    );

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: "Synthetic order verification failed.",
    });
  });
});

describe("health route", () => {
  it("reports the exact release after a successful database query", async () => {
    process.env.RELEASE_SHA = "abc123";
    databaseMocks.queryRaw.mockResolvedValue([{ "?column?": 1 }]);

    const response = await health();
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toMatchObject({
      service: "meme-sticker-store",
      status: "ok",
      version: "abc123",
    });
  });

  it("returns 503 when the database is unavailable", async () => {
    databaseMocks.queryRaw.mockRejectedValue(new Error("database down"));

    const response = await health();
    const body = await response.json();

    expect(response.status).toBe(503);
    expect(body).toMatchObject({
      service: "meme-sticker-store",
      status: "unhealthy",
    });
  });
});
