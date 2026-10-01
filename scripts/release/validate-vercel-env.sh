#!/usr/bin/env bash

set -euo pipefail

environment_name="${1:?usage: validate-vercel-env.sh <environment>}"
environment_file=".vercel/.env.${environment_name}.local"

if [[ ! -f "$environment_file" ]]; then
  echo "Vercel did not provide $environment_file." >&2
  exit 1
fi

required_variables=(
  APP_URL
  DATABASE_URL
  STRIPE_SECRET_KEY
  STRIPE_WEBHOOK_SECRET
)

missing=()
for variable_name in "${required_variables[@]}"; do
  value="$(
    sed -n "s/^${variable_name}=//p" "$environment_file" |
      tail -n 1
  )"
  if [[ -z "$value" || "$value" == '""' || "$value" == "''" ]]; then
    missing+=("$variable_name")
  fi
done

if (( ${#missing[@]} > 0 )); then
  printf 'Missing required Vercel %s variables: %s\n' \
    "$environment_name" "${missing[*]}" >&2
  exit 1
fi

echo "Vercel $environment_name runtime configuration contains all required keys."
