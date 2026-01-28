# PM2 설정 가이드

## ⚠️ 보안 주의사항

**절대로 PM2 설정 파일에 API 키, 비밀번호 등을 하드코딩하지 마세요!**

---

## 🔒 안전한 환경 변수 설정 방법

### 1. 서버에 `.env` 파일 생성

```bash
# SSH 접속
ssh ubuntu@your-server-ip

# .env 파일 생성 (AI 서비스)
sudo -u ubuntu nano /home/ubuntu/refit/app/ai/.env
```

### 2. `.env` 파일 내용 (예시)

```bash
# Google API Key (Gemini)
GOOGLE_API_KEY=your_google_api_key_here

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/dbname

# Backend API
BACKEND_API_URL=https://re-fit.kr/

# CloudWatch
CLOUDWATCH_METRICS_ENABLED=true
ENVIRONMENT=production
AWS_REGION=ap-northeast-2
```

### 3. 권한 설정 (중요!)

```bash
# 소유자만 읽기/쓰기 가능
chmod 600 /home/ubuntu/refit/app/ai/.env
chown ubuntu:ubuntu /home/ubuntu/refit/app/ai/.env
```

### 4. PM2 재시작

```bash
sudo -u ubuntu pm2 restart ai-service
sudo -u ubuntu pm2 save
```

---

## 🔍 환경 변수 확인

```bash
# PM2로 환경 변수 확인 (민감 정보 제외하고 확인)
pm2 env 0

# 로그에서 확인
pm2 logs ai-service --lines 20
```

---

## 📝 새 팀원 온보딩

1. **Google API Key 발급**:
   - https://console.cloud.google.com/apis/credentials
   - "Create Credentials" → "API Key"
   - API 제한 설정 (Gemini API만 허용)

2. **서버 접속 권한 요청**:
   - SSH 키 등록
   - `.env` 파일 접근 권한

3. **환경 변수 설정**:
   - 위 가이드 참고

---

## ⚠️ 절대 하지 말아야 할 것

- ❌ API 키를 코드에 직접 입력
- ❌ API 키를 PM2 설정 파일에 하드코딩
- ❌ `.env` 파일을 Git에 커밋
- ❌ 공개 채널(Slack, Discord 등)에 API 키 공유

---

## ✅ 해야 할 것

- ✅ `.env` 파일 사용
- ✅ `.gitignore`에 `.env` 추가 확인
- ✅ API 키는 1:1 DM으로만 공유
- ✅ 유출 시 즉시 키 재발급

---

## 🚨 API 키 유출 시 대응

1. **즉시 키 삭제**: Google Cloud Console에서 기존 키 삭제
2. **새 키 발급**: 새로운 API 키 생성
3. **서버 업데이트**: `.env` 파일 수정
4. **PM2 재시작**: `pm2 restart ai-service`
5. **Git 히스토리 정리**: (아래 참고)

### Git 히스토리에서 민감 정보 제거

```bash
# BFG Repo-Cleaner 사용 (권장)
# https://rtyley.github.io/bfg-repo-cleaner/

# 또는 git filter-branch (주의 필요!)
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch pm2/ecosystem.ai.config.js" \
  --prune-empty --tag-name-filter cat -- --all

# Force push (팀원들과 조율 필요!)
git push origin --force --all
```

---

## 📞 문제 발생 시

- 클라우드 팀에 문의
- 또는 팀 리더에게 연락
