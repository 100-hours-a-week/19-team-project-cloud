#!/bin/bash

################################################################################
# run-all-tests.sh
#
# Re-Fit 부하테스트 전체 자동 실행 스크립트
#
# 실행 순서:
#   1. 환경 검증
#   2. 토큰 생성
#   3. Baseline Test (10분)
#   4. Load Test (7분)
#   5. Stress Test (28분)
#   6. Spike Test (9분)
#   7. AI Agent Test (10분)
#   8. HPA Validation Test (22분)
#   9. Cleanup (5분)
#  10. 결과 아카이브
#
# 총 소요시간: 약 95분
# 참고: Self-Healing Test는 kubectl 대화형 확인이 필요하므로
#       run-single-test.sh 옵션 7로 별도 실행하세요.
#
# 사용법:
#   chmod +x run-all-tests.sh
#   ./run-all-tests.sh
#
################################################################################

set -e  # 에러 발생 시 즉시 중단

# 스크립트 디렉토리로 이동 (loadTest 폴더)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ════════════════════════════════════════════════════════════════════════════
# 환경 설정
# ════════════════════════════════════════════════════════════════════════════

export BACKEND_URL="${BACKEND_URL:-https://api-k8s.re-fit.kr}"

# ════════════════════════════════════════════════════════════════════════════
# 색상 정의
# ════════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

print_step() {
  echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

wait_with_countdown() {
  local seconds=$1
  local message=$2
  
  echo ""
  echo -e "${YELLOW}⏳ ${message}${NC}"
  
  for ((i=$seconds; i>0; i--)); do
    echo -ne "${YELLOW}   ${i}초 남음...\r${NC}"
    sleep 1
  done
  
  echo -e "${GREEN}   완료!          ${NC}"
  echo ""
}

# ════════════════════════════════════════════════════════════════════════════
# 1. 환경 검증
# ════════════════════════════════════════════════════════════════════════════

print_header "🔍 Re-Fit 부하테스트 자동 실행"

print_step "환경 검증 중..."

# Node.js 확인
if ! command -v node &> /dev/null; then
  print_error "Node.js가 설치되지 않았습니다."
  exit 1
fi
print_success "Node.js $(node --version)"

# k6 확인
if ! command -v k6 &> /dev/null; then
  print_error "k6가 설치되지 않았습니다."
  echo ""
  echo "설치 방법:"
  echo "  macOS: brew install k6"
  echo "  Linux: sudo apt-get install k6"
  exit 1
fi
print_success "k6 $(k6 version 2>/dev/null | head -1 || echo 'installed')"

# ════════════════════════════════════════════════════════════════════════════
# 2. 토큰 생성
# ════════════════════════════════════════════════════════════════════════════

print_header "🔐 토큰 확인"
print_step "data/test-users.json 사용 (pre-generated tokens)"
if [ ! -f "data/test-users.json" ]; then
  print_error "data/test-users.json 파일이 없습니다."
  exit 1
fi
print_success "토큰 파일 확인 완료"

# ════════════════════════════════════════════════════════════════════════════
# 3. Baseline Test
# ════════════════════════════════════════════════════════════════════════════

print_header "📊 Baseline Test (10분)"
k6 run scripts/1-baseline.js
print_success "Baseline Test 완료"

# ════════════════════════════════════════════════════════════════════════════
# 4. Load Test
# ════════════════════════════════════════════════════════════════════════════

print_header "📈 Load Test (7분)"
k6 run scripts/2-load-test.js
print_success "Load Test 완료"

# ════════════════════════════════════════════════════════════════════════════
# 5. Stress Test
# ════════════════════════════════════════════════════════════════════════════

print_header "🔥 Stress Test (28분)"
k6 run scripts/3-stress-test.js
print_success "Stress Test 완료"

# ════════════════════════════════════════════════════════════════════════════
# 6. Spike Test
# ════════════════════════════════════════════════════════════════════════════

print_header "⚡ Spike Test (9분)"
k6 run scripts/4-spike-test.js
print_success "Spike Test 완료"

# ════════════════════════════════════════════════════════════════════════════
# 7. AI Agent Test
# ════════════════════════════════════════════════════════════════════════════

print_header "🤖 AI Agent Test (10분)"
k6 run scripts/5-ai-agent-test.js
print_success "AI Agent Test 완료"

# ════════════════════════════════════════════════════════════════════════════
# 8. HPA Validation Test
# ════════════════════════════════════════════════════════════════════════════

print_header "⚡ HPA Validation Test (22분)"
print_warning "kubectl watch를 별도 터미널에서 실행하는 것을 권장합니다:"
echo "  watch -n5 kubectl get hpa -n refit-app"
echo "  watch -n5 kubectl get pods -n refit-app"
echo ""
wait_with_countdown 10 "10초 후 HPA Validation Test를 시작합니다..."
k6 run scripts/6-hpa-validation.js
print_success "HPA Validation Test 완료"

# ════════════════════════════════════════════════════════════════════════════
# 9. Cleanup
# ════════════════════════════════════════════════════════════════════════════

print_header "🧹 Cleanup (테스트 데이터 정리)"
k6 run scripts/9-cleanup.js
print_success "Cleanup 완료"

# ════════════════════════════════════════════════════════════════════════════
# 완료
# ════════════════════════════════════════════════════════════════════════════

print_header "✅ 전체 부하테스트 완료!"
echo "결과는 ./results/ 폴더에 저장되었습니다."
echo ""
echo "Self-Healing 테스트가 필요하면:"
echo "  ./run-single-test.sh → 옵션 7 선택"
echo ""