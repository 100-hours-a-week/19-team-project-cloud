# K8s 클러스터 설계 — 핵심 개념 Q&A 정리

## 1. Multi-AZ — 현재 설계에서 더 고민할 게 있는가?

### 현재 설계 구조

```
AZ-a              AZ-c              AZ-b
├─ CP-1           ├─ CP-2           ├─ CP-3
├─ Worker-1       ├─ Worker-2       │
│  ├─ BE Pod #1   │  ├─ BE Pod #2   │
│  ├─ Redis       │  ├─ AI Pod      │
│  └─ Kafka       │  └─ PLG         │
```

CP는 3개 AZ에 분산 ✅, Worker는 2개 AZ에 분산 ✅

### 추가로 인지해야 할 포인트: Stateful 워크로드의 AZ 종속

- Redis가 AZ-a의 Worker-1에 있는데, AZ-a가 죽으면 → Redis 유실 → **세션 + 채팅 Pub/Sub 전체 중단**
- Kafka도 마찬가지 → **AI 분석 작업 큐 전체 중단**
- CP는 HA로 살아있어서 "Redis Pod를 AZ-c의 Worker-2에 재스케줄링"은 가능하지만, **EBS(디스크)는 AZ에 종속**이라 다른 AZ에서 마운트 불가

즉, **Worker를 Multi-AZ로 분산해도, Stateful 워크로드(Redis/Kafka)는 AZ 장애에 취약**하다. 이건 현재 설계의 한계로 인지하되, 완전한 해결은 Redis Sentinel/Cluster, Kafka 멀티 브로커 등이 필요하며 Re-Fit 규모에서는 과잉이다.

**결론**: 현재 설계로 충분하지만, "Stateful 워크로드의 AZ 종속"이라는 한계는 인지하고 있어야 한다.

---

## 2. iptables 기반 vs eBPF 기반 — 뭐가 다른 건지

**"네트워크 패킷을 어떤 방식으로 처리하느냐"**의 차이다.

### iptables 기반 (Calico)

리눅스에 원래 내장된 방화벽/패킷 필터링 도구. 1998년부터 있었고, 모든 리눅스 서버 관리자가 알고 있다.

```
패킷이 들어옴 → 커널의 iptables 규칙 테이블을 순서대로 확인
→ "이 IP에서 온 거면 허용", "이 포트로 가는 거면 차단" 같은 규칙을 하나씩 매칭
→ 매칭되면 해당 동작(허용/차단/전달) 실행
```

비유하면 **종이 체크리스트**:
- 1번: 직원증 있으면 → 통과
- 2번: 택배기사면 → 물류센터로
- 3번: 그 외 → 차단

규칙이 100개면 최악의 경우 100개를 다 확인해야 한다. **느리지만 직관적이고, 문제가 생기면 `iptables -L`로 규칙을 바로 볼 수 있다.**

### eBPF 기반 (Cilium)

리눅스 커널 안에 **작은 프로그램을 직접 삽입**해서 패킷을 처리한다. 2014년에 나온 신기술.

```
패킷이 들어옴 → 커널 내부에 삽입된 eBPF 프로그램이 즉시 처리
→ iptables 규칙 테이블을 거치지 않고, 커널 레벨에서 바로 판단
→ 해시맵으로 O(1) 조회 → 매우 빠름
```

비유하면 **자동 AI 게이트**:
- 얼굴 인식으로 즉시 판단 → 직원이면 통과, 아니면 차단

**훨씬 빠르고 L7(HTTP URL, DNS 도메인)까지 제어 가능하지만**, 문제가 생기면 `iptables -L`로 확인할 수 없다. eBPF 전용 도구(`cilium monitor`, `hubble`)를 써야 한다. 익숙하지 않으면 "게이트가 왜 이 사람을 막았지?"를 디버깅하기가 매우 어렵다.

### 비교 요약

| | iptables (Calico) | eBPF (Cilium) |
|:--|:-----------------|:-------------|
| 비유 | 종이 체크리스트 | AI 자동 게이트 |
| 속도 | 규칙 많으면 느림 | 항상 빠름 |
| 제어 범위 | L3/L4 (IP, 포트) | L3/L4/L7 (URL, DNS까지) |
| 디버깅 | `iptables -L`로 바로 확인 | 전용 도구 필요 |
| Re-Fit 선택 | ✅ 선택 — 익숙한 도구로 디버깅 가능 | 탈락 — 학습 비용 |

---

## 3. VXLAN이 뭔지

K8s에서 각 Pod는 **자기만의 IP**를 가진다. 그런데 Pod가 서로 다른 Worker 노드에 있으면, 물리적으로 다른 서버에 있는 셈이다.

### 문제

Worker-1의 Pod(10.244.1.5)가 Worker-2의 Pod(10.244.2.3)에게 패킷을 보내려면, 이 패킷이 **물리 네트워크(AWS VPC)**를 통과해야 한다. 그런데 AWS VPC는 `10.244.x.x`라는 Pod IP를 모른다. VPC는 EC2 인스턴스 IP(예: `172.31.1.10`)만 알고 있다.

### VXLAN의 해결 방법: "편지를 봉투에 넣는다"

```
[Pod 패킷: 10.244.1.5 → 10.244.2.3]   ← 이건 VPC가 모르는 주소

VXLAN이 이걸 포장함:

[VPC 봉투: 172.31.1.10 → 172.31.2.20]  ← 이건 VPC가 아는 주소
  └─ [안의 편지: 10.244.1.5 → 10.244.2.3]
```

- Worker-1이 Pod 패킷을 **VPC가 이해하는 봉투(VXLAN 헤더)**로 감싸서 보냄
- AWS VPC는 봉투의 주소(EC2 IP)만 보고 Worker-2로 전달
- Worker-2가 봉투를 뜯어서 안의 Pod 패킷을 꺼내 목적지 Pod에게 전달

**장점**: AWS VPC 라우팅 테이블을 건드릴 필요 없음. 봉투로 감싸니까 VPC는 Pod IP를 몰라도 됨.

**단점**: 봉투 포장/뜯기에 약간의 시간이 추가됨 (~0.5ms). Re-Fit 규모에서는 체감 불가.

**BGP 모드**는 반대로 "VPC 라우팅 테이블에 Pod IP 대역을 직접 등록"하는 방식이라 봉투가 필요 없지만, VPC 설정을 건드려야 해서 kubeadm에서 번거롭다.

---

## 4. Traefik의 "글로벌 레벨" 타임아웃

Traefik에서 타임아웃 설정은 **EntryPoint**라는 곳에서만 설정할 수 있다.

**EntryPoint = Traefik이 외부 트래픽을 받는 입구**. 보통 하나만 있다.

```
클라이언트 → [EntryPoint :443] → /api/*     → BE Service
                                → /ws/*      → BE Service
                                → /predict/* → AI Service
```

EntryPoint에 `readTimeout: 3600`을 설정하면, 이 EntryPoint를 통과하는 **모든 경로에 3600초가 적용**된다.

```
/api/users  → 3600초 타임아웃 ← 이건 60초면 충분한데 3600초가 됨 😱
/ws/chat    → 3600초 타임아웃 ← 이건 맞음 ✅
/predict    → 3600초 타임아웃 ← 이것도 60초면 충분한데 3600초 😱
```

**문제**: `/api` 경로에서 서버가 응답을 안 하면 3600초(1시간) 동안 기다려야 함. 일반 API의 장애를 **1시간 동안 감지 못함**.

**ingress-nginx는 다름**: Ingress 리소스 단위로 타임아웃을 설정하므로:

```
[Ingress A: /ws/*]   → proxy-read-timeout: 3600  ← WebSocket용
[Ingress B: /api/*]  → proxy-read-timeout: 60    ← 일반 API용 (기본값)
```

각 경로에 **다른 타임아웃**을 적용할 수 있다. 이것이 "경로별 차등 제어".

---

## 5. Contour 2계층 구조 vs 다른 컨트롤러 — 구조 비교

### ingress-nginx (1계층)

```
[클라이언트 요청] → [nginx Pod 1개]
                     ├─ Ingress 규칙 읽기    ← 컨트롤러 역할
                     └─ 트래픽 실제 라우팅    ← 프록시 역할
                     (하나의 프로세스가 둘 다 함)
```

- **Pod 1개**가 "규칙 읽기"와 "트래픽 처리"를 동시에 수행
- 장애 나면 → 이 Pod 하나만 보면 됨
- 리소스: ~100m / ~128Mi

### Contour (2계층)

```
[클라이언트 요청] → [Envoy Pod]          ← 트래픽 실제 라우팅 (데이터 플레인)
                       ↑ 설정 수신
                   [Contour Pod]         ← Ingress 규칙 읽기 + Envoy에 전달 (컨트롤 플레인)
```

- **Contour Pod**: K8s의 Ingress/HTTPProxy 리소스를 감시하고, 규칙이 바뀌면 Envoy에게 알려줌
- **Envoy Pod**: Contour에게 받은 규칙대로 실제 트래픽을 라우팅
- **장애 시**: "요청이 안 가요" → Envoy 문제? Contour가 규칙을 잘못 전달? Contour↔Envoy 통신 문제? → **원인 분리 진단 필요**
- 리소스: ~150m / ~200Mi (두 Pod 합산)

### Traefik (1계층)

```
[클라이언트 요청] → [Traefik Pod 1개]
                     ├─ Ingress 규칙 읽기
                     └─ 트래픽 실제 라우팅
                     (nginx와 동일한 1계층)
```

- nginx와 구조는 같음. 다만 경로별 타임아웃 불가로 탈락.

### Contour의 장점과 Re-Fit에서 안 쓴 이유

**Contour의 장점**: Envoy는 xDS API로 설정을 받으므로 **설정이 바뀌어도 프로세스 재시작 없이 반영** → 기존 WebSocket 연결이 안 끊김. nginx는 설정 변경 시 worker 리로드가 필요해서 연결이 끊어질 수 있음.

**Re-Fit에서 Contour를 안 쓴 이유**: 설정 변경 빈도가 매우 낮아(배포 때만) 이 장점의 실익이 제한적. 반면 2계층 디버깅 복잡도 + 50% 더 많은 리소스는 상시 부담.

---

## 6. Gateway API가 뭐고, 처음부터 쓰면 안 되나?

### Gateway API란?

K8s에서 트래픽 관리를 하는 **차세대 표준 규격**이다.

현재 쓰는 `Ingress`는 K8s 초기(2015년)에 만든 규격인데, 기능이 너무 단순하다:

```yaml
# Ingress (기존) — "경로별 라우팅"만 할 수 있음
rules:
  - path: /api → BE Service
  - path: /ws  → BE Service
# 타임아웃? 어노테이션으로... (표준이 아님, 컨트롤러마다 다름)
```

`Gateway API`는 이걸 대체하려고 2020년부터 개발 중인 **공식 후속 규격**이다:

```yaml
# Gateway API (차세대) — 타임아웃, 트래픽 비율 분할 등을 표준으로 지원
HTTPRoute:
  - path: /api → BE Service (timeout: 60s)
  - path: /ws  → BE Service (timeout: 3600s)  ← 표준 필드!
```

### 처음부터 Gateway API를 쓰면 안 되나?

기술적으로는 가능하지만, 현 시점에서 리스크가 있다:

| 고려사항 | Ingress + ingress-nginx | Gateway API |
|:--------|:----------------------|:-----------|
| **성숙도** | 10년 역사, 프로덕션 검증 완료 | GA(정식 릴리스)되었지만 아직 **실 프로덕션 사례가 적음** |
| **커뮤니티 레퍼런스** | Stack Overflow, 블로그 답변 **압도적** | "Gateway API + WebSocket + kubeadm" 조합의 트러블슈팅 자료가 부족 |
| **구현체 선택** | ingress-nginx 하나로 확정 | Envoy Gateway? Traefik? Istio? → **어떤 구현체를 쓸지도 결정 필요** |
| **학습 곡선** | Ingress 리소스 1개만 이해하면 됨 | Gateway, GatewayClass, HTTPRoute, ReferenceGrant 등 **새로운 리소스 4~5개 학습 필요** |
| **kubeadm 환경** | 레퍼런스 매우 풍부 | kubeadm에서 Gateway API를 쓴 사례가 **매우 드물**. 대부분 EKS/GKE 환경 |

**핵심**: Gateway API의 방향성은 좋지만, **kubeadm 환경에서 WebSocket을 운영하는 레퍼런스가 거의 없다.** 문제가 생겼을 때 검색해도 답을 찾기 어렵다. 반면 ingress-nginx는 같은 문제를 겪은 사람의 해결책이 넘쳐난다.

그래서 **"지금은 ingress-nginx로 안정적으로 시작하고, Gateway API가 더 성숙해지면 전환"**이라는 전략을 취한 것이다. ingress-nginx EOL(2026.03)까지 시간이 있으므로, 그 사이에 Gateway API 생태계가 더 성숙해질 것으로 기대한다.
