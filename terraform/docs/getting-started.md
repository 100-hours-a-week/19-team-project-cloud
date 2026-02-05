# 시작하기

Terraform을 사용하여 AWS 인프라를 관리하기 위한 초기 설정 가이드입니다.

## 목차

1. [필수 도구 설치](#필수-도구-설치)
2. [AWS 설정](#aws-설정)
3. [프로젝트 구조 이해](#프로젝트-구조-이해)
4. [첫 번째 배포](#첫-번째-배포)

## 필수 도구 설치

### 1. Terraform 설치

#### macOS (Homebrew)

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# 버전 확인
terraform version
# Terraform v1.5.7 이상이어야 함
```

#### Linux (Ubuntu/Debian)

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

#### Windows (Chocolatey)

```powershell
choco install terraform
```

또는 [공식 다운로드 페이지](https://www.terraform.io/downloads)에서 직접 설치.

### 2. AWS CLI 설치

#### macOS

```bash
brew install awscli

# 버전 확인
aws --version
```

#### Linux

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

#### Windows

[AWS CLI 설치 가이드](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) 참고.

### 3. Git (선택사항)

프로젝트 버전 관리를 위해 권장.

```bash
# macOS
brew install git

# Ubuntu/Debian
sudo apt install git
```

## AWS 설정

### 1. AWS 계정 준비

- AWS 계정 필요
- IAM 사용자 또는 역할 권한 필요

### 2. AWS CLI 자격 증명 설정

```bash
aws configure
```

입력 항목:
```
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: ap-northeast-2
Default output format [None]: json
```

### 3. 자격 증명 확인

```bash
# 설정 확인
aws configure list

# 계정 정보 확인
aws sts get-caller-identity
```

출력 예시:
```json
{
    "UserId": "AIDACKCEVSQ6C2EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

### 4. 필요한 IAM 권한

최소 권한:
- EC2: VPC, Subnet, Instance, SecurityGroup 생성/수정/삭제
- S3: Terraform state 버킷 접근
- DynamoDB: State locking 테이블 접근

권장 정책:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "s3:*",
        "dynamodb:*"
      ],
      "Resource": "*"
    }
  ]
}
```

**보안 팁**: 운영 환경에서는 최소 권한 원칙에 따라 구체적인 리소스와 액션만 허용.

## 프로젝트 구조 이해

### 디렉토리 레이아웃

```
terraform/
├── backend-setup/     # 1단계: 백엔드 리소스 생성
├── dev/              # 2단계: 개발 환경 배포
├── prod/             # 3단계: 운영 환경 배포
└── docs/             # 문서
```

### 파일 설명

각 환경 디렉토리의 주요 파일:

- **provider.tf**: AWS provider 설정 및 리전 지정
- **backend.tf**: Terraform state 저장 위치 설정
- **variables.tf**: 변수 정의
- **terraform.tfvars**: 변수 값 설정 (환경별로 다름, Git 제외)
- **terraform.tfvars.example**: 변수 값 예제
- **vpc.tf**: VPC, Subnet, IGW, Route Table
- **security-group.tf**: 보안 그룹 및 규칙
- **ec2.tf**: EC2 인스턴스 및 EBS
- **outputs.tf**: 배포 후 출력 정보

## 첫 번째 배포

### 단계 1: 백엔드 설정

Terraform state를 저장할 S3 버킷과 DynamoDB 테이블 생성.

자세한 내용은 [백엔드 설정 가이드](./backend-setup.md) 참고.

```bash
cd terraform/backend-setup
terraform init
terraform plan
terraform apply
```

### 단계 2: 개발 환경 설정

변수 파일 준비:

```bash
cd ../dev
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
```

필수 수정 항목:
- `key_name`: AWS EC2 키 페어 이름
- `allowed_ssh_cidr`: SSH 접근 허용 IP (보안을 위해 본인 IP로 제한)

### 단계 3: 개발 환경 배포

자세한 내용은 [개발 환경 배포 가이드](./dev-deployment.md) 참고.

```bash
terraform init
terraform plan
terraform apply
```

### 단계 4: 접속 확인

배포 완료 후 출력된 SSH 명령어로 접속:

```bash
# 출력 예시
ssh_command = "ssh -i ~/.ssh/refit.pem ubuntu@13.125.XXX.XXX"

# 접속
ssh -i ~/.ssh/refit.pem ubuntu@13.125.XXX.XXX
```

## Terraform 기본 명령어

### 초기화

```bash
terraform init
```

- provider 플러그인 다운로드
- backend 초기화
- 최초 1회 실행 필요

### 계획 확인

```bash
terraform plan
```

- 변경 사항 미리 확인
- 실제 적용 전 검토

출력 기호:
- `+`: 생성
- `-`: 삭제
- `~`: 수정
- `-/+`: 재생성

### 적용

```bash
terraform apply
```

- 인프라 변경 사항 적용
- 확인 후 `yes` 입력

자동 승인 (주의):
```bash
terraform apply -auto-approve
```

### 삭제

```bash
terraform destroy
```

- 모든 리소스 삭제
- 확인 후 `yes` 입력

### 출력값 확인

```bash
terraform output
terraform output elastic_ip
```

### State 관리

```bash
# State 목록
terraform state list

# State 상세 정보
terraform state show aws_instance.main

# State 새로고침
terraform refresh
```

## 모범 사례

### 1. 변수 파일 관리

- `terraform.tfvars`는 Git에 커밋하지 않음 (.gitignore 설정)
- `terraform.tfvars.example`로 예제 제공
- 민감 정보는 환경 변수나 AWS Secrets Manager 사용

### 2. State 파일 보안

- 원격 백엔드 사용 (S3 + DynamoDB)
- 버전 관리 활성화
- 암호화 활성화
- 로컬 state 파일은 Git에 커밋하지 않음

### 3. 코드 작성

- 리소스 이름에 환경 구분 (dev, prod)
- 태그를 활용한 리소스 관리
- 모듈화로 코드 재사용
- 주석으로 의도 명시

### 4. 협업

- Pull Request로 변경 사항 리뷰
- State locking으로 동시 실행 방지
- 문서화 유지

## 다음 단계

1. ✅ 필수 도구 설치 완료
2. ✅ AWS 자격 증명 설정 완료
3. → [백엔드 설정](./backend-setup.md)
4. → [개발 환경 배포](./dev-deployment.md)

## 추가 학습 자료

### 공식 문서
- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)

### 튜토리얼
- [Terraform Getting Started](https://developer.hashicorp.com/terraform/tutorials/aws-get-started)
- [Terraform AWS Workshop](https://hashicorp.github.io/field-workshops-terraform/)

### 커뮤니티
- [Terraform Community Forum](https://discuss.hashicorp.com/c/terraform-core)
- [r/Terraform](https://www.reddit.com/r/Terraform/)

## 도움이 필요한가요?

문제가 발생하면 [트러블슈팅 가이드](./troubleshooting.md)를 확인하세요.
