# NetworkPolicy 장애 분석: Cilium Gateway API 환경에서의 hostNetwork 이슈

## 개요

`refit-app` 네임스페이스에 `default-deny-ingress` NetworkPolicy를 적용한 직후 전체 서비스가 다운됐다. TCP 연결은 성공하지만 HTTP 응답이 없는 증상이 약 2시간 지속됐다.

---

## 타임라인

| 시각 | 이벤트 |
|---|---|
| T+0 | `default-deny-ingress`, `allow-cilium-gateway`, `allow-monitoring-scrape` NetworkPolicy 적용 |
| T+1분 | 서비스 응답 없음 확인 (TCP 연결은 성공, HTTP 타임아웃) |
| T+5분 | `kubectl delete networkpolicy --all -n refit-app` 실행 → 여전히 503 |
| T+10분 | `kubectl rollout restart daemonset cilium-envoy -n kube-system` → 여전히 503 |
| T+15분 | `kubectl rollout restart daemonset cilium -n kube-system` → 여전히 503 |
| T+60분 | Envoy admin API 분석으로 원인 파악: `cx_connect_fail: 37` (엔드포인트별 연결 실패 누적) |
| T+90분 | git에서 NetworkPolicy 제거, ArgoCD sync 차단 |
| T+100분 | `kubectl delete pod cilium-envoy-2tzm8 -n kube-system` → **200 OK 복구** |

---

## 증상

- `curl http://<NODE_IP>:30080/actuator/health` → TCP 연결 성공 후 HTTP 타임아웃 (0 bytes received)
- Cilium Envoy 로그: xDS gRPC 스트림 반복 단절
  ```
  StreamRoutes gRPC config stream to xds-grpc-cilium closed: 13, upstream_reset_after_response_started{connection_termination}
  StreamEndpoints gRPC config stream to xds-grpc-cilium closed: 13, ...
  StreamListeners gRPC config stream to xds-grpc-cilium closed: 13, ...
  ```
- Envoy admin clusters API: 백엔드 엔드포인트별 `cx_connect_fail` 50+ 누적

---

## 근본 원인

### 1. hostNetwork 파드의 Cilium 아이덴티티

Cilium의 Gateway API 구현에서 트래픽 경로는 다음과 같다:

```
ALB → NodePort:30080 → [Cilium eBPF] → cilium-envoy:13057 → Backend Pod
```

`cilium-envoy`는 `hostNetwork: true` DaemonSet이다. Cilium의 eBPF 보안 모델에서 hostNetwork 파드의 아이덴티티는 **라벨 기반 Pod Identity가 아닌 `reserved:host` / `reserved:remote-node`** 로 처리된다.

따라서 표준 Kubernetes NetworkPolicy의 `podSelector`는 cilium-envoy를 매칭하지 못한다:

```yaml
# 이 정책은 효과가 없음
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: kube-system
    podSelector:
      matchLabels:
        k8s-app: cilium-envoy  # hostNetwork 파드는 이 selector에 매칭 안 됨
```

### 2. xDS 스트림 연쇄 장애

NetworkPolicy가 cilium-envoy → 백엔드 파드 연결을 차단하자, Envoy는 백엔드 엔드포인트로의 연결을 반복 시도하고 실패를 누적했다. 이 과정에서 Cilium agent와 cilium-envoy 간 xDS gRPC 스트림이 불안정해졌다.

### 3. 상태 오염 (Dirty State)

NetworkPolicy를 제거해도 이미 오염된 Envoy 내부 상태(cx_connect_fail 누적, EDS 스트림 불안정)가 유지됐다. cilium-envoy DaemonSet 전체 재시작으로도 복구되지 않았고, **개별 파드 재시작**으로만 복구됐다.

> DaemonSet 재시작(`rollout restart`)은 파드를 순차적으로 교체하기 때문에, 이미 다른 파드로 인한 클러스터 상태 오염이 남아있을 수 있다. 직접 pod delete가 즉각 복구에 효과적이었다.

---

## 진단 과정

### Envoy admin API 활용

```bash
# Cilium 에이전트를 통해 Envoy admin API 접근
kubectl exec -n kube-system <cilium-agent-pod> -- cilium-dbg envoy admin clusters

# 주요 확인 지표
# - cx_connect_fail: 연결 실패 누적 횟수
# - health_flags: healthy / failed_active_hc
# - rq_success / rq_error: 요청 성공/실패
```

발견 내용:
```
refit-backend-svc::10.244.3.181:8080::cx_connect_fail::37    ← 연결 실패 37회
refit-backend-svc::10.244.3.181:8080::health_flags::healthy   ← 하지만 헬스는 healthy
argocd-server::10.244.3.95:8080::cx_connect_fail::0           ← argocd는 정상 (NetworkPolicy 없음)
```

argocd는 NetworkPolicy가 없어서 정상, refit-backend만 차단 → NetworkPolicy 원인 확정

### 파드 직접 접근 가능 여부 확인

```bash
# 파드→파드: 정상
kubectl exec -n refit-app deploy/refit-backend -- wget http://refit-backend-svc:8080/actuator/health

# hostNetwork 파드→파드: 정상
kubectl run debug-host --image=curlimages/curl --restart=Never --rm -i \
  --overrides='{"spec":{"nodeName":"ip-10-2-1-227","hostNetwork":true}}' \
  -- curl http://10.244.3.181:8080/actuator/health
```

일반적인 hostNetwork 파드에서는 접근 가능 → 문제는 cilium-envoy에 특화된 eBPF 처리 이슈

---

## 올바른 NetworkPolicy 설계 (Cilium Gateway API 환경)

표준 `NetworkPolicy` 대신 `CiliumNetworkPolicy`를 사용해야 한다.

```yaml
# cilium-envoy(hostNetwork) 트래픽 허용
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-gateway-ingress
  namespace: refit-app
spec:
  endpointSelector: {}
  ingress:
  - fromEntities:
    - host         # 동일 노드의 cilium-envoy (같은 노드에 배포된 경우)
    - remote-node  # 다른 노드의 cilium-envoy (cross-node 라우팅)
---
# 모니터링 스크랩 허용 (표준 NetworkPolicy로 가능 - 일반 파드 간 통신)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring-scrape
  namespace: refit-app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    ports:
    - protocol: TCP
      port: 8080
    - protocol: TCP
      port: 8000
```

### Cilium 아이덴티티 구조

| 아이덴티티 | 대상 | 사용 시점 |
|---|---|---|
| `reserved:host` | 동일 노드의 호스트 프로세스/hostNetwork 파드 | 같은 노드의 cilium-envoy → 파드 |
| `reserved:remote-node` | 다른 노드의 호스트 프로세스/hostNetwork 파드 | 다른 노드의 cilium-envoy → 파드 |
| `reserved:cluster` | 클러스터 내 모든 파드 및 노드 | 클러스터 내부 전체 허용 시 |
| Pod 라벨 기반 | 일반 파드 (hostNetwork 아님) | 표준 NetworkPolicy podSelector |

---

## 복구 방법

```bash
# 빠른 복구: 문제가 있는 노드의 cilium-envoy 파드 재시작
kubectl delete pod <cilium-envoy-pod-name> -n kube-system

# 전체 cilium-envoy 재시작이 필요한 경우
kubectl delete pod -n kube-system -l k8s-app=cilium-envoy
```

> 주의: `kubectl rollout restart daemonset cilium-envoy`는 순차 교체라 오염된 클러스터 상태가 남아있을 수 있다. 빠른 복구가 필요하면 직접 pod delete가 효과적이다.

---

## 교훈

1. **Cilium + Gateway API 환경에서 NetworkPolicy는 사전 테스트 필수** — 표준 NetworkPolicy는 hostNetwork 파드를 제대로 다루지 못한다.
2. **Envoy 상태 오염은 NetworkPolicy 제거로 자동 복구되지 않는다** — cilium-envoy 재시작이 필요하다.
3. **ArgoCD auto-sync가 활성화된 환경에서는 git에서 먼저 제거 후 클러스터 수정** — 클러스터에서 삭제해도 ArgoCD가 수십 초 내에 재적용한다.
4. **Envoy admin API(`cilium-dbg envoy admin clusters`)는 강력한 진단 도구** — cx_connect_fail 카운트로 어떤 엔드포인트가 문제인지 즉시 파악 가능하다.
