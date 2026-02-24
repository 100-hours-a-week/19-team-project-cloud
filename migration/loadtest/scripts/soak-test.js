/**
 * Soak Test — 마이그레이션 가중치 전환 중 장시간 실행 (핵심 테스트)
 *
 * 용도: 4단계 BE 가중치 전환 중 api.re-fit.kr로 지속 요청하며 에러율/응답시간 관찰
 * 실행: k6 run --dns-ttl=0s -o experimental-prometheus-rw -e TARGET=v2 scripts/soak-test.js
 *
 * 병행 작업:
 *   터미널 2에서 ./shell/switch-weight.sh 90 10  (v1=90, v2=10)
 *   → 30분 관찰 후 비율 변경 반복
 */
import { THRESHOLDS } from '../utils/config.js';
import { authMeOnly } from '../scenarios/auth.js';
import { resumeFullScenario, resumeListOnly } from '../scenarios/resume.js';
import { expertScenario } from '../scenarios/expert.js';
import { chatRestScenario } from '../scenarios/chat.js';

export const options = {
  stages: [
    { duration: '5m', target: 10 },    // Ramp-up
    { duration: '120m', target: 10 },   // 2시간 지속 (가중치 전환 구간)
    { duration: '5m', target: 0 },      // Ramp-down
  ],
  thresholds: THRESHOLDS,
};

export default function () {
  const rand = Math.random();

  if (rand < 0.40) {
    // 40% — 현직자 검색/조회
    expertScenario();
  } else if (rand < 0.70) {
    // 30% — 내 정보 조회 + 이력서 목록
    if (Math.random() < 0.5) {
      authMeOnly();
    } else {
      resumeListOnly();
    }
  } else if (rand < 0.90) {
    // 20% — 채팅방 목록/메시지 조회
    chatRestScenario();
  } else {
    // 10% — 이력서 파싱 (AI 호출 비용 고려)
    resumeFullScenario();
  }
}
