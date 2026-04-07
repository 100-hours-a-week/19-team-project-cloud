# -----------------------------------------------------
# Locals (refit prod v3 - self-managed K8s)
# -----------------------------------------------------
locals {
  prefix = "${var.project_name}-k8s"

  # AMI: Ubuntu 22.04 LTS ARM64 (Canonical official)
  # ami-028a89fd47585df22 = ubuntu-jammy-22.04-arm64-server-20251212
  k8s_ami_id = "ami-028a89fd47585df22"

  # Master node private IPs (fixed for NLB target registration & kubeadm join)
  master_nodes = {
    master_1 = {
      name       = "refit-master-1"
      private_ip = "10.2.1.5"
      subnet_key = "pub_a"
      az         = "ap-northeast-2a"
    }
    master_2 = {
      name       = "refit-master-2"
      private_ip = "10.2.3.32"
      subnet_key = "pub_b"
      az         = "ap-northeast-2b"
    }
    master_3 = {
      name       = "refit-master-3"
      private_ip = "10.2.2.173"
      subnet_key = "pub_c"
      az         = "ap-northeast-2c"
    }
  }

  # Worker node config
  worker_nodes = {
    worker_1 = {
      name       = "refit-worker-1"
      private_ip = "10.2.1.227"
      subnet_key = "pub_a"
      az         = "ap-northeast-2a"
    }
    worker_2 = {
      name       = "refit-worker-2"
      private_ip = "10.2.2.139"
      subnet_key = "pub_c"
      az         = "ap-northeast-2c"
    }
    worker_3 = {
      name       = "refit-worker-3"
      private_ip = "10.2.1.142"
      subnet_key = "pub_a"
      az         = "ap-northeast-2a"
    }
  }

  # NLB DNS (used by Cilium as k8sServiceHost)
  cp_nlb_dns = "refit-k8s-cp-nlb-d4b7b4ab87ff588f.elb.ap-northeast-2.amazonaws.com"
}
