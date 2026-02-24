# k6 부하테스트 — 테스트 데이터 생성 요청서

## 1. 개요

마이그레이션 무중단 검증을 위한 k6 부하테스트에 필요한 테스트 데이터입니다.
모든 데이터는 **v1 RDS**에 생성해주세요. (마이그레이션 중 v2도 v1 RDS를 바라보고, DB 전환 시 DMS CDC로 복제됩니다.)

---

## 2. 테스트 계정 (총 13개)

### 2.1 SEEKER 계정 (10개) — user_id `1000`번대

| user_id | nickname | user_type | 비고 |
|---------|----------|-----------|------|
| 1001 | k6-seeker-01 | SEEKER | |
| 1002 | k6-seeker-02 | SEEKER | |
| 1003 | k6-seeker-03 | SEEKER | |
| 1004 | k6-seeker-04 | SEEKER | |
| 1005 | k6-seeker-05 | SEEKER | |
| 1006 | k6-seeker-06 | SEEKER | |
| 1007 | k6-seeker-07 | SEEKER | |
| 1008 | k6-seeker-08 | SEEKER | |
| 1009 | k6-seeker-09 | SEEKER | |
| 1010 | k6-seeker-10 | SEEKER | |

### 2.2 EXPERT 계정 (3개) — user_id `2000`번대

| user_id | nickname | user_type | 비고 |
|---------|----------|-----------|------|
| 2001 | k6-expert-01 | EXPERT | 직무/스킬 프로필 설정 필요 |
| 2002 | k6-expert-02 | EXPERT | 직무/스킬 프로필 설정 필요 |
| 2003 | k6-expert-03 | EXPERT | 직무/스킬 프로필 설정 필요 |

> - SEEKER는 `1000`번대, EXPERT는 `2000`번대로 user_id를 지정하여 테스트 후 데이터 정리 시 범위 기반으로 쉽게 구분/삭제 가능
> - EXPERT 계정은 현직자 검색 API(`GET /api/v1/experts`)에서 조회 가능하도록 직무, 스킬 등 프로필 정보를 설정해주세요

---

## 3. JWT 토큰 발급 (계정당 1세트, 총 13세트)

| 항목 | 요구사항 |
|------|---------|
| access_token | 만료 기간 **최소 7일** |
| refresh_token | 만료 기간 **최소 30일** |

### 전달 형식 (JSON)

아래 형식으로 전달해주시면 `test-tokens.json`에 그대로 사용합니다.

```json
[
  { "user_id": 1001, "user_type": "SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 1002, "user_type": "SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 1003, "user_type": "SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 1004, "user_type": "SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 1005, "user_type": "SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 1006, "user_type": "SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 1007, "user_type": "SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 1008, "user_type": "SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 1009, "user_type": "SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 1010, "user_type": "SEEKER", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 2001, "user_type": "EXPERT", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 2002, "user_type": "EXPERT", "access_token": "eyJ...", "refresh_token": "eyJ..." },
  { "user_id": 2003, "user_type": "EXPERT", "access_token": "eyJ...", "refresh_token": "eyJ..." }
]
```

---

## 4. 채팅방 생성 (총 10개)

각 SEEKER↔EXPERT 간 1:1 채팅방을 사전 생성해주세요.

| 채팅방 # | SEEKER (user_id) | EXPERT (user_id) | 테스트 메시지 |
|----------|-----------------|-----------------|-------------|
| 1 | k6-seeker-01 (1001) | k6-expert-01 (2001) | 1~2개 |
| 2 | k6-seeker-02 (1002) | k6-expert-01 (2001) | 1~2개 |
| 3 | k6-seeker-03 (1003) | k6-expert-01 (2001) | 1~2개 |
| 4 | k6-seeker-04 (1004) | k6-expert-02 (2002) | 1~2개 |
| 5 | k6-seeker-05 (1005) | k6-expert-02 (2002) | 1~2개 |
| 6 | k6-seeker-06 (1006) | k6-expert-02 (2002) | 1~2개 |
| 7 | k6-seeker-07 (1007) | k6-expert-03 (2003) | 1~2개 |
| 8 | k6-seeker-08 (1008) | k6-expert-03 (2003) | 1~2개 |
| 9 | k6-seeker-09 (1009) | k6-expert-03 (2003) | 1~2개 |
| 10 | k6-seeker-10 (1010) | k6-expert-03 (2003) | 1~2개 |

> 각 채팅방에 테스트 메시지를 1~2개 미리 넣어주시면 메시지 조회 시나리오 검증에 도움됩니다.

---

## 5. 요약

| 항목 | 수량 |
|------|------|
| SEEKER 계정 | 10개 |
| EXPERT 계정 | 3개 |
| JWT 토큰 세트 | 13세트 (access + refresh) |
| 채팅방 | 10개 (SEEKER↔EXPERT 1:1) |
| 테스트 메시지 | 채팅방당 1~2개 |
| 생성 위치 | **v1 RDS** |

---

## 6. 주의사항

- **user_id 규칙**: SEEKER는 `1001~1010`, EXPERT는 `2001~2003`으로 고정하여 테스트 후 `WHERE user_id BETWEEN 1001 AND 1010 OR user_id BETWEEN 2001 AND 2003`으로 정리 가능
- 테스트 계정 nickname에 `k6-` prefix를 붙여서 실제 유저와 구분해주세요
- 부하테스트 중 이력서가 계속 생성되므로, **테스트 후 k6- prefix 데이터 정리가 필요**합니다
- JWT 만료 시 재발급이 필요할 수 있으므로, 가능하면 **토큰 발급 방법도 공유**해주세요
