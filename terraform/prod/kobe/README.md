# Re-Fit Terraform - Production Environment (Kobe)

이 디렉토리는 Re-Fit 프로젝트의 프로덕션 인프라를 관리하는 Terraform 코드입니다.

## 시작하기

### 1. 변수 파일 설정

```bash
# 템플릿 파일을 복사
cp terraform.tfvars.example terraform.tfvars

# 실제 값으로 수정
vim terraform.tfvars
```

**필수 수정 항목**:
- `key_name`: AWS EC2 키페어 이름
- `allowed_ssh_cidr`: SSH 접속 허용 IP (보안을 위해 특정 IP로 제한)

### 2. Terraform 실행

```bash
# 초기화
terraform init

# 계획 확인
terraform plan

# 인프라 생성
terraform apply
```

### 3. 생성된 리소스 확인

```bash
# 모든 출력 보기
terraform output

# 특정 값만 보기
terraform output elastic_ip
terraform output s3_bucket_name
```

## 주요 리소스

- **VPC**: 10.0.0.0/16
- **EC2**: t4g.medium (Ubuntu 22.04 ARM64)
- **S3**: refit-prod-files (애플리케이션 파일 저장)
- **Elastic IP**: 고정 공인 IP

## 문서

자세한 내용은 [docs/README.md](docs/README.md)를 참고하세요.

## 보안 주의사항

⚠️ **절대 커밋하면 안 되는 파일**:
- `terraform.tfstate` - 상태 파일
- `terraform.tfvars` - 실제 설정값
- `*.pem`, `*.key` - SSH 키 파일

이 파일들은 `.gitignore`에 등록되어 있습니다.

## AWS Profile

이 프로젝트는 `refit-kobe` AWS 프로필을 사용합니다.

```bash
# 프로필 설정
aws configure --profile refit-kobe

# 프로필 확인
aws sts get-caller-identity --profile refit-kobe
```

## 비용

월 예상 비용: 약 $35-40 (EC2 + EBS + S3)

자세한 비용 정보는 [docs/README.md](docs/README.md#비용-예상)를 참고하세요.
