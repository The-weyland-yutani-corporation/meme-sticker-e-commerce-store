#!/usr/bin/env bash
set -euo pipefail

az bicep build --file infra/main.bicep --stdout >/dev/null
az bicep build --file infra/preflight.bicep --stdout >/dev/null

if grep -RInE \
  --exclude='validate-bicep.sh' \
  'client_secret|publish[_ -]?profile|AZURE_CREDENTIALS' \
  infra scripts/azure; then
  echo "Long-lived Azure credential pattern found in infrastructure files." >&2
  exit 1
fi

echo "Azure Bicep and credential policy validation passed."
