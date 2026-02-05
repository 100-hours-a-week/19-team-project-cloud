/**
 * generate-tokens.js
 * 백엔드와 동일한 구조로 JWT를 직접 생성하여 test-users.json으로 저장
 *
 * 백엔드 JwtUtil에서 디콤파일로 확인한 구조:
 *   - algorithm : HS256
 *   - header   : { typ: "JWT" }  (jjwt 기본)
 *   - issuer   : "re-fit"        (application.yml)
 *   - subject  : String(userId)
 *   - iat      : 현재 시간
 *   - exp      : iat + accessExpMs (600000 = 10분)
 *   - claim    : { typ: "access" }
 *   - secret   : application-secret.yml의 jwt.secret
 */

const crypto = require('crypto');
const fs     = require('fs');
const path   = require('path');

// ─── 백엔드와 동일한 설정값 ───
const SECRET       = 'dlfrngkwh19!dlfrngkwh19!dlfrngkwh19!dlfrngkwh19!dlfrngkwh19!dlfrngkwh19!';
const ISSUER       = 're-fit';
const ACCESS_EXP_MS = 600000; // 10분

// DB에 실제로 존재하는 JOB_SEEKER 유저 ID (20명)
const JOB_SEEKER_IDS = [2,3,4,5,6,7,8,9,10,11,12,13,14,23,24,25,28,29,31,32];

// ─── JWT 생성 (jjwt와 동일한 방식) ───
function base64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function createAccessToken(userId) {
  const now = Date.now();

  const header = { alg: 'HS256', typ: 'JWT' };
  const payload = {
    iss: ISSUER,
    sub: String(userId),
    iat: Math.floor(now / 1000),
    exp: Math.floor((now + ACCESS_EXP_MS) / 1000),
    typ: 'access',
  };

  const headerEncoded  = base64url(Buffer.from(JSON.stringify(header)));
  const payloadEncoded = base64url(Buffer.from(JSON.stringify(payload)));
  const signingInput   = `${headerEncoded}.${payloadEncoded}`;

  const signature = crypto
    .createHmac('sha256', SECRET)
    .update(signingInput)
    .digest();

  const signatureEncoded = base64url(signature);

  return `${signingInput}.${signatureEncoded}`;
}

// ─── 실행 ───
console.log('🔐 토큰 생성 시작');
console.log(`   유저 수    : ${JOB_SEEKER_IDS.length} (JOB_SEEKER)`);
console.log(`   만료 시간  : 30분`);
console.log('');

const users = JOB_SEEKER_IDS.map(id => ({
  user_id: id,
  token:   createAccessToken(id),
}));

// ─── data/ 폴더 생성 및 저장 ───
const outputDir  = path.join(__dirname, 'data');
const outputPath = path.join(outputDir, 'test-users.json');

if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir);
}
fs.writeFileSync(outputPath, JSON.stringify(users, null, 2));

console.log(`📊 완료: ${users.length}/${JOB_SEEKER_IDS.length} 생성`);
console.log(`💾 저장 완료: ${outputPath}`);
console.log('');
console.log('⚠️  토큰 만료 시간 30분 내에 테스트를 실행하세요!');