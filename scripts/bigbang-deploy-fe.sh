#!/bin/bash
set -e

FE_DIR=~/refit/app/frontend
LOG_DIR=~/refit/logs/frontend
BACKUP_DIR=~/refit/backups/frontend
PM2_CONFIG=~/refit/infra/pm2/ecosystem.config.js
TIMESTAMP=$(date +%Y%m%d%H%M%S)
APP_NAME="frontend"

echo "============================================"
echo "Re-Fit FE 배포 시작: $(date)"
echo "============================================"

# 0. 로그 및 디렉토리 준비
mkdir -p $LOG_DIR $BACKUP_DIR

# 1. 백업 (롤백용)
if [ -d "$FE_DIR/.next" ]; then
    cp -r $FE_DIR/.next $BACKUP_DIR/frontend-$TIMESTAMP
    echo "백업 완료: $BACKUP_DIR/frontend-$TIMESTAMP"
fi

# 2. 소스 업데이트 및 설치
cd $FE_DIR
git pull origin main
pnpm install --frozen-lockfile

# 3. 환경 변수 체크
if [ ! -f .env.production ]; then
    echo "❌ 에러: .env.production 파일이 없습니다. 배포를 중단합니다."
    exit 1
fi

# 4. 빌드 (SSR 서버 기능 포함)
echo "빌드 중... (잠시 시간이 걸릴 수 있습니다)"
pnpm run build

# 5. PM2를 이용한 무중단 재시작 (reload)
if pm2 describe $APP_NAME > /dev/null 2>&1; then
    echo "기존 프로세스 재시작 (Reload)..."
    pm2 reload $PM2_CONFIG --env production
else
    echo "신규 프로세스 시작..."
    pm2 start $PM2_CONFIG --env production
fi

# 6. Caddy 리로드
if systemctl is-active --quiet caddy; then
    sudo systemctl reload caddy
fi

# 7. 배포 검증
echo "배포 검증 중 (5초 대기)..."
sleep 5
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ 배포 성공! (HTTP 200)"
    pm2 save
else
    echo "⚠️ 배포 이상 감지! (HTTP $HTTP_STATUS) 로그를 확인하세요: pm2 logs $APP_NAME"
fi