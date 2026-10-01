#!/usr/bin/env bash
set -euo pipefail

: "${AZURE_APP_NAME:?AZURE_APP_NAME is required}"
: "${AZURE_POSTGRES_NAME:?AZURE_POSTGRES_NAME is required}"
: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is required}"

outbound_ips="$(
  az webapp show \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AZURE_APP_NAME" \
    --query "possibleOutboundIpAddresses || outboundIpAddresses" \
    --output tsv
)"
[ -n "$outbound_ips" ] || {
  echo "App Service did not report any outbound addresses." >&2
  exit 1
}
IFS=',' read -r -a current_ips <<<"$outbound_ips"

desired_rules="$(mktemp)"
existing_rules="$(mktemp)"
trap 'rm -f "$desired_rules" "$existing_rules"' EXIT

for index in "${!current_ips[@]}"; do
  ip_address="${current_ips[$index]}"
  rule_name="app-${index}"
  printf '%s\n' "$rule_name" >>"$desired_rules"
  az postgres flexible-server firewall-rule create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AZURE_POSTGRES_NAME" \
    --rule-name "$rule_name" \
    --start-ip-address "$ip_address" \
    --end-ip-address "$ip_address" \
    --output none
done

az postgres flexible-server firewall-rule list \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_POSTGRES_NAME" \
  --query "[?starts_with(name, 'app-')].name" \
  --output tsv >"$existing_rules"

while IFS= read -r rule_name; do
  [ -n "$rule_name" ] || continue
  if ! grep -Fxq "$rule_name" "$desired_rules"; then
    az postgres flexible-server firewall-rule delete \
      --resource-group "$AZURE_RESOURCE_GROUP" \
      --name "$AZURE_POSTGRES_NAME" \
      --rule-name "$rule_name" \
      --yes \
      --output none
  fi
done <"$existing_rules"

echo "PostgreSQL firewall matches the App Service outbound addresses."
