#!/usr/bin/env bash
set -euo pipefail

check_status() {
  local name="$1"
  local expected="$2"
  local url="$3"
  local status

  status="$(curl -sS -o /tmp/higress-smoke.out -w '%{http_code}' "${url}")"
  if [[ "${status}" != "${expected}" ]]; then
    echo "FAIL ${name}: expected HTTP ${expected}, got ${status}" >&2
    cat /tmp/higress-smoke.out >&2 || true
    exit 1
  fi
  echo "OK ${name}: HTTP ${status}"
}

check_status "Higress Console" "200" "http://localhost:8084/"
check_status "Higress Gateway welcome page" "200" "http://localhost:8082/"

echo "OK Higress smoke test passed"
