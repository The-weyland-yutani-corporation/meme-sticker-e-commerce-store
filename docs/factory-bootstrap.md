# Dark factory bootstrap

These are one-time owner actions. Routine changes must not require these
credentials in implementation or review jobs.

## GitHub

1. Enable Actions, Issues, auto-merge, Dependabot, and secret scanning.
2. Install the `gh-aw` extension and compile each `.github/workflows/factory-*.md`.
3. Commit each generated `.lock.yml`.
4. Create a `main` ruleset that:
   - requires pull requests;
   - requires `CI / Validate` and `CodeQL / Analyze`;
   - handles merge queue events;
   - blocks force pushes and deletion;
   - does not require human approval.
   The included CodeQL job uses local SARIF enforcement so it also works when
   GitHub Advanced Security is not licensed for a private repository.
5. Create the labels referenced by `.factory/policy.yml` and the workflows.
6. Add a narrowly scoped `GH_AW_CI_TRIGGER_TOKEN` or GitHub App credential if
   factory-created pull requests do not start CI with the default token.

## Providers

1. Connect the repository to Vercel.
2. Configure rolling release stages at 5%, 25%, 50%, and 100%.
3. Add `PRODUCTION_HEALTH_URL` as a repository variable.
4. Add `VERCEL_TOKEN` only to the production health controller environment.
5. Provision PostgreSQL and add `DATABASE_URL` to Vercel.
6. Add Stripe test credentials and configure `/api/stripe/webhook`.
7. Promote to Stripe live mode only after a successful synthetic checkout and
   rollback exercise.

## Proving exercises

- Put prompt-injection text in an issue and verify tool/file scope does not widen.
- Break lint, type checking, tests, and build separately.
- Create a merge conflict and verify bounded repair behavior.
- Replay a Stripe event and verify no duplicate transition occurs.
- Fail `/api/health` during a rolling release and verify abort plus incident issue.
- Attempt to edit `.factory/policy.yml` from the implementer workflow and verify
  the patch is rejected or converted into an issue.
