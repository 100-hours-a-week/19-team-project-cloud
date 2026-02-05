# Terraform Infrastructure Documentation

Re-Fit 프로젝트의 AWS 인프라를 Terraform으로 관리하기 위한 문서입니다.

## 목차

1. [아키텍처 개요](#아키텍처-개요)
2. [배포 순서](#배포-순서)
3. [디렉토리 구조](#디렉토리-구조)
4. [환경별 상세](#환경별-상세)
5. [시작하기](./getting-started.md)
6. [백엔드 설정](./backend-setup.md)
7. [개발 환경 배포](./dev-deployment.md)
8. [트러블슈팅](./troubleshooting.md)

## 아키텍처 개요

### 인프라 구성 원칙

- **Infrastructure as Code**: 모든 인프라를 코드로 관리
- **환경 분리**: backend-setup, shared, dev 등 용도별로 독립된 Terraform state 관리
- **원격 백엔드**: S3 + DynamoDB를 사용한 state 관리 및 동시 실행 방지
- **보안 우선**: 암호화, IMDSv2, 최소 권한 원칙 적용

### 3계층 구조

Terraform 코드는 역할에 따라 세 계층으로 나뉩니다:

| 계층 | 디렉토리 | 역할 | State 위치 |
|------|----------|------|-----------|
| 1. 부트스트랩 | `backend-setup/` | S3/DynamoDB 백엔드 리소스 생성 | **로컬** (순환 의존 방지) |
| 2. 공유 리소스 | `shared/` | ECR 저장소 등 환경 공통 리소스 | S3 (`shared/terraform.tfstate`) |
| 3. 환경별 인프라 | `dev/` | VPC, EC2, SG 등 환경 전용 리소스 | S3 (`dev/terraform.tfstate`) |

### 주요 컴포넌트

```
┌────────────────────────────────────────────────────────────────────┐
│                        AWS Account (ap-northeast-2)                │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Backend Resources (backend-setup/)                         │   │
│  │  - S3 Bucket: refit-terraform-state (State 파일 저장)      │   │
│  │  - DynamoDB Table: refit-terraform-lock (State Locking)    │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Shared Resources (shared/)                                 │   │
│  │  - ECR: refit-ai          (AI 서비스 컨테이너 이미지)       │   │
│  │  - ECR: refit-frontend    (Frontend 컨테이너 이미지)        │   │
│  │  - ECR: refit-backend     (Backend 컨테이너 이미지)         │   │
│  │  - Lifecycle Policy: 최근 30개 이미지만 유지                │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Dev Environment (dev/)  VPC: 10.1.0.0/16                   │   │
│  │  - Public Subnet (10.1.1.0/24) + Internet Gateway          │   │
│  │  - EC2 Instance (t4g.large, Ubuntu 22.04 ARM64)            │   │
│  │  - Security Group (SSH:22, HTTP:80, HTTPS:443)             │   │
│  │  - Elastic IP (고정 퍼블릭 IP)                              │   │
│  │  - IAM Role + Instance Profile (ECR 읽기 전용)             │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 리소스 간 관계

```
backend-setup/               shared/                    dev/
┌──────────────┐         ┌──────────────┐         ┌──────────────────┐
│ S3 Bucket    │◄────────│ backend "s3" │         │ backend "s3"     │
│ DynamoDB     │◄────────│              │         │                  │
└──────────────┘         │ ECR repos    │────────►│ IAM Policy       │
                         │  - ai        │ (pull)  │  (ECR read-only) │
                         │  - frontend  │         │                  │
                         │  - backend   │         │ EC2 Instance     │
                         └──────────────┘         │  + Instance Prof │
                                                  └──────────────────┘
```

- `backend-setup`이 만든 S3/DynamoDB를 `shared`와 `dev`가 원격 백엔드로 사용
- `shared`가 만든 ECR 저장소에서 `dev`의 EC2가 이미지를 pull (IAM 정책으로 권한 부여)

## 배포 순서

반드시 아래 순서대로 배포해야 합니다:

```
1. backend-setup/  ──►  2. shared/  ──►  3. dev/
   (S3 + DynamoDB)       (ECR repos)       (VPC + EC2 + IAM)
```

1. **backend-setup**: 다른 모든 Terraform 프로젝트의 state 저장소를 먼저 생성
2. **shared**: 환경 간 공유 리소스(ECR) 생성
3. **dev**: 개발 환경 인프라 배포

## 디렉토리 구조

```
terraform/
├── docs/                          # 문서
│   ├── README.md                 # 이 파일 (전체 아키텍처 문서)
│   ├── getting-started.md        # 시작 가이드
│   ├── backend-setup.md          # 백엔드 설정 가이드
│   ├── dev-deployment.md         # 개발 환경 배포 가이드
│   └── troubleshooting.md        # 트러블슈팅 가이드
│
├── backend-setup/                 # [1단계] 백엔드 부트스트랩
│   ├── provider.tf               #   AWS provider (로컬 백엔드)
│   ├── variables.tf              #   변수 정의
│   ├── s3.tf                     #   S3 버킷 (state 저장, 암호화, 버전관리)
│   ├── dynamodb.tf               #   DynamoDB 테이블 (state locking)
│   ├── outputs.tf                #   출력값 (버킷 이름, 테이블 이름 등)
│   └── README.md                 #   백엔드 설정 가이드
│
├── shared/                        # [2단계] 환경 공통 리소스
│   ├── provider.tf               #   AWS provider (태그: Purpose=shared-resources)
│   ├── backend.tf                #   S3 원격 백엔드 (key: shared/terraform.tfstate)
│   ├── variables.tf              #   변수 (서비스 목록, 이미지 보관 개수)
│   ├── ecr.tf                    #   ECR 저장소 3개 + Lifecycle 정책
│   ├── outputs.tf                #   ECR URL, ARN, 이름 맵 출력
│   └── terraform.tfvars.example  #   변수 값 예제
│
├── dev/                           # [3단계] 개발 환경
│   ├── provider.tf               #   AWS provider (태그: Environment=dev)
│   ├── backend.tf                #   S3 원격 백엔드 (key: dev/terraform.tfstate)
│   ├── variables.tf              #   변수 정의
│   ├── terraform.tfvars          #   변수 값 (git 제외)
│   ├── terraform.tfvars.example  #   변수 값 예제
│   ├── vpc.tf                    #   VPC, Subnet, IGW, Route Table
│   ├── security-group.tf         #   보안 그룹 (SSH, HTTP, HTTPS)
│   ├── ec2.tf                    #   EC2 인스턴스 + Elastic IP
│   ├── iam.tf                    #   IAM Role + ECR 읽기 정책 + Instance Profile
│   ├── outputs.tf                #   출력값 (IP, SSH 명령어 등)
│   └── README.md                 #   개발 환경 가이드
│
└── prod/                          # 운영 환경 (참고용)
    └── kobe/                     #   운영 서버
```

## 환경별 상세

### 1. Backend Setup (`backend-setup/`)

Terraform state 파일의 중앙 저장소를 생성하는 부트스트랩 프로젝트입니다.

| 항목 | 설명 |
|------|------|
| **목적** | 다른 Terraform 프로젝트를 위한 원격 백엔드 인프라 생성 |
| **백엔드** | 로컬 (순환 의존 방지 — 자기 자신의 state를 S3에 저장할 수 없음) |
| **삭제 보호** | `prevent_destroy = true` (S3, DynamoDB 모두) |

**생성 리소스:**

| 리소스 | 이름 | 주요 설정 |
|--------|------|----------|
| S3 Bucket | `refit-terraform-state` | AES256 암호화, 버전 관리, 퍼블릭 액세스 차단, 90일 이후 구버전 삭제 |
| DynamoDB Table | `refit-terraform-lock` | PAY_PER_REQUEST, Hash Key: `LockID` |

**State 파일 경로 규칙:**
```
s3://refit-terraform-state/
├── shared/terraform.tfstate    ← shared/ 프로젝트의 state
├── dev/terraform.tfstate       ← dev/ 프로젝트의 state
└── prod/terraform.tfstate      ← (향후) prod/ 프로젝트의 state
```

### 2. Shared Resources (`shared/`)

환경(dev/prod)에 관계없이 공통으로 사용하는 리소스를 관리합니다.

| 항목 | 설명 |
|------|------|
| **목적** | 컨테이너 이미지 저장소(ECR) 관리 |
| **백엔드** | S3 원격 (`shared/terraform.tfstate`) |

**생성 리소스:**

| 리소스 | 이름 | 주요 설정 |
|--------|------|----------|
| ECR Repository | `refit-ai` | AI 서비스 이미지, AES256 암호화, push 시 보안 스캔 |
| ECR Repository | `refit-frontend` | Frontend 이미지, AES256 암호화, push 시 보안 스캔 |
| ECR Repository | `refit-backend` | Backend 이미지, AES256 암호화, push 시 보안 스캔 |
| Lifecycle Policy | 각 저장소 | 최근 30개 이미지만 유지, 초과분 자동 삭제 |

**서비스 목록 변경 방법:**

`variables.tf`의 `ecr_services` 기본값을 수정하거나 `terraform.tfvars`에서 오버라이드:
```hcl
ecr_services = ["ai", "frontend", "backend", "new-service"]
```

### 3. Dev Environment (`dev/`)

개발 환경의 전체 인프라(네트워크, 서버, 보안)를 관리합니다.

| 항목 | 설명 |
|------|------|
| **목적** | 개발용 VPC + EC2 서버 운영 |
| **백엔드** | S3 원격 (`dev/terraform.tfstate`) |

**생성 리소스:**

| 구분 | 리소스 | 이름 | 주요 설정 |
|------|--------|------|----------|
| 네트워크 | VPC | `refit-dev-vpc` | CIDR 10.1.0.0/16, DNS 활성화 |
| | Public Subnet | `refit-dev-public-subnet` | CIDR 10.1.1.0/24, ap-northeast-2a |
| | Internet Gateway | `refit-dev-igw` | VPC에 연결 |
| | Route Table | `refit-dev-public-rt` | 0.0.0.0/0 → IGW |
| 보안 | Security Group | `refit-dev-sg` | Inbound: SSH(22), HTTP(80), HTTPS(443) / Outbound: 전체 허용 |
| 컴퓨팅 | EC2 Instance | `refit-dev-server` | t4g.large (ARM), Ubuntu 22.04, gp3 30GB 암호화 EBS |
| | Elastic IP | `refit-dev-eip` | EC2에 연결된 고정 퍼블릭 IP |
| IAM | IAM Role | `refit-dev-ec2-role` | EC2 서비스 assume role |
| | IAM Policy | `refit-dev-ecr-read` | ECR 이미지 pull 권한 (`refit-*` 저장소) |
| | Instance Profile | `refit-dev-ec2-profile` | EC2에 IAM Role 연결 |

**보안 하이라이트:**
- IMDSv2 강제 적용 (`http_tokens = required`)
- EBS 루트 볼륨 암호화
- IAM 최소 권한 원칙: ECR `refit-*` 저장소에 대한 읽기만 허용
- AMI 변경 무시 (`ignore_changes = [ami]`) — 인스턴스 재생성 방지

## 다음 단계

1. [시작하기](./getting-started.md) - 초기 설정 및 도구 설치
2. [백엔드 설정](./backend-setup.md) - 원격 백엔드 구성
3. [개발 환경 배포](./dev-deployment.md) - dev 환경 인프라 배포
4. [트러블슈팅](./troubleshooting.md) - 자주 발생하는 문제 해결

## 참고 자료

- [Terraform 공식 문서](https://developer.hashicorp.com/terraform/docs)
- [AWS Provider 문서](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
