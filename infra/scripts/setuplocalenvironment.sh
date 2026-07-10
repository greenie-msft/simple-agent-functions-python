#!/usr/bin/env bash
set -euo pipefail

# azd postprovision hook entry point. Runs after `azd provision` / `azd up` to
# prepare the local development environment. Add more setup steps here as needed.

"$(dirname "$0")/createlocalsettings.sh"
