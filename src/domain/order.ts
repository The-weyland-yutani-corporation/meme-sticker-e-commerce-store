export const orderStatuses = [
  "PENDING",
  "PAID",
  "FULFILLMENT_PENDING",
  "FULFILLED",
  "CANCELED",
  "REFUNDED",
] as const;

export type OrderStatus = (typeof orderStatuses)[number];

const transitions: Record<OrderStatus, readonly OrderStatus[]> = {
  PENDING: ["PAID", "CANCELED"],
  PAID: ["FULFILLMENT_PENDING", "REFUNDED"],
  FULFILLMENT_PENDING: ["FULFILLED", "REFUNDED"],
  FULFILLED: ["REFUNDED"],
  CANCELED: [],
  REFUNDED: [],
};

export function canTransitionOrder(
  current: OrderStatus,
  next: OrderStatus,
): boolean {
  return transitions[current].includes(next);
}
