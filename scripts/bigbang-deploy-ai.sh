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
echo "[1/5] 기존 AI 프로세스 종료..."
pkill -f "uvicorn main:app" || true
pkill -f "uvicorn api.main:app" || true
# 포트를 사용하는 프로세스 종료
if lsof -ti:$PORT > /dev/null 2>&1; then
    lsof -ti:$PORT | xargs kill -9 || true
fi
sleep 2

# 2. 소스 코드 업데이트
echo "[2/5] 소스 코드 업데이트..."
cd $AI_DIR
git pull origin main

# 3. 가상환경 활성화 및 의존성 설치
echo "[3/5] 가상환경 활성화 및 의존성 설치..."
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

# 4. AI 서비스 재기동
echo "[4/5] AI 서비스 재기동..."
cd "$AI_DIR/ai_app"
nohup "$AI_DIR/venv/bin/python" -m uvicorn api.main:app \
  --host 0.0.0.0 \
  --port $PORT \
  > "$AI_DIR/ai.log" 2>&1 &

sleep 2

# 5. AI 헬스 체크 수행
echo "[5/5] AI 헬스 체크 수행..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/health 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}배포 성공! (HTTP $HTTP_STATUS)${NC}"
else
    echo -e "${RED}헬스 체크 실패! 배포 중 오류 발생. (HTTP $HTTP_STATUS)${NC}"
    exit 1
fi

echo "============================================"
echo "Re-Fit AI 배포 완료: $(date)"
echo "============================================"
