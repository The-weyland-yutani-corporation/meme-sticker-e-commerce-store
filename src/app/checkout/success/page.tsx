import Link from "next/link";

export default function CheckoutSuccessPage() {
  return (
    <main className="success-shell">
      <div className="success-card">
        <span className="success-icon" aria-hidden="true">
          ✓
        </span>
        <p className="eyebrow">Payment confirmed</p>
        <h1>Your stickers are entering the meme supply chain.</h1>
        <p>
          A receipt is on its way. Fulfillment is mocked in this release, so no
          physical shipment will be created yet.
        </p>
        <Link className="button button-primary" href="/">
          Return to the sticker floor
        </Link>
      </div>
    </main>
  );
}
