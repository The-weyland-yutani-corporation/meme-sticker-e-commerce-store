# Meme Forge

A dark-themed meme sticker store built with Next.js, TypeScript, PostgreSQL,
Azure App Service, and an agent-driven GitHub delivery factory.

## Local development

```bash
npm install
copy .env.example .env.local
npm run db:generate
npm run dev
```

The storefront works without cloud credentials. Checkout creates a
payment-free test order when `DATABASE_URL` is configured.

## Commands

```bash
npm run lint
npm run typecheck
npm test
npm run test:coverage
npm run build
npm run check
```

## Database and test orders

1. Provision a PostgreSQL database and set `DATABASE_URL`.
2. Run `npx prisma migrate dev --name init`.
3. Set `APP_URL` to the deployed origin.
4. Set `SYNTHETIC_PROBE_TOKEN` only when exercising the internal production
   probe.

Checkout prices are resolved from the server-side catalog, not accepted from
the browser. Order and item creation is transactional, no payment is collected,
and fulfillment remains mocked.

## Factory model

GitHub Issues are the durable queue. GitHub Agentic Workflows create bounded
issues and pull requests using read-only agent jobs plus SafeOutputs.
Conventional Actions perform deterministic CI and enable GitHub-native
direct merge only for factory-provenance PRs with current-head attestations. Branch protection and required
checks remain the authority.

The policy in `.factory/policy.yml` defines WIP, retry, diff, risk, and rollout
limits. Changes to the policy and compiled factory workflows are deliberately
outside the implementation agent's allowed file set.

The conventional [factory signal collector](docs/factory-signals.md) ingests
failed main checks, factory workflow failures, dependency/security maintenance,
production incidents, and queue drift into deduplicated evidence issues. The
AI intent planner only converts current evidence into work when policy capacity
exists.

## One-time bootstrap

The unattended loop still requires a one-time owner to configure the external
GitHub ruleset and run the Azure OIDC/Bicep bootstrap. After that, routine
implementation, review, merge, infrastructure reconciliation, deployment,
rollback, monitoring, and incident repair are designed to run without human
approval.

The scheduled release controller reconciles the latest main SHA against GitHub
Deployments, builds an immutable Next.js package, validates additive migrations,
deploys directly to Azure App Service, runs health and synthetic-order probes,
records deployment evidence, and redeploys the previous package after a failed
new release. Exact variables, OIDC bootstrap, Azure resources, and outage
behavior are documented in [docs/factory-bootstrap.md](docs/factory-bootstrap.md).
