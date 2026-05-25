locals {
  common_tags = merge(var.tags, {
    Project = "cs3"
  })
}

# Security group for EC2 instance
resource "aws_security_group" "k3s" {
  name        = "${var.name_prefix}-k3s-sg${var.resource_suffix_part}"
  description = "Security group for k3s instance"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-k3s-sg${var.resource_suffix_part}"
  })
}

# Allow SSH access (restrict to your IP if needed)
resource "aws_security_group_rule" "k3s_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]  # Restrict to your IP in production
  security_group_id = aws_security_group.k3s.id
}

# Allow HTTP for portal and monitoring
resource "aws_security_group_rule" "k3s_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s.id
}

# Allow HTTPS for portal and monitoring
resource "aws_security_group_rule" "k3s_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s.id
}

# Allow k3s API server traffic
resource "aws_security_group_rule" "k3s_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s.id
}

# Allow container port range
resource "aws_security_group_rule" "k3s_containers" {
  type              = "ingress"
  from_port         = 8000
  to_port           = 9999
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s.id
}

# Allow PostgreSQL access from within VPC
resource "aws_security_group_rule" "k3s_postgres" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.k3s.id
}

# Allow all outbound traffic
resource "aws_security_group_rule" "k3s_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s.id
}

# Get latest Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM role for EC2 instance
resource "aws_iam_role" "k3s" {
  name = "${var.name_prefix}-k3s-role${var.resource_suffix_part}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach basic SSM permissions for Systems Manager access (optional but useful)
resource "aws_iam_role_policy_attachment" "k3s_ssm" {
  role       = aws_iam_role.k3s.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile
resource "aws_iam_instance_profile" "k3s" {
  name = "${var.name_prefix}-k3s-profile${var.resource_suffix_part}"
  role = aws_iam_role.k3s.name
}

# User data script for k3s and PostgreSQL installation
locals {
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    db_password           = var.db_password
    grafana_admin_password = var.grafana_admin_password
  }))
}

# EC2 Instance
resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s.name

  user_data              = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  monitoring    = true
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-k3s${var.resource_suffix_part}"
  })

  depends_on = [aws_iam_instance_profile.k3s]
}

# Elastic IP for stable access
resource "aws_eip" "k3s" {
  instance = aws_instance.k3s.id
  domain   = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-k3s-eip${var.resource_suffix_part}"
  })

  depends_on = [aws_instance.k3s]
}

# Wait for instance to be ready and retrieve kubeconfig
data "aws_instance" "k3s" {
  instance_id = aws_instance.k3s.id

  depends_on = [aws_instance.k3s]
}
