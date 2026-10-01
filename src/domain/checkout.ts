import { getProduct, type Product } from "@/domain/catalog";

export type CheckoutItemInput = {
  slug: string;
  quantity: number;
};

export type CheckoutLine = {
  product: Product;
  quantity: number;
};

export type CheckoutDraft = {
  amountTotal: number;
  lines: CheckoutLine[];
};

export function buildCheckoutDraft(
  items: readonly CheckoutItemInput[],
): CheckoutDraft | undefined {
  const lines = items.flatMap((item) => {
    const product = getProduct(item.slug);
    return product ? [{ product, quantity: item.quantity }] : [];
  });

  if (lines.length !== items.length) {
    return undefined;
  }

  return {
    lines,
    amountTotal: lines.reduce(
      (total, item) => total + item.product.price * item.quantity,
      0,
    ),
  };
}
