# Terraform Infrastructure Documentation

Re-Fit 프로젝트의 AWS 인프라를 Terraform으로 관리하기 위한 문서입니다.

## 목차

1. [아키텍처 개요](#아키텍처-개요)
2. [디렉토리 구조](#디렉토리-구조)
3. [시작하기](./getting-started.md)
4. [백엔드 설정](./backend-setup.md)
5. [개발 환경 배포](./dev-deployment.md)
6. [트러블슈팅](./troubleshooting.md)

## 아키텍처 개요

### 인프라 구성 원칙

- **Infrastructure as Code**: 모든 인프라를 코드로 관리
- **환경 분리**: dev, prod 등 환경별로 독립된 리소스 관리
- **원격 백엔드**: S3 + DynamoDB를 사용한 state 관리
- **보안 우선**: 암호화, IMDSv2, 최소 권한 원칙 적용

### 주요 컴포넌트

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS Account                              │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Backend Resources (공통)                              │   │
│  │  - S3: refit-terraform-state                         │   │
│  │  - DynamoDB: refit-terraform-lock                    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Dev Environment (10.1.0.0/16)                        │   │
│  │  - VPC                                                │   │
│  │  - Public Subnet (10.1.1.0/24)                       │   │
│  │  - EC2 Instance (t4g.large)                          │   │
│  │  - Security Group                                     │   │
│  │  - Elastic IP                                         │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Prod Environment (10.0.0.0/16)                       │   │
│  │  - VPC                                                │   │
│  │  - Public Subnet (10.0.1.0/24)                       │   │
│  │  - EC2 Instance (t4g.medium)                         │   │
│  │  - Security Group                                     │   │
│  │  - Elastic IP                                         │   │
│  │  - S3 Bucket (app files)                             │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## 디렉토리 구조

```
terraform/
├── docs/                      # 문서 디렉토리
│   ├── README.md             # 이 파일
│   ├── getting-started.md    # 시작 가이드
│   ├── backend-setup.md      # 백엔드 설정 가이드
│   ├── dev-deployment.md     # 개발 환경 배포 가이드
│   └── troubleshooting.md    # 트러블슈팅 가이드
│
├── backend-setup/            # 백엔드 리소스 관리
│   ├── provider.tf           # AWS provider 설정
│   ├── variables.tf          # 변수 정의
│   ├── s3.tf                 # S3 버킷 (state 저장)
│   ├── dynamodb.tf           # DynamoDB 테이블 (state locking)
│   ├── outputs.tf            # 출력값
│   └── README.md             # 백엔드 설정 가이드
│
├── dev/                      # 개발 환경
│   ├── backend.tf            # S3 원격 백엔드 설정
│   ├── provider.tf           # AWS provider 설정
│   ├── variables.tf          # 변수 정의
│   ├── terraform.tfvars      # 변수 값 (git 제외)
│   ├── terraform.tfvars.example  # 변수 값 예제
│   ├── vpc.tf                # VPC, Subnet, IGW, Route Table
│   ├── security-group.tf     # 보안 그룹
│   ├── ec2.tf                # EC2 인스턴스
│   ├── outputs.tf            # 출력값
│   └── README.md             # 개발 환경 가이드
│
└── prod/                     # 운영 환경
    └── kobe/                 # 운영 서버
        ├── backend.tf        # S3 원격 백엔드 설정 (추후 추가)
        ├── provider.tf
        ├── variables.tf
        ├── vpc.tf
        ├── security-group.tf
        ├── ec2.tf
        ├── s3.tf
        └── outputs.tf
```

## 환경별 특징

### Backend Setup (공통)

- **목적**: Terraform state 파일을 저장하고 locking을 관리
- **백엔드**: 로컬 state 사용 (백엔드 리소스 자체는 로컬 관리)
- **리소스**:
  - S3 버킷: `refit-terraform-state`
  - DynamoDB 테이블: `refit-terraform-lock`
- **특징**:
  - 버전 관리 활성화
  - 암호화 활성화
  - 90일 지난 버전 자동 삭제
  - prevent_destroy로 삭제 방지

### Dev Environment

- **VPC CIDR**: 10.1.0.0/16
- **Public Subnet**: 10.1.1.0/24
- **Instance Type**: t4g.large (vCPU: 2, RAM: 8GB)
- **OS**: Ubuntu 22.04 LTS ARM64
- **백엔드**: S3 원격 백엔드 (key: `dev/terraform.tfstate`)
- **보안**:
  - IMDSv2 강제
  - EBS 암호화
  - SSH, HTTP, HTTPS 포트 개방

### Prod Environment (Kobe)

- **VPC CIDR**: 10.0.0.0/16
- **Public Subnet**: 10.0.1.0/24
- **Instance Type**: t4g.medium (vCPU: 2, RAM: 4GB)
- **OS**: Ubuntu 22.04 LTS ARM64
- **추가 리소스**: S3 버킷 (애플리케이션 파일 저장)
- **백엔드**: 향후 원격 백엔드로 전환 예정

## 다음 단계

1. [시작하기](./getting-started.md) - 초기 설정 및 도구 설치
2. [백엔드 설정](./backend-setup.md) - 원격 백엔드 구성 (완료)
3. [개발 환경 배포](./dev-deployment.md) - dev 환경 인프라 배포
4. [트러블슈팅](./troubleshooting.md) - 자주 발생하는 문제 해결

## 참고 자료

- [Terraform 공식 문서](https://developer.hashicorp.com/terraform/docs)
- [AWS Provider 문서](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
