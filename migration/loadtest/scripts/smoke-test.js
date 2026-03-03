/**
 * Smoke Test — 기본 동작 확인 (최소 부하)
 *
 * 용도: v2 배포 직후, API가 정상 동작하는지 확인
 * 실행: k6 run -e TARGET=v2 scripts/smoke-test.js
 *       k6 run -e TARGET=alb scripts/smoke-test.js  (ALB 직접 접근)
 */
import { THRESHOLDS } from '../utils/config.js';
import { authScenario } from '../scenarios/auth.js';
import { expertScenario } from '../scenarios/expert.js';
import { chatRestScenario } from '../scenarios/chat.js';
import { resumeListOnly } from '../scenarios/resume.js';

export const options = {
  vus: 1,
  duration: '1m',
  thresholds: THRESHOLDS,
};

export default function () {
  authScenario();
  expertScenario();
  chatRestScenario();
  resumeListOnly();
}
