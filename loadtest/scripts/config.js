/**
 * config.js
 * 
 * 모든 테스트 스크립트에서 공유하는 설정 및 헬퍼 함수
 * 
 * 사용법:
 *   import * as Config from './config.js';
 */

import { check } from 'k6';
import { Trend, Counter, Rate } from 'k6/metrics';

// ════════════════════════════════════════════════════════════════════
// 🌍 환경 설정
// ════════════════════════════════════════════════════════════════════

export const BACKEND_URL = __ENV.BACKEND_URL || 'https://dev.re-fit.kr';

// ════════════════════════════════════════════════════════════════════
// 📊 Custom Metrics (모든 테스트에서 공통 사용)
// ════════════════════════════════════════════════════════════════════

export const metrics = {
  // API별 응답시간
  expertSearchDuration: new Trend('expert_search_duration'),
  resumeListDuration: new Trend('resume_list_duration'),
  resumeCreateDuration: new Trend('resume_create_duration'),
  llmParseDuration: new Trend('llm_parse_duration'),
  chatCreateDuration: new Trend('chat_create_duration'),
  chatMessagesDuration: new Trend('chat_messages_duration'),
  
  // 에러 추적
  apiErrors: new Counter('api_errors'),
  llmErrors: new Counter('llm_parse_errors'),
  s3Errors: new Counter('s3_upload_errors'),
  
  // 성공률
  llmSuccessRate: new Rate('llm_parse_success_rate'),
  apiSuccessRate: new Rate('api_success_rate'),
};

// ════════════════════════════════════════════════════════════════════
// 🔧 공통 헬퍼 함수
// ════════════════════════════════════════════════════════════════════

/**
 * VU 인덱스에 맞는 토큰 반환
 */
export function getToken(users, vuIndex) {
  const idx = vuIndex % users.length;
  if (!users[idx]) {
    console.error(`❌ User not found at index ${idx}`);
    return '';
  }
  return users[idx].token;
}

/**
 * VU 인덱스에 맞는 유저 ID 반환
 */
export function getUserId(users, vuIndex) {
  const idx = vuIndex % users.length;
  if (!users[idx]) return 1;
  return users[idx].user_id;
}

/**
 * 인증 헤더 생성
 */
export function authHeaders(token) {
  return {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
  };
}

/**
 * 학력 수준 반환 (순환)
 */
const EDUCATION_LEVELS = [
  '고등학교 졸업',
  '2년제 재학/휴학',
  '2년제 졸업',
  '4년제 재학/휴학',
  '4년제 졸업',
];

export function getEducationLevel(userId) {
  return EDUCATION_LEVELS[userId % EDUCATION_LEVELS.length];
}

/**
 * 현직자 검색 파라미터 (API: /api/v1/experts)
 * - job_id: jobs.id (user_jobs 테이블 FK)
 * - skill_id: skills.id (user_skills 테이블 FK)
 * - career_level: career_levels.id (users.career_level_id)
 * - keyword: nickname/introduction 검색
 */
export const SEARCH_PARAMS = {
  groupA: { job_id: 1 },              // jobs.id=1: 백엔드 개발자
  groupB: { skill_id: 1 },            // skills.id=1: Java
  groupC: { skill_id: 1 },           // skills.id=1: Java (keyword=개발은 400 발생)
  groupD: { career_level: 1 },        // career_levels.id=1: 신입 (선택)
};

// ════════════════════════════════════════════════════════════════════
// 📈 SLO 기준 (Baseline 테스트 후 수정 예정)
// ════════════════════════════════════════════════════════════════════

export const SLO = {
  // 일반 API
  normalAPI: {
    p95: 2000,    // 2초
    p99: 3000,    // 3초
    errorRate: 0.02,  // 2%
  },
  
  // LLM 파싱
  llmParsing: {
    p95: 7000,    // 7초
    p99: 10000,   // 10초
    errorRate: 0.05,  // 5%
  },
  
  // 파일 업로드
  fileUpload: {
    p95: 5000,    // 5초
    errorRate: 0.01,  // 1%
  },
};

// ════════════════════════════════════════════════════════════════════
// ✅ 공통 Check 함수
// ════════════════════════════════════════════════════════════════════

/**
 * API 응답 검증
 */
export function checkAPIResponse(res, apiName, expectedStatus = 200) {
  const success = check(res, {
    [`${apiName} - 상태코드 ${expectedStatus}`]: (r) => r.status === expectedStatus,
    [`${apiName} - 응답시간 < 3초`]: (r) => r.timings.duration < 3000,
  });
  
  if (!success) {
    metrics.apiErrors.add(1);
    console.error(`❌ ${apiName} 실패 | VU ${__VU} | Status: ${res.status}`);
  }
  
  metrics.apiSuccessRate.add(success);
  return success;
}

/**
 * LLM 파싱 응답 검증
 */
export function checkLLMResponse(res) {
  const success = check(res, {
    'LLM 파싱 - 응답 정상': (r) => r.status === 200 || r.status === 500,
    'LLM 파싱 - 응답시간 < 30초': (r) => r.timings.duration < 30000,
  });
  
  if (res.status === 200) {
    metrics.llmSuccessRate.add(1);
  } else {
    metrics.llmSuccessRate.add(0);
    metrics.llmErrors.add(1);
    console.error(`⚠️ LLM 파싱 실패 | VU ${__VU} | Status: ${res.status}`);
  }
  
  return success;
}

// ════════════════════════════════════════════════════════════════════
// 📊 Summary 헬퍼
// ════════════════════════════════════════════════════════════════════

/**
 * 테스트 결과 요약 출력
 */
export function printSummary(testName, data) {
  console.log('');
  console.log('═══════════════════════════════════════════');
  console.log(`📊 ${testName} - Summary`);
  console.log('═══════════════════════════════════════════');
  console.log('');
  
  // 기본 정보
  console.log('🎯 테스트 정보:');
  console.log(`   환경: ${BACKEND_URL}`);
  console.log(`   기간: ${formatDuration(data.state.testRunDurationMs)}`);
  console.log('');
  
  // 요청 통계
  const totalReqs = data.metrics.http_reqs.values.count;
  const failedReqs = data.metrics.http_req_failed ? 
    (data.metrics.http_req_failed.values.rate * totalReqs) : 0;
  const errorRate = ((failedReqs / totalReqs) * 100).toFixed(2);
  
  console.log('📈 전체 통계:');
  console.log(`   총 요청: ${totalReqs.toFixed(0)}개`);
  console.log(`   성공: ${(totalReqs - failedReqs).toFixed(0)}개`);
  console.log(`   실패: ${failedReqs.toFixed(0)}개`);
  console.log(`   에러율: ${errorRate}% ${getStatusEmoji(errorRate, 2)}`);
  console.log('');
  
  // API별 응답시간
  console.log('⏱️  API 응답시간:');
  printMetric(data, 'expert_search_duration', '현직자 검색');
  printMetric(data, 'resume_list_duration', '이력서 목록');
  printMetric(data, 'llm_parse_duration', 'LLM 파싱');
  printMetric(data, 'chat_create_duration', '채팅방 생성');
  console.log('');
  
  // 성공률
  if (data.metrics.llm_parse_success_rate) {
    const llmSuccess = (data.metrics.llm_parse_success_rate.values.rate * 100).toFixed(1);
    console.log('✅ 성공률:');
    console.log(`   LLM 파싱: ${llmSuccess}% ${getStatusEmoji(llmSuccess, 95)}`);
    console.log('');
  }
  
  console.log('═══════════════════════════════════════════');
  console.log('');
}

function printMetric(data, metricName, label) {
  if (!data.metrics[metricName]) return;
  
  const values = data.metrics[metricName].values;
  console.log(`   [${label}]`);
  console.log(`      평균: ${values.avg.toFixed(0)}ms`);
  console.log(`      P95:  ${values['p(95)'].toFixed(0)}ms`);
  console.log(`      P99:  ${values['p(99)'].toFixed(0)}ms`);
}

function formatDuration(ms) {
  const minutes = Math.floor(ms / 60000);
  const seconds = Math.floor((ms % 60000) / 1000);
  return `${minutes}분 ${seconds}초`;
}

function getStatusEmoji(value, threshold) {
  return value <= threshold ? '✅' : '⚠️';
}