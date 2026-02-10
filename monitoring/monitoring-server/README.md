# Monitoring Server Configurations

이 디렉토리는 환경별 모니터링 서버 설정을 관리합니다.

## 디렉토리 구조

```
monitoring-server/
├── dev/                    # 개발 환경 모니터링 설정
│   ├── docker-compose.yml
│   ├── grafana/
│   ├── loki/
│   └── prometheus/
└── prod/                   # 운영 환경 모니터링 설정 (추후 추가)
```

## 환경별 설정

### Dev 환경
- **서버 IP**: 54.180.38.125 (Public), 10.1.2.163 (Private)
- **대상 서버**: 43.200.140.74 (App Server)
- **Grafana**: http://54.180.38.125:3000
- **스택**: Loki, Prometheus, Grafana

### Prod 환경
- 추후 운영 환경 구축 시 설정 추가 예정

## 배포 방법

### Dev 환경 배포
```bash
# 서버 접속
ssh ubuntu@54.180.38.125

# 설정 파일 업로드
scp -r dev ubuntu@54.180.38.125:~/monitoring-server/

# 배포
cd ~/monitoring-server/dev
docker-compose up -d
```

### Prod 환경 배포
```bash
# 추후 작성 예정
```

## 참고 문서
- [IMPLEMENTATION.md](../IMPLEMENTATION.md) - 전체 구축 과정
- [OBSERVABILITY_GUIDE.md](../OBSERVABILITY_GUIDE.md) - 초기 가이드
