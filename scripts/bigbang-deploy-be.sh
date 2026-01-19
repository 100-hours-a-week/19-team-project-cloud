#!/bin/bash
set -e

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

BE_DIR=/home/ubuntu/refit/app/backend
LOG_DIR=/home/ubuntu/refit/logs/backend
BACKUP_DIR=/home/ubuntu/refit/backups/backend
PM2_CONFIG=/home/ubuntu/refit/infra/pm2/ecosystem.config.js
TIMESTAMP=$(date +%Y%m%d%H%M%S)
APP_NAME="backend"
JAR_NAME="refit-backend-0.0.1-SNAPSHOT.jar"

echo "============================================"
echo "Re-Fit BE 배포 시작: $(date)"
echo "============================================"

# 0. 로그 및 디렉토리 준비
mkdir -p $LOG_DIR $BACKUP_DIR

# 1. 백업 (롤백용)
if [ -f "$BE_DIR/build/libs/$JAR_NAME" ]; then
    cp $BE_DIR/build/libs/$JAR_NAME $BACKUP_DIR/backend-$TIMESTAMP.jar
    echo -e "${GREEN}백업 완료: $BACKUP_DIR/backend-$TIMESTAMP.jar${NC}"
fi

# 2. 소스 업데이트
cd $BE_DIR
git pull origin main

# 3. 환경 변수 체크 (application-prod.yml 확인)
if [ ! -f "src/main/resources/application-prod.yml" ]; then
    echo -e "${RED}에러: application-prod.yml 파일이 없습니다. 배포를 중단합니다.${NC}"
    exit 1
fi

# 4. 빌드
echo "빌드 중... (잠시 시간이 걸릴 수 있습니다)"
./gradlew clean build -x test --no-daemon

# 5. 권한 확인 및 수정
echo "권한 확인 중..."
sudo chown -R ubuntu:ubuntu $BE_DIR/.gradle $BE_DIR/build 2>/dev/null || true

# 6. PM2를 이용한 무중단 재시작 (reload)
if pm2 describe $APP_NAME > /dev/null 2>&1; then
    echo "기존 프로세스 재시작 (Reload)..."
    pm2 reload $APP_NAME
else
    echo "신규 프로세스 시작..."
    pm2 start $PM2_CONFIG --only $APP_NAME --env production
fi

# 7. Caddy 리로드
if systemctl is-active --quiet caddy; then
    sudo systemctl reload caddy
fi

# 8. 배포 검증
echo "배포 검증 중 (10초 대기)..."
sleep 10
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/actuator/health 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "404" ]; then
    echo -e "${GREEN}배포 성공! (HTTP $HTTP_STATUS)${NC}"
    pm2 save
else
    echo -e "${YELLOW}배포 이상 감지! (HTTP $HTTP_STATUS) 로그를 확인하세요: pm2 logs $APP_NAME${NC}"
fi

echo "============================================"
echo "Re-Fit BE 배포 완료: $(date)"
echo "============================================"
