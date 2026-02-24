import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL } from '../utils/config.js';
import {
  getTokenForVU,
  authHeaders,
  checkJsonResponse,
  checkResponse,
  resumeParseDuration,
  errorCounter,
} from '../utils/helpers.js';

// 테스트용 PDF 바이너리 로드 (init 단계에서만 실행)
const resumePdf = open('../data/dummy_resume.pdf', 'b');

/**
 * 이력서 전체 플로우 시나리오
 * 1. Presigned URL 발급
 * 2. S3 업로드
 * 3. 이력서 파싱 (AI 호출)
 * 4. 이력서 생성
 * 5. 이력서 목록 조회
 */
export function resumeFullScenario() {
  const token = getTokenForVU('SEEKER');
  const params = authHeaders(token.access_token);

  // 1. Presigned URL 발급
  const presignedRes = http.post(
    `${BASE_URL}/api/v1/uploads/presigned-url`,
    JSON.stringify({
      target_type: 'RESUME',
      file_name: 'test_resume.pdf',
      file_size: resumePdf.length,
    }),
    params,
  );
  const presignedData = checkJsonResponse(presignedRes, 'POST /uploads/presigned-url');
  if (!presignedData?.presigned_url) return;
  sleep(1);

  // 2. S3 업로드 (Presigned URL로 PUT)
  const uploadRes = http.put(presignedData.presigned_url, resumePdf, {
    headers: { 'Content-Type': 'application/pdf' },
    timeout: '60s',
  });
  checkResponse(uploadRes, 'PUT S3 upload', 200);
  sleep(1);

  // 3. 이력서 파싱 (AI 호출 — 응답 시간이 길 수 있음)
  const parseStart = Date.now();
  const parseRes = http.post(
    `${BASE_URL}/api/v1/resumes/tasks`,
    JSON.stringify({
      file_url: presignedData.file_url,
      mode: 'BASIC',
    }),
    { ...params, timeout: '120s' },
  );
  const parseDuration = Date.now() - parseStart;
  resumeParseDuration.add(parseDuration);

  const parseData = checkJsonResponse(parseRes, 'POST /resumes/tasks');
  if (!parseData) return;
  sleep(2);

  // 4. 이력서 생성
  const createRes = http.post(
    `${BASE_URL}/api/v1/resumes`,
    JSON.stringify({
      title: `k6 테스트 이력서 ${Date.now()}`,
      is_fresher: false,
      education_level: 'BACHELOR',
      file_url: presignedData.file_url,
      content_json: parseData.result || '{}',
    }),
    params,
  );
  checkResponse(createRes, 'POST /resumes', 201);
  sleep(1);

  // 5. 이력서 목록 조회
  const listRes = http.get(`${BASE_URL}/api/v1/resumes`, params);
  checkJsonResponse(listRes, 'GET /resumes');
  sleep(1);
}

/**
 * 이력서 목록 조회만 (경량 시나리오 — AI 파싱 없음)
 */
export function resumeListOnly() {
  const token = getTokenForVU('SEEKER');
  const res = http.get(`${BASE_URL}/api/v1/resumes`, authHeaders(token.access_token));
  checkResponse(res, 'GET /resumes');
  sleep(1);
}
