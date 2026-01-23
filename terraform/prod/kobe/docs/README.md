# Re-Fit Terraform 프로덕션 인프라 문서

이 문서는 Terraform 초보자를 위한 Re-Fit 프로덕션 환경 인프라 가이드입니다.

## 목차
- [전체 구조 요약](#전체-구조-요약)
- [Terraform 파일 역할 설명](#terraform-파일-역할-설명)
- [실행 순서](#실행-순서)
- [주요 명령어](#주요-명령어)
- [인프라 구성도](#인프라-구성도)

---

## 전체 구조 요약

**프로젝트**: Re-Fit 프로덕션 서버
**리전**: ap-northeast-2 (서울)
**환경**: Production
**주요 구성**: VPC + EC2 + Security Group + Elastic IP + S3

---

## Terraform 파일 역할 설명

### 1. provider.tf - "어떤 클라우드를 사용할지"

**역할**: AWS를 사용한다고 선언하는 파일

```hcl
- Terraform 버전: >= 1.0.0
- AWS 프로바이더 버전: ~> 5.0
- 리전: ap-northeast-2 (서울)
- AWS 프로필: refit-kobe
- 자동 태그: Project, Environment, ManagedBy
```

**비유**: 어떤 건설 회사와 계약할지 정하는 계약서

**주요 내용**:
- AWS와의 연결 설정
- 리전을 변수로 관리 (var.aws_region)
- AWS 프로필 지정 (profile = "refit-kobe")
- 모든 리소스에 자동으로 붙는 기본 태그 설정

**현재 설정된 프로필**:
- Profile: `refit-kobe`
- Account: 807210685804
- Role: AdministratorAccess

---

### 2. terraform.tf - "상태를 어디에 저장할지"

**역할**: Terraform이 관리하는 인프라 상태를 저장할 위치 설정

```hcl
- 백엔드: local 파일 시스템
- 상태 파일: terraform.tfstate
```

**비유**: 공사 진행 상황을 기록하는 노트 보관 장소

**주요 내용**:
- 현재는 로컬 파일에 상태 저장
- 팀 협업 시에는 S3 + DynamoDB 백엔드로 변경 권장

**주의사항**:
- terraform.tfstate 파일은 절대 삭제하면 안 됨
- Git에 커밋하지 않도록 .gitignore에 추가 필요

---

### 3. variables.tf - "설정 가능한 값들의 목록"

**역할**: 사용자가 변경할 수 있는 변수들의 "정의"

**비유**: 주문서 양식 (빈 칸과 기본값만 있음)

**주요 변수**:

#### General (일반 설정)
- `aws_region`: AWS 리전 (기본값: ap-northeast-2)
- `project_name`: 프로젝트 이름 (기본값: refit)
- `environment`: 환경 (기본값: prod)

#### VPC (네트워크 설정)
- `vpc_cidr`: VPC CIDR 블록 (기본값: 10.0.0.0/16)
- `public_subnet_cidr`: 퍼블릭 서브넷 CIDR (기본값: 10.0.1.0/24)
- `availability_zone`: 가용 영역 (기본값: ap-northeast-2a)

#### EC2 (서버 설정)
- `instance_type`: 인스턴스 타입 (기본값: t4g.medium)
- `key_name`: SSH 키 페어 이름 (필수 입력)
- `root_volume_size`: 루트 볼륨 크기 (기본값: 30GB)

#### Security Group (보안 설정)
- `allowed_ssh_cidr`: SSH 접근 허용 IP (기본값: 0.0.0.0/0)
- `allowed_db_cidr`: PostgreSQL 접근 허용 IP (기본값: [])

---

### 4. terraform.tfvars - "실제 사용할 값"

**역할**: variables.tf에 정의된 변수에 실제 값을 입력

**비유**: 작성 완료된 주문서 (실제 값이 채워진 상태)

**설정된 값**:
```hcl
aws_region         = "ap-northeast-2"
project_name       = "refit"
environment        = "prod"
vpc_cidr           = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"
availability_zone  = "ap-northeast-2a"
instance_type      = "t4g.medium"
key_name           = "refit"
root_volume_size   = 30
allowed_ssh_cidr   = ["0.0.0.0/0"]
allowed_db_cidr    = ["0.0.0.0/0"]  # ⚠️ PostgreSQL 포트 전체 공개 (보안 위험)
```

**현재 보안 상태**:
- ⚠️ SSH 포트(22)가 전체 인터넷에 공개됨
- ⚠️ PostgreSQL 포트(5432)가 전체 인터넷에 공개됨
- 프로덕션 환경에서는 특정 IP로 제한 필수!

**보안 권장사항**:
- `allowed_ssh_cidr`을 특정 IP로 제한 권장 (예: ["123.45.67.89/32"])
- `allowed_db_cidr`을 빈 리스트 `[]` 또는 특정 IP로 제한 (예: ["10.0.0.0/16"])

---

### 5. vpc.tf - "네트워크 구성"

**역할**: AWS 내부 네트워크 인프라 생성

**비유**: 건물의 네트워크 배선, 인터넷 회선 설치

**생성되는 리소스**:

#### VPC (Virtual Private Cloud)
- CIDR: 10.0.0.0/16
- DNS 호스트 이름 활성화
- DNS 지원 활성화

#### Internet Gateway
- VPC와 인터넷을 연결하는 게이트웨이
- 퍼블릭 서브넷의 인스턴스가 인터넷 접속 가능

#### Public Subnet
- CIDR: 10.0.1.0/24
- 가용 영역: ap-northeast-2a
- 자동 퍼블릭 IP 할당 활성화

#### Route Table
- 모든 트래픽(0.0.0.0/0)을 Internet Gateway로 라우팅
- 퍼블릭 서브넷과 연결

**네트워크 구조**:
```
Internet
    ↓
Internet Gateway
    ↓
Route Table (0.0.0.0/0 → IGW)
    ↓
Public Subnet (10.0.1.0/24)
    ↓
EC2 Instance
```

---

### 6. security-group.tf - "방화벽 규칙"

**역할**: 서버로 들어오고 나가는 트래픽 제어

**비유**: 건물 출입문과 보안 규칙 (누가, 어떤 문으로 들어올 수 있는지)

**Ingress Rules (인바운드 - 들어오는 트래픽)**:

| 포트 | 프로토콜 | 허용 범위 | 용도 | 현재 상태 |
|------|----------|-----------|------|-----------|
| 22 | TCP | 0.0.0.0/0 | SSH 접속 | ⚠️ 전체 공개 |
| 80 | TCP | 0.0.0.0/0 | HTTP 웹 서비스 | ✅ 정상 |
| 443 | TCP | 0.0.0.0/0 | HTTPS 웹 서비스 | ✅ 정상 |
| 5432 | TCP | 0.0.0.0/0 | PostgreSQL | ⚠️ 전체 공개 (위험) |

**Egress Rules (아웃바운드 - 나가는 트래픽)**:
- 모든 트래픽 허용 (0.0.0.0/0, all protocols)

**현재 보안 상태**:
- ⚠️ **SSH 포트(22)가 전체 인터넷에 공개**: 무차별 대입 공격에 취약
- ⚠️ **PostgreSQL 포트(5432)가 전체 인터넷에 공개**: 데이터베이스 직접 공격 가능
- 프로덕션 환경에서는 즉시 보안 설정 변경 필요!

**보안 강화 방법**:
1. SSH 포트(22)는 특정 IP로 제한 (예: 회사 IP만 허용)
2. PostgreSQL 포트(5432)는:
   - VPC 내부에서만 접근: `["10.0.0.0/16"]`
   - 또는 완전 차단: `[]` (애플리케이션은 localhost로 접속)
3. 웹 서비스 포트(80, 443)는 전체 공개 유지

---

### 7. ec2.tf - "실제 서버 생성"

**역할**: EC2 인스턴스(가상 서버) 생성 및 Elastic IP 할당

**비유**: 실제 컴퓨터 구매하고 설치하기

**EC2 인스턴스 설정**:

#### AMI (운영체제 이미지)
- **Ubuntu 22.04 LTS (Jammy) ARM64**
- Canonical 공식 이미지 (소유자 ID: 099720109477)
- 최신 버전 자동 선택 (`most_recent = true`)
- Data Source를 통한 동적 AMI 검색
- LTS 지원 기간: 2027년 4월까지

#### 인스턴스 스펙
- 타입: t4g.medium (ARM 기반 Graviton 프로세서)
- vCPU: 2코어
- 메모리: 4GB
- 비용 효율적 (x86 대비 20% 저렴)

#### 스토리지
- 볼륨 타입: gp3 (SSD)
- 크기: 30GB
- 암호화: 활성화
- 인스턴스 종료 시 삭제: 활성화

#### 보안 설정
- IMDSv2 강제 (메타데이터 서비스 보안 강화)
- http_tokens = required

#### Lifecycle
- AMI 변경으로 인한 재생성 방지
- 운영 중인 서버의 안정성 보장

**Elastic IP (고정 공인 IP)**:
- 서버 재시작 시에도 IP 주소 유지
- DNS 설정에 유용
- EC2 인스턴스와 자동 연결

---

### 8. outputs.tf - "생성 후 확인할 정보"

**역할**: 인프라 생성 후 필요한 정보 출력

**비유**: 공사 완료 후 받는 준공 보고서 (주소, 연락처 등)

**출력되는 정보**:

#### VPC 정보
- `vpc_id`: VPC의 ID
- `vpc_cidr`: VPC의 CIDR 블록
- `public_subnet_id`: 퍼블릭 서브넷 ID

#### Security Group 정보
- `security_group_id`: 보안 그룹 ID

#### EC2 정보
- `instance_id`: EC2 인스턴스 ID
- `instance_private_ip`: 프라이빗 IP 주소
- `elastic_ip`: 퍼블릭 IP 주소 (고정 IP)

#### S3 정보
- `s3_bucket_name`: S3 버킷 이름
- `s3_bucket_arn`: S3 버킷 ARN
- `s3_bucket_domain`: S3 버킷 도메인
- `s3_bucket_url`: S3 버킷 URL

#### 편의 기능
- `ansible_inventory`: Ansible 인벤토리 포맷으로 출력
- `ssh_command`: SSH 접속 명령어 자동 생성

**사용 예시**:
```bash
# 모든 출력 보기
terraform output

# 특정 출력만 보기
terraform output elastic_ip

# SSH 접속 명령어 복사
terraform output ssh_command

# S3 버킷 이름 확인
terraform output s3_bucket_name
```

---

### 9. s3.tf - "파일 저장소"

**역할**: 애플리케이션 파일(이미지, 동영상 등)을 저장하는 S3 버킷 생성

**비유**: 온라인 창고 (파일을 안전하게 보관하고 인터넷으로 접근 가능)

**S3 버킷 설정**:

#### 기본 설정
- **버킷 이름**: `refit-prod-files`
- **용도**: 애플리케이션 파일 저장 (이미지, 동영상, 문서 등)
- **접근 방식**: 퍼블릭 읽기 허용 (웹에서 접근 가능)

#### 보안 설정
- **버전 관리**: 활성화 (파일 실수 삭제 시 복구 가능)
- **암호화**: AES256 서버측 암호화
- **퍼블릭 액세스**: 읽기(GET)만 허용

#### CORS 설정
- 웹 애플리케이션에서 파일 업로드/다운로드 가능
- 허용 메서드: GET, HEAD, PUT, POST
- 모든 오리진 허용

#### Lifecycle 정책
- **이전 버전 삭제**: 90일 후 자동 삭제
- **불완전한 업로드**: 7일 후 자동 삭제

**사용 예시**:
```bash
# S3 버킷에 파일 업로드 (AWS CLI)
aws s3 cp image.jpg s3://refit-prod-files/images/

# 웹에서 접근
https://refit-prod-files.s3.ap-northeast-2.amazonaws.com/images/image.jpg
```

**애플리케이션 코드 예시** (Node.js):
```javascript
const AWS = require('aws-sdk');
const s3 = new AWS.S3();

// 파일 업로드
await s3.putObject({
  Bucket: 'refit-prod-files',
  Key: 'images/profile.jpg',
  Body: fileBuffer,
  ContentType: 'image/jpeg'
}).promise();

// 파일 URL 생성
const url = `https://refit-prod-files.s3.ap-northeast-2.amazonaws.com/images/profile.jpg`;
```

---

## 실행 순서

### 0. AWS 자격 증명 설정 (최초 1회)

Terraform이 AWS에 접근하려면 자격 증명이 필요합니다.

#### AWS 액세스 키 발급

1. [AWS IAM 콘솔](https://console.aws.amazon.com/iam/) 접속
2. Users → 본인 계정 선택
3. "Security credentials" 탭
4. "Create access key" 클릭
5. **Use case**: Command Line Interface (CLI) 선택
6. Access Key ID와 Secret Access Key 복사 (⚠️ 한 번만 표시됨!)

#### 방법 1: AWS CLI로 설정 (권장)

```bash
aws configure
```

입력 항목:
```
AWS Access Key ID [None]: your-access-key-id
AWS Secret Access Key [None]: your-secret-access-key
Default region name [None]: ap-northeast-2
Default output format [None]: json
```

#### 방법 2: 환경 변수로 설정

```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="ap-northeast-2"
```

#### 방법 3: 자격 증명 파일 직접 생성

```bash
mkdir -p ~/.aws

cat > ~/.aws/credentials << 'EOF'
[default]
aws_access_key_id = your-access-key-id
aws_secret_access_key = your-secret-access-key
EOF

cat > ~/.aws/config << 'EOF'
[default]
region = ap-northeast-2
output = json
EOF
```

#### 설정 확인

```bash
aws sts get-caller-identity
```

성공하면 다음과 같이 출력됩니다:
```json
{
    "UserId": "AIDAXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

#### AWS 프로필 사용 (여러 계정 관리 시)

여러 AWS 계정을 사용하는 경우, 프로필을 설정할 수 있습니다:

**프로필 설정**:
```bash
aws configure --profile refit-kobe
```

**프로필 확인**:
```bash
aws sts get-caller-identity --profile refit-kobe
```

**Terraform에서 프로필 사용**:

[provider.tf](../provider.tf)에서 프로필 지정:
```hcl
provider "aws" {
  region  = var.aws_region
  profile = "refit-kobe"  # 프로필 이름 지정
  ...
}
```

또는 환경 변수로 설정:
```bash
export AWS_PROFILE=refit-kobe
```

---

### 1. 초기화
```bash
terraform init
```
- 프로바이더 플러그인 다운로드
- 백엔드 초기화
- 모듈 다운로드 (있는 경우)

### 2. 변수 설정
- `terraform.tfvars` 파일 확인 및 수정
- 특히 `key_name` 값이 AWS에 등록된 키페어와 일치하는지 확인

### 3. 계획 확인
```bash
terraform plan
```
- 어떤 리소스가 생성/변경/삭제될지 미리 확인
- 오류가 있는지 검증

### 4. 인프라 생성
```bash
terraform apply
```
- 실제로 AWS 리소스 생성
- 확인 메시지에서 'yes' 입력
- 약 2-3분 소요

### 5. 결과 확인
```bash
terraform output
```
- 생성된 리소스 정보 확인
- SSH 접속 명령어 확인

### 6. 서버 접속
```bash
ssh -i ~/.ssh/refit.pem ubuntu@<ELASTIC_IP>
```

### 7. 인프라 삭제 (필요시)
```bash
terraform destroy
```
- 모든 리소스 삭제
- 비용 절감을 위해 사용하지 않을 때 삭제 가능

---

## 주요 명령어

| 명령어 | 설명 |
|--------|------|
| `terraform init` | Terraform 초기화 (최초 1회) |
| `terraform validate` | 문법 검증 |
| `terraform fmt` | 코드 포맷팅 |
| `terraform plan` | 실행 계획 미리보기 |
| `terraform apply` | 인프라 생성/변경 |
| `terraform destroy` | 인프라 삭제 |
| `terraform output` | 출력 값 확인 |
| `terraform show` | 현재 상태 확인 |
| `terraform state list` | 관리 중인 리소스 목록 |

---

## 인프라 구성도

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS ap-northeast-2                        │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ VPC (10.0.0.0/16)                                      │ │
│  │                                                         │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │ Public Subnet (10.0.1.0/24) - ap-northeast-2a   │ │ │
│  │  │                                                   │ │ │
│  │  │  ┌─────────────────────────────────────────┐    │ │ │
│  │  │  │ EC2 Instance (t4g.medium)               │    │ │ │
│  │  │  │ - Ubuntu 22.04 LTS ARM64 (Jammy)        │    │ │ │
│  │  │  │ - 30GB gp3 (암호화)                     │    │ │ │
│  │  │  │ - Private IP: 10.0.1.x                  │    │ │ │
│  │  │  │                                          │    │ │ │
│  │  │  │ Security Group:                         │    │ │ │
│  │  │  │ - Inbound: 22, 80, 443, 5432 (⚠️)     │    │ │ │
│  │  │  │ - Outbound: All                        │    │ │ │
│  │  │  └─────────────────────────────────────────┘    │ │ │
│  │  │                      ↕                            │ │ │
│  │  │               Elastic IP (고정)                   │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  │                        ↕                               │ │
│  │                Internet Gateway                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                          ↕                                   │
└──────────────────────────────────────────────────────────────┘
                           ↕
                      Internet
```

---

## 비용 예상

**월 예상 비용 (서울 리전 기준)**:
- EC2 t4g.medium: 약 $30
- EBS gp3 30GB: 약 $3
- Elastic IP: 무료 (인스턴스 연결 시)
- S3 스토리지: 첫 50TB $0.025/GB (예: 100GB = $2.5)
- S3 요청: GET $0.0004/1000건, PUT $0.005/1000건
- 데이터 전송: 사용량에 따라 변동

**총 예상**: 약 $35-40/월 (S3 사용량에 따라 변동)

---

## 보안 권장사항

### ⚠️ 현재 보안 문제 (즉시 조치 필요)

**현재 상태**: SSH(22)와 PostgreSQL(5432) 포트가 전체 인터넷(0.0.0.0/0)에 공개되어 있습니다.

**즉시 조치사항**:

1. **SSH 접근 제한 (최우선)**
   ```hcl
   # terraform.tfvars
   allowed_ssh_cidr = ["YOUR_IP/32"]  # 본인 IP만 허용
   ```
   - 예: `["123.45.67.89/32"]` (본인 고정 IP만)
   - 예: `["123.45.67.0/24"]` (회사 네트워크만)

2. **PostgreSQL 포트 보안 (최우선)**
   ```hcl
   # terraform.tfvars
   allowed_db_cidr = []  # 외부 접속 완전 차단 (권장)
   # 또는
   allowed_db_cidr = ["10.0.0.0/16"]  # VPC 내부만 허용
   ```
   - 애플리케이션은 localhost(127.0.0.1)로 DB 접속
   - 외부 DB 클라이언트는 SSH 터널링 사용

3. **변경 적용**
   ```bash
   terraform plan   # 변경사항 확인
   terraform apply  # 적용
   ```

### 일반 보안 권장사항

4. **키 페어 관리**
   - SSH 키는 안전한 곳에 보관
   - 권한 설정: `chmod 400 ~/.ssh/refit.pem`
   - 정기적으로 키 로테이션

5. **정기 업데이트**
   - 서버 접속 후 정기적으로 `apt update && apt upgrade`
   - Ubuntu 22.04 LTS는 2027년 4월까지 보안 업데이트 제공

6. **백업**
   - 중요 데이터는 S3나 별도 볼륨에 백업
   - 자동 스냅샷 설정

7. **모니터링**
   - CloudWatch 알람 설정
   - 비정상적인 트래픽 감지
   - 실패한 SSH 로그인 시도 모니터링

---

## 문제 해결

### AWS 자격 증명 오류
```
Error: No valid credential sources found
Error: failed to refresh cached credentials
```
**원인**: AWS 자격 증명이 설정되지 않음

**해결**:
1. AWS CLI 설치 확인: `aws --version`
2. 자격 증명 설정: `aws configure`
3. 설정 확인: `aws sts get-caller-identity`
4. 자세한 내용은 [실행 순서 - 0. AWS 자격 증명 설정](#0-aws-자격-증명-설정-최초-1회) 참고

### 키 페어 오류
```
Error: InvalidKeyPair.NotFound
```
**원인**: terraform.tfvars의 key_name이 AWS에 등록되지 않음

**해결**:
1. AWS 콘솔 → EC2 → Key Pairs에서 키 페어 생성
2. `terraform.tfvars`의 `key_name` 수정

### 리소스 한도 초과
```
Error: VPC limit exceeded
```
**해결**: AWS 지원팀에 한도 증가 요청

### 상태 파일 충돌
```
Error: state locked
```
**해결**: 다른 terraform 프로세스 종료 후 재시도

---

## 다음 단계

1. **Ansible 연동**: outputs.tf의 ansible_inventory 활용
2. **CI/CD 구축**: GitHub Actions와 연동
3. **백엔드 변경**: S3 + DynamoDB로 원격 상태 관리
4. **모니터링 추가**: CloudWatch 알람 설정
5. **Auto Scaling**: 트래픽에 따른 자동 확장

---

## 참고 자료

- [Terraform AWS 프로바이더 문서](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS VPC 사용 설명서](https://docs.aws.amazon.com/vpc/)
- [AWS EC2 인스턴스 타입](https://aws.amazon.com/ec2/instance-types/)
- [Terraform 공식 문서](https://www.terraform.io/docs)

---

**작성일**: 2026-01-23
**최종 수정**: 2026-01-23
**버전**: 1.4.0
**프로젝트**: Re-Fit Production Infrastructure

## 변경 이력

### v1.4.0 (2026-01-23)
- S3 버킷 추가: 애플리케이션 파일 저장용
- s3.tf 파일 생성 (7개 리소스)
- outputs.tf에 S3 정보 추가
- 문서에 s3.tf 섹션 추가
- 비용 예상에 S3 비용 추가
- 총 리소스: 14개 → 21개

### v1.3.0 (2026-01-23)
- AWS 프로필 설정 추가: `profile = "refit-kobe"`
- provider.tf에 프로필 정보 업데이트
- AWS 프로필 사용 가이드 추가
- Terraform init 및 plan 테스트 완료

### v1.2.0 (2026-01-23)
- AWS 자격 증명 설정 가이드 추가
- 실행 순서에 "0. AWS 자격 증명 설정" 단계 추가
- 문제 해결 섹션에 AWS credentials 오류 해결 방법 추가
- 키 페어 오류 해결 방법 개선

### v1.1.0 (2026-01-23)
- Ubuntu 버전 변경: 24.04 → 22.04 LTS (Jammy)
- PostgreSQL 포트 활성화: allowed_db_cidr = ["0.0.0.0/0"]
- 보안 경고 추가: SSH 및 DB 포트 전체 공개 상태
- 보안 권장사항 강화 및 즉시 조치사항 추가

### v1.0.0 (2026-01-23)
- 초기 문서 작성
