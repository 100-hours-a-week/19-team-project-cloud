/**
 * 5-ai-agent-test.js
 *
 * AI Agent 채팅 테스트 (SSE 스트리밍)
 *
 * 대상 엔드포인트:
 *   POST /api/ai/agent/sessions    - 세션 생성
 *   POST /api/ai/agent/reply       - SSE 스트리밍 답변
 *   GET  /api/ai/agent/sessions/:id - 세션 상태 조회
 *
 * 실행:
 *   npm run generate-tokens
 *   k6 run --iterations 1 scripts/5-ai-agent-test.js   # 단일 검증
 *   npm run test:ai-agent                               # 전체 실행 (10분)
 *
 * 참고:
 *   k6 표준 HTTP는 SSE 스트림을 서버가 닫을 때까지 버퍼링함.
 *   AI 서비스는 'done' 이벤트 전송 후 연결을 닫으므로 res.body에 전체 이벤트가 포함됨.
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { vu } from 'k6/execution';
import * as Config from './config.js';

// ════════════════════════════════════════════════════════════════════
// 📁 데이터 로딩
// ════════════════════════════════════════════════════════════════════

const users = JSON.parse(open('../data/test-users.json'));

// ════════════════════════════════════════════════════════════════════
// 💬 샘플 메시지 (취업 관련 한국어 질문 5개 순환)
// ════════════════════════════════════════════════════════════════════

const SAMPLE_MESSAGES = [
  '백엔드 개발자로 취업하려면 어떤 기술을 준비해야 하나요?',
  '신입 개발자 포트폴리오에서 가장 중요한 점은 무엇인가요?',
  '스타트업과 대기업 중 신입에게 어디가 더 좋을까요?',
  '코딩 인터뷰 준비는 어떻게 시작해야 하나요?',
  '주니어 개발자가 성장하기 위해 가장 중요한 것은 무엇인가요?',
];

// ════════════════════════════════════════════════════════════════════
// ⚙️  테스트 옵션
// ════════════════════════════════════════════════════════════════════

export const options = {
  scenarios: {
    ai_agent_chat: {
      executor: 'constant-vus',
      vus: 3,         // SSE는 연결당 10~30초 LLM 추론 → 3 VU로 시작
      duration: '10m',
    },
  },
  thresholds: {
    'agent_session_duration': ['p(95)<3000'],
    'agent_reply_duration': ['p(95)<30000', 'p(99)<45000'],
    'agent_reply_success': ['rate>0.90'],
    'http_req_failed': ['rate<0.05'],
  },
};

// ════════════════════════════════════════════════════════════════════
// 🔧 SSE 파싱 헬퍼
// ════════════════════════════════════════════════════════════════════

/**
 * SSE 응답 바디를 파싱하여 이벤트 객체 배열로 반환
 * 형식: "data: {...}\n\ndata: {...}\n\n"
 */
function parseSSEBody(body) {
  if (!body) return [];
  return body.split('\n\n')
    .map(chunk => chunk.trim())
    .filter(chunk => chunk.startsWith('data: '))
    .map(chunk => {
      try {
        return JSON.parse(chunk.slice(6));
      } catch (e) {
        return null;
      }
    })
    .filter(Boolean);
}

// ════════════════════════════════════════════════════════════════════
// 🤖 API 헬퍼 함수
// ════════════════════════════════════════════════════════════════════

/**
 * AI Agent 세션 생성
 * POST /api/ai/agent/sessions
 */
function createAgentSession(token) {
  const res = http.post(
    `${Config.BACKEND_URL}/api/ai/agent/sessions`,
    null,
    {
      headers: Config.authHeaders(token),
      tags: { name: 'agent_session_create' },
    }
  );

  Config.metrics.agentSessionDuration.add(res.timings.duration);

  const ok = check(res, {
    'AI 세션 생성 - 상태코드 200/201': (r) => r.status === 200 || r.status === 201,
  });

  if (!ok) {
    Config.metrics.agentErrors.add(1);
    console.error(`❌ 세션 생성 실패 | VU ${__VU} | Status: ${res.status} | Body: ${res.body?.slice(0, 200)}`);
    return null;
  }

  try {
    const body = res.json();
    // API 응답 구조: { code: "OK", data: { session_id: "..." } } 또는 { session_id: "..." }
    return body?.data?.session_id || body?.session_id || null;
  } catch (e) {
    console.error(`❌ 세션 ID 파싱 실패 | VU ${__VU} | Body: ${res.body?.slice(0, 200)}`);
    return null;
  }
}

/**
 * AI Agent 답변 요청 (SSE 스트리밍)
 * POST /api/ai/agent/reply
 */
function sendAgentReply(token, sessionId, message) {
  const payload = JSON.stringify({
    session_id: sessionId,
    message: message,
    top_k: 3,
  });

  const res = http.post(
    `${Config.BACKEND_URL}/api/ai/agent/reply`,
    payload,
    {
      headers: {
        ...Config.authHeaders(token),
        'Accept': 'text/event-stream',
      },
      tags: { name: 'agent_reply' },
      timeout: '60s',
    }
  );

  Config.metrics.agentReplyDuration.add(res.timings.duration);

  const events = parseSSEBody(res.body);
  Config.checkAgentReplyResponse(res, events);

  // 디버깅용: 이벤트 타입 목록 출력 (오류 시)
  if (res.status !== 200) {
    console.log(`  이벤트 타입: ${events.map(e => e.type).join(', ')}`);
  }

  return events;
}

/**
 * 세션 상태 조회
 * GET /api/ai/agent/sessions/{session_id}
 */
function getAgentSession(token, sessionId) {
  const res = http.get(
    `${Config.BACKEND_URL}/api/ai/agent/sessions/${sessionId}`,
    {
      headers: Config.authHeaders(token),
      tags: { name: 'agent_session_get' },
    }
  );

  check(res, {
    'AI 세션 조회 - 상태코드 200': (r) => r.status === 200,
  });

  return res;
}

// ════════════════════════════════════════════════════════════════════
// 🏃 메인 테스트 함수
// ════════════════════════════════════════════════════════════════════

export default function () {
  const vuIndex = vu.idInInstance - 1;
  const token = Config.getToken(users, vuIndex);
  if (!token) return;

  // VU와 반복 횟수를 조합하여 메시지 순환
  const message = SAMPLE_MESSAGES[(__VU + __ITER) % SAMPLE_MESSAGES.length];

  let sessionId = null;

  group('1. AI 에이전트 세션 생성', () => {
    sessionId = createAgentSession(token);
  });

  if (!sessionId) {
    sleep(5);
    return;
  }

  sleep(1);

  group('2. AI 에이전트 답변 요청 (SSE)', () => {
    sendAgentReply(token, sessionId, message);
  });

  sleep(1);

  group('3. 세션 상태 확인', () => {
    getAgentSession(token, sessionId);
  });

  // SSE 스트리밍 후 think time (3~5초)
  sleep(3 + Math.random() * 2);
}

// ════════════════════════════════════════════════════════════════════
// 📊 결과 요약
// ════════════════════════════════════════════════════════════════════

export function handleSummary(data) {
  Config.printSummary('AI Agent Test', data);

  // AI Agent 성공률 출력
  if (data.metrics.agent_reply_success) {
    const successRate = (data.metrics.agent_reply_success.values.rate * 100).toFixed(1);
    console.log('🤖 AI Agent 성공률:');
    console.log(`   Agent 답변: ${successRate}% ${successRate >= 90 ? '✅' : '⚠️'}`);
    console.log('');
  }

  return {
    stdout: '',
  };
}
