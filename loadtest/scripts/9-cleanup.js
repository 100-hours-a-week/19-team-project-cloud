/**
 * 9-cleanup.js
 * 
 * Cleanup: 테스트 데이터 정리
 * 
 * 목적:
 *   - 테스트 후 생성된 이력서/채팅방 삭제
 *   - 테스트 유저별로 데이터 정리
 *   - S3 파일 정리 (선택적)
 * 
 * 조건:
 *   - 각 유저별 VU 할당
 *   - 순차 삭제 (API Rate Limit 고려)
 * 
 * 실행:
 *   k6 run scripts/9-cleanup.js
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { vu } from 'k6/execution';
import * as Config from './config.js';

// ─── 테스트 데이터 로드 ───
const users = JSON.parse(open('../data/test-users.json'));

export const options = {
  scenarios: {
    cleanup: {
      executor: 'per-vu-iterations',
      vus: users.length,      // 유저 수만큼 VU
      iterations: 1,          // 각 VU는 1회만 실행
      maxDuration: '10m',
    },
  },
  
  // Cleanup은 threshold 없음
  thresholds: {},
};

// ═════════════════════════════════════════════════════════════════
// 헬퍼 함수
// ═════════════════════════════════════════════════════════════════

function deleteResumes(token) {
  // 1. 이력서 목록 조회
  const listRes = http.get(
    `${Config.BACKEND_URL}/api/v1/resumes`,
    {
      headers: Config.authHeaders(token),
      tags: { name: 'resume_list' },
    }
  );
  
  if (listRes.status !== 200) {
    console.log(`이력서 목록 조회 실패: ${listRes.status}`);
    return 0;
  }
  
  let resumes = [];
  try {
    resumes = listRes.json().data.resumes || listRes.json().data || [];
  } catch (e) {
    console.log('이력서 목록 파싱 실패');
    return 0;
  }
  
  if (resumes.length === 0) {
    return 0;
  }
  
  // 2. 각 이력서 삭제
  let deletedCount = 0;
  
  for (const resume of resumes) {
    const resumeId = resume.resume_id || resume.id;
    if (!resumeId) continue;
    
    const deleteRes = http.del(
      `${Config.BACKEND_URL}/api/v1/resumes/${resumeId}`,
      null,
      {
        headers: Config.authHeaders(token),
        tags: { name: 'resume_delete' },
      }
    );
    
    if (deleteRes.status === 204 || deleteRes.status === 200) {
      deletedCount++;
    }
    
    sleep(0.2); // Rate Limit 방지
  }
  
  return deletedCount;
}

function deleteChats(token) {
  // 1. 채팅방 목록 조회
  const listRes = http.get(
    `${Config.BACKEND_URL}/api/v1/chats`,
    {
      headers: Config.authHeaders(token),
      tags: { name: 'chat_list' },
    }
  );
  
  if (listRes.status !== 200) {
    console.log(`채팅방 목록 조회 실패: ${listRes.status}`);
    return 0;
  }
  
  let chats = [];
  try {
    chats = listRes.json().data.chats || listRes.json().data || [];
  } catch (e) {
    console.log('채팅방 목록 파싱 실패');
    return 0;
  }
  
  if (chats.length === 0) {
    return 0;
  }
  
  // 2. 각 채팅방 삭제
  let deletedCount = 0;
  
  for (const chat of chats) {
    const chatId = chat.chat_id || chat.id;
    if (!chatId) continue;
    
    const deleteRes = http.del(
      `${Config.BACKEND_URL}/api/v1/chats/${chatId}`,
      null,
      {
        headers: Config.authHeaders(token),
        tags: { name: 'chat_delete' },
      }
    );
    
    if (deleteRes.status === 204 || deleteRes.status === 200) {
      deletedCount++;
    }
    
    sleep(0.2); // Rate Limit 방지
  }
  
  return deletedCount;
}

// ═════════════════════════════════════════════════════════════════
// 메인 Cleanup 로직
// ═════════════════════════════════════════════════════════════════

export default function() {
  const vuIndex = vu.idInInstance - 1;
  const token = Config.getToken(users, vuIndex);
  const userId = Config.getUserId(users, vuIndex);
  
  if (!token) {
    console.error(`VU ${vuIndex}: 토큰 없음`);
    return;
  }
  
  console.log(`🧹 [User ${userId}] Cleanup 시작...`);
  
  let totalResumes = 0;
  let totalChats = 0;
  
  // 1. 이력서 삭제
  group('이력서 삭제', () => {
    totalResumes = deleteResumes(token);
  });
  
  sleep(1);
  
  // 2. 채팅방 삭제
  group('채팅방 삭제', () => {
    totalChats = deleteChats(token);
  });
  
  console.log(`✅ [User ${userId}] 완료 - 이력서: ${totalResumes}개, 채팅: ${totalChats}개 삭제`);
}

export function handleSummary(data) {
  console.log('');
  console.log('═══════════════════════════════════════════');
  console.log('🧹 Cleanup Summary');
  console.log('═══════════════════════════════════════════');
  console.log('');
  
  const totalReqs = data.metrics.http_reqs?.values.count || 0;
  const resumeDeletes = data.metrics.http_reqs?.values.count || 0; // 실제로는 태그별로 집계
  
  console.log(`📊 총 요청 수: ${totalReqs.toFixed(0)}개`);
  console.log(`🗑️  삭제 작업 완료`);
  console.log('');
  
  console.log('💡 추가 정리 (수동):');
  console.log('');
  console.log('   1. S3 파일 정리:');
  console.log('      aws s3 rm s3://refit-bucket/resumes/ --recursive --dryrun');
  console.log('      (--dryrun 제거 후 실행)');
  console.log('');
  console.log('   2. DB 직접 정리 (백엔드 권한 있을 때):');
  console.log('      DELETE FROM chat_messages WHERE chat_room_id IN (SELECT id FROM chat_rooms WHERE requester_id BETWEEN 1 AND 500 OR receiver_id BETWEEN 1 AND 500);');
  console.log('      DELETE FROM chat_rooms WHERE requester_id BETWEEN 1 AND 500 OR receiver_id BETWEEN 1 AND 500;');
  console.log('      DELETE FROM resumes WHERE user_id BETWEEN 1 AND 500;');
  console.log('');
  
  console.log('═══════════════════════════════════════════');
  console.log('');
  
  return {
    './results/cleanup-summary.json': JSON.stringify(data, null, 2),
  };
}
