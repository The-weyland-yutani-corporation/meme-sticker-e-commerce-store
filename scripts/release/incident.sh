#!/usr/bin/env bash

set -euo pipefail

action="${1:?usage: incident.sh <report|resolve> [summary]}"
summary="${2:-Release controller failure}"
fingerprint="production-release:autonomous-controller"
marker="<!-- factory-signal:${fingerprint} -->"
title="[factory signal] Autonomous release controller blocked"
repository="${REPOSITORY:-${GITHUB_REPOSITORY:-}}"

if [[ -z "$repository" ]]; then
  echo "REPOSITORY or GITHUB_REPOSITORY is required." >&2
  exit 1
fi

existing_issue="$(
  gh api --paginate --slurp \
    "repos/${repository}/issues?state=all&labels=factory%3Asignal&per_page=100" |
    jq -r --arg marker "$marker" '
      add |
      [
        .[] |
        select(
          .pull_request == null and
          ((.body // "") | contains($marker))
        )
      ] |
      sort_by(.number) |
      first.number // empty
    '
)"

if [[ -z "$existing_issue" ]]; then
  existing_issue="$(
    gh issue list \
      --repo "$repository" \
      --state all \
      --search '"[factory incident] Autonomous release controller blocked" in:title' \
      --limit 1 \
      --json number \
      --jq '.[0].number // empty'
  )"
fi

if [[ "$action" == "resolve" ]]; then
  if [[ -n "$existing_issue" ]] &&
    [[ "$(gh issue view "$existing_issue" --repo "$repository" --json state --jq '.state')" == "OPEN" ]]; then
    gh issue close "$existing_issue" \
      --repo "$repository" \
      --comment "Release reconciliation recovered successfully for \`${TARGET_SHA:-unknown}\`. Run: ${RUN_URL:-unknown}"
  fi
  exit 0
fi

if [[ "$action" != "report" ]]; then
  echo "Unknown action: $action" >&2
  exit 1
fi

gh label create "factory:incident" \
  --repo "$repository" \
  --color "B60205" \
  --description "Automated factory incident" 2>/dev/null || true
gh label create "factory:repair" \
  --repo "$repository" \
  --color "D93F0B" \
  --description "Factory repair queue" 2>/dev/null || true
gh label create "factory:signal" \
  --repo "$repository" \
  --color "1D76DB" \
  --description "Deterministic repository or production signal" 2>/dev/null || true

body="$(cat <<EOF
## Active factory signal

- Priority: \`P1\`
- Category: \`production\`
- Fingerprint: \`${fingerprint}\`
- First observed: \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`
- Last observed: \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`

## Summary

${summary}

## Deterministic evidence

- Phase: \`${RELEASE_PHASE:-unknown}\`
- Target main SHA: \`${TARGET_SHA:-unknown}\`
- Workflow run: ${RUN_URL:-unknown}

## Required response

The controller failed closed. Review the workflow evidence before retrying. No
Stripe charge or other transactional synthetic operation was attempted.

${marker}
<!-- factory-signal-category:production -->
EOF
)"

if [[ -n "$existing_issue" ]]; then
  if gh api "repos/${repository}/issues/${existing_issue}" \
    --jq '
      (.state_reason // "") == "not_planned" or
      ([.labels[].name] | index("factory:muted") != null)
    ' | grep -Fxq true; then
    echo "Release signal #$existing_issue is muted or closed as not planned."
    exit 0
  fi
  gh issue reopen "$existing_issue" --repo "$repository" 2>/dev/null || true
  gh issue edit "$existing_issue" \
    --repo "$repository" \
    --title "$title" \
    --add-label "factory:incident,factory:repair,factory:signal"
  if gh issue view "$existing_issue" \
    --repo "$repository" \
    --json body \
    --jq '.body' |
    grep -Fq "$marker"; then
    gh issue comment "$existing_issue" --repo "$repository" --body "$body"
  else
    gh issue edit "$existing_issue" --repo "$repository" --body "$body"
  fi
else
  gh issue create \
    --repo "$repository" \
    --title "$title" \
    --body "$body" \
    --label "factory:incident,factory:repair,factory:signal"
fi
