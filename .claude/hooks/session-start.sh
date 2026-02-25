#!/bin/bash
# Session start hook: authenticates gh CLI using a stored GitHub token.
#
# Setup (one-time, per machine):
#   echo "ghp_YOUR_PERSONAL_ACCESS_TOKEN" > /home/user/neco/.github_token
#   chmod 600 /home/user/neco/.github_token
#
# The .github_token file is gitignored and never committed.

set -euo pipefail

TOKEN_FILE="${CLAUDE_PROJECT_DIR:-/home/user/neco}/.github_token"

# Only run in remote (web) sessions
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Already authenticated — nothing to do
if gh auth status >/dev/null 2>&1; then
  exit 0
fi

# Read token from file
if [ ! -f "$TOKEN_FILE" ]; then
  echo "[session-start] .github_token not found — gh will not be authenticated." >&2
  echo "[session-start] Create $TOKEN_FILE with your GitHub PAT to enable gh pr create / gh pr merge." >&2
  exit 0
fi

TOKEN=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
if [ -z "$TOKEN" ]; then
  echo "[session-start] .github_token is empty — skipping gh auth." >&2
  exit 0
fi

# Export for the session so gh picks it up without needing hosts.yml
echo "GH_TOKEN=$TOKEN" >> "${CLAUDE_ENV_FILE:-/dev/null}"

# Also log in interactively so 'gh auth status' shows as logged in
echo "$TOKEN" | gh auth login --with-token --git-protocol https 2>&1

echo "[session-start] gh authenticated successfully."
