#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_ROOT="${HIGRESS_DEV_RUNTIME_DIR:-${PROJECT_DIR}/.runtime/develop}"
RUNTIME_COMPOSE="${RUNTIME_ROOT}/compose"

source "${SCRIPT_DIR}/docker-env.sh"

if [[ ! -d "${RUNTIME_COMPOSE}" ]]; then
  echo "Higress develop runtime 不存在，无需停止。"
  exit 0
fi

HIGRESS_COMPOSE_ROOT="${RUNTIME_COMPOSE}" \
HIGRESS_COMPOSE_PROJECT="${HIGRESS_DEV_PROJECT:-higress-dev}" \
  "${PROJECT_DIR}/bin/shutdown.sh"
