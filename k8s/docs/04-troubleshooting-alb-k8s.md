# 트러블슈팅: ALB 연동 시 504 Gateway Timeout 및 404 에러 해결

Kubernetes 클러스터 외부 노출을 위해 AWS ALB(Application Load Balancer) 구성 후, 실제 파드 통신을 시도하는 과정에서 발생한 이슈와 해결 방법에 대한 기록입니다.

## 🔴 증상 1: ALB 대상 그룹(Target Group) Unhealthy (Timeout)

- **상황:** ALB 생성 후 대상 그룹에 워커 노드(`refit-worker-1`, `refit-worker-2`)를 등록했으나 상태가 `Unhealthy`로 표시됨.
- **오류 메시지:** `Target.Timeout` (워커 노드가 응답하지 않음)
- **원인:** AWS EC2 보안 그룹(Security Group)에서 외부(ALB)로부터 유입되는 K8s NodePort 대역에 대한 허용 규칙이 부재함. K8s Gateway API(Cilium)가 열어둔 포트(`32678`)로 ALB의 상태 검사(Health Check) 트래픽이 방화벽에 막혀 도달하지 못함.

### ✅ 해결 방법
1. **워커 노드 보안 그룹 (`k8s-worker-sg`) 인바운드 규칙 추가**
   - 유형: 사용자 지정 TCP
   - 포트: `32678` (K8s Gateway NodePort)
   - 소스: ALB 보안 그룹 (`k8s-alb-sg`) (또는 테스트 시 0.0.0.0/0)
   - 설명: `Allow ALB to K8s Gateway NodePort (Cilium)`

---

## 🟡 증상 2: 대상 그룹 404 (ResponseCodeMismatch)

- **상황:** 보안 그룹을 뚫어 Timeout은 해결되었으나, 여전히 대상 상태가 `Unhealthy` 로 표시됨.
- **오류 메시지:** `Target.ResponseCodeMismatch` (Health checks failed with these codes: [404])
- **원인:** ALB는 기본적으로 루트 경로(`/`)로 상태 검사를 보냄. 그러나 K8s 내부의 `HTTPRoute` 매니페스트는 `/api` 등의 특정 경로만 백엔드로 포워딩하도록 설정되어 있음. K8s Gateway 입장에서 `/` 요청은 경로 매칭 실패에 해당하여 `404 Not Found`를 반환함.

### ✅ 해결 방법
- **ALB 상태 검사 기준 변경**
  - 대상 그룹 설정 ➡️ 상태 검사(Health checks) 편집 ➡️ 고급 설정
  - 성공 코드(Success codes)를 `200`에서 **`200,404`**로 완화하여 `404`가 반환되어도 네트워크/애플리케이션 통로 자체는 활성화된 것으로 간주토록 수정. (또는 상태 검사 경로를 실제 200이 뜨는 `/api/...`로 변경)

---

## 🔴 증상 3: 브라우저 접속 시 504/Reset 에러 (Upstream Connect Error)

- **상황:** ALB 대상 상태가 `Healthy`로 전환됨. 브라우저에서 `(ALB_DNS)/actuator/health`로 접속 시 504 에러 발생.
- **오류 메시지:** `upstream connect error or disconnect/reset before headers. reset reason: connection timeout`
- **단서 분석:**
  1. K8s 대문(`refit-gateway`)까지 통신은 도달했으나, 대문에서 실제 백엔드 파드(`refit-backend`)로 트래픽을 넘기는 과정(오버레이 통신)에서 단절됨.
  2. 현재 워커 노드가 2개(`worker-1`, `worker-2`)이며, ALB로부터 트래픽을 받은 워커 노드와 실제 파드가 띄워져 있는 워커 노드가 다를 확률이 존재함. 이 경우 K8s CNI(Cilium)가 내부 통신망(Overlay Network)을 통해 트래픽을 노드 간 패스해야 함.
- **원인:** AWS 워커 노드 보안 그룹(`k8s-worker-sg`)에 **"워커 노드들끼리의 내부 통신(All Traffic)"을 허용하는 인바운드 규칙**이 빠져있었음. 이로 인해 Cilium VXLAN(오버레이 네트워크 캡슐화 포트) 또는 노드 간 트래픽이 AWS 방화벽에 막혀 `Connection Timeout` 발생.

### ✅ 해결 방법
1. **노드 간 내부 통신 전면 허용 규칙 추가 (필수)**
   - 보안 그룹: `k8s-worker-sg`
   - 유형: 모든 트래픽 (All traffic)
   - 소스: 자신과 동일한 보안 그룹 ID (`sg-0c9006991cf3e0dd1`)
   - 설명: `Allow internal node-to-node communication for K8s overlay network`
2. **트래픽 개통 확인**
   - 방화벽 적용 즉시 504 에러가 해소되며 `{"status":"UP"}` 등 정상 애플리케이션 응답을 반환하기 시작함.

---

## 💡 레슨 런 (Lessons Learned)
- **온프레미스와 클라우드 K8s의 차이:** kubeadm을 사용해 AWS EC2 위에 깡통 클러스터를 올리는 환경(수동 구축)에서는, K8s 내부의 네트워크 정책(CNI)과 더불어 밑바닥을 감싸고 있는 **AWS VPC 보안 그룹 설정이 완벽하게 일치해야만 전체 트래픽 플로우가 열림**을 확인. 노드 간 내부 통신을 위한 자기 참조(Self-referencing) 방화벽 개방은 필수 요소임.
