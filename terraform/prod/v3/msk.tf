# -----------------------------------------------------
# MSK (Amazon Managed Streaming for Kafka)
# refit prod v3 - self-managed K8s
# 2 brokers, kafka.t3.small, Kafka 3.7.x, 20GB EBS
# Unauthenticated (plaintext 9092)
# -----------------------------------------------------

resource "aws_msk_cluster" "kafka" {
  cluster_name           = "refit-kafka"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.kafka_broker_count

  broker_node_group_info {
    instance_type = var.kafka_broker_instance_type

    # 2 브로커 → 2 AZ (ap-northeast-2a, ap-northeast-2c)
    client_subnets = [
      aws_subnet.pub_a.id,
      aws_subnet.pub_c.id,
    ]

    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.kafka_ebs_volume_size
      }
    }
  }

  client_authentication {
    unauthenticated = true
  }

  # Prometheus 기반 모니터링 (KMinion이 사용하는 JMX + Node exporter)
  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
      in_cluster    = true
    }
  }

  tags = { Name = "refit-kafka" }
}
