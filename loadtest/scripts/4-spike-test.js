/**
 * 4-spike-test.js
 * 
 * Spike Test: 급증 대응력 테스트
 * 
 * 목적:
 *   - 트래픽 급증 시 시스템 대응 능력 검증
 *   - 갑작스러운 부하 증가에 대한 안정성 확인
 *   - 회복 시간(Recovery Time) 측정
 * 
 * 조건:
 *   - VU: 5 → 50 → 5 (10배 급증)
 *   - 급증: 30초 만에 5→50
 *   - 유지: 2분 30초
 *   - 회복: 30초 만에 50→5
 *   - 관찰: 2분 30초
 * 
 * 관찰 포인트:
 *   - 급증 시 에러율 < 15%
 *   - 회복 시간 < 1분
 *   - 서버 크래시 없음
 *   - AI 파싱 큐 정상 처리
 * 
 * 실행:
 *   k6 run scripts/4-spike-test.js
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { vu } from 'k6/execution';
import * as Config from './config.js';

// ─── 테스트 데이터 로드 ───
const users = JSON.parse(open('../data/test-users.json'));
const resumePDF = open('../data/sample_resume_3mb.pdf', 'b');
const resumePDFSize = resumePDF.byteLength || resumePDF.length || 3145728;

export const options = {
  scenarios: {
    spike_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        // Phase 1: 평상시 (2분)
        { duration: '30s', target: 5 },
        { duration: '1m30s', target: 5 },
        
        // Phase 2: 급증 (30초 만에 10배)
        { duration: '30s', target: 50 },
        
        // Phase 3: 피크 유지 (2분 30초)
        { duration: '2m30s', target: 50 },
        
        // Phase 4: 급감 (30초 만에 복구)
        { duration: '30s', target: 5 },
        
        // Phase 5: 회복 관찰 (2분 30초)
        { duration: '2m30s', target: 5 },
        
        // Phase 6: 종료 (30초)
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },

  thresholds: {
    // 급증 시에도 유지해야 할 최소 기준
    'http_req_failed': [
      { threshold: 'rate<0.15', abortOnFail: false },  // 15% 미만
    ],
    'llm_parse_success_rate': [
      { threshold: 'rate>0.80', abortOnFail: false },  // 80% 이상
    ],
    'expert_search_duration': [
      { threshold: 'p(95)<5000', abortOnFail: false },  // 5초
    ],
    'llm_parse_duration': [
      { threshold: 'p(95)<15000', abortOnFail: false }, // 15초
    ],
  },
};

// ═════════════════════════════════════════════════════════════════
// 헬퍼 함수
// ═════════════════════════════════════════════════════════════════

function getPresignedUrl(token, fileName) {
  const res = http.post(
    `${Config.BACKEND_URL}/api/v1/uploads/presigned-url`,
    JSON.stringify({
      target_type: 'RESUME_PDF',
      file_name: fileName,
      file_size: resumePDFSize,
    }),
    {
      headers: Config.authHeaders(token),
      tags: { name: 'presigned_url' },
    }
  );
  
  if (res.status !== 200) return null;
  return res.json();
}

function uploadToS3(presignedUrl, fileBytes) {
  const res = http.put(presignedUrl, fileBytes, {
    headers: { 'Content-Type': 'application/pdf' },
    tags: { name: 's3_upload' },
  });
  
  if (res.status !== 200) {
    Config.metrics.s3Errors.add(1);
    return false;
  }
  
  return true;
}

function triggerLLMParsing(token, s3FileUrl) {
  const startTime = Date.now();

  const res = http.post(
    `${Config.BACKEND_URL}/api/v2/resumes/tasks`,
    JSON.stringify({
      file_url: s3FileUrl,
    }),
    {
      headers: Config.authHeaders(token),
      tags: { name: 'llm_parse_submit' },
      timeout: '10s',
    }
  );

  // v2 API는 task 생성 성공 시 201 반환
  if (res.status !== 201 && res.status !== 202) {
    Config.metrics.llmParseDuration.add(Date.now() - startTime);
    Config.metrics.llmSuccessRate.add(0);
    Config.metrics.llmErrors.add(1);
    console.error(`⚠️ LLM 파싱 제출 실패 | VU ${__VU} | Status: ${res.status}`);
    return null;
  }

  let taskId;
  try {
    const body = res.json();
    taskId = body.data?.taskId || body.data?.task_id;
  } catch (e) {}

  if (!taskId) {
    Config.metrics.llmParseDuration.add(Date.now() - startTime);
    Config.metrics.llmSuccessRate.add(0);
    Config.metrics.llmErrors.add(1);
    return null;
  }

  sleep(8);
  for (let i = 0; i < 5; i++) {
    const pollRes = http.get(
      `${Config.BACKEND_URL}/api/v2/resumes/tasks/${taskId}`,
      {
        headers: Config.authHeaders(token),
        tags: { name: 'llm_parse_poll' },
      }
    );

    let status;
    try {
      status = pollRes.json().data?.status;
    } catch (e) { continue; }

    if (status === 'COMPLETED') {
      Config.metrics.llmParseDuration.add(Date.now() - startTime);
      Config.metrics.llmSuccessRate.add(1);
      return pollRes;
    }

    if (status === 'FAILED') {
      Config.metrics.llmParseDuration.add(Date.now() - startTime);
      Config.metrics.llmSuccessRate.add(0);
      Config.metrics.llmErrors.add(1);
      return null;
    }

    if (i < 4) sleep(5);
  }

  Config.metrics.llmParseDuration.add(Date.now() - startTime);
  Config.metrics.llmSuccessRate.add(0);
  Config.metrics.llmErrors.add(1);
  console.error(`⚠️ LLM 폴링 타임아웃 | VU ${__VU} | taskId: ${taskId}`);
  return null;
}

function searchExperts(token) {
  // 랜덤하게 다양한 검색 수행
  const searchTypes = [
    Config.SEARCH_PARAMS.groupA,
    Config.SEARCH_PARAMS.groupB,
    Config.SEARCH_PARAMS.groupC,
  ];
  
  const params = searchTypes[Math.floor(Math.random() * searchTypes.length)];
  
  const query = Object.entries(params)
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join('&');

  const res = http.get(
    `${Config.BACKEND_URL}/api/v1/experts?${query}&size=5`,
    {
      headers: Config.authHeaders(token),
      tags: { name: 'expert_search' },
    }
  );
  
  Config.metrics.expertSearchDuration.add(res.timings.duration);
  Config.checkAPIResponse(res, '현직자 검색');

  try {
    const experts = res.json().data.experts;
    if (experts && experts.length > 0) return experts[0].user_id;
  } catch (e) {}
  
  return null;
}

function createManualResume(token, userId) {
  const res = http.post(
    `${Config.BACKEND_URL}/api/v1/resumes`,
    JSON.stringify({
      title: `Spike Test Resume ${userId}_${Date.now()}`,
      is_fresher: Math.random() < 0.5,
      education_level: Config.getEducationLevel(userId),
      content_json: {
        summary: '급증 테스트용 이력서입니다.',
        skills: ['JavaScript', 'React', 'Node.js'],
      },
    }),
    {
      headers: Config.authHeaders(token),
      tags: { name: 'resume_create' },
    }
  );
  
  Config.metrics.resumeCreateDuration.add(res.timings.duration);
  check(res, {
    '이력서 생성': (r) => r.status === 201 || r.status === 409,
  });
  
  return res;
}

// ═════════════════════════════════════════════════════════════════
// 메인 시나리오: 혼합 트래픽
// ═════════════════════════════════════════════════════════════════

export default function() {
  const vuIndex = vu.idInInstance - 1;
  const token = Config.getToken(users, vuIndex);
  const userId = Config.getUserId(users, vuIndex);
  
  if (!token) {
    console.error(`VU ${vuIndex}: 토큰 없음`);
    return;
  }

  const scenario = Math.random();

  // ─────────────────────────────────────────────────────────────
  // 30% - AI 파싱 (가장 무거운 작업)
  // ─────────────────────────────────────────────────────────────
  if (scenario < 0.3) {
    group('AI 파싱', () => {
      const presigned = getPresignedUrl(token, `spike_${userId}_${Date.now()}.pdf`);
      if (!presigned) return;

      if (!uploadToS3(presigned.data.presigned_url, resumePDF)) return;

      triggerLLMParsing(token, presigned.data.file_url);
    });

    sleep(1.5 + Math.random());
  }
  // ─────────────────────────────────────────────────────────────
  // 30% - 수동 이력서 생성 (중간 부하)
  // ─────────────────────────────────────────────────────────────
  else if (scenario < 0.6) {
    group('수동 이력서', () => {
      createManualResume(token, userId);
    });

    sleep(1 + Math.random());
  }
  // ─────────────────────────────────────────────────────────────
  // 40% - 검색만 (가벼운 작업)
  // ─────────────────────────────────────────────────────────────
  else {
    group('현직자 검색', () => {
      searchExperts(token);
    });

    sleep(0.5 + Math.random() * 0.5);

    // 30% 확률로 이력서 목록 조회
    if (Math.random() < 0.3) {
      group('이력서 목록', () => {
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
      
      sleep(1 + Math.random());
    }
  }
}

export function handleSummary(data) {
  Config.printSummary('Spike Test', data);
  
  console.log('⚡ Spike 대응력 분석:');
  console.log('');
  
  const errorRate = (data.metrics.http_req_failed?.values.rate * 100) || 0;
  const llmSuccessRate = (data.metrics.llm_parse_success_rate?.values.rate * 100) || 0;
  const expertP95 = data.metrics.expert_search_duration?.values['p(95)'] || 0;
  const llmP95 = data.metrics.llm_parse_duration?.values['p(95)'] || 0;
  
  console.log('📊 급증 시 성능:');
  console.log(`   에러율: ${errorRate.toFixed(2)}% ${errorRate < 15 ? '✅' : '⚠️'} (목표: <15%)`);
  console.log(`   LLM 성공률: ${llmSuccessRate.toFixed(2)}% ${llmSuccessRate > 80 ? '✅' : '⚠️'} (목표: >80%)`);
  console.log(`   검색 P95: ${expertP95.toFixed(0)}ms ${expertP95 < 5000 ? '✅' : '⚠️'} (목표: <5000ms)`);
  console.log(`   LLM P95: ${llmP95.toFixed(0)}ms ${llmP95 < 15000 ? '✅' : '⚠️'} (목표: <15000ms)`);
  console.log('');
  
  // 회복력 평가
  const recoveryOk = errorRate < 15 && llmSuccessRate > 80;
  
  console.log(`🎯 회복력 평가: ${recoveryOk ? '우수 ✅' : '개선 필요 ⚠️'}`);
  console.log('');
  
  console.log('💡 권장사항:');
  
  if (!recoveryOk) {
    console.log('   ⚠️  급증 대응력이 부족합니다:');
    console.log('      - Auto Scaling 도입 (EC2/ECS)');
    console.log('      - Circuit Breaker 패턴 적용');
    console.log('      - Rate Limiting 설정');
    console.log('      - Queue 기반 비동기 처리');
  } else {
    console.log('   ✅ 급증 대응력이 우수합니다!');
    console.log('      - 현재 아키텍처 유지');
    console.log('      - 모니터링 강화 권장');
  }
  
  console.log('');
  console.log('📌 다음 단계:');
  console.log('   1. 테스트 데이터 정리: npm run cleanup');
  console.log('   2. 전체 결과 분석 및 문서화');
  console.log('   3. 마이그레이션 계획 수립');
  console.log('');
  
  return {
    './results/spike-test-summary.json': JSON.stringify(data, null, 2),
  };
}