export type FulfillmentOrder = {
  orderId: string;
  recipientEmail: string;
  items: Array<{
    productSlug: string;
    quantity: number;
  }>;
};

export type FulfillmentReceipt = {
  provider: string;
  reference: string;
  acceptedAt: string;
};

export interface FulfillmentProvider {
  submit(order: FulfillmentOrder): Promise<FulfillmentReceipt>;
}
