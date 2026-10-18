import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "@prisma/client";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { POST as checkout } from "@/app/api/checkout/route";
import { GET as health } from "@/app/api/health/route";
import { createPaymentFreeOrder, verifyAndDeleteSyntheticOrder } from "@/application/orders";
import { getPrisma } from "@/infrastructure/db";

const databaseUrl = process.env.TEST_DATABASE_URL;

describe.skipIf(!databaseUrl)("real PostgreSQL acceptance", () => {
  let database: PrismaClient;
  const orderIds: string[] = [];

  beforeAll(() => {
    const url = new URL(databaseUrl!);
    if (!["postgres:", "postgresql:"].includes(url.protocol) || !url.pathname.endsWith("_test")) {
      throw new Error("TEST_DATABASE_URL must name a disposable database ending in _test");
    }
    vi.stubEnv("DATABASE_URL", databaseUrl!);
    database = new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl! }) });
  });

  afterAll(async () => {
    try {
      if (database) {
        await database.order.deleteMany({ where: { id: { in: orderIds } } });
        expect(await database.orderItem.count({ where: { orderId: { in: orderIds } } })).toBe(0);
      }
    } finally {
      if (database) {
        await database.$disconnect();
        await getPrisma().$disconnect();
      }
      vi.unstubAllEnvs();
    }
  });

  it("persists the $9.98 reference cart with server prices and returns confirmation", async () => {
    const response = await checkout(new Request("http://localhost/api/checkout", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        items: [
          { slug: "ship-it", quantity: 1, price: 1 },
          { slug: "rubber-duck-debugger", quantity: 1, price: 1 },
        ],
      }),
    }));
    expect(response.status).toBe(200);
    const result = await response.json();
    const order = await database.order.findUniqueOrThrow({
      where: { confirmationToken: result.orderId },
      include: { items: true },
    });
    orderIds.push(order.id);
    expect(result.confirmationUrl).toBe(`/checkout/success?order_id=${order.confirmationToken}`);
    expect(order).toMatchObject({
      amountTotal: 998,
      currency: "usd",
      checkoutMode: "PAYMENT_FREE",
      status: "FULFILLMENT_PENDING",
      email: null,
      stripeCheckoutSessionId: null,
      stripePaymentIntentId: null,
    });
    expect(order.items).toHaveLength(2);
    expect(order.items).toEqual(expect.arrayContaining([
      expect.objectContaining({ productSlug: "ship-it", unitAmount: 449, quantity: 1 }),
      expect.objectContaining({ productSlug: "rubber-duck-debugger", unitAmount: 549, quantity: 1 }),
    ]));
  });

  it("rejects an unknown product without persisting an order", async () => {
    const before = await database.order.count();
    const response = await checkout(new Request("http://localhost/api/checkout", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ items: [{ slug: "not-a-product", quantity: 1 }] }),
    }));
    expect(response.status).toBe(400);
    expect(await database.order.count()).toBe(before);
  });

  it("creates, verifies, and deletes a synthetic order and its items", async () => {
    const order = await createPaymentFreeOrder([{ slug: "ship-it", quantity: 1 }], { synthetic: true });
    expect(order).toBeDefined();
    orderIds.push(order!.id);
    await verifyAndDeleteSyntheticOrder(order!.id);
    expect(await database.order.findUnique({ where: { id: order!.id } })).toBeNull();
    expect(await database.orderItem.count({ where: { orderId: order!.id } })).toBe(0);
  });

  it("reports healthy only after connecting to PostgreSQL", async () => {
    const response = await health();
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ status: "ok", service: "meme-sticker-store" });
  });
});
