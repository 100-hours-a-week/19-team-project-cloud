/**
 * 3-stress-test.js
 * 
 * Stress Test: Breaking Point 탐색
 * 
 * 목적:
 *   - 시스템의 한계점(Breaking Point) 찾기
 *   - 어느 지점에서 에러율이 급증하는지 파악
 *   - 병목 지점 식별 (CPU/Memory/DB/AI)
 * 
 * 조건:
 *   - VU: 0 → 20 → 40 → 60 → 80 → 100 → 0
 *   - 각 단계: 4분 (총 28분)
 *   - 60% 일반 API, 40% AI 파싱
 * 
 * Breaking Point 판단 기준:
 *   - 에러율 > 20% (1분 이상 지속)
 *   - P95 > 15초
 *   - 502/504 연속 발생 (30초 이상)
 *   - DB Connection 고갈
 *   - AI 서버 타임아웃 > 50%
 * 
 * 실행:
 *   k6 run scripts/3-stress-test.js
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
    stress_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 20 },   // 0→20 (2분)
        { duration: '2m', target: 20 },   // 20 유지 (2분)
        { duration: '2m', target: 40 },   // 20→40 (2분)
        { duration: '2m', target: 40 },   // 40 유지 (2분)
        { duration: '2m', target: 60 },   // 40→60 (2분)
        { duration: '2m', target: 60 },   // 60 유지 (2분)
        { duration: '2m', target: 80 },   // 60→80 (2분)
        { duration: '2m', target: 80 },   // 80 유지 (2분)
        { duration: '2m', target: 100 },  // 80→100 (2분)
        { duration: '2m', target: 100 },  // 100 유지 (2분)
        { duration: '4m', target: 0 },    // 100→0 (4분, 서서히 감소)
      ],
      gracefulRampDown: '30s',
    },
  },

  thresholds: {
    // 경고 수준 (테스트 중단 안 함)
    'expert_search_duration': [
      { threshold: 'p(95)<3000', abortOnFail: false },
    ],
    'llm_parse_duration': [
      { threshold: 'p(95)<10000', abortOnFail: false },
    ],
    
    // 심각 수준 (테스트 중단)
    'http_req_failed': [
      { threshold: 'rate<0.30', abortOnFail: true },  // 30% 이상 실패 시 중단
    ],
    'llm_parse_success_rate': [
      { threshold: 'rate>0.50', abortOnFail: true },  // 50% 미만 성공 시 중단
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
  const params = Math.random() < 0.5 
    ? Config.SEARCH_PARAMS.groupA 
    : Config.SEARCH_PARAMS.groupB;
  
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

function createChatRoom(token, expertId, resumeId) {
  const body = {
    receiver_id: expertId,
    request_type: Math.random() < 0.5 ? 'FEEDBACK' : 'COFFEE_CHAT',
  };
  
  if (resumeId) body.resume_id = resumeId;

  const res = http.post(
    `${Config.BACKEND_URL}/api/v1/chats`,
    JSON.stringify(body),
    {
      headers: Config.authHeaders(token),
      tags: { name: 'chat_create' },
    }
  );
  
  Config.metrics.chatCreateDuration.add(res.timings.duration);
  check(res, {
    '채팅방 생성': (r) => r.status === 201 || r.status === 409,
  });
  
  return res;
}

// ═════════════════════════════════════════════════════════════════
// 메인 시나리오: 60% 일반 API, 40% AI 파싱
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
  // 40% - AI 파싱 (고부하 시나리오)
  // ─────────────────────────────────────────────────────────────
  if (scenario < 0.4) {
    group('AI 이력서 파싱', () => {
      const presigned = getPresignedUrl(token, `stress_${userId}_${Date.now()}.pdf`);
      if (!presigned) return;

      if (!uploadToS3(presigned.data.presigned_url, resumePDF)) return;

      const s3Url = presigned.data.file_url;
      triggerLLMParsing(token, s3Url);
    });

    sleep(2 + Math.random() * 2);
  } 
  // ─────────────────────────────────────────────────────────────
  // 60% - 일반 API (검색 + 채팅)
  // ─────────────────────────────────────────────────────────────
  else {
    // 1. 현직자 검색
    let expertId = null;
    group('현직자 검색', () => {
      expertId = searchExperts(token);
    });

    sleep(1 + Math.random());

    if (!expertId) return;

    // 2. 채팅방 생성
    group('채팅 생성', () => {
      createChatRoom(token, expertId, null);
    });

    sleep(1.5 + Math.random());

    // 3. 내 이력서 목록 조회
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

    sleep(2 + Math.random() * 2);
  }
}

export function handleSummary(data) {
  Config.printSummary('Stress Test', data);
  
  console.log('🔥 Breaking Point 분석:');
  console.log('');
  
  // VU별 에러율 추이 분석
  const errorRate = (data.metrics.http_req_failed?.values.rate * 100) || 0;
  const llmSuccessRate = (data.metrics.llm_parse_success_rate?.values.rate * 100) || 0;
  const p95Duration = data.metrics.http_req_duration?.values['p(95)'] || 0;
  
  console.log('📊 최종 지표:');
  console.log(`   전체 에러율: ${errorRate.toFixed(2)}%`);
  console.log(`   LLM 성공률: ${llmSuccessRate.toFixed(2)}%`);
  console.log(`   P95 응답시간: ${p95Duration.toFixed(0)}ms`);
  console.log('');
  
  // Breaking Point 판단
  let breakingPoint = '발견되지 않음';
  
  if (errorRate > 20) {
    breakingPoint = '에러율 20% 초과';
  } else if (llmSuccessRate < 50) {
    breakingPoint = 'LLM 성공률 50% 미만';
  } else if (p95Duration > 15000) {
    breakingPoint = 'P95 응답시간 15초 초과';
  }
  
  console.log(`🎯 Breaking Point: ${breakingPoint}`);
  console.log('');
  
  console.log('💡 권장사항:');
  if (errorRate > 10) {
    console.log('   ⚠️  에러율이 높습니다. 다음을 확인하세요:');
    console.log('      - AI 서버 분리 (Runpod/Gemini API)');
    console.log('      - DB Connection Pool 증설');
    console.log('      - 로드밸런서 도입');
  }
  
  if (llmSuccessRate < 80) {
    console.log('   ⚠️  LLM 파싱 성공률이 낮습니다:');
    console.log('      - AI 서버 타임아웃 증가');
    console.log('      - 비동기 처리(Queue) 도입');
    console.log('      - 재시도 로직 강화');
  }
  
  if (p95Duration > 10000) {
    console.log('   ⚠️  응답시간이 느립니다:');
    console.log('      - 캐싱 레이어 추가 (Redis)');
    console.log('      - DB 쿼리 최적화');
    console.log('      - CDN 도입');
  }
  
  console.log('');
  console.log('📌 다음 단계:');
  console.log('   1. Spike Test 실행: npm run test:spike');
  console.log('   2. 개선사항 적용 후 재테스트');
  console.log('');
  
  return {
    './results/stress-test-summary.json': JSON.stringify(data, null, 2),
  };
}