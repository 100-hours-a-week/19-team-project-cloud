# ArgoCD GitOps + Helm Chart + External Secrets 구성

- **작업일시**: 2026-03-15
- **작업자**: yoonseo + Claude

---

## 배경

기존에는 워크로드를 로컬에서 `kubectl apply`로 수동 배포하고 있었음.
Secret 파일(`03-backend-secret.yaml`)은 SCP로 마스터 노드에 옮겨서 apply하는 방식이어서 자동화·보안 모두 취약한 상태였음.
이번 작업에서 ArgoCD + Helm + AWS Secrets Manager를 연결해 GitOps 기반 자동 배포 파이프라인을 구성함.

---

## 작업 내용

### 1. ArgoCD Application 등록

기존에 ArgoCD Pod는 설치되어 있었으나 Application 리소스가 클러스터에 등록되어 있지 않았음.
`k8s/manifests/argocd-apps/refit-stack.yaml`을 apply해 4개 Application 등록.

```bash
kubectl apply -f k8s/manifests/argocd-apps/refit-stack.yaml
```

| Application | 경로 | 방식 | 대상 namespace |
|---|---|---|---|
| refit-foundation | k8s/manifests/01-foundation | raw YAML | argocd |
| refit-networking | k8s/manifests/02-networking | raw YAML | refit-app |
| refit-infra | k8s/manifests/03-workload (Redis, Kafka만) | raw YAML | refit-app |
| refit-backend | k8s/helm/refit-backend | **Helm chart** | refit-app |

**refit-infra**는 `03-workload` 경로에서 `01-redis.yaml`, `02-kafka.yaml`만 include하도록 설정 (backend secret 파일 제외 목적).

---

### 2. Backend Helm Chart 구성

기존 `03-backend.yaml` (Deployment + Service + HTTPRoute)을 Helm chart로 전환.

**구조:**
```
k8s/helm/refit-backend/
├── Chart.yaml
├── values.yaml                      ← 이미지 태그 등 변경 가능한 값
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── httproute.yaml
    └── external-secret.yaml         ← Secret은 여기서 AWS SM에서 가져옴
```

**이미지 태그 업데이트 방법:**
`values.yaml`의 `image.tag`만 변경 후 git push → ArgoCD가 자동으로 롤링 업데이트.

```yaml
# values.yaml
image:
  repository: 807210685804.dkr.ecr.ap-northeast-2.amazonaws.com/refit-backend
  tag: "develop-latest"   # ← 이 값만 바꾸면 됨
```

---

### 3. AWS Secrets Manager + External Secrets Operator 구성

#### 배경: Secret을 Git에 올리면 안 되는 이유

`03-backend-secret.yaml`에는 DB 비밀번호, JWT Secret, Kakao OAuth 키, AWS 액세스 키 등 민감 정보가 담겨 있어 Git에 올리면 안 됨.
기존 방식(SCP → apply)을 대체하기 위해 AWS Secrets Manager + ESO를 도입.

#### 동작 흐름

```
AWS Secrets Manager (refit/backend)
         ↑  읽기 권한
  refit-eso IAM User
         ↓  인증 정보 (K8s Secret으로 저장)
  ClusterSecretStore (aws-secrets-manager)
         ↓  1시간마다 자동 갱신
  ExternalSecret (refit-backend-external-secret)
         ↓  자동 생성
  K8s Secret (refit-backend-secret)
         ↓  볼륨 마운트
  Backend Pod (/config/secret/application-secret.yml)
```

#### Step 1: External Secrets Operator 설치

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --wait
```

#### Step 2: IAM User 생성 (refit-eso)

ESO 전용 IAM User를 별도로 생성함.
기존 `refit-backend` IAM User에 권한을 추가하지 않은 이유: 앱 런타임 권한과 인프라 권한을 분리하고, 추후 AI 서비스 시크릿도 동일한 ESO User로 관리하기 위함.

```
IAM User: refit-eso
ARN: arn:aws:iam::807210685804:user/refit-eso
Policy: secretsmanager:GetSecretValue, DescribeSecret (refit/* 경로만 허용)
```

인라인 정책 내용:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:ap-northeast-2:807210685804:secret:refit/*"
    }
  ]
}
```

#### Step 3: AWS Secrets Manager에 시크릿 저장

Secret 이름: `refit/backend`
저장 내용: `application-secret.yml` 파일 전체 내용 (Spring Boot가 읽는 YAML 형식 그대로)

```bash
aws secretsmanager create-secret \
  --region ap-northeast-2 \
  --name refit/backend \
  --secret-string "$(cat application-secret.yml)"
```

시크릿 내용 변경이 필요할 때는 AWS 콘솔 또는 CLI로 직접 업데이트:
```bash
aws secretsmanager update-secret \
  --region ap-northeast-2 \
  --secret-id refit/backend \
  --secret-string "$(cat application-secret.yml)"
```
K8s Secret은 1시간 내에 자동으로 갱신됨 (즉시 반영이 필요하면 ExternalSecret을 annotate해서 강제 갱신 가능).

#### Step 4: ESO 자격증명 K8s Secret 등록 (수동, 1회)

이 작업은 새 클러스터 구성 시 1회만 수행하면 됨.

```bash
kubectl create secret generic refit-eso-credentials \
  -n external-secrets \
  --from-literal=access-key-id=<AKIA...> \
  --from-literal=secret-access-key=<...>
```

> **주의:** 액세스 키는 AWS IAM 콘솔에서 `refit-eso` 유저의 보안 자격증명에서 확인.
> 현재 키는 팀 내 공유 채널에 별도 보관할 것.

#### Step 5: ClusterSecretStore 적용

`k8s/manifests/01-foundation/04-cluster-secret-store.yaml`
이 파일은 Git에 올려도 안전 (비밀값 없음, 설정만 있음).

ArgoCD `refit-foundation` Application이 자동으로 sync해줌.

---

### 4. .gitignore에 Secret 파일 추가

기존에 Git으로 추적되던 secret 파일들을 tracking에서 제거.

```bash
git rm --cached k8s/manifests/03-workload/03-backend-secret.yaml
git rm --cached k8s/manifests/03-workload/04-ai-secret.yaml
```

`.gitignore`에 추가:
```
k8s/manifests/03-workload/03-backend-secret.yaml
k8s/manifests/03-workload/04-ai-secret.yaml
```

> 로컬 파일은 그대로 남아있음 (삭제된 게 아니라 Git tracking만 해제).
> 클러스터 재구성 시에는 이 파일을 참조해 AWS Secrets Manager 내용을 업데이트하면 됨.

---

## 현재 클러스터 상태

```
$ kubectl get applications -n argocd
NAME               SYNC STATUS   HEALTH STATUS
refit-backend      Synced        Healthy
refit-foundation   Synced        Healthy
refit-infra        Synced        Healthy
refit-networking   Synced        Progressing   ← Gateway 관련 이슈 (별도 확인 필요)
```

```
$ kubectl get externalsecret -n refit-app
NAME                             STATUS         READY
refit-backend-external-secret    SecretSynced   True
```

---

## 신규 인프라 구성원이 클러스터를 재구성할 때 체크리스트

클러스터가 날아가서 처음부터 다시 구성해야 하는 경우:

- [ ] kubeadm으로 클러스터 초기화 (기존 스크립트 참고)
- [ ] ArgoCD 설치
- [ ] External Secrets Operator 설치 (위 helm 명령어)
- [ ] `refit-eso` IAM 액세스 키로 `refit-eso-credentials` K8s Secret 생성
- [ ] `kubectl apply -f k8s/manifests/argocd-apps/refit-stack.yaml` → 이후 모든 것 자동 배포
- [ ] ECR imagePullSecret 재생성 (`ecr-secret`)

---

## 다음 작업 예정

- [ ] AI 서비스도 동일하게 Helm chart + ExternalSecret으로 전환 (`refit/ai` 경로로 AWS SM에 저장)
- [ ] GitHub Actions CI/CD 연결: 이미지 빌드 후 `values.yaml`의 `image.tag` 자동 업데이트 → git push
- [ ] `refit-networking` Progressing 이슈 원인 파악 (Cilium Gateway EXTERNAL-IP pending)
- [ ] ECR imagePullSecret 자동 갱신 구성 (현재 12시간 만료)
