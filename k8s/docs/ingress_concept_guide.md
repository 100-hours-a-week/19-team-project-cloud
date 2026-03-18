# Ingress, Ingress Controller, ALB — 개념 정리

## 1. 문제 상황: 외부 사용자가 Pod에 접근할 수 없다

K8s 클러스터 안에 BE Pod 3개, AI Pod 1개가 있다고 하자. 외부 사용자가 이 Pod들에 접근하려면 어떻게 해야 할까?

Pod는 클러스터 **내부**에서만 통신 가능한 IP를 가진다. 외부에서 직접 접근이 안 된다. 마치 **사무실 건물 안에 있는 내선 전화**와 같다 — 건물 밖에서 내선번호로 전화할 수 없다.

---

## 2. Service — 내부 전화교환기

K8s `Service`는 여러 Pod를 묶어서 **하나의 고정 주소**를 제공한다.

```
BE Pod #1 (10.244.1.5)
BE Pod #2 (10.244.2.3)  ← Service (refit-be-svc) → 내부 고정 주소 제공
BE Pod #3 (10.244.1.8)
```

하지만 Service도 기본적으로 **클러스터 내부 전용**이다. 여전히 외부에서 접근할 수 없다.

---

## 3. Ingress — "교통 규칙표"

**Ingress는 코드가 아니라, "규칙 문서"**다.

```yaml
# "이런 URL이 오면 → 이 서비스로 보내라"는 규칙
rules:
  - /api/*     → refit-be-svc:8080    # API 요청은 BE로
  - /ws/*      → refit-be-svc:8080    # WebSocket도 BE로
  - /predict/* → refit-ai-svc:8000    # AI 요청은 AI로
```

비유하면 **건물 안내판**이다:
- "영업팀 찾으시면 3층으로"
- "개발팀 찾으시면 5층으로"

안내판 자체는 그냥 **종이에 적힌 규칙**이지, 실제로 사람을 안내하지 않는다. **안내판을 보고 실제로 안내하는 사람**이 필요하다.

---

## 4. Ingress Controller — "실제로 교통을 관리하는 경찰관"

**Ingress Controller가 바로 그 "안내하는 사람"**이다.

- Ingress(규칙표)를 읽고, 그 규칙대로 **실제 트래픽을 라우팅**하는 프로그램
- 클러스터 안에 **Pod 형태**로 실행됨
- Re-Fit에서는 **ingress-nginx**를 사용 = NGINX 기반 리버스 프록시가 Pod로 떠서, Ingress 규칙을 읽어 트래픽을 분배

```
[외부 요청] → [Ingress Controller (nginx Pod)] → 규칙 확인 → /api/*     → BE Service → BE Pod
                                                           → /predict/* → AI Service → AI Pod
```

핵심: **Ingress Controller도 결국 클러스터 안의 Pod**이다.

---

## 5. 그런데 외부 트래픽이 어떻게 이 Pod까지 도달하나?

Ingress Controller Pod는 클러스터 **안**에 있다. 사용자는 **밖**에 있다.

```
사용자 → ??? → ??? → Ingress Controller Pod
```

이 "???"를 채우는 것이 **NodePort + ALB** 조합이다.

---

## 6. NodePort — "건물 벽에 뚫은 구멍"

`NodePort`는 EC2 Worker 노드의 **특정 포트(예: 30080)를 열어서**, 외부 트래픽이 Ingress Controller Pod로 들어올 수 있게 한다.

```
[사용자] → Worker 노드 IP:30080 → Ingress Controller Pod → BE/AI Pod
```

이렇게 하면 되긴 하는데... **문제가 있다**:

1. 사용자가 **Worker 노드 IP를 직접 알아야** 한다
2. Worker가 2대인데, **어느 노드로 보내야** 하나?
3. **HTTPS(TLS) 처리**를 누가 하나?
4. Worker 노드 1대가 죽으면 **그 IP로 보낸 요청은 실패**한다

---

## 7. AWS ALB — "건물 앞의 안내 데스크"

**이 모든 문제를 해결하는 것이 ALB**다.

```
[사용자 HTTPS] → CloudFront → ALB → Worker-1:30080 → Ingress Controller → BE/AI Pod
                                   → Worker-2:30080 ↗
```

### ALB가 하는 일

| ALB의 역할 | 설명 |
|:-----------|:-----|
| **단일 진입점** | 사용자는 `api.refit.com` 하나만 알면 됨. ALB가 뒤에 Worker가 몇 대인지 숨겨줌 |
| **로드밸런싱** | Worker 2대의 NodePort 30080으로 트래픽을 골고루 분배 |
| **TLS 종료** | HTTPS를 ALB에서 풀어서, 클러스터 내부는 HTTP로 통신 (ACM 인증서 사용) |
| **헬스체크** | Worker 1대가 죽으면 자동으로 살아있는 Worker로만 트래픽 전달 |

---

## 전체 흐름

```
사용자(HTTPS) → CloudFront → ALB(TLS 종료) → Worker:30080 → ingress-nginx Pod → 규칙 읽음 → BE/AI Service → Pod
                              ↑                ↑                ↑                    ↑
                        "건물 앞 안내데스크"   "벽에 뚫은 구멍"    "교통 경찰관"         "안내판"
```

---

## 핵심 정리

| 구성 요소 | 비유 | 역할 | 위치 |
|:---------|:-----|:-----|:-----|
| **Ingress** | 안내판 | "이 URL → 이 서비스"라는 **라우팅 규칙 문서**. 그 자체로는 아무것도 안 함 | K8s 리소스 (YAML) |
| **Ingress Controller** | 교통 경찰관 | Ingress 규칙을 읽고 **실제로 트래픽을 라우팅**하는 프로그램 | 클러스터 안의 **Pod** |
| **NodePort** | 벽에 뚫은 구멍 | Worker 노드의 포트를 열어 **외부 → Ingress Controller 진입 경로** 확보 | Worker 노드 |
| **ALB** | 건물 안내 데스크 | 외부 트래픽을 **Worker 노드에 분배** + TLS 종료 + 헬스체크 | AWS (클러스터 외부) |

---

## FAQ

### "ALB 없이 Ingress Controller만으로는 안 되나?"

기술적으로는 된다. Ingress Controller의 NodePort로 직접 접속할 수 있다. 하지만:
- 사용자가 Worker **IP를 직접** 알아야 하고
- Worker가 죽으면 **수동으로** 다른 IP로 바꿔야 하고
- **HTTPS 인증서**를 Ingress Controller에서 직접 관리해야 한다

ALB를 앞에 두면 이 모든 걸 AWS가 자동으로 처리해준다. 특히 **ACM(AWS Certificate Manager)으로 TLS 인증서를 무료·자동 갱신**할 수 있는 것이 큰 이점이다.

### "그러면 ALB가 있으면 Ingress Controller가 필요 없는 거 아닌가?"

아니다. **역할이 다르다.**

- **ALB**: "외부 트래픽을 **어느 Worker 노드**로 보낼까?" (노드 레벨 로드밸런싱)
- **Ingress Controller**: "이 요청을 **어느 Service(= 어느 Pod)**로 보낼까?" (경로 기반 라우팅)

ALB는 `/api`와 `/predict`를 구별하지 않는다. 그냥 Worker:30080으로 보낸다. Ingress Controller가 URL 경로를 보고 "이건 BE로, 저건 AI로" 나누는 역할을 한다.

### "ALB도 경로 기반 라우팅이 되지 않나?"

맞다. ALB 자체도 path-based routing을 지원한다. 이 경우 **AWS ALB Ingress Controller**를 사용하면 ALB가 Ingress Controller 역할까지 겸할 수 있다. 하지만 Re-Fit에서 이것을 선택하지 않은 이유는:

1. **kubeadm 환경 호환성**: AWS ALB Ingress Controller는 EKS 환경을 전제로 설계됨
2. **WebSocket 타임아웃 차등 제어 불가**: ALB의 `idle_timeout`은 ALB 전체에 적용되어 경로별 차등 불가
3. **클러스터 레벨 제어**: ingress-nginx를 쓰면 WebSocket 타임아웃, sticky session 등을 Ingress 어노테이션으로 **K8s 안에서 선언적으로** 관리 가능
