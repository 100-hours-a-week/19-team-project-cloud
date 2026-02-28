# Re-Fit LB 마이그레이션 리허설 가이드 (dev → v2)

## 이 문서는 무엇인가

실제 운영 마이그레이션(v1 → v2) 전에, dev 서버를 v1 역할로 사용하여 전체 과정을 리허설한다. 리허설을 통해 아래를 사전 검증한다:

- Route 53 가중치 레코드 생성/변경/삭제 절차
- Caddy 도메인 서버 블록 설정
- FE API base URL 변경 시 CORS 동작
- 가중치 전환 중 트래픽 분배 확인
- 롤백 절차 동작 확인
- 전체 소요 시간 측정

### 도메인 매핑

| 역할 | 본 마이그레이션 | 리허설 |
|------|---------------|--------|
| v1 FE + BE (전환 대상) | `re-fit.kr` | `dev.re-fit.kr` |
| v2 BE (ALB) | `api.re-fit.kr` | `api.re-fit.kr` (동일) |
| v2 FE (CloudFront) | `prod-v2.re-fit.kr` | `prod-v2.re-fit.kr` (동일) |

> `api.re-fit.kr`은 현재 v2 ALB를 가리키는 단일 레코드이며, 운영 v1 FE는 상대경로(`/api`)를 사용하고 있어서 이 도메인을 호출하지 않는다. 따라서 리허설에서 `api.re-fit.kr` 레코드를 변경해도 **운영 서비스에 영향 없다.**

### 리허설 전제 조건

- [ ] dev 서버(`dev.re-fit.kr`)가 v1과 유사한 환경 (EC2 + Caddy + Next.js + Spring Boot)
- [ ] dev FE가 현재 상대경로(`/api`)로 API를 호출하고 있음
- [ ] `api.re-fit.kr`이 v2 ALB를 가리키는 단일 Alias 레코드로 존재
- [ ] v2 ALB + ASG + Spring Boot가 정상 동작 중
- [ ] v2 BE가 v1 RDS(또는 dev DB)에 접근 가능

---

## 리허설 전 상태 기록

리허설 후 원복할 때 필요하므로, 현재 상태를 기록해둔다.

### DNS 레코드 백업

```bash
# api.re-fit.kr 현재 레코드 백업
aws route53 list-resource-record-sets \
  --hosted-zone-id Z__________________ \
  --query "ResourceRecordSets[?Name=='api.re-fit.kr.']" \
  > rehearsal-backup-api.json

# dev.re-fit.kr 현재 레코드 백업
aws route53 list-resource-record-sets \
  --hosted-zone-id Z__________________ \
  --query "ResourceRecordSets[?Name=='dev.re-fit.kr.']" \
  > rehearsal-backup-dev.json
```

또는 Route 53 콘솔에서 각 레코드의 현재 설정을 스크린샷으로 저장한다.

### 현재 상태 체크리스트

| 항목 | 현재 값 |
|------|--------|
| `api.re-fit.kr` 레코드 타입 | A (Alias → v2 ALB) |
| `api.re-fit.kr` ALB DNS | `______________________________` |
| `dev.re-fit.kr` 레코드 타입 | ______ |
| `dev.re-fit.kr` 값 (IP 또는 Alias) | `______________________________` |
| dev EC2 Elastic IP | `___.___.___.___ ` |
| dev Spring Boot 포트 | `____` |
| dev Caddyfile 위치 | `____________________` |

### dev Caddyfile 백업

```bash
# dev EC2에서
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup.before-rehearsal
```

### dev FE 현재 API 설정 기록

```
현재 NEXT_PUBLIC_API_URL = ________ (빈 값이면 "미설정"으로 기록)
```

---

## 리허설 실행

### Step 1. CORS 설정 추가

#### dev Spring Boot

dev BE에 CORS 허용 설정을 추가한다:

```
허용 Origin:  https://dev.re-fit.kr, https://prod-v2.re-fit.kr
허용 Methods: GET, POST, PUT, DELETE, OPTIONS
허용 Headers: Content-Type, Authorization
Credentials:  true
```

dev BE를 재시작한다.

#### v2 Spring Boot

v2 BE에도 `dev.re-fit.kr` Origin을 허용에 추가한다 (리허설 동안만 필요):

```
허용 Origin에 추가:  https://dev.re-fit.kr
```

#### 확인

```bash
curl -X OPTIONS https://api.re-fit.kr/auth/login \
  -H "Origin: https://dev.re-fit.kr" \
  -H "Access-Control-Request-Method: POST" \
  -v
```

응답에 `Access-Control-Allow-Origin: https://dev.re-fit.kr`이 포함되어야 한다.

- [ ] dev BE CORS 설정 완료
- [ ] v2 BE CORS 설정 완료
- [ ] preflight 응답 확인

---

### Step 2. dev Caddy에 api.re-fit.kr 서버 블록 추가

dev EC2에 접속하여 Caddyfile에 추가한다:

```
api.re-fit.kr {
    reverse_proxy localhost:{Spring Boot 포트}
}
```

```bash
sudo systemctl reload caddy
```

#### 확인

```bash
# Caddy 상태 확인
sudo systemctl status caddy

# 에러 로그 확인
journalctl -u caddy --since "5 minutes ago" | grep -i error
```

- [ ] Caddy 서버 블록 추가 완료
- [ ] Caddy 리로드 성공, 에러 없음

---

### Step 3. Route 53 TTL 조정

`api.re-fit.kr` 레코드의 TTL을 확인하고, Alias 레코드가 아닌 경우 60초로 변경한다.

> Alias 레코드는 TTL을 직접 설정할 수 없고 대상 리소스의 TTL을 따른다. 이 경우 이 단계는 건너뛴다.

**콘솔:** Route 53 → Hosted zones → `re-fit.kr` → `api.re-fit.kr` 레코드 확인

- [ ] TTL 확인/조정 완료 (또는 Alias라서 건너뜀)

---

### Step 4. Route 53 레코드를 가중치 기반으로 교체

기존 단일 Alias 레코드를 삭제하고, 가중치 레코드 2개를 생성한다.

**방법 1: AWS 콘솔**

1. Route 53 → Hosted zones → `re-fit.kr`
2. 기존 `api.re-fit.kr` A (Alias) 레코드 선택 → **Delete record**
3. **Create record** → v1(dev)용 레코드:
   - Record name: `api`
   - Record type: `A`
   - Routing policy: `Weighted`
   - Value: dev EC2 Elastic IP
   - TTL: `60`
   - Weight: `100`
   - Record ID: `v1-backend`
   - **Create records**
4. **Create record** → v2용 레코드:
   - Record name: `api`
   - Record type: `A`
   - Routing policy: `Weighted`
   - Alias: ON
   - Route traffic to: `Alias to Application and Classic Load Balancer` → `Asia Pacific (Seoul)` → v2 ALB 선택
   - Weight: `0`
   - Record ID: `v2-backend`
   - **Create records**

**방법 2: AWS CLI (원자적 처리)**

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z__________________ \
  --change-batch '{
    "Changes": [
      {
        "Action": "DELETE",
        "ResourceRecordSet": {
          "Name": "api.re-fit.kr",
          "Type": "A",
          "AliasTarget": {
            "HostedZoneId": "ZWKZPGTI48KDX",
            "DNSName": "현재_v2_ALB_DNS",
            "EvaluateTargetHealth": true
          }
        }
      },
      {
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "api.re-fit.kr",
          "Type": "A",
          "SetIdentifier": "v1-backend",
          "Weight": 100,
          "TTL": 60,
          "ResourceRecords": [{"Value": "dev_EC2_ELASTIC_IP"}]
        }
      },
      {
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "api.re-fit.kr",
          "Type": "A",
          "SetIdentifier": "v2-backend",
          "Weight": 0,
          "AliasTarget": {
            "HostedZoneId": "ZWKZPGTI48KDX",
            "DNSName": "v2_ALB_DNS",
            "EvaluateTargetHealth": true
          }
        }
      }
    ]
  }'
```

#### 확인

```bash
dig api.re-fit.kr +short
# dev EC2 IP가 반환되어야 함
```

**콘솔:** Route 53에서 `api.re-fit.kr` 레코드가 2개(v1-backend, v2-backend)로 보이는지 확인

- [ ] 기존 단일 레코드 삭제 확인
- [ ] v1-backend (가중치 100, dev EC2 IP) 생성 확인
- [ ] v2-backend (가중치 0, v2 ALB Alias) 생성 확인
- [ ] DNS 응답이 dev EC2 IP인지 확인

#### Caddy TLS 인증서 확인

Route 53이 dev EC2를 가리키면 Caddy가 `api.re-fit.kr`에 대한 인증서를 자동 발급한다.

```bash
# dev EC2에서
journalctl -u caddy --since "5 minutes ago" | grep -i "certificate"
```

- [ ] 인증서 발급 확인 (1~2분 소요)

---

### Step 5. dev FE API base URL 변경

dev Next.js 코드에서 API base URL을 변경하고 배포한다.

```
변경 전: NEXT_PUBLIC_API_URL=          (빈 값 — 상대경로)
변경 후: NEXT_PUBLIC_API_URL=https://api.re-fit.kr
```

dev 서버에 배포한다.

#### 확인

브라우저에서 `https://dev.re-fit.kr`에 접속하고, 개발자 도구 Network 탭에서 확인한다.

| 확인 항목 | 결과 |
|-----------|------|
| API 요청 URL이 `api.re-fit.kr`으로 가는가 | ☐ Pass / ☐ Fail |
| CORS 에러 없는가 (Console 탭) | ☐ Pass / ☐ Fail |
| 로그인 정상 | ☐ Pass / ☐ Fail |
| 이력서 조회 정상 | ☐ Pass / ☐ Fail |
| AI 분석 요청 정상 | ☐ Pass / ☐ Fail |

- [ ] 모든 기능 정상 동작 확인

---

### Step 6. 가중치 전환 테스트

실제 마이그레이션과 동일하게 단계적으로 진행한다. 리허설이므로 관찰 시간은 짧게 가져간다 (각 단계 5~10분).

#### 6-1. dev=90, v2=10

**콘솔:** v1-backend Weight=`90`, v2-backend Weight=`10`으로 변경
**CLI:** `./scripts/switch-weight.sh 90 10`

```bash
# DNS 분배 확인
for i in $(seq 1 20); do dig api.re-fit.kr +short; done | sort | uniq -c
```

- [ ] dev IP와 v2 ALB IP가 대략 9:1 비율로 반환되는지 확인
- [ ] `dev.re-fit.kr`에서 기능 테스트 — 정상 동작
- [ ] 5분 관찰 후 이상 없음

#### 6-2. dev=50, v2=50

**콘솔:** v1-backend Weight=`50`, v2-backend Weight=`50`
**CLI:** `./scripts/switch-weight.sh 50 50`

- [ ] DNS 분배 확인 (대략 1:1)
- [ ] 기능 테스트 정상
- [ ] 5분 관찰 후 이상 없음

#### 6-3. dev=0, v2=100

**콘솔:** v1-backend Weight=`0`, v2-backend Weight=`100`
**CLI:** `./scripts/switch-weight.sh 0 100`

```bash
dig api.re-fit.kr +short
# v2 ALB IP만 반환되어야 함
```

- [ ] 모든 DNS 응답이 v2 ALB인지 확인
- [ ] `dev.re-fit.kr`에서 기능 테스트 — API가 v2 BE를 통해 정상 동작
- [ ] 5분 관찰 후 이상 없음

---

### Step 7. 롤백 테스트

**리허설에서 가장 중요한 단계.** 실제 마이그레이션에서 롤백이 필요할 때 신속하게 대응할 수 있는지 검증한다.

#### 7-1. BE 롤백: v2=100 → dev=100

**콘솔:** v1-backend Weight=`100`, v2-backend Weight=`0`
**CLI:** `./scripts/switch-weight.sh 100 0`

시작 시각: `__:__:__`

```bash
dig api.re-fit.kr +short
# dev EC2 IP만 반환되어야 함
```

완료 시각: `__:__:__`

- [ ] DNS가 dev IP로 돌아왔는지 확인
- [ ] `dev.re-fit.kr`에서 기능 테스트 정상
- [ ] **소요 시간 기록**: DNS 전환까지 ____초

---

### Step 8. FE 전환 테스트 (선택)

FE 도메인 전환도 리허설하려면, `dev.re-fit.kr`을 v2 CloudFront로 가리키는 테스트를 한다.

#### 8-1. dev.re-fit.kr → v2 CloudFront 전환

**콘솔:**
1. Route 53 → `dev.re-fit.kr` 레코드 **Edit**
2. **Alias** ON → `Alias to CloudFront distribution` → v2 CloudFront 배포 선택
3. **Save**

**CLI:**
```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z__________________ \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "dev.re-fit.kr",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z2FDTNDATAQYW2",
          "DNSName": "d____________.cloudfront.net",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'
```

#### 확인

```bash
dig dev.re-fit.kr +short
# CloudFront IP가 반환되어야 함
```

- [ ] `https://dev.re-fit.kr` 접속 시 v2 FE가 렌더링되는가
- [ ] API 호출이 `api.re-fit.kr` → v2 ALB로 정상 동작하는가

> **주의**: CloudFront에 `dev.re-fit.kr`이 대체 도메인(CNAME)으로 설정되어 있어야 한다. 설정되어 있지 않으면 CloudFront가 요청을 거부한다. 리허설 전에 이 설정을 추가하고, 원복 시 다시 제거한다.

---

### Step 9. 리허설 결과 기록

| 항목 | 결과 | 비고 |
|------|------|------|
| CORS 설정 | ☐ 성공 / ☐ 실패 | |
| Caddy 서버 블록 추가 | ☐ 성공 / ☐ 실패 | |
| Route 53 레코드 교체 | ☐ 성공 / ☐ 실패 | 소요시간: ____분 |
| TLS 인증서 자동 발급 | ☐ 성공 / ☐ 실패 | 소요시간: ____분 |
| FE base URL 변경 | ☐ 성공 / ☐ 실패 | |
| 가중치 전환 (dev→v2) | ☐ 성공 / ☐ 실패 | |
| 롤백 (v2→dev) | ☐ 성공 / ☐ 실패 | DNS 전환 소요: ____초 |
| FE 도메인 전환 | ☐ 성공 / ☐ 실패 / ☐ 미실시 | |

### 발견된 이슈

| # | 이슈 내용 | 영향도 | 본 마이그레이션 전 해결 필요 여부 |
|---|----------|--------|-------------------------------|
| 1 | | | |
| 2 | | | |
| 3 | | | |

---

## 원복 절차

리허설이 끝나면 **모든 것을 원래 상태로** 되돌린다. 아래 순서를 따른다.

> **원복 순서가 중요하다.** FE base URL을 먼저 상대경로로 되돌린 후 DNS를 변경해야, 전환 중 요청이 실패하지 않는다.

### 원복 1. dev FE API base URL 원복

dev Next.js 코드에서 API base URL을 원래대로 되돌리고 배포한다.

```
변경: NEXT_PUBLIC_API_URL=https://api.re-fit.kr
원복: NEXT_PUBLIC_API_URL=          (빈 값 — 상대경로)
```

dev 서버에 배포한다.

#### 확인

브라우저에서 `https://dev.re-fit.kr` 접속 → Network 탭에서 API 요청이 `/api/*` (상대경로)로 가는지 확인한다.

- [ ] API 요청이 상대경로로 복귀
- [ ] 모든 기능 정상 동작

---

### 원복 2. Route 53 api.re-fit.kr 레코드 원복

가중치 레코드 2개를 삭제하고, 원래의 단일 Alias 레코드로 복원한다.

**방법 1: AWS 콘솔**

1. Route 53 → Hosted zones → `re-fit.kr`
2. `api.re-fit.kr`의 v1-backend 레코드 선택 → **Delete record**
3. `api.re-fit.kr`의 v2-backend 레코드 선택 → **Delete record**
4. **Create record**:
   - Record name: `api`
   - Record type: `A`
   - **Alias** ON
   - Route traffic to: `Alias to Application and Classic Load Balancer` → `Asia Pacific (Seoul)` → v2 ALB 선택
   - Routing policy: `Simple routing`
   - **Create records**

**방법 2: AWS CLI (원자적 처리)**

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z__________________ \
  --change-batch '{
    "Changes": [
      {
        "Action": "DELETE",
        "ResourceRecordSet": {
          "Name": "api.re-fit.kr",
          "Type": "A",
          "SetIdentifier": "v1-backend",
          "Weight": 100,
          "TTL": 60,
          "ResourceRecords": [{"Value": "dev_EC2_ELASTIC_IP"}]
        }
      },
      {
        "Action": "DELETE",
        "ResourceRecordSet": {
          "Name": "api.re-fit.kr",
          "Type": "A",
          "SetIdentifier": "v2-backend",
          "Weight": 0,
          "AliasTarget": {
            "HostedZoneId": "ZWKZPGTI48KDX",
            "DNSName": "v2_ALB_DNS",
            "EvaluateTargetHealth": true
          }
        }
      },
      {
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "api.re-fit.kr",
          "Type": "A",
          "AliasTarget": {
            "HostedZoneId": "ZWKZPGTI48KDX",
            "DNSName": "v2_ALB_DNS",
            "EvaluateTargetHealth": true
          }
        }
      }
    ]
  }'
```

> **주의**: DELETE할 때의 레코드 내용(Weight, TTL, Value 등)이 실제 현재 상태와 정확히 일치해야 한다. 가중치 전환 중에 값을 바꿨다면 마지막으로 설정한 값을 사용한다. 확실하지 않으면 콘솔에서 삭제하는 것이 안전하다.

#### 확인

```bash
dig api.re-fit.kr +short
# v2 ALB IP가 반환되어야 함

aws route53 list-resource-record-sets \
  --hosted-zone-id Z__________________ \
  --query "ResourceRecordSets[?Name=='api.re-fit.kr.']"
# 단일 Alias 레코드 1개만 존재해야 함
```

또는 Route 53 콘솔에서 `api.re-fit.kr`이 가중치 레코드 없이 단일 레코드로 보이는지 확인한다.

- [ ] 가중치 레코드 2개 삭제 확인
- [ ] 단일 Alias 레코드 복원 확인
- [ ] DNS 응답이 v2 ALB인지 확인

---

### 원복 3. dev.re-fit.kr 레코드 원복 (Step 8을 실행한 경우만)

Step 8에서 `dev.re-fit.kr`을 CloudFront로 변경한 경우, 원래 값으로 되돌린다.

**콘솔:**
1. Route 53 → `dev.re-fit.kr` 레코드 **Edit**
2. 리허설 전 백업한 원래 설정으로 되돌린다 (IP 또는 Alias)
3. **Save**

**CLI (예시 — 원래가 IP 레코드인 경우):**

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z__________________ \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "dev.re-fit.kr",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "dev_EC2_ELASTIC_IP"}]
      }
    }]
  }'
```

> 원래 값은 리허설 전에 백업한 `rehearsal-backup-dev.json` 파일 또는 스크린샷을 참조한다.

#### 확인

```bash
dig dev.re-fit.kr +short
# dev EC2 IP가 반환되어야 함
```

- [ ] `dev.re-fit.kr`이 dev EC2를 가리키는지 확인
- [ ] `https://dev.re-fit.kr` 접속 시 dev FE가 정상 렌더링되는지 확인

---

### 원복 4. dev Caddy 원복

dev EC2에서 리허설용으로 추가한 `api.re-fit.kr` 서버 블록을 제거한다.

```bash
# dev EC2에서
# 백업에서 복원
cp /etc/caddy/Caddyfile.backup.before-rehearsal /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

또는 수동으로 Caddyfile에서 `api.re-fit.kr { ... }` 블록을 삭제한 후 리로드한다.

#### 확인

```bash
sudo systemctl status caddy
# active (running) 상태 확인

journalctl -u caddy --since "5 minutes ago" | grep -i error
# 에러 없음 확인
```

- [ ] Caddy 원복 완료, 에러 없음

---

### 원복 5. CORS 설정 원복

#### v2 Spring Boot

리허설용으로 추가한 `https://dev.re-fit.kr` Origin 허용을 제거한다.

> 본 마이그레이션 때는 `https://re-fit.kr`로 다시 추가할 예정이므로, 리허설용 설정만 제거하면 된다.

#### dev Spring Boot

리허설용으로 추가한 CORS 설정을 제거한다. (또는 본 마이그레이션 전까지 남겨둬도 무방)

- [ ] v2 BE에서 dev.re-fit.kr CORS 허용 제거
- [ ] dev BE CORS 원복

---

### 원복 6. CloudFront 대체 도메인 제거 (Step 8을 실행한 경우만)

Step 8에서 CloudFront에 `dev.re-fit.kr`을 대체 도메인(CNAME)으로 추가한 경우:

**콘솔:**
1. [CloudFront 콘솔](https://console.aws.amazon.com/cloudfront/) → 해당 배포 선택
2. **General** 탭 → **Settings** → **Edit**
3. **Alternate domain name (CNAME)** 에서 `dev.re-fit.kr` 제거
4. **Save changes**

- [ ] CloudFront 대체 도메인 제거 완료

---

## 원복 완료 확인 체크리스트

모든 원복이 끝난 후, 아래를 최종 확인한다.

| 항목 | 확인 방법 | 결과 |
|------|----------|------|
| `api.re-fit.kr` → v2 ALB (단일 레코드) | `dig api.re-fit.kr +short` 또는 Route 53 콘솔 | ☐ 확인 |
| `dev.re-fit.kr` → dev EC2 | `dig dev.re-fit.kr +short` 또는 Route 53 콘솔 | ☐ 확인 |
| dev FE가 상대경로 사용 | 브라우저 Network 탭에서 `/api/*`로 요청 | ☐ 확인 |
| dev Caddy에 `api.re-fit.kr` 블록 없음 | Caddyfile 확인 | ☐ 확인 |
| v2 BE CORS에 `dev.re-fit.kr` 없음 | 설정 파일 확인 | ☐ 확인 |
| `re-fit.kr` (운영) 정상 동작 | 브라우저 접속 확인 | ☐ 확인 |
| CloudFront에 `dev.re-fit.kr` CNAME 없음 | CloudFront 콘솔 확인 (Step 8 실행 시만) | ☐ 확인 / ☐ 해당없음 |

**원복 완료 시각**: `____년 __월 __일 __:__`

---

## 리허설에서 본 마이그레이션으로의 차이점

리허설이 끝나면, 본 마이그레이션에서 달라지는 점을 정리해둔다.

| 항목 | 리허설 | 본 마이그레이션 |
|------|--------|---------------|
| v1 역할 서버 | dev EC2 (`dev.re-fit.kr`) | 운영 EC2 (`re-fit.kr`) |
| Caddy 설정 대상 | dev EC2 | 운영 EC2 |
| FE base URL 변경 대상 | dev Next.js | 운영 Next.js |
| CORS Origin | `dev.re-fit.kr` | `re-fit.kr` |
| 가중치 레코드 v1 IP | dev EC2 Elastic IP | 운영 EC2 Elastic IP |
| 관찰 시간 | 5~10분/단계 | 30분~/단계 |
| FE 전환 도메인 | `dev.re-fit.kr` → CloudFront | `re-fit.kr` → CloudFront |
| DB 상태 | dev DB 사용 | v1 RDS 공유 전략 적용 |

---

## 변경 이력

| 날짜 | 내용 |
|------|------|
| 2026-02-23 | 초안 작성 |