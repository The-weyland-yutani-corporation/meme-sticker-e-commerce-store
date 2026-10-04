#!/usr/bin/env bash

set -euo pipefail

environment_name="${1:?usage: validate-config.sh <production>}"

required_variables=(
  APP_URL
  AZURE_APP_NAME
  AZURE_CLIENT_ID
  AZURE_KEY_VAULT_NAME
  AZURE_LOCATION
  AZURE_NAME_PREFIX
  AZURE_POSTGRES_NAME
  AZURE_PRINCIPAL_OBJECT_ID
  AZURE_RELEASE_CONTAINER
  AZURE_RESOURCE_GROUP
  AZURE_STORAGE_ACCOUNT
  AZURE_SUBSCRIPTION_ID
  AZURE_TENANT_ID
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

if [[ "$environment_name" != "production" ]]; then
  echo "Only the production Azure environment is supported." >&2
  exit 1
fi

echo "$environment_name release configuration is present and structurally valid."
