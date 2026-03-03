/**
 * Load Test — 실제 트래픽 패턴 시뮬레이션
 *
 * 용도: v1/v2 환경에서 동일 시나리오로 전체 트래픽 처리 성능 비교
 * 실행: k6 run --dns-ttl=0s -e TARGET=v1 scripts/load-test.js
 *       k6 run --dns-ttl=0s -e TARGET=v2 scripts/load-test.js
 */
import { THRESHOLDS, SCENARIO_WEIGHTS } from '../utils/config.js';
import { authMeOnly, authMeUpdateScenario } from '../scenarios/auth.js';
import { expertScenario } from '../scenarios/expert.js';
import { chatRestScenario } from '../scenarios/chat.js';

export const options = {
  stages: [
    { duration: '2m', target: 10 },   // Ramp-up
    { duration: '5m', target: 10 },   // Steady
    { duration: '2m', target: 30 },   // 증가
    { duration: '5m', target: 30 },   // Steady (고부하)
    { duration: '2m', target: 0 },    // Ramp-down
  ],
  thresholds: THRESHOLDS,
};

export default function () {
  const rand = Math.random();
  const { expert, auth, auth_update } = SCENARIO_WEIGHTS;

  if (rand < expert) {
    // 40% — 현직자 검색/조회
    expertScenario();
  } else if (rand < expert + auth) {
    // 20% — 내 정보 조회
    authMeOnly();
  } else if (rand < expert + auth + auth_update) {
    // 15% — 내 정보 수정
    authMeUpdateScenario();
  } else {
    // 25% — 채팅방 목록/메시지 조회
    chatRestScenario();
  }
}
