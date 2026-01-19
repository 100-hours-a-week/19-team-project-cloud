#!/bin/bash
set -e

# =============================================
# AI Big Bang 배포 스크립트
# - 기존 AI 프로세스를 완전히 종료
# - 최신 코드로 교체
# - AI 서비스 재기동
# =============================================

DEPLOY_TIME=$(date "+%Y-%m-%d %H:%M:%S")

echo "============================================"
echo "AI Big Bang 배포 시작: $DEPLOY_TIME"
echo "============================================"

# AI 애플리케이션 디렉토리
APP_DIR="$HOME/refit/app/ai"
PORT=8000

echo "[1/5] 기존 AI 프로세스 종료..."
pkill -f "uvicorn main:app" || true
pkill -f "port $PORT" || true

sleep 2

echo "[2/5] 소스 코드 업데이트..."
cd $APP_DIR
git pull origin main

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
    echo "requirements.txt 파일이 없습니다. 최소 필수 패키지를 설치합니다."
    pip install fastapi uvicorn
fi

echo "[4/5] AI 서비스 재기동..."
cd "$APP_DIR/ai_app"
nohup "$APP_DIR/venv/bin/python" -m uvicorn api.main:app \
  --host 0.0.0.0 \
  --port $PORT \
  > "$APP_DIR/ai.log" 2>&1 &

sleep 2

echo "[5/5] AI 헬스 체크 수행..."
curl -s http://localhost:$PORT/health || {
    echo "헬스 체크 실패! 배포 중 오류 발생."
    echo " 배포 실패: $DEPLOY_TIME"
    exit 1
}

echo "============================================"
echo "AI Big Bang 배포 완료!"
echo " 배포 완료: $DEPLOY_TIME"
echo "============================================"