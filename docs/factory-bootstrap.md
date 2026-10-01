# Dark factory bootstrap

These are one-time owner actions. Routine changes must not require these
credentials in implementation or review jobs.

## GitHub

1. Enable Actions, Issues, Dependabot, and secret scanning.
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
