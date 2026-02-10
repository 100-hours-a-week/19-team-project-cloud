# Refit Prod v2 (Terraform)

Prod v2 인프라: VPC 10.2.0.0/16, External/Internal ALB, Frontend(Next.js)·Backend(Spring Boot)·Kafka ASG, RDS, ElastiCache(Valkey), CodeDeploy.  
인스턴스 식별은 **tier 태그**를 사용한다.

---

## 필수 설정

### 0. Terraform State 백엔드 (S3)

이 프로젝트의 state는 **원격 백엔드(S3 + DynamoDB)** 에 저장된다.  
`shared/`, `dev/`와 동일하게 `terraform/backend-setup` 이 만든 S3/DynamoDB를 사용하며, 설정은 `backend.tf` 에 있다.

- 백엔드 리소스: `terraform/backend-setup` 에서 **최초 1회** `terraform apply` 로 S3 버킷(`refit-terraform-state`)과 DynamoDB(`refit-terraform-lock`) 생성
- State 키: `prod/v2/terraform.tfstate`
- 참고: `terraform/backend-setup/README.md`, `terraform/docs/README.md` (아키텍처 다이어그램)

**기존에 로컬 state(`terraform.tfstate`)를 쓰고 있었다면** S3로 옮기려면:

```bash
# backend를 s3로 바꾼 뒤
terraform init -migrate-state
# 프롬프트에서 yes 입력
```

### 1. AWS CLI 프로파일

Terraform은 `aws_profile = "refit-terraform"` 을 사용한다. 해당 프로파일을 등록한다.

- IAM 사용자 `refit-terraform`에 EC2, RDS, ELB, IAM, S3, CodeDeploy, SSM(GetParameter) 권한이 있어야 한다.
- 로컬 등록: `aws configure --profile refit-terraform` (Access Key, Secret Key, 리전 `ap-northeast-2`)
- 확인: `aws sts get-caller-identity --profile refit-terraform`

### 2. 시크릿 (3종)

본 모듈에서 관리하는 시크릿은 다음 세 가지이다.

| 시크릿 | 용도 |
|--------|------|
| ACM 인증서 ARN | External ALB HTTPS 리스너 |
| RDS 마스터 사용자명 | RDS PostgreSQL 접속 |
| RDS 마스터 비밀번호 | RDS PostgreSQL 접속 |

**방법 A: SSM Parameter Store (권장)**

1. AWS Systems Manager → Parameter Store에서 아래 파라미터를 생성한다.

   | 파라미터 경로 | 타입 |
   |---------------|------|
   | `/refit/prod-v2/acm-certificate-arn` | String |
   | `/refit/prod-v2/rds/username` | String |
   | `/refit/prod-v2/rds/password` | String 또는 SecureString |

2. IAM 사용자 `refit-terraform`에 SSM 조회 권한을 부여한다.

3. `terraform.tfvars`에 파라미터 경로만 지정한다.

   ```hcl
   ssm_parameter_acm_certificate_arn = "/refit/prod-v2/acm-certificate-arn"
   ssm_parameter_db_username        = "/refit/prod-v2/rds/username"
   ssm_parameter_db_password        = "/refit/prod-v2/rds/password"
   ```

**방법 B: 변수로 지정**

`terraform.tfvars`에 `acm_certificate_arn`, `db_username`, `db_password`를 직접 넣어 사용할 수 있다.

### 3. terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

- `aws_profile` 기본값은 `refit-terraform`이다.
- 기존 RDS를 사용할 경우 `use_existing_rds = true`, `db_instance_identifier`, `existing_db_subnet_group_name`, `existing_rds_security_group_id`를 설정한다.

### 4. 기존 RDS를 state에 포함할 때

이미 존재하는 RDS 인스턴스를 Terraform이 관리하도록 할 때만 실행한다.

```bash
terraform import aws_db_instance.prod_v2 <RDS_인스턴스_식별자>
```

---

## 사용법

```bash
terraform init
terraform plan -lock=false
terraform apply
```

---

## 안전한 적용 절차

apply 전에 아래 순서를 권장한다.

### 1. 적용 전 확인

- **계정·리전**: `aws sts get-caller-identity --profile refit-terraform` 으로 올바른 계정인지 확인.
- **plan 출력 검토**: 생성·변경·삭제될 리소스 목록을 끝까지 확인한다.

### 2. plan 저장 후 apply (권장)

plan 결과를 파일로 저장한 뒤, 그 파일만 사용해 apply하면 **plan 시점과 동일한 변경만** 적용된다.

```bash
terraform plan -lock=false -out=tfplan
# tfplan 내용 확인 (선택): terraform show tfplan
terraform apply tfplan
```

중간에 설정이나 state를 바꿨다면 `tfplan`을 버리고 다시 `plan -out=tfplan` 후 apply한다.

### 3. 단계별 적용 (선택)

한 번에 전체 apply가 부담되면 `-target`으로 리소스 단위로 나눠 적용할 수 있다.  
아래 순서대로 적용하면 의존 관계를 지키면서 검증하기 좋다.

| 단계 | 대상 | 명령 예시 |
|------|------|-----------|
| 1 | VPC·서브넷·NAT·라우트 | `terraform apply -lock=false -target=aws_vpc.prod_v2 -target=aws_internet_gateway.prod_v2 -target=aws_subnet.prod_v2_public -target=aws_subnet.prod_v2_private_backend -target=aws_subnet.prod_v2_private_data -target=aws_eip.prod_v2_nat -target=aws_nat_gateway.prod_v2 -target=aws_route_table.prod_v2_public -target=aws_route_table.prod_v2_private_backend -target=aws_route_table.prod_v2_private_data -target=aws_route_table_association.prod_v2_public -target=aws_route_table_association.prod_v2_private_backend -target=aws_route_table_association.prod_v2_private_data -target=aws_vpc_endpoint.prod_v2_s3` |
| 2 | 보안 그룹 | `terraform apply -lock=false -target=aws_security_group.prod_v2_alb_ext -target=aws_security_group.prod_v2_alb_int -target=aws_security_group.prod_v2_backend -target=aws_security_group.prod_v2_frontend -target=aws_security_group.prod_v2_rds -target=aws_security_group.prod_v2_elasticache -target=aws_security_group.prod_v2_kafka` |
| 3 | IAM 역할 | `terraform apply -lock=false -target=aws_iam_role.prod_v2_backend -target=aws_iam_role.prod_v2_frontend -target=aws_iam_role.prod_v2_kafka -target=aws_iam_role.prod_v2_codedeploy` |
| 4 | ElastiCache | `terraform apply -lock=false -target=aws_elasticache_subnet_group.prod_v2 -target=aws_elasticache_replication_group.prod_v2` |
| 5 | ALB·타깃 그룹·리스너 | `terraform apply -lock=false -target=aws_lb.prod_v2_external -target=aws_lb.prod_v2_internal -target=aws_lb_listener.prod_v2_external_https -target=aws_lb_listener.prod_v2_internal_http` (필요 시 관련 리소스 추가) |
| 6 | Launch Template·ASG | `terraform apply -lock=false -target=aws_launch_template.prod_v2_backend -target=aws_launch_template.prod_v2_frontend -target=aws_launch_template.prod_v2_kafka -target=aws_autoscaling_group.prod_v2_backend -target=aws_autoscaling_group.prod_v2_frontend -target=aws_autoscaling_group.prod_v2_kafka` |
| 7 | CodeDeploy·S3 | `terraform apply -lock=false -target=aws_s3_bucket.prod_v2_deployments -target=aws_codedeploy_app.prod_v2_backend -target=aws_codedeploy_deployment_group.prod_v2_backend` |

각 단계 후 콘솔에서 리소스가 의도대로 생성되었는지 확인한 뒤 다음 단계를 진행한다.  
단계별 적용 후에는 **의존성만 남은 리소스**를 채우기 위해 마지막에 `terraform apply -lock=false` 한 번 더 실행하는 것이 좋다.

### 4. destroy 전 확인

리소스 제거 전에 제거 대상만 먼저 확인한다.

```bash
terraform plan -destroy -lock=false
```

출력에서 삭제될 리소스 목록을 검토한 뒤, 필요할 때만 `terraform destroy`를 실행한다.

---

## 리소스 네이밍

- 접두사: `refit-prod-v2`
- VPC: `refit-prod-v2-vpc` (CIDR 10.2.0.0/16)
- 서브넷: public 10.2.1.0/24, 10.2.2.0/24 / private backend 10.2.10, 10.2.11 / private data 10.2.20, 10.2.21
- ALB: External(인터넷), Internal(VPC 내부)

## ALB 규칙

- `/api/ai/*`, `/ai/*`, `/swagger-ui/*`, `/v3/api-docs*`, `/actuator/*`, `/ws*`, `/api/ws*`, `/api/*`, `/dev/*` → Backend(8080)
- 기본 → Frontend(3000)

## CloudFront + WAF (설계도: Route 53 → WAF → CloudFront → ALB)

`cloudfront_enabled = true`로 두면 설계도대로 **WAF → CloudFront → ALB** 구성을 적용한다.

- **WAF**: us-east-1에 Web ACL 생성. AWS 관리 규칙(CommonRuleSet, KnownBadInputs), IP 기반 rate limit(기본 2000/분) 적용.
- **CloudFront**: 오리진은 External ALB. 기본은 ALB DNS + HTTP(80). 커스텀 도메인 오리진·HTTPS 오리진을 쓰려면 `cloudfront_origin_domain`과 해당 도메인이 ALB를 가리키고 ALB 인증서에 포함되어 있어야 한다.
- **뷰어 인증서**: 커스텀 도메인 사용 시 **us-east-1** ACM 인증서가 필요하다. `cloudfront_acm_certificate_arn` 또는 `ssm_parameter_cloudfront_acm_certificate_arn`에 설정.
- **Route 53**: 이미 연동된 상태라면, 트래픽을 CloudFront로 보내려면 기존 A/alias 레코드를 CloudFront 배포 도메인(`output "cloudfront_domain_name"`)과 Hosted Zone ID(`output "cloudfront_hosted_zone_id"`)로 alias 타깃을 바꾸면 된다.

적용 후 `terraform output cloudfront_domain_name`, `cloudfront_hosted_zone_id`로 Route 53 alias 레코드를 연결하면 된다.

## tier 태그

인스턴스 재시작 시 private IP가 바뀌므로, 서비스 역할은 **tier 태그**로 구분한다.

| tier | 용도 |
|------|------|
| backend | Backend(Spring Boot) EC2 |
| frontend | Frontend(Next.js) EC2 |
| kafka | Kafka EC2 |
| alb-external | External ALB |
| alb-internal | Internal ALB |
| rds | RDS Primary |
| rds-replica | RDS Read Replica |
| elasticache | ElastiCache Valkey |
| deploy | CodeDeploy 앱·배포 그룹, S3 배포 버킷 |

예: Backend 인스턴스 조회

```bash
aws ec2 describe-instances --filters "Name=tag:tier,Values=backend" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]' --output table
```

CodeDeploy는 **tier=backend** 인스턴스에만 배포된다.

## 파일 구성

| 파일 | 내용 |
|------|------|
| backend.tf | 원격 백엔드(S3 + DynamoDB, backend-setup 연동) |
| provider.tf | Terraform 버전·required_providers + AWS provider (ap-northeast-2, us-east-1 alias) |
| locals.tf | name prefix, tier 상수, 시크릿 local |
| ssm_parameters.tf | SSM Parameter Store 조회 (시크릿 3종) |
| vpc.tf | VPC, 서브넷, NAT, S3 엔드포인트 |
| security_group.tf | ALB·Frontend·Backend·RDS·ElastiCache·Kafka SG |
| iam.tf | EC2 역할, CodeDeploy 서비스 역할 |
| rds.tf | RDS PostgreSQL Primary, Read Replica |
| elasticache.tf | ElastiCache Valkey |
| alb.tf | External/Internal ALB, Target Group, Listener (CloudFront 경유 시 HTTP 규칙 포함) |
| waf.tf | WAF v2 Web ACL (us-east-1, CloudFront 연동) |
| cloudfront.tf | CloudFront 배포 (오리진=ALB, WAF 연동) |
| asg.tf | Backend·Frontend Launch Template, ASG |
| kafka.tf | Kafka Launch Template, ASG |
| codedeploy.tf | S3 배포 버킷, CodeDeploy 앱/배포 그룹 |
| variables.tf | 변수 정의 |
| outputs.tf | 출력값 |
