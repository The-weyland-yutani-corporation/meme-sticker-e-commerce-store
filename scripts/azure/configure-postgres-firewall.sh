#!/usr/bin/env bash
set -euo pipefail

# Retained only for break-glass rollback to a public PostgreSQL network model.
: "${AZURE_APP_NAME:?AZURE_APP_NAME is required}"
: "${AZURE_POSTGRES_NAME:?AZURE_POSTGRES_NAME is required}"
: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is required}"

public_access="$(
  az postgres flexible-server show \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AZURE_POSTGRES_NAME" \
    --query "network.publicNetworkAccess" \
    --output tsv
)"
if [ "$public_access" = "Disabled" ]; then
  echo "PostgreSQL public access is disabled; private networking is authoritative."
  exit 0
fi

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
filtered_ips=()
for ip_address in "${current_ips[@]}"; do
  ip_address="${ip_address//$'\r'/}"
  [ -n "$ip_address" ] && filtered_ips+=("$ip_address")
done
current_ips=("${filtered_ips[@]}")

desired_rules="$(mktemp)"
existing_rules="$(mktemp)"
trap 'rm -f "$desired_rules" "$existing_rules"' EXIT

az postgres flexible-server firewall-rule list \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_POSTGRES_NAME" \
  --output json >"$existing_rules"

for index in "${!current_ips[@]}"; do
  ip_address="${current_ips[$index]}"
  rule_name="app-${index}"
  printf '%s\n' "$rule_name" >>"$desired_rules"
  if jq -e \
    --arg name "$rule_name" \
    --arg ip "$ip_address" \
    '.[] | select(.name == $name and .startIpAddress == $ip and .endIpAddress == $ip)' \
    "$existing_rules" >/dev/null; then
    continue
  fi
  az postgres flexible-server firewall-rule create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AZURE_POSTGRES_NAME" \
    --rule-name "$rule_name" \
    --start-ip-address "$ip_address" \
    --end-ip-address "$ip_address" \
    --output none
done

while IFS= read -r rule_name; do
  rule_name="${rule_name//$'\r'/}"
  [ -n "$rule_name" ] || continue
  if ! grep -Fxq "$rule_name" "$desired_rules"; then
    az postgres flexible-server firewall-rule delete \
      --resource-group "$AZURE_RESOURCE_GROUP" \
      --name "$AZURE_POSTGRES_NAME" \
      --rule-name "$rule_name" \
      --yes \
      --output none
  fi
done < <(jq -r '.[] | select(.name | startswith("app-")) | .name' "$existing_rules")

echo "PostgreSQL firewall matches the App Service outbound addresses."
