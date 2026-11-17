variable "aws_region" {
  description = "AWS region in which to create the load balancer."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix used for load-balancer resources."
  type        = string
  default     = "gordonquant-public"
}

variable "vpc_id" {
  description = "VPC containing the GordonQuant EC2 instance."
  type        = string
}

variable "subnet_ids" {
  description = "At least two public subnets in distinct availability zones."
  type        = list(string)

  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "subnet_ids must contain at least two distinct public subnet IDs."
  }
}

variable "launch_template_id" {
  description = "Launch Template used for GordonQuant Auto Scaling instances."
  type        = string
}

variable "launch_template_version" {
  description = "Launch Template version used for GordonQuant Auto Scaling instances."
  type        = string
}

variable "service_port" {
  description = "Port on which GordonQuant listens."
  type        = number

  validation {
    condition     = var.service_port >= 1 && var.service_port <= 65535
    error_message = "service_port must be between 1 and 65535."
  }
}

variable "public_ingress_cidrs" {
  description = "IPv4 CIDRs allowed to reach the public HTTP listener."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.public_ingress_cidrs) > 0
    error_message = "public_ingress_cidrs must contain at least one IPv4 CIDR."
  }
}

variable "health_check_path" {
  description = "HTTP path used by the target group health check."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must begin with /."
  }
}

variable "asg_min_size" {
  description = "Minimum number of GordonQuant instances."
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Desired number of GordonQuant instances created with the public ALB."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of GordonQuant instances."
  type        = number
  default     = 2

  validation {
    condition     = var.asg_max_size >= var.asg_desired_capacity && var.asg_desired_capacity >= var.asg_min_size
    error_message = "asg_max_size must be at least desired capacity, which must be at least asg_min_size."
  }
}

variable "tags" {
  description = "Additional tags to apply to all supported resources."
  type        = map(string)
  default     = {}
}
