locals {
  common_tags = merge(var.tags, {
    Project = "cs3"
  })
}

data "aws_region" "current" {}

data "aws_vpcs" "default" {
  filter {
    name   = "isDefault"
    values = ["true"]
  }
}

locals {
  default_vpc_id  = length(data.aws_vpcs.default.ids) > 0 ? data.aws_vpcs.default.ids[0] : null
  selected_vpc_id = var.use_default_vpc ? local.default_vpc_id : null
  create_vpc      = !var.use_default_vpc || local.selected_vpc_id == null
}

resource "aws_vpc" "this" {
  count                = local.create_vpc ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

data "aws_subnets" "selected" {
  count = local.create_vpc ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [local.selected_vpc_id]
  }
}

data "aws_internet_gateway" "selected" {
  count = local.create_vpc ? 0 : 1

  filter {
    name   = "attachment.vpc-id"
    values = [local.selected_vpc_id]
  }
}

locals {
  existing_subnet_ids = local.create_vpc ? [] : try(data.aws_subnets.selected[0].ids, [])
  selected_igw_id     = local.create_vpc ? null : try(data.aws_internet_gateway.selected[0].id, null)
  vpc_id              = local.create_vpc ? aws_vpc.this[0].id : local.selected_vpc_id
  internet_gateway_id = local.create_vpc ? aws_internet_gateway.this[0].id : local.selected_igw_id
  public_subnet_ids   = local.create_vpc ? [for subnet in values(aws_subnet.public) : subnet.id] : local.existing_subnet_ids
  private_subnet_ids  = local.create_vpc ? [for subnet in values(aws_subnet.private) : subnet.id] : local.existing_subnet_ids
  database_subnet_ids = local.create_vpc ? [for subnet in values(aws_subnet.database) : subnet.id] : local.existing_subnet_ids
}

data "aws_vpc" "selected" {
  count = local.create_vpc ? 0 : 1
  id    = local.vpc_id
}

locals {
  endpoint_subnet_ids = length(local.private_subnet_ids) > 0 ? local.private_subnet_ids : local.public_subnet_ids
  endpoint_vpc_cidr   = local.create_vpc ? var.vpc_cidr : data.aws_vpc.selected[0].cidr_block
}

resource "aws_internet_gateway" "this" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = local.create_vpc ? { for index, cidr in var.public_subnet_cidrs : index => cidr } : {}

  vpc_id                  = local.vpc_id
  cidr_block              = each.value
  availability_zone       = element(var.azs, tonumber(each.key) % length(var.azs))
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                        = "${var.name_prefix}-public-${tonumber(each.key) + 1}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_subnet" "private" {
  for_each = local.create_vpc ? { for index, cidr in var.private_subnet_cidrs : index => cidr } : {}

  vpc_id            = local.vpc_id
  cidr_block        = each.value
  availability_zone = element(var.azs, tonumber(each.key) % length(var.azs))

  tags = merge(local.common_tags, {
    Name                                        = "${var.name_prefix}-private-${tonumber(each.key) + 1}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_subnet" "database" {
  for_each = local.create_vpc ? { for index, cidr in var.database_subnet_cidrs : index => cidr } : {}

  vpc_id            = local.vpc_id
  cidr_block        = each.value
  availability_zone = element(var.azs, tonumber(each.key) % length(var.azs))

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-database-${tonumber(each.key) + 1}"
  })
}

resource "aws_eip" "nat" {
  count  = local.create_vpc && var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  count         = local.create_vpc && var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = values(aws_subnet.public)[0].id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_default" {
  count                  = local.create_vpc ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = local.internet_gateway_id
}

resource "aws_route_table_association" "public" {
  for_each = local.create_vpc ? { for index, cidr in var.public_subnet_cidrs : index => cidr } : {}

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-private-rt"
  })
}

resource "aws_route" "private_default" {
  count                  = local.create_vpc && var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  for_each = local.create_vpc ? { for index, cidr in var.private_subnet_cidrs : index => cidr } : {}

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[0].id
}

resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_ssm_vpc_endpoints ? 1 : 0
  name        = "${var.name_prefix}-ssm-endpoints-sg"
  description = "Allow VPC access to Systems Manager endpoints"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.endpoint_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-endpoints-sg"
  })
}

resource "aws_vpc_endpoint" "ssm" {
  count               = var.enable_ssm_vpc_endpoints && length(local.endpoint_subnet_ids) > 0 ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.endpoint_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpce-ssm"
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count               = var.enable_ssm_vpc_endpoints && length(local.endpoint_subnet_ids) > 0 ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.endpoint_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpce-ssmmessages"
  })
}

resource "aws_vpc_endpoint" "ec2messages" {
  count               = var.enable_ssm_vpc_endpoints && length(local.endpoint_subnet_ids) > 0 ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.endpoint_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpce-ec2messages"
  })
}

output "vpc_id" {
  value = local.vpc_id
}

output "public_subnet_ids" {
  value = local.public_subnet_ids
}

output "database_subnet_ids" {
  value = local.database_subnet_ids
}

output "private_subnet_ids" {
  value = local.private_subnet_ids
}

output "internet_gateway_id" {
  value = local.internet_gateway_id
}

output "nat_gateway_id" {
  value       = try(aws_nat_gateway.this[0].id, null)
  description = "NAT gateway id when enabled"
}

output "ssm_endpoint_id" {
  value       = try(aws_vpc_endpoint.ssm[0].id, null)
  description = "Interface VPC endpoint id for SSM"
}

output "ssmmessages_endpoint_id" {
  value       = try(aws_vpc_endpoint.ssmmessages[0].id, null)
  description = "Interface VPC endpoint id for SSMMessages"
}

output "ec2messages_endpoint_id" {
  value       = try(aws_vpc_endpoint.ec2messages[0].id, null)
  description = "Interface VPC endpoint id for EC2Messages"
}

output "ssm_endpoints_security_group_id" {
  value       = try(aws_security_group.vpc_endpoints[0].id, null)
  description = "Security group id attached to Systems Manager interface endpoints"
}
