# 트러블슈팅 가이드

Terraform 사용 중 발생할 수 있는 일반적인 문제와 해결 방법을 정리한 문서입니다.

## 목차

1. [State Lock 관련](#state-lock-관련)
2. [Backend 관련](#backend-관련)
3. [AWS 인증 관련](#aws-인증-관련)
4. [리소스 생성 실패](#리소스-생성-실패)
5. [SSH 접속 문제](#ssh-접속-문제)
6. [기타 문제](#기타-문제)

## State Lock 관련

### 문제: State Lock 에러

**증상**:
```
Error: Error acquiring the state lock

Error message: ConditionalCheckFailedException: The conditional request failed
Lock Info:
  ID:        01397b77-e16d-47d5-b6ef-af5e5509a2a3
  Path:      refit-terraform-state/dev/terraform.tfstate
  Operation: OperationTypePlan
  Who:       yoonseo@yseo-MacBookPro.local
  Version:   1.5.7
  Created:   2026-02-03 05:02:39.664006 +0000 UTC
```

**원인**:
- 다른 Terraform 프로세스가 실행 중
- 이전 실행이 비정상 종료되어 lock이 남아있음
- VSCode Terraform 확장이 백그라운드에서 실행 중

**해결 방법**:

1. 실행 중인 Terraform 프로세스 확인:
```bash
ps aux | grep terraform | grep -v grep
```

2. 실행 중인 프로세스가 없다면 강제 unlock:
```bash
cd terraform/dev
terraform force-unlock -force <LOCK_ID>
```

Lock ID는 에러 메시지의 `ID:` 항목에서 확인.

예시:
```bash
terraform force-unlock -force 01397b77-e16d-47d5-b6ef-af5e5509a2a3
```

3. 성공 확인:
```
Terraform state has been successfully unlocked!
```

**예방**:
- Terraform 실행 중 강제 종료(Ctrl+C) 피하기
- 하나의 터미널에서만 실행

### 문제: 여러 곳에서 동시 실행

**증상**:
```
Error: Error acquiring the state lock
```

**원인**:
여러 개발자나 CI/CD가 동시에 terraform 실행

**해결**:
DynamoDB locking이 정상 작동하는 것이므로:
1. 먼저 실행된 작업이 완료될 때까지 대기
2. 완료 후 다시 실행

**팁**:
- CI/CD 파이프라인에서 순차 실행 설정
- 팀원 간 작업 시간 조율

## Backend 관련

### 문제: Backend Configuration Changed

**증상**:
```
Error: Backend configuration changed

A change in the backend configuration has been detected, which may require
migrating existing state.

If you wish to attempt automatic migration of the state, use "terraform
init -migrate-state".
```

**원인**:
backend.tf 파일의 설정이 변경됨

**해결**:

1. 기존 state를 새 백엔드로 마이그레이션:
```bash
terraform init -migrate-state
```

2. 또는 새로 시작 (기존 state 무시):
```bash
terraform init -reconfigure
```

**주의**: `-reconfigure`는 기존 state를 버리므로 신중히 사용!

### 문제: S3 버킷이 없음

**증상**:
```
Error: Failed to get existing workspaces: S3 bucket does not exist
```

**원인**:
backend에 지정된 S3 버킷이 존재하지 않음

**해결**:

1. S3 버킷 확인:
```bash
aws s3 ls | grep terraform
```

2. 버킷이 없다면 backend-setup으로 생성:
```bash
cd terraform/backend-setup
terraform apply
```

3. dev 환경 재초기화:
```bash
cd ../dev
terraform init
```

### 문제: DynamoDB 테이블이 없음

**증상**:
State lock 기능이 작동하지 않음

**원인**:
DynamoDB 테이블이 존재하지 않음

**해결**:

1. DynamoDB 테이블 확인:
```bash
aws dynamodb list-tables --region ap-northeast-2 | grep terraform
```

2. 테이블이 없다면 backend-setup으로 생성:
```bash
cd terraform/backend-setup
terraform apply
```

## AWS 인증 관련

### 문제: AWS 자격 증명 에러

**증상**:
```
Error: error configuring Terraform AWS Provider: no valid credential sources found
```

**원인**:
AWS CLI가 설정되지 않았거나 자격 증명이 만료됨

**해결**:

1. AWS CLI 설정 확인:
```bash
aws configure list
```

2. 프로필 확인:
```bash
cat ~/.aws/credentials
```

3. 새로 설정:
```bash
aws configure
# AWS Access Key ID:
# AWS Secret Access Key:
# Default region: ap-northeast-2
# Default output format: json
```

4. 특정 프로필 사용하는 경우:
```bash
export AWS_PROFILE=your-profile-name
```

### 문제: 권한 부족 에러

**증상**:
```
Error: Error creating VPC: UnauthorizedOperation: You are not authorized to perform this operation
```

**원인**:
IAM 사용자/역할에 필요한 권한이 없음

**해결**:

필요한 권한:
- EC2 (VPC, Subnet, Instance, SecurityGroup 등)
- S3 (state 저장)
- DynamoDB (state locking)

AWS 관리자에게 다음 정책 요청:
- `AmazonEC2FullAccess`
- `AmazonS3FullAccess` (또는 특정 버킷만)
- `AmazonDynamoDBFullAccess` (또는 특정 테이블만)

## 리소스 생성 실패

### 문제: VPC CIDR 충돌

**증상**:
```
Error: Error creating VPC: VpcLimitExceeded: The maximum number of VPCs has been reached
```

**원인**:
리전당 VPC 개수 제한 (기본 5개)

**해결**:

1. 기존 VPC 확인:
```bash
aws ec2 describe-vpcs --region ap-northeast-2
```

2. 사용하지 않는 VPC 삭제
3. 또는 AWS에 VPC 한도 증가 요청

### 문제: Elastic IP 할당 실패

**증상**:
```
Error: Error allocating EIP: AddressLimitExceeded: The maximum number of addresses has been reached
```

**원인**:
계정당 Elastic IP 개수 제한 (기본 5개)

**해결**:

1. 사용 중인 EIP 확인:
```bash
aws ec2 describe-addresses --region ap-northeast-2
```

2. 연결되지 않은 EIP 해제
3. 또는 AWS에 한도 증가 요청

### 문제: 키 페어를 찾을 수 없음

**증상**:
```
Error: Error launching source instance: InvalidKeyPair.NotFound: The key pair 'refit' does not exist
```

**원인**:
terraform.tfvars에 지정한 키 페어가 AWS에 존재하지 않음

**해결**:

1. 키 페어 목록 확인:
```bash
aws ec2 describe-key-pairs --region ap-northeast-2
```

2. 키 페어 생성:
   - AWS Console → EC2 → Key Pairs → Create key pair
   - Name: `refit`
   - 생성 후 다운로드

3. terraform.tfvars에서 키 이름 확인:
```hcl
key_name = "refit"  # AWS에 등록된 키 페어 이름과 일치해야 함
```

## SSH 접속 문제

### 문제: Permission denied (publickey)

**증상**:
```bash
ssh -i ~/.ssh/refit.pem ubuntu@13.125.XXX.XXX
# Permission denied (publickey)
```

**원인**:
1. 키 파일 권한 문제
2. 잘못된 사용자 이름
3. 잘못된 키 파일

**해결**:

1. 키 파일 권한 확인 및 수정:
```bash
chmod 400 ~/.ssh/refit.pem
ls -la ~/.ssh/refit.pem
# 출력: -r-------- 1 user user ... refit.pem
```

2. 올바른 사용자 이름 사용:
```bash
# Ubuntu AMI는 'ubuntu' 사용자
ssh -i ~/.ssh/refit.pem ubuntu@<IP>

# Amazon Linux는 'ec2-user'
```

3. 키 파일 경로 확인:
```bash
ls ~/.ssh/refit.pem
```

### 문제: Connection timeout

**증상**:
```bash
ssh: connect to host 13.125.XXX.XXX port 22: Operation timed out
```

**원인**:
1. Security Group에서 SSH 포트 차단
2. 잘못된 IP 주소
3. 인스턴스가 실행 중이 아님

**해결**:

1. Security Group 확인:
```bash
terraform output security_group_id
aws ec2 describe-security-groups --group-ids <SG_ID>
```

SSH 규칙이 있는지 확인:
```json
{
  "IpProtocol": "tcp",
  "FromPort": 22,
  "ToPort": 22,
  "IpRanges": [...]
}
```

2. 인스턴스 상태 확인:
```bash
terraform output instance_id
aws ec2 describe-instances --instance-ids <INSTANCE_ID>
```

State가 `running`인지 확인.

3. Elastic IP 확인:
```bash
terraform output elastic_ip
```

### 문제: Host key verification failed

**증상**:
```
Host key verification failed
```

**원인**:
이전에 같은 IP로 다른 서버에 접속한 적이 있음

**해결**:
```bash
ssh-keygen -R <IP_ADDRESS>
```

## 기타 문제

### 문제: Terraform 버전 호환성

**증상**:
```
Error: Unsupported Terraform Core version
```

**원인**:
Terraform 버전이 맞지 않음

**해결**:

1. 현재 버전 확인:
```bash
terraform version
```

2. 필요 버전 확인 (provider.tf):
```hcl
terraform {
  required_version = ">= 1.0.0"
}
```

3. Terraform 업그레이드:
```bash
# macOS
brew upgrade terraform

# 또는 직접 다운로드
# https://www.terraform.io/downloads
```

### 문제: Provider 플러그인 다운로드 실패

**증상**:
```
Error: Failed to install provider
```

**원인**:
네트워크 문제 또는 Terraform Registry 접근 불가

**해결**:

1. 네트워크 연결 확인
2. 프록시 설정 확인
3. 재시도:
```bash
rm -rf .terraform
terraform init
```

### 문제: Plan과 Apply 결과가 다름

**증상**:
Plan에서는 변경 사항이 없었는데 Apply 후 리소스가 변경됨

**원인**:
- AWS 측에서 리소스가 변경됨
- Terraform state와 실제 인프라가 불일치

**해결**:

1. State 새로고침:
```bash
terraform refresh
```

2. Plan 다시 확인:
```bash
terraform plan
```

3. State와 실제 인프라 동기화:
```bash
terraform apply -refresh-only
```

## 로그 및 디버깅

### 상세 로그 활성화

```bash
export TF_LOG=DEBUG
terraform plan

# 로그 파일로 저장
export TF_LOG=DEBUG
export TF_LOG_PATH=terraform.log
terraform plan
```

로그 레벨:
- `TRACE`: 가장 상세
- `DEBUG`: 디버깅 정보
- `INFO`: 일반 정보
- `WARN`: 경고
- `ERROR`: 에러만

### State 파일 검사

```bash
# State 목록
terraform state list

# 특정 리소스 상세 정보
terraform state show aws_instance.main

# State를 JSON으로 출력
terraform show -json
```

## 추가 도움

### 공식 문서
- [Terraform Troubleshooting](https://developer.hashicorp.com/terraform/tutorials/configuration-language/troubleshooting-workflow)
- [AWS Provider Issues](https://github.com/hashicorp/terraform-provider-aws/issues)

### 커뮤니티
- [Terraform Community Forum](https://discuss.hashicorp.com/c/terraform-core)
- [Stack Overflow - Terraform Tag](https://stackoverflow.com/questions/tagged/terraform)

### 도움 요청 시 포함할 정보

1. Terraform 버전: `terraform version`
2. 에러 메시지 전체
3. 관련 코드 스니펫
4. 실행한 명령어
5. TF_LOG=DEBUG 로그 (민감 정보 제거 후)
