# Re-Fit 부하테스트 실행 가이드

## 목차

1. [사전 준비](#1-사전-준비)
2. [테스트 환경](#2-테스트-환경)
3. [시나리오별 실행 가이드](#3-시나리오별-실행-가이드)
   - [1. Baseline Test](#31-baseline-test--정상-상태-기준값-측정)
   - [2. Load Test](#32-load-test--일반-부하-검증)
   - [3. Stress Test](#33-stress-test--한계점-탐색)
   - [4. Spike Test](#34-spike-test--급증-대응력-검증)
   - [5. AI Agent Test](#35-ai-agent-test--ai-sse-스트리밍-검증)
   - [6. HPA Validation Test](#36-hpa-validation-test--hpa-스케일링-검증)
   - [7. Self-Healing Test](#37-self-healing-test--파드-자동-복구-검증)
4. [전체 자동 실행](#4-전체-자동-실행)
5. [모니터링 대시보드 설명](#5-모니터링-대시보드-설명)
6. [SLO 기준](#6-slo-기준)
7. [테스트 후 정리](#7-테스트-후-정리)

---

## 1. 사전 준비

### 필수 도구

```bash
# k6 설치 확인
k6 version

# macOS 설치
brew install k6
```

### 테스트 데이터 확인

```bash
# data/test-users.json 존재 확인 (25명 토큰)
ls loadtest/data/test-users.json

# sample PDF 존재 확인 (LLM 파싱용 3MB)
ls loadtest/data/sample_resume_3mb.pdf
```

### 모니터링 터미널 준비 (별도 터미널)

```bash
# HPA 실시간 모니터링
watch -n5 kubectl get hpa -n refit-app

# Pod 수 실시간 모니터링
watch -n5 kubectl get pods -n refit-app
```

---

## 2. 테스트 환경

| 항목 | 값 |
|------|-----|
| 대상 서버 | `https://api-k8s.re-fit.kr` (prod k8s) |
| 테스트 계정 | JOB_SEEKER 20명 (5001~5020), EXPERT 5명 (6001~6005) |
| 결과 저장 | `loadtest/results/` |

### 인프라 구성

| 서비스 | HPA (min→max) | CPU 임계값 | VPA |
|--------|--------------|-----------|-----|
| refit-backend | 2 → 5 pods | CPU 70% | Off (추천만) |
| refit-ai | 1 → 3 pods | CPU 70% | Off (추천만) |

---

## 3. 시나리오별 실행 가이드

### 3.1 Baseline Test — 정상 상태 기준값 측정

#### 목적

- 부하가 없는 정상 상태에서 API 응답시간·에러율 기준값(baseline) 수집
- 이후 테스트의 SLO 목표값 산정에 활용
- HPA 트리거 없음 (5 VU는 스케일아웃 수준 아님)

#### 부하 프로파일

```
VU: ─────────────── 5 ───────────────
     0           10분
```

| 시나리오 | VU | 동작 |
|---------|-----|------|
| 단일 | 5 | 현직자 검색 → 이력서 목록 → 채팅 목록 (순환) |

#### 실행 명령

```bash
cd loadtest
k6 run scripts/1-baseline.js
```

#### 확인할 Grafana 패널

| 대시보드 | 패널 | 확인 포인트 |
|---------|------|-----------|
| **Service Performance** | Latency (ms), P95 Latency | 각 API별 평시 응답시간 — SLO 기준값으로 기록 |
| **Service Performance** | Request Rate | 정상 RPS 기준값 |
| **K8s Views Global** | CPU Usage, RAM Usage | Pod 정상 상태 리소스 사용량 |
| **K8s Dashboard 15661** | Pod Containers CPU Utilization | refit-backend 평시 CPU 수준 |

#### 결과 해석

- `expert_search` P95 < 2초 → 정상
- `resume_list` P95 < 1초 → 정상
- 에러율 0% → 정상
- 이 수치가 이후 테스트의 **정상 기준선**이 됨

---

### 3.2 Load Test — 일반 부하 검증

#### 목적

- 실서비스 수준의 부하(25 VU)에서 SLO 준수 여부 확인
- AI 파싱·이력서·검색·채팅 혼합 시나리오로 실사용 패턴 재현
- 각 사용자 유형별 성능 차이 측정

#### 부하 프로파일

```
Group A (AI 파싱)  : ──▲─── 12 ───▼──
Group B (이력서)   : ──▲──  8  ──▼──
Group C (검색/채팅): ──▲─   5  ─▼──
                        0    7분
```

| 그룹 | VU | 동작 |
|------|-----|------|
| **A (고부하)** | 12 | S3 업로드 → LLM 파싱 → 이력서 목록 → 현직자 검색(job_id=1) → 채팅 생성·조회 |
| **B (일반)** | 8 | 수동 이력서 생성 → 현직자 검색(skill_id=1) → 채팅 생성·조회 |
| **C (경량)** | 5 | 현직자 검색(skill_id=1) → 채팅 조회 → 30% 확률 프로필 수정 |

#### 실행 명령

```bash
cd loadtest
k6 run scripts/2-load-test.js
```

#### SLO 기준 (Pass/Fail)

| 지표 | 목표 |
|------|------|
| 현직자 검색 P95 | < 2,000ms |
| LLM 파싱 P95 | < 7,000ms |
| LLM 파싱 P99 | < 10,000ms |
| 전체 에러율 | < 2% |
| LLM 성공률 | > 95% |

#### 확인할 Grafana 패널

| 대시보드 | 패널 | 확인 포인트 |
|---------|------|-----------|
| **Service Performance** | Error Rate (%), Latency (ms), P95 Latency | SLO 준수 여부 실시간 확인 |
| **K8s Dashboard 15661** | Pod Containers CPU Utilization | refit-backend CPU — 70% 근접 시 HPA 예비 트리거 |
| **K8s Dashboard 15661** | Pod Container Memory Usage | refit-ai 메모리 — LLM 처리 중 급증 여부 |
| **Kafka / MSK** | Consumer Lag, Produce 레이턴시 | 채팅 메시지 Kafka 처리 지연 여부 |
| **Kubernetes Apps Logs** | 앱 로그 | ERROR 로그 발생 여부 |

---

### 3.3 Stress Test — 한계점 탐색

#### 목적

- 시스템의 Breaking Point(임계 VU 수) 탐색
- HPA 스케일아웃이 실제로 발동하는지 확인 (CPU 70% 초과 시)
- 병목 지점 식별 (백엔드 CPU / AI 메모리 / DB / Kafka)
- **에러율 30% 초과 또는 LLM 성공률 50% 미만이면 테스트 자동 중단**

#### 부하 프로파일

```
VU: 0──▲──20──▲──40──▲──60──▲──80──▲──100──▼──0
        2m  2m  2m  2m  2m  2m  2m  2m  2m  2m  4m
```

| 단계 | VU | 시간 | 예상 동작 |
|------|-----|------|---------|
| 웜업 | 0 → 20 | 4분 | 정상 처리 |
| 증가 | 20 → 40 | 4분 | CPU 상승 시작 |
| 증가 | 40 → 60 | 4분 | **HPA 트리거 구간** (CPU 70% 초과) |
| 증가 | 60 → 80 | 4분 | 스케일아웃 완료 후 안정 또는 에러 급증 |
| 피크 | 80 → 100 | 4분 | Breaking Point 탐색 |
| 쿨다운 | 100 → 0 | 4분 | 스케일다운 관찰 |

> **40% AI 파싱 + 60% 현직자 검색·채팅·이력서 조회** 혼합

#### 실행 명령

```bash
cd loadtest
k6 run scripts/3-stress-test.js
```

#### 확인할 Grafana 패널 ← **가장 중요한 테스트**

| 대시보드 | 패널 | 확인 포인트 |
|---------|------|-----------|
| **K8s Views Global** | **Running Pods** | Pod 수 2 → 5 스케일아웃 타이밍 확인 |
| **K8s Views Global** | Container Restarts by namespace | OOM/크래시 여부 |
| **K8s Views Global** | OOM Events by namespace | Memory limit 초과 감지 |
| **K8s Dashboard 15661** | **Pod Containers CPU Utilization** | 70% 임계값 돌파 시점 확인 |
| **K8s Dashboard 15661** | Pod Number (refit-app 필터) | 스케일아웃 전·후 Pod 수 변화 |
| **Service Performance** | **Error Rate (%)** | 스케일아웃 지연 구간 에러 급등 여부 |
| **Service Performance** | Latency (ms) | 부하 단계별 레이턴시 변화 패턴 |
| **Kafka / MSK** | 토픽별 Consumer Lag | 채팅 메시지 밀림 여부 |
| **Kubernetes Apps Logs** | 앱 로그 | OOMKilled, 504, DB 커넥션 에러 |

#### Breaking Point 판단 기준

- 에러율 > 20% (1분 이상 지속)
- P95 > 15초
- 502/504 연속 발생 (30초 이상)
- OOMKilled 이벤트 발생

---

### 3.4 Spike Test — 급증 대응력 검증

#### 목적

- 트래픽이 순간적으로 10배 급증했을 때 시스템이 버티는지 확인
- 급증 → 안정화까지의 **회복 시간(Recovery Time)** 측정
- HPA 반응 속도 vs 에러율 관계 확인

#### 부하 프로파일

```
        ┌──────────┐
   50   │ 피크 유지  │
        │          │
    5 ──┘          └── 5 ──── (회복 관찰)
    |   30s spike  30s
    0         총 9분
```

| 단계 | VU | 시간 | 목적 |
|------|-----|------|------|
| 평상시 | 5 | 2분 | 기준선 확인 |
| 급증 | 5 → 50 | 30초 | 10배 순간 증가 |
| 피크 | 50 | 2분 30초 | 시스템 대응 확인 |
| 급감 | 50 → 5 | 30초 | 트래픽 복구 |
| 회복 관찰 | 5 | 2분 30초 | 회복 시간 측정 |

> **30% AI 파싱 + 30% 이력서 생성 + 40% 현직자 검색** 혼합

#### 실행 명령

```bash
cd loadtest
k6 run scripts/4-spike-test.js
```

#### SLO 기준 (Spike 허용 기준)

| 지표 | 목표 |
|------|------|
| 급증 구간 에러율 | < 15% |
| LLM 성공률 | > 80% |
| 현직자 검색 P95 | < 5,000ms |
| LLM 파싱 P95 | < 15,000ms |
| 회복 시간 | < 1분 |

#### 확인할 Grafana 패널

| 대시보드 | 패널 | 확인 포인트 |
|---------|------|-----------|
| **Service Performance** | **Error Rate (%)** | 급증 구간 에러 급등 → 회복까지 시간 측정 |
| **Service Performance** | **Latency (ms)** | 레이턴시 스파이크 폭과 회복 패턴 |
| **K8s Views Global** | Running Pods | HPA 스케일아웃 반응 시간 (급증 후 얼마 만에 스케일?) |
| **K8s Dashboard 15661** | Pod Containers CPU Utilization | CPU 급등 → HPA 반응 딜레이 |

#### 관찰 포인트

- 급증 후 에러율이 치솟았다가 HPA 스케일아웃으로 회복하는 패턴 관찰
- HPA는 평균 1~2분 내 반응 → 그 전까지 에러율 높아도 정상
- 회복 관찰 구간(5 VU)에서 에러율이 0으로 돌아오는지 확인

---

### 3.5 AI Agent Test — AI SSE 스트리밍 검증

#### 목적

- AI 에이전트 채팅의 SSE(Server-Sent Events) 스트리밍 응답 성능 검증
- LLM 추론 지연(10~30초)에서 P95 < 30초 유지 확인
- 낮은 동시 접속(3 VU)에서 refit-ai 서비스 안정성 확인

#### 부하 프로파일

```
VU: ─────────────── 3 ───────────────
     0           10분
```

| 단계 | 동작 |
|------|------|
| 1 | POST /api/ai/agent/sessions → 세션 생성 |
| 2 | POST /api/ai/agent/reply → SSE 스트리밍 수신 (done 이벤트까지 대기) |
| 3 | 5개 취업 관련 질문 순환 반복 |

#### 실행 명령

```bash
cd loadtest
k6 run scripts/5-ai-agent-test.js
```

#### SLO 기준

| 지표 | 목표 |
|------|------|
| 세션 생성 P95 | < 3,000ms |
| SSE 응답 P95 | < 30,000ms |
| SSE 응답 P99 | < 45,000ms |
| 성공률 | > 90% |
| HTTP 에러율 | < 5% |

#### 확인할 Grafana 패널

| 대시보드 | 패널 | 확인 포인트 |
|---------|------|-----------|
| **Service Performance** | Latency (ms), P95 Latency | `/api/ai/*` 경로 SSE 응답시간 |
| **K8s Dashboard 15661** | Pod Container Memory Usage | refit-ai 메모리 — LLM 추론 중 급증 여부 |
| **K8s Dashboard 15661** | Pod Containers CPU Utilization | refit-ai CPU 사용률 |
| **Kubernetes Apps Logs** | 앱 로그 | AI 서비스 타임아웃·오류 로그 |

#### 참고

- SSE는 k6가 스트림 종료(`done` 이벤트)까지 응답을 버퍼링함
- 응답시간 = 세션 생성부터 마지막 토큰 수신까지 전체 시간
- 다른 테스트와 **병행 실행 가능** (3 VU로 부하 낮음)

---

### 3.6 HPA Validation Test — HPA 스케일링 검증

#### 목적

- CPU를 의도적으로 70% 이상으로 지속 유지해 **HPA 스케일아웃 실제 발동** 확인
- 스케일아웃 → 부하 감소 → 스케일다운 전체 사이클 관찰
- VPA 추천 메모리값 수집 (updateMode: Off)
- 스케일링 중 에러 없이 서비스 유지되는지 확인

#### 부하 프로파일

```
VU:    ┌──────────────────────┐
  35   │     CPU > 70% 구간    │
       │     (HPA 트리거)       │
  20   │                      └── ─▼
   0 ──┘                              0
       5m         10m          5m   2m
```

| 단계 | VU | 시간 | 목적 |
|------|-----|------|------|
| 램프업 | 0 → 35 | 5분 | CPU 상승 |
| 지속 부하 | 35 | 10분 | **HPA 트리거 유지** (CPU > 70% × 3분 → 스케일) |
| 감소 | 35 → 20 | 5분 | 스케일다운 관찰 |
| 종료 | 20 → 0 | 2분 | 완전 종료 |

> **50% LLM 파싱 + 30% 이력서·현직자 조회 + 20% 현직자 검색** (sleep 0.5초로 CPU 압박 극대화)

#### 실행 명령

```bash
# 모니터링 터미널 먼저 열기
watch -n5 kubectl get hpa -n refit-app
watch -n5 kubectl get pods -n refit-app

# 테스트 실행
cd loadtest
k6 run scripts/6-hpa-validation.js
```

#### 확인할 Grafana 패널 ← **HPA/VPA 검증 핵심**

| 대시보드 | 패널 | 확인 포인트 |
|---------|------|-----------|
| **K8s Views Global** | **Running Pods** | Pod 수 2 → 5 스케일아웃, 감소 후 2로 복귀 확인 |
| **K8s Dashboard 15661** | **Pod Containers CPU Utilization** | 70% 임계값 돌파 타이밍 → HPA 반응 딜레이 측정 |
| **K8s Dashboard 15661** | Pod Containers WSS Memory Usage | **VPA 추천을 위한 실제 메모리 사용량 수집** |
| **K8s Views Global** | Container Restarts by namespace | 스케일링 중 재시작 여부 (0이어야 정상) |
| **Service Performance** | Error Rate (%) | 스케일링 중 서비스 중단 없는지 확인 |

#### 테스트 후 VPA 추천값 확인

```bash
# 테스트 종료 후 VPA 추천값 확인
kubectl describe vpa refit-backend -n refit-app
kubectl describe vpa refit-ai -n refit-app
```

#### 예상 시나리오

1. 램프업 5분 → CPU 서서히 상승
2. 35 VU 도달 후 3분 내 CPU 70% 초과 지속 → HPA 스케일아웃 발동
3. refit-backend: 2 → 3 → (최대 5) pods
4. 스케일아웃 후 CPU가 70% 아래로 내려감 → 안정화
5. 부하 감소 구간 → 5~10분 후 스케일다운 (기본 쿨다운 5분)

---

### 3.7 Self-Healing Test — 파드 자동 복구 검증

#### 목적

- 파드 강제 종료 후 k8s의 자동 재시작(Self-Healing) 동작 확인
- 재시작 중 서비스 중단 없는지 확인 (readinessProbe 기반 트래픽 제어)

#### 실행 명령

```bash
cd loadtest
chmod +x scripts/k8s-self-healing-test.sh
./scripts/k8s-self-healing-test.sh
```

#### 테스트 중 확인할 패널

| 대시보드 | 패널 | 확인 포인트 |
|---------|------|-----------|
| **K8s Views Global** | Container Restarts by namespace | 재시작 카운트 증가 후 0으로 안정화 |
| **K8s Views Global** | Running Pods | 파드 수 일시 감소 후 복귀 |
| **Service Performance** | Error Rate (%) | 재시작 중 사용자 요청 실패율 |

---

## 4. 전체 자동 실행

모든 테스트를 순서대로 자동 실행합니다 (총 약 95분).

```bash
cd loadtest
./run-all-tests.sh
```

> Self-Healing Test는 대화형 확인이 필요하므로 자동 실행에서 제외.
> 별도로 `./scripts/k8s-self-healing-test.sh`를 실행하세요.

### 실행 순서 요약

| 순서 | 스크립트 | 소요시간 | 목적 |
|------|---------|---------|------|
| 1 | 1-baseline.js | 10분 | 기준값 측정 |
| 2 | 2-load-test.js | 7분 | 일반 부하 SLO 검증 |
| 3 | 3-stress-test.js | 28분 | 한계점 탐색 |
| 4 | 4-spike-test.js | 9분 | 급증 대응 검증 |
| 5 | 5-ai-agent-test.js | 10분 | AI SSE 검증 |
| 6 | 6-hpa-validation.js | 22분 | HPA/VPA 검증 |
| — | k8s-self-healing-test.sh | 별도 | Self-Healing 검증 |

---

## 5. 모니터링 대시보드 설명

### Grafana 대시보드 목록

| 대시보드 | 데이터소스 | 주요 용도 |
|---------|---------|---------|
| **Kubernetes Views Global** (ID: 15757) | Prometheus | 클러스터 전체 CPU/RAM/Pod 현황 |
| **K8s Dashboard** (ID: 15661) | Prometheus | 노드·Pod별 상세 리소스 |
| **Re-Fit / Traces / Service Performance** | Tempo | API 레이턴시·에러율·요청량 |
| **Kubernetes Apps Logs** (ID: 18115) | Loki | 백엔드 에러 로그 |
| **Re-Fit / Kafka / MSK** | Prometheus (KMinion) | Kafka 처리량·Lag·DLQ |

### 테스트 목적별 핵심 패널 요약

| 검증 목적 | 대시보드 | 패널 |
|---------|---------|------|
| API 응답성능 | Service Performance | Latency (ms), P95 Latency, Error Rate (%) |
| HPA 스케일링 | K8s Views Global | Running Pods, Container Restarts |
| CPU 임계값 | K8s Dashboard 15661 | Pod Containers CPU Utilization |
| VPA 추천 기반 | K8s Dashboard 15661 | Pod Containers WSS Memory Usage |
| 서비스 장애 감지 | K8s Views Global | OOM Events, Container Restarts |
| Kafka 처리 지연 | Kafka / MSK | Consumer Lag, Produce 레이턴시 |
| 에러 원인 분석 | Kubernetes Apps Logs | 앱 로그 (ERROR 필터) |

---

## 6. SLO 기준

### 일반 API

| 지표 | 목표 |
|------|------|
| P95 응답시간 | < 2,000ms |
| P99 응답시간 | < 3,000ms |
| 에러율 | < 2% |

### LLM 이력서 파싱

| 지표 | 목표 |
|------|------|
| P95 응답시간 | < 7,000ms |
| P99 응답시간 | < 10,000ms |
| 에러율 | < 5% |

### AI 에이전트 SSE

| 지표 | 목표 |
|------|------|
| 세션 생성 P95 | < 3,000ms |
| SSE 전체 응답 P95 | < 30,000ms |
| SSE 전체 응답 P99 | < 45,000ms |
| 성공률 | > 90% |

---

## 7. 테스트 후 정리

### 테스트 데이터 DB 정리

```sql
-- 채팅 메시지 → 채팅방 → 이력서 → 프로필 → 유저 순서로 삭제
DELETE FROM chat_messages
  WHERE chat_room_id IN (
    SELECT id FROM chat_rooms
    WHERE requester_id BETWEEN 5001 AND 5020
       OR receiver_id  BETWEEN 6001 AND 6005
  );

DELETE FROM chat_rooms
  WHERE requester_id BETWEEN 5001 AND 5020
     OR receiver_id  BETWEEN 6001 AND 6005;

DELETE FROM chat_requests
  WHERE requester_id BETWEEN 5001 AND 5020
     OR receiver_id  BETWEEN 6001 AND 6005;

DELETE FROM resumes
  WHERE user_id BETWEEN 5001 AND 5020;

DELETE FROM expert_profiles
  WHERE user_id BETWEEN 6001 AND 6005;

DELETE FROM user_jobs
  WHERE user_id BETWEEN 5001 AND 5020
     OR user_id BETWEEN 6001 AND 6005;

DELETE FROM user_skills
  WHERE user_id BETWEEN 5001 AND 5020
     OR user_id BETWEEN 6001 AND 6005;

DELETE FROM users
  WHERE id BETWEEN 5001 AND 5020
     OR id BETWEEN 6001 AND 6005;
```

### 결과 파일 확인

```bash
ls loadtest/results/
# baseline-summary.json
# load-test-summary.json
# stress-test-summary.json
# ...
```
