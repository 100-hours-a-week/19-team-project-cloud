# Dev Monitoring Environment Terraform Configuration

**개발 환경** 모니터링 서버(Grafana, Prometheus, Loki)를 위한 AWS 인프라를 Terraform으로 관리합니다.

> 💡 운영 환경 모니터링 서버는 `../monitoring-prod/`를 참조하세요.

## 사전 조건

- `backend-setup/`이 배포되어 있어야 합니다 (원격 백엔드 S3/DynamoDB)
- `shared/`가 배포되어 있어야 합니다 (ECR 저장소)
- `dev/`가 배포되어 있어야 합니다 (애플리케이션 서버가 실행 중이어야 함)

## 아키텍처 개요

```
┌─────────────────────────────────────────┐
│         Dev VPC (10.1.0.0/16)           │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │ Dev Subnet (10.1.1.0/24)          │  │
│  │  - Application Server             │  │
│  │    (FE, BE, AI, DB, Caddy)        │  │
│  │    + Monitoring Agents            │  │
│  │    (Promtail, Node Exporter,      │  │
│  │     cAdvisor)                     │  │
│  └───────────────────────────────────┘  │
│                  │                      │
│                  │ metrics & logs       │
│                  ▼                      │
│  ┌───────────────────────────────────┐  │
│  │ Monitoring Subnet (10.1.2.0/24)   │  │
│  │  - Monitoring Server              │  │
│  │    (Loki, Prometheus, Grafana)    │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## 인프라 구성

### 네트워크

| 리소스 | 이름 | 설정 |
|--------|------|------|
| VPC | `refit-dev-vpc` (참조) | Dev 환경과 동일한 VPC 사용 |
| Monitoring Subnet | `refit-monitoring-subnet` | CIDR 10.1.2.0/24, AZ ap-northeast-2a |
| Internet Gateway | `refit-dev-igw` (참조) | Dev 환경과 공유 |
| Route Table | `refit-monitoring-rt` | 0.0.0.0/0 → IGW |

### 컴퓨팅

| 리소스 | 이름 | 설정 |
|--------|------|------|
| EC2 Instance | `refit-monitoring-server` | t4g.medium (ARM Graviton, 2 vCPU, 4GB RAM), Ubuntu 22.04 LTS ARM64 |
| EBS Volume | 루트 볼륨 | gp3, 50GB, 암호화 |
| Elastic IP | `refit-monitoring-eip` | EC2에 연결된 고정 퍼블릭 IP |

### 보안

| 리소스 | 이름 | 설정 |
|--------|------|------|
| Security Group | `refit-monitoring-sg` | Inbound: SSH(22), Grafana(3000), Loki(3100 from app server) / Outbound: 전체 허용 |

**보안 그룹 규칙:**
- **SSH (22)**: `allowed_ssh_cidr`에서 지정한 IP (기본: 0.0.0.0/0)
- **Grafana (3000)**: `allowed_grafana_cidr`에서 지정한 IP (기본: 0.0.0.0/0)
- **Loki (3100)**: 애플리케이션 서버 Private IP만 허용
- **Prometheus (9090)**: `allow_public_prometheus=true`일 때만 허용
- **Alertmanager (9093)**: `allow_public_prometheus=true`일 때만 허용

### IAM (EC2용 권한)

| 리소스 | 이름 | 설정 |
|--------|------|------|
| IAM Role | `refit-monitoring-ec2-role` | EC2 서비스가 assume할 수 있는 역할 |
| IAM Policy | `refit-monitoring-ecr-read` | ECR 이미지 pull 권한 (필요시) |
| Instance Profile | `refit-monitoring-ec2-profile` | EC2 인스턴스에 IAM Role 연결 |

## 파일 구성

| 파일 | 역할 |
|------|------|
| `provider.tf` | AWS provider (리전, Terraform 버전, 기본 태그) |
| `backend.tf` | S3 원격 백엔드 (key: `monitoring-dev/terraform.tfstate`) |
| `variables.tf` | 입력 변수 정의 |
| `terraform.tfvars` | 변수 값 (git 제외) |
| `terraform.tfvars.example` | 변수 값 예제 |
| `data.tf` | Dev VPC, IGW, 애플리케이션 서버 참조 |
| `vpc.tf` | Monitoring Subnet, Route Table |
| `security-group.tf` | Security Group + Ingress/Egress 규칙 |
| `ec2.tf` | EC2 인스턴스 + Elastic IP + Ubuntu AMI 조회 |
| `iam.tf` | IAM Role + ECR 읽기 정책 + Instance Profile |
| `outputs.tf` | 출력값 (VPC ID, IP, SSH 명령어 등) |

## 사용 방법

### 1. 초기 설정

```bash
# terraform.tfvars 파일 생성
cp terraform.tfvars.example terraform.tfvars

# terraform.tfvars 파일을 편집하여 key_name 등 필요한 값 설정
vi terraform.tfvars
```

**필수 변경 사항:**
- `key_name`: AWS EC2 키 페어 이름으로 변경
- `allowed_ssh_cidr`: SSH 접근 허용 IP 범위 (보안상 특정 IP로 제한 권장)

### 2. Terraform 초기화

```bash
terraform init
```

### 3. 실행 계획 확인

```bash
terraform plan
```

### 4. 인프라 배포

```bash
terraform apply
```

배포 완료 후 다음 정보가 출력됩니다:
- Monitoring 서버 Public IP
- Grafana URL (http://<IP>:3000)
- SSH 접속 명령어
- 다음 단계 안내

### 5. 인프라 삭제

```bash
terraform destroy
```

## 변수

| 변수 | 타입 | 기본값 | 필수 | 설명 |
|------|------|--------|------|------|
| `aws_region` | string | `ap-northeast-2` | | AWS 리전 |
| `project_name` | string | `refit` | | 프로젝트 이름 (리소스 이름 접두사) |
| `environment` | string | `monitoring` | | 환경 이름 |
| `dev_environment` | string | `dev` | | Dev 환경 이름 (VPC 참조용) |
| `monitoring_subnet_cidr` | string | `10.1.2.0/24` | | Monitoring Subnet CIDR |
| `availability_zone` | string | `ap-northeast-2a` | | 가용 영역 |
| `instance_type` | string | `t4g.medium` | | EC2 인스턴스 타입 |
| `key_name` | string | — | **필수** | AWS EC2 키 페어 이름 |
| `root_volume_size` | number | `50` | | 루트 볼륨 크기 (GB) |
| `allowed_ssh_cidr` | list(string) | `["0.0.0.0/0"]` | | SSH 접근 허용 CIDR 목록 |
| `allowed_grafana_cidr` | list(string) | `["0.0.0.0/0"]` | | Grafana 접근 허용 CIDR 목록 |
| `allow_public_prometheus` | bool | `false` | | Prometheus 공개 접근 허용 여부 |
| `allow_public_loki` | bool | `false` | | Loki 공개 접근 허용 여부 |

## 출력 정보

배포 완료 후 다음 정보가 출력됩니다:

| 출력 | 설명 |
|------|------|
| `vpc_id` | VPC ID (Dev 환경과 공유) |
| `monitoring_subnet_id` | Monitoring Subnet ID |
| `security_group_id` | Security Group ID |
| `instance_id` | EC2 인스턴스 ID |
| `instance_private_ip` | EC2 프라이빗 IP |
| `elastic_ip` | 퍼블릭 Elastic IP |
| `dev_app_server_private_ip` | Dev 애플리케이션 서버 Private IP |
| `grafana_url` | Grafana 웹 UI URL |
| `prometheus_url` | Prometheus 웹 UI URL |
| `loki_url` | Loki API URL |
| `ssh_command` | SSH 접속 명령어 |
| `next_steps` | 다음 단계 안내 |

## 다음 단계

Terraform 배포 후:

1. **SSH 접속**
   ```bash
   ssh -i ~/.ssh/<key>.pem ubuntu@<monitoring-server-ip>
   ```

2. **Docker 설치**
   ```bash
   sudo apt update
   sudo apt install -y docker.io docker-compose-v2
   sudo usermod -aG docker ubuntu
   # 재로그인 필요
   ```

3. **모니터링 스택 구성**
   - `/cloud/monitoring/OBSERVABILITY_GUIDE.md` 참조
   - Loki, Prometheus, Grafana Docker Compose 파일 작성
   - 설정 파일 작성 및 배포

4. **애플리케이션 서버 보안 그룹 업데이트**
   - Dev 환경의 `security-group.tf`에 모니터링 서버로부터의 메트릭 수집 허용 규칙 추가
   - Node Exporter (9100), cAdvisor (8081), Postgres Exporter (9187) 포트 열기

## 보안 권장사항

- **SSH 접근 제한**: `allowed_ssh_cidr`을 특정 IP로 제한 (`["<본인_IP>/32"]`)
- **Grafana 접근 제한**: 필요시 `allowed_grafana_cidr`을 특정 IP로 제한
- **Prometheus/Loki 비공개**: `allow_public_prometheus`와 `allow_public_loki`는 false로 유지 (Grafana를 통해 접근)
- **Grafana 비밀번호 변경**: 최초 로그인 후 admin 비밀번호 즉시 변경

## 트러블슈팅

### 1. Dev 애플리케이션 서버를 찾을 수 없음

**에러:**
```
Error: Your query returned no results. Please change your search criteria and try again.
```

**원인:** Dev 환경의 EC2 인스턴스가 실행되지 않았거나 태그 이름이 다름

**해결:**
1. Dev 환경 먼저 배포: `cd ../dev && terraform apply`
2. 인스턴스 태그 확인: `aws ec2 describe-instances --filters "Name=tag:Name,Values=refit-dev-server"`

### 2. VPC를 찾을 수 없음

**원인:** Dev 환경이 배포되지 않음

**해결:** Dev 환경 먼저 배포

### 3. 보안 그룹 규칙 충돌

**원인:** 동일한 포트에 대한 중복 규칙

**해결:** 기존 보안 그룹 규칙 확인 및 제거

## 비용 예상

- **EC2 (t4g.medium)**: ~$30/월 (온디맨드, 24시간 가동)
- **EBS (50GB gp3)**: ~$4/월
- **Elastic IP**: $0 (EC2에 연결된 경우)
- **데이터 전송**: 변동 (인바운드 무료, 아웃바운드 종량제)

**총 예상 비용**: ~$35/월

**비용 절감 팁:**
- Reserved Instance 또는 Savings Plans 사용
- 개발 중 미사용 시간에 인스턴스 중지 (단, 로그/메트릭 수집 중단됨)
