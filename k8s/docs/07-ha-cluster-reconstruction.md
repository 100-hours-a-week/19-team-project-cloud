# HA 클러스터 재구성 전체 가이드

> 작성일: 2026-03-17
> 대상 독자: 쿠버네티스 초보자 포함
> 목적: 단일 마스터 → 3중 마스터(HA) 클러스터 재구성 전 과정 기록

---

## 목차

1. [배경 및 목표](#1-배경-및-목표)
2. [사전 지식: HA 클러스터란?](#2-사전-지식-ha-클러스터란)
3. [작업 전 구성 확인](#3-작업-전-구성-확인)
4. [전체 작업 순서 개요](#4-전체-작업-순서-개요)
5. [단계별 작업 상세](#5-단계별-작업-상세)
6. [발생한 이슈 및 해결](#6-발생한-이슈-및-해결)
7. [ArgoCD 서브도메인 설정](#7-argocd-서브도메인-설정)
8. [최종 구성 상태](#8-최종-구성-상태)
9. [재구성 시 주의사항 요약](#9-재구성-시-주의사항-요약)

---

## 1. 배경 및 목표

### 기존 문제점

기존 클러스터는 **마스터 노드가 1대**인 단일(single) 구성이었습니다.

```
[기존 구성]
마스터 1대 (ap-northeast-2a)
워커 2대 (ap-northeast-2a, ap-northeast-2c)
```

단일 마스터 구성의 문제점:
- 마스터 노드가 다운되면 **kubectl 명령 불가**, 새 파드 스케줄링 불가
- API 서버(포트 6443)가 단일 장애점(SPOF)
- 실제 서비스 파드는 워커에서 계속 동작하지만, 클러스터 관리 자체가 불가능해짐

### 목표

```
[목표 구성]
마스터 3대 (ap-northeast-2a, 2b, 2c) ← NLB로 로드밸런싱
워커 2대 (ap-northeast-2a, ap-northeast-2c)
```

- etcd 쿼럼: 3대 중 2대가 살아있으면 클러스터 정상 동작
- NLB(Network Load Balancer)가 마스터 3대의 API 서버(6443 포트)에 TCP 로드밸런싱

---

## 2. 사전 지식: HA 클러스터란?

### etcd란?

쿠버네티스의 모든 상태 정보(파드 목록, 서비스, 시크릿 등)를 저장하는 **분산 키-값 저장소**입니다.
etcd는 **Raft 합의 알고리즘**을 사용하며, 과반수(quorum)가 살아있어야 쓰기 작업이 가능합니다.

| 마스터 수 | 허용 장애 수 | 쿼럼 |
|---|---|---|
| 1 | 0 | 1 |
| 3 | 1 | 2 |
| 5 | 2 | 3 |

→ **3대 구성에서는 1대가 죽어도 클러스터가 정상 동작합니다.**

### NLB(Network Load Balancer)란?

AWS의 L4(TCP) 로드밸런서입니다.
`--control-plane-endpoint`로 NLB DNS를 지정하면, kubectl/kubelet이 마스터 1대에 고정되지 않고 NLB를 통해 3대 중 살아있는 마스터에 연결됩니다.

```
[클라이언트/워커 노드]
        ↓ TCP:6443
[NLB: refit-k8s-cp-nlb-xxxx.elb.ap-northeast-2.amazonaws.com]
    ↙         ↓         ↘
[마스터1]  [마스터2]  [마스터3]
```

### Cilium이란?

쿠버네티스의 CNI(Container Network Interface) 플러그인입니다.
파드 간 통신, 서비스 로드밸런싱, 네트워크 정책을 담당합니다.
이 클러스터에서는 **kube-proxy를 대체**하여 eBPF 기반으로 동작합니다.

> **eBPF**: 리눅스 커널에서 실행되는 안전한 프로그램으로, 네트워크 패킷을 커널 레벨에서 처리합니다. iptables보다 빠르고 유연합니다.

---

## 3. 작업 전 구성 확인

### 클러스터 상태 확인

```bash
kubectl get nodes
# NAME            STATUS   ROLES           AGE
# ip-10-2-1-5     Ready    control-plane   ...  ← 마스터 1대만 존재
# ip-10-2-1-227   Ready    <none>          ...  ← 워커
# ip-10-2-2-139   Ready    <none>          ...  ← 워커
```

### Git으로 관리되는 리소스 확인

재구성 전, Git에 없는 리소스가 있으면 클러스터 재구성 후 복원이 불가능합니다.
확인 결과, 아래 리소스들이 Git에 없어 추가했습니다:

| 리소스 | 위치 | 내용 |
|---|---|---|
| Cilium helm values | `00-initial-install/helm-values/cilium-values.yaml` | CNI 설정 |
| ArgoCD helm values | `00-initial-install/helm-values/argocd-values.yaml` | GitOps 도구 설정 |
| External Secrets helm values | `00-initial-install/helm-values/external-secrets-values.yaml` | Secret 관리 |
| ArgoCD 알림 ConfigMap | `00-initial-install/argocd-notifications-cm.yaml` | Discord 알림 |

### 수동 관리 Secret 목록

Git에 저장할 수 없는 민감한 정보들은 클러스터 재구성 시 수동으로 재생성해야 합니다:

| Secret 이름 | 네임스페이스 | 내용 |
|---|---|---|
| `argocd-notifications-secret` | argocd | Discord webhook URL |
| `refit-eso-credentials` | external-secrets | AWS IAM 자격증명 |
| `ecr-secret` | refit-app | ECR 이미지 풀링 토큰 |
| `refit-ai-secret` | refit-app | AI 서비스 환경변수 |

---

## 4. 전체 작업 순서 개요

```
[준비]
 ① ap-northeast-2b 서브넷 생성 (2b AZ에 마스터2 배치 예정)
 ② 마스터2(2b), 마스터3(2c) EC2 인스턴스 생성
 ③ 신규 마스터들에 K8s 패키지 설치 (containerd, kubeadm, kubelet, kubectl)

[인프라]
 ④ Control Plane용 NLB 생성 (TCP:6443 리스너, 마스터1 타겟 등록)

[클러스터 재구성]
 ⑤ 마스터1 kubeadm reset 후 NLB를 endpoint로 재초기화
 ⑥ Cilium CNI 설치
 ⑦ 마스터2, 마스터3 control-plane join
 ⑧ NLB 타겟그룹에 마스터2, 3 추가
 ⑨ 워커1, 2 kubeadm reset 후 재조인

[애플리케이션 복원]
 ⑩ ArgoCD, External Secrets Helm 설치
 ⑪ 수동 Secret 생성 (4종)
 ⑫ ArgoCD Notifications ConfigMap 적용
 ⑬ refit-stack.yaml 적용 → ArgoCD가 나머지 자동 배포
 ⑭ 전체 파드 정상 기동 확인
```

---

## 5. 단계별 작업 상세

### ① ap-northeast-2b 서브넷 생성

기존에 2b AZ 서브넷이 없었습니다. 마스터2를 2b에 배치하기 위해 생성합니다.

```bash
# 새 서브넷 생성 (10.2.3.0/24 대역, 2b AZ)
aws ec2 create-subnet \
  --vpc-id <VPC_ID> \
  --cidr-block 10.2.3.0/24 \
  --availability-zone ap-northeast-2b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=refit-private-2b}]'

# 라우트 테이블 연결 (NAT Gateway 경유하는 프라이빗 라우트 테이블)
aws ec2 associate-route-table \
  --route-table-id <PRIVATE_RT_ID> \
  --subnet-id <NEW_SUBNET_ID>
```

### ② 마스터 EC2 인스턴스 생성

| 항목 | 마스터2 | 마스터3 |
|---|---|---|
| AZ | ap-northeast-2b | ap-northeast-2c |
| 서브넷 | 10.2.3.0/24 | 기존 2c 서브넷 |
| IP | 10.2.3.32 | 10.2.2.173 |
| 인스턴스 타입 | 기존 마스터와 동일 |

### ③ K8s 패키지 설치 (신규 마스터들)

```bash
# containerd 설치
apt-get install -y containerd

# kubeadm, kubelet, kubectl 설치 (버전 고정!)
apt-get install -y kubeadm=1.34.5-1.1 kubelet=1.34.5-1.1 kubectl=1.34.5-1.1

# kubelet 자동 시작
systemctl enable --now kubelet
```

> **버전 고정이 중요한 이유**: kubeadm 버전이 다르면 join 시 인증서 검증 실패가 발생할 수 있습니다.

### ④ NLB 생성

```bash
# NLB 생성 (인터넷 연결 없는 내부 NLB)
aws elbv2 create-load-balancer \
  --name refit-k8s-cp-nlb \
  --type network \
  --scheme internal \
  --subnets <SUBNET_2A> <SUBNET_2B> <SUBNET_2C>

# 타겟그룹 생성 (TCP:6443)
aws elbv2 create-target-group \
  --name refit-k8s-cp-tg \
  --protocol TCP \
  --port 6443 \
  --vpc-id <VPC_ID> \
  --target-type instance

# 리스너 생성
aws elbv2 create-listener \
  --load-balancer-arn <NLB_ARN> \
  --protocol TCP \
  --port 6443 \
  --default-actions Type=forward,TargetGroupArn=<TG_ARN>

# 마스터1을 타겟으로 등록
aws elbv2 register-targets \
  --target-group-arn <TG_ARN> \
  --targets Id=<MASTER1_INSTANCE_ID>
```

결과: `refit-k8s-cp-nlb-d4b7b4ab87ff588f.elb.ap-northeast-2.amazonaws.com`

### ⑤ 마스터1 reset 및 재초기화

> **서비스 중단 시작**: 이 시점부터 클러스터가 중단됩니다.

```bash
# 기존 클러스터 상태 완전 삭제
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/etcd

# NLB DNS를 control-plane-endpoint로 지정하여 재초기화
sudo kubeadm init \
  --control-plane-endpoint="refit-k8s-cp-nlb-d4b7b4ab87ff588f.elb.ap-northeast-2.amazonaws.com:6443" \
  --upload-certs \
  --pod-network-cidr=10.244.0.0/16

# kubeconfig 설정
mkdir -p ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config
```

`--upload-certs`: 마스터2,3 join 시 사용할 인증서를 etcd에 임시 저장합니다 (24시간 유효).

### ⑥ Cilium CNI 설치

```bash
helm install cilium cilium/cilium --version 1.19.1 \
  -n kube-system \
  -f helm-values/cilium-values.yaml \
  --set k8sServiceHost=refit-k8s-cp-nlb-d4b7b4ab87ff588f.elb.ap-northeast-2.amazonaws.com
```

> **CNI 설치 순서가 중요**: Cilium을 먼저 설치해야 마스터1의 `CoreDNS` 파드가 Running 상태가 됩니다. CNI 없이는 파드 간 통신이 불가능합니다.

> **Gateway API CRD 먼저 설치 필요** (아래 이슈 섹션 참조):
> ```bash
> kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
> kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
> kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
> kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
> kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
> ```

### ⑦ 마스터2, 3 control-plane join

`kubeadm init` 완료 시 출력된 join 명령어를 사용합니다:

```bash
# 마스터2, 3에서 실행 (control-plane join)
sudo kubeadm join refit-k8s-cp-nlb-xxxx.elb.ap-northeast-2.amazonaws.com:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <CERT_KEY>

# kubeconfig 설정 (각 마스터에서)
mkdir -p ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config
```

### ⑧ NLB 타겟그룹에 마스터2, 3 추가

```bash
aws elbv2 register-targets \
  --target-group-arn <TG_ARN> \
  --targets Id=<MASTER2_INSTANCE_ID> Id=<MASTER3_INSTANCE_ID>
```

### ⑨ 워커 reset 및 재조인

```bash
# 워커 노드에서 실행
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes

# 워커 join (control-plane 없이 일반 조인)
sudo kubeadm join refit-k8s-cp-nlb-xxxx.elb.ap-northeast-2.amazonaws.com:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

### ⑩ ArgoCD, External Secrets Helm 설치

```bash
# ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
kubectl create namespace argocd
helm install argocd argo/argo-cd --version 9.4.10 \
  -n argocd \
  -f helm-values/argocd-values.yaml

# External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
kubectl create namespace external-secrets
helm install external-secrets external-secrets/external-secrets --version 2.1.0 \
  -n external-secrets \
  -f helm-values/external-secrets-values.yaml
```

### ⑪ 수동 Secret 생성

```bash
# 1. ArgoCD Discord 알림 webhook
kubectl create secret generic argocd-notifications-secret \
  --from-literal=discord-ai-webhook-url=<DISCORD_WEBHOOK_URL> \
  -n argocd

# 2. External Secrets AWS 자격증명
kubectl create secret generic refit-eso-credentials \
  --from-literal=access-key-id=<AWS_ACCESS_KEY_ID> \
  --from-literal=secret-access-key=<AWS_SECRET_ACCESS_KEY> \
  -n external-secrets

# 3. ECR 이미지 풀 시크릿 (로컬 머신에서 실행)
ECR_PASS=$(aws ecr get-login-password --region ap-northeast-2)
kubectl create secret docker-registry ecr-secret \
  --docker-server=807210685804.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${ECR_PASS}" \
  -n refit-app \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. AI 서비스 환경변수 (AI 팀 제공 값으로 생성)
kubectl create secret generic refit-ai-secret \
  --from-literal=DATABASE_URL=<DB_URL> \
  --from-literal=BACKEND_API_URL=<API_URL> \
  --from-literal=GOOGLE_APPLICATION_CREDENTIALS=<GCP_CRED_PATH> \
  --from-literal=GCP_PROJECT_ID=<PROJECT_ID> \
  --from-literal=GCP_LOCATION=<LOCATION> \
  --from-literal=GOOGLE_API_KEYS=<API_KEYS> \
  --from-literal=INTERNAL_API_KEY=<KEY> \
  --from-literal=INTERNAL_API_KEY_HEADER=<HEADER> \
  --from-literal=OTEL_EXPORTER_OTLP_ENDPOINT=<OTLP_URL> \
  --from-literal=LANGFUSE_SECRET_KEY=<LANGFUSE_SK> \
  --from-literal=LANGFUSE_PUBLIC_KEY=<LANGFUSE_PK> \
  --from-literal=LANGFUSE_HOST=<LANGFUSE_HOST> \
  -n refit-app
```

### ⑫⑬ ArgoCD 알림 및 앱 배포

```bash
# ArgoCD 알림 ConfigMap 적용
kubectl apply -f argocd-notifications-cm.yaml

# ArgoCD Application 배포 (이후 모든 리소스는 ArgoCD가 자동 관리)
kubectl apply -f argocd-apps/refit-stack.yaml
```

`refit-stack.yaml`을 적용하면 ArgoCD가 Git에서 다음 리소스들을 자동으로 배포합니다:
- `refit-foundation`: 네임스페이스, LimitRange, ResourceQuota, ClusterSecretStore
- `refit-networking`: Gateway, HTTPRoute
- `refit-infra`: ECR 갱신 CronJob
- `refit-backend`: 백엔드 서비스 (Helm chart)
- `refit-ai`: AI 서비스 (Helm chart)

---

## 6. 발생한 이슈 및 해결

### 이슈 1: 마스터2/3 kubeadm join 실패

**증상**
```
[ERROR FileAvailable--etc-kubernetes/kubelet.conf]: already exists
[ERROR Port-10250]: Port 10250 is in use
```

**원인**
패키지 설치 스크립트(`init_master.sh`)가 이전에 부분 실행되어 `/etc/kubernetes` 디렉토리와 kubelet이 이미 초기화된 상태였습니다.

**해결**
```bash
# 마스터2, 3에서 실행 (join 전에 완전히 초기화)
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/etcd
```

---

### 이슈 2: Gateway API CRD 미설치

**증상**
ArgoCD `refit-networking` App에서 다음 오류:
```
The Kubernetes API could not find gateway.networking.k8s.io/Gateway
for requested resource refit-app/refit-gateway.
Make sure the "Gateway" CRD is installed on the destination cluster.
```

**원인**
Kubernetes Gateway API는 쿠버네티스 자체에 내장된 기능이 아니라 **별도 CRD**를 설치해야 합니다. Cilium이 Gateway API를 지원하지만, CRD 파일은 `kubernetes-sigs/gateway-api` 프로젝트에서 따로 제공됩니다.

이번 재구성 때 Cilium을 먼저 설치하고 Gateway API CRD를 나중에 설치했기 때문에 발생한 문제입니다.

**해결**
Gateway API CRD v1.2.1 수동 설치:
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
```

**재발 방지**
`cluster-setup-guide.md`의 Cilium 설치 단계 앞에 Gateway API CRD 설치를 추가했습니다.

---

### 이슈 3: GatewayClass `cilium`이 자동 생성되지 않음

**증상**
```bash
kubectl get gatewayclass
# No resources found
```

Gateway 리소스 상태:
```
Message: Unable to get GatewayClass - GatewayClass.gateway.networking.k8s.io "cilium" not found
```

**원인**
Cilium은 설치 시 `gatewayAPI.enabled: true`로 설정하면 `GatewayClass` 리소스를 자동 생성해야 합니다. 그런데 **Gateway API CRD가 없는 상태에서 Cilium이 설치**되었기 때문에, Cilium Operator가 GatewayClass를 생성하지 못했습니다.

이후 CRD를 추가 설치했지만, Cilium Operator를 재시작해도 GatewayClass가 자동 생성되지 않았습니다.

**해결**
GatewayClass를 수동으로 생성합니다:
```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: cilium
spec:
  controllerName: io.cilium/gateway-controller
EOF
```

---

### 이슈 4: Gateway NodePort가 ALB 타겟그룹과 불일치

**증상**
ALB 타겟그룹 헬스체크 unhealthy. `api-k8s.re-fit.kr` 접속 불가.

**원인**
클러스터를 재구성하면 Cilium이 Gateway를 위한 서비스를 새로 생성하면서 **NodePort 번호가 바뀝니다**.

- 이전 NodePort: `30080`
- 재구성 후 새 NodePort: `32211` (랜덤 할당)

ALB 타겟그룹(`refit-k8s-tg`)은 포트 `30080`으로 워커 노드들을 등록하고 있었기 때문에 연결이 안 됐습니다.

**해결**
Cilium이 생성한 서비스의 NodePort를 `30080`으로 강제 고정:
```bash
kubectl -n refit-app patch svc cilium-gateway-refit-gateway \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'
```

> **재발 방지**: 클러스터 재구성 시 반드시 ALB 타겟그룹 포트를 확인하고, Cilium Gateway 서비스의 NodePort를 맞춰줘야 합니다.

---

### 이슈 5: `refit-ai-secret` 미존재

**증상**
```
Error: secret "refit-ai-secret" not found
```
AI 파드가 `CreateContainerConfigError` 상태.

**원인**
`refit-ai-secret`은 Git에 저장되지 않고 클러스터에 직접 생성하여 관리하던 Secret입니다. 클러스터를 재구성하면서 삭제됐습니다.
`cluster-setup-guide.md`의 수동 생성 Secret 목록에도 누락되어 있었습니다.

**해결**
AI 팀으로부터 Secret 값을 받아 수동 생성:
```bash
kubectl create secret generic refit-ai-secret \
  --from-literal=DATABASE_URL='...' \
  --from-literal=BACKEND_API_URL='...' \
  # ... (나머지 환경변수)
  -n refit-app
```

`cluster-setup-guide.md`에 `refit-ai-secret` 항목 추가 완료.

---

### 이슈 6: ArgoCD 접속 시 connection timeout (심각)

**증상**
```
upstream connect error or disconnect/reset before headers.
reset reason: connection timeout
```
`https://argocd.re-fit.kr` 접속 불가. 이후 워커 노드 2대 모두 `NotReady`.

**원인 분석 과정**

1. ArgoCD Gateway `Progressing` 상태를 해결하려고 Cilium이 생성한 `cilium-gateway-refit-gateway` 서비스의 `status.loadBalancer.ingress`에 워커 노드 IP를 직접 설정했습니다.

```bash
# ❌ 잘못된 조치 - 이것이 문제의 원인
kubectl -n refit-app patch svc cilium-gateway-refit-gateway \
  --subresource=status \
  -p '{"status":{"loadBalancer":{"ingress":[
    {"ip":"10.2.1.227","ipMode":"VIP"},
    {"ip":"10.2.2.139","ipMode":"VIP"}
  ]}}}'
```

2. Cilium의 kube-proxy 대체 기능은 `ipMode: VIP`로 설정된 IP를 **eBPF 가상 IP 규칙**으로 처리합니다.

3. `10.2.1.227`과 `10.2.2.139`는 실제 워커 노드의 내부 IP입니다.

4. Cilium이 이 IP들을 VIP로 등록하면, **해당 IP로 오는 모든 트래픽**이 서비스(포트 80)로 리다이렉트됩니다.

5. 결과: 워커 노드에 대한 SSH(22), kubelet(10250), 노드 간 통신이 전부 차단됨.

```
[정상 상태]
외부 → 10.2.1.227:30080 → NodePort → Gateway

[문제 상태 - VIP 등록 후]
외부 → 10.2.1.227:ANY → eBPF가 포트 80으로 리다이렉트
                    → SSH, kubelet 등 모든 통신 차단!
```

**해결**
```bash
# loadBalancer 상태 초기화
kubectl -n refit-app patch svc cilium-gateway-refit-gateway \
  --subresource=status \
  -p '{"status":{"loadBalancer":{"ingress":[]}}}'

# 워커 노드 재부팅 (eBPF 규칙 초기화)
aws ec2 reboot-instances --region ap-northeast-2 \
  --instance-ids <WORKER1_ID> <WORKER2_ID>
```

**교훈 및 주의사항**

> ⚠️ **Cilium kube-proxy replacement 환경에서는 실제 노드 IP를 서비스의 LoadBalancer IP나 externalIP로 절대 설정하면 안 됩니다.**
>
> - `externalIPs`에 노드 IP 설정 → 노드 네트워킹 완전 차단
> - `status.loadBalancer.ingress`에 노드 IP + `ipMode: VIP` 설정 → 동일 문제
>
> Gateway `Progressing` 상태는 기능에 영향이 없으므로 그냥 두는 것이 안전합니다.

---

## 7. ArgoCD 서브도메인 설정

클러스터 재구성 완료 후, ArgoCD UI에 편리하게 접근하기 위해 `argocd.re-fit.kr` 서브도메인을 설정했습니다.

### 작업 순서

```
① ACM 인증서 발급 (argocd.re-fit.kr)
② Route53 DNS 검증 레코드 + CNAME 추가
③ ALB HTTPS 리스너에 인증서 추가
④ ArgoCD 서버 insecure 모드 설정
⑤ Cilium Gateway allowedRoutes를 All로 변경
⑥ ArgoCD namespace에 HTTPRoute 추가
```

### ArgoCD insecure 모드란?

ALB가 HTTPS를 종료하고 HTTP로 클러스터에 전달하기 때문에, ArgoCD 서버가 HTTP 요청을 받을 수 있어야 합니다.

기본적으로 ArgoCD 서버는 HTTPS만 처리하는데, `server.insecure: true` 설정으로 HTTP도 허용합니다.

```yaml
# argocd-values.yaml
configs:
  params:
    server.insecure: true  # ALB가 HTTPS 종료 → ArgoCD는 HTTP 수신
```

### Gateway allowedRoutes 변경

`Gateway` 리소스는 기본적으로 같은 네임스페이스(`refit-app`)의 HTTPRoute만 허용합니다. ArgoCD는 `argocd` 네임스페이스에 있으므로, `from: All`로 변경이 필요합니다.

```yaml
# 02-gateway.yaml
spec:
  listeners:
  - name: http
    allowedRoutes:
      namespaces:
        from: All  # Same → All 변경
```

### ArgoCD HTTPRoute

```yaml
# 03-argocd-httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-route
  namespace: argocd  # ArgoCD 네임스페이스에 생성
spec:
  parentRefs:
  - name: refit-gateway
    namespace: refit-app  # 다른 네임스페이스의 Gateway 참조
  hostnames:
  - "argocd.re-fit.kr"  # 호스트 기반 라우팅
  rules:
  - backendRefs:
    - name: argocd-server
      port: 80
```

### 접속 정보

- URL: `https://argocd.re-fit.kr`
- ID: `admin`
- PW: 클러스터 재구성 시 랜덤 생성 (`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`)

---

## 8. 최종 구성 상태

### 노드 구성

```
NAME            STATUS   ROLES           AZ
ip-10-2-1-5     Ready    control-plane   ap-northeast-2a  ← 마스터1 (기존)
ip-10-2-3-32    Ready    control-plane   ap-northeast-2b  ← 마스터2 (신규)
ip-10-2-2-173   Ready    control-plane   ap-northeast-2c  ← 마스터3 (신규)
ip-10-2-1-227   Ready    <none>          ap-northeast-2a  ← 워커1
ip-10-2-2-139   Ready    <none>          ap-northeast-2c  ← 워커2
```

### ArgoCD Applications

| App | Sync | Health | 역할 |
|---|---|---|---|
| refit-foundation | Synced | Healthy | 네임스페이스, 리소스 제한, ESO SecretStore |
| refit-networking | Synced | Healthy | Gateway, HTTPRoute |
| refit-infra | Synced | Healthy | ECR 갱신 CronJob |
| refit-backend | Synced | Healthy | 백엔드 서비스 (2 replicas) |
| refit-ai | Synced | Healthy | AI 서비스 (1 replica) |

### 트래픽 흐름

```
[인터넷]
  ↓ HTTPS (443)
[ALB: refit-k8s-alb] ← ACM 인증서로 HTTPS 종료
  ↓ HTTP (NodePort 30080)
[워커 노드들]
  ↓
[Cilium Gateway: refit-gateway]
  ↓ (호스트 기반 라우팅)
  ├── api-k8s.re-fit.kr → refit-backend-svc
  ├── api-k8s.re-fit.kr/api/ai → refit-ai
  └── argocd.re-fit.kr → argocd-server
```

### NLB (Control Plane)

```
[kubectl / kubelet / 워커 노드]
  ↓ TCP (6443)
[NLB: refit-k8s-cp-nlb]
  ↓
  ├── 마스터1 (10.2.1.5:6443)
  ├── 마스터2 (10.2.3.32:6443)
  └── 마스터3 (10.2.2.173:6443)
```

---

## 9. 재구성 시 주의사항 요약

### 반드시 확인해야 할 사항

1. **Gateway API CRD를 Cilium보다 먼저 설치**
   순서가 바뀌면 GatewayClass가 자동 생성되지 않아 수동 생성이 필요합니다.

2. **NodePort 번호 확인**
   재구성 후 Cilium Gateway 서비스의 NodePort가 변경됩니다.
   ALB 타겟그룹에 등록된 포트와 맞춰야 합니다.
   ```bash
   kubectl -n refit-app get svc cilium-gateway-refit-gateway
   # PORT(S): 80:30080/TCP ← 이 포트가 ALB 타겟그룹 포트와 일치해야 함
   ```

3. **수동 Secret 4종 재생성**
   `cluster-setup-guide.md`의 수동 생성 Secret 목록을 확인하고 모두 재생성합니다.

4. **Cilium VIP 설정 금지**
   워커 노드 IP를 서비스의 LoadBalancer IP나 externalIP로 절대 설정하지 마세요.

5. **ArgoCD selfHeal 주의**
   ArgoCD가 `selfHeal: true`로 설정된 경우, 클러스터에서 수동으로 변경한 내용은 ArgoCD가 Git 상태로 되돌립니다.
   변경사항을 영구적으로 적용하려면 반드시 Git에 커밋 후 ArgoCD가 sync하도록 해야 합니다.

6. **`kubeadm join` 토큰 유효시간**
   토큰은 기본 24시간 유효합니다. `--upload-certs`로 업로드한 인증서도 24시간만 유효합니다.
   24시간 이후 마스터를 추가해야 한다면:
   ```bash
   # 새 토큰 생성
   kubeadm token create --print-join-command
   # 새 인증서 키 생성
   kubeadm init phase upload-certs --upload-certs
   ```
