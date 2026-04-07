# -----------------------------------------------------
# Security Groups (refit prod v3 - self-managed K8s)
# -----------------------------------------------------

# ------- ALB Security Group -------
resource "aws_security_group" "alb" {
  name        = "k8s-alb-sg"
  description = "SG for ALB"
  vpc_id      = aws_vpc.k8s.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k8s-alb-sg" }
}

# ------- Master Node Security Group -------
resource "aws_security_group" "master" {
  name        = "k8s-master-sg"
  description = "SG for Master Node"
  vpc_id      = aws_vpc.k8s.id

  # SSH - 허용된 IP만
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat(var.ssh_allowed_cidrs, var.ssh_allowed_cidrs_master_extra)
  }

  # K8s API server - VPC 내부 전체 (worker, NLB health check 포함)
  ingress {
    description = "K8s API server from VPC"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Master-to-Master 전체 통신 (etcd, controller 등)
  ingress {
    description = "All traffic between master nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Kubelet API - worker → master
  ingress {
    description     = "Kubelet API from workers"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  # Cilium VXLAN overlay (UDP 8472) - worker → master
  ingress {
    description     = "Cilium VXLAN overlay from workers"
    from_port       = 8472
    to_port         = 8472
    protocol        = "udp"
    security_groups = [aws_security_group.worker.id]
  }

  # Cilium Hubble (TCP 4244) - worker → master
  ingress {
    description     = "Cilium Hubble from workers"
    from_port       = 4244
    to_port         = 4244
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k8s-master-sg" }
}

# ------- Worker Node Security Group -------
resource "aws_security_group" "worker" {
  name        = "k8s-worker-sg"
  description = "SG for Worker Node"
  vpc_id      = aws_vpc.k8s.id

  # SSH - 허용된 IP만
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  # NodePort (30080) - ALB SG에서 접근
  ingress {
    description     = "NodePort from ALB"
    from_port       = var.alb_nodeport
    to_port         = var.alb_nodeport
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # NodePort (30080) - VPC 내부에서 접근 (health check, 내부 통신)
  ingress {
    description = "NodePort from VPC internal"
    from_port   = var.alb_nodeport
    to_port     = var.alb_nodeport
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Master → Worker 전체 (kubelet, CNI 등)
  ingress {
    description     = "All traffic from master nodes"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.master.id]
  }

  # Worker-to-Worker 전체 (Cilium overlay, pod 통신)
  ingress {
    description = "All traffic between worker nodes (K8s overlay)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k8s-worker-sg" }
}

# ------- MSK Security Group -------
resource "aws_security_group" "msk" {
  name        = "refit-msk-sg"
  description = "MSK Kafka - allow from K8s workers"
  vpc_id      = aws_vpc.k8s.id

  ingress {
    description     = "Kafka plaintext from K8s workers"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "refit-msk-sg" }
}

# ------- ElastiCache Security Group -------
resource "aws_security_group" "elasticache" {
  name        = "refit-elasticache-sg"
  description = "ElastiCache Redis - allow from K8s workers"
  vpc_id      = aws_vpc.k8s.id

  ingress {
    description     = "Valkey/Redis from K8s workers"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "refit-elasticache-sg" }
}
