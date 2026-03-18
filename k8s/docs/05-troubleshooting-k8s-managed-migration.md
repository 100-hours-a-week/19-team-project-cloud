# 트러블슈팅 기록: K8s 운영 이슈 및 관리형 서비스 전환

> 작성일: 2026-03-16
> 대상: refit-backend 배포 안정화 + Redis/Kafka → ElastiCache/MSK 전환

---

## 목차

1. [StartupProbe 타임아웃으로 인한 CrashLoopBackOff](#1-startupprobe-타임아웃으로-인한-crashloopbackoff)
2. [ECR Secret 만료 → ImagePullBackOff](#2-ecr-secret-만료--imagepullbackoff)
3. [ECR 갱신 CronJob 미적용 (ArgoCD App 객체 미갱신)](#3-ecr-갱신-cronjob-미적용-argocd-app-객체-미갱신)
4. [ResourceQuota 초과로 롤링 업데이트 중단](#4-resourcequota-초과로-롤링-업데이트-중단)
5. [Secrets Manager YAML 구조 오류 (duplicate key)](#5-secrets-manager-yaml-구조-오류-duplicate-key)

---

## 1. StartupProbe 타임아웃으로 인한 CrashLoopBackOff

### 원인

Spring Boot 앱 시작에 약 **105초**가 소요되는데, `startupProbe`에 `timeoutSeconds`를 설정하지 않아 기본값 **1초**가 적용됨.

Tomcat이 포트를 열기 시작하는 시점부터 Spring Application Context가 완전히 로드될 때까지 약 80초 동안 `/actuator/health` 엔드포인트가 1초 내에 응답하지 못해 반복 실패.

```
총 허용 시간: initialDelaySeconds(20) + periodSeconds(5) × failureThreshold(24) = 140초
앱 시작 시간: ~105초
→ 이론상 통과 가능하지만, 시작 중 health endpoint가 1초 내 응답 불가 → 누적 실패
```

Hikari Connection Pool min-idle 30개 연결 생성, FCM 초기화 등 무거운 초기화 작업이 원인.

### 해결

`startupProbe`에 `timeoutSeconds: 5` 추가, `periodSeconds`와 `failureThreshold` 조정.

```yaml
# 변경 전
startupProbe:
  periodSeconds: 5
  failureThreshold: 24
  # timeoutSeconds 미설정 → 기본값 1초

# 변경 후
startupProbe:
  periodSeconds: 10
  failureThreshold: 18
  timeoutSeconds: 5  # 추가
  # 총 허용 시간: 20 + 10×18 = 200초
```

### 결과

`timeoutSeconds: 5`로 인해 앱 시작 중 응답 지연을 허용, 200초 내에 startupProbe 통과 확인.

---

## 2. ECR Secret 만료 → ImagePullBackOff

### 원인

ECR 인증 토큰은 **12시간마다 만료**됨. `ecr-secret`이 3일 전 수동 생성된 후 갱신되지 않아 만료 상태.

기존 파드는 이미지가 노드에 캐시되어 있어 정상 동작했지만, 새 이미지(`develop-566f470`) pull 시도 시 **403 Forbidden** 발생.

```
ECR Response: 403 Forbidden
→ Failed to pull image: unexpected status from HEAD request
→ ImagePullBackOff
```

### 해결

로컬에서 ECR 토큰을 발급받아 클러스터에 직접 적용.

```bash
ECR_PASS=$(aws ecr get-login-password --region ap-northeast-2)
kubectl create secret docker-registry ecr-secret \
  --docker-server=807210685804.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${ECR_PASS}" \
  -n refit-app \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 결과

Secret 갱신 후 이미지 pull 성공. 이후 ECR 갱신 CronJob을 적용해 **6시간마다 자동 갱신** 설정.

---

## 3. ECR 갱신 CronJob 미적용 (ArgoCD App 객체 미갱신)

### 원인

`refit-stack.yaml`에 `00-ecr-secret-refresh.yaml`을 include 필터에 추가하는 커밋을 했지만, 클러스터의 ArgoCD Application 객체 자체는 자동으로 갱신되지 않음.

ArgoCD Application 객체는 `refit-stack.yaml`로 정의되지만, 이 파일 자체를 관리하는 App of Apps 구조가 없어 **변경 시 수동 `kubectl apply` 필요**.

```
git push → ArgoCD가 refit-infra 앱 sync
                   ↓
         refit-infra 앱 spec은 구버전 (include 필터에 00-ecr-secret-refresh.yaml 없음)
                   ↓
         CronJob 관련 리소스 미생성
```

### 해결

`refit-stack.yaml` 변경 후 반드시 수동으로 적용.

```bash
kubectl apply -f k8s/manifests/argocd-apps/refit-stack.yaml
```

### 결과

CronJob 생성 확인. 이후 6시간 주기로 ECR Secret 자동 갱신.

> **주의**: `refit-stack.yaml` 변경 시 항상 `kubectl apply`를 함께 실행해야 함.

---

## 4. ResourceQuota 초과로 롤링 업데이트 중단

### 원인

Redis/Kafka를 관리형 서비스로 전환하면서 `refit-app` ResourceQuota를 `limits.memory: 5Gi`로 줄임. 하지만 AI 파드가 설계서(512Mi)와 달리 실제 **3Gi** limit으로 설정되어 있었음.

```
현재 사용량:
  AI pod:          3Gi
  Backend × 2:     1.5Gi (768Mi × 2)
  합계:            4.5Gi

롤링 업데이트 시 새 파드 추가:
  4.5Gi + 0.75Gi = 5.25Gi > 5Gi → FailedCreate
```

### 해결

AI 파드의 실제 사용량(857Mi)과 최대 스케일(2 pods × 3Gi = 6Gi)을 반영해 quota 상향.

```yaml
# 변경 전
requests.memory: "3Gi"
limits.memory: "5Gi"
pods: "12"

# 변경 후
requests.memory: "8Gi"
limits.memory: "11Gi"  # BE max(5×768Mi=3.75Gi) + AI max(2×3Gi=6Gi) + 여유
pods: "15"
```

ArgoCD selfHeal이 git 상태로 되돌리므로 반드시 **커밋 + push 후** ArgoCD sync 확인.

### 결과

quota 반영 후 롤링 업데이트 정상 완료.

---

## 5. Secrets Manager YAML 구조 오류 (duplicate key)

### 원인

Kafka 설정을 Secrets Manager에서 관리하도록 전환하면서 두 가지 실수 발생.

**실수 1**: YAML 키 구조 오류 - Spring Boot가 인식하지 못하는 구조로 작성

```yaml
# 잘못된 구조 (Spring이 인식 못 함)
kafka:
  bootstrap-servers: b-1.refitkafka...

# 올바른 구조
spring:
  kafka:
    bootstrap-servers: b-1.refitkafka...
```

**실수 2**: 수정 과정에서 `spring:` 루트 키가 파일 내 2회 등장

```yaml
spring:          # 1번째 (line 1): datasource, data.redis, security...
  ...

spring:          # 2번째 (line 64): kafka (중복!)
  kafka:
    ...
```

SnakeYAML이 duplicate key를 허용하지 않아 앱 시작 시 파싱 에러 발생:
```
found duplicate key spring
ApplicationContextException: Failed to start bean 'internalKafkaListenerEndpointRegistry'
```

### 해결

두 `spring:` 블록을 하나로 병합. `spring.kafka`를 기존 `spring:` 블록 안으로 이동.

```yaml
spring:
  datasource: ...
  data:
    redis: ...
  security: ...
  jwt: ...
  mail: ...
  cloud: ...
  kafka:                    # ← 여기로 통합
    bootstrap-servers: b-2.refitkafka...,b-1.refitkafka...
    consumer:
      group-id: refit-backend-dev
```

수정 후 Secrets Manager 업로드 → ExternalSecret 강제 갱신 → 파드 재시작.

```bash
# ExternalSecret 강제 갱신
kubectl annotate externalsecret refit-backend-external-secret \
  -n refit-app force-sync=$(date +%s) --overwrite

# 파드 재시작
kubectl rollout restart deployment/refit-backend -n refit-app
```

### 결과

앱이 MSK 연결 에러 없이 정상 시작. `Started RefitBackendApplication in 105s` 확인.

> **교훈**: Secrets Manager의 시크릿이 Spring Boot YAML 형식일 경우, 키 구조가 Spring 프로퍼티 계층과 일치해야 함. 수정 전 전체 파일 구조를 확인하고, 중복 루트 키가 없는지 검증 필요.

---

## 전체 작업 결과 요약

| 항목 | 변경 전 | 변경 후 |
|---|---|---|
| Kafka | in-cluster StatefulSet (emptyDir) | MSK kafka.t3.small × 2 브로커 |
| Redis | in-cluster StatefulSet (emptyDir) | ElastiCache Valkey 8.0 (cache.t4g.micro) |
| ECR Secret | 수동 관리 (만료 위험) | CronJob으로 6시간마다 자동 갱신 |
| ResourceQuota limits.memory | 5Gi | 11Gi (AI 3Gi 반영) |
| StartupProbe timeoutSeconds | 1초 (기본값) | 5초 |
| Kafka 엔드포인트 관리 | values.yaml 하드코딩 | Secrets Manager (git 미노출) |
