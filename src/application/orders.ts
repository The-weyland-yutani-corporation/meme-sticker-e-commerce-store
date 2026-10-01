import { CheckoutMode, OrderStatus } from "@prisma/client";
import {
  buildCheckoutDraft,
  type CheckoutItemInput,
} from "@/domain/checkout";
import { getPrisma } from "@/infrastructure/db";

export async function createPaymentFreeOrder(
  items: readonly CheckoutItemInput[],
  options: { synthetic?: boolean } = {},
) {
  const draft = buildCheckoutDraft(items);
  if (!draft) {
    return undefined;
  }

  const prisma = getPrisma();
  return prisma.order.create({
    data: {
      amountTotal: draft.amountTotal,
      checkoutMode: CheckoutMode.PAYMENT_FREE,
      status: OrderStatus.FULFILLMENT_PENDING,
      synthetic: options.synthetic ?? false,
      items: {
        create: draft.lines.map(({ product, quantity }) => ({
          productSlug: product.slug,
          productName: product.name,
          unitAmount: product.price,
          quantity,
        })),
      },
    },
    include: { items: true },
  });
}

export async function verifyAndDeleteSyntheticOrder(orderId: string) {
  const prisma = getPrisma();
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: { items: true },
  });

  if (
    !order?.synthetic ||
    order.checkoutMode !== CheckoutMode.PAYMENT_FREE ||
    order.items.length === 0
  ) {
    throw new Error("Synthetic order verification failed");
  }

  await prisma.order.delete({ where: { id: orderId } });
  const deletedOrder = await prisma.order.findUnique({ where: { id: orderId } });
  if (deletedOrder) {
    throw new Error("Synthetic order cleanup failed");
  }

  return order;
}
