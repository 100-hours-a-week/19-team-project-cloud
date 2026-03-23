# Cluster Autoscaler 도입 필요성 분석

## 배경 — 부하테스트 중 발생한 CPU 고갈 사건

부하테스트(`2-load-test.js`) 실행 중 AI 파드가 `Pending` 상태에 빠지는 문제가 발생했다.

### 클러스터 구성 (사건 당시)

| 구성 요소 | 수량 |
|-----------|------|
| 워커 노드 | 2개 (각 CPU 2 core) |
| 총 CPU | 4 core (4000m) |

### 당시 노드별 CPU 사용량

| 노드 | 사용량 | 비율 |
|------|--------|------|
| Worker Node 1 | 1851m / 2000m | **92%** |
| Worker Node 2 | 1591m / 2000m | **79%** |

백엔드 롤링 업데이트로 파드가 일시적으로 3개(평소 2개)가 되면서 클러스터 CPU가 포화 상태에 빠졌고,
그 상태에서 AI HPA가 1→2 스케일 아웃을 시도했으나 500m를 수용할 노드가 없어 Pending이 된 것.

---

## 문제의 근본 원인

### HPA + 고정 노드 수의 충돌

```
[정상 상태]
  refit-backend: 2 pods × 250m req = 500m
  refit-ai:      1 pod  × 500m req = 500m
  기타 시스템 파드:                  ~1200m
  ─────────────────────────────────────────
  총 사용량:                         ~2200m / 4000m (55%)

[롤링 업데이트 + HPA 동시 발생]
  refit-backend: 3 pods × 250m req = 750m  ← surge=1 신규 파드 추가
  refit-ai:      2 pods × 500m req = 1000m ← HPA 스케일 아웃 시도
  기타 시스템 파드:                  ~1200m
  ─────────────────────────────────────────
  요구량:                            ~2950m / 4000m
  → 특정 노드에서 여유 없음 → Pending
```

- HPA는 파드 수를 늘릴 수는 있지만 **노드를 추가하지는 못한다**
- 워커 노드가 2개로 고정되어 있어 트래픽 급증 시 HPA가 스케일 아웃을 결정해도 파드를 배치할 공간이 없음

---

## 임시 조치

```bash
kubectl scale deployment refit-backend -n refit-app --replicas=2
```

롤링 업데이트 surge로 일시적으로 3개가 된 백엔드 파드를 2개로 강제 축소하여 CPU 여유 공간 확보.
AI 파드 Pending 해소 확인.

---

## 근본 해결책: Cluster Autoscaler (CA) 도입

### CA 동작 방식

```
트래픽 증가
  → HPA: 파드 수 증가 요청
  → 스케줄러: 배치 가능한 노드 없음 → 파드 Pending
  → CA: Pending 파드 감지 → AWS ASG에 노드 추가 요청
  → 새 노드 Join → 파드 배치 완료
트래픽 감소
  → HPA: 파드 수 감소
  → CA: 노드 활용률 낮은 노드 감지 → 노드 제거 (scale-down-delay 경과 후)
```

### 설정 예시 (EKS + AWS ASG)

**1. ASG 태그 추가** (CA가 관리 대상 ASG 식별)

```
k8s.io/cluster-autoscaler/enabled = true
k8s.io/cluster-autoscaler/<CLUSTER_NAME> = owned
```

**2. CA Deployment 핵심 파라미터**

```yaml
command:
  - ./cluster-autoscaler
  - --cloud-provider=aws
  - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/<CLUSTER_NAME>
  - --balance-similar-node-groups
  - --skip-nodes-with-system-pods=false
  - --scale-down-delay-after-add=5m     # 스케일 아웃 후 5분간 스케일 다운 억제
  - --scale-down-unneeded-time=10m      # 10분간 미사용 노드만 제거
```

**3. IAM 권한** (CA 파드가 ASG를 제어할 수 있도록)

```json
{
  "Effect": "Allow",
  "Action": [
    "autoscaling:DescribeAutoScalingGroups",
    "autoscaling:SetDesiredCapacity",
    "autoscaling:TerminateInstanceInAutoScalingGroup",
    "ec2:DescribeLaunchTemplateVersions"
  ],
  "Resource": "*"
}
```

---

## CA 도입 시 기대 효과

| 구분 | CA 없음 (현재) | CA 있음 |
|------|---------------|---------|
| HPA 스케일 아웃 시 노드 부족 | 파드 Pending | 자동 노드 추가 후 배치 |
| 롤링 업데이트 + HPA 동시 발생 | CPU 고갈 위험 | 노드 여유 확보 자동화 |
| 야간 저트래픽 | 노드 낭비 | 불필요한 노드 자동 제거 |
| 수동 개입 필요 | 자주 필요 | 불필요 |

---

## 현재 임시 완화책 (CA 도입 전)

| 항목 | 설정값 | 비고 |
|------|--------|------|
| refit-backend HPA maxReplicas | 5 | 노드 용량 초과 시 Pending 위험 |
| refit-ai HPA maxReplicas | 3 | 마찬가지 |
| backend CPU request | 250m | 조정 여지 있음 |
| backend CPU limit | 500m | |

- 부하테스트 전 `kubectl top nodes`로 여유 CPU 확인 권장
- HPA maxReplicas를 클러스터 총 여유 용량 기준으로 제한하는 것도 단기 방안

---

## 참고

- 부하테스트 상세: `loadtest/scripts/6-hpa-validation.js`
- Self-healing 테스트: `loadtest/scripts/k8s-self-healing-test.sh`
- 백엔드 HPA/VPA 설정: `k8s/helm/refit-backend/values.yaml`
- AI HPA/VPA 설정: `k8s/helm/refit-ai/values.yaml`
