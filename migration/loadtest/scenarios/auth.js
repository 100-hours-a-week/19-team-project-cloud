import http from 'k6/http';
import { sleep } from 'k6';
import { BASE_URL } from '../utils/config.js';
import { getTokenForVU, authHeaders, checkJsonResponse, checkResponse } from '../utils/helpers.js';

/**
 * 인증 시나리오
 * 내 정보 조회 (GET /api/v1/users/me)
 */
export function authScenario() {
  const token = getTokenForVU();
  const meRes = http.get(`${BASE_URL}/api/v1/users/me`, authHeaders(token.access_token));
  checkJsonResponse(meRes, 'GET /users/me');
  sleep(1);
}

/**
 * 내 정보 조회만 (경량 시나리오)
 */
export function authMeOnly() {
  const token = getTokenForVU();
  const res = http.get(`${BASE_URL}/api/v1/users/me`, authHeaders(token.access_token));
  checkResponse(res, 'GET /users/me');
  sleep(1);
}
