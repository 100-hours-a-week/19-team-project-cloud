#!/bin/bash

################################################################################
# run-single-test.sh
#
# Re-Fit 부하테스트 개별 실행 스크립트 (대화형)
#
# 사용법:
#   chmod +x run-single-test.sh
#   ./run-single-test.sh
#
################################################################################

set -e

# 스크립트 디렉토리로 이동 (loadTest 폴더)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ════════════════════════════════════════════════════════════════════════════
# 색상 정의
# ════════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ════════════════════════════════════════════════════════════════════════════
# 헬퍼 함수
# ════════════════════════════════════════════════════════════════════════════

print_header() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}$1${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
  echo ""
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠  $1${NC}"
}

# ════════════════════════════════════════════════════════════════════════════
# 메인 메뉴
# ════════════════════════════════════════════════════════════════════════════

print_header "🧪 Re-Fit 부하테스트 - 개별 실행"

echo "실행할 테스트를 선택하세요:"
echo ""
echo "  1) Baseline Test        (10분)  - 정상 상태 측정"
echo "  2) Load Test            (7분)   - 일반 부하 검증"
echo "  3) Stress Test          (28분)  - Breaking Point 탐색"
echo "  4) Spike Test           (9분)   - 급증 대응력 테스트"
echo "  5) AI Agent Test        (10분)  - AI 챗봇 SSE 테스트"
echo "  6) HPA Validation Test  (22분)  - HPA 스케일링 검증 (kubectl watch 필요)"
echo "  7) Self-Healing Test    (~15분) - Pod 삭제 복구 테스트 (kubectl 필요)"
echo "  8) Cleanup              (5분)   - 테스트 데이터 정리"
echo ""
echo "  G1) Grafana 연동 - Baseline Test"
echo "  G2) Grafana 연동 - Load Test"
echo "  G3) Grafana 연동 - Stress Test"
echo "  G4) Grafana 연동 - Spike Test"
echo "  G5) Grafana 연동 - AI Agent Test"
echo "  G6) Grafana 연동 - HPA Validation Test"
echo ""
echo "  0) 전체 테스트 실행"
echo ""

read -p "선택 (0-8, G1-G6): " choice

# ════════════════════════════════════════════════════════════════════════════
# 선택에 따른 실행
# ════════════════════════════════════════════════════════════════════════════

case $choice in
  1)
    print_header "📊 Baseline Test 실행 (10분)"
    node generate-tokens.js
    k6 run scripts/1-baseline.js
    print_success "Baseline Test 완료"
    ;;

  2)
    print_header "📊 Load Test 실행 (7분)"
    node generate-tokens.js
    k6 run scripts/2-load-test.js
    print_success "Load Test 완료"
    ;;

  3)
    print_header "📊 Stress Test 실행 (28분)"
    node generate-tokens.js
    k6 run scripts/3-stress-test.js
    print_success "Stress Test 완료"
    ;;

  4)
    print_header "📊 Spike Test 실행 (9분)"
    node generate-tokens.js
    k6 run scripts/4-spike-test.js
    print_success "Spike Test 완료"
    ;;

  5)
    print_header "🤖 AI Agent Test 실행 (10분)"
    node generate-tokens.js
    k6 run scripts/5-ai-agent-test.js
    print_success "AI Agent Test 완료"
    ;;

  6)
    print_header "⚡ HPA Validation Test 실행 (22분)"
    echo -e "${YELLOW}별도 터미널에서 실행하세요:${NC}"
    echo "  watch -n5 kubectl get hpa -n refit-app"
    echo "  watch -n5 kubectl get pods -n refit-app"
    echo ""
    read -p "kubectl watch 준비됐나요? (y/N): " kubectl_ready
    if [[ "$kubectl_ready" != "y" && "$kubectl_ready" != "Y" ]]; then
      echo "kubectl watch를 먼저 실행한 후 다시 시도하세요."
      exit 0
    fi
    node generate-tokens.js
    k6 run scripts/6-hpa-validation.js
    print_success "HPA Validation Test 완료"
    echo ""
    echo "VPA 추천 확인:"
    echo "  kubectl get vpa -n refit-app -o json | jq '.items[] | {name: .metadata.name, recs: .status.recommendation.containerRecommendations}'"
    ;;

  7)
    print_header "🔧 Self-Healing Test 실행 (~15분)"
    print_warning "kubectl이 EKS 클러스터에 연결되어 있어야 합니다"
    echo "  EKS 설정: aws eks update-kubeconfig --region ap-northeast-2 --name <CLUSTER>"
    echo ""
    node generate-tokens.js
    bash scripts/k8s-self-healing-test.sh
    print_success "Self-Healing Test 완료"
    ;;

  8)
    print_header "🧹 Cleanup 실행 (5분)"
    node generate-tokens.js
    k6 run scripts/9-cleanup.js
    print_success "Cleanup 완료"
    ;;

  G1|g1)
    print_header "📊 Grafana 연동 - Baseline Test"
    node generate-tokens.js
    k6 run --out influxdb=http://localhost:8086/k6db scripts/1-baseline.js
    ;;

  G2|g2)
    print_header "📊 Grafana 연동 - Load Test"
    node generate-tokens.js
    k6 run --out influxdb=http://localhost:8086/k6db scripts/2-load-test.js
    ;;

  G3|g3)
    print_header "📊 Grafana 연동 - Stress Test"
    node generate-tokens.js
    k6 run --out influxdb=http://localhost:8086/k6db scripts/3-stress-test.js
    ;;

  G4|g4)
    print_header "📊 Grafana 연동 - Spike Test"
    node generate-tokens.js
    k6 run --out influxdb=http://localhost:8086/k6db scripts/4-spike-test.js
    ;;

  G5|g5)
    print_header "🤖 Grafana 연동 - AI Agent Test"
    node generate-tokens.js
    k6 run --out influxdb=http://localhost:8086/k6db scripts/5-ai-agent-test.js
    ;;

  G6|g6)
    print_header "⚡ Grafana 연동 - HPA Validation Test"
    node generate-tokens.js
    k6 run --out influxdb=http://localhost:8086/k6db scripts/6-hpa-validation.js
    ;;

  0)
    print_header "🚀 전체 테스트 실행"
    bash run-all-tests.sh
    ;;

  *)
    print_error "잘못된 선택입니다: $choice"
    exit 1
    ;;
esac
