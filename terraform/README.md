# Re:fit Terraform Infrastructure

Terraform을 사용하여 Re:fit 프로젝트의 AWS 인프라를 관리합니다.

## 📁 디렉토리 구조

```
terraform/
├── backend-setup/       # Terraform 원격 백엔드 (S3 + DynamoDB)
├── shared/             # 공유 리소스 (ECR 저장소 등)
├── dev/                # 개발 환경 애플리케이션 서버
├── prod/               # 운영 환경 애플리케이션 서버
├── monitoring-dev/     # 개발 환경 모니터링 서버
├── monitoring-prod/    # 운영 환경 모니터링 서버 (추후 추가)
└── docs/               # 문서 및 가이드
```

## 🚀 배포 순서

### 1. Backend Setup (최초 1회)
```bash
cd backend-setup
terraform init
terraform apply
```
- S3 버킷: Terraform state 파일 저장
- DynamoDB 테이블: State locking

### 2. Shared Resources (최초 1회)
```bash
cd shared
terraform init
terraform apply
```
- ECR 저장소: 도커 이미지 저장소

### 3. Dev Environment (개발 환경)
```bash
cd dev
terraform init
terraform apply
```
- VPC, Subnet, Internet Gateway
- Security Group
- EC2 인스턴스 (애플리케이션 서버)
- Elastic IP

### 4. Dev Monitoring (개발 모니터링)
```bash
cd monitoring-dev
terraform init
terraform apply
```
- Monitoring Subnet (Dev VPC 내)
- EC2 인스턴스 (모니터링 서버)
- Security Group

### 5. Prod Environment (운영 환경, 추후)
```bash
cd prod
# 추후 구성 예정
```

### 6. Prod Monitoring (운영 모니터링, 추후)
```bash
cd monitoring-prod
# 추후 구성 예정
```

## 🏗️ 아키텍처 개요

### Dev 환경
```
┌─────────────────────────────────────────┐
│         Dev VPC (10.1.0.0/16)           │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │ Dev Subnet (10.1.1.0/24)          │  │
│  │  - Application Server             │  │
│  │    (FE, BE, AI, DB)               │  │
│  └───────────────────────────────────┘  │
│                  │                      │
│                  │ metrics/logs         │
│                  ▼                      │
│  ┌───────────────────────────────────┐  │
│  │ Monitoring Subnet (10.1.2.0/24)   │  │
│  │  - Monitoring Server              │  │
│  │    (Grafana, Prometheus, Loki)    │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### Prod 환경 (추후)
```
┌─────────────────────────────────────────┐
│        Prod VPC (10.2.0.0/16)           │
│         (추후 구성 예정)                  │
└─────────────────────────────────────────┘
```

## 📝 환경별 특징

### Dev (개발 환경)
- **목적**: 개발 및 테스트
- **VPC**: 10.1.0.0/16
- **인스턴스 타입**: t4g.large (App), t4g.medium (Monitoring)
- **고가용성**: 단일 AZ
- **백업**: 미설정
- **비용**: 최소화

### Prod (운영 환경, 추후)
- **목적**: 실제 서비스 운영
- **VPC**: 10.2.0.0/16 (예정)
- **인스턴스 타입**: 부하에 따라 결정
- **고가용성**: Multi-AZ, Auto Scaling (검토)
- **백업**: RDS 자동 백업, Snapshot
- **비용**: 안정성 우선

## 🔐 State 관리

모든 환경의 Terraform State는 S3에 원격 저장됩니다:

```
s3://refit-terraform-state/
├── backend/terraform.tfstate           # Backend 설정
├── shared/terraform.tfstate            # 공유 리소스
├── dev/terraform.tfstate               # Dev 앱 서버
├── monitoring-dev/terraform.tfstate    # Dev 모니터링
├── prod/terraform.tfstate              # Prod 앱 서버 (추후)
└── monitoring-prod/terraform.tfstate   # Prod 모니터링 (추후)
```

DynamoDB 테이블 `refit-terraform-lock`으로 동시 수정을 방지합니다.

## 🛠️ 사용 방법

### 기본 워크플로우

1. **초기화**
   ```bash
   terraform init
   ```

2. **변경 사항 확인**
   ```bash
   terraform plan
   ```

3. **인프라 배포**
   ```bash
   terraform apply
   ```

4. **인프라 삭제**
   ```bash
   terraform destroy
   ```

### 환경별 작업

각 디렉토리의 `README.md`를 참조하세요:
- [backend-setup/README.md](backend-setup/README.md)
- [shared/README.md](shared/README.md)
- [dev/README.md](dev/README.md)
- [monitoring-dev/README.md](monitoring-dev/README.md)

## 📊 리소스 현황

### 현재 배포됨
- ✅ Backend Setup (S3, DynamoDB)
- ✅ Shared Resources (ECR)
- ✅ Dev Environment (VPC, EC2, Security Group)
- ✅ Dev Monitoring (EC2, Security Group, Subnet)

### 추후 추가 예정
- ⏳ Prod Environment
- ⏳ Prod Monitoring

## ⚠️ 주의사항

1. **삭제 순서**
   - 인프라를 삭제할 때는 배포 순서의 **역순**으로 진행
   - monitoring-dev → dev → shared → backend-setup

2. **State 파일 보호**
   - `terraform.tfstate` 파일은 절대 수동으로 편집하지 않기
   - S3 버킷 버저닝이 활성화되어 있어 복구 가능

3. **비밀 정보 관리**
   - `terraform.tfvars` 파일은 Git에 커밋하지 않기 (.gitignore에 포함)
   - 민감한 정보는 AWS Secrets Manager 또는 환경 변수 사용

4. **비용 관리**
   - 미사용 리소스는 즉시 삭제
   - EC2 인스턴스는 중지해도 EBS 요금 발생
   - Elastic IP는 연결되지 않으면 요금 발생

## 💰 예상 비용 (월간)

### Dev 환경
- EC2 (t4g.large): ~$60
- EC2 Monitoring (t4g.medium): ~$30
- EBS: ~$10
- 데이터 전송: ~$5
- **소계**: ~$105/월

### Prod 환경 (추후)
- 부하 및 구성에 따라 결정

## 📚 참고 문서

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS EC2 가격](https://aws.amazon.com/ec2/pricing/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

## 🆘 문제 해결

### Init 실패
```bash
# Backend 재설정
terraform init -reconfigure
```

### State Lock 걸림
```bash
# DynamoDB에서 Lock 수동 해제 (주의!)
aws dynamodb delete-item \
  --table-name refit-terraform-lock \
  --key '{"LockID":{"S":"<환경>/terraform.tfstate-md5"}}'
```

### VPC 참조 실패
- Dev 환경이 먼저 배포되어 있는지 확인
- VPC 태그가 정확한지 확인 (Project, Environment)

---

**마지막 업데이트**: 2026-02-10
