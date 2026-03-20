#!/bin/bash
# =============================================================================
# k8s-self-healing-test.sh
#
# Self-Healing 검증 테스트
#
# 목적:
#   - 부하 중 파드를 강제 삭제하고 k8s가 자동으로 복구하는지 검증
#   - 백엔드/AI 파드의 복구 시간 측정
#   - 복구 중 서비스 가용성 확인
#   - 테스트 종료 후 VPA 추천 리소스 확인
#
# 전제조건:
#   - kubectl이 EKS 클러스터에 연결되어 있어야 함 (아래 SETUP 섹션 참고)
#   - k6 설치 필요
#   - JWT 토큰 생성 완료 (npm run generate-tokens)
#
# 실행:
#   bash scripts/k8s-self-healing-test.sh
#   또는: npm run test:self-healing
#
# 예상 소요시간: ~15분
# =============================================================================

set -e

# ═══════════════════════════════════════════════════════════════════
# 색상 정의
# ═══════════════════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════════
# 설정 변수
# ═══════════════════════════════════════════════════════════════════
NAMESPACE="refit-app"
BACKEND_DEPLOYMENT="refit-backend"
AI_DEPLOYMENT="refit-ai"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/results"

# ═══════════════════════════════════════════════════════════════════
# 헬퍼 함수
# ═══════════════════════════════════════════════════════════════════
print_header() {
  echo ""
  echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════${NC}"
  echo -e "${BLUE}${BOLD}  $1${NC}"
  echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""
}

print_step() {
  echo -e "${CYAN}▶ $1${NC}"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

# ═══════════════════════════════════════════════════════════════════
# EKS kubectl 설정 안내 출력
# ═══════════════════════════════════════════════════════════════════
print_header "Self-Healing Test - EKS kubectl 설정 확인"

echo -e "${YELLOW}kubectl이 EKS 클러스터에 연결되지 않은 경우 아래 명령을 먼저 실행하세요:${NC}"
echo ""
echo "  aws eks update-kubeconfig \\"
echo "    --region ap-northeast-2 \\"
echo "    --name <CLUSTER_NAME>"
echo ""
echo "  # 접근 확인:"
echo "  kubectl get nodes"
echo "  kubectl get pods -n $NAMESPACE"
echo ""

# kubectl 접근 확인
print_step "kubectl 접근 테스트 중..."
if ! kubectl get pods -n $NAMESPACE --no-headers > /dev/null 2>&1; then
  print_error "kubectl이 $NAMESPACE 네임스페이스에 접근할 수 없습니다."
  echo ""
  echo "  가능한 원인:"
  echo "  1. aws eks update-kubeconfig 미실행"
  echo "  2. AWS 자격증명 미설정 (aws configure 또는 AWS_PROFILE)"
  echo "  3. 클러스터 이름 오타"
  echo ""
  echo "  클러스터 목록 확인:"
  echo "  aws eks list-clusters --region ap-northeast-2"
  exit 1
fi

print_success "kubectl 접근 확인 완료"

# k6 설치 확인
if ! command -v k6 &> /dev/null; then
  print_error "k6가 설치되지 않았습니다. https://k6.io/docs/getting-started/installation/"
  exit 1
fi

# 토큰 파일 확인
if [ ! -f "$SCRIPT_DIR/../data/test-users.json" ]; then
  print_warning "test-users.json이 없습니다. 토큰을 생성합니다..."
  cd "$SCRIPT_DIR/.." && node generate-tokens.js
fi

mkdir -p "$RESULTS_DIR"

# ═══════════════════════════════════════════════════════════════════
# 1. 사전 상태 스냅샷
# ═══════════════════════════════════════════════════════════════════
print_header "1. 사전 상태 확인"

echo -e "${BOLD}[파드 상태]${NC}"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo -e "${BOLD}[HPA 상태]${NC}"
kubectl get hpa -n $NAMESPACE

echo ""
echo -e "${BOLD}[PDB 상태]${NC}"
kubectl get pdb -n $NAMESPACE 2>/dev/null || echo "(PDB 없음)"

# ═══════════════════════════════════════════════════════════════════
# 2. 백그라운드 부하 시작
# ═══════════════════════════════════════════════════════════════════
print_header "2. 백그라운드 k6 부하 시작"

K6_LOG="$RESULTS_DIR/self-healing-k6-output.txt"
K6_JSON="$RESULTS_DIR/self-healing-k6-summary.json"

print_step "k6 HPA 검증 스크립트를 백그라운드로 실행합니다..."
k6 run \
  --out "json=$K6_JSON" \
  "$SCRIPT_DIR/6-hpa-validation.js" \
  > "$K6_LOG" 2>&1 &
K6_PID=$!
echo "  k6 PID: $K6_PID"
echo "  로그: $K6_LOG"
echo ""

# ═══════════════════════════════════════════════════════════════════
# 3. 램프업 대기 (2분)
# ═══════════════════════════════════════════════════════════════════
print_step "부하 램프업 대기 중 (2분)..."
for i in $(seq 120 -10 10); do
  echo -ne "  ${i}초 남음...\r"
  sleep 10
done
echo ""

# k6가 아직 실행 중인지 확인
if ! kill -0 $K6_PID 2>/dev/null; then
  print_error "k6가 예상보다 일찍 종료되었습니다. 로그를 확인하세요: $K6_LOG"
  tail -20 "$K6_LOG"
  exit 1
fi

print_step "현재 파드 상태:"
kubectl get pods -n $NAMESPACE

# ═══════════════════════════════════════════════════════════════════
# 4. 백엔드 파드 삭제 + 복구 시간 측정
# ═══════════════════════════════════════════════════════════════════
print_header "3. 백엔드 파드 Self-Healing 테스트"

BACKEND_POD=$(kubectl get pods -n $NAMESPACE \
  -l "app.kubernetes.io/name=$BACKEND_DEPLOYMENT" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# app 레이블이 다를 수 있으므로 폴백
if [ -z "$BACKEND_POD" ]; then
  BACKEND_POD=$(kubectl get pods -n $NAMESPACE \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null \
    | head -1)
fi

if [ -z "$BACKEND_POD" ]; then
  print_error "실행 중인 백엔드 파드를 찾을 수 없습니다."
  kill $K6_PID 2>/dev/null
  exit 1
fi

echo "  대상 파드: $BACKEND_POD"
echo ""

BACKEND_DELETION_TIME=$(date +%s)
print_step "파드 삭제: $BACKEND_POD ($(date '+%H:%M:%S'))"
kubectl delete pod "$BACKEND_POD" -n $NAMESPACE

echo ""
print_step "Deployment 복구 대기 중 (최대 120초)..."
echo "  참고: minReadySeconds=30 + startup probe 초기화 시간으로 50~80초 예상"

if kubectl rollout status deployment/$BACKEND_DEPLOYMENT -n $NAMESPACE --timeout=120s; then
  BACKEND_RECOVERY_TIME=$(date +%s)
  BACKEND_RECOVERY_DURATION=$((BACKEND_RECOVERY_TIME - BACKEND_DELETION_TIME))
  print_success "백엔드 복구 완료! 소요시간: ${BACKEND_RECOVERY_DURATION}초"
else
  print_warning "rollout status 타임아웃 (파드가 아직 준비 중일 수 있음)"
  BACKEND_RECOVERY_DURATION="타임아웃(>120초)"
fi

echo ""
echo -e "${BOLD}[복구 후 파드 상태]${NC}"
kubectl get pods -n $NAMESPACE

# ═══════════════════════════════════════════════════════════════════
# 5. 안정화 대기 (3분)
# ═══════════════════════════════════════════════════════════════════
print_step "다음 테스트 전 안정화 대기 (3분)..."
for i in $(seq 180 -10 10); do
  echo -ne "  ${i}초 남음...\r"
  sleep 10
done
echo ""

# ═══════════════════════════════════════════════════════════════════
# 6. AI 파드 삭제 + 복구 시간 측정
# ═══════════════════════════════════════════════════════════════════
print_header "4. AI 서비스 파드 Self-Healing 테스트"

# 실행 중인 AI 파드 수 확인
AI_RUNNING=$(kubectl get pods -n $NAMESPACE \
  -l "app.kubernetes.io/name=$AI_DEPLOYMENT" \
  --field-selector=status.phase=Running \
  --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo "  현재 실행 중인 AI 파드 수: $AI_RUNNING"
echo "  PDB 설정: maxUnavailable=1 (1개 파드 삭제 허용)"
echo ""

AI_POD=$(kubectl get pods -n $NAMESPACE \
  -l "app.kubernetes.io/name=$AI_DEPLOYMENT" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$AI_POD" ]; then
  print_warning "AI 파드를 찾을 수 없습니다 (레이블 이름이 다를 수 있음). 건너뜁니다."
  AI_RECOVERY_DURATION="건너뜀"
else
  echo "  대상 파드: $AI_POD"
  echo ""

  AI_DELETION_TIME=$(date +%s)
  print_step "AI 파드 삭제: $AI_POD ($(date '+%H:%M:%S'))"
  # AI terminationGracePeriodSeconds: 30 적용
  kubectl delete pod "$AI_POD" -n $NAMESPACE --grace-period=30

  echo ""
  print_step "AI Deployment 복구 대기 중 (최대 180초)..."
  echo "  참고: AI startup probe initialDelaySeconds=30 + 초기화로 60~90초 예상"

  if kubectl rollout status deployment/$AI_DEPLOYMENT -n $NAMESPACE --timeout=180s; then
    AI_RECOVERY_TIME=$(date +%s)
    AI_RECOVERY_DURATION=$((AI_RECOVERY_TIME - AI_DELETION_TIME))
    print_success "AI 서비스 복구 완료! 소요시간: ${AI_RECOVERY_DURATION}초"
  else
    print_warning "rollout status 타임아웃 (파드가 아직 준비 중일 수 있음)"
    AI_RECOVERY_DURATION="타임아웃(>180초)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════
# 7. 관찰 창 (2분)
# ═══════════════════════════════════════════════════════════════════
print_step "최종 안정화 관찰 (2분)..."
for i in $(seq 120 -10 10); do
  echo -ne "  ${i}초 남음...\r"
  sleep 10
done
echo ""

# ═══════════════════════════════════════════════════════════════════
# 8. k6 종료
# ═══════════════════════════════════════════════════════════════════
print_header "5. k6 종료"

if kill -0 $K6_PID 2>/dev/null; then
  print_step "k6 종료 중..."
  kill $K6_PID 2>/dev/null
  wait $K6_PID 2>/dev/null || true
  print_success "k6 종료 완료"
else
  print_warning "k6가 이미 종료되었습니다."
fi

# ═══════════════════════════════════════════════════════════════════
# 9. 최종 상태 확인
# ═══════════════════════════════════════════════════════════════════
print_header "6. 최종 상태 확인"

echo -e "${BOLD}[파드 상태]${NC}"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo -e "${BOLD}[HPA 상태]${NC}"
kubectl get hpa -n $NAMESPACE

# ═══════════════════════════════════════════════════════════════════
# 10. VPA 추천 확인
# ═══════════════════════════════════════════════════════════════════
print_header "7. VPA 추천 리소스 확인"

echo -e "${BOLD}[백엔드 VPA]${NC}"
if kubectl get vpa -n $NAMESPACE > /dev/null 2>&1; then
  kubectl get vpa -n $NAMESPACE
  echo ""

  # jq가 있으면 상세 추천 출력
  if command -v jq &> /dev/null; then
    echo -e "${BOLD}[VPA 상세 추천 (jq)]${NC}"
    kubectl get vpa -n $NAMESPACE -o json | \
      jq '.items[] | {
        name: .metadata.name,
        recommendations: [
          .status.recommendation.containerRecommendations[]? |
          {
            container: .containerName,
            lowerBound: .lowerBound,
            target: .target,
            upperBound: .upperBound
          }
        ]
      }' 2>/dev/null || echo "(VPA 추천 데이터 없음 - 더 많은 부하 데이터 필요)"
  else
    echo -e "${BOLD}[VPA 상세 추천 (kubectl describe)]${NC}"
    kubectl describe vpa -n $NAMESPACE 2>/dev/null | \
      grep -A 30 "Recommendation:" || echo "(VPA 추천 없음)"
  fi
else
  print_warning "VPA 리소스를 찾을 수 없습니다. ($NAMESPACE 네임스페이스)"
fi

echo ""
echo -e "${YELLOW}현재 설정과 비교:${NC}"
echo "  Backend: request=250m CPU, 300Mi memory / limit=500m CPU, 768Mi memory"
echo "  AI:      request=500m CPU, 1Gi memory   / limit=2 CPU,   3Gi memory"
echo ""
echo -e "${CYAN}VPA target 값이 현재 설정과 크게 다르면 values.yaml 조정을 검토하세요.${NC}"

# ═══════════════════════════════════════════════════════════════════
# 11. 최종 리포트
# ═══════════════════════════════════════════════════════════════════
print_header "Self-Healing Test 완료"

echo -e "${BOLD}📊 복구 시간 요약:${NC}"
echo "  백엔드 파드 복구: ${BACKEND_RECOVERY_DURATION}초"
echo "  AI 파드 복구:     ${AI_RECOVERY_DURATION}초"
echo ""
echo -e "${BOLD}📁 결과 파일:${NC}"
echo "  k6 로그:        $K6_LOG"
echo "  k6 JSON 요약:   $K6_JSON"
echo ""
echo -e "${BOLD}✅ 검증 체크리스트:${NC}"
echo "  [ ] 백엔드 파드 삭제 후 자동 재시작 확인"
echo "  [ ] AI 파드 삭제 후 자동 재시작 확인"
echo "  [ ] 복구 중 서비스 요청 에러율 허용치 이내 (k6 JSON 확인)"
echo "  [ ] VPA 추천이 현재 설정과 합리적 범위 내에 있는지 확인"
echo ""
echo -e "${CYAN}k6 에러율 분석 (복구 구간):${NC}"
echo "  cat $K6_JSON | jq '.metrics.http_req_failed.values'"
echo ""
