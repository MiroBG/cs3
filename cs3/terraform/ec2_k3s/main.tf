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

  # Keep rules inline so imported SG with identical rules stays idempotent.
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "k3s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Container ports"
    from_port   = 8000
    to_port     = 9999
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "PostgreSQL in VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-k3s-sg${var.resource_suffix_part}"
  })
}

# Get latest Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

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
    db_password            = var.db_password
    grafana_admin_password = var.grafana_admin_password
  }))
  instance_name = "${var.name_prefix}-k3s${var.resource_suffix_part}"
}

# Look for existing k3s instances (idempotency: avoid creating duplicates)
data "aws_instances" "existing_k3s" {
  filter {
    name   = "tag:Name"
    values = [local.instance_name]
  }
  filter {
    name   = "instance-state-name"
    values = ["pending", "running", "stopping", "stopped"]
  }
}

# EC2 Instance (only create if none exist)
resource "aws_instance" "k3s" {
  count                  = length(data.aws_instances.existing_k3s.ids) > 0 ? 0 : 1
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s.name

  user_data                   = local.user_data
  user_data_replace_on_change = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  monitoring                  = true
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = local.instance_name
  })

  depends_on = [aws_iam_instance_profile.k3s]
}

# Reference either existing or newly created instance
data "aws_instance" "k3s_target" {
  instance_id = length(data.aws_instances.existing_k3s.ids) > 0 ? data.aws_instances.existing_k3s.ids[0] : aws_instance.k3s[0].id
  depends_on  = [aws_instance.k3s]
}

# Elastic IP for stable access (associate with existing or new instance)
resource "aws_eip" "k3s" {
  instance   = data.aws_instance.k3s_target.id
  domain     = "vpc"
  depends_on = [aws_instance.k3s]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-k3s-eip${var.resource_suffix_part}"
  })
}

# Wait for instance to be ready and retrieve kubeconfig
data "aws_instance" "k3s" {
  instance_id = data.aws_instance.k3s_target.id
  depends_on  = [aws_eip.k3s]
}
