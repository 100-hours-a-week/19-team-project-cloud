# Development Environment Terraform Configuration

이 디렉토리는 개발 환경의 AWS 인프라를 Terraform으로 관리합니다.

## 사전 조건

- `backend-setup/`이 배포되어 있어야 합니다 (원격 백엔드 S3/DynamoDB)
- `shared/`가 배포되어 있어야 합니다 (EC2에서 pull할 ECR 저장소)

## 인프라 구성

### 네트워크

| 리소스 | 이름 | 설정 |
|--------|------|------|
| VPC | `refit-dev-vpc` | CIDR 10.1.0.0/16, DNS 활성화 |
| Public Subnet | `refit-dev-public-subnet` | CIDR 10.1.1.0/24, AZ ap-northeast-2a |
| Internet Gateway | `refit-dev-igw` | VPC에 연결 |
| Route Table | `refit-dev-public-rt` | 0.0.0.0/0 → IGW |

### 컴퓨팅

| 리소스 | 이름 | 설정 |
|--------|------|------|
| EC2 Instance | `refit-dev-server` | t4g.large (ARM Graviton, 2 vCPU, 8GB RAM), Ubuntu 22.04 LTS ARM64 |
| EBS Volume | 루트 볼륨 | gp3, 30GB, 암호화 |
| Elastic IP | `refit-dev-eip` | EC2에 연결된 고정 퍼블릭 IP |

### 보안

| 리소스 | 이름 | 설정 |
|--------|------|------|
| Security Group | `refit-dev-sg` | Inbound: SSH(22), HTTP(80), HTTPS(443) / Outbound: 전체 허용 |

### IAM (EC2용 권한)

| 리소스 | 이름 | 설정 |
|--------|------|------|
| IAM Role | `refit-dev-ec2-role` | EC2 서비스가 assume할 수 있는 역할 |
| IAM Policy | `refit-dev-ecr-read` | `ecr:GetAuthorizationToken` (전체) + `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer`, `ecr:BatchCheckLayerAvailability` (`refit-*` 저장소만) |
| Instance Profile | `refit-dev-ec2-profile` | EC2 인스턴스에 IAM Role 연결 |

EC2 인스턴스에 ECR 읽기 전용 권한이 자동으로 부여되므로, 인스턴스에서 별도의 AWS 자격증명 설정 없이 ECR 이미지를 pull할 수 있습니다.

### 보안 하이라이트

- **IMDSv2 강제**: EC2 인스턴스 메타데이터 서비스 v2만 허용 (`http_tokens = required`)
- **EBS 암호화**: 루트 볼륨 서버측 암호화
- **최소 권한 IAM**: `refit-*` ECR 저장소에 대한 읽기만 허용
- **AMI 변경 무시**: `lifecycle { ignore_changes = [ami] }` — Ubuntu AMI 업데이트 시 인스턴스 재생성 방지

## 파일 구성

| 파일 | 역할 |
|------|------|
| `provider.tf` | AWS provider (리전, Terraform 버전, 기본 태그) |
| `backend.tf` | S3 원격 백엔드 (key: `dev/terraform.tfstate`) |
| `variables.tf` | 입력 변수 정의 |
| `terraform.tfvars` | 변수 값 (git 제외) |
| `terraform.tfvars.example` | 변수 값 예제 |
| `vpc.tf` | VPC, Subnet, IGW, Route Table |
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

## 변수

| 변수 | 타입 | 기본값 | 필수 | 설명 |
|------|------|--------|------|------|
| `aws_region` | string | `ap-northeast-2` | | AWS 리전 |
| `project_name` | string | `refit` | | 프로젝트 이름 (리소스 이름 접두사) |
| `environment` | string | `dev` | | 환경 이름 |
| `vpc_cidr` | string | `10.1.0.0/16` | | VPC CIDR 블록 |
| `public_subnet_cidr` | string | `10.1.1.0/24` | | Public Subnet CIDR |
| `availability_zone` | string | `ap-northeast-2a` | | 가용 영역 |
| `instance_type` | string | `t4g.large` | | EC2 인스턴스 타입 |
| `key_name` | string | — | **필수** | AWS EC2 키 페어 이름 |
| `root_volume_size` | number | `30` | | 루트 볼륨 크기 (GB) |
| `allowed_ssh_cidr` | list(string) | `["0.0.0.0/0"]` | | SSH 접근 허용 CIDR 목록 |

## 출력 정보

배포 완료 후 다음 정보가 출력됩니다:

| 출력 | 설명 |
|------|------|
| `vpc_id` | VPC ID |
| `vpc_cidr` | VPC CIDR 블록 |
| `public_subnet_id` | Public Subnet ID |
| `security_group_id` | Security Group ID |
| `instance_id` | EC2 인스턴스 ID |
| `instance_private_ip` | EC2 프라이빗 IP |
| `elastic_ip` | 퍼블릭 Elastic IP |
| `ssh_command` | SSH 접속 명령어 (복사해서 바로 사용 가능) |

## 보안 권장사항

- `allowed_ssh_cidr`: SSH 접근을 특정 IP 주소로 제한하는 것을 권장합니다.
- 기본값은 `0.0.0.0/0`으로 모든 IP에서 접근 가능하므로, 운영 환경에서는 반드시 변경하세요.
- 본인 IP 확인: `curl ifconfig.me` → `allowed_ssh_cidr = ["<본인 IP>/32"]`
