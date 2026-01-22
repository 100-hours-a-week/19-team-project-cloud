#!/bin/bash
set -e

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

AI_DIR=/home/ubuntu/refit/app/ai
LOG_DIR=/home/ubuntu/refit/logs/ai
BACKUP_DIR=/home/ubuntu/refit/backups/ai
PORT=8000
TIMESTAMP=$(date +%Y%m%d%H%M%S)

echo "============================================"
echo "Re-Fit AI 배포 시작: $(date)"
echo "============================================"

# 0. 로그 및 디렉토리 준비
mkdir -p $LOG_DIR $BACKUP_DIR

# 1. 기존 AI 프로세스 종료
echo "[1/6] 기존 AI 프로세스 종료..."
sudo systemctl reload caddy

# 2. 기존 프로세스 정리 및 DB 백업
echo "[2/6] 기존 프로세스 정리 및 DB 백업..."
sudo systemctl stop fastapi || true

if [ -d "$AI_DIR/ai_app" ]; then
    cp -r "$AI_DIR/ai_app" "$BACKUP_DIR/ai-$TIMESTAMP"
    echo -e "${GREEN}백업 완료: $BACKUP_DIR/ai-$TIMESTAMP${NC}"
fi

# 3. 소스 코드 업데이트
echo "[3/6] 소스 코드 업데이트..."
cd $AI_DIR
git pull origin main

# 4. 가상환경 활성화 및 의존성 설치
echo "[4/6] 가상환경 활성화 및 의존성 설치..."
if [ -d "venv" ]; then
    source venv/bin/activate
else
    python3 -m venv venv
    source venv/bin/activate
fi

if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
else
    echo -e "${YELLOW}requirements.txt 파일이 없습니다. 최소 필수 패키지를 설치합니다.${NC}"
    pip install fastapi uvicorn
fi

# 5. AI 서비스 재기동
echo "[5/6] AI 서비스 재기동..."
sudo systemctl restart fastapi

sleep 2
# 6. AI 헬스 체크 수행
echo "[6/6] AI 헬스 체크 수행..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/health 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}배포 성공! (HTTP $HTTP_STATUS)${NC}"
else
    echo -e "${RED}헬스 체크 실패! 배포 중 오류 발생. (HTTP $HTTP_STATUS)${NC}"
    echo "에러 확인: sudo journalctl -u fastapi -n 50"
    exit 1
fi

echo "============================================"
echo "Re-Fit AI 배포 완료: $(date)"
echo "============================================"