data "aws_ssm_parameter" "al2023_arm64_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_subnet" "existing" {
  id = var.subnet_id
}

locals {
  common_tags = merge({ Name = var.name }, var.tags)

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    peers                    = var.peers
    wireguard_port           = var.wireguard_port
    wireguard_server_address = var.wireguard_server_address
  })
}

resource "aws_security_group" "wireguard" {
  name_prefix = "${var.name}-"
  description = "WireGuard UDP ingress; unrestricted egress for VPN clients and SSM"
  vpc_id      = data.aws_subnet.existing.vpc_id

  dynamic "ingress" {
    for_each = toset(var.wireguard_client_cidrs)

    content {
      description = "WireGuard from ${ingress.value}"
      from_port   = var.wireguard_port
      to_port     = var.wireguard_port
      protocol    = "udp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "Internet access for VPN clients, package installation, and SSM"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
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
  subnet_id                   = data.aws_subnet.existing.id
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
  ]
}
