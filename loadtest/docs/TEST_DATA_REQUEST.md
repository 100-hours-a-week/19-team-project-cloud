# 부하테스트 데이터 요청 — k8s HPA/VPA/Self-healing 검증용

## 1. 개요

k8s 클러스터의 HPA 스케일링, VPA 추천, Self-healing 동작 검증을 위한 k6 부하테스트에 필요한 테스트 데이터입니다.

- **테스트 대상**: **prod RDS만** (단일 환경)
- **기존 데이터 충돌 방지**: `1001~1010`, `2001~2003`, `3001~3010`, `4001~4003` 범위와 겹치지 않는 `5000`/`6000`번대 사용

---

## 2. 테스트 계정 (총 25개)

### 2.1 JOB\_SEEKER 계정 (20개) — user\_id `5000`번대

| user\_id | nickname | user\_type | career\_level\_id |
|----------|----------|------------|-------------------|
| 5001 | k6seeker01 | JOB\_SEEKER | 1 |
| 5002 | k6seeker02 | JOB\_SEEKER | 1 |
| 5003 | k6seeker03 | JOB\_SEEKER | 2 |
| 5004 | k6seeker04 | JOB\_SEEKER | 2 |
| 5005 | k6seeker05 | JOB\_SEEKER | 3 |
| 5006 | k6seeker06 | JOB\_SEEKER | 3 |
| 5007 | k6seeker07 | JOB\_SEEKER | 1 |
| 5008 | k6seeker08 | JOB\_SEEKER | 1 |
| 5009 | k6seeker09 | JOB\_SEEKER | 2 |
| 5010 | k6seeker10 | JOB\_SEEKER | 2 |
| 5011 | k6seeker11 | JOB\_SEEKER | 1 |
| 5012 | k6seeker12 | JOB\_SEEKER | 3 |
| 5013 | k6seeker13 | JOB\_SEEKER | 1 |
| 5014 | k6seeker14 | JOB\_SEEKER | 2 |
| 5015 | k6seeker15 | JOB\_SEEKER | 1 |
| 5016 | k6seeker16 | JOB\_SEEKER | 3 |
| 5017 | k6seeker17 | JOB\_SEEKER | 1 |
| 5018 | k6seeker18 | JOB\_SEEKER | 2 |
| 5019 | k6seeker19 | JOB\_SEEKER | 1 |
| 5020 | k6seeker20 | JOB\_SEEKER | 2 |

> 스크립트는 `users[vuIndex % users.length]` 방식으로 순환합니다.
> Stress Test 최대 100 VU 실행 시에도 20명이면 충분합니다.

### 2.2 EXPERT 계정 (5개) — user\_id `6000`번대

현직자 검색 API 결과에 반드시 포함될 수 있도록 **직무·스킬·프로필 설정이 필요**합니다.

| user\_id | nickname | user\_type | career\_level\_id | company\_name | UserJob (job\_id) | UserSkill (skill\_id) |
|----------|----------|------------|-------------------|---------------|-------------------|-----------------------|
| 6001 | k6expert01 | EXPERT | 4 | 카카오 | **1** (백엔드) | **1** (Java), 2 (Spring Boot) |
| 6002 | k6expert02 | EXPERT | 5 | 네이버 | **1** (백엔드) | **1** (Java), 3 (JPA) |
| 6003 | k6expert03 | EXPERT | 4 | 라인 | **1** (백엔드) | 2 (Spring Boot), 4 (PostgreSQL) |
| 6004 | k6expert04 | EXPERT | 5 | 쿠팡 | 2 (프론트엔드) | **1** (Java) |
| 6005 | k6expert05 | EXPERT | 3 | 토스 | **1** (백엔드) | 5 (Redis), 6 (Kafka) |

**EXPERT 계정 추가 요청사항:**

- `expert_profiles` 테이블에 `company_name` 포함 레코드 생성 (`verified = false` 가능)
- 테스트 스크립트가 사용하는 검색 파라미터는 아래 두 가지입니다. 두 쿼리 모두 **결과가 1개 이상** 반환되어야 합니다.
  - `GET /api/v1/experts?job_id=1` → **6001, 6002, 6003, 6005** 가 해당
  - `GET /api/v1/experts?skill_id=1` → **6001, 6002, 6004** 가 해당
- 스크립트는 검색 결과의 `experts[0].user_id`를 채팅 상대로 사용합니다.

> 테스트 종료 후 `WHERE user_id BETWEEN 5001 AND 5020 OR user_id BETWEEN 6001 AND 6005` 로 전체 정리 가능합니다.

---

## 3. JWT 토큰 발급 (총 25세트, prod 전용)

| 항목 | 요구사항 |
|------|----------|
| access\_token | 만료 기간 **최소 7일** |
| refresh\_token | 만료 기간 **최소 30일** |
| 알고리즘 | HS256 (`re-fit` issuer) |

### 전달 형식 (JSON)

아래 형식으로 전달해주시면 `data/test-users.json`에 그대로 사용합니다.

```json
[
  { "user_id": 5001, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5002, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5003, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5004, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5005, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5006, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5007, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5008, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5009, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5010, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5011, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5012, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5013, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5014, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5015, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5016, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5017, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5018, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5019, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 5020, "user_type": "JOB_SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 6001, "user_type": "EXPERT", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 6002, "user_type": "EXPERT", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 6003, "user_type": "EXPERT", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 6004, "user_type": "EXPERT", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 6005, "user_type": "EXPERT", "access_token": "eyJ...", "refresh_token": "eyJ..." }
]
```

---

## 4. 채팅방 사전 생성 (권장, 총 10개)

`1-baseline.js`의 채팅방 목록 조회가 의미 있는 데이터를 반환하도록,
그리고 `2-load-test.js` 실행 초반 채팅방 생성 경쟁을 줄이기 위해 사전 생성을 권장합니다.

> 채팅방이 없어도 스크립트는 정상 동작합니다 (`GET /api/v1/chats` 빈 배열 반환, `POST /api/v1/chats` 409 시 기존 방 재사용 처리됨).

| # | JOB\_SEEKER | EXPERT | request\_type | 사전 메시지 |
|---|-------------|--------|---------------|-------------|
| 1 | 5001 | 6001 | FEEDBACK | 2개 |
| 2 | 5002 | 6001 | COFFEE\_CHAT | 2개 |
| 3 | 5003 | 6002 | FEEDBACK | 2개 |
| 4 | 5004 | 6002 | COFFEE\_CHAT | 2개 |
| 5 | 5005 | 6003 | FEEDBACK | 2개 |
| 6 | 5006 | 6003 | COFFEE\_CHAT | 2개 |
| 7 | 5007 | 6004 | FEEDBACK | 2개 |
| 8 | 5008 | 6004 | COFFEE\_CHAT | 2개 |
| 9 | 5009 | 6005 | FEEDBACK | 2개 |
| 10 | 5010 | 6005 | COFFEE\_CHAT | 2개 |

> 각 채팅방에 SEEKER 발신 메시지 2개(내용 임의)를 미리 넣어주세요.

---

## 5. 요약

| 항목 | 수량 | 비고 |
|------|------|------|
| JOB\_SEEKER 계정 | 20개 (5001~5020) | prod RDS |
| EXPERT 계정 | 5개 (6001~6005) | prod RDS, ExpertProfile + 직무·스킬 설정 필요 |
| JWT 토큰 세트 | 25세트 (access + refresh) | prod 전용, access 7일 / refresh 30일 |
| 채팅방 | 10개 (권장) | SEEKER↔EXPERT 1:1, 방당 메시지 2개 |

---

## 6. 테스트 시나리오 및 사용 API

### 시나리오별 비율

| 시나리오 | 비율 | 사용 API |
|---------|------|---------|
| AI 이력서 파싱 | ~35% | `POST /api/v1/uploads/presigned-url` → `PUT {S3 presigned URL}` → `POST /api/v1/resumes/tasks` |
| 현직자 검색 | ~25% | `GET /api/v1/experts?job_id=1`, `GET /api/v1/experts?skill_id=1` |
| 이력서 조회/생성 | ~20% | `GET /api/v1/resumes`, `POST /api/v1/resumes` |
| 채팅 조회/생성 | ~15% | `GET /api/v1/chats`, `POST /api/v1/chats`, `GET /api/v1/chats/{id}/messages`, `GET /api/v1/chats/{id}` |
| 프로필 수정 | ~5% | `PATCH /api/v1/users/me` (nickname 변경) |
| AI 에이전트 채팅 | 별도 (3 VU 고정) | `POST /api/ai/agent/sessions`, `POST /api/ai/agent/reply` (SSE 스트리밍) |

### 테스트별 최대 VU 및 소요시간

| 테스트 스크립트 | 최대 VU | 소요시간 | 주요 시나리오 |
|----------------|---------|---------|--------------|
| 1-baseline | 5 | 10분 | 현직자 검색, 이력서 목록, 채팅 목록 |
| 2-load-test | 25 | 7분 | AI 파싱(12) + 이력서생성(8) + 검색·채팅(5) |
| 3-stress | **100** | 28분 | AI 파싱 40% + 검색·채팅 60% |
| 4-spike | 50 | 9분 | AI 파싱 30% + 이력서생성 30% + 검색 40% |
| 5-ai-agent | 3 | 10분 | AI 에이전트 SSE 채팅 |
| 6-hpa-validation | 35 | 22분 | AI 파싱 50% + 이력서·검색 50% |

> **S3 업로드**: Presigned URL 방식으로 3MB PDF를 직접 S3에 PUT합니다. S3 접근 가능한 환경임을 확인했습니다.

---

## 7. 참고 — DB 정리 쿼리

테스트 완료 후 아래 쿼리로 전체 정리 가능합니다.

```sql
-- 채팅 메시지 → 채팅방 → 채팅 요청 → 이력서 → expert_profiles → user_jobs → user_skills → users 순으로 삭제
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
