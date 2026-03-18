# WebSocket HTTPRoute 타임아웃 설정

## 배경

Spring Boot 백엔드는 실시간 채팅, 알림 등의 기능에 WebSocket을 사용한다. WebSocket은 단일 TCP 연결을 장시간 유지하는 프로토콜이기 때문에, 일반 REST API와 동일한 타임아웃을 적용하면 연결이 중간에 끊어진다.

Cilium Gateway API 환경에서는 HTTPRoute 리소스의 `timeouts` 필드로 경로별 타임아웃을 독립적으로 설정할 수 있다.

---

## 문제

기존 HTTPRoute는 단일 규칙으로 `/api`와 `/actuator` 경로를 모두 처리했고, 타임아웃 설정이 없었다.

```yaml
# 변경 전
rules:
- matches:
  - path:
      type: PathPrefix
      value: /api
  - path:
      type: PathPrefix
      value: /actuator
  backendRefs:
  - name: refit-backend-svc
    port: 8080
```

타임아웃 미설정 시 Envoy의 기본값(15초)이 적용되어 WebSocket 연결이 15초 후 강제 종료된다.

---

## 해결 방법: 경로별 HTTPRoute 규칙 분리

WebSocket 엔드포인트(`/api/ws`)를 별도 규칙으로 분리하고, 각 규칙에 적합한 타임아웃을 적용했다.

### Gateway API `timeouts` 필드

| 필드 | 의미 |
|---|---|
| `request` | 클라이언트가 요청을 완전히 전송하는 시간 (헤더 포함). WebSocket의 경우 연결 유지 시간과 동일 |
| `backendRequest` | Gateway가 백엔드 서비스와 연결을 유지하는 시간. `request`보다 짧거나 같아야 함 |

### Helm 차트 구조

`k8s/helm/refit-backend/values.yaml`:

```yaml
gateway:
  name: refit-gateway
  routes:
    - paths:
        - /api/ws        # WebSocket 전용 규칙
      timeouts:
        request: "3600s"         # 1시간 (WebSocket 세션 유지)
        backendRequest: "3600s"
    - paths:
        - /api           # 일반 REST API
        - /actuator      # 헬스체크, 메트릭 등
      timeouts:
        request: "60s"           # 1분
        backendRequest: "60s"
```

`k8s/helm/refit-backend/templates/httproute.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: backend-route
  namespace: refit-app
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: {{ .Values.gateway.name }}
  rules:
  {{- range .Values.gateway.routes }}
  - matches:
    {{- range .paths }}
    - path:
        type: PathPrefix
        value: {{ . }}
    {{- end }}
    timeouts:
      request: {{ .timeouts.request }}
      backendRequest: {{ .timeouts.backendRequest }}
    backendRefs:
    - group: ""
      kind: Service
      name: refit-backend-svc
      port: {{ $.Values.service.port }}
      weight: 1
  {{- end }}
```

### 렌더링 결과

위 Helm 템플릿이 렌더링되면 다음과 같은 HTTPRoute가 생성된다:

```yaml
rules:
- matches:
  - path:
      type: PathPrefix
      value: /api/ws
  timeouts:
    request: "3600s"
    backendRequest: "3600s"
  backendRefs:
  - name: refit-backend-svc
    port: 8080
- matches:
  - path:
      type: PathPrefix
      value: /api
  - path:
      type: PathPrefix
      value: /actuator
  timeouts:
    request: "60s"
    backendRequest: "60s"
  backendRefs:
  - name: refit-backend-svc
    port: 8080
```

---

## HTTPRoute 매칭 우선순위

Gateway API는 더 **구체적인(specific) 경로를 우선** 매칭한다.

| 경로 패턴 | 예시 요청 | 매칭 규칙 |
|---|---|---|
| `/api/ws` (PathPrefix) | `GET /api/ws/chat` | WebSocket 규칙 (3600s) |
| `/api` (PathPrefix) | `GET /api/users` | REST 규칙 (60s) |
| `/api` (PathPrefix) | `GET /api/ws/...`는 더 긴 `/api/ws`가 우선 | WebSocket 규칙 (3600s) |

`/api/ws`는 `/api`보다 경로가 길기 때문에 Gateway API 스펙에 따라 항상 먼저 매칭된다.

---

## 적용 아키텍처

```
클라이언트
  │
  ├── WebSocket 요청 (ws://api-k8s.re-fit.kr/api/ws/...)
  │     │
  │     ▼
  │   ALB → NodePort:30080 → cilium-envoy
  │     │
  │     │  HTTPRoute 규칙 1: /api/ws  → timeout: 3600s
  │     ▼
  │   refit-backend:8080 (WebSocket 연결 1시간 유지)
  │
  └── REST 요청 (https://api-k8s.re-fit.kr/api/...)
        │
        ▼
      ALB → NodePort:30080 → cilium-envoy
        │
        │  HTTPRoute 규칙 2: /api, /actuator  → timeout: 60s
        ▼
      refit-backend:8080 (60초 타임아웃)
```

---

## 검증

ArgoCD sync 후 CiliumEnvoyConfig에 타임아웃 설정이 반영된 것을 확인:

```bash
kubectl get ciliumenvoyconfig cilium-gateway-refit-gateway -n refit-app -o yaml | grep -A 5 'pathSeparatedPrefix\|timeout'
```

출력:
```yaml
- match:
    pathSeparatedPrefix: /api/ws
  route:
    cluster: refit-app:refit-backend-svc:8080
    timeout: 3600s        # WebSocket 1시간
- match:
    pathSeparatedPrefix: /api
  route:
    cluster: refit-app:refit-backend-svc:8080
    timeout: 60s          # REST 60초
```

---

## 참고

- [Gateway API HTTPRoute Timeouts](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.HTTPRouteTimeouts)
- WebSocket 연결 시간은 서비스 특성에 따라 조정 가능 (현재 1시간)
- ALB의 idle timeout도 별도로 설정 필요 (현재 ALB 기본값: 60초 → WebSocket을 위해 3600초 이상으로 조정 권장)
