/**
 * Stress Test — 시스템 임계점(Breaking Point) 탐색 테스트
 *
 * 시나리오: 부하를 계단식으로 계속 증가시켜 시스템이 완전히 뻗는 임계점을 찾음
 * 입증 목표: v1 vs v2의 최대 수용 처리량(Max Throughput/RPS) 차이 비교
 *           (예: "v1 대비 최대 처리량 ○배 향상")
 *
 * 실행: k6 run --dns-ttl=0s -e TARGET=v1 scripts/stress-test.js
 *       k6 run --dns-ttl=0s -e TARGET=v2 scripts/stress-test.js
 */
import { SPIKE_THRESHOLDS } from '../utils/config.js';
import { authMeOnly, authMeUpdateScenario } from '../scenarios/auth.js';
import { expertScenario } from '../scenarios/expert.js';
import { chatRestScenario } from '../scenarios/chat.js';

export const options = {
  stages: [
    // 계단식 증가 — 공격적으로 부하를 올려 Breaking Point 탐색 (총 ~20분)
    { duration: '1m', target: 100 },    // Step 1: 워밍업
    { duration: '2m', target: 100 },    // 유지
    { duration: '30s', target: 300 },   // Step 2: 중간 부하
    { duration: '2m', target: 300 },    // 유지
    { duration: '30s', target: 600 },   // Step 3: 고부하
    { duration: '2m', target: 600 },    // 유지
    { duration: '30s', target: 1000 },  // Step 4: 극한 부하
    { duration: '2m', target: 1000 },   // 유지
    { duration: '30s', target: 1500 },  // Step 5: Breaking Point 탐색
    { duration: '2m', target: 1500 },   // 유지
    { duration: '30s', target: 2000 },  // Step 6: 최대 부하
    { duration: '2m', target: 2000 },   // 유지
    { duration: '1m', target: 0 },      // Ramp-down
  ],
  thresholds: SPIKE_THRESHOLDS,
};

export default function () {
  const rand = Math.random();

  if (rand < 0.40) {
    // 40% — 현직자 검색/조회 (DB 부하)
    expertScenario();
  } else if (rand < 0.60) {
    // 20% — 내 정보 조회
    authMeOnly();
  } else if (rand < 0.75) {
    // 15% — 내 정보 수정
    authMeUpdateScenario();
  } else {
    // 25% — 채팅 REST
    chatRestScenario();
  }
}
