#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

export DOCKER_CONFIG="${PROJECT_DIR}/.docker-tmp"

mkdir -p "${DOCKER_CONFIG}/cli-plugins"

if [[ -d "${HOME}/.docker/contexts" && ! -e "${DOCKER_CONFIG}/contexts" ]]; then
  ln -s "${HOME}/.docker/contexts" "${DOCKER_CONFIG}/contexts"
fi

if [[ -x "${HOME}/.docker/cli-plugins/docker-compose" && ! -e "${DOCKER_CONFIG}/cli-plugins/docker-compose" ]]; then
  ln -s "${HOME}/.docker/cli-plugins/docker-compose" "${DOCKER_CONFIG}/cli-plugins/docker-compose"
fi
