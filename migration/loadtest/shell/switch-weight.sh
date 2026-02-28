#!/bin/bash
#
# Route 53 가중치 전환 스크립트
#
# 사용법: ./switch-weight.sh <v1_weight> <v2_weight>
# 예시:   ./switch-weight.sh 90 10    # v1=90%, v2=10% (카나리)
#         ./switch-weight.sh 0 100    # v2=100% (전환 완료)

set -euo pipefail

V1_WEIGHT=${1:?"Usage: $0 <v1_weight> <v2_weight>"}
V2_WEIGHT=${2:?"Usage: $0 <v1_weight> <v2_weight>"}

# === 설정 ===
HOSTED_ZONE_ID="<YOUR_HOSTED_ZONE_ID>"
RECORD_NAME="api.re-fit.kr"
V1_SET_ID="v1-weighted"
V2_SET_ID="v2-weighted"

# v1 레코드: EC2 IP (A 레코드)
V1_VALUE="<YOUR_V1_EC2_IP>"
# v2 레코드: ALB DNS (ALIAS 또는 CNAME)
V2_ALB_DNS="${V2_ALB_DNS:-<YOUR_ALB_DNS_NAME>}"
V2_ALB_HOSTED_ZONE="${V2_ALB_HOSTED_ZONE:-<YOUR_ALB_HOSTED_ZONE_ID>}"

echo "================================================"
echo "  Route 53 가중치 전환"
echo "  ${RECORD_NAME}: v1=${V1_WEIGHT}, v2=${V2_WEIGHT}"
echo "================================================"

CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RECORD_NAME}",
        "Type": "A",
        "SetIdentifier": "${V1_SET_ID}",
        "Weight": ${V1_WEIGHT},
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
        "Weight": ${V2_WEIGHT},
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

echo ""
echo "변경 내용:"
echo "${CHANGE_BATCH}" | python3 -m json.tool 2>/dev/null || echo "${CHANGE_BATCH}"
echo ""

read -rp "진행하시겠습니까? (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  echo "취소되었습니다."
  exit 0
fi

CHANGE_ID=$(aws route53 change-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --change-batch "${CHANGE_BATCH}" \
  --query 'ChangeInfo.Id' --output text)

echo ""
echo "변경 요청 완료: ${CHANGE_ID}"
echo "상태 확인 중..."

aws route53 wait resource-record-sets-changed --id "${CHANGE_ID}"
echo "DNS 전파 완료!"
echo ""
echo "현재 레코드 확인:"
aws route53 list-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --query "ResourceRecordSets[?Name=='${RECORD_NAME}.']" \
  --output table
