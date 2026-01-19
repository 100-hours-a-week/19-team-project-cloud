#!/bin/bash
set -e

FE_DIR=~/app/frontend
BACKUP_DIR=~/backups
TIMESTAMP=$(date +%Y%m%d%H%M%S)

echo "============================================"
echo "프론트엔드 배포 시작: $(date)"
echo "============================================"

# 1. 백업
echo "[1/5] 현재 버전 백업..."
if [ -d /srv/frontend ] && [ "$(ls -A /srv/frontend 2>/dev/null)" ]; then
    mkdir -p $BACKUP_DIR
    cp -r /srv/frontend $BACKUP_DIR/frontend-$TIMESTAMP
    echo "백업 완료: $BACKUP_DIR/frontend-$TIMESTAMP"
fi

# 2. 소스 업데이트
echo "[2/5] 소스 코드 업데이트..."
cd $FE_DIR
git pull

# 3. 의존성 설치
echo "[3/5] 의존성 설치..."
pnpm install

# 4. 빌드
echo "[4/5] 프로덕션 빌드..."
pnpm run build

# 5. 배포
echo "[5/5] 배포..."
sudo rm -rf /srv/frontend/*
sudo cp -r build/* /srv/frontend/
sudo chown -R www-data:www-data /srv/frontend
sudo systemctl reload caddy

echo "============================================"
echo "프론트엔드 배포 완료!"
echo "============================================"