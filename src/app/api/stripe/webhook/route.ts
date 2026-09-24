import { OrderStatus, Prisma } from "@prisma/client";
import type Stripe from "stripe";
import { getPrisma } from "@/infrastructure/db";
import { getStripe } from "@/infrastructure/stripe";

export async function POST(request: Request) {
  const signature = request.headers.get("stripe-signature");
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;

  if (!signature || !webhookSecret) {
    return new Response("Webhook is not configured", { status: 503 });
  }

  let event: Stripe.Event;

  try {
    event = getStripe().webhooks.constructEvent(
      await request.text(),
      signature,
      webhookSecret,
    );
  } catch (error) {
    console.error("stripe.invalid_signature", error);
    return new Response("Invalid signature", { status: 400 });
  }

  try {
    await processEvent(event);
    return new Response("ok");
  } catch (error) {
    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2002"
    ) {
      return new Response("already processed");
    }

    console.error("stripe.event_failed", { eventId: event.id, error });
    return new Response("Webhook processing failed", { status: 500 });
  }
}

async function processEvent(event: Stripe.Event) {
  const prisma = getPrisma();
  await prisma.$transaction(async (transaction) => {
    await transaction.stripeEvent.create({
      data: { id: event.id, type: event.type },
    });

    if (event.type === "checkout.session.completed") {
      const session = event.data.object;
      const orderId = session.metadata?.orderId;

      if (!orderId) {
        throw new Error(`Stripe session ${session.id} is missing orderId`);
      }

      await transaction.order.update({
        where: { id: orderId },
        data: {
          email: session.customer_details?.email,
          status: OrderStatus.PAID,
          stripePaymentIntentId:
            typeof session.payment_intent === "string"
              ? session.payment_intent
              : session.payment_intent?.id,
        },
      });
    }

    if (event.type === "checkout.session.expired") {
      const orderId = event.data.object.metadata?.orderId;
      if (orderId) {
        await transaction.order.updateMany({
          where: { id: orderId, status: OrderStatus.PENDING },
          data: { status: OrderStatus.CANCELED },
        });
      }
    }

    if (event.type === "charge.refunded") {
      const paymentIntent = event.data.object.payment_intent;
      if (typeof paymentIntent === "string") {
        await transaction.order.updateMany({
          where: { stripePaymentIntentId: paymentIntent },
          data: { status: OrderStatus.REFUNDED },
        });
      }
    }
  });
}
