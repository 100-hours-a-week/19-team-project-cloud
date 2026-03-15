# K8s ALB 연동 및 트러블슈팅 로그 (2026-03-15)

## 1. 작업 개요
- **목표:** 수동 구축한 K8s 클러스터(Master 1, Worker 2)의 내부 서비스를 외부로 노출하기 위해 AWS ALB(Application Load Balancer)를 생성하고 연동함.
- **방식:** K8s Gateway API(Cilium)가 제공하는 NodePort(`32678`)를 타겟으로 지정하여, ALB가 워커 노드로 트래픽을 포워딩하도록 구성.

## 2. 세부 작업 내역

### 1) 대상 그룹(Target Group) 생성
- **대상 유형:** 인스턴스 (Instances)
- **VPC:** `refit-k8s-vpc`
- **포트:** `HTTP 32678` (Gateway NodePort)
- **대상 등록:** 마스터 노드 제외, 실질적인 트래픽을 처리하는 **워커 노드 2대(`refit-worker-1`, `refit-worker-2`) 모두 등록** 완료.

### 2) ALB(Application Load Balancer) 생성
- **이름:** `refit-k8s-alb`
- **네트워크:** Public Subnets 할당 (Internet-facing)
- **리스너 규칙:** `HTTP 80` 포트로 들어오는 요청을 위에서 생성한 대상 그룹으로 포워딩.

---

## 3. 트러블슈팅 기록

ALB 연동 직후 통신이 정상적으로 이루어지지 않아 3단계에 걸친 트러블슈팅을 진행함.

### 🐛 이슈 1: 타겟 그룹 Unhealthy (Target.Timeout)
- **증상:** ALB 상태 검사 트래픽이 워커 노드에 도달하지 못해 Timeout 발생.
- **원인:** 워커 노드가 속한 보안 그룹에 K8s Gateway 포트(`32678`) 인바운드 규칙이 존재하지 않음.
- **조치:** `k8s-worker-sg` 보안 그룹에 ALB로부터 유입되는 `TCP 32678` 허용 규칙 추가.

### 🐛 이슈 2: 타겟 그룹 Unhealthy (404 ResponseCodeMismatch)
- **증상:** Timeout은 해결되었으나 `Health checks failed with these codes: [404]` 발생.
- **원인:** K8s 내부 `HTTPRoute`는 `/api` 등의 특정 경로만 허용하도록 라우팅되어 있음. 반면 ALB 상태 검사는 기본적으로 루트(`/`) 경로를 검사하여 K8s Gateway가 404를 반환하게 됨.
- **조치:** 타겟 그룹의 고급 상태 검사 설정(Success codes)을 `200`에서 **`200,404`**로 완화하여 네트워크 통로 유효성을 검증하도록 조치 완료.

### 🐛 이슈 3: 브라우저 접속 시 504 (Upstream Connect Error)
- **증상:** 상태 검사는 통과했으나 실제 브라우저 접속 시 `upstream connect error or disconnect/reset before headers` 및 504 Timeout 터짐.
- **원인:** 트래픽을 받은 워커 노드와 백엔드 파드가 띄워진 워커 노드가 다를 경우, K8s 내부망(Cilium VXLAN 등)을 통해 트래픽을 노드 간 전달해야 함. 하지만 AWS 방화벽에서 기본적으로 자체 VPC 내 EC2 간 내부 트래픽이 막혀 있어 오버레이 네트워크 통신이 끊어짐.
- **조치:** `k8s-worker-sg` 보안 그룹의 인바운드 규칙에 **자신의 보안 그룹 ID를 대상으로 하는 "모든 트래픽(All traffic)" 허용 룰을 추가**하여 노드 간 K8s 내부망 통신을 완전히 개통함.

## 4. 최종 결과
위 조치들을 통해 브라우저 및 Postman에서 `http://(ALB-DNS)/actuator/health` 접속 시, 백엔드 파드까지 완벽히 트래픽이 도달하여 `{"status":"UP"}` 응답을 정상 반환하는 것을 확인. 외부 노출 및 라우팅 파이프라인 개통 대성공.
