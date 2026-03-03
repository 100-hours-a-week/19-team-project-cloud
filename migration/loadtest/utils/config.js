/**
 * k6 부하테스트 환경 설정
 *
 * 사용법:
 *   k6 run -e TARGET=v2 scripts/smoke-test.js
 *   k6 run -e TARGET=dev scripts/smoke-test.js   (리허설)
 *   k6 run -e TARGET=alb scripts/smoke-test.js
 */

// 환경별 설정
const ENVIRONMENTS = {
  // === Production ===
  v1: {
    api: "https://dev.re-fit.kr",
    fe: "https://dev.re-fit.kr",
    ws: "wss://dev.re-fit.kr/ws",
  },
  v2: {
    api: "https://api.re-fit.kr",
    fe: "https://re-fit.kr",
    ws: "wss://api.re-fit.kr/ws",
  },
  alb: {
    api: "https://<YOUR_ALB_DNS_NAME>",
    fe: "https://re-fit.kr",
    ws: "wss://<YOUR_ALB_DNS_NAME>/ws",
  },

  // === Dev (리허설용) ===
  dev: {
    api: "https://dev.re-fit.kr",
    fe: "https://dev.re-fit.kr",
    ws: "wss://dev.re-fit.kr/ws",
  },
};

// 현재 타겟 결정
const TARGET = __ENV.TARGET || "v2";
const env = ENVIRONMENTS[TARGET] || ENVIRONMENTS.v2;

export const BASE_URL = env.api;
export const FE_BASE_URL = env.fe;
export const WS_BASE_URL = env.ws;

// SLO 임계값
export const THRESHOLDS = {
  http_req_failed: ["rate<0.01"], // 에러율 < 1%
  http_req_duration: ["p(95)<500", "p(99)<1000"],
  checks: ["rate>0.99"], // checks 통과율 > 99%
};

// Spike Test용 완화된 임계값
export const SPIKE_THRESHOLDS = {
  http_req_failed: ["rate<0.05"], // 에러율 < 5%
  http_req_duration: ["p(95)<1000", "p(99)<2000"],
  checks: ["rate>0.97"],
};

// FE Health Test용 임계값
export const FE_THRESHOLDS = {
  http_req_failed: ["rate<0.01"],
  http_req_duration: ["p(95)<2000"],
  checks: ["rate>0.99"],
};

// 시나리오 비율 (Load/Soak Test용)
// 현직자 검색, 내 정보 조회, 내 정보 수정, 채팅
export const SCENARIO_WEIGHTS = {
  expert: 0.4,
  auth: 0.2,
  auth_update: 0.15,
  chat: 0.25,
};

// 검색 키워드 풀
export const SEARCH_KEYWORDS = [
  "백엔드",
  "프론트엔드",
  "데이터",
  "DevOps",
  "AI",
  "클라우드",
];

// 공통 HTTP 파라미터
export const DEFAULT_PARAMS = {
  headers: { "Content-Type": "application/json" },
  timeout: "30s",
};
