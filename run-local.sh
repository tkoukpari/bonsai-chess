#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "Building frontend bundle (release profile)..."
if ! opam list --installed --short | grep -qx "bonsai"; then
  echo "Installing project dependencies into current opam switch..."
  opam install -y . --deps-only
fi

opam exec -- dune build --profile release web/app.js

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "Error: DATABASE_URL is not set."
  echo "Example:"
  echo "  export DATABASE_URL='postgresql://user:pass@localhost:5432/bonsai_chess'"
  exit 1
fi

echo "Starting local server..."
exec opam exec -- dune exec bin/main.exe
