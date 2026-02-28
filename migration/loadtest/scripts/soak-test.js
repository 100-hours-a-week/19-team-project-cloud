/**
 * Soak Test — 마이그레이션 중 에러율/응답시간 검증 (핵심 테스트)
 *
 * ┌──────────────────────────────────────────────────────────────┐
 * │  역할 분리                                                    │
 * │  • k6       → 에러율/응답시간 검증 (v1·v2 어디든 정상 응답?)    │
 * │  • CloudWatch → 트래픽 분배 검증 (v1 vs v2 비율 대시보드)       │
 * └──────────────────────────────────────────────────────────────┘
 *
 * 실행 예시:
 *   # 마이그레이션 병행 (기본 20분, gradual-migration.sh에 맞춤)
 *   K6_WEB_DASHBOARD=true k6 run --dns "ttl=0s" scripts/soak-test.js
 *
 *   # 시간 직접 지정 (분 단위, 예: 30분)
 *   K6_WEB_DASHBOARD=true k6 run --dns "ttl=0s" -e DURATION=30 scripts/soak-test.js
 *
 *   # ALB 직접 타겟 (v2 단독 처리량 검증)
 *   K6_WEB_DASHBOARD=true k6 run -e TARGET=alb scripts/soak-test.js
 *
 * 병행 작업:
 *   터미널 2에서 ./shell/gradual-migration.sh --interval 120
 *
 * VU 50 × 평균 시나리오 소요 ~1s → 약 30~50 RPS
 */
import { sleep } from 'k6';
import { THRESHOLDS } from "../utils/config.js";
import { authMeOnly, authMeUpdateScenario } from "../scenarios/auth.js";
import { resumeListOnly } from "../scenarios/resume.js";
import { expertScenario } from "../scenarios/expert.js";
import { chatRestScenario, chatWebSocketScenario } from "../scenarios/chat.js";

const TARGET = __ENV.TARGET || "v2";

// 마이그레이션 총 시간에 맞춰 동적 조절 (분 단위)
// 기본 20분 = gradual-migration.sh 6단계 × 120초(12분) + 워밍업/쿨다운 2분 + 버퍼 6분
const DURATION_MIN = parseInt(__ENV.DURATION || "20", 10);
const SUSTAIN_MIN = Math.max(DURATION_MIN - 3, 5); // 워밍업1분+증가1분+쿨다운1분 = 3분 제외

export const options = {
  stages: [
    { duration: "1m", target: 20 },               // 워밍업: 0→20 VU
    { duration: "1m", target: 50 },               // 증가: 20→50 VU
    { duration: `${SUSTAIN_MIN}m`, target: 50 },  // 지속 (마이그레이션 전 구간 커버)
    { duration: "30s", target: 20 },              // 감소
    { duration: "30s", target: 0 },               // Ramp-down
  ],
  thresholds: THRESHOLDS,
  // ALB 직접 연결 시 TLS 인증서 호스트명 불일치(*.re-fit.kr vs ALB DNS) 우회
  insecureSkipTLSVerify: TARGET === "alb",
  // Route 53 가중치 기반 DNS 분산이 실제 동작하도록 매 요청마다 새 TCP 연결 강제
  // Keep-Alive가 켜지면 VU가 v1 TCP 연결을 유지 → 가중치 변경에도 v1으로만 요청
  // TARGET=alb는 ALB 직접 접속이므로 재사용해도 무관
  noConnectionReuse: TARGET !== "alb",
};

export default function () {
  const rand = Math.random();

  if (rand < 0.35) {
    // 35% — 현직자 검색/조회 (가장 DB 부하가 큰 시나리오)
    expertScenario();
    sleep(0.5);
  } else if (rand < 0.55) {
    // 20% — 내 정보 조회 + 이력서 목록
    if (Math.random() < 0.5) {
      authMeOnly();
    } else {
      resumeListOnly();
    }
    sleep(0.5);
  } else if (rand < 0.70) {
    // 15% — 내 정보 조회 + 수정 (Write 포함)
    authMeUpdateScenario();
    sleep(0.5);
  } else if (rand < 0.90) {
    // 20% — 채팅 REST (채팅방 목록 + 메시지 조회)
    chatRestScenario();
    sleep(0.5);
  } else {
    // 10% — 채팅 WebSocket (메시지 전송 포함)
    // ALB WebSocket 지원 확인 완료: HTTP/1.1 101 Switching Protocols ✅
    chatWebSocketScenario();
    sleep(0.5);
  }
}
