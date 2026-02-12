/**
 * 1-baseline.js
 * 
 * Baseline Test: 정상 상태 성능 측정
 * 
 * 목적:
 *   - 정상 부하에서의 시스템 성능 파악
 *   - SLO 설정을 위한 기준 데이터 수집
 * 
 * 조건:
 *   - VU: 5명 (피크 8명의 60%)
 *   - Duration: 10분
 *   - Threshold: 없음 (측정만)
 * 
 * 실행:
 *   k6 run scripts/1-baseline.js
 *   k6 run --out influxdb=http://localhost:8086/k6db scripts/1-baseline.js
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { vu } from 'k6/execution';
import * as Config from './config.js';

// ─── 테스트 데이터 로드 ───
const users = JSON.parse(open(import.meta.resolve('../data/test-users.json')));

export const options = {
  scenarios: {
    baseline_measurement: {
      executor: 'constant-vus',
      vus: 5,              // 고정 5명
      duration: '10m',     // 10분
    },
  },
  
  // Baseline은 threshold 없음 (측정만)
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
};

export default function() {
  const vuIndex = vu.idInInstance - 1;
  const token = Config.getToken(users, vuIndex);
  
  if (!token) {
    console.error(`VU ${vuIndex}: 토큰 없음`);
    return;
  }
  
  // ═══════════════════════════════════════════════════════════════
  // 시나리오: 일반적인 사용자 행동 패턴
  // ═══════════════════════════════════════════════════════════════
  
  // 1. 현직자 검색 (가장 빈번한 행동)
  group('현직자 검색', () => {
    const res = http.get(
      `${Config.BACKEND_URL}/api/v1/experts?skill_id=1&size=5`,
      {
        headers: Config.authHeaders(token),
        tags: { name: 'expert_search' },
      }
    );
    
    Config.metrics.expertSearchDuration.add(res.timings.duration);
    Config.checkAPIResponse(res, '현직자 검색');
  });
  
  sleep(2 + Math.random() * 2); // 2-4초 사이 랜덤
  
  // 2. 내 이력서 목록 조회
  group('이력서 목록 조회', () => {
    const res = http.get(
      `${Config.BACKEND_URL}/api/v1/resumes`,
      {
        headers: Config.authHeaders(token),
        tags: { name: 'resume_list' },
      }
    );
    
    Config.metrics.resumeListDuration.add(res.timings.duration);
    Config.checkAPIResponse(res, '이력서 목록');
  });
  
  sleep(3 + Math.random() * 2); // 3-5초 사이 랜덤
  
  // 3. 채팅방 목록 조회
  group('채팅방 목록 조회', () => {
    const res = http.get(
      `${Config.BACKEND_URL}/api/v1/chats`,
      {
        headers: Config.authHeaders(token),
        tags: { name: 'chat_list' },
      }
    );
    
    Config.metrics.chatMessagesDuration.add(res.timings.duration);
    Config.checkAPIResponse(res, '채팅방 목록');
  });
  
  sleep(5 + Math.random() * 3); // 5-8초 (다음 행동까지)
}

export function handleSummary(data) {
  Config.printSummary('Baseline Test', data);
  
  console.log('💡 다음 단계:');
  console.log('   1. 위 P95 수치를 기준으로 SLO 설정');
  console.log('   2. scripts/config.js의 SLO 값 업데이트');
  console.log('   3. Load Test 실행: k6 run scripts/2-load-test.js');
  console.log('');
  
  return {
    'stdout': '', // 콘솔 출력은 위에서 함
    './results/baseline-summary.json': JSON.stringify(data, null, 2),
  };
}