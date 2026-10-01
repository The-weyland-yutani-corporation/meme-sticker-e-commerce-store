#!/usr/bin/env bash

set -euo pipefail

environment_name="${1:?usage: validate-config.sh <staging|production>}"

required_variables=(
  APP_URL
  DATABASE_URL
  STRIPE_SECRET_KEY
  STRIPE_WEBHOOK_SECRET
  VERCEL_ORG_ID
  VERCEL_PROJECT_ID
  VERCEL_TOKEN
)

missing=()
for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    missing+=("$variable_name")
  fi
done

if (( ${#missing[@]} > 0 )); then
  printf 'Missing required %s release configuration: %s\n' \
    "$environment_name" "${missing[*]}" >&2
  exit 1
fi

if [[ "$APP_URL" != https://* ]]; then
  echo "APP_URL must use HTTPS." >&2
  exit 1
fi

if [[ "$DATABASE_URL" != postgres://* && "$DATABASE_URL" != postgresql://* ]]; then
  echo "DATABASE_URL must be a PostgreSQL connection URL." >&2
  exit 1
fi

if [[ "$VERCEL_PROJECT_ID" != prj_* ]]; then
  echo "VERCEL_PROJECT_ID must be a Vercel project ID." >&2
  exit 1
fi

if [[ "$VERCEL_ORG_ID" != team_* && "$VERCEL_ORG_ID" != user_* ]]; then
  echo "VERCEL_ORG_ID must be a Vercel team or user ID." >&2
  exit 1
fi

if [[ "$STRIPE_WEBHOOK_SECRET" != whsec_* ]]; then
  echo "STRIPE_WEBHOOK_SECRET must be a Stripe webhook signing secret." >&2
  exit 1
fi

if [[ "$environment_name" == "staging" && "$STRIPE_SECRET_KEY" != sk_test_* ]]; then
  echo "Staging must use a Stripe test-mode secret key." >&2
  exit 1
fi

if [[ "$environment_name" == "production" &&
  "$STRIPE_SECRET_KEY" != sk_test_* &&
  "$STRIPE_SECRET_KEY" != sk_live_* ]]; then
  echo "Production STRIPE_SECRET_KEY must be a Stripe secret key." >&2
  exit 1
fi

echo "$environment_name release configuration is present and structurally valid."
