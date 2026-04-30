#!/usr/bin/env bash
set -euo pipefail

API_SERVER_CONTAINER="${API_SERVER_CONTAINER:-higress-apiserver-1}"
API_SERVER_URL="${API_SERVER_URL:-https://127.0.0.1:8443}"
NAMESPACE="${NAMESPACE:-higress-system}"

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

# This Higress standalone install is driven by Console-style Ingress + McpBridge.
# Clean earlier Gateway API resources if this script is re-run after experiments.
delete_resource "${NAMESPACE}" "gateway.networking.k8s.io/v1beta1" "httproutes" "sso-web-route"
delete_resource "${NAMESPACE}" "gateway.networking.k8s.io/v1beta1" "httproutes" "sso-api-route"
delete_resource "${NAMESPACE}" "gateway.networking.k8s.io/v1beta1" "httproutes" "ai-image-studio-route"
delete_resource "${NAMESPACE}" "v1" "services" "sso-web-dev"
delete_resource "${NAMESPACE}" "v1" "services" "sso-api"
delete_resource "${NAMESPACE}" "v1" "services" "ai-image-studio"

apply_resource "${NAMESPACE}" "networking.higress.io/v1" "mcpbridges" "default" <<'YAML'
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
    name: user-system-web
    port: 5173
    protocol: http
    type: dns
  - domain: host.docker.internal
    name: sso-api
    port: 4000
    protocol: http
    type: dns
  - domain: host.docker.internal
    name: user-system-api
    port: 4000
    protocol: http
    type: dns
  - domain: host.docker.internal
    name: ai-image-studio
    port: 3008
    protocol: http
    type: dns
YAML

apply_resource "${NAMESPACE}" "networking.k8s.io/v1" "ingresses" "sso-web-route" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sso-web-route
  namespace: higress-system
  labels:
    higress.io/domain_sso.localhost: "true"
    higress.io/resource-definer: higress
  annotations:
    higress.io/destination: user-system-web.dns:5173
    higress.io/ignore-path-case: "false"
spec:
  ingressClassName: higress
  rules:
  - host: sso.localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          resource:
            apiGroup: networking.higress.io
            kind: McpBridge
            name: default
YAML

apply_resource "${NAMESPACE}" "networking.k8s.io/v1" "ingresses" "sso-api-route" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sso-api-route
  namespace: higress-system
  labels:
    higress.io/domain_sso-api.localhost: "true"
    higress.io/resource-definer: higress
  annotations:
    higress.io/destination: user-system-api.dns:4000
    higress.io/ignore-path-case: "false"
spec:
  ingressClassName: higress
  rules:
  - host: sso-api.localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          resource:
            apiGroup: networking.higress.io
            kind: McpBridge
            name: default
YAML

apply_resource "${NAMESPACE}" "networking.k8s.io/v1" "ingresses" "ai-image-studio-route" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ai-image-studio-route
  namespace: higress-system
  labels:
    higress.io/domain_image.localhost: "true"
    higress.io/resource-definer: higress
  annotations:
    higress.io/destination: ai-image-studio.dns:3008
    higress.io/ignore-path-case: "false"
spec:
  ingressClassName: higress
  rules:
  - host: image.localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          resource:
            apiGroup: networking.higress.io
            kind: McpBridge
            name: default
YAML

cat <<'TEXT'
OK project routes configured.

验证入口：
  curl -i http://localhost:8082/ -H 'Host: sso.localhost'
  curl -i http://localhost:8082/health -H 'Host: sso-api.localhost'
  curl -i http://localhost:8082/api/health -H 'Host: image.localhost'
TEXT
