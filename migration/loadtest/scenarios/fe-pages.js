import http from 'k6/http';
import { check, sleep } from 'k6';
import { FE_BASE_URL } from '../utils/config.js';
import { checkResponse, errorCounter } from '../utils/helpers.js';

/**
 * FE 페이지 응답 시나리오 (5단계 CloudFront 전환 검증용)
 * 1. 메인 페이지
 * 2. 로그인 페이지
 * 3. 현직자 목록 페이지
 * 4. 정적 리소스 확인
 */
export function fePagesScenario() {
  // 1. 메인 페이지
  const mainRes = http.get(`${FE_BASE_URL}/`);
  check(mainRes, {
    'Main page - status 200': (r) => r.status === 200,
    'Main page - has HTML': (r) => r.body && r.body.includes('<html'),
  });
  sleep(1);

  // 2. 로그인 페이지
  const loginRes = http.get(`${FE_BASE_URL}/login`);
  check(loginRes, {
    'Login page - status 200': (r) => r.status === 200,
    'Login page - has HTML': (r) => r.body && r.body.includes('<html'),
  });
  sleep(1);

  // 3. 현직자 목록 페이지
  const expertsRes = http.get(`${FE_BASE_URL}/experts`);
  check(expertsRes, {
    'Experts page - status 200': (r) => r.status === 200,
    'Experts page - has HTML': (r) => r.body && r.body.includes('<html'),
  });
  sleep(1);

  // 4. 정적 리소스 확인 (메인 페이지에서 _next 리소스 URL 추출)
  if (mainRes.body) {
    const nextMatch = mainRes.body.match(/\/_next\/static\/[^"'\s]+/);
    if (nextMatch) {
      const staticRes = http.get(`${FE_BASE_URL}${nextMatch[0]}`);
      check(staticRes, {
        'Static resource - status 200': (r) => r.status === 200,
        'Static resource - has Cache-Control': (r) =>
          r.headers['Cache-Control'] !== undefined,
      });
    }
  }
  sleep(1);
}
