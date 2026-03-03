# 부하테스트 데이터 요청 — v1 vs v2 아키텍처 비교용

## 1. 개요

dev(단일 인스턴스) vs v2 pord(다중 인스턴스) 아키텍처 성능 비교를 위한 k6 부하테스트에 필요한 테스트 데이터입니다.
기존 마이그레이션 테스트 데이터(user_id `1001~1010`, `2001~2003`)와 **겹치지 않는 새 범위**를 사용합니다.

**dev 서버 데이터베이스, prod RDS 모두에 동일한 데이터를 생성해주세요.** (동일 조건에서 비교 테스트를 진행합니다.)

---

## 2. 테스트 계정 (총 13개)

### 2.1 SEEKER 계정 (10개) — user_id `3000`번대

| user_id | nickname     | user_type | 비고 |
|---------|--------------|-----------|------|
| 3001    | k6seeker01   | SEEKER    |      |
| 3002    | k6seeker02   | SEEKER    |      |
| 3003    | k6seeker03   | SEEKER    |      |
| 3004    | k6seeker04   | SEEKER    |      |
| 3005    | k6seeker05   | SEEKER    |      |
| 3006    | k6seeker06   | SEEKER    |      |
| 3007    | k6seeker07   | SEEKER    |      |
| 3008    | k6seeker08   | SEEKER    |      |
| 3009    | k6seeker09   | SEEKER    |      |
| 3010    | k6seeker10   | SEEKER    |      |

### 2.2 EXPERT 계정 (3개) — user_id `4000`번대

| user_id | nickname     | user_type | 비고                       |
|---------|--------------|-----------|----------------------------|
| 4001    | k6expert01   | EXPERT    | 직무/스킬 프로필 설정 필요 |
| 4002    | k6expert02   | EXPERT    | 직무/스킬 프로필 설정 필요 |
| 4003    | k6expert03   | EXPERT    | 직무/스킬 프로필 설정 필요 |

> - SEEKER는 `3000`번대, EXPERT는 `4000`번대로 user_id를 지정하여 기존 테스트 데이터(`1000`/`2000`번대)와 충돌 방지
> - 테스트 후 `WHERE user_id BETWEEN 3001 AND 3010 OR user_id BETWEEN 4001 AND 4003`으로 정리 가능
> - EXPERT 계정은 현직자 검색 API(`GET /api/v1/experts`)에서 조회 가능하도록 직무, 스킬 등 프로필 정보를 설정해주세요

---

## 3. JWT 토큰 발급 (계정당 1세트, 총 13세트)

| 항목          | 요구사항               |
|---------------|------------------------|
| access_token  | 만료 기간 **최소 7일** |
| refresh_token | 만료 기간 **최소 30일** |

### 전달 형식 (JSON)

아래 형식으로 전달해주시면 `test-tokens.json`에 그대로 사용합니다.

```json
[
  { "user_id": 3001, "user_type": "JOB_SEEKER", "access_token": "...", "refresh_token": "..." },
  { "user_id": 3002, "user_type": "JOB_SEEKER", "access_token": "...", "refresh_token": "..." },
  { "user_id": 3003, "user_type": "JOB_SEEKER", "access_token": "...", "refresh_token": "..." },
  { "user_id": 3004, "user_type": "JOB_SEEKER", "access_token": "...", "refresh_token": "..." },
  { "user_id": 3005, "user_type": "JOB_SEEKER", "access_token": "...", "refresh_token": "..." },
  { "user_id": 3006, "user_type": "JOB_SEEKER", "access_token": "...", "refresh_token": "..." },
  { "user_id": 3007, "user_type": "JOB_SEEKER", "access_token": "...", "refresh_token": "..." },
  { "user_id": 3008, "user_type": "JOB_SEEKER", "access_token": "...", "refresh_token": "..." },
  { "user_id": 3009, "user_type": "JOB_SEEKER", "access_token": "...", "refresh_token": "..." },
  { "user_id": 3010, "user_type": "JOB_SEEKER", "access_token": "...", "refresh_token": "..." },
  { "user_id": 4001, "user_type": "EXPERT", "access_token": "...", "refresh_token": "..." },
  { "user_id": 4002, "user_type": "EXPERT", "access_token": "...", "refresh_token": "..." },
  { "user_id": 4003, "user_type": "EXPERT", "access_token": "...", "refresh_token": "..." }
]
```

---

## 4. 채팅방 생성 (총 10개)

각 SEEKER↔EXPERT 간 1:1 채팅방을 사전 생성해주세요.

| 채팅방 # | SEEKER (user_id)       | EXPERT (user_id)       | 테스트 메시지 |
|----------|------------------------|------------------------|---------------|
| 1        | k6seeker01 (3001)  | k6expert01 (4001)  | 1~2개         |
| 2        | k6seeker02 (3002)  | k6expert01 (4001)  | 1~2개         |
| 3        | k6seeker03 (3003)  | k6expert01 (4001)  | 1~2개         |
| 4        | k6seeker04 (3004)  | k6expert02 (4002)  | 1~2개         |
| 5        | k6seeker05 (3005)  | k6expert02 (4002)  | 1~2개         |
| 6        | k6seeker06 (3006)  | k6expert02 (4002)  | 1~2개         |
| 7        | k6seeker07 (3007)  | k6expert03 (4003)  | 1~2개         |
| 8        | k6seeker08 (3008)  | k6expert03 (4003)  | 1~2개         |
| 9        | k6seeker09 (3009)  | k6expert03 (4003)  | 1~2개         |
| 10       | k6seeker10 (3010)  | k6expert03 (4003)  | 1~2개         |

> 각 채팅방에 테스트 메시지를 1~2개 미리 넣어주시면 메시지 조회 시나리오 검증에 도움됩니다.

---

## 5. 요약

| 항목             | 수량                              |
|------------------|-----------------------------------|
| SEEKER 계정      | 10개 (user_id 3001~3010)          |
| EXPERT 계정      | 3개 (user_id 4001~4003)           |
| JWT 토큰 세트    | 13세트 (access + refresh)         |
| 채팅방           | 10개 (SEEKER↔EXPERT 1:1)          |
| 테스트 메시지    | 채팅방당 1~2개                    |
| 생성 위치        | **v1 RDS + v2 RDS 양쪽 모두**     |

---

## 6. 테스트 대상 시나리오

이번 부하테스트에서 사용하는 시나리오는 아래 4가지입니다. (AI 관련 API는 사용하지 않습니다.)

| 시나리오             | 비율 | 사용 API                                  |
|----------------------|------|-------------------------------------------|
| 현직자 검색/조회     | 40%  | `GET /api/v1/experts`, `GET /api/v1/experts/{id}` |
| 채팅 (REST/WS)       | 25%  | `GET /api/v1/chats`, `GET /api/v1/chats/{id}/messages`, WebSocket STOMP |
| 내 정보 조회         | 20%  | `GET /api/v1/users/me`                    |
| 내 정보 수정         | 15%  | `PATCH /api/v1/users/me`                  |

---

## 7. 주의사항

- **기존 데이터와 충돌 방지**: `4001~4003` 범위 사용
- 테스트 계정 nickname에 `k6` prefix를 붙이되, 특수문자 없이 10자 이내로 설정해주세요 (예: `k6seeker01`, `k6expert01`)
- **양쪽 RDS에 동일 데이터 필요**: dev와 v2에서 동일한 시나리오로 비교 테스트하므로, 두 DB 모두에 같은 데이터를 넣어주세요
