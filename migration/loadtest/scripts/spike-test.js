/**
 * Spike Test — 순간 트래픽 급증 테스트
 *
 * 용도: v2 전환 완료 후 ASG 스케일링 검증
 * 실행: k6 run --dns-ttl=0s -e TARGET=v2 scripts/spike-test.js
 */
import { SPIKE_THRESHOLDS } from '../utils/config.js';
import { authMeOnly } from '../scenarios/auth.js';
import { resumeListOnly } from '../scenarios/resume.js';
import { expertScenario } from '../scenarios/expert.js';
import { chatRestScenario } from '../scenarios/chat.js';

export const options = {
  stages: [
    { duration: '2m', target: 10 },    // 평상시
    { duration: '1m', target: 100 },   // 급증
    { duration: '5m', target: 100 },   // 유지
    { duration: '1m', target: 10 },    // 정상화
    { duration: '5m', target: 10 },    // 안정화
  ],
  thresholds: SPIKE_THRESHOLDS,
};

export default function () {
  const rand = Math.random();

  if (rand < 0.40) {
    expertScenario();
  } else if (rand < 0.65) {
    resumeListOnly();
  } else if (rand < 0.85) {
    authMeOnly();
  } else {
    chatRestScenario();
  }
}
