import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// 커스텀 메트릭
export const errorCounter = new Counter('custom_errors');
export const resumeParseDuration = new Trend('resume_parse_duration', true);

// 테스트 토큰 로드 및 타입별 분류
const tokenData = JSON.parse(open('../data/test-tokens.json'));
const seekerTokens = tokenData.filter((t) => t.user_type === 'JOB_SEEKER');
const expertTokens = tokenData.filter((t) => t.user_type === 'EXPERT');

/**
 * VU 기반 사용자 토큰 반환
 * 각 VU가 서로 다른 계정을 사용하도록 __VU 기반으로 분배.
 * 동일 VU는 항상 같은 계정을 사용하여 세션 일관성 유지.
 *
 * @param {string} [userType] - 'SEEKER' 또는 'EXPERT' (미지정 시 전체 풀에서 분배)
 */
export function getTokenForVU(userType) {
  let pool = tokenData;
  if (userType === 'SEEKER' || userType === 'JOB_SEEKER') pool = seekerTokens;
  else if (userType === 'EXPERT') pool = expertTokens;
  if (pool.length === 0) pool = tokenData;
  return pool[(__VU - 1) % pool.length];
}

/**
 * 인증 헤더 생성
 */
export function authHeaders(accessToken) {
  return {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
  };
}

/**
 * 공통 응답 검증
 */
export function checkResponse(res, name, expectedStatus = 200) {
  const passed = check(res, {
    [`${name} - status ${expectedStatus}`]: (r) => r.status === expectedStatus,
    [`${name} - no timeout`]: (r) => r.timings.duration < 30000,
  });

  if (!passed) {
    errorCounter.add(1, { endpoint: name, status: res.status });
  }

  return passed;
}

/**
 * JSON 응답 검증 (상태 코드 + body 파싱)
 */
export function checkJsonResponse(res, name, expectedStatus = 200) {
  const passed = checkResponse(res, name, expectedStatus);

  if (passed && res.status === expectedStatus) {
    try {
      return res.json();
    } catch (e) {
      errorCounter.add(1, { endpoint: name, error: 'json_parse' });
      return null;
    }
  }
  return null;
}

/**
 * 랜덤 sleep (min~max 초)
 */
export function randomSleep(min = 1, max = 3) {
  const duration = Math.random() * (max - min) + min;
  return __VU ? require('k6').sleep(duration) : null;
}

/**
 * STOMP 프레임 생성
 */
export function buildStompFrame(command, headers = {}, body = '') {
  let frame = command + '\n';
  for (const [key, value] of Object.entries(headers)) {
    frame += `${key}:${value}\n`;
  }
  frame += '\n' + body + '\0';
  return frame;
}

/**
 * STOMP CONNECT 프레임
 */
export function stompConnect(accessToken) {
  return buildStompFrame('CONNECT', {
    'accept-version': '1.2',
    'heart-beat': '10000,10000',
    Authorization: `Bearer ${accessToken}`,
  });
}

/**
 * STOMP SUBSCRIBE 프레임
 */
export function stompSubscribe(destination, id = 'sub-0') {
  return buildStompFrame('SUBSCRIBE', {
    id,
    destination,
    ack: 'auto',
  });
}

/**
 * STOMP SEND 프레임
 */
export function stompSend(destination, body) {
  return buildStompFrame('SEND', {
    destination,
    'content-type': 'application/json',
  }, typeof body === 'string' ? body : JSON.stringify(body));
}

/**
 * STOMP DISCONNECT 프레임
 */
export function stompDisconnect() {
  return buildStompFrame('DISCONNECT', { receipt: 'disconnect-receipt' });
}
