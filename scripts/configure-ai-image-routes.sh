#!/usr/bin/env bash
set -euo pipefail

API_SERVER_CONTAINER="${API_SERVER_CONTAINER:-higress-apiserver-1}"
API_SERVER_URL="${API_SERVER_URL:-https://127.0.0.1:8443}"
NAMESPACE="${NAMESPACE:-higress-system}"
LOCAL_SSO_HOST="${LOCAL_SSO_HOST:-sso.localhost}"
LOCAL_SSO_API_HOST="${LOCAL_SSO_API_HOST:-sso-api.localhost}"
LOCAL_IMAGE_HOST="${LOCAL_IMAGE_HOST:-image.localhost}"
SSO_WEB_PORT="${SSO_WEB_PORT:-5173}"
SSO_API_PORT="${SSO_API_PORT:-4000}"
AI_IMAGE_PORT="${AI_IMAGE_PORT:-3008}"
GATEWAY_HTTP_PORT="${GATEWAY_HTTP_PORT:-8082}"
SSO_WEB_SERVICE_NAME="${SSO_WEB_SERVICE_NAME:-user-system-web}"
SSO_API_SERVICE_NAME="${SSO_API_SERVICE_NAME:-user-system-api}"
AI_IMAGE_SERVICE_NAME="${AI_IMAGE_SERVICE_NAME:-ai-image-studio}"
PUBLIC_SSO_HOST="${PUBLIC_SSO_HOST:-}"
PUBLIC_SSO_API_HOST="${PUBLIC_SSO_API_HOST:-}"
PUBLIC_IMAGE_HOST="${PUBLIC_IMAGE_HOST:-}"

resource_url() {
  local namespace="$1"
  local group_version="$2"
  local resource_type="$3"
  local resource_name="${4:-}"
  local uri_prefix="/api"

  if [[ "${group_version}" == *"/"* ]]; then
    uri_prefix="/apis"
  fi

  if [[ -z "${namespace}" ]]; then
    printf '%s%s/%s/%s' "${API_SERVER_URL}" "${uri_prefix}" "${group_version}" "${resource_type}"
  else
    printf '%s%s/%s/namespaces/%s/%s' "${API_SERVER_URL}" "${uri_prefix}" "${group_version}" "${namespace}" "${resource_type}"
  fi

  if [[ -n "${resource_name}" ]]; then
    printf '/%s' "${resource_name}"
  fi
}

delete_resource() {
  local namespace="$1"
  local group_version="$2"
  local resource_type="$3"
  local resource_name="$4"
  local url
  local status

  url="$(resource_url "${namespace}" "${group_version}" "${resource_type}" "${resource_name}")"
  status="$(docker exec "${API_SERVER_CONTAINER}" sh -lc "curl -sk -o /dev/null -w '%{http_code}' -X DELETE '${url}'")"
  case "${status}" in
    200|202|404) ;;
    *)
      echo "FAIL delete ${resource_type}/${resource_name}: HTTP ${status}" >&2
      exit 1
      ;;
  esac
}

apply_resource() {
  local namespace="$1"
  local group_version="$2"
  local resource_type="$3"
  local resource_name="$4"
  local url
  local status

  delete_resource "${namespace}" "${group_version}" "${resource_type}" "${resource_name}"
  url="$(resource_url "${namespace}" "${group_version}" "${resource_type}")"
  status="$(
    docker exec -i "${API_SERVER_CONTAINER}" sh -lc "
      tmp=\$(mktemp)
      cat > \${tmp}
      status=\$(curl -sk -o /tmp/higress-apply-response -w '%{http_code}' -X POST -H 'Content-Type: application/yaml' --data-binary @\${tmp} '${url}')
      rm -f \${tmp}
      printf '%s' \${status}
    "
  )"

  if [[ "${status}" != "201" && "${status}" != "200" ]]; then
    echo "FAIL apply ${resource_type}/${resource_name}: HTTP ${status}" >&2
    docker exec "${API_SERVER_CONTAINER}" sh -lc "cat /tmp/higress-apply-response 2>/dev/null || true" >&2
    exit 1
  fi

  echo "OK ${resource_type}/${resource_name}"
}

apply_ingress() {
  local resource_name="$1"
  local host="$2"
  local destination="$3"
  local path="${4:-/}"

  apply_resource "${NAMESPACE}" "networking.k8s.io/v1" "ingresses" "${resource_name}" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${resource_name}
  namespace: higress-system
  labels:
    higress.io/domain_${host}: "true"
    higress.io/resource-definer: higress
  annotations:
    higress.io/destination: ${destination}
    higress.io/ignore-path-case: "false"
spec:
  ingressClassName: higress
  rules:
  - host: ${host}
    http:
      paths:
      - path: ${path}
        pathType: Prefix
        backend:
          resource:
            apiGroup: networking.higress.io
            kind: McpBridge
            name: default
YAML
}

# This Higress standalone install is driven by Console-style Ingress + McpBridge.
# Clean earlier Gateway API resources if this script is re-run after experiments.
delete_resource "${NAMESPACE}" "gateway.networking.k8s.io/v1beta1" "httproutes" "sso-web-route"
delete_resource "${NAMESPACE}" "gateway.networking.k8s.io/v1beta1" "httproutes" "sso-api-route"
delete_resource "${NAMESPACE}" "gateway.networking.k8s.io/v1beta1" "httproutes" "ai-image-studio-route"
delete_resource "${NAMESPACE}" "v1" "services" "sso-web-dev"
delete_resource "${NAMESPACE}" "v1" "services" "sso-api"
delete_resource "${NAMESPACE}" "v1" "services" "ai-image-studio"

apply_resource "${NAMESPACE}" "networking.higress.io/v1" "mcpbridges" "default" <<YAML
apiVersion: networking.higress.io/v1
kind: McpBridge
metadata:
  name: default
  namespace: higress-system
spec:
  registries:
  - domain: console.svc
    name: higress-console
    port: 8080
    type: dns
  - domain: nacos
    nacosGroups:
    - DEFAULT_GROUP
    name: nacos
    port: 8848
    type: nacos2
  - domain: host.docker.internal
    name: ${SSO_WEB_SERVICE_NAME}
    port: ${SSO_WEB_PORT}
    protocol: http
    type: dns
  - domain: host.docker.internal
    name: sso-api
    port: ${SSO_API_PORT}
    protocol: http
    type: dns
  - domain: host.docker.internal
    name: ${SSO_API_SERVICE_NAME}
    port: ${SSO_API_PORT}
    protocol: http
    type: dns
  - domain: host.docker.internal
    name: ${AI_IMAGE_SERVICE_NAME}
    port: ${AI_IMAGE_PORT}
    protocol: http
    type: dns
YAML

apply_ingress "sso-web-route" "${LOCAL_SSO_HOST}" "${SSO_WEB_SERVICE_NAME}.dns:${SSO_WEB_PORT}"
apply_ingress "sso-api-route" "${LOCAL_SSO_API_HOST}" "${SSO_API_SERVICE_NAME}.dns:${SSO_API_PORT}"
apply_ingress "ai-image-studio-route" "${LOCAL_IMAGE_HOST}" "${AI_IMAGE_SERVICE_NAME}.dns:${AI_IMAGE_PORT}"

# Public routes are optional; when PUBLIC_* is omitted, preserve existing public
# ingress resources to avoid accidentally taking domains offline during local-only updates.
if [[ -n "${PUBLIC_SSO_HOST}" ]]; then
  apply_ingress "sso-web-public-route" "${PUBLIC_SSO_HOST}" "${SSO_WEB_SERVICE_NAME}.dns:${SSO_WEB_PORT}"
fi

if [[ -n "${PUBLIC_SSO_API_HOST}" ]]; then
  apply_ingress "sso-api-public-route" "${PUBLIC_SSO_API_HOST}" "${SSO_API_SERVICE_NAME}.dns:${SSO_API_PORT}" "/health"
fi

if [[ -n "${PUBLIC_IMAGE_HOST}" ]]; then
  apply_ingress "ai-image-studio-public-route" "${PUBLIC_IMAGE_HOST}" "${AI_IMAGE_SERVICE_NAME}.dns:${AI_IMAGE_PORT}"
fi

cat <<'TEXT'
OK project routes configured.

验证入口：
TEXT
cat <<TEXT
  curl -i http://localhost:${GATEWAY_HTTP_PORT}/ -H 'Host: ${LOCAL_SSO_HOST}'
  curl -i http://localhost:${GATEWAY_HTTP_PORT}/health -H 'Host: ${LOCAL_SSO_API_HOST}'
  curl -i http://localhost:${GATEWAY_HTTP_PORT}/api/health -H 'Host: ${LOCAL_IMAGE_HOST}'
TEXT

if [[ -n "${PUBLIC_SSO_HOST}${PUBLIC_SSO_API_HOST}${PUBLIC_IMAGE_HOST}" ]]; then
  cat <<TEXT

 公网 Host 已写入：
  PUBLIC_SSO_HOST=${PUBLIC_SSO_HOST:-未设置}
  PUBLIC_SSO_API_HOST=${PUBLIC_SSO_API_HOST:-未设置}（仅 /health）
  PUBLIC_IMAGE_HOST=${PUBLIC_IMAGE_HOST:-未设置}
TEXT
fi
