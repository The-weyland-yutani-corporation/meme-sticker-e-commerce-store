#!/usr/bin/env bash

set -euo pipefail

app_url="${1:?usage: probe-release.sh <app-url>}"
app_url="${app_url%/}"
health_response="$(mktemp)"
home_response="$(mktemp)"
trap 'rm -f "$health_response" "$home_response"' EXIT

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

  for attempt in 1 2 3 4 5; do
    if curl "${curl_arguments[@]}" "$url" >"$output_file"; then
      return 0
    fi
    if (( attempt < 5 )); then
      sleep 10
    fi
  done

  return 1
}

probe_url "${app_url}/api/health" "$health_response"
jq -e '
  .status == "ok" and
  .service == "meme-sticker-store" and
  .version == env.EXPECTED_RELEASE_SHA
' "$health_response" >/dev/null

probe_url "${app_url}/" "$home_response"
grep -Eiq '<(html|body)([[:space:]>])' "$home_response"

echo "Health, storefront, and database probes passed for $app_url."
