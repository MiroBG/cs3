locals {
  common_tags = merge(var.tags, {
    Project = "cs3"
  })
}

data "aws_vpc" "default" {
  count  = var.use_default_vpc ? 1 : 0
  default = true
}

data "aws_internet_gateway" "default" {
  count = var.use_default_vpc ? 1 : 0

  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

resource "aws_vpc" "this" {
  count                = var.use_default_vpc ? 0 : 1
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  count  = var.use_default_vpc ? 0 : 1
  vpc_id = aws_vpc.this[0].id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-igw"
  })
}

locals {
  vpc_id              = var.use_default_vpc ? data.aws_vpc.default[0].id : aws_vpc.this[0].id
  internet_gateway_id = var.use_default_vpc ? data.aws_internet_gateway.default[0].id : aws_internet_gateway.this[0].id
}

resource "aws_subnet" "public" {
  for_each = { for index, cidr in var.public_subnet_cidrs : index => cidr }

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
  for_each = { for index, cidr in var.private_subnet_cidrs : index => cidr }

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
  for_each = { for index, cidr in var.database_subnet_cidrs : index => cidr }

  vpc_id            = local.vpc_id
  cidr_block        = each.value
  availability_zone = element(var.azs, tonumber(each.key) % length(var.azs))

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-database-${tonumber(each.key) + 1}"
  })
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway && !var.use_default_vpc ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway && !var.use_default_vpc ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = values(aws_subnet.public)[0].id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = local.internet_gateway_id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-private-rt"
  })
}

resource "aws_route" "private_default" {
  count                  = var.enable_nat_gateway && !var.use_default_vpc ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

output "vpc_id" {
  value = local.vpc_id
}

output "public_subnet_ids" {
  value = [for subnet in values(aws_subnet.public) : subnet.id]
}

output "database_subnet_ids" {
  value = [for subnet in values(aws_subnet.database) : subnet.id]
}

output "private_subnet_ids" {
  value = [for subnet in values(aws_subnet.private) : subnet.id]
}

output "internet_gateway_id" {
  value = local.internet_gateway_id
}

output "nat_gateway_id" {
  value       = try(aws_nat_gateway.this[0].id, null)
  description = "NAT gateway id when enabled"
}
