import Link from "next/link";

export default function CheckoutSuccessPage() {
  return (
    <main className="success-shell">
      <div className="success-card">
        <span className="success-icon" aria-hidden="true">
          ✓
        </span>
        <p className="eyebrow">Test order confirmed</p>
        <h1>Your sticker order entered the meme supply chain.</h1>
        <p>
          No payment was collected. Fulfillment is mocked in this release, so
          no physical shipment will be created.
        </p>
        <Link className="button button-primary" href="/">
          Return to the sticker floor
        </Link>
      </div>
    </main>
  );
}
