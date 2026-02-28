#!/bin/bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

INSTANCE_ID="<YOUR_INSTANCE_ID>"
REGION="ap-northeast-2"
NAMESPACE="ReFit/Infrastructure"

NET_STATE_FILE="/var/tmp/refit-net-counters.json"
NET_ENV_FILE="/var/tmp/refit-net.env"

get_actuator_metric() {
  local name="$1"
  local stat="${2:-VALUE}"  # Default to VALUE, can be COUNT, TOTAL_TIME, MAX, etc.
  local tags="${3:-}"       # Optional tags like "area:heap" (Spring Boot uses colon, not equals)
  local url="http://localhost:8080/actuator/metrics/${name}"
  if [ -n "$tags" ]; then
    # Convert = to : for Spring Boot Actuator tag format
    tags_fixed=$(echo "$tags" | sed 's/=/:/g')
    url="${url}?tag=${tags_fixed}"
  fi
  local resp
  resp=$(curl -s "$url" 2>/dev/null || true)
  # NOTE: `python3 -` consumes stdin as *code*, so we must use `-c` and pipe JSON into stdin.
  printf '%s' "$resp" | python3 -c "import sys, json
try:
    data = json.load(sys.stdin)
    ms = data.get('measurements', [])
    for m in ms:
        if m.get('statistic') == '${stat}':
            print(float(m.get('value', 0)))
            break
    else:
        # If stat not found, return first measurement value
        print(float(ms[0].get('value', 0)) if ms else 0)
except Exception:
    print(0)
"
}

# --- Service status (0=good, 1=bad) ---
BACKEND_STATUS=$(
  pm2 jlist 2>/dev/null \
    | python3 -c "import sys, json; data=json.load(sys.stdin); print(0 if any(p.get('name')=='backend' and p.get('pm2_env', {}).get('status')=='online' for p in data) else 1)" \
    2>/dev/null || echo 1
)
FRONTEND_STATUS=$(
  pm2 jlist 2>/dev/null \
    | python3 -c "import sys, json; data=json.load(sys.stdin); print(0 if any(p.get('name')=='frontend' and p.get('pm2_env', {}).get('status')=='online' for p in data) else 1)" \
    2>/dev/null || echo 1
)
AI_STATUS=$(
  pm2 jlist 2>/dev/null \
    | python3 -c "import sys, json; data=json.load(sys.stdin); print(0 if any(p.get('name')=='ai-service' and p.get('pm2_env', {}).get('status')=='online' for p in data) else 1)" \
    2>/dev/null || echo 1
)

BACKEND_HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://re-fit.kr/actuator/health 2>/dev/null || echo "000")
BACKEND_HEALTH_STATUS=$([ "$BACKEND_HEALTH_CODE" = "200" ] && echo 0 || echo 1)

FRONTEND_HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
FRONTEND_HEALTH_STATUS=$([ "$FRONTEND_HEALTH_CODE" = "200" ] && echo 0 || echo 1)

AI_HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health 2>/dev/null || echo "000")
AI_HEALTH_STATUS=$([ "$AI_HEALTH_CODE" = "200" ] && echo 0 || echo 1)

# --- Memory (MB) ---
BACKEND_MEM=$(
  pm2 jlist 2>/dev/null \
    | python3 -c "import sys, json; data=json.load(sys.stdin); mem=next((p.get('monit', {}).get('memory', 0) for p in data if p.get('name')=='backend'), 0); print(int(mem/1024/1024))" \
    2>/dev/null || echo 0
)
FRONTEND_MEM=$(
  pm2 jlist 2>/dev/null \
    | python3 -c "import sys, json; data=json.load(sys.stdin); mem=next((p.get('monit', {}).get('memory', 0) for p in data if p.get('name')=='frontend'), 0); print(int(mem/1024/1024))" \
    2>/dev/null || echo 0
)
AI_MEM=$(
  pm2 jlist 2>/dev/null \
    | python3 -c "import sys, json; data=json.load(sys.stdin); mem=next((p.get('monit', {}).get('memory', 0) for p in data if p.get('name')=='ai-service'), 0); print(int(mem/1024/1024))" \
    2>/dev/null || echo 0
)

# --- Restart count (cumulative) ---
BACKEND_RESTARTS=$(
  pm2 jlist 2>/dev/null \
    | python3 -c "import sys, json; data=json.load(sys.stdin); restarts=next((p.get('pm2_env', {}).get('restart_time', 0) for p in data if p.get('name')=='backend'), 0); print(restarts)" \
    2>/dev/null || echo 0
)
FRONTEND_RESTARTS=$(
  pm2 jlist 2>/dev/null \
    | python3 -c "import sys, json; data=json.load(sys.stdin); restarts=next((p.get('pm2_env', {}).get('restart_time', 0) for p in data if p.get('name')=='frontend'), 0); print(restarts)" \
    2>/dev/null || echo 0
)
AI_RESTARTS=$(
  pm2 jlist 2>/dev/null \
    | python3 -c "import sys, json; data=json.load(sys.stdin); restarts=next((p.get('pm2_env', {}).get('restart_time', 0) for p in data if p.get('name')=='ai-service'), 0); print(restarts)" \
    2>/dev/null || echo 0
)

# --- Caddy (0=active, 1=down) ---
if systemctl is-active --quiet caddy 2>/dev/null; then
  CADDY_STATUS=0
else
  CADDY_STATUS=1
fi

# --- Backend HTTP metrics (Spring Boot) ---
# HTTP 요청 수 (전체, 누적 카운터)
HTTP_REQUESTS_COUNT=$(get_actuator_metric http.server.requests COUNT)
# HTTP 응답 시간 (총 누적 시간 / 최대 응답 시간, 초 단위)
HTTP_REQUESTS_TIME_TOTAL=$(get_actuator_metric http.server.requests TOTAL_TIME)
HTTP_REQUESTS_TIME_MAX=$(get_actuator_metric http.server.requests MAX)
# HTTP 에러 수 (5xx)
HTTP_5XX_COUNT=$(curl -s "http://localhost:8080/actuator/metrics/http.server.requests?tag=status:5xx" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); ms=d.get('measurements',[]); print(sum(m.get('value',0) for m in ms if m.get('statistic')=='COUNT'))" 2>/dev/null || echo 0)
# HTTP 활성 요청 수
HTTP_REQUESTS_ACTIVE=$(get_actuator_metric http.server.requests.active)
# 최근 수집 주기(예: 1분) 동안의 평균 응답 시간(ms) - 누적 카운터에서 delta 계산
HTTP_LATENCY_AVG_MS=$(
python3 <<PY
import json
from pathlib import Path

state_path = Path("/var/tmp/refit-http-latency.json")
try:
    prev = json.loads(state_path.read_text())
except Exception:
    prev = {"count": 0.0, "total": 0.0}

try:
    cur_count = float("${HTTP_REQUESTS_COUNT:-0}")
except Exception:
    cur_count = 0.0
try:
    cur_total = float("${HTTP_REQUESTS_TIME_TOTAL:-0}")
except Exception:
    cur_total = 0.0

delta_count = cur_count - float(prev.get("count", 0.0))
delta_total = cur_total - float(prev.get("total", 0.0))

if delta_count <= 0 or delta_total < 0:
    avg_ms = 0.0
else:
    # Actuator는 초(Seconds) 단위로 제공하므로 ms로 변환
    avg_ms = (delta_total / delta_count) * 1000.0

state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text(json.dumps({"count": cur_count, "total": cur_total}))

print(int(avg_ms))
PY
)

# --- Backend JVM metrics (Spring Boot) ---
# GC 시간 (총 GC 시간)
JVM_GC_TIME_TOTAL=$(get_actuator_metric jvm.gc.pause TOTAL_TIME)
# 힙 사용량 (MB) - Python으로 계산
JVM_HEAP_USED=$(get_actuator_metric jvm.memory.used VALUE "area:heap")
JVM_HEAP_MAX=$(get_actuator_metric jvm.memory.max VALUE "area:heap")
JVM_HEAP_CALC=$(python3 <<PY
used = ${JVM_HEAP_USED:-0}
max = ${JVM_HEAP_MAX:-0}
used_mb = int(used / 1024 / 1024)
max_mb = int(max / 1024 / 1024)
pct = int(used * 100 / max) if max > 0 else 0
print(f"{used_mb},{max_mb},{pct}")
PY
)
JVM_HEAP_USED_MB=$(echo "$JVM_HEAP_CALC" | cut -d',' -f1)
JVM_HEAP_MAX_MB=$(echo "$JVM_HEAP_CALC" | cut -d',' -f2)
JVM_HEAP_USAGE_PCT=$(echo "$JVM_HEAP_CALC" | cut -d',' -f3)
# 스레드 수
JVM_THREADS_LIVE=$(get_actuator_metric jvm.threads.live)

# --- Backend DB pool (hikaricp.*) ---
DB_ACTIVE=$(get_actuator_metric hikaricp.connections.active)
DB_IDLE=$(get_actuator_metric hikaricp.connections.idle)
DB_PENDING=$(get_actuator_metric hikaricp.connections.pending)
DB_TIMEOUT=$(get_actuator_metric hikaricp.connections.timeout)
DB_POOL=$(get_actuator_metric hikaricp.connections)
DB_MAX=$(get_actuator_metric hikaricp.connections.max)
DB_MIN=$(get_actuator_metric hikaricp.connections.min)
# Connection acquire metrics (connection 획득 시간/횟수 - 읽기/쓰기 활동의 대리 지표)
DB_ACQUIRE_COUNT=$(get_actuator_metric hikaricp.connections.acquire COUNT)
DB_ACQUIRE_TIME_MAX=$(get_actuator_metric hikaricp.connections.acquire MAX)
# Connection usage metrics (connection 사용 횟수/시간 - 실제 DB 작업 활동)
DB_USAGE_COUNT=$(get_actuator_metric hikaricp.connections.usage COUNT)
DB_USAGE_TIME_TOTAL=$(get_actuator_metric hikaricp.connections.usage TOTAL_TIME)
# Connection creation metrics (새 connection 생성 - 풀 확장/재연결)
DB_CREATION_COUNT=$(get_actuator_metric hikaricp.connections.creation COUNT)
DB_CREATION_TIME_MAX=$(get_actuator_metric hikaricp.connections.creation MAX)

# --- Per-service network bytes/packets in/out (delta since last run) ---
python3 - <<'PY' > "$NET_ENV_FILE"
import json, subprocess, re
from pathlib import Path

state_path = Path("/var/tmp/refit-net-counters.json")

keys = [
    "refit-port-8080-in","refit-port-8080-out",
    "refit-port-3000-in","refit-port-3000-out",
    "refit-port-8000-in","refit-port-8000-out",
]

try:
    out = subprocess.check_output(["sudo","-n","iptables-save","-c"], text=True)
except Exception:
    out = ""

rule_re = re.compile(
    r'^\\[(\\d+):(\\d+)\\]\\s+-A\\s+(?:REFIT_IN|REFIT_OUT)\\s+.*--(?:dport|sport)\\s+\\d+.*--comment\\s+\\"(refit-port-\\d+-(?:in|out))\\"',
    re.IGNORECASE,
)

cur = {}
for line in out.splitlines():
    m = rule_re.search(line)
    if not m:
        continue
    pkts, byt, comment = m.groups()
    cur[comment] = {"packets": int(pkts), "bytes": int(byt)}

prev = {}
if state_path.exists():
    try:
        prev = json.loads(state_path.read_text())
    except Exception:
        prev = {}

name_map = {
    "refit-port-8080-in": ("BACKEND_NET_PKTS_IN","BACKEND_NET_BYTES_IN"),
    "refit-port-8080-out": ("BACKEND_NET_PKTS_OUT","BACKEND_NET_BYTES_OUT"),
    "refit-port-3000-in": ("FRONTEND_NET_PKTS_IN","FRONTEND_NET_BYTES_IN"),
    "refit-port-3000-out": ("FRONTEND_NET_PKTS_OUT","FRONTEND_NET_BYTES_OUT"),
    "refit-port-8000-in": ("AI_NET_PKTS_IN","AI_NET_BYTES_IN"),
    "refit-port-8000-out": ("AI_NET_PKTS_OUT","AI_NET_BYTES_OUT"),
}

def delta(key: str):
    c = cur.get(key, {"packets": 0, "bytes": 0})
    p = prev.get(key, {"packets": 0, "bytes": 0})
    dp = c["packets"] - int(p.get("packets", 0))
    db = c["bytes"] - int(p.get("bytes", 0))
    return max(dp, 0), max(db, 0)

for k in keys:
    dp, db = delta(k)
    pvar, bvar = name_map[k]
    print(f"{pvar}={dp}")
    print(f"{bvar}={db}")

state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text(json.dumps(cur))
PY

# shellcheck disable=SC1090
source "$NET_ENV_FILE"

: "${BACKEND_NET_PKTS_IN:=0}"; : "${BACKEND_NET_PKTS_OUT:=0}"; : "${BACKEND_NET_BYTES_IN:=0}"; : "${BACKEND_NET_BYTES_OUT:=0}"
: "${FRONTEND_NET_PKTS_IN:=0}"; : "${FRONTEND_NET_PKTS_OUT:=0}"; : "${FRONTEND_NET_BYTES_IN:=0}"; : "${FRONTEND_NET_BYTES_OUT:=0}"
: "${AI_NET_PKTS_IN:=0}"; : "${AI_NET_PKTS_OUT:=0}"; : "${AI_NET_BYTES_IN:=0}"; : "${AI_NET_BYTES_OUT:=0}"

# PutMetricData (<=20 per call) - split into 3 calls
aws cloudwatch put-metric-data --namespace "$NAMESPACE" --region "$REGION" --metric-data \
  "MetricName=backend_process_status,Value=$BACKEND_STATUS,Unit=None,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=frontend_process_status,Value=$FRONTEND_STATUS,Unit=None,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=ai_service_process_status,Value=$AI_STATUS,Unit=None,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_health_status,Value=$BACKEND_HEALTH_STATUS,Unit=None,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=frontend_health_status,Value=$FRONTEND_HEALTH_STATUS,Unit=None,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=ai_service_health_status,Value=$AI_HEALTH_STATUS,Unit=None,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_memory_usage,Value=$BACKEND_MEM,Unit=Megabytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=frontend_memory_usage,Value=$FRONTEND_MEM,Unit=Megabytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=ai_service_memory_usage,Value=$AI_MEM,Unit=Megabytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_restart_count,Value=$BACKEND_RESTARTS,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=frontend_restart_count,Value=$FRONTEND_RESTARTS,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=ai_service_restart_count,Value=$AI_RESTARTS,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=caddy_service_status,Value=$CADDY_STATUS,Unit=None,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]"

aws cloudwatch put-metric-data --namespace "$NAMESPACE" --region "$REGION" --metric-data \
  "MetricName=backend_http_requests_count,Value=$HTTP_REQUESTS_COUNT,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_http_latency_avg_ms,Value=$HTTP_LATENCY_AVG_MS,Unit=Milliseconds,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_http_requests_time_max,Value=$HTTP_REQUESTS_TIME_MAX,Unit=Seconds,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_http_5xx_count,Value=$HTTP_5XX_COUNT,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_http_requests_active,Value=$HTTP_REQUESTS_ACTIVE,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_jvm_gc_time_total,Value=$JVM_GC_TIME_TOTAL,Unit=Seconds,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_jvm_heap_used_mb,Value=$JVM_HEAP_USED_MB,Unit=Megabytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_jvm_heap_max_mb,Value=$JVM_HEAP_MAX_MB,Unit=Megabytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_jvm_heap_usage_percent,Value=$JVM_HEAP_USAGE_PCT,Unit=Percent,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_jvm_threads_live,Value=$JVM_THREADS_LIVE,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]"

aws cloudwatch put-metric-data --namespace "$NAMESPACE" --region "$REGION" --metric-data \
  "MetricName=backend_db_active_connections,Value=$DB_ACTIVE,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_idle_connections,Value=$DB_IDLE,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_pending_connections,Value=$DB_PENDING,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_timeout_count,Value=$DB_TIMEOUT,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_pool_size,Value=$DB_POOL,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_max_connections,Value=$DB_MAX,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_min_connections,Value=$DB_MIN,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_connection_acquire_count,Value=$DB_ACQUIRE_COUNT,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_connection_acquire_time_max,Value=$DB_ACQUIRE_TIME_MAX,Unit=Seconds,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_connection_usage_count,Value=$DB_USAGE_COUNT,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_connection_usage_time_total,Value=$DB_USAGE_TIME_TOTAL,Unit=Seconds,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_connection_creation_count,Value=$DB_CREATION_COUNT,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_db_connection_creation_time_max,Value=$DB_CREATION_TIME_MAX,Unit=Seconds,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]"

aws cloudwatch put-metric-data --namespace "$NAMESPACE" --region "$REGION" --metric-data \
  "MetricName=backend_net_bytes_in,Value=$BACKEND_NET_BYTES_IN,Unit=Bytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_net_bytes_out,Value=$BACKEND_NET_BYTES_OUT,Unit=Bytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_net_packets_in,Value=$BACKEND_NET_PKTS_IN,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=backend_net_packets_out,Value=$BACKEND_NET_PKTS_OUT,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=frontend_net_bytes_in,Value=$FRONTEND_NET_BYTES_IN,Unit=Bytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=frontend_net_bytes_out,Value=$FRONTEND_NET_BYTES_OUT,Unit=Bytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=frontend_net_packets_in,Value=$FRONTEND_NET_PKTS_IN,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=frontend_net_packets_out,Value=$FRONTEND_NET_PKTS_OUT,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=ai_service_net_bytes_in,Value=$AI_NET_BYTES_IN,Unit=Bytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=ai_service_net_bytes_out,Value=$AI_NET_BYTES_OUT,Unit=Bytes,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=ai_service_net_packets_in,Value=$AI_NET_PKTS_IN,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]" \
  "MetricName=ai_service_net_packets_out,Value=$AI_NET_PKTS_OUT,Unit=Count,Dimensions=[{Name=InstanceId,Value=$INSTANCE_ID}]"