#!/usr/bin/env bash
set -euo pipefail

node node_modules/prisma/build/index.js migrate deploy
node server.js &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
node verify-startup.mjs
trap - EXIT
wait "$server_pid"
