#!/bin/bash

# ================================================
# AI 서비스 systemd → PM2 전환 스크립트
# ================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

AI_DIR="/home/ubuntu/refit/app/ai"
PM2_CONFIG="/home/ubuntu/refit/infra/pm2/ecosystem.ai.config.js"
LOG_DIR="/home/ubuntu/refit/logs/ai"

echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW}AI 서비스 systemd → PM2 전환 시작${NC}"
echo -e "${YELLOW}============================================${NC}"

# 1. 로그 디렉토리 생성
echo -e "\n[1/5] 로그 디렉토리 준비..."
mkdir -p $LOG_DIR
echo -e "${GREEN}✅ 로그 디렉토리 생성 완료${NC}"

# 2. systemd 서비스 확인 및 중지
echo -e "\n[2/5] systemd 서비스 중지..."
if systemctl is-active --quiet fastapi; then
    echo "기존 systemd 서비스 중지 중..."
    sudo systemctl stop fastapi
    echo -e "${GREEN}✅ systemd 서비스 중지 완료${NC}"
else
    echo "systemd 서비스가 실행 중이지 않습니다."
fi

if systemctl is-enabled --quiet fastapi 2>/dev/null; then
    echo "systemd 서비스 자동 시작 비활성화 중..."
    sudo systemctl disable fastapi
    echo -e "${GREEN}✅ systemd 자동 시작 비활성화 완료${NC}"
fi

# 3. PM2 설치 확인
echo -e "\n[3/5] PM2 설치 확인..."
if ! command -v pm2 &> /dev/null; then
    echo -e "${RED}❌ PM2가 설치되지 않았습니다.${NC}"
    echo "다음 명령어로 PM2를 설치하세요:"
    echo "  npm install -g pm2"
    exit 1
fi
echo -e "${GREEN}✅ PM2가 설치되어 있습니다 ($(pm2 --version))${NC}"

# 4. PM2로 AI 서비스 시작
echo -e "\n[4/5] PM2로 AI 서비스 시작..."
cd $AI_DIR

# 기존 PM2 프로세스 확인
if pm2 describe ai-service > /dev/null 2>&1; then
    echo "기존 PM2 프로세스 제거 중..."
    pm2 delete ai-service
fi

# PM2 시작
pm2 start $PM2_CONFIG
echo -e "${GREEN}✅ PM2로 AI 서비스 시작 완료${NC}"

# 5. PM2 자동 시작 설정
echo -e "\n[5/5] PM2 자동 시작 설정..."
pm2 save
echo -e "${GREEN}✅ PM2 상태 저장 완료${NC}"

# PM2 startup 확인
if ! pm2 startup | grep -q "already"; then
    echo -e "${YELLOW}⚠️  PM2 startup이 설정되지 않았습니다.${NC}"
    echo "다음 명령어를 실행하세요 (sudo 필요):"
    echo -e "${YELLOW}  pm2 startup systemd${NC}"
else
    echo -e "${GREEN}✅ PM2 startup 이미 설정됨${NC}"
fi

# 6. 헬스 체크
echo -e "\n[6/6] 서비스 헬스 체크..."
sleep 3

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}✅ AI 서비스 정상 작동 중! (HTTP $HTTP_STATUS)${NC}"
else
    echo -e "${RED}❌ 헬스 체크 실패! (HTTP $HTTP_STATUS)${NC}"
    echo "로그 확인: pm2 logs ai-service"
    exit 1
fi

# 완료
echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}✅ systemd → PM2 전환 완료!${NC}"
echo -e "${GREEN}============================================${NC}"

echo -e "\n${YELLOW}유용한 PM2 명령어:${NC}"
echo "  pm2 list              - 모든 프로세스 확인"
echo "  pm2 logs ai-service   - 로그 확인"
echo "  pm2 monit             - 실시간 모니터링"
echo "  pm2 restart ai-service - 재시작"
echo "  pm2 reload ai-service  - 무중단 재시작"
echo "  pm2 stop ai-service    - 중지"
echo ""
