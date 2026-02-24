/**
 * Load Test — 실제 트래픽 패턴 시뮬레이션
 *
 * 용도: v2 전환 완료 후 전체 트래픽 처리 성능 확인
 * 실행: k6 run --dns-ttl=0s -e TARGET=v2 scripts/load-test.js
 */
import { THRESHOLDS, SCENARIO_WEIGHTS } from '../utils/config.js';
import { authMeOnly } from '../scenarios/auth.js';
import { resumeFullScenario, resumeListOnly } from '../scenarios/resume.js';
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

  if (rand < SCENARIO_WEIGHTS.expert) {
    // 40% — 현직자 검색/조회
    expertScenario();
  } else if (rand < SCENARIO_WEIGHTS.expert + SCENARIO_WEIGHTS.resume_list) {
    // 25% — 이력서 목록 조회
    resumeListOnly();
  } else if (rand < SCENARIO_WEIGHTS.expert + SCENARIO_WEIGHTS.resume_list + SCENARIO_WEIGHTS.auth) {
    // 20% — 내 정보 조회
    authMeOnly();
  } else if (rand < SCENARIO_WEIGHTS.expert + SCENARIO_WEIGHTS.resume_list + SCENARIO_WEIGHTS.auth + SCENARIO_WEIGHTS.chat) {
    // 10% — 채팅방 목록/메시지 조회
    chatRestScenario();
  } else {
    // 5% — 이력서 파싱 (AI 호출 비용 고려)
    resumeFullScenario();
  }
}
