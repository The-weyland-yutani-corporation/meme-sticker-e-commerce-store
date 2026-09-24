import type {
  FulfillmentOrder,
  FulfillmentProvider,
  FulfillmentReceipt,
} from "./types";

export class MockFulfillmentProvider implements FulfillmentProvider {
  async submit(order: FulfillmentOrder): Promise<FulfillmentReceipt> {
    return {
      provider: "mock",
      reference: `mock-${order.orderId}`,
      acceptedAt: new Date().toISOString(),
    };
  }
}
