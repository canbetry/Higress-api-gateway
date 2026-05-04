#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_ROOT="${HIGRESS_DEV_RUNTIME_DIR:-${PROJECT_DIR}/.runtime/develop}"
RUNTIME_COMPOSE="${RUNTIME_ROOT}/compose"
SOURCE_COMPOSE="${PROJECT_DIR}/compose"

source "${SCRIPT_DIR}/docker-env.sh"

mkdir -p "${RUNTIME_COMPOSE}"
rsync -a --delete \
  --exclude '.env' \
  --exclude '.configured' \
  --exclude 'volumes' \
  "${SOURCE_COMPOSE}/" \
  "${RUNTIME_COMPOSE}/"

if [[ ! -f "${RUNTIME_COMPOSE}/.env" ]]; then
  if [[ ! -f "${SOURCE_COMPOSE}/.env" ]]; then
    echo "缺少 ${SOURCE_COMPOSE}/.env，请先运行发布栈的 ./scripts/dev-up.sh 完成初始化。" >&2
    exit 1
  fi
  cp "${SOURCE_COMPOSE}/.env" "${RUNTIME_COMPOSE}/.env"
  perl -0pi -e "s/^NACOS_CONSOLE_PORT='[^']*'/NACOS_CONSOLE_PORT='18888'/m" "${RUNTIME_COMPOSE}/.env"
  perl -0pi -e "s/^NACOS_HTTP_PORT='[^']*'/NACOS_HTTP_PORT='18848'/m" "${RUNTIME_COMPOSE}/.env"
  perl -0pi -e "s/^NACOS_GRPC_PORT='[^']*'/NACOS_GRPC_PORT='19848'/m" "${RUNTIME_COMPOSE}/.env"
  perl -0pi -e "s/^GATEWAY_HTTP_PORT='[^']*'/GATEWAY_HTTP_PORT='18082'/m" "${RUNTIME_COMPOSE}/.env"
  perl -0pi -e "s/^GATEWAY_HTTPS_PORT='[^']*'/GATEWAY_HTTPS_PORT='18443'/m" "${RUNTIME_COMPOSE}/.env"
  perl -0pi -e "s/^GATEWAY_METRICS_PORT='[^']*'/GATEWAY_METRICS_PORT='15030'/m" "${RUNTIME_COMPOSE}/.env"
  perl -0pi -e "s/^CONSOLE_PORT='[^']*'/CONSOLE_PORT='18084'/m" "${RUNTIME_COMPOSE}/.env"
fi

if [[ ! -d "${RUNTIME_COMPOSE}/volumes" ]]; then
  if [[ -d "${SOURCE_COMPOSE}/volumes" ]]; then
    cp -R "${SOURCE_COMPOSE}/volumes" "${RUNTIME_COMPOSE}/volumes"
  else
    mkdir -p "${RUNTIME_COMPOSE}/volumes"
  fi
fi

if [[ ! -f "${RUNTIME_COMPOSE}/.configured" && -f "${SOURCE_COMPOSE}/.configured" ]]; then
  cp "${SOURCE_COMPOSE}/.configured" "${RUNTIME_COMPOSE}/.configured"
fi

if [[ ! -f "${RUNTIME_COMPOSE}/.configured" ]]; then
  echo "缺少 develop Higress 初始化标记，无法安全启动独立网关。" >&2
  exit 1
fi

HIGRESS_COMPOSE_ROOT="${RUNTIME_COMPOSE}" \
HIGRESS_COMPOSE_PROJECT="${HIGRESS_DEV_PROJECT:-higress-dev}" \
  "${PROJECT_DIR}/bin/startup.sh"

API_SERVER_CONTAINER="${HIGRESS_DEV_PROJECT:-higress-dev}-apiserver-1" \
LOCAL_SSO_HOST="${HIGRESS_DEV_SSO_HOST:-sso-dev.localhost}" \
LOCAL_SSO_API_HOST="${HIGRESS_DEV_SSO_API_HOST:-sso-api-dev.localhost}" \
LOCAL_IMAGE_HOST="${HIGRESS_DEV_IMAGE_HOST:-img-dev.localhost}" \
SSO_WEB_SERVICE_NAME="user-system-web-dev" \
SSO_API_SERVICE_NAME="user-system-api-dev" \
AI_IMAGE_SERVICE_NAME="ai-image-studio-dev" \
SSO_WEB_PORT="${SSO_DEV_WEB_PORT:-5273}" \
SSO_API_PORT="${SSO_DEV_API_PORT:-4100}" \
AI_IMAGE_PORT="${AI_IMAGE_DEV_APP_PORT:-3108}" \
GATEWAY_HTTP_PORT="18082" \
  "${PROJECT_DIR}/scripts/configure-ai-image-routes.sh"

echo ""
echo "Higress develop Gateway: http://localhost:18082"
echo "Higress develop Console: http://localhost:18084"
echo "SSO develop via Gateway: http://sso-dev.localhost:18082"
echo "Image Gen develop via Gateway: http://img-dev.localhost:18082/image"
