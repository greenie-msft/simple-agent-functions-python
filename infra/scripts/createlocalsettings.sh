#!/usr/bin/env bash
set -euo pipefail

# Writes src/local.settings.json from the current azd environment so the
# function app can run locally with `uv run func start`. An existing file is
# left untouched so your local edits are never overwritten.

cd "$(dirname "$0")/../.." # repo root (infra/scripts -> repo root)
SETTINGS_FILE="src/local.settings.json"

if [ -f "$SETTINGS_FILE" ]; then
  echo "$SETTINGS_FILE already exists; leaving it unchanged."
  exit 0
fi

if ! command -v azd >/dev/null 2>&1; then
  echo "azd not found; skipping $SETTINGS_FILE generation." >&2
  exit 0
fi

values="$(azd env get-values 2>/dev/null || true)"
get() { printf '%s\n' "$values" | grep "^$1=" | head -n1 | cut -d'=' -f2- | tr -d '"'; }

FOUNDRY_PROJECT_ENDPOINT="$(get FOUNDRY_PROJECT_ENDPOINT)"
FOUNDRY_MODEL="$(get FOUNDRY_MODEL)"
GITHUB_REPOSITORY="$(get GITHUB_REPOSITORY)"

: "${FOUNDRY_MODEL:=gpt-5-mini}"
: "${GITHUB_REPOSITORY:=Azure/azure-functions-host}"

cat >"$SETTINGS_FILE" <<JSON
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "AZURE_FUNCTIONS_AGENTS_PROVIDER": "foundry",
    "FOUNDRY_PROJECT_ENDPOINT": "${FOUNDRY_PROJECT_ENDPOINT}",
    "FOUNDRY_MODEL": "${FOUNDRY_MODEL}",
    "GITHUB_REPOSITORY": "${GITHUB_REPOSITORY}"
  }
}
JSON

echo "Wrote $SETTINGS_FILE (FOUNDRY_MODEL=${FOUNDRY_MODEL}, GITHUB_REPOSITORY=${GITHUB_REPOSITORY})."
