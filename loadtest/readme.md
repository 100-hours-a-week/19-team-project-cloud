load-tests/
├── data/
│   ├── test-users.json          # 자동 생성됨
│   └── sample_resume_3mb.pdf    # 기존 파일
├── scripts/
│   ├── config.js                # 공통 설정 & 헬퍼 함수
│   ├── 1-baseline.js            # 정상 상태 측정
│   ├── 2-load-test.js           # 일반 부하 테스트
│   ├── 3-stress-test.js         # Breaking Point 탐색
│   ├── 4-spike-test.js          # 급증 대응력 테스트
│   └── 9-cleanup.js             # 테스트 데이터 정리
├── results/                      # 테스트 결과 저장
├── generate-tokens.js           # JWT 토큰 생성
├── run-all-tests.sh            # 전체 자동 실행
├── run-single-test.sh          # 개별 테스트 실행
└── README.md                    # 사용 가이드


# Re-Fit 부하 테스트

Re-Fit 서비스의 **Baseline**, **Load**, **Stress**, **Spike** 테스트를 위한 k6 기반 부하 테스트 시스템입니다.

---

## 📋 목차

- [특징](#특징)
- [시스템 요구사항](#시스템-요구사항)
- [빠른 시작](#빠른-시작)
- [테스트 종류](#테스트-종류)
- [파일 구조](#파일-구조)
- [환경 설정](#환경-설정)
- [실행 방법](#실행-방법)
- [결과 분석](#결과-분석)
- [Grafana 연동](#grafana-연동)
- [문제 해결](#문제-해결)
- [기여 가이드](#기여-가이드)

---

## ✨ 특징

-  **4가지 테스트 타입**: Baseline, Load, Stress, Spike
-  **자동화**: 전체 테스트 자동 실행 (`run-all-tests.sh`)
-  **Grafana 실시간 모니터링**: InfluxDB + Grafana 대시보드
-  **안전한 환경변수 관리**: `.env` 파일로 JWT Secret 관리
-  **테스트 데이터 자동 정리**: Cleanup 스크립트 제공
-  **상세한 결과 분석**: JSON 형식 결과 + 콘솔 요약

---

## 🖥️ 시스템 요구사항

### 필수

- **Node.js** v18 이상
- **k6** 최신 버전
- **macOS** 또는 **Linux** (Windows는 WSL 권장)

### 선택 (Grafana 연동 시)

- **Docker** (InfluxDB + Grafana 실행용)
- **InfluxDB** v1.8+
- **Grafana** v9.0+

---

## 🚀 빠른 시작

### 1. 설치
```bash