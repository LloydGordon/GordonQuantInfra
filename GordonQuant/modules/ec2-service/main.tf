data "aws_ssm_parameter" "al2023_minimal_arm64_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-arm64"
}

data "aws_subnet" "existing" {
  id = var.subnet_id
}

data "aws_vpc" "existing" {
  id = data.aws_subnet.existing.vpc_id
}

data "aws_route53_zone" "service" {
  name         = var.route53_zone_name
  private_zone = false
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  common_tags = merge({ Name = var.name }, var.tags)

  service_ingress_cidrs = length(var.service_ingress_cidrs) > 0 ? var.service_ingress_cidrs : [data.aws_vpc.existing.cidr_block]

  github_token_parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.github_token_parameter_name}"

  user_data_common = {
    github_token_parameter_name = var.github_token_parameter_name
    git_tag                     = var.git_tag
    repository_url              = var.repository_url
    service_port                = var.service_port
  }

  # The public ASG terminates TLS at the ALB, while the persistent private
  # instance terminates TLS locally with Nginx and Certbot.
  launch_template_user_data = join("", [chomp(templatefile("${path.module}/user_data.sh.tftpl", merge(local.user_data_common, {
    certificate_email        = ""
    dns_wait_timeout_seconds = 0
    docker_publish_address   = "$service_port:5000"
    enable_tls               = false
    health_check_url         = "http://127.0.0.1:$service_port/healthz"
    tls_domain               = ""
  }))), "\n"])

  instance_user_data = templatefile("${path.module}/user_data.sh.tftpl", merge(local.user_data_common, {
    certificate_email        = var.certificate_email
    dns_wait_timeout_seconds = var.dns_wait_timeout_seconds
    docker_publish_address   = var.enable_tls ? "127.0.0.1:5000:5000" : "${var.service_port}:5000"
    enable_tls               = var.enable_tls
    health_check_url         = var.enable_tls ? "http://127.0.0.1:5000/healthz" : "http://127.0.0.1:${var.service_port}/healthz"
    tls_domain               = var.route53_record_name
  }))
}

resource "aws_security_group" "service" {
  name_prefix = "${var.name}-"
  description = "GordonQuant service ingress from approved private networks"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    description = "GordonQuant HTTP"
    from_port   = var.service_port
    to_port     = var.service_port
    protocol    = "tcp"
    cidr_blocks = local.service_ingress_cidrs
  }

  dynamic "ingress" {
    for_each = var.enable_tls ? [1] : []

    content {
      description = "GordonQuant HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = local.service_ingress_cidrs
    }
  }

  egress {
    description = "Package installation, private GitHub clone, and SSM"
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

resource "aws_iam_role" "service" {
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
  role       = aws_iam_role.service.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "github_token" {
  name_prefix = "github-token-"
  role        = aws_iam_role.service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadGitHubToken"
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = local.github_token_parameter_arn
    }]
  })
}

resource "aws_iam_role_policy" "certificate_dns" {
  count = var.enable_tls ? 1 : 0

  name_prefix = "certificate-dns-"
  role        = aws_iam_role.service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DiscoverHostedZone"
        Effect   = "Allow"
        Action   = "route53:ListHostedZones"
        Resource = "*"
      },
      {
        Sid      = "ManageCertificateValidationRecords"
        Effect   = "Allow"
        Action   = "route53:ChangeResourceRecordSets"
        Resource = "arn:${data.aws_partition.current.partition}:route53:::hostedzone/${data.aws_route53_zone.service.zone_id}"
        Condition = {
          "ForAllValues:StringEquals" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = ["_acme-challenge.${var.route53_record_name}"]
            "route53:ChangeResourceRecordSetsRecordTypes"           = ["TXT"]
          }
        }
      },
      {
        Sid      = "CheckCertificateValidation"
        Effect   = "Allow"
        Action   = "route53:GetChange"
        Resource = "arn:${data.aws_partition.current.partition}:route53:::change/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "service" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.service.name

  tags = local.common_tags
}

resource "aws_launch_template" "service" {
  name_prefix            = "${var.name}-"
  description            = "GordonQuant ${var.git_tag} service instances"
  image_id               = nonsensitive(data.aws_ssm_parameter.al2023_minimal_arm64_ami.value)
  instance_type          = var.instance_type
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.service.name
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    device_index                = 0
    security_groups             = [aws_security_group.service.id]
  }

  user_data = base64encode(local.launch_template_user_data)

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      encrypted             = true
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      delete_on_termination = true
    }
  }

  credit_specification {
    cpu_credits = "standard"
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.github_token,
    aws_iam_role_policy.certificate_dns,
    aws_iam_role_policy_attachment.ssm,
  ]
}

# This instance is the persistent private GordonQuant service. It deliberately
# belongs to the service stack so removing the optional public ALB stack does
# not remove private access through WireGuard or SSM.
resource "aws_instance" "service" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_minimal_arm64_ami.value)
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.existing.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.service.id]
  iam_instance_profile        = aws_iam_instance_profile.service.name

  user_data                   = local.instance_user_data
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
    aws_iam_role_policy.github_token,
    aws_iam_role_policy.certificate_dns,
    aws_iam_role_policy_attachment.ssm,
  ]
}

resource "aws_route53_record" "service" {
  zone_id = data.aws_route53_zone.service.zone_id
  name    = var.route53_record_name
  type    = "A"
  ttl     = 60
  records = [aws_instance.service.private_ip]
}
