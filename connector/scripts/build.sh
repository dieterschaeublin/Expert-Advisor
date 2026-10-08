#!/usr/bin/env bash
# Baut dist/metatrader4-connector.mcpb (nur Laufzeit-Abhaengigkeiten, EAs mitgeliefert).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -R "$here/server" "$here/manifest.json" "$here/package.json" "$stage/"
[ -f "$here/package-lock.json" ] && cp "$here/package-lock.json" "$stage/"
mkdir -p "$stage/ea"
cp "$here/../MQL4/Experts/"*.mq4 "$stage/ea/"
(cd "$stage" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund >/dev/null)

mkdir -p "$here/../dist"
"$here/node_modules/.bin/mcpb" validate "$stage/manifest.json"
"$here/node_modules/.bin/mcpb" pack "$stage" "$here/../dist/metatrader4-connector.mcpb"
