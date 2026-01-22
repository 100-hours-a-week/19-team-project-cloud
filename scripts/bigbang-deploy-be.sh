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
BRANCH=develop
REPO_URL="https://github.com/100-hours-a-week/19-team-project-be.git"
PROJECT_DIR="$BE_DIR/refit-backend"
JAR_PATH="$PROJECT_DIR/build/libs/$JAR_NAME"
# 서버에만 존재하는 민감 설정 파일(깃에 올리지 않음)
# - CI/CD에서는 GitHub Secrets로 주입하지만, 수동 배포에서는 서버 로컬 파일을 주입한다.
SECRET_YML="/home/ubuntu/refit/secret/backend/application-secret.yml"

echo "============================================"
echo "Re-Fit BE 배포 시작: $(date)"
echo "============================================"

# 0. 로그 및 디렉토리 준비
mkdir -p $LOG_DIR $BACKUP_DIR

# 1. 백업 (롤백용)
if [ -f "$JAR_PATH" ]; then
    cp "$JAR_PATH" "$BACKUP_DIR/backend-$TIMESTAMP.jar"
    echo -e "${GREEN}백업 완료: $BACKUP_DIR/backend-$TIMESTAMP.jar${NC}"
fi

# 2. 소스 업데이트
if [ ! -d "$BE_DIR/.git" ]; then
    echo -e "${YELLOW}백엔드 레포가 없습니다. 클론을 진행합니다...${NC}"
    mkdir -p "$(dirname "$BE_DIR")"
    rm -rf "$BE_DIR"
    git clone --single-branch -b "$BRANCH" "$REPO_URL" "$BE_DIR"
else
    echo -e "${GREEN}기존 레포 발견. $BRANCH 브랜치로 업데이트합니다...${NC}"
    cd "$BE_DIR"
    # origin이 없거나 다른 경우 대비
    if ! git remote get-url origin > /dev/null 2>&1; then
        git remote add origin "$REPO_URL"
    fi
    git fetch origin --prune "$BRANCH"
    git checkout "$BRANCH"
    git pull --ff-only origin "$BRANCH" || {
        echo -e "${YELLOW}경고: fast-forward pull 실패. 서버 로컬 파일(시크릿 주입 등) 충돌 가능성이 있어 hard reset을 수행합니다.${NC}"
        git reset --hard "origin/$BRANCH"
    }
fi

# 3. 설정 파일 주입 (application-secret.yml)
# - 레포에는 민감정보가 없으므로, 서버 로컬 보관본을 배포 시점에 주입한다.
TARGET_SECRET_YML="$PROJECT_DIR/src/main/resources/application-secret.yml"

if [ ! -f "$SECRET_YML" ]; then
    echo -e "${RED}에러: 서버 시크릿 설정 파일이 없습니다: $SECRET_YML${NC}"
    echo -e "${YELLOW}해결: $SECRET_YML 경로에 application-secret.yml을 배치하세요.${NC}"
    exit 1
fi

mkdir -p "$(dirname "$TARGET_SECRET_YML")"
cp "$SECRET_YML" "$TARGET_SECRET_YML"

# git pull 시 로컬 주입 파일이 수정으로 잡혀도 방해되지 않도록(서버에서만)
cd "$BE_DIR"
git update-index --skip-worktree "refit-backend/src/main/resources/application-secret.yml" 2>/dev/null || true

if [ ! -f "$TARGET_SECRET_YML" ]; then
    echo -e "${RED}에러: application-secret.yml 주입에 실패했습니다: $TARGET_SECRET_YML${NC}"
    exit 1
fi

# 4. 빌드
echo "빌드 중... (잠시 시간이 걸릴 수 있습니다)"
cd "$PROJECT_DIR"
./gradlew clean bootJar --no-daemon

if [ ! -f "$JAR_PATH" ]; then
    echo -e "${RED}에러: 빌드 산출물 JAR을 찾을 수 없습니다: $JAR_PATH${NC}"
    exit 1
fi

# 5. 권한 확인 및 수정
echo "권한 확인 중..."
sudo chown -R ubuntu:ubuntu "$PROJECT_DIR/.gradle" "$PROJECT_DIR/build" 2>/dev/null || true

# 6. PM2를 이용한 무중단 재시작 (reload)
if pm2 describe $APP_NAME > /dev/null 2>&1; then
    # 기존 프로세스가 오래된 jar 경로를 물고 있을 수 있어, delete 후 올바른 jar로 재기동
    echo "기존 프로세스 교체 (Delete + Start)..."
    pm2 delete $APP_NAME || true
    pm2 start /usr/bin/java --name "$APP_NAME" -- -jar "$JAR_PATH"
else
    echo "신규 프로세스 시작..."
    # ecosystem.config.js에 backend가 없을 수 있으므로, 직접 java -jar 로 기동
    pm2 start /usr/bin/java --name "$APP_NAME" -- -jar "$JAR_PATH"
fi

# 7. Caddy 리로드
if systemctl is-active --quiet caddy; then
    sudo systemctl reload caddy
fi

# 8. 배포 검증
echo "배포 검증 중 (초기 10초 대기)..."
sleep 10

MAX_RETRIES=18
RETRY_INTERVAL=5
HEALTH_URLS=("https://re-fit.kr/api/actuator/health")
OK_URL=""

for i in $(seq 1 $MAX_RETRIES); do
    echo "헬스 체크 시도 $i/$MAX_RETRIES..."
    for url in "${HEALTH_URLS[@]}"; do
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        echo "  - $url -> HTTP $HTTP_STATUS"
        if [ "$HTTP_STATUS" = "200" ]; then
            OK_URL="$url"
            break
        fi
    done
    [ -n "$OK_URL" ] && break
    [ $i -lt $MAX_RETRIES ] && sleep $RETRY_INTERVAL
done

if [ -n "$OK_URL" ]; then
    echo -e "${GREEN}배포 성공! ($OK_URL)${NC}"
    pm2 save
else
    echo -e "${YELLOW}배포 이상 감지! 헬스체크가 200을 반환하지 않습니다.${NC}"
    echo "PM2 상태:"
    pm2 status || true
    echo "포트 리스닝 확인:"
    ss -ltnp 2>/dev/null | grep -E ':8080\\b' || true
    echo "백엔드 로그 (최근 80줄):"
    pm2 logs $APP_NAME --lines 80 --nostream || true
fi

echo "============================================"
echo "Re-Fit BE 배포 완료: $(date)"
echo "============================================"
