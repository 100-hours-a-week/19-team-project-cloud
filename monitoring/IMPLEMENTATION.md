# 모니터링 인프라 구축 완료 문서

## 📋 프로젝트 개요

Re:fit 개발 환경에 옵저버빌리티 스택을 추가하여 로그 수집, 메트릭 모니터링, 시각화 기능을 구현했습니다.

- **구축 일자**: 2026-02-10
- **아키텍처**: 별도 모니터링 서버 패턴 (Application Server + Monitoring Server)
- **기술 스택**: Promtail, Loki, Prometheus, Grafana
- **인프라**: AWS EC2, Terraform

---

## 🏗️ 아키텍처

```
┌─────────────────────────────────────┐
│   Application Server (t4g.large)    │
│   IP: 43.200.140.74 (Public)        │
│       10.1.1.193 (Private)          │
├─────────────────────────────────────┤
│  Application Services:              │
│  - Frontend (Next.js)               │
│  - Backend (Spring Boot)            │
│  - AI Service (Python)              │
│  - PostgreSQL                       │
│  - Caddy (Reverse Proxy)            │
├─────────────────────────────────────┤
│  Monitoring Agents:                 │
│  - Promtail (로그 수집)              │
│  - Node Exporter (시스템 메트릭)     │
│  - cAdvisor (컨테이너 메트릭)        │
│  - Postgres Exporter (DB 메트릭)    │
└─────────────────────────────────────┘
            │
            │ Metrics/Logs
            ↓
┌─────────────────────────────────────┐
│  Monitoring Server (t4g.medium)     │
│  IP: 54.180.38.125 (Public)         │
│      10.1.2.163 (Private)           │
├─────────────────────────────────────┤
│  - Loki (로그 저장소)                │
│  - Prometheus (메트릭 저장소)        │
│  - Grafana (시각화)                  │
└─────────────────────────────────────┘
```

---

## ✅ 완료된 작업

### 1단계: Terraform 인프라 구축

#### 생성된 리소스
- **EC2 Instance**: t4g.medium (ARM64), 50GB EBS (암호화)
- **Subnet**: 10.1.2.0/24 (monitoring-subnet)
- **Security Group**: monitoring-sg
  - SSH (22): 제한된 IP
  - Grafana (3000): 0.0.0.0/0 (공개)
  - Loki (3100): 10.1.1.193/32 (App Server만)
  - Prometheus (9090): 비활성화
- **Elastic IP**: 54.180.38.125
- **Route Table**: 인터넷 게이트웨이 연결

#### Terraform 파일 구조
```
terraform/monitoring-dev/
├── backend.tf           # S3 backend 설정 (key: monitoring-dev/terraform.tfstate)
├── data.tf             # VPC, IGW, AMI 데이터 소스
├── ec2.tf              # EC2 인스턴스 정의
├── vpc.tf              # Subnet, Route Table
├── security-group.tf   # Security Group 규칙
├── iam.tf              # IAM Role, Policy
├── outputs.tf          # 출력 변수
├── provider.tf         # AWS Provider 설정
└── variables.tf        # 입력 변수
```

#### 발생한 이슈 및 해결
1. **DynamoDB 테이블 이름 오류**
   - 문제: `refit-terraform-locks` vs `refit-terraform-lock`
   - 해결: backend.tf 수정 후 `terraform init -reconfigure`

2. **VPC 조회 실패**
   - 문제: Name 태그 불일치 ("refit-dev-vpc" vs "refit-dev-v1-vpc")
   - 해결: Project + Environment 태그 기반 조회로 변경

#### 실행 명령어
```bash
cd terraform/monitoring-dev
terraform init
terraform plan
terraform apply  # 사용자가 직접 실행
```

---

### 2단계: 보안 그룹 업데이트

#### Application Server Security Group 규칙 추가
Dev 서버의 보안 그룹에 모니터링 서버에서 메트릭을 수집할 수 있도록 규칙 추가:

| Port | Service | Source | Description |
|------|---------|--------|-------------|
| 9100 | Node Exporter | 10.1.2.163/32 | 시스템 메트릭 |
| 8081 | cAdvisor | 10.1.2.163/32 | 컨테이너 메트릭 |
| 9187 | Postgres Exporter | 10.1.2.163/32 | DB 메트릭 |

#### 실행 명령어
```bash
cd terraform/dev
terraform apply
```

---

### 3단계: Monitoring Server 스택 배포

#### 생성된 파일
```
monitoring/monitoring-server/
├── README.md                                   # 환경별 배포 가이드
├── dev/                                        # Dev 환경 설정
│   ├── docker-compose.yml                      # 모니터링 스택 정의
│   ├── loki/
│   │   └── loki-config.yml                    # Loki 설정 (7일 보존)
│   ├── prometheus/
│   │   └── prometheus.yml                     # Prometheus scrape 설정
│   └── grafana/
│       └── provisioning/
│           ├── datasources/
│           │   └── datasources.yml            # Loki, Prometheus 연동
│           └── dashboards/
│               └── dashboards.yml             # 대시보드 프로비저닝
└── prod/                                       # Prod 환경 (추후 추가)
```

#### 배포된 서비스
- **Loki**: 3100 포트, 로그 보존 7일
- **Prometheus**: 9090 포트, 15초 scrape interval
- **Grafana**: 3000 포트, admin/admin 기본 인증

#### Prometheus Scrape Targets
```yaml
- job_name: 'node-exporter'      # 10.1.1.193:9100
- job_name: 'cadvisor'           # 10.1.1.193:8081
- job_name: 'spring-boot'        # 43.200.140.74:80/actuator/prometheus
- job_name: 'postgres'           # 10.1.1.193:9187
```

#### 실행 명령어
```bash
# 모니터링 서버 접속
ssh ubuntu@54.180.38.125

# 파일 업로드 (로컬에서)
scp -r monitoring-server ubuntu@54.180.38.125:~/

# Docker 설치 및 실행 (모니터링 서버에서)
sudo apt update
sudo apt install -y docker.io docker-compose
sudo usermod -aG docker ubuntu
newgrp docker

cd ~/monitoring-server/dev
docker-compose up -d
```

---

### 4단계: Application Server 에이전트 추가

#### 추가된 컨테이너
1. **Promtail** (grafana/promtail:2.9.3)
   - Docker 컨테이너 로그 수집
   - Loki로 전송 (10.1.2.163:3100)

2. **Node Exporter** (prom/node-exporter:v1.7.0)
   - CPU, 메모리, 디스크, 네트워크 메트릭
   - Port: 9100

3. **cAdvisor** (gcr.io/cadvisor/cadvisor:v0.47.2)
   - 컨테이너별 리소스 사용량
   - Port: 8081
   - Platform: linux/arm64

4. **Postgres Exporter** (prometheuscommunity/postgres-exporter:v0.15.0)
   - PostgreSQL 성능 메트릭
   - Port: 9187

#### 실행 명령어
```bash
# 애플리케이션 서버 접속
ssh ubuntu@43.200.140.74

# 설정 파일 업로드 (로컬에서)
scp app-server-docker-compose.yml ubuntu@43.200.140.74:~/re-fit/infra/docker-compose.yml
scp app-server-promtail-config.yml ubuntu@43.200.140.74:~/re-fit/infra/promtail-config.yml

# 컨테이너 재시작 (애플리케이션 서버에서)
cd ~/re-fit/infra
docker compose up -d
docker ps  # 상태 확인
```

#### 배포 결과
모든 에이전트가 정상적으로 실행 중:
```
✓ refit-promtail         Running
✓ refit-node-exporter    Up (9100/tcp)
✓ refit-cadvisor         Up healthy (8081/tcp)
✓ refit-postgres-exporter Up (9187/tcp)
```

---

## 🔐 접속 정보

### Grafana 대시보드
- **URL**: http://54.180.38.125:3000
- **Username**: admin
- **Password**: admin (초기 로그인 시 변경 필요)

### Prometheus
- **URL**: http://54.180.38.125:9090 (현재 외부 접속 차단)
- **Internal**: http://10.1.2.163:9090

### Loki
- **URL**: http://10.1.2.163:3100 (App Server에서만 접근 가능)

---

## 📊 권장 Grafana 대시보드

Grafana에서 다음 대시보드를 Import하여 즉시 사용 가능:

| ID | 이름 | 용도 |
|----|------|------|
| 1860 | Node Exporter Full | 시스템 리소스 종합 모니터링 |
| 179 | Docker Container & Host Metrics | 컨테이너 메트릭 |
| 9628 | PostgreSQL Database | PostgreSQL 성능 모니터링 |
| 12019 | Spring Boot 2.1 Statistics | Spring Boot 메트릭 (Actuator 활성화 필요) |

### Import 방법
1. Grafana 접속 (http://54.180.38.125:3000)
2. Dashboards → Import
3. Dashboard ID 입력
4. Prometheus 데이터소스 선택
5. Import 클릭

---

## 📝 선택적 추가 작업

### 1. Spring Boot Actuator 메트릭 활성화
Backend의 `application.yml`에 Prometheus 메트릭 노출 설정 추가:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,prometheus
  metrics:
    export:
      prometheus:
        enabled: true
```

### 2. Grafana Alerting 설정
- Slack, Discord 등 알림 채널 연동
- CPU 사용률, 메모리, 디스크 공간에 대한 알림 규칙 생성

### 3. Loki 로그 쿼리 예시
```logql
# 에러 로그만 필터링
{container="refit-backend"} |= "ERROR"

# 특정 시간대 요청 로그
{service="backend"} |= "GET" | json | duration > 1s
```

### 4. 보안 강화
- Grafana 관리자 비밀번호 변경
- Prometheus 외부 접속 차단 유지
- HTTPS 적용 (Let's Encrypt)

### 5. 데이터 보존 정책 조정
현재 Loki 로그 보존 기간: 7일
- 필요시 `loki-config.yml`의 `retention_period` 조정
- Prometheus 데이터 보존: 기본 15일 (필요시 `--storage.tsdb.retention.time` 플래그로 조정)

---

## 🗂️ 파일 위치 요약

### 로컬 (Git Repository)
```
cloud/
├── monitoring/
│   ├── OBSERVABILITY_GUIDE.md          # 초기 가이드
│   ├── IMPLEMENTATION.md               # 이 문서
│   ├── app-server-docker-compose.yml   # App 서버용 docker-compose
│   ├── app-server-promtail-config.yml  # App 서버 Promtail 설정
│   └── monitoring-server/              # Monitoring 서버 설정 (환경별)
│       ├── README.md                   # 환경별 배포 가이드
│       ├── dev/                        # Dev 환경 설정
│       │   ├── docker-compose.yml
│       │   ├── loki/loki-config.yml
│       │   ├── prometheus/prometheus.yml
│       │   └── grafana/provisioning/
│       └── prod/                       # Prod 환경 설정 (추후 추가)
└── terraform/
    ├── README.md                        # Terraform 전체 가이드
    ├── dev/
    │   └── security-group.tf           # 메트릭 수집 규칙 추가됨
    ├── monitoring-dev/                  # Dev 모니터링 서버 인프라
    │   ├── README.md
    │   ├── backend.tf
    │   ├── data.tf
    │   ├── ec2.tf
    │   ├── vpc.tf
    │   ├── security-group.tf
    │   ├── iam.tf
    │   ├── outputs.tf
    │   ├── provider.tf
    │   └── variables.tf
    └── monitoring-prod/                 # Prod 모니터링 (추후 추가)
        └── .gitkeep
```

### Application Server (43.200.140.74)
```
~/re-fit/infra/
├── docker-compose.yml        # 모든 서비스 + 에이전트
└── promtail-config.yml       # Promtail 설정
```

### Monitoring Server (54.180.38.125)
```
~/monitoring-server/
└── dev/                      # Dev 환경 설정
    ├── docker-compose.yml
    ├── loki/loki-config.yml
    ├── prometheus/prometheus.yml
    └── grafana/provisioning/
```

---

## 🎯 남은 태스크

### 즉시 필요한 작업
- [ ] Grafana 초기 비밀번호 변경 (보안)
- [ ] 대시보드 Import 및 확인
  - [ ] Node Exporter Full (1860)
  - [ ] Docker Container Metrics (179)
  - [ ] PostgreSQL Database (9628)

### 선택적 작업
- [ ] Spring Boot Actuator Prometheus 메트릭 활성화
- [ ] Grafana Alert 설정 (CPU, 메모리, 디스크)
- [ ] Discord/Slack 알림 채널 연동
- [ ] HTTPS 적용 (Let's Encrypt)
- [ ] Custom 대시보드 작성 (비즈니스 메트릭)
- [ ] Loki 로그 쿼리 최적화 및 Saved Queries 작성

### 유지보수 작업
- [ ] 주기적 디스크 사용량 모니터링 (로그/메트릭 데이터)
- [ ] Grafana 버전 업데이트 계획 수립
- [ ] 백업 전략 수립 (Grafana 대시보드, 알림 규칙)

---

## 🔧 트러블슈팅

### 메트릭이 수집되지 않는 경우
```bash
# Prometheus Targets 확인
curl http://10.1.2.163:9090/api/v1/targets

# Exporter 상태 확인
curl http://10.1.1.193:9100/metrics  # Node Exporter
curl http://10.1.1.193:8081/metrics  # cAdvisor
curl http://10.1.1.193:9187/metrics  # Postgres Exporter
```

### 로그가 수집되지 않는 경우
```bash
# Promtail 로그 확인
docker logs refit-promtail

# Loki 연결 테스트
curl http://10.1.2.163:3100/ready
```

### Grafana 대시보드가 표시되지 않는 경우
1. Data Source 연결 확인: Configuration → Data Sources
2. Prometheus/Loki 상태 확인: Test 버튼 클릭
3. Query 확인: Explore 메뉴에서 직접 쿼리 테스트

---

## 📚 참고 자료

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Node Exporter Guide](https://prometheus.io/docs/guides/node-exporter/)
- [cAdvisor Metrics](https://github.com/google/cadvisor/blob/master/docs/storage/prometheus.md)

---

## 📅 변경 이력

| 날짜 | 작업 내용 | 작성자 |
|------|----------|--------|
| 2026-02-10 | 모니터링 인프라 초기 구축 완료 | Claude |

---

## ✅ 최종 체크리스트

- [x] Terraform으로 모니터링 서버 생성
- [x] 보안 그룹 규칙 설정
- [x] Monitoring Server에 Loki, Prometheus, Grafana 배포
- [x] Application Server에 에이전트 추가
  - [x] Promtail
  - [x] Node Exporter
  - [x] cAdvisor
  - [x] Postgres Exporter
- [x] 모든 컨테이너 정상 실행 확인
- [x] Grafana 접속 확인

**구축 완료일**: 2026-02-10
**상태**: ✅ 운영 준비 완료
