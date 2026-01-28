#!/bin/bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

INSTANCE_ID="i-00fc6ef034cf67de7"
REGION="ap-northeast-2"
NAMESPACE="ReFit/Infrastructure"

NET_STATE_FILE="/var/tmp/refit-net-counters.json"
NET_ENV_FILE="/var/tmp/refit-net.env"

get_actuator_metric() {
  local name="$1"
  local stat="${2:-VALUE}"  # Default to VALUE, can be COUNT, TOTAL_TIME, MAX, etc.
  local resp
  resp=$(curl -s "http://localhost:8080/actuator/metrics/${name}" 2>/dev/null || true)
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
