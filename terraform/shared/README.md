# Shared Resources Terraform Configuration

이 디렉토리는 환경(dev/prod)에 관계없이 공통으로 사용하는 AWS 리소스를 Terraform으로 관리합니다.

## 관리 리소스

### ECR (Elastic Container Registry)

서비스별 Docker 이미지를 저장하는 컨테이너 레지스트리입니다.

| 저장소 이름 | 대상 서비스 | 설명 |
|-------------|-------------|------|
| `refit-ai` | AI 서비스 | AI/ML 모델 서빙 컨테이너 |
| `refit-frontend` | Frontend | 프론트엔드 웹 애플리케이션 컨테이너 |
| `refit-backend` | Backend | 백엔드 API 서버 컨테이너 |

### ECR 설정 상세

- **이미지 태그**: Mutable (동일 태그로 덮어쓰기 가능)
- **보안 스캔**: Push 시 자동 취약점 스캔 활성화
- **암호화**: AES256 서버측 암호화
- **Lifecycle 정책**: 저장소당 최근 **30개** 이미지만 유지, 초과분 자동 삭제

## 파일 구성

| 파일 | 역할 |
|------|------|
| `provider.tf` | AWS provider 설정 (리전: ap-northeast-2, 태그: Purpose=shared-resources) |
| `backend.tf` | S3 원격 백엔드 (key: `shared/terraform.tfstate`) |
| `variables.tf` | 변수 정의 (서비스 목록, 이미지 보관 개수) |
| `ecr.tf` | ECR 저장소 + Lifecycle 정책 (`for_each`로 서비스별 생성) |
| `outputs.tf` | ECR URL, ARN, 이름을 서비스별 맵으로 출력 |

## 사전 조건

- `backend-setup/`이 먼저 배포되어 있어야 합니다 (S3 버킷 + DynamoDB 테이블 필요)

## 사용 방법

### 1. 초기화 및 배포

```bash
cd terraform/shared
terraform init
terraform plan
terraform apply
```

### 2. ECR URL 확인

```bash
terraform output ecr_repository_urls
```

출력 예시:
```
{
  "ai"       = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/refit-ai"
  "backend"  = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/refit-backend"
  "frontend" = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/refit-frontend"
}
```

### 3. ECR에 이미지 Push

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com

# 이미지 태그 및 Push (예: backend)
docker tag my-app:latest 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/refit-backend:latest
docker push 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/refit-backend:latest
```

### 4. EC2에서 이미지 Pull

dev 환경의 EC2에는 ECR 읽기 권한이 부여된 IAM Role이 연결되어 있어 별도의 자격증명 없이 pull할 수 있습니다:

```bash
# EC2 인스턴스에서 실행
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com

docker pull 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/refit-backend:latest
```

## 서비스 추가/제거

`ecr_services` 변수를 수정하여 ECR 저장소를 추가하거나 제거할 수 있습니다.

### 서비스 추가

`terraform.tfvars` 파일을 만들어 오버라이드하거나 `variables.tf`의 기본값을 수정:

```hcl
ecr_services = ["ai", "frontend", "backend", "worker"]
```

```bash
terraform plan   # 새 저장소 생성 확인
terraform apply
```

### 서비스 제거

목록에서 서비스를 제거하면 해당 ECR 저장소가 **삭제**됩니다 (저장된 이미지도 함께 삭제).

```hcl
ecr_services = ["ai", "frontend"]  # backend 제거
```

## 변수

| 변수 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `aws_region` | string | `ap-northeast-2` | AWS 리전 |
| `project_name` | string | `refit` | 리소스 이름 접두사 |
| `ecr_services` | list(string) | `["ai", "frontend", "backend"]` | ECR 저장소를 생성할 서비스 목록 |
| `ecr_image_retention_count` | number | `30` | 저장소당 유지할 최대 이미지 수 |

## 출력값

| 출력 | 형식 | 설명 |
|------|------|------|
| `ecr_repository_urls` | `map(string)` | 서비스 → ECR URL 맵 |
| `ecr_repository_arns` | `map(string)` | 서비스 → ECR ARN 맵 |
| `ecr_repository_names` | `map(string)` | 서비스 → ECR 이름 맵 |

## 다른 프로젝트와의 관계

- **backend-setup/** → `shared/`가 S3 원격 백엔드로 사용
- **shared/** → `dev/`의 EC2 IAM 정책이 `refit-*` ECR 저장소에 대한 읽기 권한을 부여
