# K8s 워크로드 배포 및 RDS 연결

- **작업일시**: 2026-03-13
- **작업자**: yoonseo + Claude

## 작업 내용

### 1. Redis 배포
- `03-workload/01-redis.yaml` 매니페스트 수정 (emptyDir 볼륨 추가)
- StatefulSet + Service 배포 완료, PONG 응답 확인
- EBS PV는 미연결 상태 (운영 전환 시 연결 예정)

### 2. Kafka 배포
- `03-workload/02-kafka.yaml` 매니페스트 신규 작성
- KRaft 모드 단일 브로커 (ZooKeeper 불필요)
- StatefulSet + Service 배포 완료, 브로커 API 정상 응답 확인

### 3. RDS VPC Peering
- K8s VPC(`vpc-083e31bb3f6ddad6c`, 10.2.0.0/16)와 RDS VPC(`vpc-012479f611e903bc6`, 10.0.0.0/16)가 분리되어 있어 연결 불가 상태였음
- VPC Peering 생성: `pcx-02f7665a1ee9348bb`
- 양쪽 라우트 테이블에 상대 CIDR 경로 추가
- RDS 보안그룹에 K8s CIDR(10.2.0.0/16) 5432 인바운드 허용
- 클러스터 내부에서 RDS 5432 포트 연결 테스트 성공

### 4. Backend 배포
- ECR 이미지: `refit-backend:develop-latest` (develop-dab92eb, 2026-03-13 빌드)
- Secret 관리: K8s Secret에 `application-secret.yml` 통째로 저장 → 볼륨 마운트 방식
  - `SPRING_CONFIG_IMPORT=optional:file:/config/secret/application-secret.yml`
  - dev 설정 기반으로 인프라 주소만 K8s에 맞게 변경 (DB→RDS, Redis→svc, Kafka→svc)
- ECR 인증: `imagePullSecrets` (ecr-secret) 사용. 워커노드 IAM Role에 ECR ReadOnly 정책도 추가
- Kafka 연결 이슈: Secret의 `kafka.bootstrap-servers`가 prod 프로파일에 오버라이드되지 않아 환경변수 `SPRING_KAFKA_BOOTSTRAP_SERVERS`로 직접 주입하여 해결
- 기동 완료 확인: `Started RefitBackendApplication in 96.89 seconds`

### 5. Backend OOMKilled 해결
- memory limit 512Mi에서 반복 OOMKilled 발생 (재시작 7회)
- 원인: JVM 힙(70%=358MB) + non-heap(메타스페이스, 스레드 스택, CodeCache 등)이 512Mi 초과
- 조치: memory limit `512Mi → 768Mi`, JVM `MaxRAMPercentage 70→60%`, `InitialRAMPercentage 70→50%`
- 결과: 재시작 0회, actuator health `{"status":"UP"}` 정상 응답 확인

### 경미한 이슈 (앱 기동에는 영향 없음)
- FCM: `firebase/refit-fcm.json` 파일이 이미지에 없음 → 푸시 알림 기능만 비활성
- OTel: `otel-agent` 호스트 미존재 → 모니터링 스택 배포 전이라 정상

## 현재 클러스터 상태

- master 1대 + worker 1대 (t4g.large, ARM/Graviton)
- refit-app 네임스페이스: Redis, Kafka, Backend 모두 Running
- ECR imagePullSecret 만료: 12시간 (갱신 자동화 필요)
- 다음 작업: 모니터링 스택 배포 또는 워커노드 확장
