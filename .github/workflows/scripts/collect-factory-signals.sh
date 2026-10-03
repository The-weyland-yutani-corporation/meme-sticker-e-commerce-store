#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${REPOSITORY:?REPOSITORY is required}"

DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
SIGNAL_COOLDOWN_HOURS="${SIGNAL_COOLDOWN_HOURS:-6}"
DRY_RUN="${DRY_RUN:-0}"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date -u +%s)"
COOLDOWN_SECONDS="$((SIGNAL_COOLDOWN_HOURS * 3600))"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
issues_cache="$work_dir/signal-issues.json"
active_signals="$work_dir/active-signals.tsv"
evaluated_categories="$work_dir/evaluated-categories.txt"
: >"$active_signals"
: >"$evaluated_categories"

policy_value() {
  local section="$1"
  local key="$2"
  awk -v section="$section" -v key="$key" '
    $0 == section ":" { in_section=1; next }
    in_section && /^[^ ]/ { in_section=0 }
    in_section && $1 == key ":" { print $2; exit }
  ' .factory/policy.yml
}

wip_limit="$(policy_value queue work_in_progress_limit)"
max_attempts="$(policy_value queue max_attempts_per_issue)"
max_open_prs="$(policy_value queue max_open_factory_pull_requests)"
max_agent_minutes="$(policy_value budgets max_agent_minutes_per_issue)"
: "${wip_limit:?Missing queue.work_in_progress_limit}"
: "${max_attempts:?Missing queue.max_attempts_per_issue}"
: "${max_open_prs:?Missing queue.max_open_factory_pull_requests}"
: "${max_agent_minutes:?Missing budgets.max_agent_minutes_per_issue}"

ensure_label() {
  local name="$1"
  local color="$2"
  local description="$3"
  local encoded_name
  encoded_name="$(jq -rn --arg value "$name" '$value | @uri')"
  if gh api "repos/$REPOSITORY/labels/$encoded_name" >/dev/null 2>&1; then
    return
  fi
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] create label: $name"
    return
  fi
  if ! gh label create "$name" \
    --repo "$REPOSITORY" \
    --color "$color" \
    --description "$description"; then
    gh api "repos/$REPOSITORY/labels/$encoded_name" >/dev/null
  fi
}

ensure_label "factory:signal" "1D76DB" "Deterministic repository or production signal"
ensure_label "signal:ci" "D93F0B" "Main branch CI or CodeQL signal"
ensure_label "signal:factory" "8250DF" "Factory workflow signal"
ensure_label "signal:dependencies" "0E8A16" "Dependency or security maintenance signal"
ensure_label "signal:production" "B60205" "Production health or release signal"
ensure_label "signal:queue" "FBCA04" "Factory queue drift signal"
ensure_label "signal:priority-1" "B60205" "Immediate operational response"
ensure_label "signal:priority-2" "D93F0B" "Prompt bounded remediation"
ensure_label "signal:priority-3" "FBCA04" "Maintenance when capacity permits"
ensure_label "factory:incident" "B60205" "Factory or production incident"
ensure_label "factory:muted" "6E7781" "Suppress automatic signal updates and reopening"

gh api --paginate --slurp \
  "repos/$REPOSITORY/issues?state=all&labels=factory%3Asignal&per_page=100" |
  jq 'add | map(select(.pull_request == null))' >"$issues_cache"

mark_evaluated() {
  printf '%s\n' "$1" >>"$evaluated_categories"
}

to_epoch() {
  date -u -d "$1" +%s
}

is_active_status() {
  case "$1" in
    queued | in_progress | waiting | requested | pending)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_failed_conclusion() {
  case "$1" in
    failure | stale | startup_failure | timed_out)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

record_active() {
  printf '%s\t%s\n' "$1" "$2" >>"$active_signals"
}

upsert_signal() {
  local priority="$1"
  local category="$2"
  local fingerprint="$3"
  local title="$4"
  local summary="$5"
  local evidence="$6"
  local response="$7"
  local labels="$8"
  local state_key="$9"
  local marker="<!-- factory-signal:${fingerprint} -->"
  local state_hash
  local existing
  local issue_number
  local issue_state
  local existing_body
  local first_observed
  local last_update_epoch
  local existing_hash
  local update_due=0
  local body_file="$work_dir/body.md"
  local label
  local -a label_args=(-f "labels[]=factory:signal")
  local -a signal_labels=()

  IFS=',' read -r -a signal_labels <<<"$labels"
  for label in "${signal_labels[@]}"; do
    label_args+=(-f "labels[]=$label")
  done

  state_hash="$(
    printf '%s' "$priority|$category|$state_key|$response" |
      sha256sum |
      awk '{print $1}'
  )"
  existing="$(
    jq -c --arg marker "$marker" \
      '[.[] | select((.body // "") | contains($marker))] | sort_by(.number) | first // empty' \
      "$issues_cache"
  )"
  issue_number="$(jq -r '.number // empty' <<<"$existing")"
  issue_state="$(jq -r '.state // empty' <<<"$existing")"
  existing_body="$(jq -r '.body // ""' <<<"$existing")"
  if [ -n "$existing" ] &&
    jq -e '
      (.state_reason // "") == "not_planned" or
      ([.labels[].name] | index("factory:muted") != null)
    ' <<<"$existing" >/dev/null; then
    record_active "$category" "$fingerprint"
    echo "Signal #$issue_number is muted or closed as not planned: $fingerprint"
    return
  fi
  first_observed="$(
    # The backticks are literal Markdown delimiters in the stored issue body.
    # shellcheck disable=SC2016
    sed -n 's/^- First observed: `\([^`]*\)`.*/\1/p' <<<"$existing_body" |
      head -n 1
  )"
  first_observed="${first_observed:-$NOW_ISO}"
  last_update_epoch="$(
    sed -n 's/.*<!-- factory-signal-updated:\([0-9][0-9]*\) -->.*/\1/p' \
      <<<"$existing_body" |
      head -n 1
  )"
  last_update_epoch="${last_update_epoch:-0}"
  existing_hash="$(
    sed -n 's/.*<!-- factory-signal-state:\([a-f0-9][a-f0-9]*\) -->.*/\1/p' \
      <<<"$existing_body" |
      head -n 1
  )"

  cat >"$body_file" <<EOF
## Active factory signal

- Priority: \`$priority\`
- Category: \`$category\`
- Fingerprint: \`$fingerprint\`
- First observed: \`$first_observed\`
- Last observed: \`$NOW_ISO\`

## Summary

$summary

## Deterministic evidence

$(jq -S . <<<"$evidence" | sed 's/^/    /')

## Required response

$response

This issue is maintained by the scheduled factory signal collector. It is not
an implementation queue item until the intent planner verifies policy capacity,
an allowed file scope, objective acceptance criteria, and bounded rollback.

$marker
<!-- factory-signal-category:$category -->
<!-- factory-signal-state:$state_hash -->
<!-- factory-signal-updated:$NOW_EPOCH -->
EOF

  record_active "$category" "$fingerprint"

  if [ -z "$issue_number" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      echo "[dry-run] create signal: $title ($fingerprint)"
      return
    fi
    local created
    created="$(
      gh api --method POST "repos/$REPOSITORY/issues" \
        -f title="$title" \
        -f body="$(cat "$body_file")" \
        "${label_args[@]}" \
        --jq '{number, state, title, body, labels}'
    )"
    jq --argjson created "$created" '. + [$created]' "$issues_cache" \
      >"$issues_cache.next"
    mv "$issues_cache.next" "$issues_cache"
    echo "Created signal issue #$(jq -r '.number' <<<"$created"): $title"
    return
  fi

  if [ "$issue_state" != "open" ]; then
    update_due=1
  elif [ "$existing_hash" != "$state_hash" ]; then
    update_due=1
  elif [ "$((NOW_EPOCH - last_update_epoch))" -ge "$COOLDOWN_SECONDS" ]; then
    update_due=1
  fi

  if [ "$update_due" -eq 0 ]; then
    echo "Signal #$issue_number unchanged inside cooldown: $fingerprint"
    return
  fi
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] update signal #$issue_number: $fingerprint"
    return
  fi
  if [ "$issue_state" != "open" ]; then
    gh issue reopen "$issue_number" --repo "$REPOSITORY"
  fi
  gh issue edit "$issue_number" \
    --repo "$REPOSITORY" \
    --title "$title" \
    --body-file "$body_file" \
    --add-label "factory:signal,$labels"
  echo "Updated signal issue #$issue_number: $title"
}

collect_main_checks() {
  local workflow
  local runs
  local completed_run
  local active_run
  local run
  local status
  local conclusion
  local updated_at
  local age_minutes
  local workflow_name
  local priority
  local summary
  local response
  local evidence
  local state_key

  for workflow in ci.yml codeql.yml; do
    runs="$(
      gh run list \
        --repo "$REPOSITORY" \
        --workflow "$workflow" \
        --branch "$DEFAULT_BRANCH" \
        --limit 10 \
        --json databaseId,workflowName,status,conclusion,createdAt,updatedAt,url,headSha,event
    )"
    completed_run="$(
      jq -c '[
        .[] |
        select(
          .status == "completed" and
          (
            .conclusion == "success" or
            .conclusion == "failure" or
            .conclusion == "stale" or
            .conclusion == "startup_failure" or
            .conclusion == "timed_out"
          )
        )
      ] | first // empty' <<<"$runs"
    )"
    active_run="$(
      jq -c '[
        .[] |
        select(
          .status == "queued" or
          .status == "in_progress" or
          .status == "waiting" or
          .status == "requested" or
          .status == "pending"
        )
      ] | first // empty' <<<"$runs"
    )"
    run="$completed_run"
    if [ -z "$run" ]; then
      run="$active_run"
    fi
    [ -n "$run" ] || continue
    status="$(jq -r '.status' <<<"$run")"
    conclusion="$(jq -r '.conclusion // ""' <<<"$run")"
    updated_at="$(jq -r '.updatedAt' <<<"$run")"
    age_minutes="$(((NOW_EPOCH - $(to_epoch "$updated_at")) / 60))"
    workflow_name="$(jq -r '.workflowName' <<<"$run")"
    priority="P2"
    summary=""
    response="Repair the default branch with the smallest policy-compliant change and verify the failed workflow."

    if is_failed_conclusion "$conclusion"; then
      summary="The latest \`$workflow_name\` run on \`$DEFAULT_BRANCH\` concluded \`$conclusion\`."
      state_key="$(jq -c '{databaseId,status,conclusion,headSha}' <<<"$run")"
    elif [ -n "$active_run" ]; then
      run="$active_run"
      status="$(jq -r '.status' <<<"$run")"
      updated_at="$(jq -r '.updatedAt' <<<"$run")"
      age_minutes="$(((NOW_EPOCH - $(to_epoch "$updated_at")) / 60))"
      workflow_name="$(jq -r '.workflowName' <<<"$run")"
      if ! is_active_status "$status" ||
        [ "$age_minutes" -le "$max_agent_minutes" ]; then
        continue
      fi
      summary="The latest \`$workflow_name\` run on \`$DEFAULT_BRANCH\` has remained \`$status\` for ${age_minutes} minutes."
      state_key="$(jq -c '{databaseId,status,headSha}' <<<"$run")"
    else
      continue
    fi
    evidence="$(
      jq -cn \
        --arg source "github-actions" \
        --arg workflow "$workflow" \
        --argjson run "$run" \
        --argjson age_minutes "$age_minutes" \
        '{source:$source, workflow:$workflow, age_minutes:$age_minutes, run:$run}'
    )"
    upsert_signal \
      "$priority" \
      "ci" \
      "main-check:$workflow" \
      "[factory signal] Main check requires attention: $workflow_name" \
      "$summary" \
      "$evidence" \
      "$response" \
      "signal:ci,signal:priority-2,factory:incident" \
      "$state_key"
  done
  mark_evaluated "ci"
}

collect_factory_workflows() {
  local workflow
  local path
  local name
  local runs
  local completed_run
  local active_run
  local run
  local status
  local conclusion
  local updated_at
  local age_minutes
  local summary
  local evidence
  local findings='[]'
  local state_key

  while IFS= read -r workflow; do
    path="$(jq -r '.path' <<<"$workflow")"
    name="$(jq -r '.name' <<<"$workflow")"
    [ "$path" != ".github/workflows/factory-signal-collector.yml" ] || continue
    runs="$(
      gh run list \
        --repo "$REPOSITORY" \
        --workflow "$path" \
        --branch "$DEFAULT_BRANCH" \
        --limit 10 \
        --json databaseId,workflowName,status,conclusion,createdAt,updatedAt,url,headSha,event
    )"
    completed_run="$(
      jq -c '[
        .[] |
        select(
          .status == "completed" and
          (
            .conclusion == "success" or
            .conclusion == "failure" or
            .conclusion == "stale" or
            .conclusion == "startup_failure" or
            .conclusion == "timed_out"
          )
        )
      ] | first // empty' <<<"$runs"
    )"
    active_run="$(
      jq -c '[
        .[] |
        select(
          .status == "queued" or
          .status == "in_progress" or
          .status == "waiting" or
          .status == "requested" or
          .status == "pending"
        )
      ] | first // empty' <<<"$runs"
    )"
    run="$completed_run"
    if [ -z "$run" ]; then
      run="$active_run"
    fi
    [ -n "$run" ] || continue
    status="$(jq -r '.status' <<<"$run")"
    conclusion="$(jq -r '.conclusion // ""' <<<"$run")"
    updated_at="$(jq -r '.updatedAt' <<<"$run")"
    age_minutes="$(((NOW_EPOCH - $(to_epoch "$updated_at")) / 60))"
    summary=""

    if is_failed_conclusion "$conclusion"; then
      summary="The latest \`$name\` run on \`$DEFAULT_BRANCH\` concluded \`$conclusion\`."
    elif [ -n "$active_run" ]; then
      run="$active_run"
      status="$(jq -r '.status' <<<"$run")"
      updated_at="$(jq -r '.updatedAt' <<<"$run")"
      age_minutes="$(((NOW_EPOCH - $(to_epoch "$updated_at")) / 60))"
      if ! is_active_status "$status" ||
        [ "$age_minutes" -le "$max_agent_minutes" ]; then
        continue
      fi
      summary="The latest \`$name\` run has remained \`$status\` for ${age_minutes} minutes, beyond the ${max_agent_minutes}-minute agent budget."
    else
      continue
    fi
    findings="$(
      jq -cn \
        --argjson current "$findings" \
        --arg workflow "$path" \
        --arg summary "$summary" \
        --argjson run "$run" \
        --argjson age_minutes "$age_minutes" \
        '$current + [{
          workflow:$workflow,
          summary:$summary,
          age_minutes:$age_minutes,
          run:$run
        }]'
    )"
  done < <(
    gh workflow list --repo "$REPOSITORY" --all --json name,path,state |
      jq -c '.[] | select(.state == "active" and (.path | test("^\\.github/workflows/factory-.*\\.yml$")))'
  )

  if [ "$(jq 'length' <<<"$findings")" -gt 0 ]; then
    summary="$(jq -r 'map(.summary) | join(" ")' <<<"$findings")"
    evidence="$(
      jq -cn \
        --arg source "github-actions" \
        --argjson max_agent_minutes "$max_agent_minutes" \
        --argjson findings "$findings" \
        '{
          source:$source,
          budget_minutes:$max_agent_minutes,
          workflows:$findings
        }'
    )"
    state_key="$(
      jq -c '[
        .[] |
        {
          workflow,
          run:{
            databaseId:.run.databaseId,
            status:.run.status,
            conclusion:.run.conclusion,
            headSha:.run.headSha
          }
        }
      ] | sort_by(.workflow)' <<<"$findings"
    )"
    upsert_signal \
      "P2" \
      "factory" \
      "factory-workflows:health" \
      "[factory signal] Factory workflows require attention" \
      "$summary" \
      "$evidence" \
      "Diagnose the recorded runs. Use bounded retries or the governance lane; do not weaken permissions, checks, or retry ceilings." \
      "signal:factory,signal:priority-2,factory:incident" \
      "$state_key"
  fi
  mark_evaluated "factory"
}

collect_dependency_security() {
  local dependabot_prs
  local dependabot_alerts='[]'
  local code_alerts='[]'
  local alerts_supported=false
  local code_alerts_supported=false
  local actionable_prs
  local high_alert_count
  local code_alert_count
  local actionable_pr_count
  local summary
  local evidence

  dependabot_prs="$(
    gh pr list \
      --repo "$REPOSITORY" \
      --state open \
      --author "app/dependabot" \
      --limit 100 \
      --json number,title,url,createdAt,updatedAt,isDraft,statusCheckRollup
  )"
  actionable_prs="$(
    jq -c --argjson now "$NOW_EPOCH" '
      [
        .[] |
        . + {
          age_days: ((($now - (.createdAt | fromdateiso8601)) / 86400) | floor),
          failed_checks: [
            .statusCheckRollup[]? |
            select(
              (.conclusion // .state // "") as $conclusion |
              ["ACTION_REQUIRED","CANCELLED","FAILURE","STALE","STARTUP_FAILURE","TIMED_OUT"] |
              index($conclusion)
            )
          ] | length
        } |
        select(.age_days >= 7 or .failed_checks > 0) |
        {
          number,
          title,
          url,
          age_days,
          failed_checks
        }
      ]
    ' <<<"$dependabot_prs"
  )"

  if dependabot_alerts="$(
    gh api --paginate --slurp \
      "repos/$REPOSITORY/dependabot/alerts?state=open&per_page=100" \
      2>"$work_dir/dependabot-alerts.err" |
      jq 'add'
  )"; then
    alerts_supported=true
  elif grep -Eq 'HTTP 404|Not Found' "$work_dir/dependabot-alerts.err"; then
    alerts_supported=true
    dependabot_alerts='[]'
  else
    dependabot_alerts='[]'
  fi
  if code_alerts="$(
    gh api --paginate --slurp \
      "repos/$REPOSITORY/code-scanning/alerts?state=open&per_page=100" \
      2>"$work_dir/code-scanning-alerts.err" |
      jq 'add'
  )"; then
    code_alerts_supported=true
  elif grep -Eq 'HTTP 404|Not Found' "$work_dir/code-scanning-alerts.err"; then
    code_alerts_supported=true
    code_alerts='[]'
  else
    code_alerts='[]'
  fi

  actionable_pr_count="$(jq 'length' <<<"$actionable_prs")"
  high_alert_count="$(
    jq '[
      .[] |
      select(
        (.security_advisory.severity // "") == "high" or
        (.security_advisory.severity // "") == "critical"
      )
    ] | length' <<<"$dependabot_alerts"
  )"
  code_alert_count="$(jq 'length' <<<"$code_alerts")"

  if [ "$actionable_pr_count" -eq 0 ] &&
    [ "$high_alert_count" -eq 0 ] &&
    [ "$code_alert_count" -eq 0 ]; then
    if [ "$alerts_supported" = "true" ] &&
      [ "$code_alerts_supported" = "true" ]; then
      mark_evaluated "dependencies"
    else
      echo "Dependency/security APIs were not fully available; preserving any existing signal."
    fi
    return
  fi

  summary="GitHub reports ${high_alert_count} open high/critical Dependabot alerts, ${code_alert_count} open code-scanning alerts, and ${actionable_pr_count} stale or failing Dependabot pull requests."
  evidence="$(
    jq -cn \
      --arg source "github-security-and-dependabot" \
      --argjson dependabot_api_supported "$alerts_supported" \
      --argjson code_scanning_api_supported "$code_alerts_supported" \
      --argjson dependabot_alerts "$dependabot_alerts" \
      --argjson code_alerts "$code_alerts" \
      --argjson actionable_prs "$actionable_prs" \
      '{
        source:$source,
        api_support:{
          dependabot_alerts:$dependabot_api_supported,
          code_scanning_alerts:$code_scanning_api_supported
        },
        high_or_critical_dependabot_alerts:[
          $dependabot_alerts[] |
          select(
            (.security_advisory.severity // "") == "high" or
            (.security_advisory.severity // "") == "critical"
          ) |
          {
            number,
            severity:.security_advisory.severity,
            advisory:.security_advisory.ghsa_id,
            dependency:.dependency.package.name,
            url:.html_url
          }
        ][0:20],
        code_scanning_alerts:[
          $code_alerts[] |
          {
            number,
            severity:(.rule.security_severity_level // .rule.severity),
            rule:.rule.id,
            url:.html_url
          }
        ][0:20],
        dependabot_pull_requests:$actionable_prs[0:20]
      }'
  )"
  upsert_signal \
    "P3" \
    "dependencies" \
    "dependency-security:open-maintenance" \
    "[factory signal] Dependency or security maintenance is pending" \
    "$summary" \
    "$evidence" \
    "Prioritize exploitable or failing updates, keep dependency changes minimal, and require the repository's security and regression checks." \
    "signal:dependencies,signal:priority-3" \
    "$(jq -c '{
      dependabot_alerts:([
        .high_or_critical_dependabot_alerts[] |
        {number,severity,advisory,dependency}
      ] | sort_by(.number)),
      code_scanning_alerts:([
        .code_scanning_alerts[] |
        {number,severity,rule}
      ] | sort_by(.number)),
      dependabot_pull_requests:([
        .dependabot_pull_requests[] |
        {number,failed_checks}
      ] | sort_by(.number))
    }' <<<"$evidence")"
  if [ "$alerts_supported" = "true" ] &&
    [ "$code_alerts_supported" = "true" ]; then
    mark_evaluated "dependencies"
  fi
}

collect_production() {
  local runs
  local run
  local conclusion=""
  local failed_run='null'
  local incidents
  local incident_count
  local summary
  local evidence

  runs="$(
    gh run list \
      --repo "$REPOSITORY" \
      --workflow "release-health.yml" \
      --branch "$DEFAULT_BRANCH" \
      --limit 10 \
      --json databaseId,workflowName,status,conclusion,createdAt,updatedAt,url,headSha,event
  )"
  run="$(
    jq -c '[
      .[] |
      select(
        .status == "completed" and
        (
          .conclusion == "success" or
          .conclusion == "failure" or
          .conclusion == "stale" or
          .conclusion == "startup_failure" or
          .conclusion == "timed_out"
        )
      )
    ] | first // empty' <<<"$runs"
  )"
  if [ -n "$run" ]; then
    conclusion="$(jq -r '.conclusion // ""' <<<"$run")"
    if is_failed_conclusion "$conclusion"; then
      failed_run="$run"
    fi
  fi
  incidents="$(
    gh issue list \
      --repo "$REPOSITORY" \
      --state open \
      --label "factory:incident" \
      --limit 100 \
      --json number,title,url,labels,updatedAt |
      jq -c '[
        .[] |
        select(
          ([.labels[].name] | index("factory:signal") | not) and
          (.title | test("production|release|health"; "i"))
        ) |
        {number,title,url,updatedAt}
      ]'
  )"
  incident_count="$(jq 'length' <<<"$incidents")"
  if [ "$failed_run" = "null" ] && [ "$incident_count" -eq 0 ]; then
    mark_evaluated "production"
    return
  fi

  summary="Production evidence includes $incident_count open incident issue(s)"
  if [ "$failed_run" != "null" ]; then
    summary="$summary and a latest health-controller conclusion of \`$conclusion\`."
  else
    summary="$summary; the latest health-controller run is not failing."
  fi
  evidence="$(
    jq -cn \
      --arg source "production-health" \
      --arg health_url_configured "${APP_URL:+true}" \
      --argjson failed_run "$failed_run" \
      --argjson incidents "$incidents" \
      '{
        source:$source,
        production_health_url_configured:($health_url_configured == "true"),
        failed_health_run:$failed_run,
        open_incidents:$incidents
      }'
  )"
  upsert_signal \
    "P1" \
    "production" \
    "production-health:api-health" \
    "[factory signal] Production health requires attention" \
    "$summary" \
    "$evidence" \
    "Protect users first: keep a failed rollout aborted, verify the health endpoint, repair the smallest root cause, and require a successful production probe before closure." \
    "signal:production,signal:priority-1,factory:incident" \
    "$(jq -cn \
      --arg health_failing "$([ "$failed_run" != "null" ] && echo true || echo false)" \
      --argjson incidents "$incidents" \
      '{
        health_failing:($health_failing == "true"),
        incident_numbers:([$incidents[].number] | sort)
      }')"
  mark_evaluated "production"
}

collect_azure_observability() {
  local app_id=""
  local app_http_samples=0
  local app_response_samples=0
  local missing_variables=()
  local postgres_id=""
  local postgres_cpu_samples=0
  local postgres_storage_samples=0
  local metrics
  local queries_ok=true
  local http_5xx=0
  local response_time_ms=0
  local postgres_cpu=0
  local postgres_storage=0
  local state_key
  local summary
  local evidence

  for variable_name in \
    AZURE_CLIENT_ID \
    AZURE_TENANT_ID \
    AZURE_SUBSCRIPTION_ID \
    AZURE_RESOURCE_GROUP \
    AZURE_APP_NAME \
    AZURE_POSTGRES_NAME; do
    if [ -z "${!variable_name:-}" ]; then
      missing_variables+=("$variable_name")
    fi
  done

  if (( ${#missing_variables[@]} > 0 )); then
    evidence="$(
      printf '%s\n' "${missing_variables[@]}" |
        jq -Rsc '
          split("\n")[:-1] as $missing |
          {
            source:"azure-monitor",
            queries_ok:false,
            missing_configuration:$missing
          }
        '
    )"
    upsert_signal \
      "P1" \
      "azure-observability" \
      "azure-observability:production" \
      "[factory signal] Azure production telemetry requires attention" \
      "Azure production telemetry is not fully configured; health is unknown." \
      "$evidence" \
      "Configure the missing GitHub production-environment variables and verify Azure OIDC telemetry access before closure." \
      "signal:production,signal:priority-1,factory:incident" \
      "$(jq -c '{queries_ok,missing_configuration}' <<<"$evidence")"
    mark_evaluated "azure-observability"
    return
  fi

  if ! app_id="$(
    az webapp show \
      --resource-group "$AZURE_RESOURCE_GROUP" \
      --name "$AZURE_APP_NAME" \
      --query id \
      --output tsv
  )"; then
    queries_ok=false
  fi
  if ! postgres_id="$(
    az postgres flexible-server show \
      --resource-group "$AZURE_RESOURCE_GROUP" \
      --name "$AZURE_POSTGRES_NAME" \
      --query id \
      --output tsv
  )"; then
    queries_ok=false
  fi

  if [ -n "$app_id" ]; then
    if metrics="$(
      az monitor metrics list \
        --resource "$app_id" \
        --metric Http5xx AverageResponseTime \
        --interval PT5M \
        --aggregation Total Average \
        --offset 30m \
        --output json
    )"; then
      http_5xx="$(
        jq '[.value[] | select(.name.value == "Http5xx") | .timeseries[].data[].total // 0] | add // 0' \
          <<<"$metrics"
      )"
      response_time_ms="$(
        jq '[.value[] | select(.name.value == "AverageResponseTime") | .timeseries[].data[].average // 0] | max // 0 | . * 1000' \
          <<<"$metrics"
      )"
      app_http_samples="$(
        jq '[.value[] | select(.name.value == "Http5xx") | .timeseries[].data[] | select(.total != null)] | length' \
          <<<"$metrics"
      )"
      app_response_samples="$(
        jq '[.value[] | select(.name.value == "AverageResponseTime") | .timeseries[].data[] | select(.average != null)] | length' \
          <<<"$metrics"
      )"
      if (( app_http_samples == 0 || app_response_samples == 0 )); then
        queries_ok=false
      fi
    else
      queries_ok=false
    fi
  fi

  if [ -n "$postgres_id" ]; then
    if metrics="$(
      az monitor metrics list \
        --resource "$postgres_id" \
        --metric cpu_percent storage_percent \
        --interval PT5M \
        --aggregation Average \
        --offset 30m \
        --output json
    )"; then
      postgres_cpu="$(
        jq '[.value[] | select(.name.value == "cpu_percent") | .timeseries[].data[].average // 0] | max // 0' \
          <<<"$metrics"
      )"
      postgres_storage="$(
        jq '[.value[] | select(.name.value == "storage_percent") | .timeseries[].data[].average // 0] | max // 0' \
          <<<"$metrics"
      )"
      postgres_cpu_samples="$(
        jq '[.value[] | select(.name.value == "cpu_percent") | .timeseries[].data[] | select(.average != null)] | length' \
          <<<"$metrics"
      )"
      postgres_storage_samples="$(
        jq '[.value[] | select(.name.value == "storage_percent") | .timeseries[].data[] | select(.average != null)] | length' \
          <<<"$metrics"
      )"
      if (( postgres_cpu_samples == 0 || postgres_storage_samples == 0 )); then
        queries_ok=false
      fi
    else
      queries_ok=false
    fi
  fi

  if [ "$queries_ok" = true ] &&
    awk "BEGIN { exit !($http_5xx <= 5 && $response_time_ms <= 1200 && $postgres_cpu <= 90 && $postgres_storage <= 80) }"; then
    mark_evaluated "azure-observability"
    return
  fi

  if [ "$queries_ok" = true ]; then
    summary="Azure production metrics exceeded one or more factory thresholds."
  else
    summary="Azure production telemetry could not be collected completely; health is unknown."
  fi
  evidence="$(
    jq -cn \
      --arg app_id "$app_id" \
      --arg postgres_id "$postgres_id" \
      --arg queries_ok "$queries_ok" \
      --argjson http_5xx "$http_5xx" \
      --argjson http_5xx_samples "$app_http_samples" \
      --argjson postgres_cpu "$postgres_cpu" \
      --argjson postgres_cpu_samples "$postgres_cpu_samples" \
      --argjson postgres_storage "$postgres_storage" \
      --argjson postgres_storage_samples "$postgres_storage_samples" \
      --argjson response_time_ms "$response_time_ms" \
      --argjson response_time_samples "$app_response_samples" \
      '{
        source:"azure-monitor",
        queries_ok:($queries_ok == "true"),
        app_service:{
          resource_id:$app_id,
          http_5xx_30m:$http_5xx,
          http_5xx_samples_30m:$http_5xx_samples,
          response_time_samples_30m:$response_time_samples,
          max_response_time_ms_30m:$response_time_ms
        },
        postgresql:{
          resource_id:$postgres_id,
          max_cpu_percent_30m:$postgres_cpu,
          cpu_samples_30m:$postgres_cpu_samples,
          max_storage_percent_30m:$postgres_storage,
          storage_samples_30m:$postgres_storage_samples
        },
        thresholds:{
          http_5xx_max:5,
          response_time_ms_max:1200,
          postgres_cpu_percent_max:90,
          postgres_storage_percent_max:80
        }
      }'
  )"
  state_key="$(jq -c '{queries_ok,app_service,postgresql}' <<<"$evidence")"
  upsert_signal \
    "P1" \
    "azure-observability" \
    "azure-observability:production" \
    "[factory signal] Azure production telemetry requires attention" \
    "$summary" \
    "$evidence" \
    "Protect production first. Verify Azure telemetry access, then repair the smallest application, database, or infrastructure cause and require healthy metrics before closure." \
    "signal:production,signal:priority-1,factory:incident" \
    "$state_key"
  mark_evaluated "azure-observability"
}

collect_azure_budget() {
  local budget_json=""
  local budget_name="meme-forge-production"
  local evidence
  local spend=""
  local state_key
  local summary
  local threshold="${AZURE_MONTHLY_BUDGET_USD:-}"

  if [ -z "${AZURE_SUBSCRIPTION_ID:-}" ] || [ -z "$threshold" ]; then
    evidence="$(
      jq -cn \
        --arg subscription_configured "${AZURE_SUBSCRIPTION_ID:+true}" \
        --arg threshold_configured "${threshold:+true}" \
        '{
          source:"azure-cost-management",
          queries_ok:false,
          subscription_configured:($subscription_configured == "true"),
          threshold_configured:($threshold_configured == "true")
        }'
    )"
    summary="The Azure production budget signal is not fully configured; spend is unknown."
  elif budget_json="$(
    az consumption budget show \
      --budget-name "$budget_name" \
      --output json
  )"; then
    spend="$(jq -r '.currentSpend.amount // .properties.currentSpend.amount // empty' <<<"$budget_json")"
    if [[ "$spend" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
      [[ "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      if awk "BEGIN { exit !($spend <= $threshold) }"; then
        mark_evaluated "azure-budget"
        return
      fi
      evidence="$(
        jq -cn \
          --arg budget_name "$budget_name" \
          --argjson spend "$spend" \
          --argjson threshold "$threshold" \
          '{
            source:"azure-cost-management",
            queries_ok:true,
            budget_name:$budget_name,
            month_to_date_spend_usd:$spend,
            monthly_threshold_usd:$threshold
          }'
      )"
      summary="Azure production month-to-date spend exceeded the configured monthly threshold."
    else
      evidence="$(
        jq -cn \
          --arg budget_name "$budget_name" \
          --arg spend "$spend" \
          --arg threshold "$threshold" \
          '{
            source:"azure-cost-management",
            queries_ok:false,
            budget_name:$budget_name,
            observed_spend:$spend,
            configured_threshold:$threshold
          }'
      )"
      summary="Azure production budget data could not be interpreted; spend is unknown."
    fi
  else
    evidence="$(
      jq -cn \
        --arg budget_name "$budget_name" \
        --arg threshold "$threshold" \
        '{
          source:"azure-cost-management",
          queries_ok:false,
          budget_name:$budget_name,
          configured_threshold:$threshold
        }'
    )"
    summary="Azure production budget data could not be collected; spend is unknown."
  fi

  state_key="$(jq -c '.' <<<"$evidence")"
  upsert_signal \
    "P2" \
    "azure-budget" \
    "azure-budget:production" \
    "[factory signal] Azure production budget requires attention" \
    "$summary" \
    "$evidence" \
    "Verify Cost Management access and the production budget, then reduce or rightsize the smallest safe cost driver before closure." \
    "signal:production,signal:priority-2,factory:incident" \
    "$state_key"
  mark_evaluated "azure-budget"
}

collect_queue_drift() {
  local managed_prs
  local active_issues
  local queued_issues
  local implementer_runs
  local active_pr_count
  local active_issue_count
  local active_run_count
  local stale_queue
  local stale_queue_count
  local reasons
  local reason_count
  local evidence
  local summary

  managed_prs="$(
    gh pr list \
      --repo "$REPOSITORY" \
      --state open \
      --label "factory:managed" \
      --limit 100 \
      --json number,title,url,createdAt,updatedAt
  )"
  active_issues="$(
    gh issue list \
      --repo "$REPOSITORY" \
      --state open \
      --label "factory:active" \
      --limit 100 \
      --json number,title,url,createdAt,updatedAt
  )"
  queued_issues="$(
    gh issue list \
      --repo "$REPOSITORY" \
      --state open \
      --limit 100 \
      --json number,title,url,createdAt,updatedAt,labels |
      jq -c '[
        .[] |
        select(
          ([.labels[].name] | index("factory:ready")) or
          ([.labels[].name] | index("factory:repair"))
        ) |
        select([.labels[].name] | index("factory:active") | not)
      ]'
  )"
  implementer_runs="$(
    gh run list \
      --repo "$REPOSITORY" \
      --workflow "factory-implement.lock.yml" \
      --limit 20 \
      --json databaseId,status,conclusion,createdAt,updatedAt,url
  )"
  active_pr_count="$(jq 'length' <<<"$managed_prs")"
  active_issue_count="$(jq 'length' <<<"$active_issues")"
  active_run_count="$(
    jq '[
      .[] |
      select(
        .status == "queued" or
        .status == "in_progress" or
        .status == "waiting" or
        .status == "requested" or
        .status == "pending"
      )
    ] | length' <<<"$implementer_runs"
  )"
  stale_queue="$(
    jq -c --argjson now "$NOW_EPOCH" '
      [
        .[] |
        . + {age_hours: ((($now - (.updatedAt | fromdateiso8601)) / 3600) | floor)} |
        select(.age_hours >= 24) |
        {number,title,url,updatedAt,age_hours}
      ]
    ' <<<"$queued_issues"
  )"
  stale_queue_count="$(jq 'length' <<<"$stale_queue")"
  reasons="$(
    jq -cn \
      --argjson active_pr_count "$active_pr_count" \
      --argjson active_issue_count "$active_issue_count" \
      --argjson active_run_count "$active_run_count" \
      --argjson stale_queue_count "$stale_queue_count" \
      --argjson wip_limit "$wip_limit" \
      --argjson max_open_prs "$max_open_prs" \
      '[
        if $active_pr_count > $max_open_prs then
          "open managed pull requests exceed policy"
        else empty end,
        if $active_pr_count > $wip_limit then
          "active pull requests exceed WIP"
        else empty end,
        if $active_issue_count > ($active_pr_count + $active_run_count) then
          "active issues are not matched by active runs or pull requests"
        else empty end,
        if $stale_queue_count > 0 and $active_run_count == 0 and $active_pr_count < $wip_limit then
          "ready or repair work has waited at least 24 hours despite capacity"
        else empty end
      ]'
  )"
  reason_count="$(jq 'length' <<<"$reasons")"
  if [ "$reason_count" -eq 0 ]; then
    mark_evaluated "queue"
    return
  fi

  summary="Factory queue state violates $(jq -r 'join(", ")' <<<"$reasons")."
  evidence="$(
    jq -cn \
      --arg source "factory-queue" \
      --argjson policy "$(jq -cn \
        --argjson wip "$wip_limit" \
        --argjson attempts "$max_attempts" \
        --argjson prs "$max_open_prs" \
        '{work_in_progress_limit:$wip,max_attempts_per_issue:$attempts,max_open_factory_pull_requests:$prs}')" \
      --argjson reasons "$reasons" \
      --argjson managed_prs "$managed_prs" \
      --argjson active_issues "$active_issues" \
      --argjson active_run_count "$active_run_count" \
      --argjson stale_queue "$stale_queue" \
      '{
        source:$source,
        policy:$policy,
        reasons:$reasons,
        open_managed_pull_requests:$managed_prs,
        active_issues:$active_issues,
        active_implementer_runs:$active_run_count,
        stale_ready_or_repair_issues:$stale_queue
      }'
  )"
  upsert_signal \
    "P2" \
    "queue" \
    "factory-queue:drift" \
    "[factory signal] Factory queue drift requires reconciliation" \
    "$summary" \
    "$evidence" \
    "Reconcile labels, runs, and linked pull requests without raising WIP, retry, or AI budgets." \
    "signal:queue,signal:priority-2,factory:incident" \
    "$(jq -c '{
      reasons,
      open_managed_pull_requests:([.open_managed_pull_requests[].number] | sort),
      active_issues:([.active_issues[].number] | sort),
      active_implementer_runs,
      stale_ready_or_repair_issues:([.stale_ready_or_repair_issues[].number] | sort)
    }' <<<"$evidence")"
  mark_evaluated "queue"
}

close_cleared_signals() {
  local issue
  local number
  local body
  local fingerprint
  local category

  while IFS= read -r issue; do
    number="$(jq -r '.number' <<<"$issue")"
    body="$(jq -r '.body // ""' <<<"$issue")"
    fingerprint="$(
      sed -n 's/.*<!-- factory-signal:\([^>]*\) -->.*/\1/p' <<<"$body" |
        head -n 1
    )"
    category="$(
      sed -n 's/.*<!-- factory-signal-category:\([^>]*\) -->.*/\1/p' <<<"$body" |
        head -n 1
    )"
    [ -n "$fingerprint" ] && [ -n "$category" ] || continue
    if [ "$fingerprint" = "production-release:autonomous-controller" ]; then
      continue
    fi
    grep -Fxq "$category" "$evaluated_categories" || continue
    if grep -Fqx "$category"$'\t'"$fingerprint" "$active_signals"; then
      continue
    fi
    if [ "$DRY_RUN" = "1" ]; then
      echo "[dry-run] close cleared signal #$number: $fingerprint"
    else
      gh issue close "$number" --repo "$REPOSITORY" --reason completed
      echo "Closed cleared signal issue #$number: $fingerprint"
    fi
  done < <(jq -c '.[] | select(.state == "open")' "$issues_cache")
}

collect_main_checks
collect_factory_workflows
collect_dependency_security
collect_production
collect_azure_observability
collect_azure_budget
collect_queue_drift
close_cleared_signals
