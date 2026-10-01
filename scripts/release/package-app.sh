#!/usr/bin/env bash
set -euo pipefail

: "${RELEASE_SHA:?RELEASE_SHA is required}"

release_dir=".release"
package_dir="$release_dir/package"
archive="$release_dir/meme-sticker-store-${RELEASE_SHA}.zip"

rm -rf "$release_dir"
mkdir -p "$package_dir/.next"

RELEASE_SHA="$RELEASE_SHA" npm run build
cp -R .next/standalone/. "$package_dir/"
cp -R .next/static "$package_dir/.next/static"
cp -R public "$package_dir/public"
cp -R prisma "$package_dir/prisma"

if command -v zip >/dev/null 2>&1; then
  (
    cd "$package_dir"
    zip -qr "../$(basename "$archive")" .
  )
else
  tar -a -cf "$archive" -C "$package_dir" .
fi

test -s "$archive"
test -f "$package_dir/server.js"
test -d "$package_dir/.next/static"
test -d "$package_dir/prisma/migrations"

printf '%s\n' "$archive"
