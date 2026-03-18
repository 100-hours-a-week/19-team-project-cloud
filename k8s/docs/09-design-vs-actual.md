# 설계서 vs 실제 클러스터 비교 분석

> 문서: K8s_design_v2.md (설계) ↔ 현재 클러스터 실제 상태 (2026-03-17 기준)

---

## 요약

| 영역 | 설계 | 실제 | 일치 여부 |
|---|---|---|---|
| 노드 구성 (CP HA) | t4g.medium × 3, 3개 AZ | CP 3대, AZ-a/c/b 분산 | ✅ 일치 |
| 노드 구성 (Worker) | t4g.large × 2~3 | Worker 2대 | ✅ 일치 |
| CNI | Cilium VXLAN | Cilium VXLAN + kube-proxy replacement | ✅+ (설계 초과) |
| Ingress | Gateway API (Cilium 구현체) | Gateway API (Cilium 구현체) | ✅ 일치 |
| ArgoCD GitOps | ArgoCD, selfHeal | ArgoCD, selfHeal=true | ✅ 일치 |
| Redis / Kafka | 클러스터 내 단일 Pod + EBS PV | **미배포** (외부 관리형 서비스로 전환) | ❌ 미구현 |
| NetworkPolicy | BE만 Redis/Kafka 접근 허용 | **미설정** | ❌ 미구현 |
| WebSocket HTTPRoute 타임아웃 | `/ws` 경로 3600s | **미설정** | ❌ 미구현 |
| 모니터링 스택 | OTel Collector + PLG | Grafana Alloy + PLG + Tempo | 🔄 변경됨 |
| BE 리소스 할당 | req 250m/512Mi, lim 500m/1Gi | req 250m/300Mi, lim 500m/768Mi | 🔄 메모리 조정됨 |
| AI 리소스 할당 | req 200m/256Mi, lim 400m/512Mi | req 500m/1Gi, lim 2/3Gi | 🔄 크게 상향됨 |
| AI HPA max | 1 / 2 | 1 / 3 | 🔄 상향됨 |
| Rolling update 전략 | maxUnavailable:0, maxSurge:1, minReady:30s, terminationGracePeriod:60s | 동일 | ✅ 일치 |
| Pod AntiAffinity (BE) | preferred, weight 100, hostname | 동일 | ✅ 일치 |
| Probe 분리 (startup/readiness/liveness) | liveness에 DB 미포함 | 동일 | ✅ 일치 |
| ResourceQuota | 설계표 값 | 일부 다름 | 🔄 조정됨 |

---

## 1. 노드 구성 ✅

| 항목 | 설계 | 실제 |
|---|---|---|
| Control Plane | t4g.medium × 3, 3개 AZ 분산 | 3대 (AZ-a: 10.2.1.5, AZ-c: 10.2.2.173, AZ-b: 10.2.3.32) |
| Worker Node | t4g.large × 2~3 | 2대 (AZ-a: 10.2.1.227, AZ-c: 10.2.2.139) |
| NLB (API Server) | Internal NLB TCP 6443 | `refit-k8s-cp-nlb-d4b7b4ab87ff588f.elb.ap-northeast-2.amazonaws.com` |
| OS | — | Ubuntu 22.04.5 LTS, kernel 6.8.0-1047-aws |
| K8s 버전 | — | v1.34.5 |

설계대로 3개 AZ에 CP 1:1:1로 분산되어 있어 etcd 쿼럼이 보장됩니다. Worker 2대 운영으로 비시즌 기본 구성입니다.

---

## 2. CNI: Cilium ✅ (설계 초과)

| 항목 | 설계 | 실제 |
|---|---|---|
| 네트워킹 모드 | VXLAN 오버레이 | VXLAN (`routing-mode: tunnel, tunnel-protocol: vxlan`) |
| kube-proxy | 언급 없음 | `kubeProxyReplacement: true` (eBPF로 kube-proxy 완전 대체) |
| Hubble | 활성화 | Hubble + Hubble Relay + Hubble UI 활성화 |
| Gateway API | 활성화 | `gatewayAPI.enabled: true, serviceType: NodePort` |

**설계 대비 추가 구성**: `kubeProxyReplacement: true`는 설계서에 명시되지 않았지만 실제로 적용됨. eBPF 기반 kube-proxy 완전 대체로 iptables 불필요, 성능 향상. 단, eBPF VIP 관련 주의사항 필요 (실제로 이번 재구성 중 VIP 오남용으로 워커 장애 발생).

---

## 3. Ingress: Gateway API ✅

| 항목 | 설계 | 실제 |
|---|---|---|
| 구현체 | Cilium Gateway API | `GatewayClass: cilium` |
| Gateway 이름 | `refit-gateway` | `refit-gateway` (ns: refit-app) |
| TLS 종료 | AWS ALB + ACM | ALB + ACM, 클러스터 내 HTTP |
| NodePort | 30080 | 30080 |

### HTTPRoute 비교

| 경로 | 설계 | 실제 |
|---|---|---|
| `/api/*` | backend-route, timeout 60s | backend-route (timeout **미설정**) |
| `/ws/*` | ws-route, timeout **3600s** | **미존재** |
| `/api/ai/*` | ai-route | refit-ai HTTPRoute ✅ |
| `/api/ai/health` | 언급 없음 | refit-ai-healthcheck (별도 HTTPRoute) |
| `argocd.re-fit.kr` | 언급 없음 | argocd-route (운영 중 추가) |

**설계와의 차이:**
- `/ws` HTTPRoute 미생성: WebSocket 경로가 현재 `backend-route`에 합류되거나 별도 라우팅 없이 처리 중
- `timeouts` 필드 미설정: 설계의 핵심 근거(경로별 타임아웃 차등 제어)가 아직 미적용

---

## 4. 워크로드: Redis / Kafka ❌ 미구현

설계서는 Redis와 Kafka를 **클러스터 내 단일 Pod + EBS PV**로 배치한다고 명시했습니다.

| 항목 | 설계 | 실제 |
|---|---|---|
| Redis | 클러스터 내 Pod + EBS PV (req 100m/256Mi) | **미배포** |
| Kafka | 클러스터 내 Pod + EBS PV (req 200m/512Mi) | **미배포** |

실제 클러스터에 Redis/Kafka Pod 및 관련 PVC가 존재하지 않습니다. 외부 관리형 서비스(Amazon ElastiCache, MSK 또는 다른 방식)로 전환된 것으로 추정됩니다. 설계서의 비용 절감 근거(ElastiCache ~$25/월 → 내부 배치)와 다른 방향입니다.

---

## 5. 리소스 할당 🔄

### Backend (refit-backend)

| 항목 | 설계 | 실제 |
|---|---|---|
| CPU request | 250m | 250m ✅ |
| CPU limit | 500m | 500m ✅ |
| Memory request | 512Mi | 300Mi (하향) |
| Memory limit | 1Gi | 768Mi (하향) |

메모리 request가 512Mi → 300Mi로 낮아졌습니다. 실제 운영 중 JVM 메모리 사용량을 측정한 결과 설계 예측보다 낮아 최적화한 것으로 보입니다.

### AI (refit-ai)

| 항목 | 설계 | 실제 |
|---|---|---|
| CPU request | 200m | **500m** (2.5배 상향) |
| CPU limit | 400m | **2** (5배 상향) |
| Memory request | 256Mi | **1Gi** (4배 상향) |
| Memory limit | 512Mi | **3Gi** (6배 상향) |

설계와 실제 사이에 가장 큰 괴리입니다. 설계서는 "Python async 기반 경량 프로세스, 모델은 RunPod 외부 호출"을 가정했으나, 실제로는 AI 서비스가 훨씬 무거운 것으로 판명되었습니다. 모델 로컬 로딩, 대용량 데이터 처리, 또는 GCP/RunPod 호출 이외의 로컬 연산이 포함된 것으로 추정됩니다.

---

## 6. HPA 🔄

| 서비스 | 설계 min/max | 실제 min/max | CPU 목표 |
|---|---|---|---|
| BE | 2 / 5 | 2 / 5 ✅ | 70% ✅ |
| AI | 1 / **2** | 1 / **3** | 70% ✅ |

AI HPA max가 2→3으로 상향되었습니다. 실제 AI 서비스 부하가 설계 예측보다 높아 더 많은 Pod를 허용하도록 조정된 것으로 보입니다.

---

## 7. Rolling Update & Probe ✅

| 항목 | 설계 | 실제 |
|---|---|---|
| maxUnavailable | 0 | 0 ✅ |
| maxSurge | 1 | 1 ✅ |
| minReadySeconds | 30 | 30 ✅ |
| terminationGracePeriodSeconds | 60 | 60 ✅ |
| startupProbe | 있음 (JVM 워밍업) | `/actuator/health`, initial 20s, period 10s, failure 18 (총 200s) ✅ |
| readinessProbe | DB 포함 가능 | `/actuator/health/readiness` ✅ |
| livenessProbe | DB **미포함** | `/actuator/health/liveness` ✅ (liveness와 readiness 엔드포인트 분리) |

무중단 배포 전략이 설계대로 정확히 구현되어 있습니다.

---

## 8. Pod AntiAffinity ✅ (설정) / ⚠️ (실효)

**설정**: 설계대로 `preferred, weight 100, topologyKey: kubernetes.io/hostname` 적용됨.

**실제 배치 현황:**
```
ip-10-2-1-227 (worker-1): refit-ai, refit-backend × 2
ip-10-2-2-139 (worker-2): 파드 없음
```

`preferred`(소프트) AntiAffinity임에도 불구하고 BE 파드 2개가 같은 노드에 배치되어 있습니다. worker-2에 파드가 전혀 없는 것은 worker-2의 리소스 부족 또는 초기 스케줄링 시 worker-2가 NotReady였던 상황 때문일 수 있습니다.

**영향**: worker-1 장애 시 모든 애플리케이션 파드가 동시에 중단됩니다. 설계의 "노드 1대 장애에도 서비스 유지" 목표가 현재는 달성되지 않고 있습니다.

---

## 9. NetworkPolicy ❌ 미구현

설계서 6.5절에서 명시한 NetworkPolicy가 **전혀 설정되어 있지 않습니다.**

| 설계 정책 | 실제 |
|---|---|
| BE Egress: Redis(6379), Kafka(9092), RDS(5432), AI(8000)만 허용 | 미설정 |
| Redis/Kafka Ingress: `app: refit-be` 라벨 Pod만 허용 | 미설정 |
| AI Egress: Kafka(9092), RunPod API만 허용 | 미설정 |

현재는 모든 Pod 간 통신이 자유롭게 허용됩니다. Cilium이 설치되어 있어 NetworkPolicy를 적용할 준비는 되어 있지만, 실제 정책이 없습니다.

---

## 10. 모니터링 스택 🔄

| 항목 | 설계 | 실제 |
|---|---|---|
| 메트릭 수집 | Prometheus | kube-prometheus-stack (Prometheus Operator) |
| 로그 수집 에이전트 | OTel Collector DaemonSet | **Grafana Alloy** DaemonSet (4대 - CP 3대 + Worker 1대) |
| 로그 저장 | Loki | Loki ✅ |
| 시각화 | Grafana | Grafana ✅ |
| 트레이싱 | 언급 없음 | **Tempo** (분산 추적 추가됨) |

OTel Collector 대신 **Grafana Alloy**를 사용합니다. Alloy는 OTel Collector와 Prometheus Agent를 통합한 Grafana Labs의 통합 에이전트로, 로그/메트릭/트레이스를 단일 에이전트로 수집합니다.

Tempo(분산 추적)는 설계에 없었으나 추가 구성됨.

---

## 11. ResourceQuota 비교 🔄

| 네임스페이스 | 설계 (requests.memory / limits.memory) | 실제 (requests.memory / limits.memory) |
|---|---|---|
| refit-app | — / — | 8Gi / 11Gi |
| monitoring | 4Gi / 8Gi | 1Gi / 2Gi (대폭 하향) |
| argocd | 1Gi / 2Gi | 3Gi / 6Gi (상향) |

설계서의 CPU requests 상한(refit-app: 3core, monitoring: 1core, argocd: 500m)은 실제에 적용되지 않았습니다. 실제 ResourceQuota는 메모리와 Pod 수 위주로 설정되어 있습니다.

monitoring 네임스페이스가 설계(4Gi)보다 실제(1Gi)가 훨씬 낮습니다. Alloy의 경량화 덕분에 예상보다 낮은 메모리로 운영 가능합니다.

argocd는 설계(1Gi)보다 실제(3Gi)가 높습니다. 클러스터 재구성 과정에서 ArgoCD 컴포넌트들의 실제 메모리 사용량이 예상보다 많아 상향 조정했습니다.

---

## 종합 평가

### 잘 구현된 부분 ✅
- HA Control Plane (3 AZ 분산, etcd 쿼럼)
- Cilium VXLAN + kube-proxy replacement
- Gateway API + ALB 연동
- ArgoCD GitOps (selfHeal)
- Rolling update 전략 (무중단 배포)
- Pod Probe 분리 설계 (liveness ≠ DB 체크)
- Pod AntiAffinity 설정 (preferred)

### 설계와 다르게 변경된 부분 🔄
| 변경 | 이유 |
|---|---|
| AI 리소스 대폭 상향 (설계: 400m/512Mi → 실제: 2/3Gi) | 실제 AI 서비스가 예상보다 무거움 |
| AI HPA max 2→3 | 실제 부하에 맞게 조정 |
| BE 메모리 하향 (설계: 512Mi → 실제: 300Mi req) | 실제 JVM 메모리 사용량이 설계 예측보다 낮음 |
| OTel Collector → Grafana Alloy | 더 통합된 에이전트 선택 |
| Tempo 추가 | 분산 추적 요구사항 추가 |
| ResourceQuota 수치 조정 | 실제 운영 데이터 기반 최적화 |
| Redis/Kafka 외부 전환 | 비용 또는 운영 편의성 판단 변경 |

### 미구현 항목 ❌
| 항목 | 영향도 | 권고 |
|---|---|---|
| NetworkPolicy | **높음** - 클러스터 내 Pod 간 격리 없음 | Cilium 이미 설치됨 → 정책만 추가하면 됨 |
| `/ws` HTTPRoute + timeouts 설정 | **높음** - WebSocket 장기 연결 강제 종료 가능성 | HTTPRoute에 `/ws` 경로 + `timeouts.request: 3600s` 추가 |
| BE Pod 분산 배치 (현재 worker-1에 집중) | **중간** - worker-1 장애 시 전체 서비스 중단 | worker-2에 pod 재스케줄 또는 AntiAffinity를 required로 변경 검토 |
