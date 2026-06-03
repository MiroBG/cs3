locals {
  common_tags = merge(var.tags, {
    Project = "cs3"
  })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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
    description = "Grafana NodePort"
    from_port   = 30100
    to_port     = 30100
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

resource "aws_iam_role_policy" "k3s_kubeconfig_parameter" {
  name = "${var.name_prefix}-k3s-kubeconfig-parameter${var.resource_suffix_part}"
  role = aws_iam_role.k3s.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:AddTagsToResource"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.kubeconfig_parameter_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "k3s_cognito_admin" {
  name = "${var.name_prefix}-k3s-cognito-admin${var.resource_suffix_part}"
  role = aws_iam_role.k3s.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminDeleteUser",
          "cognito-idp:AdminDisableUser",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminRemoveUserFromGroup",
          "cognito-idp:CreateGroup",
          "cognito-idp:GetGroup"
        ]
        Resource = var.cognito_user_pool_arn
      }
    ]
  })
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
    eip_public_ip          = try(aws_eip.k3s[0].public_ip, "")
    kubeconfig_parameter   = var.kubeconfig_parameter_name
  }))
  instance_name = "${var.name_prefix}-k3s${var.resource_suffix_part}"
}

# EC2 Instance
resource "aws_instance" "k3s" {
  count                  = var.create_instance ? 1 : 0
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s.name

  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  monitoring                  = true
  associate_public_ip_address = true

  # Hop limit 2 lets k3s pods (one CNI hop away) reach the Instance Metadata
  # Service, so the portal pod can borrow the instance role for boto3 Cognito
  # admin calls. Default of 1 blocks pods. http_tokens optional keeps IMDSv1/v2.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }

  tags = merge(local.common_tags, {
    Name = local.instance_name
  })

  depends_on = [
    aws_iam_instance_profile.k3s,
    aws_iam_role_policy_attachment.k3s_ssm,
    aws_iam_role_policy.k3s_kubeconfig_parameter
  ]
}

# Elastic IP for stable access
resource "aws_eip" "k3s" {
  count  = var.create_instance ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-k3s-eip${var.resource_suffix_part}"
  })
}

resource "aws_eip_association" "k3s" {
  count         = var.create_instance ? 1 : 0
  allocation_id = aws_eip.k3s[0].id
  instance_id   = aws_instance.k3s[0].id
}
