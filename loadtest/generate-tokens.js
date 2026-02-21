/**
 * generate-tokens.js
 * 
 * Re-Fit 부하테스트용 JWT 토큰 생성
 * 환경변수(.env)에서 설정값 로드
 * 
 * 사용법:
 *   node generate-tokens.js
 * 
 * 출력:
 *   ./data/test-users.json
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
require('dotenv').config(); // .env 파일 로드

// ════════════════════════════════════════════════════════════════════
// ⚙️ 환경변수에서 설정 로드
// ════════════════════════════════════════════════════════════════════

const SECRET = process.env.JWT_SECRET;
const ISSUER = process.env.JWT_ISSUER || 're-fit';
const ACCESS_EXP_MS = parseInt(process.env.JWT_ACCESS_EXP_MS || '600000', 10);

// 테스트 유저 ID (쉼표로 구분된 문자열 → 배열)
const TEST_USER_IDS = process.env.TEST_USER_IDS
  ? process.env.TEST_USER_IDS.split(',').map(id => parseInt(id.trim(), 10))
  : [];

// ════════════════════════════════════════════════════════════════════
// ✅ 환경변수 검증
// ════════════════════════════════════════════════════════════════════

function validateEnv() {
  const errors = [];

  if (!SECRET) {
    errors.push('❌ JWT_SECRET이 설정되지 않았습니다.');
  }

  if (SECRET && SECRET.length < 32) {
    errors.push('⚠️  JWT_SECRET이 너무 짧습니다 (최소 32자 권장).');
  }

  if (TEST_USER_IDS.length === 0) {
    errors.push('❌ TEST_USER_IDS가 설정되지 않았습니다.');
  }

  if (TEST_USER_IDS.some(id => isNaN(id))) {
    errors.push('❌ TEST_USER_IDS에 유효하지 않은 ID가 있습니다.');
  }

  if (errors.length > 0) {
    console.error('');
    console.error('═══════════════════════════════════════════');
    console.error('🚨 환경변수 오류');
    console.error('═══════════════════════════════════════════');
    console.error('');
    errors.forEach(err => console.error(`   ${err}`));
    console.error('');
    console.error('📌 해결 방법:');
    console.error('   1. .env 파일이 있는지 확인');
    console.error('   2. .env.example을 복사: cp .env.example .env');
    console.error('   3. .env 파일에 실제 값 입력');
    console.error('');
    console.error('═══════════════════════════════════════════');
    console.error('');
    process.exit(1);
  }
}

// ════════════════════════════════════════════════════════════════════
// 🔐 JWT 생성 함수
// ════════════════════════════════════════════════════════════════════

function base64url(buf) {
  return buf
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

function createAccessToken(userId) {
  const now = Date.now();

  const header = {
    alg: 'HS256',
    typ: 'JWT',
  };

  const payload = {
    iss: ISSUER,
    sub: String(userId),
    iat: Math.floor(now / 1000),
    exp: Math.floor((now + ACCESS_EXP_MS) / 1000),
    typ: 'access',
  };

  const headerEncoded = base64url(Buffer.from(JSON.stringify(header)));
  const payloadEncoded = base64url(Buffer.from(JSON.stringify(payload)));
  const signingInput = `${headerEncoded}.${payloadEncoded}`;

  const signature = crypto
    .createHmac('sha256', SECRET)
    .update(signingInput)
    .digest();

  const signatureEncoded = base64url(signature);

  return `${signingInput}.${signatureEncoded}`;
}

// ════════════════════════════════════════════════════════════════════
// 🚀 실행
// ════════════════════════════════════════════════════════════════════

// 환경변수 검증
validateEnv();

console.log('');
console.log('═══════════════════════════════════════════');
console.log('🔐 Re-Fit 부하테스트 토큰 생성');
console.log('═══════════════════════════════════════════');
console.log('');
console.log('⚙️  설정:');
console.log(`   JWT Issuer: ${ISSUER}`);
console.log(`   토큰 만료: ${ACCESS_EXP_MS / 60000}분`);
console.log(`   테스트 유저: ${TEST_USER_IDS.length}명`);
console.log('');

// 토큰 생성 (user_id = users.id, JWT sub claim)
const users = TEST_USER_IDS.map(id => ({
  user_id: id,   // users 테이블 id와 매핑
  token: createAccessToken(id),
}));

// data/ 폴더 생성
const dataDir = path.join(__dirname, 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

// test-users.json 저장
const outputPath = path.join(dataDir, 'test-users.json');
fs.writeFileSync(outputPath, JSON.stringify(users, null, 2), 'utf-8');

console.log('✅ 토큰 생성 완료!');
console.log('');
console.log(`📁 저장 위치: ${outputPath}`);
console.log(`📝 생성된 유저: ${users.length}명`);
console.log('');
console.log('⚠️  주의사항:');
console.log(`   - ${ACCESS_EXP_MS / 60000}분 내에 테스트를 시작하세요`);
console.log('   - 토큰 만료 시 이 스크립트를 다시 실행하세요');
console.log('   - test-users.json은 Git에 커밋하지 마세요');
console.log('');
console.log('📌 다음 단계:');
console.log('   1. k6 run scripts/1-baseline.js');
console.log('   2. 또는 ./run-all-tests.sh');
console.log('');
console.log('═══════════════════════════════════════════');
console.log('');