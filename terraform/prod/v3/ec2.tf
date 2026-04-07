# -----------------------------------------------------
# EC2 Instances (refit prod v3 - self-managed K8s)
# Master: 3x t4g.medium (Ubuntu 22.04 ARM64, 30GB gp3)
# Worker: 3x t4g.large  (Ubuntu 22.04 ARM64, 50GB gp3)
# -----------------------------------------------------

# ------- Master Nodes -------
resource "aws_instance" "master" {
  for_each = local.master_nodes

  ami                         = local.k8s_ami_id
  instance_type               = var.master_instance_type
  key_name                    = var.key_name
  subnet_id                   = local.subnet_ids[each.value.subnet_key]
  private_ip                  = each.value.private_ip
  vpc_security_group_ids      = [aws_security_group.master.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.master_root_volume_size
    delete_on_termination = true
  }

  tags = {
    Name = each.value.name
    Role = "master"
  }
}

# ------- Worker Nodes -------
resource "aws_instance" "worker" {
  for_each = local.worker_nodes

  ami                         = local.k8s_ami_id
  instance_type               = var.worker_instance_type
  key_name                    = var.key_name
  subnet_id                   = local.subnet_ids[each.value.subnet_key]
  private_ip                  = each.value.private_ip
  vpc_security_group_ids      = [aws_security_group.worker.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.worker_root_volume_size
    delete_on_termination = true
  }

  tags = {
    Name = each.value.name
    Role = "worker"
  }
}
