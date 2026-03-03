# 🚀 아키텍처 개편 및 성능 최적화: 계절성 트래픽 병목 해결 (v1 vs v2)

이 문서는 단일 인스턴스(v1) 환경에서 다중 인스턴스(v2) 환경으로 아키텍처를 전환한 배경과 기대 효과, 그리고 이를 입증하기 위한 부하 테스트 및 모니터링 대시보드 전략을 정리한 포트폴리오 기획안입니다.

## 1. 개요 및 배경

*   **서비스 특성:** 취업 준비생들을 돕는 서비스로, 특정 시기(공채 시즌, 서류 마감일 등)에 트래픽이 집중되는 **계절성 트래픽(Seasonal Traffic)** 특성을 가짐.
*   **문제 상황 (v1 아키텍처의 한계):**
    *   기존 v1 아키텍처는 단일 인스턴스(Single Instance) 구조.
    *   평상시에는 문제가 없으나 공채 시즌 등 사용자 접속이 폭증(Spike)하는 시기에는 한계 성능(병목점)에 도달.
    *   결과적으로 사용자에게 심각한 응답 지연(Latency 급증) 및 서버 다운(Connection Timeout, 5xx 에러)을 초래하여 서비스 신뢰도 저하 발생.
*   **해결 전략 (v2 아키텍처 도입):**
    *   SPOF(Single Point of Failure)를 극복하고 대규모 트래픽 분산 처리를 위해 L4/L7 단위의 로드밸런서(Load Balancer) 도입.
    *   다중 인스턴스(Multi-Instance) 환경 구축 및 부하에 따른 탄력적인 Auto Scaling(필요시) 적용.

## 2. 전환에 따른 기대 효과 (가설)

v2 아키텍처 전환을 통해 다음 세 가지 핵심 효과 달성을 목표로 합니다.

1.  **Spike 트래픽(폭증) 방어력 대폭 향상:** 동시 접속자가 단기간에 10배 이상 급증해도 안정적인 요청 처리가 가능하여 다운타임(Downtime)을 예방.
2.  **응답 속도 (Latency) 안정화 보장:** 트래픽이 여러 대로 분산되므로, 피크 타임에도 개별 인스턴스의 하드웨어(CPU/Memory) 고갈을 방지하고 p95 기준 평시와 유사한 여유로운 응답 속도를 유지.
3.  **고가용성 (High Availability) 및 장애 격리(Failover):** 1대의 인스턴스에 예기치 못한 장애가 발생하더라도, 로드밸런서의 상태 확인(Health Check)을 통해 즉시 정상 인스턴스로 트래픽을 넘겨 무중단 서비스 제공.

---

## 3. 검증 전략 1: 부하 테스트 (Load Testing) 설계

기대 효과를 객관적인 수치와 데이터로 증명하기 위해, `v1`과 `v2` 환경에 동일한 시나리오의 부하 테스트를 수행하여 한계점과 성능 추이를 비교합니다. (k6 도구 활용)

### 3.1. 핵심 테스트 종류

*   **Spike Test (스파이크 테스트)**
    *   **시나리오:** 평시 부하(ex: 10 VU) 유지 중, 1분 이내에 부하를 극한(ex: 100~200 VU)으로 급상승 시킴.
    *   **입증 목표:**
        *   `v1:` 특정 RPS에서 에러율(5xx)이 치솟고 서비스 불능 상태 돌입 확인.
        *   `v2:` 스파이크 상황에서도 에러율 수렴(목표 0%) 및 지연 시간 방어 확인.
*   **Stress Test (스트레스 테스트)**
    *   **시나리오:** 부하를 계단식으로 계속 증가시켜 시스템이 완전히 뻗는 임계점(Breaking Point)을 찾음.
    *   **입증 목표:** 아키텍처 변경 전/후의 최대 수용 처리량(Max Throughput/RPS) 차이 비교. (예: "v1 대비 최대 처리량 ○배 향상")

### 3.2. 실제 환경과 유사한 시나리오 (Traffic Mix)
부하의 신뢰도를 높이기 위해, 실제 서비스에서 발생할 수 있는 주요 행동 패턴을 조합하여 테스트합니다.
*   현직자 검색/조회 (DB 부하) : 40%
*   채팅(REST/WS) : 25%
*   내 정보 조회 : 20%
*   내 정보 수정 : 15%

---

## 4. 검증 전략 2: 시각적 입증을 위한 대시보드 (Grafana) 구성

면접관/리뷰어에게 v1과 v2의 성능 차이를 "그래프 형태의 극적인 대비(극명한 Before/After)"를 통해 직관적으로 증명하는 전략입니다. v1과 v2 대시보드는 동일한 화면 분할(패널) 구성을 갖추고 테스트 결과를 나란히 보여줍니다.

### 4.0. 대시보드 구현 파일

*   **v1 대시보드**: `monitoring/monitoring-server/dev/grafana/provisioning/dashboards/architecture-comparison.json`
    *   Grafana UID: `arch-comparison-v1`
    *   접속: `grafana.dev.re-fit.kr`
*   **v2 대시보드**: `monitoring/monitoring-server/prod/grafana/provisioning/dashboards/architecture-comparison.json`
    *   Grafana UID: `arch-comparison-v2`
    *   접속: `monitoring-v2.re-fit.kr`

### 4.1. Row 1: System Health Overview (안정성 한눈에 비교)

| 패널 구성 | v1 메트릭 | v2 메트릭 | 입증 목표 |
| :--- | :--- | :--- | :--- |
| **Current RPS** (Stat) | `rate(http_server_requests_seconds_count[1m])` | `rate(refit_http_server_requests_milliseconds_count[1m])` | 동일한 부하 조건 증명 |
| **Active Instances** (Stat) | `count(up{job="spring-boot"})` → 항상 `1` | `count(refit_up{exported_job="refit-backend"})` → `2`+ | 아키텍처 스케일링 시각화 |
| **5xx Error Rate** (Gauge) | 에러율 15%+ 예상 (빨간 게이지) | 에러율 0% 목표 (초록 게이지) | 장애 방어 직관적 입증 |

### 4.2. Row 2: Response Latency (사용자 경험 비교)

| 패널 구성 | v1 예상 뷰 | v2 예상 뷰 | 입증 목표 |
| :--- | :--- | :--- | :--- |
| **p50/p95/p99 응답 시간** (Time series) | 스파이크 시 p95 5000ms+ 병목 (빨간 산맥) | p95 500ms 이하 안정 유지 (잔물결) | 쾌적한 UX 보장 |
| **API별 p95 응답 시간** (Time series) | 전 구간 동시 병목 | 엔드포인트별 균등한 낮은 지연 | 시나리오별 성능 분석 |

> **주의**: v1은 응답 시간이 **초(seconds)** 단위이므로 `* 1000` 변환하여 ms로 표시. v2는 **밀리초(milliseconds)** 단위이므로 변환 불필요.

### 4.3. Row 3: System Resources (병목 해소 입증)

| 패널 구성 | v1 메트릭 | v2 메트릭 | 입증 목표 |
| :--- | :--- | :--- | :--- |
| **Host CPU** (Line) | `node_cpu_seconds_total` + `system_cpu_usage` — 천장(100%) | `refit_system_cpu_usage` — 60% 미만 유지 | CPU 고갈 해결 |
| **Host Memory** (Line) | `node_memory_MemAvailable_bytes` — 고갈 위험 | `refit_jvm_memory_used_bytes` — 안정적 | 메모리 안정화 |

### 4.4. Row 4: DB Connection Pool — HikariCP (+RDS Proxy 효과)

| 패널 구성 | v1 (Direct DB) | v2 (RDS Proxy) | 입증 목표 |
| :--- | :--- | :--- | :--- |
| **Connection Pool** (Line) | Active가 Max에 도달 → Pending 급증 | Active 여유 유지, Pending 0 | 커넥션 고갈 방지 |
| **Acquire/Usage Time** (Line) | Acquire p95 1000ms+ (타임아웃 발생) | Acquire p95 10ms 이하 안정 | RDS Proxy 효과 입증 |

### 4.5. Row 5: Throughput & Traffic Distribution

| 패널 구성 | v1 예상 뷰 | v2 예상 뷰 | 입증 목표 |
| :--- | :--- | :--- | :--- |
| **Total RPS** (Line) | Total과 Successful 괴리 (5xx로 인한 실패) | Total ≈ Successful (에러 0) | 실질 처리량 비교 |
| **Traffic Distribution** (Stacked Bar) | 단일 색상 1대 | 50:50 분산 스택 | ALB 분산 증명 |

---

## 5. (초안) 포트폴리오 요약 스크립트 작성 예시

포트폴리오 슬라이드(PPT) 또는 노션에 들어갈 요약 문구 초안입니다. (위의 캡처 화면 2장을 나란히 붙인 뒤)

> **[아키텍처 스케일링을 통한 계절성 스파이크 방어 및 고가용성 확보]**
>
> 🔹 **문제의식:** 공채 시즌에 트래픽이 일시적으로 10배 폭증하는 서비스 특성상, 기존 애플리케이션(v1)은 처리 한계를 넘어서면 CPU 자원 고갈로 최악의 지연(p95 응답 5초 이상) 및 15%에 달하는 5xx 에러율 다운타임을 겪었습니다.
>
> 🔹 **극복 전략:** SPOF를 제거하고 확장을 고려한 `L4/L7 로드밸런서 + 다중 인스턴스(v2)` 체계로 아키텍처를 진화시켰습니다.
>
> 🔹 **성과 및 시각적 입증 (k6 & Grafana 모니터링 기반):**
> 1. DB와 외부 API 부하를 실제 비율로 모사한 `Spike 테스트` 결과, **최대 수용 처리량(RPS)을 기존 단일 서버 대비 약 ○배 상향**시켰습니다.
> 2. 트래픽 폭주 상황 속에서도 `로드밸런서`가 정확히 50:50 분산 라우팅을 수행하는 것을 확인하였으며, 이로 인해 서버 평균 CPU를 60% 미만으로 억제하며 **에러율 0% 방어 및 지연 시간 500ms 유지**에 성공했습니다.
> 3. 관측 가능성(Observability) 확보를 위해 Prometheus/Grafana 대시보드를 직접 설계하여, 시스템의 안정화 궤적을 실시간 데이터로 가시화했습니다.
