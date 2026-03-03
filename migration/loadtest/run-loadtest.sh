#!/usr/bin/env bash
#
# k6 부하테스트 실행 스크립트 (Prometheus Remote Write + Web Dashboard)
#
# 사용법:
#   ./run-loadtest.sh <TARGET> <TEST_TYPE>
#
# TARGET:    v1 | v2
# TEST_TYPE: smoke | load | spike | stress | soak
#
# 예시:
#   ./run-loadtest.sh v1 smoke
#   ./run-loadtest.sh v2 spike
#
# 필수 조건:
#   - k6 설치 (https://grafana.com/docs/k6/latest/set-up/install-k6/)
#   - SSH 설정 (~/.ssh/config에 dev-refit-monit, prod-monit 정의)
#
set -euo pipefail

TARGET="${1:-v2}"
TEST_TYPE="${2:-smoke}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_FILE="${SCRIPT_DIR}/scripts/${TEST_TYPE}-test.js"

if [[ ! -f "$SCRIPT_FILE" ]]; then
  echo "Error: Script not found: $SCRIPT_FILE"
  echo "Available: smoke, load, spike, stress, soak"
  exit 1
fi

# Prometheus Remote Write 대상 결정
if [[ "$TARGET" == "v1" ]]; then
  # v1 monitoring: grafana.dev.re-fit.kr/prometheus (Basic Auth 보호)
  # SSH 터널링으로 직접 접근
  PROM_HOST="dev-refit-monit"
  PROM_LOCAL_PORT=19090
  PROM_REMOTE_PORT=32816
  PROM_RW_URL="http://localhost:${PROM_LOCAL_PORT}/api/v1/write"
else
  # v2 monitoring: SSM 경유, 포트 9091
  PROM_HOST="prod-monit"
  PROM_LOCAL_PORT=19091
  PROM_REMOTE_PORT=9091
  PROM_RW_URL="http://localhost:${PROM_LOCAL_PORT}/api/v1/write"
fi

TESTID="refit-${TARGET}-${TEST_TYPE}-$(date +%Y%m%d%H%M%S)"

echo "==================================="
echo " k6 Load Test Runner"
echo "==================================="
echo " Target:    ${TARGET}"
echo " Test:      ${TEST_TYPE}"
echo " Script:    ${SCRIPT_FILE}"
echo " Test ID:   ${TESTID}"
echo " Prom RW:   ${PROM_RW_URL}"
echo "==================================="

# SSH 터널 시작 (백그라운드)
echo "[1/3] Starting SSH tunnel to ${PROM_HOST}..."
ssh -f -N -L "${PROM_LOCAL_PORT}:localhost:${PROM_REMOTE_PORT}" "${PROM_HOST}" 2>/dev/null || {
  echo "Warning: SSH tunnel may already be running or failed to start."
  echo "If Prometheus Remote Write fails, check SSH connectivity."
}

# 터널 안정화 대기
sleep 2

# 터널 확인
if curl -s -o /dev/null -w '%{http_code}' "http://localhost:${PROM_LOCAL_PORT}/-/healthy" 2>/dev/null | grep -q "200"; then
  echo "  SSH tunnel OK - Prometheus reachable"
  USE_PROM_RW=true
else
  echo "  Warning: Prometheus not reachable via tunnel. Running without Remote Write."
  USE_PROM_RW=false
fi

# k6 실행
echo "[2/3] Running k6 ${TEST_TYPE} test..."
echo ""

K6_ARGS=(
  run
  --dns-ttl=0s
  -e "TARGET=${TARGET}"
  --tag "testid=${TESTID}"
)

# Web Dashboard 활성화
export K6_WEB_DASHBOARD=true

# Prometheus Remote Write 설정
if [[ "$USE_PROM_RW" == "true" ]]; then
  K6_ARGS+=(
    -o "experimental-prometheus-rw"
  )
  export K6_PROMETHEUS_RW_SERVER_URL="${PROM_RW_URL}"
  export K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true
  export K6_PROMETHEUS_RW_PUSH_INTERVAL="5s"
  export K6_PROMETHEUS_RW_STALE_MARKERS=true
  export K6_PROMETHEUS_RW_TREND_STATS="avg,min,med,max,p(90),p(95),p(99)"
fi

K6_ARGS+=("$SCRIPT_FILE")

echo "Command: k6 ${K6_ARGS[*]}"
echo ""

k6 "${K6_ARGS[@]}" 2>&1 | tee "${SCRIPT_DIR}/results/${TESTID}.log" || true

echo ""
echo "[3/3] Test complete!"
echo "  Results: ${SCRIPT_DIR}/results/${TESTID}.log"
echo "  Dashboard: http://127.0.0.1:5665"
if [[ "$USE_PROM_RW" == "true" ]]; then
  echo "  Grafana: Check 'Architecture Comparison' dashboard"
fi

# SSH 터널 정리
echo ""
echo "Cleaning up SSH tunnel..."
pkill -f "ssh.*-L.*${PROM_LOCAL_PORT}:localhost:${PROM_REMOTE_PORT}" 2>/dev/null || true

echo "Done."
