/**
 * Soak Test — 장시간 안정성 검증
 *
 * 용도: v1/v2 환경에서 지속적인 부하 하의 안정성 비교
 *
 * 실행 예시:
 *   K6_WEB_DASHBOARD=true k6 run --dns "ttl=0s" -e TARGET=v1 scripts/soak-test.js
 *   K6_WEB_DASHBOARD=true k6 run --dns "ttl=0s" -e TARGET=v2 scripts/soak-test.js
 *
 *   # 시간 직접 지정 (분 단위, 예: 30분)
 *   K6_WEB_DASHBOARD=true k6 run --dns "ttl=0s" -e DURATION=30 scripts/soak-test.js
 *
 * VU 50 × 평균 시나리오 소요 ~1s → 약 30~50 RPS
 */
import { sleep } from 'k6';
import { THRESHOLDS } from "../utils/config.js";
import { authMeOnly, authMeUpdateScenario } from "../scenarios/auth.js";
import { expertScenario } from "../scenarios/expert.js";
import { chatRestScenario, chatWebSocketScenario } from "../scenarios/chat.js";

const TARGET = __ENV.TARGET || "v2";

const DURATION_MIN = parseInt(__ENV.DURATION || "20", 10);
const SUSTAIN_MIN = Math.max(DURATION_MIN - 3, 5);

export const options = {
  stages: [
    { duration: "1m", target: 20 },               // 워밍업: 0→20 VU
    { duration: "1m", target: 50 },               // 증가: 20→50 VU
    { duration: `${SUSTAIN_MIN}m`, target: 50 },  // 지속
    { duration: "30s", target: 20 },              // 감소
    { duration: "30s", target: 0 },               // Ramp-down
  ],
  thresholds: THRESHOLDS,
  insecureSkipTLSVerify: TARGET === "alb",
  noConnectionReuse: TARGET !== "alb",
};

export default function () {
  const rand = Math.random();

  if (rand < 0.40) {
    // 40% — 현직자 검색/조회 (가장 DB 부하가 큰 시나리오)
    expertScenario();
    sleep(0.5);
  } else if (rand < 0.60) {
    // 20% — 내 정보 조회
    authMeOnly();
    sleep(0.5);
  } else if (rand < 0.75) {
    // 15% — 내 정보 수정 (Write 포함)
    authMeUpdateScenario();
    sleep(0.5);
  } else if (rand < 0.90) {
    // 15% — 채팅 REST (채팅방 목록 + 메시지 조회)
    chatRestScenario();
    sleep(0.5);
  } else {
    // 10% — 채팅 WebSocket (메시지 전송 포함)
    chatWebSocketScenario();
    sleep(0.5);
  }
}
