/**
 * 6-hpa-validation.js
 *
 * HPA 스케일링 검증 테스트
 *
 * 목적:
 *   - 백엔드 CPU 사용률을 70% 이상으로 지속 유지
 *   - HPA가 실제로 파드를 2 → 최대 5개로 스케일 아웃하는지 확인
 *   - 스케일 다운 동작도 관찰
 *
 * k8s 설정 (refit-backend):
 *   - HPA: min=2, max=5, CPU target=70%
 *   - Resource request: 250m CPU × 2 pods = 350m 초과 시 스케일
 *   - minReadySeconds: 30 → 스케일 아웃 시 최소 30초 지연 발생
 *
 * 부하 전략:
 *   - 50% LLM 파싱 (CPU 집약적) + 30% Resume/Expert 조회 + 20% Expert 검색
 *   - sleep 최소화 (0.5초)로 CPU 압력 극대화
 *
 * 실행:
 *   # 별도 터미널에서 먼저 실행:
 *   watch -n5 kubectl get hpa -n refit-app
 *   watch -n5 kubectl get pods -n refit-app
 *
 *   # 테스트 실행:
 *   npm run generate-tokens
 *   npm run test:hpa
 *
 * 예상 소요시간: 22분
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { vu, scenario } from 'k6/execution';
import * as Config from './config.js';

// ════════════════════════════════════════════════════════════════════
// 📁 데이터 로딩
// ════════════════════════════════════════════════════════════════════

const users = JSON.parse(open('../data/test-users.json'));
const resumePDF = open('../data/sample_resume_3mb.pdf', 'b');
const resumePDFSize = resumePDF.byteLength || resumePDF.length || 3145728;

// ════════════════════════════════════════════════════════════════════
// ⚙️  테스트 옵션
// ════════════════════════════════════════════════════════════════════

export const options = {
  scenarios: {
    hpa_validation: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '5m', target: 35 },   // 램프업: 0 → 35 VUs
        { duration: '10m', target: 35 },  // 지속: HPA 트리거 구간 (CPU >70% 3분 유지 시 스케일)
        { duration: '5m', target: 20 },   // 감소: 스케일 다운 관찰
        { duration: '2m', target: 0 },    // 종료
      ],
      gracefulRampDown: '30s',
    },
  },

  // 임계값 완화: HPA 스케일 중 지연 급등 허용 (검증 목적이므로 SLO보다 관대하게 설정)
  thresholds: {
    'http_req_failed': [{ threshold: 'rate<0.10', abortOnFail: false }],
    'expert_search_duration': [{ threshold: 'p(95)<5000', abortOnFail: false }],
    'llm_parse_duration': [{ threshold: 'p(95)<15000', abortOnFail: false }],
  },
};

// ════════════════════════════════════════════════════════════════════
// 🔧 헬퍼 함수 (2-load-test.js 패턴 재사용)
// ════════════════════════════════════════════════════════════════════

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

  // HPA 검증 목적: 폴링보다 CPU 부하 지속이 중요하므로 초기 대기 후 1회만 확인
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
  return null;
}

function searchExperts(token, params) {
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
    const experts = res.json().data?.experts;
    if (experts && experts.length > 0) return experts[0].user_id;
  } catch (e) {}
  return null;
}

function getResumeList(token) {
  const res = http.get(
    `${Config.BACKEND_URL}/api/v1/resumes`,
    {
      headers: Config.authHeaders(token),
      tags: { name: 'resume_list' },
    }
  );

  Config.metrics.resumeListDuration.add(res.timings.duration);
  Config.checkAPIResponse(res, '이력서 목록');
  return res;
}

function getChatList(token) {
  const res = http.get(
    `${Config.BACKEND_URL}/api/v1/chats`,
    {
      headers: Config.authHeaders(token),
      tags: { name: 'chat_list' },
    }
  );

  Config.checkAPIResponse(res, '채팅 목록');
  return res;
}

// ════════════════════════════════════════════════════════════════════
// 🏃 메인 테스트 함수 (3가지 패턴을 VU 번호로 분기)
// ════════════════════════════════════════════════════════════════════

export default function () {
  const vuIndex = vu.idInInstance - 1;
  const token = Config.getToken(users, vuIndex);
  const userId = Config.getUserId(users, vuIndex);
  if (!token) return;

  // VU 번호 기반 부하 혼합:
  //   0-4 (14%):  Expert 검색만 (light)
  //   5-14 (29%): Resume + Expert 조회 (medium)
  //   15-34 (57%): LLM 파싱 (heavy, CPU 집약적)
  // → 실제 VU 분포: 35 VUs 중 약 20 VUs가 LLM 파싱
  const pattern = vuIndex % 10;

  if (pattern < 2) {
    // 20% — Expert 검색만 (가벼운 부하)
    group('Expert 검색 (light)', () => {
      searchExperts(token, Config.SEARCH_PARAMS.groupA);
      sleep(0.5);
      searchExperts(token, Config.SEARCH_PARAMS.groupB);
    });
    sleep(0.5);

  } else if (pattern < 5) {
    // 30% — Resume 목록 + Expert 검색 + 채팅 목록 (중간 부하)
    group('Resume/Expert 조회 (medium)', () => {
      getResumeList(token);
      sleep(0.5);
      searchExperts(token, Config.SEARCH_PARAMS.groupA);
      sleep(0.5);
      getChatList(token);
    });
    sleep(0.5);

  } else {
    // 50% — LLM 파싱 전체 플로우 (CPU 집약적 고부하)
    group('LLM 파싱 전체 플로우 (heavy)', () => {
      const presigned = getPresignedUrl(token, `hpa_test_${userId}_${__ITER}.pdf`);
      if (!presigned) return;

      const s3Ok = uploadToS3(presigned.data?.presigned_url, resumePDF);
      if (!s3Ok) return;

      const s3Url = presigned.data?.file_url;
      if (!s3Url) return;

      triggerLLMParsing(token, s3Url);

      sleep(0.5);
      getResumeList(token);
    });
    sleep(0.5);
  }
}

// ════════════════════════════════════════════════════════════════════
// 🚀 Setup: 테스트 시작 시 kubectl 안내 출력
// ════════════════════════════════════════════════════════════════════

export function setup() {
  console.log('');
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║           ⚡ HPA Validation Test - kubectl 안내 ⚡            ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║ 별도 터미널에서 다음 명령어를 실행하세요:                       ║');
  console.log('║                                                              ║');
  console.log('║  # HPA 상태 실시간 모니터링 (5초마다 갱신)                     ║');
  console.log('║  watch -n5 kubectl get hpa -n refit-app                     ║');
  console.log('║                                                              ║');
  console.log('║  # 파드 수 변화 모니터링                                       ║');
  console.log('║  watch -n5 kubectl get pods -n refit-app                    ║');
  console.log('║                                                              ║');
  console.log('║  # CPU 사용량 확인 (수동 갱신)                                 ║');
  console.log('║  kubectl top pods -n refit-app --containers                 ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║ 예상 타임라인:                                                ║');
  console.log('║  00:00 ~ 05:00  램프업 (0 → 35 VUs)                         ║');
  console.log('║  05:00 ~ 15:00  지속 부하 → HPA 스케일 아웃 기대              ║');
  console.log('║  15:00 ~ 20:00  부하 감소 → 스케일 다운 관찰                  ║');
  console.log('║  20:00 ~ 22:00  종료                                         ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
}

// ════════════════════════════════════════════════════════════════════
// 📊 결과 요약
// ════════════════════════════════════════════════════════════════════

export function handleSummary(data) {
  Config.printSummary('HPA Validation Test', data);

  const errorRate = (data.metrics.http_req_failed?.values.rate * 100) || 0;
  const expertP95 = data.metrics.expert_search_duration?.values['p(95)'] || 0;
  const llmP95 = data.metrics.llm_parse_duration?.values['p(95)'] || 0;
  const totalReqs = data.metrics.http_reqs?.values.count || 0;

  console.log('📌 HPA 검증 포인트 (kubectl로 확인):');
  console.log('   [ ] HPA TARGETS 컬럼이 70% 초과했는가?');
  console.log('   [ ] REPLICAS 컬럼이 2 → 3 이상으로 증가했는가?');
  console.log('   [ ] 스케일 아웃 후 에러율이 안정화되었는가?');
  console.log('   [ ] 부하 감소 후 파드가 다시 2개로 스케일 다운되었는가?');
  console.log('');
  console.log(`   에러율: ${errorRate.toFixed(2)}% (허용: <10%)`);
  console.log(`   총 요청: ${totalReqs}개`);
  console.log('');
  console.log('   VPA 추천 확인:');
  console.log('   kubectl get vpa -n refit-app -o json | \\');
  console.log("     jq '.items[] | {name: .metadata.name, recs: .status.recommendation.containerRecommendations}'");
  console.log('');

  return {
    './results/hpa-validation-summary.json': JSON.stringify(data, null, 2),
  };
}
