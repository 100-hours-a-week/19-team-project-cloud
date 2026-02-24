# Re-Fit k6 부하테스트 구현 플랜

## 1. 개요

### 1.1 목적

무중단 마이그레이션(LB 전환 → DB 이전) 전 과정에서 v2 엔드포인트의 서비스 가용성과 성능을 검증하기 위한 k6 부하테스트 시나리오 및 코드를 작성한다.

### 1.2 핵심 제약 사항

| 항목 | 내용 |
|------|------|
| 인증 방식 | 카카오 OAuth만 지원 → **테스트용 JWT를 사전 발급하여 사용** |
| 채팅 프로토콜 | **WebSocket (STOMP)** — k6의 WebSocket 모듈 활용 |
| 이력서 파싱 | Presigned URL 발급 → S3 업로드 → 파싱 **전체 플로우 테스트** |
| 타겟 도메인 | BE API: `api.re-fit.kr` (4단계 가중치 전환 대상), FE 페이지: `re-fit.kr` (5단계 CloudFront 전환 대상) |

---

## 2. 테스트 대상 도메인과 마이그레이션 단계 매핑

마이그레이션에서 전환되는 도메인이 **두 개**이므로, k6도 두 도메인을 각각 테스트한다.

```
┌─────────────────────────────────────────────────────────────┐
│ LB 마이그레이션 4단계: BE 가중치 전환                          │
│                                                             │
│   k6 → api.re-fit.kr → DNS 가중치 → v1 EC2 또는 v2 ALB     │
│                                                             │
│   가중치가 바뀌면 k6 요청이 자동으로 다른 서버로 감              │
│   (--dns-ttl=0s 옵션으로 DNS 캐시 비활성화)                   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ LB 마이그레이션 5단계: FE 도메인 전환                          │
│                                                             │
│   k6 → re-fit.kr → DNS → v1 EC2(Caddy) 또는 v2 CloudFront  │
│                                                             │
│   DNS를 CloudFront로 변경한 뒤, 페이지 응답이 정상인지 확인     │
└─────────────────────────────────────────────────────────────┘
```

| 단계 | 타겟 도메인 | 테스트 내용 | k6 옵션 |
|------|-----------|-----------|---------|
| 4단계 (BE 전환) | `api.re-fit.kr` | API 에러율, 응답시간 | `--dns-ttl=0s` |
| 5단계 (FE 전환) | `re-fit.kr` | 페이지 HTTP 200, SSR 응답시간 | `--dns-ttl=0s` |
| DB 마이그레이션 | `api.re-fit.kr` | DB 전환 중 API 안정성 | - |

---

## 3. 프로젝트 구조

```
migration/loadtest/
├── scripts/
│   ├── smoke-test.js          # 기본 동작 확인 (최소 부하)
│   ├── load-test.js           # 일반 부하 테스트
│   ├── soak-test.js           # 장시간 지속 테스트 (BE 가중치 전환 중 사용)
│   ├── spike-test.js          # 순간 트래픽 급증 테스트
│   └── fe-health-test.js      # FE 도메인 전환 검증 (5단계)
├── scenarios/
│   ├── auth.js                # 인증 시나리오 (내 정보 조회, 토큰 재발급)
│   ├── resume.js              # 이력서 시나리오 (업로드 → 파싱 → 생성)
│   ├── expert.js              # 현직자 검색/조회 시나리오
│   ├── chat.js                # 채팅 시나리오 (REST + WebSocket STOMP)
│   └── fe-pages.js            # FE 페이지 응답 시나리오 (SSR 확인)
├── utils/
│   ├── config.js              # 환경 설정 (URL, 임계값, 타겟 전환)
│   └── helpers.js             # 공통 유틸리티 (인증 헤더, 응답 검증 등)
├── data/
│   ├── test-tokens.json       # 테스트용 JWT 토큰 (사전 발급)
│   └── dummy_resume.pdf       # 이력서 파싱 테스트용 PDF
└── shell/
    ├── switch-weight.sh       # 가중치 전환 스크립트
    └── rollback.sh            # 긴급 롤백 스크립트
```

---

## 4. 시나리오 상세 설계

### 4.1 인증 시나리오 (`scenarios/auth.js`)

카카오 OAuth 로그인은 브라우저 인터랙션이 필요하므로, **사전 발급된 JWT 토큰**을 사용한다. 인증 시나리오에서는 토큰이 유효한 상태에서의 API 호출을 검증한다.

| 순서 | API | Method | Path | 설명 |
|------|-----|--------|------|------|
| 1 | 내 정보 조회 | `GET` | `/api/v1/users/me` | JWT 토큰으로 인증된 사용자 정보 조회 |
| 2 | 토큰 재발급 | `POST` | `/api/v1/auth/tokens` | Refresh Token으로 Access Token 재발급 |
| 3 | 내 정보 조회 (재검증) | `GET` | `/api/v1/users/me` | 재발급된 토큰으로 재조회 |

**테스트용 JWT 준비 방법:**
- DB에 테스트 계정을 미리 생성
- 백엔드에서 해당 계정의 JWT를 직접 발급 (만료 시간을 충분히 길게 설정)
- `data/test-tokens.json`에 저장하여 k6에서 로드

```json
// data/test-tokens.json 예시
[
  {
    "user_id": 1001,
    "user_type": "JOB_SEEKER",
    "access_token": "eyJ...",
    "refresh_token": "eyJ..."
  },
  {
    "user_id": 1002,
    "user_type": "EXPERT",
    "access_token": "eyJ...",
    "refresh_token": "eyJ..."
  }
]
```

### 4.2 이력서 시나리오 (`scenarios/resume.js`)

Presigned URL 발급 → S3 업로드 → 이력서 파싱 → 이력서 생성의 **전체 플로우**를 테스트한다.

| 순서 | API | Method | Path | 설명 |
|------|-----|--------|------|------|
| 1 | Presigned URL 발급 | `POST` | `/api/v1/uploads/presigned-url` | `target_type`, `file_name`, `file_size` 전송 |
| 2 | S3 업로드 | `PUT` | `{presignedUrl}` | 발급받은 URL로 PDF 파일 업로드 |
| 3 | 이력서 파싱 | `POST` | `/api/v1/resumes/tasks` | `file_url`, `mode` 전송 → AI 파싱 결과 수신 |
| 4 | 이력서 생성 | `POST` | `/api/v1/resumes` | 파싱 결과를 기반으로 이력서 생성 |
| 5 | 이력서 목록 조회 | `GET` | `/api/v1/resumes` | 생성된 이력서 확인 |

**주의사항:**
- 이력서 파싱(Step 3)은 AI 호출이 포함된 동기 API로, 응답 시간이 길 수 있음 (수 초~수십 초)
- Soak Test에서는 AI 파싱 비율을 낮게 유지하여 RunPod 비용 제어
- 테스트용 PDF 파일은 k6 `open()` 함수로 로컬에서 바이너리 로드

### 4.3 현직자 검색/조회 시나리오 (`scenarios/expert.js`)

인증 없이도 접근 가능한 공개 API와, 인증된 상태에서의 상세 조회를 테스트한다.

| 순서 | API | Method | Path | 설명 |
|------|-----|--------|------|------|
| 1 | 현직자 목록 조회 | `GET` | `/api/v1/experts` | 키워드/직무/스킬 필터 검색 |
| 2 | 현직자 상세 조회 | `GET` | `/api/v1/experts/{user_id}` | 목록에서 얻은 ID로 상세 조회 |
| 3 | 현직자 목록 (페이징) | `GET` | `/api/v1/experts?cursor=...` | 커서 기반 페이지네이션 테스트 |

**검색 키워드 예시:** `"백엔드"`, `"프론트엔드"`, `"데이터"`, `"DevOps"` 등을 랜덤 선택

### 4.4 채팅 시나리오 (`scenarios/chat.js`)

REST API로 채팅방 관리를 하고, **WebSocket STOMP**로 실시간 메시지를 전송/수신한다.

#### REST API 부분

| 순서 | API | Method | Path | 설명 |
|------|-----|--------|------|------|
| 1 | 채팅방 목록 조회 | `GET` | `/api/v1/chats` | 내 채팅방 목록 |
| 2 | 채팅방 생성 | `POST` | `/api/v1/chats` | `receiver_id`, `request_type` 전송 |
| 3 | 채팅방 상세 조회 | `GET` | `/api/v1/chats/{chat_id}` | 생성된 채팅방 정보 |
| 4 | 메시지 목록 조회 | `GET` | `/api/v1/chats/{chat_id}/messages` | 이전 메시지 히스토리 |

#### WebSocket STOMP 부분

| 동작 | 프로토콜 | 주소 | 설명 |
|------|---------|------|------|
| 연결 | WebSocket | `wss://api.re-fit.kr/ws` (추정) | STOMP CONNECT |
| 구독 | STOMP | `/queue/chat.{chat_id}` | 채팅방 메시지 수신 |
| 전송 | STOMP | `/app/chat.sendMessage` | 메시지 전송 (`chat_id`, `content`, `message_type`) |

**k6 WebSocket 구현:**
- k6의 `k6/ws` 모듈 사용
- STOMP 프레임을 수동으로 구성하여 전송/수신
- 연결 → 구독 → 메시지 전송 → 수신 확인 → 연결 종료

### 4.5 FE 페이지 응답 시나리오 (`scenarios/fe-pages.js`)

**5단계(FE 도메인 전환)** 시 `re-fit.kr`이 v2 CloudFront(SST/OpenNext)로 정상 전환되었는지 검증한다.

| 순서 | 요청 | Method | URL | 검증 |
|------|-----|--------|-----|------|
| 1 | 메인 페이지 | `GET` | `https://re-fit.kr/` | HTTP 200, HTML 응답 |
| 2 | 로그인 페이지 | `GET` | `https://re-fit.kr/login` | HTTP 200, SSR 렌더링 |
| 3 | 현직자 목록 페이지 | `GET` | `https://re-fit.kr/experts` | HTTP 200, SSR 렌더링 |
| 4 | 정적 리소스 | `GET` | `https://re-fit.kr/_next/...` | HTTP 200, Cache-Control 헤더 |

**검증 포인트:**
- HTTP 상태 코드 200
- 응답에 HTML 콘텐츠가 포함되어 있는지 (`<html`, `<div id`)
- SSR 응답시간이 합리적인지 (p95 < 2000ms)
- CloudFront 전환 후에도 페이지가 깨지지 않는지

**사용 시점:**
- 5단계에서 `re-fit.kr` DNS를 CloudFront로 변경한 직후
- `--dns-ttl=0s` 옵션으로 DNS 전환 효과를 즉시 확인

---

## 5. 테스트 유형별 설정

### 5.1 Smoke Test (`scripts/smoke-test.js`)

v2 배포 직후, 기본 동작을 최소 부하로 확인한다.

```
VUs: 1명
Duration: 1분
시나리오: 인증 → 현직자 검색 → 채팅방 목록 (순차)
목적: "되는가?" 확인
```

### 5.2 Load Test (`scripts/load-test.js`)

실제 트래픽 패턴을 시뮬레이션한다.

```
Stages:
  2분 → 10 VUs (Ramp-up)
  5분 → 10 VUs (Steady)
  2분 → 30 VUs (증가)
  5분 → 30 VUs (Steady)
  2분 → 0 VUs  (Ramp-down)

시나리오 비율:
  40% - 현직자 검색/조회 (가장 빈번)
  25% - 이력서 목록 조회
  20% - 내 정보 조회
  10% - 채팅방 목록/메시지 조회
   5% - 이력서 파싱 (비용 고려하여 낮은 비율)
```

### 5.3 Soak Test (`scripts/soak-test.js`)

**마이그레이션 가중치 전환 중 장시간 실행하는 핵심 테스트.**

```
Stages:
  5분  → 10 VUs (Ramp-up)
  120분 → 10 VUs (2시간 지속 — 가중치 전환 구간)
  5분  → 0 VUs  (Ramp-down)

시나리오 비율:
  40% - 현직자 검색/조회
  30% - 내 정보 조회 + 이력서 목록
  20% - 채팅방 목록/메시지 조회
  10% - 이력서 파싱 (AI 호출 비용 고려)

DNS 캐시: --dns-ttl=0s 옵션 필수
```

### 5.4 Spike Test (`scripts/spike-test.js`)

v2 전환 완료 후, ASG 스케일링 검증을 위한 트래픽 급증 테스트.

```
Stages:
  2분 → 10 VUs  (평상시)
  1분 → 100 VUs (급증)
  5분 → 100 VUs (유지)
  1분 → 10 VUs  (정상화)
  5분 → 10 VUs  (안정화)

에러율 허용: 5% 이내 (스파이크 시)
```

### 5.5 FE Health Test (`scripts/fe-health-test.js`)

**5단계(FE 도메인 전환)** 전용. `re-fit.kr` DNS를 CloudFront로 변경한 직후 실행.

```
VUs: 5명
Duration: 30분
타겟: https://re-fit.kr (FE 페이지)
DNS 캐시: --dns-ttl=0s 필수

시나리오: 주요 페이지 순회
  - 메인 페이지 (/)
  - 로그인 페이지 (/login)
  - 현직자 목록 (/experts)
  - 정적 리소스 확인

검증: HTTP 200, HTML 응답 포함, p95 < 2000ms
```

---

## 6. SLO 임계값 (Thresholds)

| 지표 | Pass | Warning | Fail (롤백 고려) |
|------|------|---------|-----------------|
| API 에러율 (`http_req_failed`) | < 1% | 1% ~ 3% | > 3% |
| p95 응답시간 | < 500ms | 500ms ~ 1000ms | > 1000ms |
| p99 응답시간 | < 1000ms | 1000ms ~ 2000ms | > 2000ms |
| Checks 통과율 | > 99% | 97% ~ 99% | < 97% |

> 이력서 파싱 API는 AI 호출이 포함되어 응답 시간이 길 수 있으므로, 별도 메트릭(`resume_parse_duration`)으로 분리하여 측정한다.

---

## 7. Grafana 연동

k6 메트릭을 Prometheus Remote Write로 전송하여 실시간 모니터링.

```bash
export K6_PROMETHEUS_RW_SERVER_URL=http://<prometheus-host>:9090/api/v1/write
export K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true

k6 run --dns-ttl=0s -o experimental-prometheus-rw -e TARGET=v2 scripts/soak-test.js
```

---

## 8. 구현 순서

### Phase 1: 기반 코드 작성

| 순서 | 작업 | 파일 |
|------|------|------|
| 1-1 | 환경 설정 (URL, 타겟, SLO) | `utils/config.js` |
| 1-2 | 공통 유틸리티 (인증 헤더, 응답 검증, 커스텀 메트릭) | `utils/helpers.js` |
| 1-3 | 테스트 토큰 데이터 구조 | `data/test-tokens.json` |

### Phase 2: 시나리오 구현

| 순서 | 작업 | 파일 | 의존성 |
|------|------|------|--------|
| 2-1 | 인증 시나리오 | `scenarios/auth.js` | helpers.js |
| 2-2 | 이력서 시나리오 (전체 플로우) | `scenarios/resume.js` | helpers.js |
| 2-3 | 현직자 검색/조회 시나리오 | `scenarios/expert.js` | helpers.js |
| 2-4 | 채팅 시나리오 (REST + WebSocket STOMP) | `scenarios/chat.js` | helpers.js |
| 2-5 | FE 페이지 응답 시나리오 | `scenarios/fe-pages.js` | helpers.js |

### Phase 3: 테스트 스크립트 작성

| 순서 | 작업 | 파일 |
|------|------|------|
| 3-1 | Smoke Test | `scripts/smoke-test.js` |
| 3-2 | Load Test | `scripts/load-test.js` |
| 3-3 | Soak Test (마이그레이션 핵심) | `scripts/soak-test.js` |
| 3-4 | Spike Test | `scripts/spike-test.js` |
| 3-5 | FE Health Test (5단계용) | `scripts/fe-health-test.js` |

### Phase 4: 보조 스크립트

| 순서 | 작업 | 파일 |
|------|------|------|
| 4-1 | 가중치 전환 스크립트 | `shell/switch-weight.sh` |
| 4-2 | 긴급 롤백 스크립트 | `shell/rollback.sh` |

---

## 9. 사전 준비 사항 (코드 작성 전 확인 필요)

| 항목 | 상태 | 내용 |
|------|------|------|
| 테스트용 JWT 토큰 발급 | 대기 중 | 코드 구현 완료 후 백엔드 파트에 요청 예정 |
| 테스트용 PDF 파일 | **완료** | `data/dummy_resume.pdf` 준비 완료 |
| WebSocket 엔드포인트 | **확인** | `wss://api.re-fit.kr/ws` |
| Prometheus 서버 URL | 확인 필요 | v2 PLG 스택의 Prometheus Remote Write URL 확인 후 설정 |
| v2 ALB 직접 접근 URL | **확인** | `refit-prod-v2-external-alb-1785900646.ap-northeast-2.elb.amazonaws.com` |

---

## 10. 마이그레이션 단계별 테스트 활용

### 10.1 전체 매핑

| 마이그레이션 단계 | 테스트 유형 | 타겟 도메인 | 목적 |
|------------------|-------------|-----------|------|
| LB 3단계 (FE API 경로 변경) | Smoke Test | `api.re-fit.kr` | API 경로 변경 후 정상 동작 확인 |
| LB 4단계 (BE 가중치 전환 중) | **Soak Test** | `api.re-fit.kr` | 장시간 실행하며 가중치 변경 관찰 |
| LB 4단계 완료 (v2=100%) | Load Test | `api.re-fit.kr` | 전체 트래픽 v2 처리 성능 확인 |
| LB 5단계 (FE 도메인 전환) | **FE Health Test** | `re-fit.kr` | CloudFront 전환 후 페이지 응답 확인 |
| DB Phase 4 (DMS 복제 중) | Soak Test | `api.re-fit.kr` | DB 복제 중 API 성능 영향 관찰 |
| DB Phase 5 (DB 전환 후) | Load + Spike Test | `api.re-fit.kr` | 전환 후 안정성 + ASG 스케일링 검증 |

### 10.2 핵심 워크플로우: BE 가중치 전환 (4단계)

```
터미널 1: k6 Soak Test 시작
  k6 run --dns-ttl=0s -o experimental-prometheus-rw scripts/soak-test.js
  → api.re-fit.kr로 지속 요청, Grafana에서 실시간 모니터링

터미널 2: 가중치 전환 진행
  ./shell/switch-weight.sh 90 10   # 카나리 (30분 관찰)
  ./shell/switch-weight.sh 70 30   # 확대 (30분 관찰)
  ./shell/switch-weight.sh 50 50   # 균등 (30분 관찰)
  ./shell/switch-weight.sh 10 90   # 거의 전환 (30분 관찰)
  ./shell/switch-weight.sh 0 100   # 전환 완료 (1시간 관찰)
```

### 10.3 핵심 워크플로우: FE 도메인 전환 (5단계)

```
1. re-fit.kr DNS를 v2 CloudFront로 변경
2. 즉시 FE Health Test 시작:
   k6 run --dns-ttl=0s scripts/fe-health-test.js
   → re-fit.kr로 페이지 요청, HTTP 200 + HTML 응답 확인
3. 동시에 API Soak Test도 병행:
   k6 run --dns-ttl=0s scripts/soak-test.js
   → api.re-fit.kr API가 FE 전환에 영향받지 않는지 확인
```

---

## 변경 이력

| 날짜 | 내용 |
|------|------|
| 2026-02-24 | 초안 작성 |
| 2026-02-24 | FE 도메인 전환(5단계) 테스트 추가, 타겟 도메인 매핑 섹션 추가 |
