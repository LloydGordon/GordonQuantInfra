# WireGuard network, compute, and access resources.
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023_arm64_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  common_tags = merge({ Name = var.name }, var.tags)

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    peers                    = var.peers
    wireguard_port           = var.wireguard_port
    wireguard_server_address = var.wireguard_server_address
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = local.common_tags
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = local.common_tags
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, { Name = "${var.name}-public" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, { Name = "${var.name}-public" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "wireguard" {
  name_prefix = "${var.name}-"
  description = "WireGuard UDP ingress; unrestricted egress for VPN clients and SSM"
  vpc_id      = aws_vpc.this.id

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "wireguard" {
  for_each = toset(var.wireguard_client_cidrs)

  security_group_id = aws_security_group.wireguard.id
  description       = "WireGuard from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = var.wireguard_port
  to_port           = var.wireguard_port
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.wireguard.id
  description       = "Internet access for VPN clients, package installation, and SSM"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_iam_role" "ssm" {
  name_prefix = "${var.name}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.ssm.name

  tags = local.common_tags
}

resource "aws_instance" "wireguard" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_arm64_ami.value)
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.wireguard.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  source_dest_check           = false

  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true

    tags = local.common_tags
  }

  credit_specification {
    cpu_credits = "standard"
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_route_table_association.public,
  ]
}

resource "aws_eip" "wireguard" {
  domain = "vpc"

  tags = local.common_tags
}

resource "aws_eip_association" "wireguard" {
  allocation_id = aws_eip.wireguard.id
  instance_id   = aws_instance.wireguard.id
}
