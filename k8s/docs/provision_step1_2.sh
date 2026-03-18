#!/bin/bash
set -e

PROJECT="refit-k8s"
VPC_NAME="${PROJECT}-vpc"
VPC_CIDR="10.2.0.0/16"
REGION="ap-northeast-2"
PUB_SUBNET_A="10.2.1.0/24"
PUB_SUBNET_C="10.2.2.0/24"

echo "=== [Step 1] VPC 및 서브넷 생성 ==="
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

PUB_SUB_A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUB_SUBNET_A --availability-zone ${REGION}a --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PUB_SUB_A --tags Key=Name,Value=$PROJECT-pub-a
aws ec2 modify-subnet-attribute --subnet-id $PUB_SUB_A --map-public-ip-on-launch

PUB_SUB_C=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUB_SUBNET_C --availability-zone ${REGION}c --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PUB_SUB_C --tags Key=Name,Value=$PROJECT-pub-c
aws ec2 modify-subnet-attribute --subnet-id $PUB_SUB_C --map-public-ip-on-launch

IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value=$PROJECT-igw
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

PUB_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $PUB_RT --tags Key=Name,Value=$PROJECT-pub-rt
aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID > /dev/null
aws ec2 associate-route-table --subnet-id $PUB_SUB_A --route-table-id $PUB_RT > /dev/null
aws ec2 associate-route-table --subnet-id $PUB_SUB_C --route-table-id $PUB_RT > /dev/null

echo "=== [Step 2] 보안 그룹(SG) 생성 및 규칙 할당 ==="
MASTER_SG=$(aws ec2 create-security-group --group-name k8s-master-sg --description "SG for Master Node" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $MASTER_SG --tags Key=Name,Value=$PROJECT-master-sg

WORKER_SG=$(aws ec2 create-security-group --group-name k8s-worker-sg --description "SG for Worker Node" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $WORKER_SG --tags Key=Name,Value=$PROJECT-worker-sg

ALB_SG=$(aws ec2 create-security-group --group-name k8s-alb-sg --description "SG for ALB" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $ALB_SG --tags Key=Name,Value=$PROJECT-alb-sg

MY_IP=$(curl -s https://checkip.amazonaws.com)/32
echo "My IP is $MY_IP"

# Master SG Rules
aws ec2 authorize-security-group-ingress --group-id $MASTER_SG --protocol tcp --port 22 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $MASTER_SG --protocol tcp --port 6443 --cidr $VPC_CIDR
aws ec2 authorize-security-group-ingress --group-id $MASTER_SG --protocol -1 --source-group $MASTER_SG

# Worker SG Rules
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG --protocol tcp --port 22 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG --protocol tcp --port 30080 --cidr $VPC_CIDR
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG --protocol tcp --port 30080 --source-group $ALB_SG
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG --protocol -1 --source-group $WORKER_SG
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG --protocol -1 --source-group $MASTER_SG

# ALB SG Rules
aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0

echo "✅ Step 1, 2 완료!"
echo "- VPC_ID: $VPC_ID"
echo "- MASTER_SG: $MASTER_SG"
echo "- WORKER_SG: $WORKER_SG"
echo "- ALB_SG: $ALB_SG"
