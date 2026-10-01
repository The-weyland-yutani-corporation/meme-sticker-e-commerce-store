CREATE TYPE "CheckoutMode" AS ENUM ('PAYMENT_FREE', 'STRIPE');

ALTER TABLE "Order"
ADD COLUMN "confirmationToken" TEXT,
ADD COLUMN "checkoutMode" "CheckoutMode" NOT NULL DEFAULT 'PAYMENT_FREE',
ADD COLUMN "synthetic" BOOLEAN NOT NULL DEFAULT false;

UPDATE "Order"
SET
  "confirmationToken" = "id",
  "checkoutMode" = CASE
    WHEN "stripeCheckoutSessionId" IS NOT NULL THEN 'STRIPE'::"CheckoutMode"
    ELSE 'PAYMENT_FREE'::"CheckoutMode"
  END;

ALTER TABLE "Order"
ALTER COLUMN "confirmationToken" SET NOT NULL,
ALTER COLUMN "confirmationToken" SET DEFAULT gen_random_uuid()::text,
ALTER COLUMN "status" SET DEFAULT 'FULFILLMENT_PENDING';

CREATE UNIQUE INDEX "Order_confirmationToken_key"
ON "Order"("confirmationToken");
