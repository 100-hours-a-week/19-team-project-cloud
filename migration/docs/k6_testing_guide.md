# Re-Fit 마이그레이션 검증: k6 부하 테스트 가이드

## 1. 개요

### 1.1 목적

무중단 마이그레이션 전 과정에서 v2 엔드포인트에 지속적인 합성 트래픽을 발생시켜, 서비스 가용성과 성능을 실시간으로 검증한다.

### 1.2 k6를 선택한 이유

- JavaScript로 시나리오 작성 → 러닝커브가 낮음
- CLI 기반으로 CI/CD 파이프라인에 통합 가능
- 임계값(Thresholds) 기능으로 자동 Pass/Fail 판정
- Prometheus Remote Write를 지원하여 Grafana 대시보드와 연동 가능

### 1.3 설치

```bash
# macOS
brew install k6

# Linux (Debian/Ubuntu)
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6

# Docker
docker run --rm -i grafana/k6 run - < script.js
```

---

## 2. 프로젝트 구조

```
k6-tests/
├── scripts/
│   ├── smoke-test.js          # 기본 동작 확인 (최소 부하)
│   ├── load-test.js           # 일반 부하 테스트
│   ├── soak-test.js           # 장시간 지속 테스트 (마이그레이션 중 사용)
│   └── spike-test.js          # 순간 트래픽 급증 테스트
├── scenarios/
│   ├── auth.js                # 인증 관련 시나리오
│   ├── resume.js              # 이력서 관련 시나리오
│   ├── ai-analysis.js         # AI 분석 시나리오
│   └── matching.js            # 매칭 시나리오
├── utils/
│   ├── config.js              # 환경 설정 (URL, 임계값 등)
│   └── helpers.js             # 공통 유틸리티 함수
└── data/
    └── test-users.json        # 테스트 사용자 데이터
```

---

## 3. 설정 파일

### 3.1 환경 설정 (`utils/config.js`)

```javascript
// 실행 시 환경 변수로 타겟을 전환할 수 있도록 구성
// 사용법: k6 run -e TARGET=v2 scripts/load-test.js

const targets = {
  v1: {
    baseUrl: 'https://refit.com',
    apiUrl: 'https://refit.com/api',  // 전환 전 (상대경로)
  },
  v1_separated: {
    baseUrl: 'https://refit.com',
    apiUrl: 'https://api.refit.com',  // API URL 분리 후
  },
  v2: {
    baseUrl: 'https://refit.com',       // FE 전환 후
    apiUrl: 'https://api.refit.com',    // BE 전환 후
  },
  v2_alb_direct: {
    baseUrl: '',
    apiUrl: 'https://refit-be-alb-xxxx.ap-northeast-2.elb.amazonaws.com',  // ALB 직접 테스트
  },
};

export const ENV = __ENV.TARGET || 'v1';
export const config = targets[ENV];

// SLO 기준 임계값
export const SLO = {
  errorRate: 0.01,          // 1% 이하
  p95ResponseTime: 500,     // 500ms 이하
  p99ResponseTime: 1000,    // 1000ms 이하
  successRate: 0.99,        // 99% 이상
};
```

### 3.2 공통 유틸리티 (`utils/helpers.js`)

```javascript
import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// 커스텀 메트릭 정의
export const errorRate = new Rate('custom_error_rate');
export const apiDuration = new Trend('custom_api_duration');

// 인증 토큰 획득
export function login(apiUrl, email, password) {
  const res = http.post(`${apiUrl}/auth/login`, JSON.stringify({
    email: email,
    password: password,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  const success = check(res, {
    'login: status 200': (r) => r.status === 200,
    'login: has token': (r) => r.json('accessToken') !== undefined,
  });

  errorRate.add(!success);
  apiDuration.add(res.timings.duration);

  if (success) {
    return res.json('accessToken');
  }
  return null;
}

// 인증 헤더 생성
export function authHeaders(token) {
  return {
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
  };
}

// 응답 검증 공통 함수
export function checkResponse(res, name, expectedStatus = 200) {
  const success = check(res, {
    [`${name}: status ${expectedStatus}`]: (r) => r.status === expectedStatus,
    [`${name}: response time < 1s`]: (r) => r.timings.duration < 1000,
  });

  errorRate.add(!success);
  apiDuration.add(res.timings.duration);

  return success;
}
```

### 3.3 테스트 사용자 데이터 (`data/test-users.json`)

```json
[
  { "email": "test01@refit.com", "password": "testpass123!" },
  { "email": "test02@refit.com", "password": "testpass123!" },
  { "email": "test03@refit.com", "password": "testpass123!" },
  { "email": "test04@refit.com", "password": "testpass123!" },
  { "email": "test05@refit.com", "password": "testpass123!" }
]
```

> **참고**: 테스트 전에 v2 환경에 테스트 계정을 미리 생성해두거나, 회원가입 시나리오를 포함해야 한다.

---

## 4. 시나리오별 스크립트

### 4.1 인증 시나리오 (`scenarios/auth.js`)

```javascript
import http from 'k6/http';
import { config } from '../utils/config.js';
import { checkResponse, login } from '../utils/helpers.js';

export function authScenario(testUser) {
  // 1. 로그인
  const token = login(config.apiUrl, testUser.email, testUser.password);
  if (!token) return;

  // 2. 내 정보 조회
  const profileRes = http.get(`${config.apiUrl}/users/me`, {
    headers: { 'Authorization': `Bearer ${token}` },
  });
  checkResponse(profileRes, 'get-profile');
}
```

### 4.2 이력서 시나리오 (`scenarios/resume.js`)

```javascript
import http from 'k6/http';
import { sleep } from 'k6';
import { config } from '../utils/config.js';
import { checkResponse, authHeaders } from '../utils/helpers.js';

export function resumeScenario(token) {
  const headers = authHeaders(token);

  // 1. 이력서 목록 조회
  const listRes = http.get(`${config.apiUrl}/resumes`, headers);
  checkResponse(listRes, 'resume-list');
  sleep(1);

  // 2. 이력서 상세 조회 (목록에서 첫 번째)
  if (listRes.status === 200) {
    const resumes = listRes.json();
    if (resumes && resumes.length > 0) {
      const detailRes = http.get(
        `${config.apiUrl}/resumes/${resumes[0].id}`,
        headers
      );
      checkResponse(detailRes, 'resume-detail');
    }
  }
}
```

### 4.3 AI 분석 시나리오 (`scenarios/ai-analysis.js`)

```javascript
import http from 'k6/http';
import { sleep } from 'k6';
import { config } from '../utils/config.js';
import { checkResponse, authHeaders } from '../utils/helpers.js';

export function aiAnalysisScenario(token, resumeId) {
  const headers = authHeaders(token);

  // 1. AI 분석 요청 (비동기 — 202 Accepted 또는 200 예상)
  const analyzeRes = http.post(
    `${config.apiUrl}/ai/analyze`,
    JSON.stringify({ resumeId: resumeId }),
    headers
  );
  checkResponse(analyzeRes, 'ai-analyze-request', 202);

  // 2. 분석 결과 폴링 (비동기 처리 대기)
  // AI 분석은 시간이 걸리므로 폴링 간격을 두고 확인
  if (analyzeRes.status === 202) {
    const taskId = analyzeRes.json('taskId');
    for (let i = 0; i < 10; i++) {
      sleep(3);
      const statusRes = http.get(
        `${config.apiUrl}/ai/analyze/${taskId}/status`,
        headers
      );

      if (statusRes.status === 200 && statusRes.json('status') === 'completed') {
        checkResponse(statusRes, 'ai-analyze-result');
        break;
      }
    }
  }
}
```

### 4.4 매칭 시나리오 (`scenarios/matching.js`)

```javascript
import http from 'k6/http';
import { config } from '../utils/config.js';
import { checkResponse, authHeaders } from '../utils/helpers.js';

export function matchingScenario(token) {
  const headers = authHeaders(token);

  // 1. 매칭 결과 목록 조회
  const matchesRes = http.get(`${config.apiUrl}/matches`, headers);
  checkResponse(matchesRes, 'matches-list');

  // 2. 매칭 상세 조회
  if (matchesRes.status === 200) {
    const matches = matchesRes.json();
    if (matches && matches.length > 0) {
      const detailRes = http.get(
        `${config.apiUrl}/matches/${matches[0].id}`,
        headers
      );
      checkResponse(detailRes, 'match-detail');
    }
  }
}
```

---

## 5. 테스트 유형별 실행 스크립트

### 5.1 Smoke Test (`scripts/smoke-test.js`)

최소 부하로 기본 동작을 확인한다. v2 배포 직후, 가중치 전환 전에 먼저 실행.

```javascript
import { sleep } from 'k6';
import { config, SLO } from '../utils/config.js';
import { login, errorRate, apiDuration } from '../utils/helpers.js';
import { authScenario } from '../scenarios/auth.js';
import { resumeScenario } from '../scenarios/resume.js';
import { matchingScenario } from '../scenarios/matching.js';

const testUsers = JSON.parse(open('../data/test-users.json'));

export const options = {
  vus: 1,             // 가상 유저 1명
  duration: '1m',     // 1분간 실행
  thresholds: {
    'custom_error_rate': [{ threshold: `rate<${SLO.errorRate}`, abortOnFail: true }],
    'custom_api_duration': [`p(95)<${SLO.p95ResponseTime}`],
    'http_req_failed': ['rate<0.01'],
  },
};

export default function () {
  const user = testUsers[0];
  const token = login(config.apiUrl, user.email, user.password);
  if (!token) return;

  authScenario(user);
  sleep(1);
  resumeScenario(token);
  sleep(1);
  matchingScenario(token);
  sleep(2);
}
```

**실행:**

```bash
k6 run -e TARGET=v2_alb_direct scripts/smoke-test.js
```

### 5.2 Load Test (`scripts/load-test.js`)

일반적인 트래픽 패턴을 시뮬레이션한다. 가중치 전환 중 각 단계에서 실행.

```javascript
import { sleep } from 'k6';
import { config, SLO } from '../utils/config.js';
import { login, errorRate, apiDuration } from '../utils/helpers.js';
import { authScenario } from '../scenarios/auth.js';
import { resumeScenario } from '../scenarios/resume.js';
import { aiAnalysisScenario } from '../scenarios/ai-analysis.js';
import { matchingScenario } from '../scenarios/matching.js';

const testUsers = JSON.parse(open('../data/test-users.json'));

export const options = {
  stages: [
    { duration: '2m', target: 10 },   // 2분간 10명까지 증가 (Ramp-up)
    { duration: '5m', target: 10 },   // 5분간 10명 유지 (Steady)
    { duration: '2m', target: 30 },   // 2분간 30명까지 증가
    { duration: '5m', target: 30 },   // 5분간 30명 유지
    { duration: '2m', target: 0 },    // 2분간 감소 (Ramp-down)
  ],
  thresholds: {
    'custom_error_rate': [`rate<${SLO.errorRate}`],
    'custom_api_duration': [
      `p(95)<${SLO.p95ResponseTime}`,
      `p(99)<${SLO.p99ResponseTime}`,
    ],
    'http_req_failed': ['rate<0.01'],
  },
};

export default function () {
  const user = testUsers[__VU % testUsers.length];
  const token = login(config.apiUrl, user.email, user.password);
  if (!token) return;

  // 실제 사용 패턴을 반영한 가중치 기반 시나리오 선택
  const rand = Math.random();

  if (rand < 0.4) {
    // 40% - 이력서 조회 (가장 빈번한 동작)
    resumeScenario(token);
  } else if (rand < 0.7) {
    // 30% - 매칭 결과 확인
    matchingScenario(token);
  } else if (rand < 0.9) {
    // 20% - 프로필 조회
    authScenario(user);
  } else {
    // 10% - AI 분석 요청 (무거운 작업이라 비율 낮게)
    aiAnalysisScenario(token, 'test-resume-id');
  }

  sleep(1 + Math.random() * 3);  // 1~4초 랜덤 대기 (실제 사용자 행동 모사)
}
```

**실행:**

```bash
k6 run -e TARGET=v2 scripts/load-test.js
```

### 5.3 Soak Test (`scripts/soak-test.js`)

마이그레이션 가중치 전환 중 장시간 지속 실행한다. **이 테스트가 마이그레이션에서 가장 중요하다.**

```javascript
import { sleep } from 'k6';
import { config, SLO } from '../utils/config.js';
import { login, errorRate, apiDuration } from '../utils/helpers.js';
import { authScenario } from '../scenarios/auth.js';
import { resumeScenario } from '../scenarios/resume.js';
import { matchingScenario } from '../scenarios/matching.js';

const testUsers = JSON.parse(open('../data/test-users.json'));

export const options = {
  stages: [
    { duration: '5m', target: 10 },    // Ramp-up
    { duration: '120m', target: 10 },   // 2시간 지속 (가중치 전환 구간)
    { duration: '5m', target: 0 },      // Ramp-down
  ],
  thresholds: {
    'custom_error_rate': [{ threshold: `rate<${SLO.errorRate}`, abortOnFail: true }],
    'custom_api_duration': [
      `p(95)<${SLO.p95ResponseTime}`,
      `p(99)<${SLO.p99ResponseTime}`,
    ],
    'http_req_failed': ['rate<0.01'],
  },
};

export default function () {
  const user = testUsers[__VU % testUsers.length];
  const token = login(config.apiUrl, user.email, user.password);
  if (!token) return;

  const rand = Math.random();

  if (rand < 0.4) {
    resumeScenario(token);
  } else if (rand < 0.7) {
    matchingScenario(token);
  } else {
    authScenario(user);
  }

  sleep(2 + Math.random() * 4);  // 2~6초 대기
}
```

**실행 방법 — 백그라운드에서 실행하면서 별도 터미널에서 가중치 전환을 진행:**

```bash
# 터미널 1: soak test 시작 (Prometheus로 메트릭 전송)
k6 run \
  -e TARGET=v2 \
  -o experimental-prometheus-rw \
  scripts/soak-test.js

# 터미널 2: 가중치 전환 진행 (soak test 지표를 보면서)
# v1=90, v2=10으로 전환
./scripts/switch-weight.sh 90 10

# 지표 안정 확인 후
./scripts/switch-weight.sh 50 50

# 계속 진행...
```

### 5.4 Spike Test (`scripts/spike-test.js`)

v2 전환 완료 후, 채용 시즌 트래픽 급증 상황을 대비해 ASG 스케일링이 정상 동작하는지 확인.

```javascript
import { sleep } from 'k6';
import { config, SLO } from '../utils/config.js';
import { login, errorRate } from '../utils/helpers.js';
import { resumeScenario } from '../scenarios/resume.js';
import { matchingScenario } from '../scenarios/matching.js';

const testUsers = JSON.parse(open('../data/test-users.json'));

export const options = {
  stages: [
    { duration: '2m', target: 10 },    // 평상시
    { duration: '1m', target: 100 },   // 급증 (채용 시즌 시뮬레이션)
    { duration: '5m', target: 100 },   // 급증 유지
    { duration: '1m', target: 10 },    // 정상화
    { duration: '5m', target: 10 },    // 안정화 확인
  ],
  thresholds: {
    'custom_error_rate': [`rate<0.05`],   // 스파이크 시 에러율 5% 이내 허용
    'http_req_failed': ['rate<0.05'],
  },
};

export default function () {
  const user = testUsers[__VU % testUsers.length];
  const token = login(config.apiUrl, user.email, user.password);
  if (!token) return;

  if (Math.random() < 0.5) {
    resumeScenario(token);
  } else {
    matchingScenario(token);
  }

  sleep(1 + Math.random() * 2);
}
```

---

## 6. Grafana 연동

k6의 메트릭을 Prometheus → Grafana로 전송하여 마이그레이션 중 실시간 모니터링.

### 6.1 Prometheus Remote Write 설정

```bash
# K6_PROMETHEUS_RW_SERVER_URL 환경 변수 설정
export K6_PROMETHEUS_RW_SERVER_URL=http://<prometheus-host>:9090/api/v1/write
export K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true

k6 run -o experimental-prometheus-rw scripts/soak-test.js
```

### 6.2 Grafana 대시보드 권장 패널

| 패널 | 쿼리 대상 | 용도 |
|------|-----------|------|
| Request Rate | `rate(k6_http_reqs_total[1m])` | 초당 요청 수 추이 |
| Error Rate | `rate(k6_http_req_failed_total[1m])` | 에러율 실시간 추이 |
| Response Time (p95) | `histogram_quantile(0.95, k6_http_req_duration_seconds)` | 응답 시간 분포 |
| VUs | `k6_vus` | 현재 가상 유저 수 |
| Custom Error Rate | `k6_custom_error_rate` | 시나리오별 에러율 |

> k6 공식 Grafana 대시보드 ID `18030`을 import하면 기본 패널이 자동 구성된다.

---

## 7. 마이그레이션 단계별 활용 가이드

### 7.1 실행 순서

| 마이그레이션 단계 | 테스트 유형 | TARGET | 목적 |
|------------------|-------------|--------|------|
| Phase 2-1: v2 BE 배포 직후 | Smoke Test | `v2_alb_direct` | v2 BE 기본 동작 확인 |
| Phase 2-1: 검증 심화 | Load Test | `v2_alb_direct` | ALB 직접 호출로 v2 성능 확인 |
| Phase 2-3: API URL 분리 직후 | Smoke Test | `v1_separated` | `api.refit.com` → v1 정상 동작 확인 |
| Phase 2-4: 가중치 전환 중 | **Soak Test** | `v2` | **장시간 실행하며 가중치 변경 관찰** |
| Phase 3-2: FE beta 테스트 | Smoke Test | `v2` | FE + BE 통합 동작 확인 |
| Phase 3-3: FE 전환 후 | Load Test | `v2` | 전체 성능 확인 |
| Phase 4: 안정화 기간 | Spike Test | `v2` | ASG 스케일링 검증 |

### 7.2 Soak Test 중 가중치 전환 워크플로우

이것이 실제 무중단 마이그레이션 시 사용하는 핵심 워크플로우다.

```
1. Soak Test 시작 (TARGET=v2, api.refit.com으로 요청)
2. Grafana 대시보드에서 지표 안정 확인
3. 가중치 변경: v1=90, v2=10
4. 최소 15분 관찰 → 에러율, 응답시간 이상 없는지 확인
5. 가중치 변경: v1=50, v2=50
6. 최소 15분 관찰
7. 가중치 변경: v1=10, v2=90
8. 최소 15분 관찰
9. 가중치 변경: v1=0, v2=100
10. 30분 추가 관찰 후 Soak Test 종료
```

**관찰 중 이상 발생 시:**
- 즉시 v1=100, v2=0으로 롤백
- k6 결과에서 에러 발생 시점 확인
- Grafana에서 해당 시점의 서버 메트릭 교차 분석

---

## 8. 가중치 전환 보조 스크립트

### 8.1 전환 스크립트 (`scripts/switch-weight.sh`)

```bash
#!/bin/bash
# 사용법: ./switch-weight.sh <v1_weight> <v2_weight>

V1_WEIGHT=${1:?"v1 가중치를 입력하세요"}
V2_WEIGHT=${2:?"v2 가중치를 입력하세요"}
HOSTED_ZONE_ID="ZXXXXXXXXXXXXX"       # 실제 호스팅 영역 ID로 변경
V1_IP="13.124.xxx.xxx"                # v1 EC2 Elastic IP로 변경
V2_ALB_DNS="refit-be-alb-xxxx.ap-northeast-2.elb.amazonaws.com"  # 실제 ALB DNS로 변경
V2_ALB_HOSTED_ZONE="ZWKZPGTI48KDX"   # ALB의 호스팅 영역 ID (서울 리전 고정값)

echo "=== 가중치 전환: v1=${V1_WEIGHT}, v2=${V2_WEIGHT} ==="
echo "시각: $(date '+%Y-%m-%d %H:%M:%S')"

aws route53 change-resource-record-sets \
  --hosted-zone-id ${HOSTED_ZONE_ID} \
  --change-batch "{
    \"Changes\": [
      {
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"api.refit.com\",
          \"Type\": \"A\",
          \"SetIdentifier\": \"v1-backend\",
          \"Weight\": ${V1_WEIGHT},
          \"TTL\": 60,
          \"ResourceRecords\": [{\"Value\": \"${V1_IP}\"}]
        }
      },
      {
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"api.refit.com\",
          \"Type\": \"A\",
          \"SetIdentifier\": \"v2-backend\",
          \"Weight\": ${V2_WEIGHT},
          \"AliasTarget\": {
            \"HostedZoneId\": \"${V2_ALB_HOSTED_ZONE}\",
            \"DNSName\": \"${V2_ALB_DNS}\",
            \"EvaluateTargetHealth\": true
          }
        }
      }
    ]
  }"

if [ $? -eq 0 ]; then
  echo "전환 성공. TTL 60초 이내에 적용됩니다."
else
  echo "전환 실패! Route 53 설정을 확인하세요."
  exit 1
fi
```

### 8.2 긴급 롤백 스크립트 (`scripts/rollback.sh`)

```bash
#!/bin/bash
# 긴급 롤백: 모든 트래픽을 v1으로 즉시 복귀

echo "!!! 긴급 롤백 실행: 모든 트래픽 → v1 !!!"
./scripts/switch-weight.sh 100 0
echo "롤백 완료. 60초 이내에 적용됩니다."
```

---

## 9. 결과 해석 가이드

### 9.1 k6 출력 해석

```
✓ resume-list: status 200
✓ resume-list: response time < 1s
✗ ai-analyze-request: status 202
  ↳  95% — ✓ 190 / ✗ 10

checks.........................: 98.50% ✓ 1970  ✗ 30
http_req_duration..............: avg=120ms  p(95)=340ms  p(99)=780ms
http_req_failed................: 1.20%  ✓ 24    ✗ 1976
custom_error_rate..............: 1.50%  ✓ 30    ✗ 1970
```

### 9.2 판정 기준

| 지표 | Pass | Warning | Fail (롤백 고려) |
|------|------|---------|-----------------|
| `http_req_failed` | < 1% | 1% ~ 3% | > 3% |
| `http_req_duration p(95)` | < 500ms | 500ms ~ 1000ms | > 1000ms |
| `http_req_duration p(99)` | < 1000ms | 1000ms ~ 2000ms | > 2000ms |
| `custom_error_rate` | < 1% | 1% ~ 3% | > 3% |
| `checks` 통과율 | > 99% | 97% ~ 99% | < 97% |

### 9.3 주의 사항

- **테스트 계정 격리**: 테스트 계정은 실 사용자와 분리하여, 테스트 데이터가 프로덕션 데이터에 영향을 주지 않도록 한다.
- **AI 분석 시나리오 비율**: Runpod API 호출 비용이 발생하므로 Soak Test에서는 AI 시나리오 비율을 낮게 유지하거나 제외한다.
- **요청 비율 조절**: 실제 DAU 대비 과도한 부하를 넣지 않도록 주의한다. 목적은 가용성 검증이지 스트레스 테스트가 아니다.
- **DNS 캐시**: k6는 기본적으로 DNS 결과를 캐시한다. 가중치 전환 테스트 시 `--dns-ttl=0s` 옵션으로 DNS 캐시를 비활성화하면 전환 효과를 즉시 확인할 수 있다.

```bash
k6 run --dns-ttl=0s -e TARGET=v2 scripts/soak-test.js
```

---

## 10. 변경 이력

| 날짜 | 내용 |
|------|------|
| 2026-02-23 | 초안 작성 |