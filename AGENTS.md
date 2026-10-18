<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## Demo and accelerator invariants

- This is a payment-free reference demo. Fulfillment is mocked; do not imply real
  payments, shipping, customer identity, or runtime shopping AI.
- Resolve prices from the server catalog. Preserve transactional order/item
  creation and synthetic-order cleanup; never accept client-supplied prices.
- Keep credentials, confirmation tokens, customer data, and infrastructure
  identifiers out of documentation and captured media.
- Use root `.env` for local Next.js/Prisma configuration. Products are
  version-controlled; `db:seed` checks connectivity only.
- Validate with `npm run check` and `npm run test:coverage`. Real persistence
  tests require explicit `TEST_DATABASE_URL` naming a disposable `_test` database.
- Infrastructure, policy, and compiled factory workflows are governance-controlled.
  Preserve the external kernel/ruleset boundary and the required `Validate` and
  `Analyze` check names.
- Keep catalog readiness claims evidence-based. Licensing, support ownership and
  catalog schema acceptance require owner confirmation, not inferred approval.
