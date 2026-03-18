# Re-Fit 쿠버네티스 아키텍처 다이어그램

> K8s_design_v2.md 설계서 기반 전체 아키텍처 Mermaid 초안

---

## 1. 전체 아키텍처 (인프라 + CI/CD + 모니터링 통합)

```mermaid
graph TD
    %% ── 사용자 및 개발자 ──
    User(["👤 사용자"])
    Dev(["👨‍💻 개발자"])

    %% ── Git 저장소 ──
    subgraph Git_Repos ["GitHub Repositories"]
        BE_Repo["BE Repo<br/>(Spring Boot 소스)"]
        AI_Repo["AI Repo<br/>(FastAPI 소스)"]
        Cloud_Repo["Cloud Repo<br/>(K8s Manifests /<br/>Kustomize)"]
    end

    %% ── CI 파이프라인 ──
    subgraph CI_Pipeline ["CI Pipeline (GitHub Actions)"]
        GHA_BE["BE CI<br/>Test → Build → Push"]
        GHA_AI["AI CI<br/>Test → Build → Push"]
        Trivy["Trivy<br/>이미지 보안 스캔"]
    end

    ECR["AWS ECR<br/>(컨테이너 레지스트리)"]

    %% ── 프론트엔드 (Serverless: OpenNext + SST) ──
    subgraph Frontend ["Frontend (Serverless: OpenNext + SST)"]
        Route53["Route53<br/>(re-fit.kr / ACM)"]
        CF["CloudFront<br/>(CDN + 라우팅 + WAF)"]
        S3["S3<br/>(정적 에셋)"]
        Lambda["Lambda<br/>(SSR / API Routes / BFF)"]
        SST["SST (IaC)<br/>인프라 프로비저닝"]  
    end

    %% ── AWS 네트워크 진입점 (백엔드) ──
    ALB["AWS ALB<br/>(TLS 종료 / ACM)"]

    %% ── Kubernetes 클러스터 ──
    subgraph K8s_Cluster ["Kubernetes Cluster (kubeadm)"]

        %% Control Plane HA
        subgraph CP ["Control Plane HA (t3.medium × 3)"]
            NLB["Internal NLB<br/>:6443"]
            CP1["CP-1 (AZ-a)<br/>API Server + etcd"]
            CP2["CP-2 (AZ-c)<br/>API Server + etcd"]
            CP3["CP-3 (AZ-b)<br/>API Server + etcd"]
        end

        %% Worker Node Pool
        subgraph Workers ["Worker Node Pool (t3.large × 2~3)"]

            %% Namespace: refit-app
            subgraph NS_App ["Namespace: refit-app"]
                Gateway["Cilium Gateway API<br/>(Envoy Proxy)<br/>NodePort 30080"]
                BE["BE Pod<br/>Spring Boot<br/>HPA: 2~5"]
                AI["AI Pod<br/>FastAPI<br/>HPA: 1~2"]
                Redis["Redis Pod<br/>Single + EBS PV"]
                Kafka["Kafka Pod<br/>KRaft + EBS PV"]
            end

            %% Namespace: monitoring
            subgraph NS_Mon ["Namespace: monitoring"]
                OTel["OTel Collector<br/>(DaemonSet)"]
                Prom["Prometheus"]
                Loki["Loki"]
                Grafana["Grafana"]
                Hubble["Hubble<br/>(Cilium 내장)"]
            end

            %% Namespace: argocd
            subgraph NS_Argo ["Namespace: argocd"]
                ArgoServer["ArgoCD Server"]
                ArgoRepo["ArgoCD Repo Server"]
                ArgoCtrl["ArgoCD App Controller"]
            end

            %% CNI
            Cilium["Cilium CNI<br/>(VXLAN 모드 / eBPF)"]
        end
    end

    %% ── 외부 서비스 ──
    RDS[("Amazon RDS<br/>PostgreSQL")]
    RunPod["RunPod<br/>(LLM / GPU)"]

    %% ── 알림 ──
    Discord["Discord<br/>(알림 채널)"]

    %% ━━━━━━ 연결선: 사용자 트래픽 (프론트엔드) ━━━━━━
    User -->|"HTTPS"| Route53
    Route53 --> CF
    CF -->|"정적 에셋<br/>(JS, CSS, 이미지)"| S3
    CF -->|"SSR / API Routes"| Lambda
    SST -.->|"배포/관리"| CF & S3 & Lambda

    %% ━━━━━━ 연결선: Lambda(BFF) → 백엔드 ━━━━━━
    Lambda -->|"API 호출<br/>(Server-side)"| ALB

    %% ━━━━━━ 연결선: 클라이언트 → 백엔드 (WebSocket 등) ━━━━━━
    User -->|"WebSocket (wss://)"| ALB
    ALB -->|"HTTP :30080"| Gateway
    Gateway -->|"/api, /ws"| BE
    Gateway -->|"/api/ai"| AI

    %% ━━━━━━ 연결선: 서비스 간 통신 ━━━━━━
    BE <-->|"Session / Pub·Sub"| Redis
    BE <-->|"Produce / Consume"| Kafka
    AI <-->|"Consume / Produce"| Kafka
    BE -->|"SQL Query"| RDS
    AI -->|"Model Predict"| RunPod

    %% ━━━━━━ 연결선: CI/CD 파이프라인 ━━━━━━
    Dev -->|"git push"| BE_Repo
    Dev -->|"git push"| AI_Repo
    BE_Repo --> GHA_BE
    AI_Repo --> GHA_AI
    GHA_BE --> Trivy
    GHA_AI --> Trivy
    Trivy -->|"이미지 Push"| ECR
    GHA_BE -->|"이미지 태그 업데이트<br/>(kustomize edit)"| Cloud_Repo
    GHA_AI -->|"이미지 태그 업데이트"| Cloud_Repo

    %% ━━━━━━ 연결선: GitOps (ArgoCD) ━━━━━━
    Cloud_Repo -->|"Git Poll / Webhook"| ArgoServer
    ArgoServer --> ArgoRepo
    ArgoRepo -->|"Manifest 렌더링"| ArgoCtrl
    ArgoCtrl -->|"Sync & Deploy"| NS_App
    ArgoCtrl -->|"K8s API"| NLB

    %% ━━━━━━ 연결선: Control Plane HA ━━━━━━
    NLB --> CP1 & CP2 & CP3
    CP1 <-.->|"Raft 합의"| CP2
    CP2 <-.->|"Raft 합의"| CP3
    CP3 <-.->|"Raft 합의"| CP1

    %% ━━━━━━ 연결선: 모니터링 ━━━━━━
    BE -.->|"OTLP"| OTel
    AI -.->|"OTLP"| OTel
    OTel -.->|"메트릭"| Prom
    OTel -.->|"로그"| Loki
    Hubble -.->|"네트워크 메트릭"| Prom
    Prom -.-> Grafana
    Loki -.-> Grafana
    Prom -.->|"Alertmanager"| Discord

    %% ━━━━━━ 스타일 ━━━━━━
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:black,font-weight:bold
    classDef k8s fill:#326CE5,stroke:#fff,stroke-width:2px,color:white
    classDef app fill:#E5F5FA,stroke:#00A2CC,stroke-width:2px,color:black
    classDef infra fill:#FFE2ED,stroke:#FF4081,stroke-width:2px,color:black
    classDef ci fill:#2ECC71,stroke:#27AE60,stroke-width:2px,color:white
    classDef mon fill:#9B59B6,stroke:#8E44AD,stroke-width:2px,color:white
    classDef git fill:#333,stroke:#555,stroke-width:2px,color:white

    class ALB,CF,S3,ECR,RDS,RunPod,Route53,Lambda,SST aws
    class NLB,CP1,CP2,CP3,Gateway,Cilium k8s
    class BE,AI app
    class Redis,Kafka infra
    class GHA_BE,GHA_AI,Trivy ci
    class OTel,Prom,Loki,Grafana,Hubble mon
    class BE_Repo,AI_Repo,Cloud_Repo git
    class ArgoServer,ArgoRepo,ArgoCtrl k8s
```

---

## 2. CI/CD 파이프라인 상세 흐름

```mermaid
sequenceDiagram
    participant Dev as 👨‍💻 개발자
    participant BE as BE Repo (GitHub)
    participant GHA as GitHub Actions (CI)
    participant Trivy as Trivy 보안 스캔
    participant ECR as AWS ECR
    participant Cloud as Cloud Repo (Manifests)
    participant Argo as ArgoCD
    participant K8s as K8s Cluster

    Dev->>BE: 1. git push (소스코드 변경)
    BE->>GHA: 2. CI 워크플로우 트리거

    rect rgb(46, 204, 113, 0.1)
        Note over GHA: CI 단계
        GHA->>GHA: 3. 테스트 실행
        GHA->>GHA: 4. Docker 이미지 빌드 (태그: commit SHA)
        GHA->>Trivy: 5. 이미지 보안 스캔
        Trivy-->>GHA: 스캔 통과
        GHA->>ECR: 6. 이미지 Push
    end

    rect rgb(52, 152, 219, 0.1)
        Note over GHA,Cloud: CD 트리거
        GHA->>Cloud: 7. kustomization.yaml 이미지 태그 업데이트 & git push
    end

    rect rgb(155, 89, 182, 0.1)
        Note over Argo,K8s: CD 단계 (GitOps)
        Cloud->>Argo: 8. Git 변경 감지 (Poll 3분 / Webhook)
        Argo->>Argo: 9. Kustomize Build (Base + Overlay 합성)
        Argo->>K8s: 10. kubectl apply (Rolling Update)
        K8s->>K8s: 11. maxSurge:1 → 새 Pod 생성
        K8s->>K8s: 12. Readiness Probe 통과 확인
        K8s->>K8s: 13. PreStop Hook → 구 Pod Graceful Shutdown
    end

    K8s-->>Dev: 14. 배포 완료 (ArgoCD UI / Discord 알림)
```

---

## 3. 네임스페이스별 리소스 배치도

```mermaid
graph LR
    subgraph NS_refit_app ["🟦 Namespace: refit-app"]
        direction TB
        GW["Cilium Gateway API<br/>(Envoy Proxy)"]
        BE_D["Deployment: refit-be<br/>replicas: 2~5 (HPA)<br/>CPU: 250m/500m<br/>Mem: 512Mi/1Gi"]
        AI_D["Deployment: refit-ai<br/>replicas: 1~2 (HPA)<br/>CPU: 200m/400m<br/>Mem: 256Mi/512Mi"]
        Redis_P["Pod: refit-redis<br/>replicas: 1 (고정)<br/>+ EBS PersistentVolume"]
        Kafka_P["Pod: refit-kafka<br/>replicas: 1 (고정)<br/>+ EBS PersistentVolume"]

        BE_SVC["Service: refit-be-svc"]
        AI_SVC["Service: refit-ai-svc"]

        GW --> BE_SVC --> BE_D
        GW --> AI_SVC --> AI_D
        BE_D --> Redis_P
        BE_D --> Kafka_P
        AI_D --> Kafka_P
    end

    subgraph NS_monitoring ["🟪 Namespace: monitoring"]
        direction TB
        OTel_D["DaemonSet: otel-collector<br/>노드당 1개"]
        Prom_D["Pod: prometheus<br/>CPU: 300m/500m<br/>Mem: 512Mi/1Gi"]
        Loki_D["Pod: loki<br/>CPU: 200m/400m<br/>Mem: 256Mi/1Gi"]
        Graf_D["Pod: grafana<br/>CPU: 100m/200m<br/>Mem: 128Mi/256Mi"]
        Hub_D["Hubble<br/>(Cilium 내장)"]

        OTel_D --> Prom_D
        OTel_D --> Loki_D
        Prom_D --> Graf_D
        Loki_D --> Graf_D
        Hub_D --> Prom_D
    end

    subgraph NS_argocd ["🟩 Namespace: argocd"]
        direction TB
        Argo_S["ArgoCD Server"]
        Argo_R["ArgoCD Repo Server"]
        Argo_C["ArgoCD App Controller"]

        Argo_S --> Argo_R --> Argo_C
    end
```

---

## 4. 트래픽 흐름 상세 (사용자 요청 → 응답)

```mermaid
flowchart LR
    User(["👤 사용자"]) -->|"HTTPS"| Route53["Route53<br/>(re-fit.kr)"]
    Route53 --> CF["CloudFront<br/>(CDN + 라우팅)"]

    %% 프론트엔드 분기
    CF -->|"정적 에셋<br/>(JS, CSS, 이미지)"| S3["S3"]
    CF -->|"SSR /<br/>API Routes"| Lambda["Lambda<br/>(SSR, BFF)"]

    %% Lambda(BFF)가 백엔드 API 호출
    Lambda -->|"API 호출<br/>(Server-side)"| ALB["AWS ALB<br/>(TLS 종료)"]

    %% 클라이언트에서 직접 백엔드 호출 (WebSocket)
    User -->|"WebSocket<br/>(wss://)"| ALB

    ALB -->|"HTTP"| NP["NodePort<br/>:30080"]
    NP --> Envoy["Cilium Envoy<br/>Proxy"]

    Envoy -->|"/api/*<br/>timeout: 60s"| BE_SVC["refit-be-svc"]
    Envoy -->|"/ws/*<br/>timeout: 3600s"| BE_SVC
    Envoy -->|"/api/ai/*"| AI_SVC["refit-ai-svc"]

    BE_SVC --> BE1["BE Pod 1"]
    BE_SVC --> BE2["BE Pod 2"]

    BE1 & BE2 <-->|"6379"| Redis["Redis"]
    BE1 & BE2 <-->|"9092"| Kafka["Kafka"]
    BE1 & BE2 -->|"5432"| RDS[("RDS")]

    AI_SVC --> AI1["AI Pod 1"]
    AI1 <-->|"9092"| Kafka
    AI1 -->|"API"| RunPod["RunPod<br/>(GPU)"]
```

---

## 5. Control Plane HA 구성

```mermaid
graph TD
    subgraph Clients ["API Server 접속 주체"]
        kubelet["Worker kubelet"]
        argocd["ArgoCD"]
        kubectl["kubectl (운영자)"]
    end

    NLB["🔀 Internal NLB<br/>TCP :6443"]

    subgraph HA_CP ["Control Plane HA (3개 AZ 분산)"]
        CP1["CP-1<br/>AZ-a<br/>API Server + etcd"]
        CP2["CP-2<br/>AZ-c<br/>API Server + etcd"]
        CP3["CP-3<br/>AZ-b<br/>API Server + etcd"]
    end

    kubelet --> NLB
    argocd --> NLB
    kubectl --> NLB
    NLB --> CP1 & CP2 & CP3

    CP1 <-.->|"Raft 합의<br/>(etcd 동기화)"| CP2
    CP2 <-.->|"Raft 합의"| CP3
    CP3 <-.->|"Raft 합의"| CP1
```

---

## 6. 장애 대응 및 롤백 흐름

```mermaid
flowchart TD
    Deploy["ArgoCD Sync<br/>(새 버전 배포)"] --> RU["Rolling Update<br/>maxSurge:1"]
    RU --> NewPod["새 Pod 생성"]
    NewPod --> Startup{"startupProbe<br/>통과?"}

    Startup -->|"Yes"| Ready{"readinessProbe<br/>통과?"}
    Startup -->|"No (재시도 초과)"| Restart["Pod 재시작"]

    Ready -->|"Yes"| Traffic["Service에 등록<br/>→ 트래픽 수신 시작"]
    Ready -->|"No"| Exclude["Service에서 제외<br/>→ 트래픽 차단"]

    Traffic --> Monitor{"배포 후 5분<br/>5xx > 5%?"}
    Monitor -->|"정상"| Done["✅ 배포 완료"]
    Monitor -->|"이상 감지"| Rollback["🔄 ArgoCD Rollback<br/>+ Discord 알림"]
    Rollback --> PrevVer["이전 안정 버전<br/>재배포"]

    Exclude --> Timeout{"600초 내<br/>복구?"}
    Timeout -->|"Yes"| Traffic
    Timeout -->|"No"| ManualRB["kubectl rollout undo"]
```

---

## 7. K8s 클러스터 + GitOps 포커스 다이어그램

> ALB 이후 K8s 클러스터 내부 구성과 GitOps(CI/CD) 배포 흐름만 집중한 다이어그램

```mermaid
graph TD
    %% ── 진입점 ──
    ALB["AWS ALB<br/>(TLS 종료)"]

    %% ── Git 저장소 ──
    subgraph GitOps ["GitOps Pipeline"]
        BE_Repo["BE Repo<br/>(Spring Boot)"]
        AI_Repo["AI Repo<br/>(FastAPI)"]
        GHA["GitHub Actions<br/>(CI: Test → Build →<br/>Trivy 스캔 → ECR Push)"]
        ECR["AWS ECR"]
        Cloud_Repo["Cloud Repo<br/>(K8s Manifests /<br/>Kustomize)"]
    end

    %% ── Kubernetes 클러스터 ──
    subgraph K8s_Cluster ["Kubernetes Cluster (kubeadm)"]

        %% Control Plane HA
        subgraph CP ["Control Plane HA (t3.medium × 3, 3 AZ)"]
            NLB["Internal NLB<br/>:6443"]
            CP1["CP-1 (AZ-a)<br/>API Server / etcd<br/>Scheduler / Controller Manager"]
            CP2["CP-2 (AZ-c)<br/>API Server / etcd<br/>Scheduler / Controller Manager"]
            CP3["CP-3 (AZ-b)<br/>API Server / etcd<br/>Scheduler / Controller Manager"]
        end

        %% Worker Node (물리 인프라 레이어)
        subgraph Worker_Nodes ["Worker Nodes (t3.large × 2~3)"]
            subgraph W1 ["Worker-1 (AZ-a)"]
                W1_Kubelet["kubelet"]
                W1_KubeProxy["kube-proxy"]
                W1_Cilium["Cilium Agent"]
            end
            subgraph W2 ["Worker-2 (AZ-c)"]
                W2_Kubelet["kubelet"]
                W2_KubeProxy["kube-proxy"]
                W2_Cilium["Cilium Agent"]
            end
            subgraph W3 ["Worker-3 (AZ-a) — 피크 시 추가"]
                W3_Kubelet["kubelet"]
                W3_KubeProxy["kube-proxy"]
                W3_Cilium["Cilium Agent"]
            end
        end

        %% Pod 논리 배치 레이어 (스케줄러가 동적 배치)
        subgraph Pod_Layer ["Pod 배치 레이어 (동적 스케줄링)"]

            %% ── Namespace: kube-system ──
            subgraph NS_System ["Namespace: kube-system"]
                CoreDNS["CoreDNS<br/>(클러스터 내부 DNS /<br/>서비스 디스커버리)"]
                MetricsSvr["Metrics Server<br/>(HPA용 CPU/Mem<br/>메트릭 수집)"]
                EBS_CSI["EBS CSI Driver<br/>(PV 동적 프로비저닝)"]
            end

            %% ── Namespace: refit-app ──
            subgraph NS_App ["Namespace: refit-app"]
                Gateway["Cilium Gateway API<br/>(Envoy Proxy)<br/>NodePort 30080"]

                BE["BE Pod (Spring Boot)<br/>HPA: 2~5<br/>CPU: 250m/500m<br/>Mem: 512Mi/1Gi"]
                AI["AI Pod (FastAPI)<br/>HPA: 1~2<br/>CPU: 200m/400m<br/>Mem: 256Mi/512Mi"]

                Redis["Redis Pod<br/>Single + EBS PV"]
                Kafka["Kafka Pod<br/>KRaft + EBS PV"]
            end

            %% ── Namespace: monitoring ──
            subgraph NS_Mon ["Namespace: monitoring"]
                OTel["OTel Collector<br/>(DaemonSet)"]
                Prom["Prometheus"]
                Loki["Loki"]
                Grafana["Grafana"]
                Hubble["Hubble<br/>(Cilium 내장)"]
            end

            %% ── Namespace: argocd ──
            subgraph NS_Argo ["Namespace: argocd"]
                ArgoServer["ArgoCD Server"]
                ArgoRepo["ArgoCD Repo Server"]
                ArgoCtrl["ArgoCD App Controller"]
            end
        end
    end

    %% ── 외부 서비스 ──
    RDS[("Amazon RDS<br/>PostgreSQL")]
    RunPod["RunPod<br/>(LLM / GPU)"]
    EBS[("AWS EBS<br/>(gp3 볼륨)")]
    Discord["Discord<br/>(알림)"]

    %% ━━━━━━ ALB → 클러스터 트래픽 ━━━━━━
    ALB -->|"HTTP :30080"| Gateway
    Gateway -->|"/api, /ws"| BE
    Gateway -->|"/api/ai"| AI

    %% ━━━━━━ 서비스 간 통신 ━━━━━━
    BE <-->|"Session / Pub·Sub"| Redis
    BE <-->|"Produce / Consume"| Kafka
    AI <-->|"Consume / Produce"| Kafka
    BE -->|"SQL"| RDS
    AI -->|"Model Predict"| RunPod

    %% ━━━━━━ Worker 노드 → CP 통신 ━━━━━━
    W1_Kubelet -->|"Pod 상태 보고"| NLB
    W2_Kubelet -->|"Pod 상태 보고"| NLB
    W3_Kubelet -.->|"Pod 상태 보고"| NLB

    %% ━━━━━━ Worker 노드 → Pod 레이어 ━━━━━━
    W1 ---|"Pod 호스팅"| Pod_Layer
    W2 ---|"Pod 호스팅"| Pod_Layer

    %% ━━━━━━ kube-system 연결 ━━━━━━
    CoreDNS -.->|"DNS 해석<br/>(svc.cluster.local)"| NS_App
    MetricsSvr -->|"CPU/Mem<br/>메트릭 수집"| W1_Kubelet
    MetricsSvr -->|"CPU/Mem<br/>메트릭 수집"| W2_Kubelet

    %% ━━━━━━ EBS CSI ↔ PV ━━━━━━
    EBS_CSI -->|"PV 프로비저닝"| EBS
    Redis -.->|"PVC"| EBS_CSI
    Kafka -.->|"PVC"| EBS_CSI

    %% ━━━━━━ GitOps CI/CD 흐름 ━━━━━━
    BE_Repo --> GHA
    AI_Repo --> GHA
    GHA -->|"이미지 Push"| ECR
    GHA -->|"이미지 태그 업데이트<br/>(kustomize edit set image)"| Cloud_Repo
    Cloud_Repo -->|"Git Poll /<br/>Webhook"| ArgoServer
    ArgoServer --> ArgoRepo
    ArgoRepo -->|"Manifest<br/>렌더링"| ArgoCtrl
    ArgoCtrl -->|"Sync &<br/>Rolling Update"| NS_App
    ArgoCtrl -->|"K8s API"| NLB

    %% ━━━━━━ Control Plane HA ━━━━━━
    NLB --> CP1 & CP2 & CP3
    CP1 <-.->|"Raft"| CP2
    CP2 <-.->|"Raft"| CP3
    CP3 <-.->|"Raft"| CP1

    %% ━━━━━━ 모니터링 ━━━━━━
    BE -.->|"OTLP"| OTel
    AI -.->|"OTLP"| OTel
    OTel -.->|"메트릭"| Prom
    OTel -.->|"로그"| Loki
    Hubble -.->|"네트워크 메트릭"| Prom
    Prom -.-> Grafana
    Loki -.-> Grafana
    Prom -.->|"Alertmanager"| Discord

    %% ━━━━━━ 스타일 ━━━━━━
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:black,font-weight:bold
    classDef k8s fill:#326CE5,stroke:#fff,stroke-width:2px,color:white
    classDef app fill:#E5F5FA,stroke:#00A2CC,stroke-width:2px,color:black
    classDef infra fill:#FFE2ED,stroke:#FF4081,stroke-width:2px,color:black
    classDef ci fill:#2ECC71,stroke:#27AE60,stroke-width:2px,color:white
    classDef mon fill:#9B59B6,stroke:#8E44AD,stroke-width:2px,color:white
    classDef git fill:#333,stroke:#555,stroke-width:2px,color:white
    classDef system fill:#1ABC9C,stroke:#16A085,stroke-width:2px,color:white
    classDef worker fill:#3498DB,stroke:#2980B9,stroke-width:2px,color:white

    class ALB,ECR,RDS,RunPod,EBS aws
    class NLB,CP1,CP2,CP3,Gateway k8s
    class BE,AI app
    class Redis,Kafka infra
    class GHA ci
    class OTel,Prom,Loki,Grafana,Hubble mon
    class BE_Repo,AI_Repo,Cloud_Repo git
    class ArgoServer,ArgoRepo,ArgoCtrl k8s
    class CoreDNS,MetricsSvr,EBS_CSI system
    class W1_Kubelet,W1_KubeProxy,W1_Cilium,W2_Kubelet,W2_KubeProxy,W2_Cilium,W3_Kubelet,W3_KubeProxy,W3_Cilium worker
```

