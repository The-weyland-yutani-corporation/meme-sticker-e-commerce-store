#!/usr/bin/env bash

set -euo pipefail

app_url="${1:?usage: probe-release.sh <app-url>}"
app_url="${app_url%/}"
health_response="$(mktemp)"
home_response="$(mktemp)"
synthetic_response="$(mktemp)"
trap 'rm -f "$health_response" "$home_response" "$synthetic_response"' EXIT
probe_attempts="${PROBE_ATTEMPTS:-5}"
probe_interval_seconds="${PROBE_INTERVAL_SECONDS:-10}"

probe_url() {
  local url="$1"
  local output_file="$2"
  local curl_arguments=(
    --fail
    --silent
    --show-error
    --location
    --max-time 15
  )

  for ((attempt = 1; attempt <= probe_attempts; attempt += 1)); do
    if curl "${curl_arguments[@]}" "$url" >"$output_file"; then
      return 0
    fi
    if (( attempt < probe_attempts )); then
      sleep "$probe_interval_seconds"
    fi
  done

  return 1
}

probe_health() {
  local curl_arguments=(
    --fail
    --silent
    --show-error
    --location
    --max-time 15
  )

  for ((attempt = 1; attempt <= probe_attempts; attempt += 1)); do
    if curl "${curl_arguments[@]}" "${app_url}/api/health" >"$health_response" &&
      jq -e '
        .status == "ok" and
        .service == "meme-sticker-store" and
        .version == env.EXPECTED_RELEASE_SHA
      ' "$health_response" >/dev/null; then
      return 0
    fi
    if (( attempt < probe_attempts )); then
      sleep "$probe_interval_seconds"
    fi
  done

  return 1
}

probe_health

probe_url "${app_url}/" "$home_response"
grep -Eiq '<(html|body)([[:space:]>])' "$home_response"

: "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?GitHub OIDC request token is required}"
: "${ACTIONS_ID_TOKEN_REQUEST_URL:?GitHub OIDC request URL is required}"
oidc_token="$(
  curl \
    --fail \
    --silent \
    --show-error \
    --header "authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=meme-forge-synthetic-order" |
    jq -er '.value'
)"
echo "::add-mask::$oidc_token"

curl \
  --fail \
  --silent \
  --show-error \
  --request POST \
  --header "authorization: Bearer ${oidc_token}" \
  --max-time 30 \
  "${app_url}/api/internal/synthetic-order" >"$synthetic_response"
jq -e '
  .status == "ok" and
  .deleted == true and
  (.amountTotal | type == "number" and . > 0)
' "$synthetic_response" >/dev/null

echo "Health, storefront, database, and synthetic-order probes passed for $app_url."
