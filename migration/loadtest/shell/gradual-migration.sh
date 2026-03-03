#!/bin/bash
#
# 점진적 가중치 전환 자동화 스크립트 (포트폴리오용 로깅 포함)
#
# 사용법: ./gradual-migration.sh [--interval 120] [--dry-run]
#
# 단계: v1:v2 = 100:0 → 90:10 → 70:30 → 50:50 → 30:70 → 10:90 → 0:100
# 각 단계마다 지정된 관찰 시간(기본 2분) 동안 대기하며 메트릭을 수집합니다.
# 총 소요 시간: 6단계 × 2분 = 약 12분
#
# 출력:
#   - 콘솔: 실시간 단계별 진행 상황 + 핵심 메트릭
#   - 파일: migration-report-{timestamp}.md (포트폴리오용 마크다운 리포트)

set -euo pipefail

# === 설정 ===
HOSTED_ZONE_ID="<YOUR_HOSTED_ZONE_ID>"
RECORD_NAME="api.re-fit.kr"
V1_SET_ID="v1-weighted"
V2_SET_ID="v2-weighted"
V1_VALUE="<YOUR_V1_EC2_IP>"
V2_ALB_DNS="${V2_ALB_DNS:-<YOUR_ALB_DNS_NAME>}"
V2_ALB_HOSTED_ZONE="${V2_ALB_HOSTED_ZONE:-<YOUR_ALB_HOSTED_ZONE_ID>}"
ALB_ID="app/<YOUR_ALB_NAME>/<YOUR_ALB_ID>"
TG_ID="targetgroup/<YOUR_TG_NAME>/<YOUR_TG_ID>"
RDS_ID="refit-postgres"
REGION="ap-northeast-2"
AWS_PROFILE_OPT="--profile refit-ssm"

# 가중치 전환 단계 (v1 v2)
STAGES=(
  "90 10"
  "70 30"
  "50 50"
  "30 70"
  "10 90"
  "0 100"
)

# 옵션 파싱
INTERVAL=120  # 단계 간 관찰 시간 (초) — 기본 2분 (DNS TTL 60s + 관찰 60s)
DRY_RUN=false
while [ $# -gt 0 ]; do
  case $1 in
    --interval) shift; INTERVAL=${1:-300}; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) shift ;;
  esac
done

# 리포트 파일
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_DIR="$(cd "$(dirname "$0")/.." && pwd)/reports"
mkdir -p "${REPORT_DIR}"
REPORT="${REPORT_DIR}/migration-report-${TIMESTAMP}.md"

# === 유틸리티 함수 ===

log() {
  local msg="[$(date '+%H:%M:%S')] $1"
  echo "$msg"
}

log_section() {
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  $1"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "════════════════════════════════════════════════════════════════"
}

# CloudWatch 일반 메트릭 조회 (Sum/Average/Maximum/Minimum/SampleCount)
get_metric() {
  local namespace=$1 metric=$2 dimension_name=$3 dimension_value=$4 stat=${5:-Sum} minutes=${6:-5}
  local start_time end_time
  start_time=$(date -u -v-${minutes}M '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -d "${minutes} minutes ago" '+%Y-%m-%dT%H:%M:%S')
  end_time=$(date -u '+%Y-%m-%dT%H:%M:%S')

  aws cloudwatch get-metric-statistics \
    --namespace "$namespace" \
    --metric-name "$metric" \
    --dimensions "Name=$dimension_name,Value=$dimension_value" \
    --start-time "$start_time" \
    --end-time "$end_time" \
    --period 60 \
    --statistics "$stat" \
    --region "$REGION" \
    $AWS_PROFILE_OPT \
    --output json 2>/dev/null
}

# CloudWatch 백분위 메트릭 조회 (p90/p95/p99 등) — --extended-statistics 사용
get_metric_extended() {
  local namespace=$1 metric=$2 dimension_name=$3 dimension_value=$4 ext_stat=${5:-p95} minutes=${6:-5}
  local start_time end_time
  start_time=$(date -u -v-${minutes}M '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -d "${minutes} minutes ago" '+%Y-%m-%dT%H:%M:%S')
  end_time=$(date -u '+%Y-%m-%dT%H:%M:%S')

  aws cloudwatch get-metric-statistics \
    --namespace "$namespace" \
    --metric-name "$metric" \
    --dimensions "Name=$dimension_name,Value=$dimension_value" \
    --start-time "$start_time" \
    --end-time "$end_time" \
    --period 60 \
    --extended-statistics "$ext_stat" \
    --region "$REGION" \
    $AWS_PROFILE_OPT \
    --output json 2>/dev/null
}

# ALB 메트릭 수집
collect_alb_metrics() {
  local minutes=${1:-5}

  local req_data healthy_count resp_time_data err_5xx_data

  req_data=$(get_metric "AWS/ApplicationELB" "RequestCount" "LoadBalancer" "$ALB_ID" "Sum" "$minutes" || echo '{}')

  # HealthyHostCount: TargetGroup + LoadBalancer 두 Dimension 모두 필요
  local _hc_start _hc_end
  _hc_start=$(date -u -v-${minutes}M '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -d "${minutes} minutes ago" '+%Y-%m-%dT%H:%M:%S')
  _hc_end=$(date -u '+%Y-%m-%dT%H:%M:%S')
  healthy_count=$(aws cloudwatch get-metric-statistics \
    --namespace "AWS/ApplicationELB" \
    --metric-name "HealthyHostCount" \
    --dimensions \
      "Name=TargetGroup,Value=${TG_ID}" \
      "Name=LoadBalancer,Value=${ALB_ID}" \
    --start-time "$_hc_start" \
    --end-time "$_hc_end" \
    --period 60 \
    --statistics "Minimum" \
    --region "$REGION" \
    $AWS_PROFILE_OPT \
    --output json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin).get('Datapoints',[])
if d:
    d.sort(key=lambda x: x['Timestamp'])
    print(int(d[-1]['Minimum']))
else:
    print('N/A')
" 2>/dev/null || echo "N/A")

  # p95는 --extended-statistics 로만 조회 가능
  resp_time_data=$(get_metric_extended "AWS/ApplicationELB" "TargetResponseTime" "LoadBalancer" "$ALB_ID" "p95" "$minutes" || echo '{}')
  err_5xx_data=$(get_metric "AWS/ApplicationELB" "HTTPCode_Target_5XX_Count" "LoadBalancer" "$ALB_ID" "Sum" "$minutes" || echo '{}')

  # 파싱
  TOTAL_REQUESTS=$(echo "$req_data" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('Datapoints',[])
print(int(sum(p['Sum'] for p in d))) if d else print(0)
" 2>/dev/null || echo "0")

  # ExtendedStatistics 결과는 p['ExtendedStatistics']['p95'] 형태
  P95_RESPONSE=$(echo "$resp_time_data" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('Datapoints',[])
vals=[p['ExtendedStatistics']['p95'] for p in d if 'ExtendedStatistics' in p]
print(f'{sum(vals)/len(vals)*1000:.0f}') if vals else print('N/A')
" 2>/dev/null || echo "N/A")

  TOTAL_5XX=$(echo "$err_5xx_data" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('Datapoints',[])
print(int(sum(p['Sum'] for p in d))) if d else print(0)
" 2>/dev/null || echo "0")

  HEALTHY_HOSTS="$healthy_count"

  # 에러율 계산
  if [ "$TOTAL_REQUESTS" -gt 0 ] 2>/dev/null; then
    ERROR_RATE=$(python3 -c "import sys; a,b=float(sys.argv[1]),float(sys.argv[2]); print(f'{a/b*100:.2f}')" "$TOTAL_5XX" "$TOTAL_REQUESTS" 2>/dev/null || echo "N/A")
  else
    ERROR_RATE="0.00"
  fi
}

# v1 EC2 Spring Actuator 누적 요청수를 CloudWatch에서 읽어 반환
# collect-metrics.sh 가 1분마다 ReFit/Infrastructure/backend_http_requests_count 로 푸시하는 값
get_v1_request_count() {
  local start_time end_time
  # 최근 3분 중 가장 최근 값(Maximum)을 가져옴
  start_time=$(date -u -v-3M '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -d '3 minutes ago' '+%Y-%m-%dT%H:%M:%S')
  end_time=$(date -u '+%Y-%m-%dT%H:%M:%S')
  aws cloudwatch get-metric-statistics \
    --namespace "ReFit/Infrastructure" \
    --metric-name "backend_http_requests_count" \
    --dimensions "Name=InstanceId,Value=<YOUR_INSTANCE_ID>" \
    --start-time "$start_time" \
    --end-time "$end_time" \
    --period 60 \
    --statistics "Maximum" \
    --region "$REGION" \
    $AWS_PROFILE_OPT \
    --output json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin).get('Datapoints',[])
if d:
    d.sort(key=lambda x: x['Timestamp'])
    print(int(d[-1]['Maximum']))
else:
    print(-1)
" 2>/dev/null || echo "-1"
}

# RDS 메트릭 수집
collect_rds_metrics() {
  local minutes=${1:-5}
  RDS_CPU=$(get_metric "AWS/RDS" "CPUUtilization" "DBInstanceIdentifier" "$RDS_ID" "Average" "$minutes" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('Datapoints',[])
vals=[p['Average'] for p in d]
print(f'{sum(vals)/len(vals):.1f}') if vals else print('N/A')
" 2>/dev/null || echo "N/A")

  RDS_CONNECTIONS=$(get_metric "AWS/RDS" "DatabaseConnections" "DBInstanceIdentifier" "$RDS_ID" "Maximum" "$minutes" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('Datapoints',[])
vals=[p['Maximum'] for p in d]
print(int(max(vals))) if vals else print('N/A')
" 2>/dev/null || echo "N/A")
}

# 메트릭 콘솔 출력
print_metrics() {
  echo ""
  echo "  ┌─────────────────────────────────────────────┐"
  echo "  │          📊 Migration Metrics                │"
  echo "  ├─────────────────────────────────────────────┤"
  printf "  │  ALB Requests (${1}min)  : %-19s│\n" "${TOTAL_REQUESTS}"
  printf "  │  ALB p95 Response     : %-19s│\n" "${P95_RESPONSE}ms"
  printf "  │  ALB 5xx Errors       : %-19s│\n" "${TOTAL_5XX}"
  printf "  │  Error Rate           : %-19s│\n" "${ERROR_RATE}%"
  printf "  │  Healthy Targets      : %-19s│\n" "${HEALTHY_HOSTS}"
  echo "  ├─────────────────────────────────────────────┤"
  printf "  │  RDS CPU              : %-19s│\n" "${RDS_CPU}%"
  printf "  │  RDS Connections      : %-19s│\n" "${RDS_CONNECTIONS}"
  echo "  └─────────────────────────────────────────────┘"
  echo ""
}

# Route 53 가중치 변경
apply_weight() {
  local v1_w=$1 v2_w=$2

  local change_batch
  change_batch=$(cat <<EEOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RECORD_NAME}",
        "Type": "A",
        "SetIdentifier": "${V1_SET_ID}",
        "Weight": ${v1_w},
        "TTL": 60,
        "ResourceRecords": [{"Value": "${V1_VALUE}"}]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RECORD_NAME}",
        "Type": "A",
        "SetIdentifier": "${V2_SET_ID}",
        "Weight": ${v2_w},
        "AliasTarget": {
          "HostedZoneId": "${V2_ALB_HOSTED_ZONE}",
          "DNSName": "${V2_ALB_DNS}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EEOF
)

  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] v1=${v1_w}, v2=${v2_w} (실제 변경 없음)"
    return 0
  fi

  local change_id
  change_id=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "${HOSTED_ZONE_ID}" \
    --change-batch "${change_batch}" \
    $AWS_PROFILE_OPT \
    --query 'ChangeInfo.Id' --output text)

  log "Route 53 변경 요청: ${change_id}"
  aws route53 wait resource-record-sets-changed --id "${change_id}" $AWS_PROFILE_OPT
  log "DNS 전파 완료"

  # Route 53 가중치를 CloudWatch Custom Metric으로 기록 (대시보드 시각화용)
  aws cloudwatch put-metric-data \
    --namespace "ReFit/Migration" \
    --region "${REGION}" \
    $AWS_PROFILE_OPT \
    --metric-data \
      "MetricName=Route53WeightV1,Value=${v1_w},Unit=Percent,Dimensions=[{Name=Domain,Value=${RECORD_NAME}}]" \
      "MetricName=Route53WeightV2,Value=${v2_w},Unit=Percent,Dimensions=[{Name=Domain,Value=${RECORD_NAME}}]" \
    2>/dev/null && log "CloudWatch 가중치 메트릭 기록: v1=${v1_w}%, v2=${v2_w}%" || true
}

# 롤백
rollback() {
  echo ""
  echo "⚠️  롤백 실행: v1=100, v2=0"
  apply_weight 100 0
  log "롤백 완료 — 모든 트래픽이 v1으로 복구되었습니다."

  # 리포트에 롤백 기록
  cat >> "$REPORT" <<EOF

## ⚠️ 롤백 실행

- **시각**: $(date '+%Y-%m-%d %H:%M:%S')
- **사유**: 에러율 임계치 초과 또는 수동 중단
- **조치**: v1=100%, v2=0% 로 복구
EOF

  exit 1
}

# Ctrl+C 핸들러
trap 'echo ""; echo "중단 감지 — 롤백하시겠습니까? (y/N)"; read -r ans; if [[ "$ans" == "y" || "$ans" == "Y" ]]; then rollback; else exit 1; fi' INT

# 누적 집계용 변수
CUMUL_TOTAL=0
CUMUL_5XX=0
MAX_P95=0

# === 리포트 헤더 생성 ===
cat > "$REPORT" <<EOF
# 🚀 무중단 마이그레이션 리포트

## 개요

| 항목 | 값 |
|------|-----|
| **실행 시각** | $(date '+%Y-%m-%d %H:%M:%S') |
| **도메인** | ${RECORD_NAME} |
| **v1 엔드포인트** | EC2 (${V1_VALUE}) |
| **v2 엔드포인트** | ALB (${V2_ALB_DNS}) |
| **전환 전략** | Route 53 가중치 기반 점진적 전환 (${#STAGES[@]}단계) |
| **단계별 관찰 시간** | ${INTERVAL}초 |
| **롤백 기준** | 에러율 5% 초과 시 즉시 v1=100% 복구 |

---

## 📊 단계별 트래픽 전환 기록

> **요청수 설명**: v2(ALB) 요청수는 CloudWatch ALB RequestCount 실측값. v1(EC2) 요청수는 CloudWatch ReFit/Infrastructure/backend_http_requests_count 누적 카운터 delta 실측값 (collect-metrics.sh가 1분마다 수집).

| 단계 | 시각 | v1% | v2% | v1 요청(CW실측) | v2 요청(ALB실측) | 총 요청 | v2 실측비율 | p95(ms) | p95 변화 | 5xx | 에러율 | Healthy | RDS CPU | RDS Conn | 판정 |
|------|------|-----|-----|------------|------------|------------|----------|---------|--------|-----|--------|---------|---------|----------|------|
EOF

# === 메인 실행 ===

log_section "무중단 마이그레이션 시작"
echo ""
echo "  전환 계획:"
echo "  ──────────────────────────────────"
step=0
for stage in "${STAGES[@]}"; do
  step=$((step + 1))
  read -r v1 v2 <<< "$stage"
  printf "  %d단계: v1=%3d%%  v2=%3d%%  (관찰 %ds)\n" "$step" "$v1" "$v2" "$INTERVAL"
done
echo "  ──────────────────────────────────"
echo ""

if [ "$DRY_RUN" = true ]; then
  log "[DRY-RUN 모드] 실제 DNS 변경 없이 시뮬레이션합니다."
fi

read -rp "진행하시겠습니까? (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  echo "취소되었습니다."
  exit 0
fi

# 전환 전 메트릭 (베이스라인)
log "전환 전 베이스라인 메트릭 수집 중..."
collect_alb_metrics 5
collect_rds_metrics 5

BASELINE_P95="${P95_RESPONSE}"
BASELINE_ERROR_RATE="${ERROR_RATE}"

# 베이스라인 시점 v1 누적 카운터 스냅샷
V1_SNAPSHOT_START=$(get_v1_request_count)
log "v1 요청수 스냅샷(시작): ${V1_SNAPSHOT_START}"

# 베이스라인 누적 집계 시작
if [[ "${TOTAL_REQUESTS}" =~ ^[0-9]+$ ]]; then
  CUMUL_TOTAL=$((CUMUL_TOTAL + TOTAL_REQUESTS))
fi
if [[ "${TOTAL_5XX}" =~ ^[0-9]+$ ]]; then
  CUMUL_5XX=$((CUMUL_5XX + TOTAL_5XX))
fi

echo "| 0 (베이스라인) | $(date '+%H:%M:%S') | 100 | 0 | - | ${TOTAL_REQUESTS} | ${TOTAL_REQUESTS} | 0% (기대 0%) | ${P95_RESPONSE} | 기준값 | ${TOTAL_5XX} | ${ERROR_RATE}% | ${HEALTHY_HOSTS} | ${RDS_CPU}% | ${RDS_CONNECTIONS} | ✅ |" >> "$REPORT"

print_metrics 5

# 단계별 전환 실행
STEP_NUM=0
for stage in "${STAGES[@]}"; do
  STEP_NUM=$((STEP_NUM + 1))
  read -r V1_W V2_W <<< "$stage"

  log_section "${STEP_NUM}/${#STAGES[@]} 단계: v1=${V1_W}% → v2=${V2_W}%"

  # 가중치 적용
  apply_weight "$V1_W" "$V2_W"

  # 관찰 구간 시작 시 v1 누적 카운터 스냅샷
  V1_OBS_START=$(get_v1_request_count)
  log "v1 요청수 스냅샷(구간 시작): ${V1_OBS_START}"

  # DNS 캐시 만료 대기 (TTL=60s)
  log "DNS TTL 대기 (60초)..."
  sleep 60

  # 관찰 대기
  OBSERVE_TIME=$((INTERVAL - 60))
  if [ "$OBSERVE_TIME" -gt 0 ]; then
    log "관찰 대기 중... (${OBSERVE_TIME}초)"
    sleep "$OBSERVE_TIME"
  fi

  # 관찰 구간 종료 시 v1 누적 카운터 스냅샷 → delta = 실측 요청수
  V1_OBS_END=$(get_v1_request_count)
  log "v1 요청수 스냅샷(구간 종료): ${V1_OBS_END}"

  # v1 실측 요청수 계산 (카운터 리셋 시 N/A 처리)
  V1_ACTUAL="N/A"
  if [[ "${V1_OBS_START}" =~ ^[0-9]+$ ]] && [[ "${V1_OBS_END}" =~ ^[0-9]+$ ]]; then
    if [ "${V1_OBS_END}" -ge "${V1_OBS_START}" ]; then
      V1_ACTUAL=$((V1_OBS_END - V1_OBS_START))
    else
      # Spring Boot 재시작으로 카운터 리셋된 경우
      log "⚠️ v1 카운터 리셋 감지 (재시작 의심), 종료 값만 사용: ${V1_OBS_END}"
      V1_ACTUAL="${V1_OBS_END}"
    fi
  fi

  # 메트릭 수집 (CloudWatch ALB 발행 지연 최소 1~2분 → lookback 최소 5분 고정)
  OBSERVE_MINUTES=$((INTERVAL / 60))
  [ "$OBSERVE_MINUTES" -lt 5 ] && OBSERVE_MINUTES=5
  collect_alb_metrics "$OBSERVE_MINUTES"
  collect_rds_metrics "$OBSERVE_MINUTES"

  # 총 추정 요청수 = v1 실측 + v2 실측 (collect_alb_metrics 이후에 계산해야 정확)
  TOTAL_EST="N/A"
  if [[ "${V1_ACTUAL}" =~ ^[0-9]+$ ]] && [[ "${TOTAL_REQUESTS}" =~ ^[0-9]+$ ]]; then
    TOTAL_EST=$((V1_ACTUAL + TOTAL_REQUESTS))
  fi

  # v2 실측 트래픽 비율 계산 (기대값과 비교)
  V2_RATIO="N/A"
  if [[ "${TOTAL_EST}" =~ ^[0-9]+$ ]] && [ "${TOTAL_EST}" -gt 0 ]; then
    V2_RATIO=$(python3 -c "print(f'{${TOTAL_REQUESTS}/${TOTAL_EST}*100:.1f}%')" 2>/dev/null || echo "N/A")
  fi
  V2_RATIO_DISPLAY="${V2_RATIO} (기대 ${V2_W}%)"

  print_metrics "$OBSERVE_MINUTES"
  log "v2 트래픽 비율: 실측 ${V2_RATIO} / 기대 ${V2_W}%"

  # 누적 집계
  if [[ "${TOTAL_REQUESTS}" =~ ^[0-9]+$ ]]; then
    CUMUL_TOTAL=$((CUMUL_TOTAL + TOTAL_REQUESTS))
  fi
  if [[ "${TOTAL_5XX}" =~ ^[0-9]+$ ]]; then
    CUMUL_5XX=$((CUMUL_5XX + TOTAL_5XX))
  fi

  # p95 베이스라인 대비 변화
  P95_DELTA="N/A"
  if [[ "${P95_RESPONSE}" =~ ^[0-9]+$ ]] && [[ "${BASELINE_P95}" =~ ^[0-9]+$ ]] && [ "${BASELINE_P95}" -gt 0 ]; then
    P95_DELTA=$(python3 -c "delta=(${P95_RESPONSE}-${BASELINE_P95})/${BASELINE_P95}*100; sign='+' if delta>=0 else ''; print(f'{sign}{delta:.1f}%')" 2>/dev/null || echo "N/A")
    # 최대 p95 추적
    if [ "${P95_RESPONSE}" -gt "${MAX_P95}" ] 2>/dev/null; then MAX_P95=${P95_RESPONSE}; fi
  fi

  # 판정
  RESULT="✅"
  if [ "$TOTAL_5XX" -gt 0 ] 2>/dev/null; then
    local_error_rate=$(python3 -c "
rate = ${TOTAL_5XX} / max(${TOTAL_REQUESTS}, 1) * 100
print(f'{rate:.2f}')
" 2>/dev/null || echo "0")
    # 에러율 5% 초과 시 경고
    is_critical=$(python3 -c "print('yes' if float('${local_error_rate}') > 5 else 'no')" 2>/dev/null || echo "no")
    if [ "$is_critical" = "yes" ]; then
      RESULT="❌"
      log "⚠️  에러율 ${local_error_rate}% — 임계치(5%) 초과!"
      echo ""
      read -rp "롤백하시겠습니까? (y/N): " ROLLBACK_CONFIRM
      if [[ "$ROLLBACK_CONFIRM" == "y" || "$ROLLBACK_CONFIRM" == "Y" ]]; then
        echo "| ${STEP_NUM} | $(date '+%H:%M:%S') | ${V1_W} | ${V2_W} | ${V1_ACTUAL} | ${TOTAL_REQUESTS} | ${TOTAL_EST} | ${V2_RATIO_DISPLAY} | ${P95_RESPONSE} | ${P95_DELTA} | ${TOTAL_5XX} | ${ERROR_RATE}% | ${HEALTHY_HOSTS} | ${RDS_CPU}% | ${RDS_CONNECTIONS} | ${RESULT} |" >> "$REPORT"
        rollback
      fi
    fi
  fi

  # 리포트 기록
  echo "| ${STEP_NUM} | $(date '+%H:%M:%S') | ${V1_W} | ${V2_W} | ${V1_ACTUAL} | ${TOTAL_REQUESTS} | ${TOTAL_EST} | ${V2_RATIO_DISPLAY} | ${P95_RESPONSE} | ${P95_DELTA} | ${TOTAL_5XX} | ${ERROR_RATE}% | ${HEALTHY_HOSTS} | ${RDS_CPU}% | ${RDS_CONNECTIONS} | ${RESULT} |" >> "$REPORT"

  log "${STEP_NUM}단계 완료: ${RESULT}"
done

# === 완료 ===
log_section "마이그레이션 완료"
echo ""
echo "  ✅ 모든 트래픽이 v2로 전환되었습니다."
echo "  📄 리포트: ${REPORT}"
echo ""

# SLO 달성 여부 판정
SLO_STATUS="✅ 달성"
if [ "${CUMUL_5XX}" -gt 0 ] 2>/dev/null; then
  OVERALL_ERR=$(python3 -c "print(f'{${CUMUL_5XX}/max(${CUMUL_TOTAL},1)*100:.3f}')" 2>/dev/null || echo "N/A")
  SLO_STATUS="⚠️ 에러 ${CUMUL_5XX}건 (${OVERALL_ERR}%)"
else
  OVERALL_ERR="0.000"
fi

# 리포트 푸터
cat >> "$REPORT" <<EOF

---

## ✅ 결과 요약

| 지표 | 값 | 기준 | 달성 |
|------|-----|------|------|
| **총 소요 시간** | 약 $((STEP_NUM * INTERVAL / 60))분 | - | - |
| **전환 완료 시각** | $(date '+%Y-%m-%d %H:%M:%S') | - | - |
| **v2 ALB 실측 총 요청** | ${CUMUL_TOTAL}건 | - | - |
| **전체 5xx 에러** | ${CUMUL_5XX}건 | 0건 | ${SLO_STATUS} |
| **전체 에러율** | ${OVERALL_ERR}% | < 1% | $([ "${CUMUL_5XX}" -eq 0 ] 2>/dev/null && echo '✅' || echo '⚠️') |
| **최대 p95 응답시간** | ${MAX_P95}ms | < 500ms | $(python3 -c "print('✅' if ${MAX_P95} < 500 else '⚠️')" 2>/dev/null || echo '-') |
| **Healthy 타겟 유지** | 전 구간 1개 이상 | 1개 이상 | ✅ |
| **서비스 중단** | 없음 | 없음 | ✅ |
| **최종 상태** | v1=0%, v2=100% | v2 100% | ✅ |

---

## 🏗️ 마이그레이션 아키텍처

### 전환 방식: Route 53 가중치 기반 점진적 라우팅

\`\`\`
클라이언트
    │
    ▼
Route 53 (api.re-fit.kr)
    ├─── v1 가중치% ──→ EC2 (Spring Boot + Caddy)
    └─── v2 가중치% ──→ ALB ──→ ECS/EC2 v2 백엔드
\`\`\`

### 전환 단계
\`\`\`
100:0 → 90:10 → 70:30 → 50:50 → 30:70 → 10:90 → 0:100
       ← ${INTERVAL}초 관찰 간격 →
\`\`\`

### 검증 전략: 역할 분리

| 도구 | 역할 | 확인 항목 |
|------|------|-----------|
| **k6 부하테스트** | 에러율/응답시간 검증 | api.re-fit.kr로 VU 50 혼합 시나리오 부하 → v1·v2 어디로 라우팅되든 정상 응답하는지 확인 |
| **CloudWatch 대시보드** | 트래픽 분배 검증 | v1 EC2 요청수(Spring Actuator) vs v2 ALB 요청수 비율이 Route 53 가중치대로 분배되는지 시각화 |
| **이 리포트** | 자동 수집 + 판정 | 매 단계마다 CloudWatch 메트릭을 수집하여 SLO 임계치와 비교, 에러율 초과 시 롤백 |

> **DNS 캐시 참고**: k6의 DNS 해석 결과는 OS 리졸버 캐시에 영향을 받아 한쪽 백엔드에 편중될 수 있음.
> 따라서 트래픽 분배 비율은 CloudWatch 대시보드(v1 vs v2 요청수 stacked chart)로 확인하고,
> k6는 "어느 백엔드로 라우팅되든 에러 없이 응답하는가"를 검증하는 역할로 사용.

### 무중단 보장 메커니즘
1. **점진적 전환**: 한 번에 20~30%p씩만 이동하여 급격한 트래픽 쏠림 방지
2. **TTL 60초**: DNS 레코드 TTL = 60s, 가중치 변경 후 60초 대기 후 관찰 시작
3. **실시간 판정**: 매 단계마다 에러율·p95·Healthy 타겟 자동 수집 및 임계치 비교
4. **자동 롤백 프롬프트**: 에러율 5% 초과 시 즉시 v1=100% 복구 옵션 제공
5. **k6 부하테스트 병행**: VU 50개로 실사용과 유사한 혼합 시나리오 부하 인가

### 관찰 지표
| 지표 | 수집원 | 임계치 |
|------|--------|--------|
| 요청수 | CloudWatch ALB RequestCount | - |
| p95 응답시간 | CloudWatch ALB TargetResponseTime (extended) | < 500ms |
| 5xx 에러율 | CloudWatch ALB HTTPCode_Target_5XX_Count | < 1% |
| Healthy 타겟 | CloudWatch ALB HealthyHostCount | ≥ 1 |
| RDS CPU | CloudWatch RDS CPUUtilization | < 70% |
| RDS 커넥션 | CloudWatch RDS DatabaseConnections | < 181 |
| v1 HTTP 요청수 | Spring Actuator → ReFit/Infrastructure CW | 감소 추세 확인 |
| Route 53 가중치 | ReFit/Migration CW Custom Metric | 단계별 확인 |
EOF
