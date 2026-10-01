# Factory signals

The factory signal collector is a conventional GitHub Actions workflow that
runs twice an hour. It performs deterministic GitHub API and production-health
checks without invoking an AI agent. Agentic planning remains a separate,
budgeted step.

## Priority order

Signals are considered in this order:

1. **P1 production:** failed Azure production probes, rollback failures,
   unavailable telemetry, threshold breaches, or open production incidents.
2. **P2 main, cost, and factory reliability:** Azure budget breaches or unknown
   spend, failed or stalled CI, CodeQL, factory workflows, and queue drift.
3. **P3 maintenance:** open high/critical Dependabot alerts, code-scanning
   alerts, and Dependabot pull requests that are failing or at least seven days
   old.

The intent planner uses the same order, but it creates implementation work only
when the evidence is current, all WIP and pull-request capacity gates pass, no
equivalent work is queued, and the remediation fits the implementation
authority in `.factory/policy.yml`. Governance, credential, provider, and root
control changes remain outside that planner.

## Fingerprints and deduplication

Each operational condition has a stable fingerprint, such as
`main-check:ci.yml`, `factory-workflows:health`,
`dependency-security:open-maintenance`, `production-health:api-health`, or
`factory-queue:drift`.

The collector stores the fingerprint in an HTML marker in the issue body and
reuses the same issue across repeated observations. It updates an open issue
only when the material evidence changes or the six-hour observation cooldown
expires. Cleared signals are closed; recurrence reopens the same issue. This
keeps durable history without comments or new issues for every scheduled run.

Azure evidence uses stable fingerprints such as
`azure-observability:production`, `production-health:api-health`, and
`production-release:autonomous-controller`. The budget signal uses
`azure-budget:production`. App Service HTTP 5xx and response time plus
PostgreSQL CPU/storage are evaluated over bounded windows, and month-to-date
Azure spend is compared with the configured $75 threshold. Missing Azure
access, metric samples, or cost data is `unknown` and creates evidence; it is
never interpreted as healthy.

Dependency and security findings are aggregated into one maintenance signal
rather than creating an issue per alert. Factory workflow failures are likewise
aggregated into one health signal. Evidence is capped to bounded lists.
Unavailable GitHub security APIs are recorded as unsupported and are not
treated as proof of a clean repository.

Maintainers can apply `factory:muted` or close an issue as not planned to
suppress automatic updates and reopening. Removing that override returns the
fingerprint to normal reconciliation.

## Evidence shape

Every signal issue contains:

- priority, category, stable fingerprint, and first/last observation times;
- a concise summary;
- canonical JSON evidence with GitHub run, alert, pull request, or incident
  URLs and policy thresholds;
- a bounded required response;
- machine-readable category, state-hash, and update-time markers.

The state hash excludes the observation timestamp. Unchanged polling therefore
does not produce an issue edit until the cooldown expires.

## Budgets and idle behavior

The collector never changes WIP, retry, diff, release, or AI budgets. It does
not label signal issues `factory:ready` or `factory:repair`; only the intent
planner may create a bounded implementation item after checking capacity.

When no signal is active, the collector creates nothing and closes previously
active signal issues whose categories were successfully evaluated. If a scan
cannot complete, the workflow fails before reconciliation instead of
success-shaped cleanup. The planner and auditor must use their noop SafeOutput
when there is no evidence-backed action.

The auditor runs twice daily. It treats the signal collector and existing
signal issues as primary evidence, suppresses transient failures inside
cooldown/retry budgets, and does not duplicate an open signal or unchanged
audit fingerprint.
