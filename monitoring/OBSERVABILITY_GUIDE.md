# 옵저버빌리티 스택 구축 가이드

Promtail, Loki, Prometheus, Grafana를 사용한 개발 서버 모니터링 구축 가이드입니다.

## 아키텍처 개요

### 배포 구성

```
┌─────────────────────────────────────────────────────┐
│         애플리케이션 서버 (dev.re-fit.kr)            │
│  ┌───────────────────────────────────────────────┐  │
│  │ 기존 서비스 (docker-compose)                  │  │
│  │  - Frontend (Next.js)                        │  │
│  │  - Backend (Spring Boot)                     │  │
│  │  - AI (FastAPI)                              │  │
│  │  - Postgres                                  │  │
│  │  - Caddy                                     │  │
│  └───────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────┐  │
│  │ 모니터링 에이전트 (새로 추가)                 │  │
│  │  - Promtail (로그 수집)                      │  │
│  │  - Node Exporter (시스템 메트릭)             │  │
│  │  - cAdvisor (컨테이너 메트릭)                │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                        │
                        │ logs & metrics
                        ▼
┌─────────────────────────────────────────────────────┐
│          모니터링 서버 (monitoring.re-fit.kr)         │
│  ┌───────────────────────────────────────────────┐  │
│  │  - Loki (로그 저장 및 쿼리)                   │  │
│  │  - Prometheus (메트릭 저장 및 쿼리)          │  │
│  │  - Grafana (통합 대시보드)                   │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### 데이터 흐름

1. **로그 수집**
   - Docker 컨테이너 로그 → Promtail → Loki → Grafana
   - Caddy 액세스 로그 → Promtail → Loki → Grafana

2. **메트릭 수집**
   - 시스템 메트릭 (CPU, 메모리, 디스크) → Node Exporter → Prometheus → Grafana
   - 컨테이너 메트릭 (Docker stats) → cAdvisor → Prometheus → Grafana
   - 애플리케이션 메트릭 (Spring Boot Actuator) → Prometheus → Grafana

---

## 1단계: 모니터링 서버 구축

### 1.1 Terraform으로 모니터링 서버 생성

`terraform/dev/` 디렉토리를 참고하여 새로운 EC2 인스턴스를 생성합니다.

**권장 스펙:**
- 인스턴스 타입: `t4g.medium` (2 vCPU, 4GB RAM) 또는 `t4g.large` (2 vCPU, 8GB RAM)
- 스토리지: 50GB 이상 (로그/메트릭 저장용)
- 보안 그룹:
  - Inbound: SSH (22), Grafana (3000), Prometheus (9090 - 선택), Loki (3100 - 선택)
  - 애플리케이션 서버로부터의 접근 허용

### 1.2 모니터링 서버 Docker Compose 구성

모니터링 서버에 다음 디렉토리 구조를 생성합니다:

```bash
monitoring-server/
├── docker-compose.yml
├── prometheus/
│   └── prometheus.yml
├── loki/
│   └── loki-config.yml
└── grafana/
    └── provisioning/
        ├── datasources/
        │   └── datasources.yml
        └── dashboards/
            └── dashboards.yml
```

#### `docker-compose.yml`

```yaml
version: '3.8'

services:
  # Loki - 로그 집계 및 저장
  loki:
    image: grafana/loki:2.9.3
    container_name: loki
    restart: unless-stopped
    ports:
      - "3100:3100"
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml
      - loki-data:/loki
    command: -config.file=/etc/loki/loki-config.yml
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3100/ready"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Prometheus - 메트릭 수집 및 저장
  prometheus:
    image: prom/prometheus:v2.48.0
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Grafana - 대시보드
  grafana:
    image: grafana/grafana:10.2.2
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      - loki
      - prometheus
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  loki-data:
  prometheus-data:
  grafana-data:
```

#### `loki/loki-config.yml`

```yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

# 로그 보존 기간 설정
limits_config:
  retention_period: 168h  # 7일

# 로그 압축 및 정리
compactor:
  working_directory: /loki/compactor
  shared_store: filesystem
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
```

#### `prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'refit-dev'
    environment: 'development'

# Alertmanager 설정 (선택사항)
# alerting:
#   alertmanagers:
#     - static_configs:
#         - targets: ['alertmanager:9093']

scrape_configs:
  # Prometheus 자체 메트릭
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # 애플리케이션 서버 - Node Exporter (시스템 메트릭)
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['<애플리케이션_서버_IP>:9100']
        labels:
          instance: 'refit-dev-app'

  # 애플리케이션 서버 - cAdvisor (Docker 컨테이너 메트릭)
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['<애플리케이션_서버_IP>:8080']
        labels:
          instance: 'refit-dev-app'

  # Spring Boot Actuator (백엔드 애플리케이션 메트릭)
  - job_name: 'spring-boot'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['<애플리케이션_서버_IP>:8080']
        labels:
          application: 'refit-backend'
          instance: 'refit-dev-app'

  # Postgres Exporter (선택사항)
  - job_name: 'postgres'
    static_configs:
      - targets: ['<애플리케이션_서버_IP>:9187']
        labels:
          instance: 'refit-dev-db'
```

#### `grafana/provisioning/datasources/datasources.yml`

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: true
    jsonData:
      maxLines: 1000
```

#### `grafana/provisioning/dashboards/dashboards.yml`

```yaml
apiVersion: 1

providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
```

### 1.3 모니터링 서버 실행

```bash
# 모니터링 서버에 SSH 접속
ssh -i <key>.pem ubuntu@<monitoring-server-ip>

# Docker 및 Docker Compose 설치 (필요시)
sudo apt update
sudo apt install -y docker.io docker-compose-v2

# 파일 업로드 또는 git clone으로 구성 파일 복사

# 실행
docker compose up -d

# 로그 확인
docker compose logs -f
```

---

## 2단계: 애플리케이션 서버에 모니터링 에이전트 추가

### 2.1 기존 docker-compose.yml에 에이전트 추가

기존 `docker-compose.yml`에 다음 서비스를 추가합니다:

```yaml
services:
  # ... 기존 서비스들 ...

  # Promtail - 로그 수집 에이전트
  promtail:
    image: grafana/promtail:2.9.3
    container_name: refit-promtail
    restart: unless-stopped
    volumes:
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./promtail/promtail-config.yml:/etc/promtail/promtail-config.yml:ro
    command: -config.file=/etc/promtail/promtail-config.yml
    depends_on:
      - backend
      - frontend
      - ai

  # Node Exporter - 시스템 메트릭
  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: refit-node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    command:
      - '--path.rootfs=/host'
    volumes:
      - /:/host:ro,rslave
    pid: host

  # cAdvisor - 컨테이너 메트릭
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.47.2
    container_name: refit-cadvisor
    restart: unless-stopped
    ports:
      - "8081:8080"  # 8080은 백엔드가 사용 중이므로 8081로 변경
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    privileged: true
    devices:
      - /dev/kmsg

  # Postgres Exporter (선택사항) - DB 메트릭
  postgres-exporter:
    image: prometheuscommunity/postgres-exporter:v0.15.0
    container_name: refit-postgres-exporter
    restart: unless-stopped
    ports:
      - "9187:9187"
    environment:
      DATA_SOURCE_NAME: "postgresql://${DB_USER}:${DB_PASSWORD}@db:5432/${DB_NAME}?sslmode=disable"
    depends_on:
      db:
        condition: service_healthy
```

### 2.2 Promtail 설정 파일

`promtail/promtail-config.yml` 파일을 생성합니다:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://<모니터링_서버_IP>:3100/loki/api/v1/push

scrape_configs:
  # Docker 컨테이너 로그
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'stream'
      - source_labels: ['__meta_docker_container_label_com_docker_compose_service']
        target_label: 'service'
    pipeline_stages:
      - docker: {}
      - json:
          expressions:
            level: level
            message: message
            timestamp: timestamp
      - labels:
          level:
          service:
      - timestamp:
          source: timestamp
          format: RFC3339
```

### 2.3 Spring Boot Actuator 메트릭 활성화

`application.yml` 또는 `application-secret.yml`에 다음 설정 추가:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  metrics:
    export:
      prometheus:
        enabled: true
  endpoint:
    prometheus:
      enabled: true
```

Spring Boot 프로젝트에 다음 의존성 추가 (`pom.xml` 또는 `build.gradle`):

```xml
<!-- Prometheus 메트릭 의존성 -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

### 2.4 Caddyfile 로그 레벨 조정 (선택사항)

더 상세한 로그를 수집하려면 Caddyfile의 로그 설정을 변경:

```caddyfile
dev.re-fit.kr {
    # ... 기존 설정 ...

    log {
        output stdout
        format json  # JSON 형식으로 변경하면 Loki에서 파싱 용이
        level INFO
    }
}
```

### 2.5 애플리케이션 서버 재시작

```bash
# 애플리케이션 서버에 SSH 접속
ssh -i <key>.pem ubuntu@<app-server-ip>

# 구성 파일 추가 후 재시작
docker compose up -d

# 로그 확인
docker compose logs -f promtail node-exporter cadvisor
```

---

## 3단계: 보안 그룹 설정

### 3.1 애플리케이션 서버 보안 그룹

Terraform `security-group.tf`에 다음 규칙 추가:

```hcl
# Node Exporter
resource "aws_security_group_rule" "node_exporter" {
  type              = "ingress"
  from_port         = 9100
  to_port           = 9100
  protocol          = "tcp"
  cidr_blocks       = ["<모니터링_서버_IP>/32"]  # 모니터링 서버만 허용
  security_group_id = aws_security_group.dev_sg.id
  description       = "Node Exporter metrics from monitoring server"
}

# cAdvisor
resource "aws_security_group_rule" "cadvisor" {
  type              = "ingress"
  from_port         = 8081
  to_port           = 8081
  protocol          = "tcp"
  cidr_blocks       = ["<모니터링_서버_IP>/32"]
  security_group_id = aws_security_group.dev_sg.id
  description       = "cAdvisor metrics from monitoring server"
}

# Postgres Exporter
resource "aws_security_group_rule" "postgres_exporter" {
  type              = "ingress"
  from_port         = 9187
  to_port           = 9187
  protocol          = "tcp"
  cidr_blocks       = ["<모니터링_서버_IP>/32"]
  security_group_id = aws_security_group.dev_sg.id
  description       = "Postgres Exporter metrics from monitoring server"
}
```

### 3.2 모니터링 서버 보안 그룹

모니터링 서버의 보안 그룹에 다음 규칙 추가:

```hcl
# Loki (Promtail에서 로그 전송)
resource "aws_security_group_rule" "loki" {
  type              = "ingress"
  from_port         = 3100
  to_port           = 3100
  protocol          = "tcp"
  cidr_blocks       = ["<애플리케이션_서버_IP>/32"]
  security_group_id = aws_security_group.monitoring_sg.id
  description       = "Loki from application server"
}

# Grafana (웹 UI)
resource "aws_security_group_rule" "grafana" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]  # 또는 특정 IP로 제한
  security_group_id = aws_security_group.monitoring_sg.id
  description       = "Grafana web UI"
}
```

---

## 4단계: Grafana 대시보드 설정

### 4.1 Grafana 접속

브라우저에서 `http://<모니터링_서버_IP>:3000` 접속

- 기본 로그인: `admin` / `admin` (또는 설정한 비밀번호)

### 4.2 추천 대시보드

Grafana에서 **Configuration → Data Sources**로 이동하여 Prometheus와 Loki가 연결되었는지 확인 후, 다음 대시보드를 Import:

1. **Node Exporter Full** (ID: 1860)
   - 시스템 메트릭 (CPU, 메모리, 디스크, 네트워크)

2. **Docker Container & Host Metrics** (ID: 179)
   - Docker 컨테이너 리소스 사용량

3. **Spring Boot 2.1 Statistics** (ID: 6756)
   - Spring Boot 애플리케이션 메트릭

4. **Loki Dashboard Quick Search** (ID: 12019)
   - 로그 검색 및 분석

### 4.3 커스텀 대시보드 패널 예시

**Caddy 로그 분석:**
```logql
{service="caddy"} |= "api" | json | line_format "{{.method}} {{.uri}} - {{.status}}"
```

**Backend 에러 로그:**
```logql
{service="backend"} |= "ERROR" | json | level="ERROR"
```

**컨테이너별 메모리 사용량:**
```promql
container_memory_usage_bytes{name=~"refit-.*"}
```

---

## 5단계: 알림 설정 (선택사항)

### 5.1 Prometheus Alertmanager 추가

모니터링 서버 `docker-compose.yml`에 Alertmanager 추가:

```yaml
  alertmanager:
    image: prom/alertmanager:v0.26.0
    container_name: alertmanager
    restart: unless-stopped
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml
      - alertmanager-data:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'

volumes:
  alertmanager-data:
```

### 5.2 Alertmanager 설정

`alertmanager/alertmanager.yml`:

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'discord'

receivers:
  - name: 'discord'
    webhook_configs:
      - url: '<Discord_Webhook_URL>'
        send_resolved: true
```

### 5.3 Prometheus 알림 룰 추가

`prometheus/alert-rules.yml`:

```yaml
groups:
  - name: refit-alerts
    interval: 30s
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for 5 minutes on {{ $labels.instance }}"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85% on {{ $labels.instance }}"

      - alert: ContainerDown
        expr: up{job="cadvisor"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Container exporter is down"
          description: "cAdvisor on {{ $labels.instance }} is down"

      - alert: BackendDown
        expr: up{job="spring-boot"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Backend is down"
          description: "Spring Boot application is not responding"
```

`prometheus/prometheus.yml`에 룰 파일 참조 추가:

```yaml
rule_files:
  - 'alert-rules.yml'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
```

---

## 트러블슈팅

### 1. Promtail이 로그를 수집하지 못함

**확인 사항:**
- `/var/run/docker.sock` 권한 확인
- Loki 서버 URL이 올바른지 확인
- `docker compose logs promtail`로 에러 확인

**해결:**
```bash
# Promtail 컨테이너 재시작
docker compose restart promtail
```

### 2. Prometheus가 타겟을 스크랩하지 못함

**확인 사항:**
- 보안 그룹에서 포트가 열려있는지 확인
- 애플리케이션 서버에서 `curl http://localhost:9100/metrics` 테스트
- `prometheus.yml`의 타겟 IP 확인

**해결:**
```bash
# Prometheus UI에서 Status → Targets 확인
# http://<모니터링_서버_IP>:9090/targets
```

### 3. cAdvisor ARM 호환성 문제

t4g 인스턴스(ARM)에서는 cAdvisor 이미지가 제대로 동작하지 않을 수 있습니다.

**해결:**
```yaml
cadvisor:
  image: gcr.io/cadvisor/cadvisor:v0.47.2
  platform: linux/arm64  # 명시적으로 ARM64 플랫폼 지정
```

또는 docker stats를 사용하는 대안적인 방법 고려.

---

## 다음 단계

1. **커스텀 메트릭 추가**
   - AI 서비스(FastAPI) Prometheus 메트릭 추가
   - 비즈니스 메트릭 추가 (회원가입 수, API 호출 수 등)

2. **분산 추적 (Tracing)**
   - Tempo 또는 Jaeger 추가
   - OpenTelemetry 연동

3. **로그 retention 최적화**
   - S3로 장기 보관
   - 로그 압축 및 정리 자동화

4. **고가용성 구성**
   - Loki 클러스터 구성
   - Prometheus HA 구성

---

## 참고 자료

- [Grafana Loki 공식 문서](https://grafana.com/docs/loki/latest/)
- [Prometheus 공식 문서](https://prometheus.io/docs/)
- [Promtail 설정 가이드](https://grafana.com/docs/loki/latest/clients/promtail/)
- [Spring Boot Actuator + Prometheus](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html#actuator.metrics.export.prometheus)
