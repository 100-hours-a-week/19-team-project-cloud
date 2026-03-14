#!/usr/bin/env bash

set -euo pipefail

# Kubernetes / container runtime 버전 설정 (control-plane 스크립트와 동일하게 유지)
K8S_REPO_VERSION="${K8S_REPO_VERSION:-v1.34}"

SCRIPT_PATH="$(readlink -f "$0")"

# Worker 부트스트랩 설정
TIMEZONE="${TIMEZONE:-Asia/Seoul}"
MASTER_HOSTNAME="${MASTER_HOSTNAME:-}"
MASTER_IP="${MASTER_IP:-}"
NODE_NAME="${NODE_NAME:-$(hostname -s)}"
KUBEADM_JOIN_CMD="${KUBEADM_JOIN_CMD:-}"
CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-}"
BOOTSTRAP_TOKEN="${BOOTSTRAP_TOKEN:-}"
DISCOVERY_TOKEN_CA_CERT_HASH="${DISCOVERY_TOKEN_CA_CERT_HASH:-}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "이 스크립트는 root 권한으로 실행해야 합니다." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "이 스크립트는 Ubuntu 22.04 환경용이며 apt-get이 필요합니다." >&2
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

echo '======== [1] EC2 기본 설정 ========'

echo '======== [1-1] 타임존 설정 ========'
timedatectl set-timezone "${TIMEZONE}"
timedatectl set-ntp true
if command -v chronyc >/dev/null 2>&1; then
  chronyc makestep || true
fi

echo '======== [1-2] hosts 설정 ========'
if [[ -n "${MASTER_IP}" && -n "${MASTER_HOSTNAME}" ]] && ! grep -Eq "^[[:space:]]*${MASTER_IP}[[:space:]]+${MASTER_HOSTNAME}([[:space:]]|$)" /etc/hosts; then
  echo "${MASTER_IP} ${MASTER_HOSTNAME}" >> /etc/hosts
fi

echo '======== [2] kubeadm 설치 전 사전작업 ========'
echo '======== [2-0] 기본 패키지 설치 ========'
refresh_package_index
install_packages "${BOOTSTRAP_PACKAGES[@]}"

echo '======== [2-1] 방화벽 해제 ========'
systemctl disable --now firewalld || true
systemctl disable --now ufw || true

echo '======== [2-2] Swap 비활성화 ========'
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo '======== [2-3] 커널 모듈 및 sysctl 설정 ========'
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

echo '======== [3] 컨테이너 런타임 설치 ========'

echo '======== [3-1] containerd 설치 ========'
setup_containerd_repo
install_packages containerd.io
systemctl daemon-reload
systemctl enable --now containerd

echo '======== [3-2] containerd SystemdCgroup 설정 ========'
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/^\(\s*SystemdCgroup = \)false/\1true/' /etc/containerd/config.toml
sed -i 's#sandbox_image = "registry.k8s.io/pause:3.8"#sandbox_image = "registry.k8s.io/pause:3.10.1"#' /etc/containerd/config.toml
systemctl restart containerd

echo '======== [4] kubeadm / kubelet 설치 ========'

echo '======== [4-1] Kubernetes repo 설정 ========'
setup_kubernetes_repo

echo '======== [4-2] SELinux 설정 ========'
true

echo '======== [4-3] kubelet, kubeadm 설치 ========'
install_packages kubelet kubeadm
apt-mark hold kubelet kubeadm
systemctl enable --now kubelet

echo '======== [5] Worker 노드 클러스터 조인 ========'

if [[ -f /etc/kubernetes/kubelet.conf ]] && systemctl is-active --quiet kubelet; then
  echo '======== [5-1] 기존 worker 조인 감지: kubeadm join 생략 ========'
else
  if [[ -n "${KUBEADM_JOIN_CMD}" ]]; then
    read -r -a JOIN_ARGS <<< "${KUBEADM_JOIN_CMD}"
    if [[ "${KUBEADM_JOIN_CMD}" != *"--node-name "* ]]; then
      JOIN_ARGS+=(--node-name "${NODE_NAME}")
    fi
  else
    if [[ -z "${CONTROL_PLANE_ENDPOINT}" || -z "${BOOTSTRAP_TOKEN}" || -z "${DISCOVERY_TOKEN_CA_CERT_HASH}" ]]; then
      echo "KUBEADM_JOIN_CMD 또는 CONTROL_PLANE_ENDPOINT, BOOTSTRAP_TOKEN, DISCOVERY_TOKEN_CA_CERT_HASH를 모두 설정하세요." >&2
      exit 1
    fi
    JOIN_ARGS=(
      kubeadm join "${CONTROL_PLANE_ENDPOINT}"
      --token "${BOOTSTRAP_TOKEN}"
      --discovery-token-ca-cert-hash "${DISCOVERY_TOKEN_CA_CERT_HASH}"
      --node-name "${NODE_NAME}"
    )
  fi

  echo '======== [5-1] kubeadm join 실행 ========'
  "${JOIN_ARGS[@]}"

  echo '======== [5-2] kubelet 활성화 확인 ========'
  systemctl is-active --quiet kubelet || { echo "조인 후 kubelet이 활성화되지 않았습니다." >&2; exit 1; }
fi

echo '======== [6] 완료 ========'
echo "Worker 노드 부트스트랩이 완료되었습니다."
echo "실행 스크립트: ${SCRIPT_PATH}"
