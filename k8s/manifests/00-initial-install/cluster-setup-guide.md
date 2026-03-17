# 클러스터 재구성 설치 가이드

## 설치 순서

### 1단계: kubeadm 클러스터 초기화

```bash
# 마스터 1 (HA 구성 시 --control-plane-endpoint에 NLB DNS 지정)
kubeadm init \
  --control-plane-endpoint="<NLB_DNS>:6443" \
  --upload-certs \
  --pod-network-cidr=10.244.0.0/16

# 워커 노드 조인 (kubeadm init 출력에서 복사)
kubeadm join <NLB_DNS>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# 마스터 2, 3 조인 (HA)
kubeadm join <NLB_DNS>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane --certificate-key <cert-key>
```

### 2단계: Cilium 설치

```bash
helm repo add cilium https://helm.cilium.io
helm install cilium cilium/cilium --version 1.19.1 \
  -n kube-system \
  -f helm-values/cilium-values.yaml \
  --set k8sServiceHost=<NLB_DNS>   # HA 구성 시 NLB DNS로 변경
```

### 3단계: ArgoCD 설치

```bash
helm repo add argo https://argoproj.github.io/argo-helm
kubectl create namespace argocd
helm install argocd argo/argo-cd --version 9.4.10 \
  -n argocd \
  -f helm-values/argocd-values.yaml
```

### 4단계: ArgoCD 알림 설정

```bash
# Discord webhook secret 생성 (값은 팀 내부 공유)
kubectl create secret generic argocd-notifications-secret \
  --from-literal=discord-ai-webhook-url=<DISCORD_WEBHOOK_URL> \
  -n argocd

# 알림 ConfigMap 적용
kubectl apply -f argocd-notifications-cm.yaml
```

### 5단계: External Secrets 설치

```bash
helm repo add external-secrets https://charts.external-secrets.io
kubectl create namespace external-secrets
helm install external-secrets external-secrets/external-secrets --version 2.1.0 \
  -n external-secrets \
  -f helm-values/external-secrets-values.yaml

# ESO가 AWS Secrets Manager에 접근하기 위한 자격증명 (값은 팀 내부 공유)
kubectl create secret generic refit-eso-credentials \
  --from-literal=access-key-id=<AWS_ACCESS_KEY_ID> \
  --from-literal=secret-access-key=<AWS_SECRET_ACCESS_KEY> \
  -n external-secrets
```

### 6단계: ArgoCD Application 배포

```bash
# ArgoCD가 GitHub 레포에 접근할 수 있도록 repo 등록 (private repo인 경우)
# ArgoCD UI 또는 argocd CLI로 등록

# ArgoCD Application 적용 (이후 모든 리소스는 ArgoCD가 자동 배포)
kubectl apply -f argocd-apps/refit-stack.yaml
```

---

## 수동 생성 Secret 목록

| Secret | Namespace | 내용 |
|---|---|---|
| `argocd-notifications-secret` | argocd | Discord webhook URL |
| `refit-eso-credentials` | external-secrets | AWS IAM 자격증명 (Secrets Manager 접근용) |
| `refit-ai-secret` | refit-app | AI 서비스 런타임 환경변수 (AI 팀 관리) |

> `refit-ai-secret`에 필요한 키 목록: `DATABASE_URL`, `BACKEND_API_URL`, `GOOGLE_APPLICATION_CREDENTIALS`, `GCP_PROJECT_ID`, `GCP_LOCATION`, `GOOGLE_API_KEYS`, `INTERNAL_API_KEY`, `INTERNAL_API_KEY_HEADER`, `OTEL_EXPORTER_OTLP_ENDPOINT`

> `ecr-secret`은 ECR CronJob이 6시간마다 자동 생성하므로 수동 생성 불필요.
> 단, 초기 배포 직후 CronJob 첫 실행 전까지는 수동으로 한 번 생성 필요.

```bash
# ECR secret 최초 수동 생성
ECR_PASS=$(aws ecr get-login-password --region ap-northeast-2)
kubectl create secret docker-registry ecr-secret \
  --docker-server=807210685804.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${ECR_PASS}" \
  -n refit-app \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## 참고: Cilium k8sServiceHost 값

| 구성 | k8sServiceHost 값 |
|---|---|
| 단일 마스터 | 마스터 노드 내부 IP |
| HA (3 마스터) | NLB DNS (e.g. `k8s-cp-nlb-xxxx.elb.ap-northeast-2.amazonaws.com`) |
