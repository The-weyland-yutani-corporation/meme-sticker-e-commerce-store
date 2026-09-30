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

Pull requests created with the workflow token do not emit recursive
`pull_request` events. The conventional PR-dispatch controller therefore starts
CI, CodeQL, correctness review, and security review explicitly against the PR
head. Reviewer completion then wakes the deterministic attestation controller.
The dispatcher records the exact implementer run ID on the selected issue; the
PR controller uses that binding and the PR's closing-issue reference rather than
guessing among concurrent work.
For direct pull-request events, the controller also requires a same-repository
head and an owner/member/collaborator association (or the verified Dependabot
identity) before it can dispatch AI reviews.

The one-time migration away from GitHub App authentication is authorized only
when `FACTORY_TOKENLESS_MIGRATION_SHA` exactly matches the migration PR head.
This exception is non-reusable and exists separately from the consumed initial
bootstrap exception.

Implementation pull requests are opened ready for review and link their issue
with a closing keyword. The lifecycle controller releases failed/no-output runs
for another bounded attempt, while the review repair bridge closes rejected PRs
and returns their linked issues to `factory:repair`.

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
