# CNI · Ingress Controller 선정 근거

> Re-Fit 쿠버네티스 클러스터의 CNI와 Ingress Controller를 선정한 과정을 정리합니다.
> "어떤 기술을 선택했다"가 아니라, **"어떤 문제가 있었고, 그 문제를 해결하다 보니 이 기술에 도달했다"**는 흐름으로 서술합니다.

---

## 1. CNI 선정: Cilium (VXLAN 모드)

### 1.1 CNI란

CNI(Container Network Interface)는 쿠버네티스 클러스터 내 **Pod 간 통신을 가능하게 하는 네트워크 플러그인**입니다.

쿠버네티스 자체는 "모든 Pod가 서로 통신할 수 있어야 한다"는 규칙만 정의하고, **실제 네트워크를 구현하는 것은 CNI의 몫**입니다. CNI 없이는 Pod에 IP가 할당되지 않고, Pod 간 통신 자체가 불가능합니다.

CNI가 담당하는 핵심 역할:

| 역할 | 설명 |
|:-----|:-----|
| **Pod IP 할당** | 각 Pod에 고유한 IP 주소를 부여 |
| **노드 간 Pod 통신** | 서로 다른 노드에 있는 Pod끼리 통신할 수 있도록 네트워크 경로 구성 |
| **NetworkPolicy 실행** | Pod 간 통신 규칙(허용/차단)을 실제로 적용 |

### 1.2 Re-Fit 클러스터 특성 분석

CNI를 선정하기 전, Re-Fit 클러스터의 특성을 먼저 정리합니다:

| 특성 | 상세 |
|:-----|:-----|
| **다양한 워크로드 혼재** | 서비스(BE/AI), 인프라(Redis/Kafka), 운영(PLG/ArgoCD) Pod가 **동일 워커 노드 풀**에 배치 |
| **인프라 Pod에 민감 데이터 존재** | Redis에 세션 토큰·채팅 메시지, Kafka에 이력서 분석 요청이 저장됨 |
| **kubeadm 자체 구축** | EKS가 아닌 kubeadm 환경. AWS VPC 위에서 직접 클러스터를 구성 |
| **소규모 클러스터** | Worker 2~3대, 총 Pod ~20개 |
| **기존 모니터링 스택 존재** | Prometheus + Grafana 기반 PLG 스택을 이미 운영 |

### 1.3 CNI가 해결해야 하는 문제 도출

클러스터 특성에서 CNI가 반드시 해결해야 하는 **세 가지 문제**를 도출합니다:

#### 문제 ① Pod 간 접근 제어 (NetworkPolicy)

K8s 기본 상태에서는 **클러스터 내 모든 Pod가 서로 자유롭게 통신**할 수 있습니다. 이것이 왜 문제인가:

- 서비스·인프라·운영 Pod가 동일 노드 풀에 혼재
- Grafana나 ArgoCD에 보안 취약점이 발생하면, 공격자가 해당 Pod를 거점으로 **Redis/Kafka에 자유 접근 가능**
- 이력서 분석 요청, 세션 토큰 등이 비인가 Pod에 노출될 위험

→ **최소 권한 원칙(Least Privilege)**에 따라, BE Pod만 Redis/Kafka에 접근하도록 CNI 레벨에서 격리가 필요합니다.

> 참고: 핵심 민감 데이터(이력서 원본, 피드백)는 클러스터 외부 RDS에 저장됩니다. 클러스터 내부의 Redis/Kafka에 저장되는 것은 세션 토큰, 채팅 메시지, AI 분석 요청/응답입니다. 그럼에도 NetworkPolicy가 필요한 이유는 단순히 "민감 데이터 보호"가 아니라, **방어 계층(defense-in-depth)**을 구축하여 어떤 Pod가 침해되어도 피해 범위를 제한하기 위함입니다.

#### 문제 ② kubeadm + AWS VPC 환경 호환

Re-Fit은 EKS가 아닌 **kubeadm으로 자체 구축**한 클러스터입니다:

- AWS VPC 라우팅 테이블을 수동 관리하거나, 클라우드 전용 CNI(AWS VPC CNI)를 사용하면 추가 설정 부담이 과중
- VPC 라우팅 테이블 조작 없이 **Pod 네트워크가 즉시 구성**되어야 함

#### 문제 ③ 네트워크 관측성 (Observability)

네트워크 문제가 발생했을 때 **원인을 빠르게 파악**할 수 있어야 합니다:

- "BE → Redis 연결이 안 된다" → 어떤 NetworkPolicy가 차단했는지?
- "어떤 Pod가 Kafka에 비정상 접근을 시도 중" → 어떤 Pod인지, 어떤 포트로 접근했는지?
- NetworkPolicy를 새로 적용했는데 의도대로 동작하는지?

→ 이런 질문에 **실시간으로 답할 수 있는 관측 도구**가 필요합니다.

### 1.4 후보 CNI 비교

세 가지 문제를 기준으로 주요 CNI를 평가합니다:

| CNI | ① NetworkPolicy | ② kubeadm + AWS 호환 | ③ 네트워크 관측성 | 비고 |
|:----|:----------------|:-------------------|:----------------|:-----|
| **Cilium** | ⭐ L3/L4/L7 지원. HTTP 경로·DNS 이름 기반까지 세밀한 정책 가능 | ✅ VXLAN 모드: VPC 설정 변경 없이 즉시 동작 (커널 5.10+ 필요, Amazon Linux 2 충족) | ⭐ **Hubble 내장** — Pod 간 트래픽 실시간 시각화, 차단 트래픽 필터링, Prometheus 메트릭 연동 | CNCF Graduated (2024) |
| **Calico** | ✅ L3/L4 완전 지원 | ⭐ VXLAN 모드 즉시 동작 | ⚠️ `iptables -L`, `conntrack -L` 등 수동 CLI 디버깅. 규칙이 많아지면 분석 비용 높음 | CNCF 프로젝트, 가장 높은 채택률 |
| **Flannel** | ❌ **미지원** | ⭐ VXLAN 모드 즉시 동작 | ⭐ 가장 단순 | — |
| **AWS VPC CNI** | ⚠️ 자체 제한적, Calico 병행 필요 | ❌ EKS 전제 설계 | ✅ | — |
| **Weave Net** | ✅ 지원 | ✅ 오버레이 즉시 동작 | ⚠️ | 2024년 프로젝트 archive |

#### 탈락 과정

1. **Flannel 탈락** — ①번 문제(NetworkPolicy) 해결 불가. Pod 간 접근 제어가 아예 불가능
2. **AWS VPC CNI 탈락** — ②번 문제(kubeadm 호환) 해결 불가. EKS 전제 설계로 kubeadm에서 ENI 관리·IAM 연동 필요
3. **Weave Net 탈락** — 2024년 프로젝트 유지보수 중단(GitHub archive). 보안 패치 미지원 위험
4. **Calico vs Cilium** — ①② 모두 해결. **③번(관측성)에서 차이 발생**

### 1.5 Calico vs Cilium: ③번 문제에서의 차이

③을 "네트워크 관측성"으로 정의했을 때, 실제 트러블슈팅 시나리오에서의 차이:

| 시나리오 | Calico (iptables 기반) | Cilium (Hubble) |
|:---------|:---------------------|:----------------|
| "BE → Redis 연결 안 됨" | `iptables -L -n`으로 규칙 수십~수백 줄 탐색 → `tcpdump`로 패킷 캡처 → 수동 분석 | `hubble observe --from-pod refit-be --to-pod refit-redis` → **즉시** 차단된 흐름과 적용된 정책 확인 |
| "비정상 Pod가 Kafka 접근 시도" | `conntrack -L` + iptables 로그 활성화 → 수동 필터링 | Hubble UI에서 **Kafka로 향하는 모든 트래픽을 source별로 시각화** |
| NetworkPolicy 적용 확인 | `calicoctl get networkpolicy` → iptables 규칙과 대조 | `hubble observe --verdict DROPPED` → **차단된 트래픽만 필터링** |

또한 Re-Fit은 이미 **Prometheus + Grafana** 기반 모니터링 스택을 운영하고 있습니다. Hubble은 네트워크 메트릭을 Prometheus 형식으로 export하므로, **기존 Grafana 대시보드에 네트워크 관측 패널을 추가**하여 별도 도구 없이 통합 관측이 가능합니다.

### 1.6 선정: Cilium

| 문제 | Cilium의 해결 |
|:-----|:------------|
| ① Pod 간 접근 제어 | L3/L4 NetworkPolicy + 향후 L7 확장 가능 |
| ② kubeadm + AWS 호환 | VXLAN 모드, VPC 설정 변경 불필요 |
| ③ 네트워크 관측성 | Hubble 실시간 시각화 + 기존 PLG 스택 연동 |
| 추가: 프로젝트 지속성 | 2024 CNCF Graduated, 장기 지속 보장 |
| 추가: Ingress 통합 | Gateway API 구현체 내장 → CNI + Ingress 통합 관리 가능 (→ 2장에서 상세) |

#### Calico를 선택하지 않은 이유

Calico는 ①②를 충분히 해결하며, CNCF 생태계에서 가장 높은 채택률을 가진 안정적인 선택입니다. 그러나 Re-Fit 환경에서는:

- ③번 관측성이 수동 CLI 기반이라, NetworkPolicy 오류 진단에 시간이 많이 소요
- Re-Fit이 이미 Prometheus + Grafana를 운영 중이므로, Hubble의 메트릭 연동이 즉각적 가치를 제공
- Cilium이 Gateway API 구현체를 내장하고 있어, Ingress Controller와 통합 운영 시 관리 포인트가 감소

> Calico가 나쁜 선택이 아니라, **Re-Fit의 구체적 환경(기존 PLG 스택, kubeadm 첫 도입으로 관측성 중요, Gateway API 통합 가능)에서 Cilium이 더 적합**하다는 판단입니다.

#### 인지해야 할 비용

| 항목 | 영향 | 완화 방안 |
|:-----|:-----|:---------|
| 리소스 증가 | Cilium agent 노드당 ~250m/256Mi (Calico ~150m/128Mi 대비 +100m/+128Mi) | Gateway API 통합으로 별도 Ingress Controller Pod 불필요 → 순 증가분 상쇄 |
| eBPF 학습 곡선 | eBPF 개념 자체가 생소할 수 있음 | 일상 운영은 `cilium status`, `hubble observe` 수준. Hubble UI가 직관적이라 진입 장벽 낮음. eBPF 내부까지 이해할 필요 없음 |
| 커뮤니티 레퍼런스 | Calico 대비 Stack Overflow 답변 적음 | Cilium Slack 커뮤니티 활발. CNCF Graduated 이후 문서·자료 급증 중 |

### 1.7 네트워킹 모드: VXLAN 선택

Cilium은 여러 네트워킹 모드를 지원합니다:

| 모드 | 동작 방식 | 장점 | 단점 |
|:-----|:---------|:-----|:-----|
| **VXLAN (오버레이)** | Pod 패킷을 VXLAN 헤더로 캡슐화하여 노드 간 전송 | **VPC 라우팅 테이블 수정 불필요**. 어떤 환경에서든 즉시 동작 | 캡슐화 오버헤드 ~0.5ms 레이턴시 추가 |
| **Native Routing** | 호스트 라우팅 테이블을 직접 사용 | 캡슐화 없어 네이티브 성능 | AWS VPC에서 각 노드의 Pod CIDR을 라우팅 테이블에 수동 등록 필요. 노드 증감 시 동기화 필요 |
| **AWS ENI** | AWS ENI를 직접 Pod에 할당 | VPC 네이티브 IP, 최고 성능 | EKS 전제. kubeadm 환경에서 사용 불가 |

**VXLAN 선택 근거:**

- kubeadm 환경에서 AWS VPC 라우팅 테이블을 수동 관리하는 부담을 피하기 위해 VXLAN 모드 선택
- Native Routing 시 필요한 VPC 라우팅 테이블 등록 + Source/Dest Check 비활성화 + 노드 증감 시 동기화 자동화 — 모두 추가 운영 부담
- Re-Fit의 내부 트래픽(BE↔Redis, BE↔Kafka)은 동일 노드 또는 인접 노드 간 통신이므로, VXLAN 오버헤드(~0.5ms)의 실질적 영향이 미미
- **성능 이점(~0.5ms)이 운영 비용(라우팅 관리)을 정당화하지 못함**

---

## 2. Ingress Controller 선정: Gateway API (Cilium 구현체)

### 2.1 Ingress Controller란

Ingress Controller는 클러스터 외부에서 들어오는 HTTP(S)/WebSocket 트래픽을 **클러스터 내부 Service로 라우팅하는 역방향 프록시**입니다.

K8s의 Ingress/Gateway 리소스는 "이 경로는 이 서비스로 보내라"는 **규칙(Rule)**만 정의하고, 그 규칙을 **실제로 실행하는 것이 Ingress Controller**입니다.

#### Ingress API vs Gateway API

K8s에는 두 가지 트래픽 관리 API가 존재합니다:

| | 기존 Ingress API | Gateway API |
|:--|:---------------|:-----------|
| 상태 | 오래된 API, 스펙이 단순 | **K8s 공식 차세대 표준** (SIG-Network) |
| 타임아웃 제어 | 구현체별 어노테이션 (비표준) | `HTTPRoute.timeouts` **표준 필드** |
| 경로별 설정 | 구현체에 따라 다름 | **route 단위 설정이 기본 설계** |
| 구현체 교체 시 | 어노테이션 전부 재작성 | **HTTPRoute 매니페스트 재사용 가능** |
| 프로젝트 지속성 | 대표 구현체 ingress-nginx가 2026.03 EOL | K8s SIG-Network 공식 표준, **EOL 없음** |

### 2.2 Re-Fit 트래픽 특성 분석

| 특성 | 상세 |
|:-----|:-----|
| **두 가지 성격의 트래픽 공존** | REST API(`/api/*`) — 요청-응답 즉시 종료. WebSocket 채팅(`/ws/*`) — 수십 분~수 시간 장기 연결 유지 |
| **kubeadm 자체 구축** | 클라우드 전용 로드밸런서 컨트롤러(AWS ALB Controller 등) 사용 제약 |
| **제한된 노드 자원** | Worker 2~3대(t3.large)에 BE/AI/Redis/Kafka/PLG 모두 배치. Ingress 자체의 리소스 점유 최소화 필요 |
| **낮은 설정 변경 빈도** | 배포 시 또는 경로 추가 시에만 설정 변경 |
| **신규 채택 시점** | 2026년 3월 — 새로 도입하는 도구가 곧 EOL되면 재선정·재학습 비용 발생 |

### 2.3 Ingress가 해결해야 하는 문제 도출

#### 문제 ① 경로별 타임아웃 차등 제어

Re-Fit의 커피챗은 WebSocket 기반으로, 유휴 시간이 수십 분에 달합니다:

- `/ws` 경로에 짧은 타임아웃(60초)이 적용되면 → **정상 채팅 연결이 강제 종료**
- `/api` 경로에 3,600초가 적용되면 → 버려진 연결이 오래 유지되어 **프록시 자원 낭비**

→ **경로마다 다른 타임아웃**을 설정할 수 있어야 합니다.

#### 문제 ② kubeadm 환경 호환 + 최소 리소스

- 클라우드 API(IAM, VPC 태깅 등)에 의존하는 컨트롤러는 kubeadm 환경에서 추가 설정 부담 과중
- Worker 자원이 제한적(2~3대 × t3.large)이므로 Ingress 자체의 리소스 점유 최소화 필요

#### 문제 ③ 장기 지속 가능한 기술 선택

2026년 3월 시점에서 새로 채택하는 도구입니다:

- 채택 직후 EOL이 되면, 곧 재전환이 필요하여 학습·마이그레이션 비용이 이중으로 발생
- **K8s 공식 표준 기반**으로 장기 지속성을 확보해야 함

### 2.4 후보 비교

| 후보 | ① 경로별 타임아웃 | ② kubeadm 호환 + 리소스 | ③ 장기 지속성 | 판정 |
|:-----|:---------------|:---------------------|:------------|:-----|
| **Gateway API (Cilium)** | ⭐ HTTPRoute `timeouts` 필드로 route 단위 네이티브 제어 | ⭐ CNI(Cilium)에 통합 → 별도 Pod 수동 설치 불필요 | ⭐ K8s 공식 표준 + Cilium CNCF Graduated | ⭐ **선정** |
| **ingress-nginx** | ✅ Ingress 어노테이션으로 가능 (비표준) | ⭐ ~100m/128Mi, 가장 경량 | ❌ **2026.03 커뮤니티 EOL** | 탈락 |
| **Contour** | ✅ HTTPProxy CRD `timeoutPolicy` | ✅ 호환 (~150m/200Mi) | ✅ CNCF Incubating | 차선 |
| **Traefik** | ❌ EntryPoint 글로벌 레벨만 (경로별 **미지원**) | ⭐ 경량 | ✅ 활발한 개발 | 탈락 |
| **Kong** | ✅ KongIngress CRD로 가능 | ❌ ~300m/512Mi (과잉) | ✅ 활발 | 탈락 |
| **AWS ALB Controller** | ❌ ALB 단위 타임아웃만 | ❌ EKS 전제 설계 | ✅ AWS 관리형 | 탈락 |

#### 탈락 과정

1. **AWS ALB Controller 탈락** — ①②번 모두 해결 불가. kubeadm에서 IAM/VPC/IRSA 연동 부담 + ALB 단위 타임아웃으로 경로별 제어 불가
2. **Traefik 탈락** — ①번 해결 불가. 타임아웃이 EntryPoint(글로벌) 레벨에서만 설정 가능 (GitHub Issue #3237, 2018년~현재 미해결)
3. **Kong 탈락** — ②번 리소스 과잉 (~300m/512Mi = BE Pod 1개분 이상). API Gateway 기능(인증, Rate Limit)이 Spring Security + ALB WAF와 중복
4. **ingress-nginx 탈락** — ③번 해결 불가. 2026.03 커뮤니티 EOL로, 현 시점 신규 채택 시 보안 패치 중단 리스크
5. **Contour vs Gateway API (Cilium)** — 아래에서 상세 비교

### 2.5 Contour vs Gateway API (Cilium): 최종 비교

Contour는 ①②③ 모두 해결 가능한 유일한 차선 후보입니다:

| 항목 | Contour | Gateway API (Cilium) |
|:-----|:--------|:--------------------|
| 경로별 타임아웃 | ✅ HTTPProxy CRD `timeoutPolicy` | ⭐ HTTPRoute `timeouts` K8s 표준 필드 |
| 설정 변경 시 연결 유지 | ⭐ Envoy xDS 동적 업데이트 | ⭐ 동일 (Envoy 기반) |
| 컴포넌트 수 | Contour Pod + Envoy Pod = **2개 컴포넌트** | Cilium DaemonSet(이미 CNI로 존재) + Envoy Proxy = **추가 1개** |
| CRD 학습 | HTTPProxy CRD 학습 필요 | K8s 표준 Gateway API → 구현체 무관 |
| 구현체 교체 시 | HTTPProxy 매니페스트 재작성 필요 | HTTPRoute 매니페스트 **그대로 재사용** |
| CNI와의 관계 | Calico/Cilium과 별개 도구 | Cilium에 통합 → 1개 도구로 관리 |

**Gateway API (Cilium)를 선택한 이유:**

1. **K8s 표준 API**: Gateway API는 K8s SIG-Network 공식 스펙이므로, 설정이 구현체에 종속되지 않음
2. **CNI 통합**: Cilium을 CNI로 이미 사용하므로, 별도 Ingress Controller를 추가 설치·관리하지 않아도 됨
3. **관리 포인트 감소**: Calico + Contour = 2개 도구 / Cilium + Gateway API = 1개 도구

### 2.6 선정: Gateway API (Cilium 구현체)

| 문제 | Gateway API (Cilium)의 해결 |
|:-----|:--------------------------|
| ① 경로별 타임아웃 제어 | HTTPRoute `timeouts` 필드로 route 단위 네이티브 제어 |
| ② kubeadm 호환 + 최소 리소스 | CNI(Cilium)에 통합. Cilium Helm 설치 시 `gatewayAPI.enabled=true` 옵션으로 활성화 |
| ③ 장기 지속성 | K8s SIG-Network 공식 표준. 구현체를 교체해도 HTTPRoute 매니페스트 재사용 가능 |

#### Gateway API의 경로별 타임아웃 설정 예시

```yaml
# /ws 경로: WebSocket 장기 연결 유지
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: refit-ws
spec:
  parentRefs:
    - name: refit-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /ws
      timeouts:
        request: 3600s         # 유휴 채팅 연결 최대 1시간
        backendRequest: 3600s
      backendRefs:
        - name: refit-be-svc
          port: 8080
---
# /api 경로: 일반 API 기본 타임아웃
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: refit-api
spec:
  parentRefs:
    - name: refit-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      timeouts:
        request: 60s            # API 응답 60초 초과 시 타임아웃
        backendRequest: 60s
      backendRefs:
        - name: refit-be-svc
          port: 8080
```

- ingress-nginx에서 동일 기능을 구현하려면 NGINX 전용 어노테이션(`nginx.ingress.kubernetes.io/proxy-read-timeout`)을 사용해야 하며, 이는 **비표준 설정**으로 구현체 교체 시 재작성이 필요합니다.
- Gateway API의 `timeouts`는 **K8s 공식 스펙**이므로, 향후 Envoy Gateway 등 다른 구현체로 전환해도 동일한 YAML이 그대로 동작합니다.

#### 인지해야 할 한계

| 한계 | 심각도 | 완화 방안 |
|:-----|:------|:---------|
| Cilium Gateway API 커뮤니티 레퍼런스가 ingress-nginx 대비 적음 | 중간 | Cilium 공식 문서 + Cilium Slack 커뮤니티 활용. Gateway API 자체는 K8s 표준이므로 구현체 무관 자료 활용 가능 |
| CNI + Ingress를 하나의 도구(Cilium)에 의존 | 중간 | CNI 장애 자체가 클러스터 전체 네트워크 장애이므로, 분리해도 실질적 차이 없음. Gateway API 표준이므로 구현체 교체 시 매니페스트 재사용 가능 |

---

## 3. Cilium + Gateway API 통합의 시너지

CNI와 Ingress Controller를 개별적으로 선정한 결과, **Cilium 하나로 통합**되었습니다. 이 통합이 Re-Fit에 주는 이점:

### 3.1 관리 포인트 감소

| 구성 | 관리 도구 수 | 설정 방식 | 업데이트 |
|:-----|:-----------|:---------|:--------|
| Calico + ingress-nginx | 2개 Helm Chart | Calico CRD + NGINX 어노테이션 | 각각 별도 업데이트 |
| **Cilium (통합)** | 1개 Helm Chart | Cilium 설정 + K8s 표준 Gateway API | 통합 업데이트 |

### 3.2 정책 일관성

NetworkPolicy(트래픽 차단)와 트래픽 라우팅(경로 제어)이 **동일한 Cilium 정책 엔진**에서 처리됩니다:

- 별도 도구 사용 시: NetworkPolicy는 Calico에서, 라우팅은 NGINX에서 → 정책 간 충돌 가능성
- Cilium 통합 시: 네트워크 보안과 트래픽 관리를 **하나의 관점에서** 확인 가능

### 3.3 통합 관측

Hubble이 네트워크 레벨(Pod 간 통신)과 L7 레벨(HTTP 라우팅) **모두를 관측**합니다:

- NetworkPolicy 차단 트래픽 + Ingress 라우팅 상태를 **하나의 Hubble 대시보드**에서 확인
- Grafana에 네트워크 + 인그레스 메트릭을 통합 시각화

### 3.4 리소스 효율

| 항목 | Calico + ingress-nginx | Cilium (통합) | 차이 |
|:-----|:---------------------|:-------------|:-----|
| CNI DaemonSet (노드당) | Calico ~150m/128Mi | Cilium ~250m/256Mi | +100m/+128Mi |
| Ingress Controller | ingress-nginx ~100m/128Mi | Cilium Envoy Proxy ~100m/128Mi (Cilium이 자동 관리) | 동일 |
| **총 추가 리소스 (노드 2대 기준)** | 400m/384Mi | 600m/640Mi | **+200m/+256Mi** |

→ 추가 리소스는 Worker t3.large(2 vCPU/8Gi) 기준 Allocatable의 약 6~7% 수준으로, 현재 운영 여유분 내에서 충분히 흡수 가능합니다.
