import { NextResponse } from "next/server";
import { z } from "zod";
import { getProduct } from "@/domain/catalog";
import { getPrisma } from "@/infrastructure/db";
import { getStripe } from "@/infrastructure/stripe";

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
  const parsed = checkoutSchema.safeParse(await request.json());

  if (!parsed.success) {
    return NextResponse.json(
      { error: "Your cart contains invalid items." },
      { status: 400 },
    );
  }

  const cartItems = parsed.data.items.flatMap((item) => {
    const product = getProduct(item.slug);

    if (!product) {
      return [];
    }

    return [{ product, quantity: item.quantity }];
  });

  if (cartItems.length !== parsed.data.items.length) {
    return NextResponse.json(
      { error: "Your cart contains a product that is no longer available." },
      { status: 400 },
    );
  }

  const appUrl = process.env.APP_URL;
  if (!appUrl) {
    return NextResponse.json(
      { error: "Checkout is not configured." },
      { status: 503 },
    );
  }

  try {
    const prisma = getPrisma();
    const stripe = getStripe();
    const amountTotal = cartItems.reduce(
      (total, item) => total + item.product.price * item.quantity,
      0,
    );

    const order = await prisma.order.create({
      data: {
        amountTotal,
        items: {
          create: cartItems.map(({ product, quantity }) => ({
            productSlug: product.slug,
            productName: product.name,
            unitAmount: product.price,
            quantity,
          })),
        },
      },
    });

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      success_url: `${appUrl}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${appUrl}/?checkout=canceled`,
      allow_promotion_codes: true,
      billing_address_collection: "auto",
      customer_creation: "always",
      line_items: cartItems.map(({ product, quantity }) => ({
        quantity,
        price_data: {
          currency: "usd",
          unit_amount: product.price,
          product_data: {
            name: product.name,
            description: product.tagline,
            metadata: { slug: product.slug },
          },
        },
      })),
      metadata: { orderId: order.id },
    });

    if (!session.url) {
      throw new Error("Stripe did not return a checkout URL");
    }

    await prisma.order.update({
      where: { id: order.id },
      data: { stripeCheckoutSessionId: session.id },
    });

    return NextResponse.json({ url: session.url });
  } catch (error) {
    console.error("checkout.create_failed", error);
    return NextResponse.json(
      { error: "Checkout is temporarily unavailable." },
      { status: 503 },
    );
  }
}
