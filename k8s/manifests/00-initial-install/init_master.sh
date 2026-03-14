#!/usr/bin/env bash
set -euo pipefail

# Kubernetes / container runtime version settings (keep in sync with worker_node.sh).
K8S_REPO_VERSION="${K8S_REPO_VERSION:-v1.34}"

API_SERVER_IP="${API_SERVER_IP:-$(hostname -I | awk '{print $1}')}"
API_SERVER_PORT="6443"
POD_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
CILIUM_VERSION="1.19.1"
GATEWAY_API_VERSION="v1.4.1"
NODE_NAME="${NODE_NAME:-$(hostname -s)}"
MASTER_HOSTNAME="${MASTER_HOSTNAME:-${NODE_NAME}}"
SCHEDULE_ON_CONTROL_PLANE="${SCHEDULE_ON_CONTROL_PLANE:-false}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script is intended for Ubuntu 22.04 and requires apt-get." >&2
  exit 1
fi

BOOTSTRAP_PACKAGES=(
  ca-certificates
  curl
  tar
  socat
  conntrack
  gnupg
  apt-transport-https
)

append_if_missing() {
  local line="$1"
  local file="$2"
  touch "${file}"
  grep -Fqx "${line}" "${file}" || echo "${line}" >> "${file}"
}

install_packages() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

refresh_package_index() {
  DEBIAN_FRONTEND=noninteractive apt-get update
}

setup_containerd_repo() {
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  refresh_package_index
}

setup_kubernetes_repo() {
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_REPO_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo \
    "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_REPO_VERSION}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list
  refresh_package_index
}

deferred_components=()
SCRIPT_PATH="$(readlink -f "$0")"

wait_for_deployment_if_schedulable() {
  local namespace="$1"
  local deployment="$2"
  local timeout="${3:-10m}"

  if has_schedulable_node; then
    kubectl -n "${namespace}" rollout status "deploy/${deployment}" --timeout="${timeout}"
    return
  fi

  deferred_components+=("${namespace}/${deployment}")
  echo "Skipping rollout wait for ${namespace}/${deployment}: no schedulable worker node yet."
}

has_schedulable_node() {
  if [[ "${SCHEDULE_ON_CONTROL_PLANE}" == "true" ]]; then
    return 0
  fi

  kubectl get nodes --no-headers 2>/dev/null | awk '$2 ~ /^Ready/ && $3 !~ /control-plane/ { found=1 } END { exit(found ? 0 : 1) }'
}

echo '======== [4-1] 타임존 설정 ========'
timedatectl set-timezone Asia/Seoul
timedatectl set-ntp true
if command -v chronyc >/dev/null 2>&1; then
  chronyc makestep || true
fi

echo '======= [4-2] hosts 설정 =========='
if ! grep -Eq "^[[:space:]]*${API_SERVER_IP}[[:space:]]+${MASTER_HOSTNAME}([[:space:]]|$)" /etc/hosts; then
  echo "${API_SERVER_IP} ${MASTER_HOSTNAME}" >> /etc/hosts
fi
if ! grep -Eq "^[[:space:]]*${API_SERVER_IP}[[:space:]]+${NODE_NAME}([[:space:]]|$)" /etc/hosts; then
  echo "${API_SERVER_IP} ${NODE_NAME}" >> /etc/hosts
fi

echo '======== [5] kubeadm 설치 전 사전작업 ========'
echo '======== [5-0] 기본 패키지 설치 ========'
refresh_package_index
install_packages "${BOOTSTRAP_PACKAGES[@]}"

echo '======== [5] 방화벽 해제 ========'
systemctl disable --now firewalld || true
systemctl disable --now ufw || true

echo '======== [5] Swap 비활성화 ========'
swapoff -a && sed -i '/ swap / s/^/#/' /etc/fstab

echo '======== [6] 컨테이너 런타임 설치 ========'
echo '======== [6-1] 컨테이너 런타임 설치 전 사전작업 ========'
echo '======== [6-1] 커널 모듈 및 sysctl 설정 ========'
cat <<'EOF' > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<'EOF' > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

echo '======== [6-2] 컨테이너 런타임 (containerd 설치) ========'
echo '======== [6-2-1] containerd 패키지 설치 (option2) ========'
echo '======== [6-2-1-1] docker engine 설치 ========'
echo '======== [6-2-1-1] repo 설정 ========'
setup_containerd_repo

echo '======== [6-2-1-1] containerd 설치 ========'
install_packages containerd.io
systemctl daemon-reload
systemctl enable --now containerd

echo '======== [6-3] 컨테이너 런타임 : cri 활성화 ========'
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/^\(\s*SystemdCgroup = \)false/\1true/' /etc/containerd/config.toml
sed -i 's#sandbox_image = "registry.k8s.io/pause:3.8"#sandbox_image = "registry.k8s.io/pause:3.10.1"#' /etc/containerd/config.toml
systemctl restart containerd

echo '======== [7] kubeadm 설치 ========'
echo '======== [7] repo 설정 ========'
setup_kubernetes_repo

echo '======== [7] SELinux 설정 ========'
true

echo '======== [7] kubelet, kubeadm, kubectl 패키지 설치 ========'
install_packages kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

echo '======== [8] kubeadm으로 클러스터 생성  ========'
if [[ -f /etc/kubernetes/admin.conf ]] && [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]]; then
  echo '======== [8-1] 기존 control plane 감지: kubeadm init 생략 ========'
else
  echo '======== [8-1] 클러스터 초기화 (Pod Network 세팅) ========'
  kubeadm init \
    --apiserver-advertise-address "$API_SERVER_IP" \
    --pod-network-cidr "$POD_CIDR" \
    --service-cidr "$SERVICE_CIDR" \
    --node-name "${NODE_NAME}" \
    --skip-phases=addon/kube-proxy
fi

echo '======== [8-2] kubectl 사용 설정 ========'
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

if [[ "${SCHEDULE_ON_CONTROL_PLANE}" == "true" ]]; then
  echo '======== [8-3] Control Plane 노드에 Pod 생성 허용 ========'
  kubectl taint nodes "${NODE_NAME}" node-role.kubernetes.io/control-plane:NoSchedule- || true
fi

echo '======== [9] 쿠버네티스 편의기능 설치 ========'
echo '======== [9-1] kubectl 자동완성 기능 ========'
append_if_missing 'source <(kubectl completion bash)' ~/.bashrc
append_if_missing 'alias k=kubectl' ~/.bashrc
append_if_missing 'complete -o default -F __start_kubectl k' ~/.bashrc

echo '======== [9-2] Helm 설치 ========'
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) HELM_ARCH="amd64" ;;
  aarch64|arm64) HELM_ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac
HELM_TARBALL="helm-v3.19.2-linux-${HELM_ARCH}.tar.gz"
if ! command -v helm >/dev/null 2>&1; then
  curl -LO "https://get.helm.sh/${HELM_TARBALL}"
  tar -zxf "${HELM_TARBALL}"
  install -m 0755 "linux-${HELM_ARCH}/helm" /usr/bin/helm
fi

echo '======== [9-3] Gateway API CRD 설치 ========'
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_gateways.yaml"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml"

echo '======== [9-4] Cilium 설치 (VXLAN + Gateway API) ========'
helm repo add cilium https://helm.cilium.io/
helm repo update
helm upgrade --install cilium cilium/cilium --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="${API_SERVER_IP}" \
  --set k8sServicePort="${API_SERVER_PORT}" \
  --set gatewayAPI.enabled=true \
  --set envoy.enabled=true \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true
kubectl -n kube-system rollout status ds/cilium --timeout=10m
wait_for_deployment_if_schedulable kube-system cilium-operator 10m

echo '======== [9-5] Metrics-server 설치 ========'
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# kubeadm/self-managed clusters often need insecure kubelet TLS and InternalIP preference.
kubectl -n kube-system patch deployment metrics-server --type='strategic' -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "metrics-server",
            "args": [
              "--cert-dir=/tmp",
              "--secure-port=10250",
              "--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP",
              "--kubelet-use-node-status-port",
              "--metric-resolution=15s",
              "--kubelet-insecure-tls"
            ]
          }
        ]
      }
    }
  }
}'
wait_for_deployment_if_schedulable kube-system metrics-server 10m

echo '======== [10] Cert-Manager 설치 ========'
if has_schedulable_node; then
  helm repo add jetstack https://charts.jetstack.io
  helm repo update
  helm upgrade --install cert-manager jetstack/cert-manager --version 1.19.1 --namespace cert-manager --create-namespace --set featureGates="ExperimentalCertificateSigningRequestControllers=true" --set crds.enabled=true
  wait_for_deployment_if_schedulable cert-manager cert-manager 10m
  wait_for_deployment_if_schedulable cert-manager cert-manager-cainjector 10m
  wait_for_deployment_if_schedulable cert-manager cert-manager-webhook 10m
else
  deferred_components+=("cert-manager/cert-manager" "cert-manager/cert-manager-cainjector" "cert-manager/cert-manager-webhook")
  echo 'Skipping cert-manager install: no schedulable worker node yet.'
fi

echo '======== [11] Worker 조인 명령 출력 ========'
JOIN_COMMAND="$(kubeadm token create --print-join-command)"
if [[ "${JOIN_COMMAND}" != *"--node-name"* ]]; then
  echo "${JOIN_COMMAND} --node-name <worker-node-name>"
else
  echo "${JOIN_COMMAND}"
fi

if (( ${#deferred_components[@]} > 0 )); then
  echo '======== [12] 후속 작업 안내 ========'
  echo 'Worker 노드가 Ready 상태가 되면 아래 명령으로 master 스크립트를 한 번 더 실행하세요.'
  echo "sudo bash ${SCRIPT_PATH}"
  echo '대기 중인 컴포넌트:'
  printf ' - %s\n' "${deferred_components[@]}" | sort -u
fi
