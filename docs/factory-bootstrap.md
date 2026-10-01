# Dark factory bootstrap

These are one-time owner actions. Routine changes must not require these
credentials in implementation or review jobs.

## GitHub

1. Enable Actions, Issues, Dependabot, and secret scanning.
2. Install the `gh-aw` extension and compile each `.github/workflows/factory-*.md`.
3. Commit each generated `.lock.yml`.
   Use the repository-compatible `gh-aw` compiler version `v0.88.8` and compile
   with `--action-mode action --action-tag
   5e508589e03a7757a7e05b26e834292f5445bfb6`. Commit
   `.github/aw/actions-lock.json` with the generated workflows. This preserves
   the validated runtime while pinning `github/gh-aw-actions/setup` to the
   immutable commit behind release `v0.88.8`.
4. Create a `main` ruleset that:
   - requires pull requests;
   - requires `CI / Validate` and `CodeQL / Analyze`;
   - handles merge queue events;
   - blocks force pushes and deletion;
   - does not require human approval.
   The included CodeQL job uses local SARIF enforcement so it also works when
   GitHub Advanced Security is not licensed for a private repository.
5. Create the labels referenced by `.factory/policy.yml` and the workflows.
6. Set the repository's default workflow permissions to **Read and write** and
   enable **Allow GitHub Actions to create and approve pull requests**. No
   personal token or GitHub App credential is required.

The conventional `Factory queue dispatcher` performs a low-cost 15-minute
reconciliation and invokes the AI implementer only when a ready/repair issue
exists, the WIP limit allows it, and no implementer is already active. It passes
the selected issue through `aw_context`, records bounded attempts, and uses the
workflow token for explicit `workflow_dispatch`. The implementer has no direct
issue-event activation or collaborator role check; GitHub's Actions permission
and the dispatcher context form the activation boundary.

Pull requests created with the workflow token cannot rely on recursive events:
enterprise policy may mark their `pull_request` runs `action_required`, and
token-created events may be suppressed. The conventional PR controller
therefore reconciles open factory PRs every five minutes and explicitly starts
CI, CodeQL, correctness review, and security review against the current head.
Event triggers are latency optimizations only.

The queue dispatcher records the exact implementer run ID on the selected
issue. The PR controller verifies that run, downloads its SafeOutputs artifact,
requires an exact `create_pull_request` item for the candidate PR, checks the
gh-aw provenance footer and same-repository branch, and writes a trusted
PR-to-issue marker. It does not rely on GitHub's closing-issue GraphQL field,
which can be empty for workflow-token PRs even when their body contains
`Closes #<issue>`.

The one-time migration away from GitHub App authentication is authorized only
when `FACTORY_TOKENLESS_MIGRATION_SHA` exactly matches the migration PR head.
This exception is non-reusable and exists separately from the consumed initial
bootstrap exception.

Implementation pull requests are opened ready for review and include a closing
keyword for readability. The scheduled lifecycle controller uses the trusted
provenance marker to close merged source issues explicitly, releases
failed/no-output runs for another bounded attempt, and returns closed or
review-rejected work to `factory:repair`.

Control-plane changes use a separate agent governance lane. They must carry the
`factory:governance` label, update source and compiled lock files together,
pass deterministic CI/CodeQL, and receive independent correctness and security
PASS verdicts bound to the current head SHA. The ordinary implementation agent
cannot edit `.github/**` or `.factory/**`.

The attestation reconciler enforces `factory:governance` whenever a pull request
changes control-plane paths, validates both PASS comments against successful
reviewer runs for the exact current head, and performs a direct squash merge. It
never leaves persistent auto-merge armed across later commits.

The policy, issue/PR dispatch controllers, independent reviewer definitions,
generated reviewer workflows, and attestation controller are root controls.
The initial dark-factory bootstrap establishes them once; ordinary
implementation and governance agents must not modify them afterward.

To authorize that one-time root-control bootstrap without weakening steady-state
automation, set the repository variable `FACTORY_ROOT_BOOTSTRAP_SHA` to the exact
head commit of the bootstrap pull request. The attestation controller refuses to
merge root-control changes at every other SHA. Delete the variable after the
bootstrap merges; the default Actions token is not granted repository-variable
administration.

The conventional `Factory queue dispatcher` performs a low-cost 15-minute
reconciliation and invokes the AI implementer only when a ready/repair issue
exists and no implementation PR is active. Scheduled agent runs should not be
used as idle polling.

Control-plane changes use a separate agent governance lane. They must carry the
`factory:governance` label, update source and compiled lock files together,
pass deterministic CI/CodeQL, and receive independent correctness and security
PASS verdicts bound to the current head SHA. The ordinary implementation agent
cannot edit `.github/**` or `.factory/**`.

The attestation reconciler enforces `factory:governance` whenever a pull request
changes control-plane paths, validates both PASS comments against successful
reviewer runs for the exact current head, and performs a direct squash merge. It
never leaves persistent auto-merge armed across later commits.

The policy, independent reviewer definitions, generated reviewer workflows, and
attestation controller are root controls. The initial dark-factory bootstrap
establishes them once; ordinary implementation and governance agents must not
modify them afterward.

To authorize that one-time root-control bootstrap without weakening steady-state
automation, set the repository variable `FACTORY_ROOT_BOOTSTRAP_SHA` to the exact
head commit of the bootstrap pull request. The attestation controller refuses to
merge root-control changes at every other SHA. Delete the variable after the
bootstrap merges; the default Actions token is not granted repository-variable
administration.

## Providers

The conventional `Autonomous release controller` is the only scheduled release
loop. Every 15 minutes (and on `workflow_dispatch`) it compares the latest main
SHA with successful GitHub production Deployments. A missing deployment is
released through staging and production; an already deployed SHA receives
ongoing health checks. Push delivery is not the source of truth.

1. Connect the repository to Vercel and create a custom `staging` environment.
2. Configure Vercel rolling release stages at 5%, 25%, 50%, and 100%.
3. Configure both `staging` and `production` GitHub environments. Do not add
   required reviewers because the controller is unattended.
4. Add these variables to each GitHub environment:
   - `APP_URL`: the stable HTTPS origin for that environment;
   - `VERCEL_ORG_ID`: the Vercel `team_...` or `user_...` ID;
   - `VERCEL_PROJECT_ID`: the Vercel `prj_...` project ID.
5. Add these secrets to each GitHub environment:
   - `VERCEL_TOKEN`: a token limited to the project/team;
   - `DATABASE_URL`: the environment-specific PostgreSQL connection URL;
   - `STRIPE_SECRET_KEY`: `sk_test_...` in staging; production may remain in
     test mode until live commerce is intentionally enabled;
   - `STRIPE_WEBHOOK_SECRET`: the environment-specific `whsec_...` secret.
   - Optional `VERCEL_AUTOMATION_BYPASS_SECRET`: the environment's deployment
     protection bypass secret when Vercel protection would otherwise reject
     controller probes.
6. Configure the matching Vercel environment variables `APP_URL`,
   `DATABASE_URL`, `STRIPE_SECRET_KEY`, and `STRIPE_WEBHOOK_SECRET`. The GitHub
   copies are used only for migrations and non-transactional release probes;
   Vercel's copies are the application runtime configuration.
7. Provision independent staging and production PostgreSQL databases and apply
   least-privilege/network controls that still permit GitHub-hosted runners.
8. Register separate Stripe webhook endpoints for the staging and production
   origins at `/api/stripe/webhook`.

The controller fails closed when any required value is absent or malformed.
It also pulls Vercel's selected environment before migration and confirms the
four required runtime keys exist without printing their values. Staging must
use a Stripe test secret. Release probes only perform HTTP GETs, `prisma migrate
status`, and Stripe's read-only account retrieval API. They never create
Checkout Sessions, PaymentIntents, test clocks, refunds, or live card charges.

Database migrations are applied before each deployment only after the
controller verifies that previously deployed migrations were not changed and
that new SQL contains no destructive/rollback-unsafe statements. Schema
changes must use an additive expand/migrate/contract sequence across separate
releases.

After staging migration, deployment, and probes pass, the controller deploys
the exact same main SHA with Vercel's production target. GitHub Deployment
statuses and retained JSON evidence record the SHA, URLs, previous production,
workflow run, timestamp, and outcome.

If the new production health gate fails, the controller first aborts any active
Vercel rolling release and then rolls back to the URL from the previous
successful GitHub production Deployment. Additive migrations remain in place
and must be backward-compatible with the restored application. If Vercel is
unavailable, abort/rollback errors are preserved in the failed run and the
deduplicated `[factory signal] Autonomous release controller blocked` issue
is updated with `factory:incident`, `factory:repair`, and `factory:signal`.

Scheduled failures for an already deployed SHA abort an active rollout but do
not blindly roll back: a provider, network, database, or Stripe outage is not
enough evidence that the prior application version is safer. Recovery closes
the open release incident. If no previous successful production Deployment URL
exists, the first production promotion fails closed rather than claiming an
automatic rollback succeeded.

## Proving exercises

- Put prompt-injection text in an issue and verify tool/file scope does not widen.
- Break lint, type checking, tests, and build separately.
- Create a merge conflict and verify bounded repair behavior.
- Replay a Stripe event and verify no duplicate transition occurs.
- Fail `/api/health` during a rolling release and verify abort plus incident issue.
- Attempt to edit `.factory/policy.yml` from the implementer workflow and verify
  the patch is rejected or converted into an issue.
