#!/bin/bash
#
# 긴급 롤백 스크립트 — v1=100%, v2=0%로 즉시 전환
#
# 사용법: ./rollback.sh
# 또는:   ./rollback.sh --force  (확인 없이 즉시 실행)

set -euo pipefail

FORCE=${1:-""}

# === 설정 ===
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:?Set HOSTED_ZONE_ID env var}"
RECORD_NAME="api.re-fit.kr"
V1_SET_ID="v1-weighted"
V2_SET_ID="v2-weighted"

V1_VALUE="${V1_RECORD_VALUE:?Set V1_RECORD_VALUE env var}"
V2_ALB_DNS="${V2_ALB_DNS:-<YOUR_ALB_DNS_NAME>}"
V2_ALB_HOSTED_ZONE="${V2_ALB_HOSTED_ZONE:-<YOUR_ALB_HOSTED_ZONE_ID>}"

echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "  긴급 롤백: v1=100%, v2=0%"
echo "  ${RECORD_NAME} → 모든 트래픽 v1으로 전환"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

if [[ "${FORCE}" != "--force" ]]; then
  read -rp "정말 롤백하시겠습니까? (y/N): " CONFIRM
  if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "취소되었습니다."
    exit 0
  fi
fi

CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RECORD_NAME}",
        "Type": "A",
        "SetIdentifier": "${V1_SET_ID}",
        "Weight": 100,
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
        "Weight": 0,
        "AliasTarget": {
          "HostedZoneId": "${V2_ALB_HOSTED_ZONE}",
          "DNSName": "${V2_ALB_DNS}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF
)

CHANGE_ID=$(aws route53 change-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --change-batch "${CHANGE_BATCH}" \
  --query 'ChangeInfo.Id' --output text)

echo ""
echo "롤백 요청 완료: ${CHANGE_ID}"
echo "DNS 전파 대기 중..."

aws route53 wait resource-record-sets-changed --id "${CHANGE_ID}"

echo ""
echo "롤백 완료! 모든 트래픽이 v1으로 전환되었습니다."
echo ""
echo "현재 레코드 확인:"
aws route53 list-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --query "ResourceRecordSets[?Name=='${RECORD_NAME}.']" \
  --output table
