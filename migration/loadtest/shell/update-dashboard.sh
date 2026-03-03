#!/bin/bash
#
# CloudWatch 대시보드 업데이트 스크립트
# 무중단 마이그레이션 모니터링에 필요한 위젯을 추가합니다.
#
# 사용법: ./update-dashboard.sh

set -euo pipefail

DASHBOARD_NAME="LB-Migration-Monitor"
REGION="ap-northeast-2"
ALB_ID="app/<YOUR_ALB_NAME>/<YOUR_ALB_ID>"
TG_ID="targetgroup/<YOUR_TG_NAME>/<YOUR_TG_ID>"
RDS_ID="refit-postgres"

DASHBOARD_BODY=$(cat <<'EODASH'
{
  "widgets": [
    {
      "type": "text",
      "x": 0, "y": 0, "width": 24, "height": 1,
      "properties": {
        "markdown": "# 🔄 v1→v2 무중단 마이그레이션 모니터링"
      }
    },

    {
      "type": "text",
      "x": 0, "y": 1, "width": 24, "height": 1,
      "properties": {
        "markdown": "### ALB (v2) — 트래픽 & 에러"
      }
    },

    {
      "type": "metric",
      "x": 0, "y": 2, "width": 6, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "ALB_ID_PLACEHOLDER"]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "요청 수 (v2 ALB)", "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 6, "y": 2, "width": 6, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", "ALB_ID_PLACEHOLDER", {"label": "2xx", "color": "#2ca02c"}],
          [".", "HTTPCode_Target_4XX_Count", ".", ".", {"label": "4xx", "color": "#ff7f0e"}],
          [".", "HTTPCode_Target_5XX_Count", ".", ".", {"label": "5xx", "color": "#d62728"}]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "HTTP 응답 코드 분포", "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 2, "width": 6, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "ALB_ID_PLACEHOLDER", {"label": "p50", "stat": "p50"}],
          ["...", {"label": "p95", "stat": "p95"}],
          ["...", {"label": "p99", "stat": "p99"}]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "응답시간 (p50/p95/p99)",
        "yAxis": {"left": {"label": "초"}}
      }
    },
    {
      "type": "metric",
      "x": 18, "y": 2, "width": 3, "height": 3,
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", "TG_ID_PLACEHOLDER", "LoadBalancer", "ALB_ID_PLACEHOLDER"]
        ],
        "sparkline": true,
        "view": "singleValue",
        "region": "ap-northeast-2",
        "title": "Healthy 타겟", "stat": "Minimum", "period": 60
      }
    },
    {
      "type": "metric",
      "x": 21, "y": 2, "width": 3, "height": 3,
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", "TG_ID_PLACEHOLDER", "LoadBalancer", "ALB_ID_PLACEHOLDER"]
        ],
        "sparkline": true,
        "view": "singleValue",
        "region": "ap-northeast-2",
        "title": "Unhealthy 타겟", "stat": "Maximum", "period": 60
      }
    },
    {
      "type": "metric",
      "x": 18, "y": 5, "width": 6, "height": 3,
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "ActiveConnectionCount", "LoadBalancer", "ALB_ID_PLACEHOLDER", {"label": "Active"}],
          [".", "NewConnectionCount", ".", ".", {"label": "New"}]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "커넥션 수", "stat": "Sum"
      }
    },

    {
      "type": "text",
      "x": 0, "y": 8, "width": 24, "height": 1,
      "properties": {
        "markdown": "### ALB 에러 상세 & 타겟 연결"
      }
    },

    {
      "type": "metric",
      "x": 0, "y": 9, "width": 8, "height": 5,
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "HTTPCode_ELB_502_Count", "LoadBalancer", "ALB_ID_PLACEHOLDER", {"label": "502 Bad Gateway", "color": "#d62728"}],
          [".", "HTTPCode_ELB_503_Count", ".", ".", {"label": "503 Unavailable", "color": "#ff7f0e"}],
          [".", "HTTPCode_ELB_504_Count", ".", ".", {"label": "504 Timeout", "color": "#9467bd"}]
        ],
        "view": "timeSeries", "stacked": true,
        "region": "ap-northeast-2", "period": 60,
        "title": "ALB 자체 5xx 에러 (502/503/504)", "stat": "Sum",
        "annotations": {
          "horizontal": [{"label": "Alert", "value": 1, "color": "#d62728"}]
        }
      }
    },
    {
      "type": "metric",
      "x": 8, "y": 9, "width": 8, "height": 5,
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "TargetConnectionErrorCount", "LoadBalancer", "ALB_ID_PLACEHOLDER"]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "타겟 연결 에러", "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 16, "y": 9, "width": 8, "height": 5,
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", "ALB_ID_PLACEHOLDER", {"label": "Target 5xx"}],
          [".", "HTTPCode_ELB_5XX_Count", ".", ".", {"label": "ELB 5xx"}]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "5xx 비교 (Target vs ELB)", "stat": "Sum"
      }
    },

    {
      "type": "text",
      "x": 0, "y": 14, "width": 24, "height": 1,
      "properties": {
        "markdown": "### RDS (v1 DB) — 마이그레이션 중 DB 부하"
      }
    },

    {
      "type": "metric",
      "x": 0, "y": 15, "width": 6, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "RDS_ID_PLACEHOLDER"]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "RDS CPU 사용률",
        "annotations": {
          "horizontal": [{"label": "Warning 70%", "value": 70, "color": "#ff7f0e"}, {"label": "Critical 90%", "value": 90, "color": "#d62728"}]
        }
      }
    },
    {
      "type": "metric",
      "x": 6, "y": 15, "width": 6, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "RDS_ID_PLACEHOLDER"]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "RDS 커넥션 수",
        "annotations": {
          "horizontal": [{"label": "max_connections", "value": 181, "color": "#d62728"}]
        }
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 15, "width": 6, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", "RDS_ID_PLACEHOLDER", {"label": "Read Latency"}],
          [".", "WriteLatency", ".", ".", {"label": "Write Latency"}]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "RDS Read/Write Latency",
        "yAxis": {"left": {"label": "초"}}
      }
    },
    {
      "type": "metric",
      "x": 18, "y": 15, "width": 6, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", "RDS_ID_PLACEHOLDER"]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "RDS 가용 메모리",
        "yAxis": {"left": {"label": "Bytes"}}
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 21, "width": 8, "height": 5,
      "properties": {
        "metrics": [
          ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", "RDS_ID_PLACEHOLDER", {"label": "Read IOPS"}],
          [".", "WriteIOPS", ".", ".", {"label": "Write IOPS"}]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "RDS IOPS", "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 8, "y": 21, "width": 8, "height": 5,
      "properties": {
        "metrics": [
          ["AWS/RDS", "NetworkReceiveThroughput", "DBInstanceIdentifier", "RDS_ID_PLACEHOLDER", {"label": "Receive"}],
          [".", "NetworkTransmitThroughput", ".", ".", {"label": "Transmit"}]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "RDS 네트워크 처리량", "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 16, "y": 21, "width": 8, "height": 5,
      "properties": {
        "metrics": [
          ["AWS/RDS", "DiskQueueDepth", "DBInstanceIdentifier", "RDS_ID_PLACEHOLDER"]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "RDS Disk Queue Depth", "stat": "Average"
      }
    },
    {
      "type": "text",
      "x": 0, "y": 26, "width": 24, "height": 1,
      "properties": {
        "markdown": "### 🔀 Route 53 가중치 전환 현황"
      }
    },

    {
      "type": "metric",
      "x": 0, "y": 27, "width": 12, "height": 6,
      "properties": {
        "metrics": [
          ["ReFit/Migration", "Route53WeightV1", "Domain", "api.re-fit.kr", {"label": "v1 (EC2) 가중치 %", "color": "#1f77b4"}],
          [".", "Route53WeightV2", ".", ".", {"label": "v2 (ALB) 가중치 %", "color": "#2ca02c"}]
        ],
        "view": "timeSeries", "stacked": false,
        "region": "ap-northeast-2", "period": 60,
        "title": "Route 53 가중치 변화 (v1 vs v2)",
        "stat": "Maximum",
        "yAxis": {
          "left": {"min": 0, "max": 100, "label": "%"}
        },
        "annotations": {
          "horizontal": [
            {"label": "50:50", "value": 50, "color": "#ff7f0e"}
          ]
        }
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 27, "width": 12, "height": 6,
      "properties": {
        "metrics": [
          ["ReFit/Migration", "Route53WeightV1", "Domain", "api.re-fit.kr", {"label": "v1 가중치 %", "color": "#1f77b4", "stat": "Maximum"}],
          [".", "Route53WeightV2", ".", ".", {"label": "v2 가중치 %", "color": "#2ca02c", "stat": "Maximum"}]
        ],
        "view": "singleValue",
        "region": "ap-northeast-2", "period": 300,
        "title": "현재 가중치 (최근 5분)",
        "stat": "Maximum",
        "sparkline": true
      }
    },

    {
      "type": "text",
      "x": 0, "y": 33, "width": 24, "height": 1,
      "properties": {
        "markdown": "### 📊 v1 (EC2) vs v2 (ALB) 실시간 트래픽 분배"
      }
    },

    {
      "type": "metric",
      "x": 0, "y": 34, "width": 16, "height": 7,
      "properties": {
        "metrics": [
          [{"expression": "IF(DIFF(m1)>0, DIFF(m1), 0)", "label": "v1 EC2 요청수 (분당)", "id": "e1", "color": "#1f77b4", "period": 60}],
          [{"expression": "m2", "label": "v2 ALB 요청수 (분당)", "id": "e2", "color": "#2ca02c", "period": 60}],
          ["ReFit/Infrastructure", "backend_http_requests_count", "InstanceId", "<YOUR_INSTANCE_ID>", {"id": "m1", "visible": false, "stat": "Maximum", "period": 60}],
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "ALB_ID_PLACEHOLDER", {"id": "m2", "visible": false, "stat": "Sum", "period": 60}]
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "ap-northeast-2",
        "period": 60,
        "title": "v1 vs v2 분당 요청수 (stacked — 합계가 총 처리량)",
        "stat": "Sum",
        "yAxis": {"left": {"label": "요청 수 / 분", "min": 0}},
        "legend": {"position": "bottom"},
        "annotations": {
          "horizontal": [
            {"label": "기준선", "value": 0, "color": "#888888"}
          ]
        }
      }
    },

    {
      "type": "metric",
      "x": 16, "y": 34, "width": 8, "height": 7,
      "properties": {
        "metrics": [
          [{"expression": "IF(DIFF(m1)>0, DIFF(m1), 0)", "label": "v1 요청/분", "id": "e1", "color": "#1f77b4", "period": 60}],
          [{"expression": "m2",              "label": "v2 요청/분", "id": "e2", "color": "#2ca02c", "period": 60}],
          [{"expression": "IF(IF(DIFF(m1)>0,DIFF(m1),0)+m2 > 0, m2/(IF(DIFF(m1)>0,DIFF(m1),0)+m2)*100, 0)", "label": "v2 비율 %", "id": "e3", "color": "#ff7f0e", "period": 60}],
          ["ReFit/Infrastructure", "backend_http_requests_count", "InstanceId", "<YOUR_INSTANCE_ID>", {"id": "m1", "visible": false, "stat": "Maximum", "period": 60}],
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "ALB_ID_PLACEHOLDER", {"id": "m2", "visible": false, "stat": "Sum", "period": 60}]
        ],
        "view": "singleValue",
        "region": "ap-northeast-2",
        "period": 300,
        "title": "현재 요청 분배 (최근 5분)",
        "stat": "Sum",
        "sparkline": true
      }
    }
  ]
}
EODASH
)

# 플레이스홀더 치환
DASHBOARD_BODY=$(echo "$DASHBOARD_BODY" | sed \
  -e "s|ALB_ID_PLACEHOLDER|${ALB_ID}|g" \
  -e "s|TG_ID_PLACEHOLDER|${TG_ID}|g" \
  -e "s|RDS_ID_PLACEHOLDER|${RDS_ID}|g")

echo "대시보드 '${DASHBOARD_NAME}' 업데이트 중..."
echo "$DASHBOARD_BODY" | python3 -m json.tool > /dev/null 2>&1 || { echo "JSON 검증 실패"; exit 1; }

aws cloudwatch put-dashboard \
  --dashboard-name "$DASHBOARD_NAME" \
  --dashboard-body "$DASHBOARD_BODY" \
  --region "$REGION" \
  --profile refit-ssm

echo ""
echo "✅ 대시보드 업데이트 완료!"
echo ""
echo "변경 사항:"
echo "  [추가] HTTP 응답 코드 분포 (2xx/4xx/5xx)"
echo "  [추가] 응답시간 p50/p95/p99 비교"
echo "  [추가] Unhealthy 타겟 수"
echo "  [추가] ALB 502/503/504 에러 상세"
echo "  [추가] 타겟 연결 에러"
echo "  [추가] 5xx 비교 (Target vs ELB)"
echo "  [추가] RDS Read/Write Latency"
echo "  [추가] RDS 네트워크 처리량"
echo "  [추가] RDS Disk Queue Depth"
echo "  [추가] Route 53 가중치 변화 (v1 vs v2 시계열 + 현재 가중치 단일값)"
echo "  [추가] v1 EC2 HTTP 요청수 (Spring Actuator 기반)"
echo "  [추가] v2 ALB HTTP 요청수"
echo "  [개선] 섹션별 구분 + 경고 임계선 추가"
