#!/bin/bash
# Session start hook: sets GH_TOKEN from .github_token so gh CLI works.
#
# Setup (one-time, per machine):
#   echo "ghp_YOUR_PERSONAL_ACCESS_TOKEN" > /home/user/neco/.github_token
#   chmod 600 /home/user/neco/.github_token
#
# The .github_token file is gitignored and never committed.
# Only 'repo' scope is required — 'read:org' is not needed.

set -euo pipefail

TOKEN_FILE="${CLAUDE_PROJECT_DIR:-/home/user/neco}/.github_token"

# Only run in remote (web) sessions
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Already authenticated — nothing to do
if GH_TOKEN="${GH_TOKEN:-}" gh auth status >/dev/null 2>&1 && [ -n "${GH_TOKEN:-}" ]; then
  exit 0
fi

# Read token from file
if [ ! -f "$TOKEN_FILE" ]; then
  echo "[session-start] .github_token not found — gh will not be authenticated." >&2
  echo "[session-start] Create $TOKEN_FILE with your GitHub PAT (repo scope) to enable gh pr create / gh pr merge." >&2
  exit 0
fi

TOKEN=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
if [ -z "$TOKEN" ]; then
  echo "[session-start] .github_token is empty — skipping gh auth." >&2
  exit 0
fi

# Export GH_TOKEN for the entire session via CLAUDE_ENV_FILE
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "GH_TOKEN=$TOKEN" >> "$CLAUDE_ENV_FILE"
fi
export GH_TOKEN="$TOKEN"

echo "[session-start] GH_TOKEN set — gh pr create / gh pr merge are ready."
