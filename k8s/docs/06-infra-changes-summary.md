# 인프라 변경 작업 요약

> 작성일: 2026-03-16
> 작업 범위: K8s 배포 안정화 · 관리형 서비스 전환 · HTTPS 적용

---

## 목차

1. [배포 안정화 (refit-backend)](#1-배포-안정화-refit-backend)
2. [ECR Secret 자동 갱신](#2-ecr-secret-자동-갱신)
3. [Redis / Kafka → AWS 관리형 서비스 전환](#3-redis--kafka--aws-관리형-서비스-전환)
4. [ResourceQuota 조정](#4-resourcequota-조정)
5. [HTTPS 적용 (ALB + ACM)](#5-https-적용-alb--acm)
6. [cert-manager 제거](#6-cert-manager-제거)
7. [현재 아키텍처](#7-현재-아키텍처)

---

## 1. 배포 안정화 (refit-backend)

### 문제

Spring Boot 앱 시작에 약 105초가 소요되는데, `startupProbe`의 `timeoutSeconds` 기본값이 1초여서 헬스체크가 반복 실패 → **CrashLoopBackOff** 발생.

### 변경 내용

`k8s/helm/refit-backend/values.yaml`

```yaml
# 변경 전
startupProbe:
  periodSeconds: 5
  failureThreshold: 24
  # timeoutSeconds 미설정 → 기본값 1초

# 변경 후
startupProbe:
  periodSeconds: 10
  failureThreshold: 18
  timeoutSeconds: 5   # 총 허용 시간: 20 + 10×18 = 200초
```

---

## 2. ECR Secret 자동 갱신

### 문제

ECR 인증 토큰 TTL은 12시간. `ecr-secret`이 수동 생성 후 갱신되지 않아 만료 → 새 이미지 pull 시 **403 Forbidden / ImagePullBackOff** 발생.

### 변경 내용

- `k8s/manifests/03-workload/00-ecr-secret-refresh.yaml` 추가
  → 6시간마다 ECR 토큰을 자동 갱신하는 CronJob

- `refit-stack.yaml`의 `refit-infra` ArgoCD App include 필터에 해당 파일 추가

> **주의**: `refit-stack.yaml` 변경 시 ArgoCD App 객체가 자동 갱신되지 않으므로
> 반드시 `kubectl apply -f k8s/manifests/argocd-apps/refit-stack.yaml` 수동 실행 필요.

---

## 3. Redis / Kafka → AWS 관리형 서비스 전환

### 변경 전 → 후

| 서비스 | 변경 전 | 변경 후 |
|---|---|---|
| Redis | in-cluster StatefulSet (emptyDir) | ElastiCache Valkey 8.0 (cache.t4g.micro) |
| Kafka | in-cluster StatefulSet (emptyDir) | MSK kafka.t3.small × 2 브로커 |

### AWS 리소스

| 리소스 | 상세 |
|---|---|
| ElastiCache | Valkey 8.0, cache.t4g.micro, refit-redis (ap-northeast-2) |
| MSK | kafka.t3.small × 2 브로커, PLAINTEXT (9092), VPC 내부 통신 |
| Security Group | refit-elasticache-sg (6379), refit-msk-sg (9092) — 워커노드 SG에서만 인바운드 허용 |

### 엔드포인트 보안

MSK / ElastiCache 엔드포인트는 git에 노출하지 않고 **AWS Secrets Manager(`refit/backend`)** 에서만 관리.
ExternalSecret이 1시간마다 자동 동기화.

### 삭제된 파일

- `k8s/manifests/03-workload/01-redis.yaml` — Redis StatefulSet 제거
- `k8s/manifests/03-workload/02-kafka.yaml` — Kafka StatefulSet 제거

### ECR Lifecycle Policy 추가

이미지 수 증가에 따른 비용 방지용 정책 적용.

| prefix | 보관 |
|---|---|
| `develop-` | 최근 10개 |
| `production-` | 최근 10개 |
| untagged | 1일 후 삭제 |

---

## 4. ResourceQuota 조정

### 문제

관리형 서비스 전환 후 `refit-app` quota를 5Gi로 줄였으나, AI 파드 limit이 설계서(512Mi)와 달리 실제 **3Gi**로 설정되어 롤링 업데이트 시 quota 초과 → **FailedCreate** 발생.

```
AI pod 3Gi + Backend×2 1.5Gi = 4.5Gi
4.5Gi + 신규 파드 0.75Gi = 5.25Gi > 5Gi → 실패
```

### 변경 내용

`k8s/manifests/01-foundation/03-resourcequota.yaml`

```yaml
# refit-app-quota
# 변경 전
limits.memory: "5Gi"
pods: "12"

# 변경 후
requests.memory: "8Gi"
limits.memory: "11Gi"   # AI max(2×3Gi) + BE max(5×768Mi) + 여유
pods: "15"
```

> ArgoCD selfHeal이 git 상태로 되돌리므로 반드시 **커밋 후 push** → ArgoCD sync 순서로 반영해야 함.

---

## 5. HTTPS 적용 (ALB + ACM)

### 아키텍처

```
Client
  │ HTTPS (443)
  ▼
AWS ALB  ←  ACM 인증서 (api-k8s.re-fit.kr)
  │ HTTP (NodePort)
  ▼
Worker Node → Cilium Gateway → HTTPRoute → Service → Pod
```

클러스터 내부는 기존 HTTP 통신 그대로 유지. TLS 종료는 ALB에서만 처리.

### 작업 내역

| 항목 | 내용 |
|---|---|
| 서브도메인 | `api-k8s.re-fit.kr` (검증용, 추후 `api.re-fit.kr`로 전환 예정) |
| ACM 인증서 | `api-k8s.re-fit.kr` 발급 완료 (DNS 검증) |
| Route 53 | `api-k8s.re-fit.kr` → `refit-k8s-alb` A 레코드(Alias) 추가 |
| ALB HTTPS 리스너 | 443 포트 추가, ACM 인증서 연결 |
| HTTP 리다이렉트 | 80 → 443 (301 Permanent) |

> **현재 도메인 전환 계획**
> `api-k8s.re-fit.kr` 검증 완료 후 `api.re-fit.kr` 레코드를 새 ALB로 교체.
> 기존 서비스(`api.re-fit.kr` → 구 ALB)는 전환 완료 전까지 병행 운영.

---

## 6. cert-manager 제거

### 배경

HTTPS를 ALB + ACM 방식으로 처리하므로 클러스터 내 cert-manager 불필요.
ClusterIssuer(`letsencrypt-prod`)는 설정만 존재했고 실제 발급된 Certificate 없음.

### 작업 내역

- cert-manager Helm 언인스톨 (`cert-manager` namespace)
- cert-manager CRD 6종 삭제
- `k8s/manifests/02-networking/01-clusterissuer.yaml` 삭제

---

## 7. 현재 아키텍처

```
                        [Client]
                           │ HTTPS
                           ▼
                       [AWS ALB]
                    (api-k8s.re-fit.kr)
                    ACM 인증서 / TLS 종료
                           │ HTTP (NodePort)
                           ▼
                    [Worker Nodes × N]
                           │
                    [Cilium Gateway]
                      (port 80, HTTP)
                     /            \
              [HTTPRoute]      [HTTPRoute]
            /api, /actuator     /ai, /health
                  │                  │
          [refit-backend]        [refit-ai]
           Deployment (HPA)    Deployment (HPA)
           2~5 replicas         1~N replicas
                  │
      ┌───────────┴────────────┐
      │                        │
[ElastiCache Valkey]      [MSK Kafka]
  cache.t4g.micro          kafka.t3.small × 2
```

### 시크릿 관리

```
AWS Secrets Manager (refit/backend)
        │ ExternalSecret (1h 주기)
        ▼
  K8s Secret (refit-backend-secret)
        │ volumeMount
        ▼
  Pod (/config/secret/application-secret.yml)
```

### ECR Secret 갱신

```
CronJob (6시간마다)
  └─ aws ecr get-login-password → kubectl apply ecr-secret
```
