#!/usr/bin/env bash

set -euo pipefail

base_sha="${1:-}"
target_sha="${2:?usage: check-migrations.sh [base-sha] <target-sha>}"

if [[ -n "$base_sha" ]]; then
  git cat-file -e "${base_sha}^{commit}"
  migration_changes="$(
    git diff --name-status "$base_sha" "$target_sha" -- \
      'prisma/migrations/*/migration.sql'
  )"

  if grep -Eq '^(M|D|R|C)[[:space:]]' <<<"$migration_changes"; then
    echo "Previously deployed migration files are immutable." >&2
    echo "$migration_changes" >&2
    exit 1
  fi

  mapfile -t migration_files < <(
    awk '$1 == "A" { print $2 }' <<<"$migration_changes"
  )
else
  mapfile -t migration_files < <(
    git ls-tree -r --name-only "$target_sha" -- \
      'prisma/migrations/*/migration.sql'
  )
fi

if (( ${#migration_files[@]} == 0 )); then
  echo "No new database migrations require release review."
  exit 0
fi

combined_sql="$(
  for migration_file in "${migration_files[@]}"; do
    git show "${target_sha}:${migration_file}"
  done |
    sed -E '/^[[:space:]]*--/d' |
    tr '\n' ' '
)"

destructive_pattern='(DROP[[:space:]]+(TABLE|COLUMN|TYPE|SCHEMA|INDEX|CONSTRAINT)|TRUNCATE([[:space:]]+TABLE)?|DELETE[[:space:]]+FROM|ALTER[[:space:]]+TABLE[^;]*(RENAME|ALTER[[:space:]]+COLUMN[^;]*TYPE)|ALTER[[:space:]]+TYPE[^;]*(RENAME|DROP))'

if grep -Eiq "$destructive_pattern" <<<"$combined_sql"; then
  echo "Release blocked: new migrations contain destructive or rollback-unsafe SQL." >&2
  printf '%s\n' "${migration_files[@]}" >&2
  echo "Use an additive expand/migrate/contract sequence in separate releases." >&2
  exit 1
fi

printf 'Migration safety check passed for:\n'
printf '  %s\n' "${migration_files[@]}"
