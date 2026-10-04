#!/usr/bin/env bash
set -euo pipefail

node node_modules/prisma/build/index.js migrate deploy
exec node server.js
