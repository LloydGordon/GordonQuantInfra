data "aws_subnet" "selected" {
  for_each = toset(var.subnet_ids)
  id       = each.value
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

moved {
  from = aws_lb.this
  to   = aws_lb.public
}

locals {
  common_tags = merge({ Name = var.name, Region = var.aws_region }, var.tags)
  availability_zones = distinct([
    for subnet in data.aws_subnet.selected : subnet.availability_zone
  ])
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-"
  description = "Public HTTP ingress for GordonQuant"
  vpc_id      = var.vpc_id

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition = alltrue([
        for subnet in data.aws_subnet.selected : subnet.vpc_id == var.vpc_id
      ])
      error_message = "Every ALB subnet must belong to vpc_id."
    }

    precondition {
      condition     = length(local.availability_zones) >= 2
      error_message = "The ALB subnets must span at least two availability zones."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "public_http" {
  for_each = toset(var.public_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "Public HTTP"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "service" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP to GordonQuant within the VPC"
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  from_port         = var.service_port
  to_port           = var.service_port
  ip_protocol       = "tcp"
}

resource "aws_lb" "public" {
  name               = var.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  drop_invalid_header_fields = true

  tags = local.common_tags
}

resource "aws_lb_target_group" "service" {
  name        = var.name
  port        = var.service_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service.arn
  }
}

resource "aws_autoscaling_group" "service" {
  # A fixed name prevents failed replacements from accumulating uniquely named
  # ASGs, each with its own billable instances.
  name = "${var.name}-asg"

  min_size         = var.asg_min_size
  desired_capacity = var.asg_desired_capacity
  max_size         = var.asg_max_size

  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [aws_lb_target_group.service.arn]
  health_check_type   = "ELB"

  # Initial bootstrap installs Docker and builds the selected Git tag on a
  # small instance, so the load-balancer health check needs a generous grace.
  health_check_grace_period = 1800
  wait_for_capacity_timeout = "40m"
  wait_for_elb_capacity     = var.asg_desired_capacity

  launch_template {
    id      = var.launch_template_id
    version = var.launch_template_version
  }

  dynamic "tag" {
    for_each = local.common_tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      instance_warmup        = 1800
      min_healthy_percentage = 50
      max_healthy_percentage = 100
    }
  }

  depends_on = [aws_lb_listener.http]
}
