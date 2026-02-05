# 개발 환경 배포 가이드

개발 환경 인프라를 Terraform으로 배포하는 가이드입니다.

## 목차

1. [인프라 개요](#인프라-개요)
2. [사전 준비](#사전-준비)
3. [배포 절차](#배포-절차)
4. [배포 후 작업](#배포-후-작업)
5. [리소스 관리](#리소스-관리)

## 인프라 개요

### 네트워크 구성

```
VPC (10.1.0.0/16)
└── Public Subnet (10.1.1.0/24, ap-northeast-2a)
    ├── Internet Gateway
    ├── Route Table (0.0.0.0/0 → IGW)
    └── EC2 Instance (t4g.large)
        ├── Elastic IP (고정 IP)
        └── Security Group
            ├── Ingress: SSH (22)
            ├── Ingress: HTTP (80)
            ├── Ingress: HTTPS (443)
            └── Egress: All
```

### 주요 리소스

| 리소스 | 이름 | 설정 |
|--------|------|------|
| VPC | refit-dev-vpc | 10.1.0.0/16 |
| Subnet | refit-dev-public-subnet | 10.1.1.0/24 |
| EC2 | refit-dev-server | t4g.large, Ubuntu 22.04 ARM64 |
| EIP | refit-dev-eip | 고정 IP |
| SG | refit-dev-sg | SSH, HTTP, HTTPS |

### 보안 설정

- **IMDSv2 강제**: 메타데이터 서비스 v2 사용
- **EBS 암호화**: 루트 볼륨 암호화
- **퍼블릭 IP 자동 할당**: Public Subnet에서 활성화
- **Elastic IP**: 인스턴스 재시작 시에도 IP 유지

## 사전 준비

### 1. 필수 요구사항

- Terraform 1.0.0 이상
- AWS CLI 설정 완료
- SSH 키 페어 생성 (AWS EC2)
- 원격 백엔드 설정 완료

### 2. SSH 키 페어 생성

AWS 콘솔에서 키 페어 생성:

1. EC2 Console → Key Pairs
2. "Create key pair"
3. Name: `refit` (또는 원하는 이름)
4. Key pair type: RSA
5. Private key file format: .pem
6. 생성 후 다운로드: `refit.pem`

로컬에 저장:

```bash
mv ~/Downloads/refit.pem ~/.ssh/
chmod 400 ~/.ssh/refit.pem
```

### 3. 변수 파일 설정

```bash
cd terraform/dev

# 예제 파일 복사
cp terraform.tfvars.example terraform.tfvars

# 변수 파일 편집
vi terraform.tfvars
```

terraform.tfvars:
```hcl
# General Configuration
aws_region   = "ap-northeast-2"
project_name = "refit"
environment  = "dev"

# VPC Configuration
vpc_cidr           = "10.1.0.0/16"
public_subnet_cidr = "10.1.1.0/24"
availability_zone  = "ap-northeast-2a"

# EC2 Configuration
instance_type    = "t4g.large"
key_name         = "refit"  # SSH 키 페어 이름
root_volume_size = 30

# Security Group Configuration
allowed_ssh_cidr = ["YOUR_IP/32"]  # 본인 IP로 제한 권장
```

**보안 권장사항**: `allowed_ssh_cidr`을 본인 IP로 제한하세요.

본인 IP 확인:
```bash
curl ifconfig.me
# 출력: 123.45.67.89

# terraform.tfvars에 적용:
# allowed_ssh_cidr = ["123.45.67.89/32"]
```

## 배포 절차

### 1. 초기화

백엔드 설정이 이미 완료된 경우 건너뜁니다.

```bash
cd terraform/dev
terraform init
```

### 2. 실행 계획 확인

```bash
terraform plan
```

생성될 리소스 확인:
- VPC
- Internet Gateway
- Public Subnet
- Route Table
- Security Group (SSH, HTTP, HTTPS 규칙 포함)
- EC2 Instance
- Elastic IP

### 3. 인프라 배포

```bash
terraform apply
```

확인 메시지에서 `yes` 입력:
```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

배포 시간: 약 2-3분

### 4. 배포 완료 확인

배포가 완료되면 다음 정보가 출력됩니다:

```
Outputs:

elastic_ip = "13.125.XXX.XXX"
instance_id = "i-0123456789abcdef0"
instance_private_ip = "10.1.1.XX"
security_group_id = "sg-0123456789abcdef0"
ssh_command = "ssh -i ~/.ssh/refit.pem ubuntu@13.125.XXX.XXX"
vpc_id = "vpc-0123456789abcdef0"
public_subnet_id = "subnet-0123456789abcdef0"
```

## 배포 후 작업

### 1. SSH 접속 확인

```bash
# 출력된 ssh_command 사용
ssh -i ~/.ssh/refit.pem ubuntu@<ELASTIC_IP>

# 또는 직접 입력
ssh -i ~/.ssh/refit.pem ubuntu@13.125.XXX.XXX
```

처음 접속 시 fingerprint 확인:
```
The authenticity of host '13.125.XXX.XXX' can't be established.
Are you sure you want to continue connecting (yes/no)? yes
```

### 2. 시스템 업데이트

```bash
# 서버에 접속한 상태에서
sudo apt update
sudo apt upgrade -y
```

### 3. 필요한 소프트웨어 설치

예: Node.js, Docker, Nginx 등

```bash
# Node.js 설치 예시
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# 확인
node -v
npm -v
```

## 리소스 관리

### 리소스 정보 확인

```bash
# 모든 출력값 확인
terraform output

# 특정 출력값만 확인
terraform output elastic_ip

# JSON 형식으로 출력
terraform output -json
```

### 리소스 상태 확인

```bash
# 모든 리소스 목록
terraform state list

# 특정 리소스 상세 정보
terraform state show aws_instance.main

# AWS 콘솔에서 확인
# EC2 Console에서 refit-dev-server 인스턴스 확인
```

### 변수 수정

terraform.tfvars 파일을 수정한 후:

```bash
# 변경 사항 확인
terraform plan

# 적용
terraform apply
```

### 리소스 수정

Terraform 코드를 수정한 후:

```bash
# 변경 사항 확인
terraform plan

# 적용
terraform apply
```

### 인프라 삭제

**주의**: 모든 리소스가 영구 삭제됩니다.

```bash
terraform destroy
```

확인 메시지에서 `yes` 입력.

## State 파일 관리

### State 파일 위치

원격 백엔드를 사용하므로 state 파일은 S3에 저장됩니다:

```
s3://refit-terraform-state/dev/terraform.tfstate
```

### State 백업

S3 버전 관리가 활성화되어 있으므로 자동 백업됩니다:

```bash
# 버전 확인
aws s3api list-object-versions \
  --bucket refit-terraform-state \
  --prefix dev/terraform.tfstate
```

### State 복구

이전 버전으로 복구가 필요한 경우:

```bash
# 특정 버전 다운로드
aws s3api get-object \
  --bucket refit-terraform-state \
  --key dev/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup
```

## 보안 체크리스트

- [ ] SSH 키 페어를 안전한 위치에 보관
- [ ] `allowed_ssh_cidr`을 특정 IP로 제한
- [ ] terraform.tfvars 파일이 .gitignore에 포함되어 있는지 확인
- [ ] AWS 자격 증명이 안전하게 관리되는지 확인
- [ ] 정기적으로 시스템 업데이트 수행

## 비용 관리

### 예상 월 비용

- **EC2 t4g.large**: ~$50/월 (24시간 운영 시)
- **EBS gp3 30GB**: ~$3/월
- **Elastic IP**: 인스턴스 실행 중이면 무료
- **데이터 전송**: 사용량에 따라 변동
- **합계**: ~$55/월

### 비용 절감 팁

1. **개발 시간에만 운영**: 퇴근 시 인스턴스 중지
   ```bash
   aws ec2 stop-instances --instance-ids <INSTANCE_ID>
   ```

2. **예약 인스턴스**: 장기 사용 시 할인
3. **Savings Plans**: 유연한 할인 플랜

## 다음 단계

1. 애플리케이션 배포
2. 모니터링 설정
3. 백업 정책 수립
4. CI/CD 파이프라인 구성

문제가 발생하면 [트러블슈팅 가이드](./troubleshooting.md)를 참고하세요.
