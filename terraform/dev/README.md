# Development Environment Terraform Configuration

이 디렉토리는 개발 환경의 AWS 인프라를 Terraform으로 관리합니다.

## 인프라 구성

- **VPC**: 10.1.0.0/16
- **Public Subnet**: 10.1.1.0/24
- **EC2 Instance**: t4g.large (Ubuntu 22.04 LTS ARM64)
- **Security Group**: SSH(22), HTTP(80), HTTPS(443) 허용
- **Elastic IP**: 고정 IP 할당

## 사용 방법

### 1. 초기 설정

```bash
# terraform.tfvars 파일 생성
cp terraform.tfvars.example terraform.tfvars

# terraform.tfvars 파일을 편집하여 key_name 등 필요한 값 설정
vi terraform.tfvars
```

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

### 5. 인프라 삭제

```bash
terraform destroy
```

## 필수 변수

- `key_name`: AWS EC2 키 페어 이름 (반드시 설정 필요)

## 출력 정보

배포 완료 후 다음 정보가 출력됩니다:

- VPC ID
- Subnet ID
- Security Group ID
- Instance ID
- Elastic IP
- SSH 접속 명령어

## 보안 권장사항

- `allowed_ssh_cidr`: SSH 접근을 특정 IP 주소로 제한하는 것을 권장합니다.
- 기본값은 `0.0.0.0/0`으로 모든 IP에서 접근 가능하므로, 운영 환경에서는 반드시 변경하세요.
