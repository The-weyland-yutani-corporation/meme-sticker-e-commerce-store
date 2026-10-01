#!/usr/bin/env bash

set -euo pipefail

action="${1:?usage: incident.sh <report|resolve> [summary]}"
summary="${2:-Release controller failure}"
title="[factory incident] Autonomous release controller blocked"
repository="${REPOSITORY:-${GITHUB_REPOSITORY:-}}"

if [[ -z "$repository" ]]; then
  echo "REPOSITORY or GITHUB_REPOSITORY is required." >&2
  exit 1
fi

existing_issue="$(
  gh issue list \
    --repo "$repository" \
    --state open \
    --label "factory:incident" \
    --limit 100 \
    --json number,title \
    --jq '.[] |
      select(.title == "[factory incident] Autonomous release controller blocked") |
      .number' |
    head -n 1
)"

if [[ "$action" == "resolve" ]]; then
  if [[ -n "$existing_issue" ]]; then
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

body="$(cat <<EOF
${summary}

- Phase: \`${RELEASE_PHASE:-unknown}\`
- Target main SHA: \`${TARGET_SHA:-unknown}\`
- Workflow run: ${RUN_URL:-unknown}

The controller failed closed. Review the workflow evidence before retrying. No
Stripe charge or other transactional synthetic operation was attempted.
EOF
)"

if [[ -n "$existing_issue" ]]; then
  gh issue comment "$existing_issue" --repo "$repository" --body "$body"
else
  gh issue create \
    --repo "$repository" \
    --title "$title" \
    --body "$body" \
    --label "factory:incident,factory:repair"
fi
