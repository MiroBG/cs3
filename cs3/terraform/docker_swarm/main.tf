terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Docker Swarm Manager Nodes (IaC for research comparison)
# This module provisions EC2 instances for Docker Swarm orchestration
# Runs in parallel to EKS as a comparison baseline

variable "swarm_manager_count" {
  type        = number
  default     = 3
  description = "Number of Docker Swarm manager nodes"
}

variable "swarm_worker_count" {
  type        = number
  default     = 3
  description = "Number of Docker Swarm worker nodes"
}

variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for Swarm nodes"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where Swarm cluster will be deployed"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for Swarm nodes"
}

variable "key_name" {
  type        = string
  description = "EC2 key pair for SSH access"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to all resources"
}

# Security group for Swarm cluster
resource "aws_security_group" "swarm" {
  name_prefix = "swarm-"
  description = "Security group for Docker Swarm cluster"
  vpc_id      = var.vpc_id

  # Swarm API communication
  ingress {
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict in production
  }

  # Container network discovery
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Overlay network data path
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Application traffic (HTTP/HTTPS)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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

  tags = merge(var.tags, { Name = "swarm-sg" })
}

# IAM role for Swarm nodes (CloudWatch logs, EC2 describe)
resource "aws_iam_role" "swarm_node" {
  name_prefix = "swarm-node-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "swarm_cloudwatch" {
  role       = aws_iam_role.swarm_node.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "swarm_ssm" {
  role       = aws_iam_role.swarm_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "swarm_node" {
  name_prefix = "swarm-node-"
  role        = aws_iam_role.swarm_node.name
}

# User data script for Swarm initialization
locals {
  manager_init_script = base64encode(templatefile("${path.module}/user_data_manager.sh", {}))
  worker_init_script  = base64encode(templatefile("${path.module}/user_data_worker.sh", {}))
}

# Manager nodes
resource "aws_instance" "swarm_manager" {
  count                    = var.swarm_manager_count
  ami                      = data.aws_ami.ubuntu.id
  instance_type            = var.instance_type
  key_name                 = var.key_name
  subnet_id                = var.subnet_ids[count.index % length(var.subnet_ids)]
  iam_instance_profile     = aws_iam_instance_profile.swarm_node.name
  vpc_security_group_ids   = [aws_security_group.swarm.id]
  user_data                = local.manager_init_script
  associate_public_ip_address = true

  tags = merge(var.tags, {
    Name = "swarm-manager-${count.index + 1}"
    Role = "manager"
  })
}

# Worker nodes
resource "aws_instance" "swarm_worker" {
  count                    = var.swarm_worker_count
  ami                      = data.aws_ami.ubuntu.id
  instance_type            = var.instance_type
  key_name                 = var.key_name
  subnet_id                = var.subnet_ids[count.index % length(var.subnet_ids)]
  iam_instance_profile     = aws_iam_instance_profile.swarm_node.name
  vpc_security_group_ids   = [aws_security_group.swarm.id]
  user_data                = local.worker_init_script
  associate_public_ip_address = true

  tags = merge(var.tags, {
    Name = "swarm-worker-${count.index + 1}"
    Role = "worker"
  })
}

# Fetch latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

output "swarm_manager_ips" {
  value       = aws_instance.swarm_manager[*].public_ip
  description = "Public IPs of Swarm manager nodes"
}

output "swarm_worker_ips" {
  value       = aws_instance.swarm_worker[*].public_ip
  description = "Public IPs of Swarm worker nodes"
}

output "swarm_security_group_id" {
  value       = aws_security_group.swarm.id
  description = "Security group ID for Swarm cluster"
}
