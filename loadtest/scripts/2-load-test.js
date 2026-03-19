/**
 * 2-load-test.js
 *
 * Load Test: 일반 부하 테스트
 *
 * 목적:
 *   - 정상적인 부하 상황에서 시스템 안정성 검증
 *   - SLO 준수 여부 확인
 *
 * 조건:
 *   - Group A: 12명 (고부하 - AI 파싱)
 *   - Group B: 8명 (일반 - 수동 이력서)
 *   - Group C: 5명 (가벼움 - 검색/채팅)
 *   - Total: 25명 (피크 8명의 3배)
 *   - Duration: 7분
 *
 * 실행:
 *   k6 run scripts/2-load-test.js
 */

import http from "k6/http";
import { check, sleep, group } from "k6";
import { vu } from "k6/execution";
import * as Config from "./config.js";

// ─── 테스트 데이터 로드 ───
const users = JSON.parse(open("../data/test-users.json"));
const resumePDF = open("../data/sample_resume_3mb.pdf", "b");
const resumePDFSize = resumePDF.byteLength || resumePDF.length || 3145728;

export const options = {
  scenarios: {
    group_a_high_load: {
      executor: "ramping-vus",
      exec: "highLoadUser",
      startVUs: 0,
      stages: [
        { duration: "2m", target: 12 },
        { duration: "3m", target: 12 },
        { duration: "2m", target: 0 },
      ],
    },
    group_b_normal: {
      executor: "ramping-vus",
      exec: "normalUser",
      startVUs: 0,
      stages: [
        { duration: "2m", target: 8 },
        { duration: "3m", target: 8 },
        { duration: "2m", target: 0 },
      ],
    },
    group_c_light: {
      executor: "ramping-vus",
      exec: "lightUser",
      startVUs: 0,
      stages: [
        { duration: "2m", target: 5 },
        { duration: "3m", target: 5 },
        { duration: "2m", target: 0 },
      ],
    },
  },

  thresholds: {
    // 일반 API (baseline P95 ~96ms 기준 × 5배)
    expert_search_duration: ["p(95)<500"],
    resume_list_duration: ["p(95)<500"],
    chat_messages_duration: ["p(95)<500"],

    // LLM 파싱
    llm_parse_duration: ["p(95)<7000", "p(99)<10000"],

    // 에러율
    http_req_failed: ["rate<0.02"], // 2% 이하
    llm_parse_success_rate: ["rate>0.95"], // 95% 이상
  },
};

// ═════════════════════════════════════════════════════════════════
// 헬퍼 함수
// ═════════════════════════════════════════════════════════════════

function getPresignedUrl(token, fileName) {
  const res = http.post(
    `${Config.BACKEND_URL}/api/v1/uploads/presigned-url`,
    JSON.stringify({
      target_type: "RESUME_PDF",
      file_name: fileName,
      file_size: resumePDFSize,
    }),
    {
      headers: Config.authHeaders(token),
      tags: { name: "presigned_url" },
    },
  );

  if (res.status !== 200) {
    console.error(`Presigned URL 실패: ${res.status}`);
    return null;
  }

  return res.json();
}

function uploadToS3(presignedUrl, fileBytes) {
  const res = http.put(presignedUrl, fileBytes, {
    headers: { "Content-Type": "application/pdf" },
    tags: { name: "s3_upload" },
  });

  if (res.status !== 200) {
    Config.metrics.s3Errors.add(1);
    return false;
  }

  return true;
}

function triggerLLMParsing(token, s3FileUrl) {
  const startTime = Date.now();

  // 1. 비동기 태스크 제출 (즉시 taskId 반환)
  const res = http.post(
    `${Config.BACKEND_URL}/api/v2/resumes/tasks`,
    JSON.stringify({
      file_url: s3FileUrl,
    }),
    {
      headers: Config.authHeaders(token),
      tags: { name: "llm_parse_submit" },
      timeout: "10s",
    },
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
    console.error(`⚠️ LLM taskId 없음 | VU ${__VU}`);
    return null;
  }

  // 2. 완료 폴링: 초기 8초 대기 후 5초 간격 최대 5회 (실제 FCM 기반 트래픽 근사)
  sleep(8);
  for (let i = 0; i < 5; i++) {
    const pollRes = http.get(
      `${Config.BACKEND_URL}/api/v2/resumes/tasks/${taskId}`,
      {
        headers: Config.authHeaders(token),
        tags: { name: "llm_parse_poll" },
      },
    );

    let status;
    try {
      status = pollRes.json().data?.status;
    } catch (e) {
      continue;
    }

    if (status === "COMPLETED") {
      Config.metrics.llmParseDuration.add(Date.now() - startTime);
      Config.metrics.llmSuccessRate.add(1);
      return pollRes;
    }

    if (status === "FAILED") {
      Config.metrics.llmParseDuration.add(Date.now() - startTime);
      Config.metrics.llmSuccessRate.add(0);
      Config.metrics.llmErrors.add(1);
      console.error(`⚠️ LLM 파싱 실패 | VU ${__VU} | taskId: ${taskId}`);
      return null;
    }

    if (i < 4) sleep(5);
  }

  // 타임아웃 (총 ~33초)
  Config.metrics.llmParseDuration.add(Date.now() - startTime);
  Config.metrics.llmSuccessRate.add(0);
  Config.metrics.llmErrors.add(1);
  console.error(`⚠️ LLM 폴링 타임아웃 | VU ${__VU} | taskId: ${taskId}`);
  return null;
}

function searchExperts(token, params) {
  const query = Object.entries(params)
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join("&");

  const res = http.get(`${Config.BACKEND_URL}/api/v1/experts?${query}&size=5`, {
    headers: Config.authHeaders(token),
    tags: { name: "expert_search" },
  });

  Config.metrics.expertSearchDuration.add(res.timings.duration);
  Config.checkAPIResponse(res, "현직자 검색");

  try {
    const experts = res.json().data.experts;
    if (experts && experts.length > 0) return experts[0].user_id;
  } catch (e) {}

  return null;
}

function createChatRoom(token, body) {
  const res = http.post(
    `${Config.BACKEND_URL}/api/v1/chats`,
    JSON.stringify(body),
    {
      headers: Config.authHeaders(token),
      tags: { name: "chat_create" },
    },
  );

  Config.metrics.chatCreateDuration.add(res.timings.duration);
  check(res, {
    "채팅방 생성 성공": (r) => r.status === 201 || r.status === 409,
  });

  return res;
}

function getChatId(token, createRes) {
  if (createRes.status === 201) {
    try {
      return createRes.json().data.chat_id;
    } catch (e) {}
  }

  if (createRes.status === 409) {
    const listRes = http.get(`${Config.BACKEND_URL}/api/v1/chats`, {
      headers: Config.authHeaders(token),
      tags: { name: "chat_list" },
    });

    try {
      const chats = listRes.json().data.chats || listRes.json().data;
      if (chats && chats.length > 0) return chats[0].chat_id;
    } catch (e) {}
  }

  return null;
}

function getChatMessages(token, chatId) {
  const res = http.get(
    `${Config.BACKEND_URL}/api/v1/chats/${chatId}/messages`,
    {
      headers: Config.authHeaders(token),
      tags: { name: "chat_messages" },
    },
  );

  Config.metrics.chatMessagesDuration.add(res.timings.duration);
  Config.checkAPIResponse(res, "메시지 목록");

  return res;
}

function getChatDetail(token, chatId) {
  const res = http.get(`${Config.BACKEND_URL}/api/v1/chats/${chatId}`, {
    headers: Config.authHeaders(token),
    tags: { name: "chat_detail" },
  });

  Config.checkAPIResponse(res, "채팅방 상세");
  return res;
}

// ═════════════════════════════════════════════════════════════════
// Group A: 고부하 유저 (AI 파싱)
// ═════════════════════════════════════════════════════════════════

export function highLoadUser() {
  const vuIndex = vu.idInInstance - 1;
  const token = Config.getToken(users, vuIndex);
  const userId = Config.getUserId(users, vuIndex);

  sleep(1);

  let resumeId = null;

  // 1. 이력서 업로드 및 AI 파싱
  group("AI 이력서 파싱", () => {
    const presigned = getPresignedUrl(token, `resume_${userId}.pdf`);
    if (!presigned) return;

    if (!uploadToS3(presigned.data.presigned_url, resumePDF)) return;

    const s3Url = presigned.data.file_url;
    const parseRes = triggerLLMParsing(token, s3Url);

    if (parseRes) {
      const listRes = http.get(`${Config.BACKEND_URL}/api/v1/resumes`, {
        headers: Config.authHeaders(token),
        tags: { name: "resume_list" },
      });

      Config.metrics.resumeListDuration.add(listRes.timings.duration);

      try {
        const items = listRes.json().data.resumes;
        if (items && items.length > 0) resumeId = items[0].resume_id;
      } catch (e) {}
    }
  });

  sleep(2);

  // 2. 현직자 검색
  let expertId = null;
  group("현직자 검색", () => {
    expertId = searchExperts(token, Config.SEARCH_PARAMS.groupA);
  });

  sleep(1.5);

  if (!expertId) return;

  // 3. 채팅 진행
  group("채팅 진행", () => {
    const chatBody = {
      receiver_id: expertId,
      request_type: "FEEDBACK",
    };
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

// ═════════════════════════════════════════════════════════════════
// Group B: 일반 유저 (수동 이력서)
// ═════════════════════════════════════════════════════════════════

export function normalUser() {
  const vuIndex = vu.idInInstance + 11; // 12번째부터
  const token = Config.getToken(users, vuIndex);
  const userId = Config.getUserId(users, vuIndex);

  sleep(1);

  let resumeId = null;

  // 1. 이력서 수동 생성
  group("이력서 수동 생성", () => {
    const res = http.post(
      `${Config.BACKEND_URL}/api/v1/resumes`,
      JSON.stringify({
        title: `테스트 이력서 ${userId}`,
        is_fresher: true,
        education_level: Config.getEducationLevel(userId),
        content_json: {
          summary: "부하테스트용 테스트 이력서입니다.",
          experience: [
            {
              company: "테스트회사",
              role: "개발자",
              period: "2023.01 ~ 2024.01",
            },
          ],
          skills: ["Java", "Spring", "AWS"],
        },
      }),
      {
        headers: Config.authHeaders(token),
        tags: { name: "resume_create" },
      },
    );

    Config.metrics.resumeCreateDuration.add(res.timings.duration);
    check(res, {
      "이력서 생성 성공": (r) => r.status === 201 || r.status === 409,
    });

    if (res.status === 201) {
      try {
        resumeId = res.json().data.resume_id;
      } catch (e) {}
    }

    if (!resumeId) {
      const listRes = http.get(`${Config.BACKEND_URL}/api/v1/resumes`, {
        headers: Config.authHeaders(token),
        tags: { name: "resume_list" },
      });

      Config.metrics.resumeListDuration.add(listRes.timings.duration);

      try {
        const items = listRes.json().data.resumes;
        if (items && items.length > 0) resumeId = items[0].resume_id;
      } catch (e) {}
    }
  });

  sleep(1.5);

  // 2. 현직자 검색
  let expertId = null;
  group("현직자 검색", () => {
    expertId = searchExperts(token, Config.SEARCH_PARAMS.groupB);
  });

  sleep(1.5);

  if (!expertId) return;

  // 3. 채팅 진행
  group("채팅 진행", () => {
    const chatBody = {
      receiver_id: expertId,
      request_type: "COFFEE_CHAT",
    };
    if (resumeId) chatBody.resume_id = resumeId;

    const chatRes = createChatRoom(token, chatBody);
    const chatId = getChatId(token, chatRes);
    if (!chatId) return;

    sleep(1);
    getChatMessages(token, chatId);
  });
}

// ═════════════════════════════════════════════════════════════════
// Group C: 가벼운 유저 (검색/채팅)
// ═════════════════════════════════════════════════════════════════

export function lightUser() {
  const vuIndex = vu.idInInstance + 19; // 20번째부터
  const token = Config.getToken(users, vuIndex);

  sleep(1);

  // 1. 현직자 검색
  let expertId = null;
  group("현직자 검색", () => {
    expertId = searchExperts(token, Config.SEARCH_PARAMS.groupC);
  });

  sleep(1);

  if (!expertId) return;

  // 2. 채팅 진행
  group("채팅 진행", () => {
    const chatRes = createChatRoom(token, {
      receiver_id: expertId,
      request_type: "COFFEE_CHAT",
    });

    const chatId = getChatId(token, chatRes);
    if (!chatId) return;

    sleep(1);
    getChatMessages(token, chatId);
  });

  // 3. 30% 확률로 회원정보 수정
  if (Math.random() < 0.3) {
    sleep(1);
    group("회원정보 수정", () => {
      const res = http.patch(
        `${Config.BACKEND_URL}/api/v1/users/me`,
        JSON.stringify({
          nickname: `n${vuIndex}t${String(Date.now()).slice(-4)}`, // users.nickname max 10자
        }),
        {
          headers: Config.authHeaders(token),
          tags: { name: "user_update" },
        },
      );

      Config.checkAPIResponse(res, "회원정보 수정");
    });
  }
}

export function handleSummary(data) {
  Config.printSummary("Load Test", data);

  console.log("📌 SLO 달성 여부:");

  const expertP95 = data.metrics.expert_search_duration?.values["p(95)"];
  const llmP95 = data.metrics.llm_parse_duration?.values["p(95)"];
  const errorRate = data.metrics.http_req_failed?.values.rate * 100;

  console.log(
    `   현직자 검색 P95: ${expertP95?.toFixed(0)}ms ${expertP95 < 2000 ? "✅" : "❌"} (목표: 2000ms)`,
  );
  console.log(
    `   LLM 파싱 P95: ${llmP95?.toFixed(0)}ms ${llmP95 < 7000 ? "✅" : "❌"} (목표: 7000ms)`,
  );
  console.log(
    `   에러율: ${errorRate?.toFixed(2)}% ${errorRate < 2 ? "✅" : "❌"} (목표: <2%)`,
  );
  console.log("");

  return {
    "./results/load-test-summary.json": JSON.stringify(data, null, 2),
  };
}
