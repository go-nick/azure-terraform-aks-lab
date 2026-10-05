#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: ./scripts/new-project.sh <new-project-name>"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/n8n-hello"
DEST="$REPO_ROOT/$1"

if [ -d "$DEST" ]; then
  echo "Error: $DEST already exists"
  exit 1
fi

rsync -av \
  --exclude='.terraform/' \
  --exclude='.terraform.lock.hcl' \
  --exclude='terraform.tfstate' \
  --exclude='terraform.tfstate.*' \
  --exclude='.env' \
  "$SRC/" "$DEST/"

echo
echo "Created ./$1 from n8n-hello template."
echo "Next steps:"
echo "  1. cd $1"
echo "  2. Edit main.tf - names, dns_prefix, etc. are all still copied from n8n-hello"
echo "  3. cp .env.example .env, then fill in real values"
echo "  4. Update README.md"
echo "  5. Add a line for '$1' to the root README.md project list"
