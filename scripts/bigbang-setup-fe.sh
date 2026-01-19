#!/bin/bash
set -e

# ============================================
# Re-Fit 프론트엔드 초기 설정 스크립트
# Ubuntu 인스턴스용
# ============================================

echo "============================================"
echo "프론트엔드 초기 설정 시작"
echo "============================================"

# 1. Node.js 설치 (NVM 사용)
echo "[1/6] Node.js 설치 확인..."
if ! command -v node &> /dev/null; then
    echo "Node.js가 없습니다. NVM으로 설치합니다..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install 22
    nvm use 22
else
    echo "Node.js 버전: $(node -v)"
fi

# 2. pnpm 설치
echo "[2/6] pnpm 설치 확인..."
if ! command -v pnpm &> /dev/null; then
    echo "pnpm 설치 중..."
    npm install -g pnpm
else
    echo "pnpm 버전: $(pnpm -v)"
fi

# 3. PM2 설치
echo "[3/6] PM2 설치 확인..."
if ! command -v pm2 &> /dev/null; then
    echo "PM2 설치 중..."
    npm install -g pm2
else
    echo "PM2 버전: $(pm2 -v)"
fi

# 4. 프로젝트 및 인프라 디렉토리 생성
echo "[4/6] 디렉토리 구조 설정..."
FE_DIR=~/refit/app/frontend
INFRA_DIR=~/infra/pm2

# 부모 디렉토리들 생성
mkdir -p ~/refit/app
mkdir -p $INFRA_DIR

if [ ! -d "$FE_DIR" ]; then
    echo "프로젝트 디렉토리 준비 완료: ~/refit/app"
else
    echo "프로젝트 디렉토리가 이미 존재합니다: $FE_DIR"
fi

# 5. 격리된 로그 및 백업 디렉토리 생성
echo "[5/6] 서비스별 로그/백업 디렉토리 생성..."
mkdir -p ~/refit/backups/frontend
mkdir -p ~/refit/logs/frontend

# 6. 환경 변수 로드 설정 (NVM 경로 인식 문제 방지)
echo "[6/6] .bashrc 설정 확인..."
if ! grep -q "NVM_DIR" ~/.bashrc; then
    echo "NVM 환경 변수를 .bashrc에 추가합니다."
fi

echo "============================================"
echo "초기 설정 완료!"
echo "============================================"
echo ""
echo "다음 단계 (실행 필수):"
echo "1. 프로젝트 클론: git clone <repo-url> ~/refit/app/frontend"
echo "2. 인프라 설정 이동: ecosystem.config.js를 $INFRA_DIR 로 이동"
echo "3. 환경 변수 설정: ~/refit/app/frontend/.env.production 생성"
echo "4. 배포 실행: ./deploy.sh"
echo ""