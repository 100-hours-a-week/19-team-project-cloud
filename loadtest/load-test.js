import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend } from 'k6/metrics';
import { vu } from 'k6/execution';

// ─── 테스트 데이터 로드 ───
const users = JSON.parse(open('./data/test-users.json'));

// ─── 테스트용 더미 PDF ───
const resumePDF      = open('./data/sample_resume_3mb.pdf', 'b');
const resumePDFSize  = resumePDF.byteLength || resumePDF.length || 3145728;

// ─── 환경 변수 ───
const BACKEND_URL = __ENV.BACKEND_URL || 'https://re-fit.kr';


// ─── custom 메트릭 ───
const llmReqDuration = new Trend('llm_req_duration');
const apiReqDuration = new Trend('api_req_duration');

// ─── DB 실제 값 (조회완료) ───
const SEARCH_PARAMS = {
  groupA: { job_id: 1 },                    // 백엔드 개발자
  groupB: { skill_id: 1 },                  // Java
  groupC: { keyword: '개발' },
};

// ─── 시나리오 & KPI ───
export const options = {
  scenarios: {
    group_a_high_load: {
      executor: 'ramping-vus',
      exec: 'highLoadUser',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 10 },
        { duration: '3m', target: 10 },
        { duration: '2m', target: 0 },
      ],
    },
    group_b_normal: {
      executor: 'ramping-vus',
      exec: 'normalUser',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 6 },
        { duration: '3m', target: 6 },
        { duration: '2m', target: 0 },
      ],
    },
    group_c_light: {
      executor: 'ramping-vus',
      exec: 'lightUser',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 4 },
        { duration: '3m', target: 4 },
        { duration: '2m', target: 0 },
      ],
    },
  },

  thresholds: {
    'llm_req_duration':  ['p(95)<7000'],   // LLM 요청: 7초
    'api_req_duration':  ['p(95)<3000'],   // API 요청: 3초
    'http_req_failed':   ['rate<0.04'],    // 에러율 4% 이하
  },
};

// ─────────────────────────────────────────────────────────
// 공통 헬퍼
// ─────────────────────────────────────────────────────────
function getToken(vuId)  {
  const idx = vuId % users.length;
  if (!users[idx]) { console.error(`users[${idx}] undefined, vuId=${vuId}, len=${users.length}`); return ''; }
  return users[idx].token;
}
function getUserId(vuId) {
  const idx = vuId % users.length;
  if (!users[idx]) return 1;
  return users[idx].user_id;
}
function authHeaders(token) {
  return { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' };
}

const EDUCATION_LEVELS = [
  '고등학교 졸업', '2년제 재학/휴학', '2년제 졸업', '4년제 재학/휴학', '4년제 졸업',
];
function getEducationLevel(userId) {
  return EDUCATION_LEVELS[userId % EDUCATION_LEVELS.length];
}

// ── 현직자 검색 ──
function searchExperts(token, params) {
  const query = Object.entries(params)
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join('&');

  const res = http.get(`${BACKEND_URL}/api/v1/experts?${query}&size=5`, {
    headers: { 'Authorization': `Bearer ${token}` },
    tags: { name: 'expert_search' },
  });
  apiReqDuration.add(res.timings.duration);
  check(res, { '현직자 검색 성공 (200)': (r) => r.status === 200 });

  try {
    const experts = res.json().data.experts;
    if (experts && experts.length > 0) return experts[0].user_id;
  } catch (e) {}
  return null;
}

// ── Presigned URL 발급 ──
function getPresignedUrl(token, fileName) {
  const res = http.post(`${BACKEND_URL}/api/v1/uploads/presigned-url`, JSON.stringify({
    target_type: 'RESUME_PDF',
    file_name:   fileName,
    file_size:   resumePDFSize,
  }), {
    headers: authHeaders(token),
    tags: { name: 'presigned_url_issue' },
  });
  apiReqDuration.add(res.timings.duration);
  check(res, { 'Presigned URL 발급 성공 (200)': (r) => r.status === 200 });
  if (res.status !== 200) {
    console.error(`Presigned URL 실패 | ${res.status} | ${res.body}`);
    return null;
  }
  return res.json();
}

// ── S3 업로드 ──
function uploadToS3(presignedUrl, fileBytes) {
  const res = http.put(presignedUrl, fileBytes, {
    headers: { 'Content-Type': 'application/pdf' },
    tags: { name: 'upload_to_s3' },
  });
  apiReqDuration.add(res.timings.duration);
  check(res, { 'S3 업로드 성공 (200)': (r) => r.status === 200 });
  return res.status === 200;
}

// ── LLM 파싱 ──
function triggerResumeParsing(token, s3FileUrl) {
  const res = http.post(`${BACKEND_URL}/api/v1/resumes/tasks`, JSON.stringify({
    file_url: s3FileUrl,
    mode:     'sync',
  }), {
    headers: authHeaders(token),
    tags:    { name: 'llm_resume_parse' },
    timeout: '30s',
  });
  llmReqDuration.add(res.timings.duration);
  check(res, {
    'LLM 파싱 응답 정상 (200 또는 500)': (r) => r.status === 200 || r.status === 500,
  });
  if (res.status !== 200) {
    console.error(`Resume 파싱 실패 | ${res.status} | ${res.body}`);
  }
  return res;
}

// ── 채팅방 생성 ──
function createChatRoom(token, body) {
  const res = http.post(`${BACKEND_URL}/api/v1/chats`, JSON.stringify(body), {
    headers: authHeaders(token),
    tags: { name: 'chat_create' },
  });
  apiReqDuration.add(res.timings.duration);
  check(res, { '채팅방 생성 또는 기존 존재 (201/409)': (r) => r.status === 201 || r.status === 409 });
  return res;
}

// ── 채팅방 목록 조회 (409 시 기존 chat_id 획득용) ──
function getChatId(token, res) {
  // 201 성공 → 응답에서 chat_id
  if (res.status === 201) {
    try { return res.json().data.chat_id; } catch (e) {}
  }
  // 409 → 내 채팅방 목록에서 최신 것 사용
  if (res.status === 409) {
    const listRes = http.get(`${BACKEND_URL}/api/v1/chats`, {
      headers: { 'Authorization': `Bearer ${token}` },
      tags: { name: 'chat_list' },
    });
    apiReqDuration.add(listRes.timings.duration);
    try {
      const chats = listRes.json().data.chats || listRes.json().data;
      if (chats && chats.length > 0) return chats[0].chat_id;
    } catch (e) {}
  }
  return null;
}

// ── 메시지 목록 조회 ──
function getChatMessages(token, chatId) {
  const res = http.get(`${BACKEND_URL}/api/v1/chats/${chatId}/messages`, {
    headers: { 'Authorization': `Bearer ${token}` },
    tags: { name: 'chat_messages_poll' },
  });
  apiReqDuration.add(res.timings.duration);
  check(res, { '메시지 목록 조회 (200)': (r) => r.status === 200 });
  return res;
}

// ── 채팅방 상세 조회 ──
function getChatDetail(token, chatId) {
  const res = http.get(`${BACKEND_URL}/api/v1/chats/${chatId}`, {
    headers: { 'Authorization': `Bearer ${token}` },
    tags: { name: 'chat_detail' },
  });
  apiReqDuration.add(res.timings.duration);
  check(res, { '채팅방 상세 조회 (200)': (r) => r.status === 200 });
  return res;
}

// ─────────────────────────────────────────────────────────
//  GROUP A: 고부하 유저 (10명)
//  PDF 업로드 → LLM 파싱 → 현직자 검색 → 채팅
// ─────────────────────────────────────────────────────────
export function highLoadUser() {
  const vuIndex = vu.idInInstance - 1;          // 0~9 (인덱스)
  const token   = getToken(vuIndex);
  const userId = getUserId(vuIndex);           // 실제 DB user_id (2~11)
  sleep(1);

  let resumeId = null;

  group('이력서 업로드 및 LLM 파싱', () => {
    const presigned = getPresignedUrl(token, 'resume.pdf');
    if (!presigned) return;
    if (!uploadToS3(presigned.data.presigned_url, resumePDF)) return;

    const s3Url = presigned.data.file_url;
    const parseRes = triggerResumeParsing(token, s3Url);
    if (parseRes && parseRes.status === 200) {
      // 파싱 완료 후 목록 조회하여 최신 resume_id 가져오기
      const listRes = http.get(`${BACKEND_URL}/api/v1/resumes`, {
        headers: authHeaders(token),
        tags:    { name: 'resume_list' },
      });
      apiReqDuration.add(listRes.timings.duration);
      try {
        const items = listRes.json().data.resumes;
        if (items && items.length > 0) resumeId = items[0].resume_id;
      } catch (e) {}
    }
  });
  sleep(2);

  let expertId = null;
  group('현직자 검색', () => {
    expertId = searchExperts(token, SEARCH_PARAMS.groupA);
  });
  sleep(1.5);

  if (!expertId) return;
  group('채팅 진행', () => {
    const chatBody = { receiver_id: expertId, request_type: 'FEEDBACK' };
    if (resumeId) chatBody.resume_id = resumeId;

    const chatRes = createChatRoom(token, chatBody);
    const chatId = getChatId(token, chatRes);
    if (!chatId) return;

    sleep(1);
    getChatMessages(token, chatId);
    sleep(1);
    getChatDetail(token, chatId);
  });
}

// ─────────────────────────────────────────────────────────
//  GROUP B: 일반 유저 (6명)
//  이력서 수동 생성 → 현직자 검색 → 채팅
// ─────────────────────────────────────────────────────────
export function normalUser() {
  const vuIndex = vu.idInInstance + 9;         // 10~15 (인덱스)
  const token   = getToken(vuIndex);
  const userId = getUserId(vuIndex);          // 실제 DB user_id (12~14, 23~25)
  sleep(1);

  let resumeId = null;

  group('이력서 수동 생성', () => {
    const res = http.post(`${BACKEND_URL}/api/v1/resumes`, JSON.stringify({
      title:            `테스트 이력서 ${userId}`,
      is_fresher:       true,
      education_level:  getEducationLevel(userId),
      content_json: {
        summary:    '부하테스트용 테스트 이력서입니다.',
        experience: [{ company: '테스트회사', role: '개발자', period: '2023.01 ~ 2024.01' }],
        skills:     ['Java', 'Spring', 'AWS'],
      },
    }), {
      headers: authHeaders(token),
      tags: { name: 'resume_manual_create' },
    });
    apiReqDuration.add(res.timings.duration);
    check(res, { '이력서 생성 또는 기존 존재 (201/409)': (r) => r.status === 201 || r.status === 409 });

    if (res.status === 201) {
      try { resumeId = res.json().data.resume_id; } catch (e) {}
    }
    // 409 RESUME_LIMIT_EXCEEDED → 기존 이력서 목록에서 사용
    if (!resumeId) {
      const listRes = http.get(`${BACKEND_URL}/api/v1/resumes`, {
        headers: authHeaders(token),
        tags: { name: 'resume_list' },
      });
      apiReqDuration.add(listRes.timings.duration);
      try {
        const items = listRes.json().data.resumes;
        if (items && items.length > 0) resumeId = items[0].resume_id;
      } catch (e) {}
    }
  });
  sleep(1.5);

  let expertId = null;
  group('현직자 검색', () => {
    expertId = searchExperts(token, SEARCH_PARAMS.groupB);
  });
  sleep(1.5);

  if (!expertId) return;
  group('채팅 진행', () => {
    const chatBody = { receiver_id: expertId, request_type: 'COFFEE_CHAT' };
    if (resumeId) chatBody.resume_id = resumeId;

    const chatRes = createChatRoom(token, chatBody);
    const chatId = getChatId(token, chatRes);
    if (!chatId) return;

    sleep(1);
    getChatMessages(token, chatId);
  });
}

// ─────────────────────────────────────────────────────────
//  GROUP C: 가벼운 유저 (4명)
//  현직자 검색 → 간단한 채팅
// ─────────────────────────────────────────────────────────
export function lightUser() {
  const vuIndex = vu.idInInstance + 15;        // 16~19 (인덱스)
  const token   = getToken(vuIndex);
  const userId = getUserId(vuIndex);           // 실제 DB user_id (23, 24, 25, 28 등)
  sleep(1);

  let expertId = null;
  group('현직자 검색', () => {
    expertId = searchExperts(token, SEARCH_PARAMS.groupC);
  });
  sleep(1);

  if (!expertId) return;
  group('채팅 진행', () => {
    const chatRes = createChatRoom(token, {
      receiver_id:  expertId,
      request_type: 'COFFEE_CHAT',
    });
    const chatId = getChatId(token, chatRes);
    if (!chatId) return;

    sleep(1);
    getChatMessages(token, chatId);
  });

  // 30% 확률로 회원정보 수정
  if (Math.random() < 0.3) {
    sleep(1);
    group('회원정보 수정', () => {
      const res = http.patch(`${BACKEND_URL}/api/v1/users/me`, JSON.stringify({
        nickname: `nick${Date.now()}_${vuIndex}`,  // 타임스탬프로 중복 방지
      }), {
        headers: authHeaders(token),
        tags: { name: 'mypage_update' },
      });
      apiReqDuration.add(res.timings.duration);
      check(res, { '회원정보 수정 성공 (200)': (r) => r.status === 200 });
      if (res.status !== 200) {
        console.error(`회원정보 수정 실패 | ${res.status} | ${res.body}`);
      }
    });
  }
}