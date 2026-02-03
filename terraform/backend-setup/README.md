# Terraform Backend Setup

이 디렉토리는 Terraform 원격 백엔드 리소스(S3 버킷 및 DynamoDB 테이블)를 생성합니다.

## 주의사항

- **이 프로젝트는 로컬 백엔드를 사용합니다** (원격 백엔드를 설정하지 않음)
- S3와 DynamoDB를 생성한 후, 다른 Terraform 프로젝트(dev, prod 등)에서 이 리소스를 원격 백엔드로 사용합니다
- `prevent_destroy = true` 설정으로 실수로 삭제되지 않도록 보호됨

## 생성되는 리소스

### S3 Bucket
- **이름**: `refit-terraform-state`
- **용도**: Terraform state 파일 저장
- **기능**:
  - 버전 관리 활성화
  - AES256 암호화
  - 퍼블릭 액세스 차단
  - 90일 지난 버전 자동 삭제

### DynamoDB Table
- **이름**: `refit-terraform-lock`
- **용도**: Terraform state locking (동시 실행 방지)
- **요금제**: PAY_PER_REQUEST (사용량 기반)

## 사용 방법

### 1. 백엔드 리소스 생성

```bash
cd terraform/backend-setup

# 초기화
terraform init

# 실행 계획 확인
terraform plan

# 리소스 생성
terraform apply
```

### 2. 출력값 확인

```bash
terraform output

# backend_config 출력값을 복사하여 다른 프로젝트의 backend.tf에 사용
terraform output -raw backend_config
```

### 3. 다른 프로젝트에서 사용

생성된 S3와 DynamoDB를 다른 Terraform 프로젝트의 backend로 설정:

```hcl
# terraform/dev/backend.tf
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

## 리소스 삭제 시 주의

백엔드 리소스를 삭제하면 모든 Terraform state가 손실됩니다.

삭제가 필요한 경우:

```bash
# 1. prevent_destroy 제거
# s3.tf와 dynamodb.tf에서 lifecycle 블록 주석 처리

# 2. 삭제 실행
terraform destroy
```

## 비용

- **S3**: 저장 용량 + 요청 수 (매우 적음)
- **DynamoDB**: PAY_PER_REQUEST (읽기/쓰기 요청 시에만 과금, 개발 환경에서는 거의 무료)

예상 월 비용: $1 미만
