import http from 'k6/http';
import { sleep } from 'k6';
import { BASE_URL, SEARCH_KEYWORDS } from '../utils/config.js';
import { getTokenForVU, authHeaders, checkJsonResponse, checkResponse } from '../utils/helpers.js';

/**
 * 현직자 검색/조회 시나리오
 * 1. 현직자 목록 조회 (키워드 검색)
 * 2. 현직자 상세 조회
 * 3. 현직자 목록 페이징 (커서 기반)
 */
export function expertScenario() {
  const token = getTokenForVU();
  const params = authHeaders(token.access_token);
  const keyword = SEARCH_KEYWORDS[Math.floor(Math.random() * SEARCH_KEYWORDS.length)];

  // 1. 현직자 목록 조회 (키워드 검색)
  const listRes = http.get(
    `${BASE_URL}/api/v1/experts?keyword=${encodeURIComponent(keyword)}&size=10`,
    params,
  );
  const listData = checkJsonResponse(listRes, 'GET /experts');
  sleep(1);

  // 2. 현직자 상세 조회 (목록에서 첫 번째 ID 사용)
  const experts = listData?.data?.experts || [];
  if (experts.length > 0) {
    const expertId = experts[0].user_id;
    const detailRes = http.get(`${BASE_URL}/api/v1/experts/${expertId}`, params);
    checkResponse(detailRes, 'GET /experts/{id}');
    sleep(1);
  }

  // 3. 커서 기반 페이지네이션
  const cursor = listData?.data?.next_cursor;
  if (cursor) {
    const pageRes = http.get(
      `${BASE_URL}/api/v1/experts?cursor=${cursor}&size=10`,
      params,
    );
    checkResponse(pageRes, 'GET /experts (page 2)');
    sleep(1);
  }
}

/**
 * 현직자 목록 조회만 (경량)
 */
export function expertListOnly() {
  const keyword = SEARCH_KEYWORDS[Math.floor(Math.random() * SEARCH_KEYWORDS.length)];
  const res = http.get(
    `${BASE_URL}/api/v1/experts?keyword=${encodeURIComponent(keyword)}&size=10`,
    { headers: { 'Content-Type': 'application/json' } },
  );
  checkResponse(res, 'GET /experts');
  sleep(1);
}
