# Meme Forge

A dark-themed meme sticker store built with Next.js, TypeScript, PostgreSQL,
Stripe Checkout, and an agent-driven GitHub delivery factory.

## Local development

```bash
npm install
copy .env.example .env.local
npm run db:generate
npm run dev
```

The storefront works without provider credentials. Checkout intentionally
returns `503` until `APP_URL`, `DATABASE_URL`, and Stripe test credentials are
configured.

## Commands

```bash
npm run lint
npm run typecheck
npm test
npm run test:coverage
npm run build
npm run check
```

## Database and Stripe

1. Provision a PostgreSQL database and set `DATABASE_URL`.
2. Run `npx prisma migrate dev --name init`.
3. Add `STRIPE_SECRET_KEY`.
4. Forward Stripe events to `/api/stripe/webhook` and add
   `STRIPE_WEBHOOK_SECRET`.
5. Set `APP_URL` to the deployed origin.

Checkout prices are resolved from the server-side catalog, not accepted from
the browser. Stripe events are signature-verified and stored by event ID before
order transitions, making retries idempotent.

## Factory model

GitHub Issues are the durable queue. GitHub Agentic Workflows create bounded
issues and pull requests using read-only agent jobs plus SafeOutputs.
Conventional Actions perform deterministic CI and enable GitHub-native
auto-merge only for factory-provenance PRs. Branch protection and required
checks remain the authority.

The policy in `.factory/policy.yml` defines WIP, retry, diff, risk, and rollout
limits. Changes to the policy and compiled factory workflows are deliberately
outside the implementation agent's allowed file set.

## One-time bootstrap

The unattended loop still requires a one-time owner to configure GitHub,
Vercel, PostgreSQL, Stripe, billing, secrets, repository rules, and DNS. After
that, routine implementation, review, merge, deployment, rollback, and incident
repair are designed to run without human approval.
