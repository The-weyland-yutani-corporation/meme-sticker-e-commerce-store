"use client";

import { useMemo, useState } from "react";
import {
  ArrowRight,
  Bot,
  Check,
  Minus,
  Plus,
  ShieldCheck,
  ShoppingBag,
  Sparkles,
  Truck,
  X,
  Zap,
} from "lucide-react";
import { formatMoney, type Product } from "@/domain/catalog";

type Cart = Record<string, number>;

export function Storefront({ products }: { products: readonly Product[] }) {
  const [cart, setCart] = useState<Cart>({});
  const [cartOpen, setCartOpen] = useState(false);
  const [checkoutError, setCheckoutError] = useState<string>();
  const [checkingOut, setCheckingOut] = useState(false);

  const cartItems = useMemo(
    () =>
      products
        .filter((product) => cart[product.slug])
        .map((product) => ({
          product,
          quantity: cart[product.slug],
        })),
    [cart, products],
  );

  const itemCount = cartItems.reduce((total, item) => total + item.quantity, 0);
  const subtotal = cartItems.reduce(
    (total, item) => total + item.product.price * item.quantity,
    0,
  );

  function updateQuantity(slug: string, quantity: number) {
    setCart((current) => {
      const next = { ...current };
      if (quantity <= 0) {
        delete next[slug];
      } else {
        next[slug] = Math.min(quantity, 10);
      }
      return next;
    });
  }

  function addToCart(product: Product) {
    updateQuantity(product.slug, (cart[product.slug] ?? 0) + 1);
    setCartOpen(true);
  }

  async function checkout() {
    setCheckoutError(undefined);
    setCheckingOut(true);

    try {
      const response = await fetch("/api/checkout", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          items: cartItems.map(({ product, quantity }) => ({
            slug: product.slug,
            quantity,
          })),
        }),
      });
      const result = (await response.json()) as {
        confirmationUrl?: string;
        error?: string;
      };

      if (!response.ok || !result.confirmationUrl) {
        throw new Error(result.error ?? "Checkout could not be started.");
      }

      window.location.assign(result.confirmationUrl);
    } catch (error) {
      setCheckoutError(
        error instanceof Error ? error.message : "Checkout could not be started.",
      );
      setCheckingOut(false);
    }
  }

  return (
    <div className="site-shell">
      <header className="site-header">
        <a className="brand" href="#top" aria-label="Meme Forge home">
          <span className="brand-mark" aria-hidden="true">
            MF
          </span>
          <span>
            MEME<span>FORGE</span>
          </span>
        </a>
        <nav aria-label="Primary navigation">
          <a href="#stickers">Stickers</a>
          <a href="#factory">The factory</a>
          <a href="#quality">Quality</a>
        </nav>
        <button
          className="cart-trigger"
          type="button"
          onClick={() => setCartOpen(true)}
          aria-label={`Open cart with ${itemCount} items`}
        >
          <ShoppingBag size={18} />
          Cart
          <span>{itemCount}</span>
        </button>
      </header>

      <main id="top">
        <section className="hero">
          <div className="hero-copy">
            <p className="eyebrow">
              <span />
              Autonomous meme production online
            </p>
            <h1>
              Stickers forged for the{" "}
              <span className="highlight">terminally online.</span>
            </h1>
            <p className="hero-intro">
              Premium vinyl memes built to survive water bottles, laptops, and
              your next production incident.
            </p>
            <div className="hero-actions">
              <a className="button button-primary" href="#stickers">
                Shop the drop <ArrowRight size={18} />
              </a>
              <a className="text-link" href="#factory">
                See how the factory runs
              </a>
            </div>
            <div className="proof-row" aria-label="Product guarantees">
              <span>
                <Check size={15} /> Weatherproof
              </span>
              <span>
                <Check size={15} /> Premium vinyl
              </span>
              <span>
                <Check size={15} /> Maximum lore
              </span>
            </div>
          </div>

          <div className="hero-visual" aria-label="Featured sticker wall">
            <div className="grid-lines" />
            <div className="sticker sticker-fire" aria-hidden="true">🔥</div>
            <div className="sticker sticker-stonks" aria-hidden="true">📈</div>
            <div className="sticker sticker-duck" aria-hidden="true">🦆</div>
            <div className="terminal-card">
              <div>
                <span />
                <span />
                <span />
              </div>
              <code>
                <b>$</b> factory status
                <br />
                <em>✓ memes compiled</em>
                <br />
                <em>✓ vibes verified</em>
                <br />
                <strong>→ shipping chaos</strong>
              </code>
            </div>
          </div>
        </section>

        <section className="ticker" aria-label="Store benefits">
          <span>SMALL-BATCH ENERGY</span>
          <i>✦</i>
          <span>BIG MEME OUTPUT</span>
          <i>✦</i>
          <span>BUILT BY BOTS</span>
          <i>✦</i>
          <span>APPROVED BY THE GROUP CHAT</span>
        </section>

        <section className="catalog-section" id="stickers">
          <div className="section-heading">
            <div>
              <p className="eyebrow">Fresh off the line</p>
              <h2>Pick your personality patch.</h2>
            </div>
            <p>
              Die-cut vinyl, loud colors, and jokes that require at least one
              browser tab of context.
            </p>
          </div>

          <div className="product-grid">
            {products.map((product, index) => (
              <article className="product-card" key={product.slug}>
                <div
                  className="product-art"
                  style={{ "--accent": product.accent } as React.CSSProperties}
                >
                  <span className="product-index">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <span className="product-badge">{product.badge}</span>
                  <span className="product-emoji" aria-hidden="true">
                    {product.emoji}
                  </span>
                  <span className="product-orbit" />
                </div>
                <div className="product-content">
                  <div>
                    <h3>{product.name}</h3>
                    <p>{product.tagline}</p>
                  </div>
                  <div className="product-buy">
                    <strong>{formatMoney(product.price)}</strong>
                    <button type="button" onClick={() => addToCart(product)}>
                      Add <Plus size={16} />
                    </button>
                  </div>
                </div>
              </article>
            ))}
          </div>
        </section>

        <section className="factory-section" id="factory">
          <div className="factory-copy">
            <p className="eyebrow">Inside Meme Forge</p>
            <h2>No meetings. Just a relentless sticker pipeline.</h2>
            <p>
              Our dark software factory turns ideas into tested storefront
              improvements, then watches every release after it ships. Robots
              write the code; hard gates keep the chaos contained.
            </p>
            <div className="factory-status">
              <span className="status-dot" />
              Factory status: all systems memeing
            </div>
          </div>
          <ol className="factory-steps">
            <li>
              <span>
                <Sparkles size={20} />
              </span>
              <div>
                <b>01 / Intent</b>
                <h3>A signal enters the queue.</h3>
                <p>Customer behavior becomes a bounded, testable work item.</p>
              </div>
            </li>
            <li>
              <span>
                <Bot size={20} />
              </span>
              <div>
                <b>02 / Build</b>
                <h3>Agents implement and challenge it.</h3>
                <p>Separate author, test, review, and security contexts.</p>
              </div>
            </li>
            <li>
              <span>
                <ShieldCheck size={20} />
              </span>
              <div>
                <b>03 / Verify</b>
                <h3>Deterministic gates decide.</h3>
                <p>Tests, policies, scans, and merge-queue validation.</p>
              </div>
            </li>
            <li>
              <span>
                <Zap size={20} />
              </span>
              <div>
                <b>04 / Ship</b>
                <h3>Canary, observe, promote.</h3>
                <p>Bad signals roll back automatically and open an incident.</p>
              </div>
            </li>
          </ol>
        </section>

        <section className="quality-section" id="quality">
          <p className="eyebrow">Sticker specifications</p>
          <div className="quality-grid">
            <article>
              <ShieldCheck />
              <h3>Weather resistant</h3>
              <p>Rain, coffee splashes, and normal laptop abuse.</p>
            </article>
            <article>
              <Sparkles />
              <h3>Crisp color</h3>
              <p>High-contrast art that refuses to become background noise.</p>
            </article>
            <article>
              <Truck />
              <h3>Fulfillment ready</h3>
              <p>The mock adapter is ready to swap for print-on-demand.</p>
            </article>
          </div>
        </section>
      </main>

      <footer>
        <a className="brand" href="#top">
          <span className="brand-mark">MF</span>
          MEME<span>FORGE</span>
        </a>
        <p>Internet culture, converted into adhesive assets.</p>
        <span>© {new Date().getFullYear()} Meme Forge</span>
      </footer>

      {cartOpen && (
        <div className="cart-layer" role="presentation">
          <button
            className="cart-backdrop"
            aria-label="Close cart"
            onClick={() => setCartOpen(false)}
          />
          <aside className="cart-panel" aria-label="Shopping cart">
            <div className="cart-header">
              <div>
                <p className="eyebrow">Your haul</p>
                <h2>Cart ({itemCount})</h2>
              </div>
              <button
                className="icon-button"
                type="button"
                onClick={() => setCartOpen(false)}
                aria-label="Close cart"
              >
                <X />
              </button>
            </div>

            {cartItems.length === 0 ? (
              <div className="empty-cart">
                <ShoppingBag />
                <h3>The cart is suspiciously reasonable.</h3>
                <p>Add a few memes and return to chaos.</p>
              </div>
            ) : (
              <div className="cart-items">
                {cartItems.map(({ product, quantity }) => (
                  <div className="cart-item" key={product.slug}>
                    <span
                      className="cart-item-art"
                      style={{ background: product.accent }}
                      aria-hidden="true"
                    >
                      {product.emoji}
                    </span>
                    <div>
                      <h3>{product.name}</h3>
                      <p>{formatMoney(product.price)}</p>
                      <div className="quantity-control">
                        <button
                          type="button"
                          aria-label={`Remove one ${product.name}`}
                          onClick={() =>
                            updateQuantity(product.slug, quantity - 1)
                          }
                        >
                          <Minus size={14} />
                        </button>
                        <span>{quantity}</span>
                        <button
                          type="button"
                          aria-label={`Add one ${product.name}`}
                          onClick={() =>
                            updateQuantity(product.slug, quantity + 1)
                          }
                        >
                          <Plus size={14} />
                        </button>
                      </div>
                    </div>
                    <strong>{formatMoney(product.price * quantity)}</strong>
                  </div>
                ))}
              </div>
            )}

            <div className="cart-footer">
              <div>
                <span>Subtotal</span>
                <strong>{formatMoney(subtotal)}</strong>
              </div>
              <p>No payment is collected. This creates a test order only.</p>
              {checkoutError && (
                <p className="checkout-error" role="alert">
                  {checkoutError}
                </p>
              )}
              <button
                className="button button-primary checkout-button"
                type="button"
                onClick={checkout}
                disabled={!cartItems.length || checkingOut}
              >
                {checkingOut ? "Creating order…" : "Create test order"}
                <ArrowRight size={18} />
              </button>
            </div>
          </aside>
        </div>
      )}
    </div>
  );
}
