# Terraform 원격 백엔드 설정 가이드

Terraform state 파일을 S3에 저장하고 DynamoDB로 locking을 관리하는 원격 백엔드 설정 가이드입니다.

## 목차

1. [개요](#개요)
2. [왜 원격 백엔드가 필요한가?](#왜-원격-백엔드가-필요한가)
3. [설정 절차](#설정-절차)
4. [검증](#검증)
5. [기존 리소스 정리](#기존-리소스-정리)

## 개요

원격 백엔드는 다음 리소스로 구성됩니다:

- **S3 버킷**: `refit-terraform-state`
  - Terraform state 파일을 저장
  - 버전 관리 활성화
  - AES256 암호화
  - 퍼블릭 액세스 차단

- **DynamoDB 테이블**: `refit-terraform-lock`
  - State locking 기능 제공
  - 동시 실행 방지
  - PAY_PER_REQUEST 요금제

## 왜 원격 백엔드가 필요한가?

### 로컬 백엔드의 문제점

- State 파일 분실 위험
- 팀 협업 불가능
- 동시 실행 시 충돌
- 버전 관리 어려움
- 민감 정보 노출 위험

### 원격 백엔드의 장점

1. **중앙화된 State 관리**: S3에 안전하게 저장
2. **협업 지원**: 팀원 간 state 공유
3. **State Locking**: DynamoDB로 동시 실행 방지
4. **버전 관리**: S3 버전 관리로 이전 상태 복구 가능
5. **보안**: 암호화 및 접근 제어

## 설정 절차

### 1. 백엔드 리소스 생성

backend-setup 프로젝트는 로컬 state를 사용합니다 (백엔드 리소스 자체는 로컬 관리).

```bash
cd terraform/backend-setup

# 초기화
terraform init

# 실행 계획 확인
terraform plan

# 리소스 생성
terraform apply
```

### 2. 생성된 리소스 확인

```bash
# 출력값 확인
terraform output

# S3 버킷 확인
aws s3 ls | grep terraform

# DynamoDB 테이블 확인
aws dynamodb list-tables --region ap-northeast-2 | grep terraform
```

예상 출력:
```
s3_bucket_name = "refit-terraform-state"
dynamodb_table_name = "refit-terraform-lock"
```

### 3. 백엔드 설정 템플릿

생성된 backend_config 출력값을 사용하여 다른 프로젝트에 적용:

```bash
terraform output -raw backend_config
```

출력:
```hcl
terraform {
  backend "s3" {
    bucket         = "refit-terraform-state"
    key            = "ENV/terraform.tfstate"  # ENV를 dev, prod 등으로 변경
    region         = "ap-northeast-2"
    encrypt        = true
    dynamodb_table = "refit-terraform-lock"
  }
}
```

### 4. Dev 환경에 적용

dev/backend.tf 파일이 이미 생성되어 있습니다:

```hcl
terraform {
  backend "s3" {
    bucket         = "refit-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
    dynamodb_table = "refit-terraform-lock"
  }
}
```

dev 환경 초기화:

```bash
cd ../dev
terraform init
```

## 검증

### 1. 백엔드 초기화 확인

```bash
cd terraform/dev
terraform init
```

성공 메시지:
```
Successfully configured the backend "s3"!
```

### 2. State 파일 확인

```bash
# 로컬에 state 파일이 없어야 함
ls -la *.tfstate

# S3에 state 파일 생성 확인 (plan/apply 후)
aws s3 ls s3://refit-terraform-state/dev/
```

### 3. State Locking 테스트

두 개의 터미널에서 동시에 terraform 실행:

```bash
# 터미널 1
terraform plan

# 터미널 2 (동시 실행)
terraform plan
```

터미널 2에서 locking 에러가 발생하면 정상:
```
Error: Error acquiring the state lock
```

## 기존 리소스 정리

### 상황

이전에 환경별 백엔드 리소스를 생성했던 경우:
- `refit-terraform-state-dev` (기존)
- `refit-terraform-lock-dev` (기존)

### 새로운 구조

환경별 접미사 없이 공통 백엔드 사용:
- `refit-terraform-state` (새로 생성)
- `refit-terraform-lock` (새로 생성)

### 기존 리소스 삭제

```bash
# S3 버킷 삭제
aws s3 rb s3://refit-terraform-state-dev --force

# DynamoDB 테이블 삭제
aws dynamodb delete-table \
  --table-name refit-terraform-lock-dev \
  --region ap-northeast-2
```

### 확인

```bash
# S3 버킷 목록
aws s3 ls | grep terraform
# 결과: refit-terraform-state만 남아있어야 함

# DynamoDB 테이블 목록
aws dynamodb list-tables --region ap-northeast-2 | grep terraform
# 결과: refit-terraform-lock만 남아있어야 함
```

## 환경별 Key 관리

하나의 S3 버킷에서 환경별로 다른 key(경로)를 사용:

```
s3://refit-terraform-state/
├── dev/
│   └── terraform.tfstate       # 개발 환경
└── prod/
    └── terraform.tfstate       # 운영 환경
```

### Dev 환경

```hcl
terraform {
  backend "s3" {
    key = "dev/terraform.tfstate"
    # ...
  }
}
```

### Prod 환경

```hcl
terraform {
  backend "s3" {
    key = "prod/terraform.tfstate"
    # ...
  }
}
```

## 비용

예상 월 비용 (개발 환경 기준):

- **S3**: ~$0.10 (state 파일 저장)
- **DynamoDB**: ~$0.01 (PAY_PER_REQUEST, 사용량 기반)
- **합계**: ~$0.15/월 미만

## 트러블슈팅

### State Lock 에러

**증상**:
```
Error: Error acquiring the state lock
```

**원인**: 이전 실행이 비정상 종료되어 lock이 남아있음

**해결**:
```bash
# Lock ID 확인 (에러 메시지에서)
# 예: ID: 01397b77-e16d-47d5-b6ef-af5e5509a2a3

# 강제 unlock
terraform force-unlock -force <LOCK_ID>
```

### 백엔드 변경 에러

**증상**:
```
Error: Backend configuration changed
```

**해결**:
```bash
# 기존 state 마이그레이션
terraform init -migrate-state

# 또는 새로 시작
terraform init -reconfigure
```

## 보안 권장사항

1. **S3 버킷 접근 제어**
   - IAM 정책으로 최소 권한 부여
   - MFA Delete 활성화 (선택사항)

2. **DynamoDB 접근 제어**
   - 읽기/쓰기 권한 제한

3. **State 파일 보안**
   - State 파일에 민감 정보 포함 가능
   - S3 암호화 활성화 (이미 적용됨)
   - 접근 로그 활성화 (선택사항)

## 다음 단계

백엔드 설정이 완료되었으므로 [개발 환경 배포](./dev-deployment.md)를 진행합니다.
