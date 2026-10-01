import { NextResponse } from "next/server";
import { z } from "zod";
import { createPaymentFreeOrder } from "@/application/orders";

const checkoutSchema = z.object({
  items: z
    .array(
      z.object({
        slug: z.string().min(1),
        quantity: z.number().int().min(1).max(10),
      }),
    )
    .min(1)
    .max(20),
});

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { error: "Your cart contains invalid items." },
      { status: 400 },
    );
  }

  const parsed = checkoutSchema.safeParse(body);

  if (!parsed.success) {
    return NextResponse.json(
      { error: "Your cart contains invalid items." },
      { status: 400 },
    );
  }

  try {
    const order = await createPaymentFreeOrder(parsed.data.items);
    if (!order) {
      return NextResponse.json(
        { error: "Your cart contains a product that is no longer available." },
        { status: 400 },
      );
    }

    return NextResponse.json({
      orderId: order.confirmationToken,
      confirmationUrl: `/checkout/success?order_id=${encodeURIComponent(order.confirmationToken)}`,
    });
  } catch (error) {
    console.error("checkout.create_failed", error);
    return NextResponse.json(
      { error: "Checkout is temporarily unavailable." },
      { status: 503 },
    );
  }
}
