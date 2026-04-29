#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/docker-env.sh"

"${PROJECT_DIR}/bin/startup.sh"

echo ""
echo "Higress Gateway: http://localhost:8082"
echo "Higress Gateway HTTPS: https://localhost:8443"
echo "Higress Console: http://localhost:8084"
