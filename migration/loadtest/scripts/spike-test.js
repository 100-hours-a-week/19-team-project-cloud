/**
 * Spike Test — 순간 트래픽 급증 테스트
 *
 * 시나리오: 평시 부하(10 VU) 유지 중, 1분 이내에 부하를 극한(100~200 VU)으로 급상승
 * 입증 목표:
 *   v1: 특정 RPS에서 에러율(5xx) 치솟고 서비스 불능 상태 돌입 확인
 *   v2: 스파이크 상황에서도 에러율 수렴(목표 0%) 및 지연 시간 방어 확인
 *
 * 실행: k6 run --dns-ttl=0s -e TARGET=v1 scripts/spike-test.js
 *       k6 run --dns-ttl=0s -e TARGET=v2 scripts/spike-test.js
 */
import { SPIKE_THRESHOLDS } from '../utils/config.js';
import { authMeOnly, authMeUpdateScenario } from '../scenarios/auth.js';
import { expertScenario } from '../scenarios/expert.js';
import { chatRestScenario } from '../scenarios/chat.js';

export const options = {
  stages: [
    { duration: '2m', target: 10 },    // 평상시
    { duration: '30s', target: 150 },   // 급증 (30초 이내 폭증)
    { duration: '5m', target: 150 },    // 스파이크 유지
    { duration: '30s', target: 10 },    // 정상화
    { duration: '3m', target: 10 },     // 안정화 관찰
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
