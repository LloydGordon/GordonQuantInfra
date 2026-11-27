variable "aws_region" {
  description = "AWS region in which to run GordonQuant."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix used for resources and tags."
  type        = string
  default     = "gordonquant"
}

variable "instance_type" {
  description = "ARM64 EC2 instance type used to run the service."
  type        = string
  default     = "t4g.nano"
}

variable "subnet_id" {
  description = "Existing public subnet with outbound internet access."
  type        = string

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid AWS subnet ID."
  }
}

variable "route53_zone_name" {
  description = "Public Route 53 hosted zone containing the private service record."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.route53_zone_name)) && !endswith(var.route53_zone_name, ".")
    error_message = "route53_zone_name must be a domain such as gordonquant.app without a trailing dot."
  }
}

variable "route53_record_name" {
  description = "Fully qualified DNS name that resolves to the persistent service instance's private IP."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.route53_record_name)) && !endswith(var.route53_record_name, ".")
    error_message = "route53_record_name must be a fully qualified domain such as dev.gordonquant.app without a trailing dot."
  }
}

variable "enable_tls" {
  description = "Whether to configure Nginx and a Certbot certificate on the persistent service instance."
  type        = bool
  default     = false
}

variable "certificate_email" {
  description = "Optional email registered with Let's Encrypt. When empty, Certbot registers without an email address."
  type        = string
  default     = ""

  validation {
    condition     = var.certificate_email == "" || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.certificate_email))
    error_message = "certificate_email must be empty or a valid email address."
  }
}

variable "dns_wait_timeout_seconds" {
  description = "Maximum time cloud-init waits for the service DNS record to resolve to the new instance before requesting a certificate."
  type        = number
  default     = 900

  validation {
    condition     = var.dns_wait_timeout_seconds >= 60 && var.dns_wait_timeout_seconds <= 3600
    error_message = "dns_wait_timeout_seconds must be between 60 and 3600."
  }
}

variable "repository_url" {
  description = "HTTPS URL of the private GitHub repository."
  type        = string

  validation {
    condition     = can(regex("^https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\\.git$", var.repository_url))
    error_message = "repository_url must be an HTTPS GitHub .git URL."
  }
}

variable "git_tag" {
  description = "Exact Git tag to fetch, build, and run."
  type        = string

  validation {
    condition     = length(var.git_tag) <= 128 && can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", var.git_tag))
    error_message = "git_tag must be 1-128 characters and contain only letters, numbers, dots, underscores, and hyphens."
  }
}

variable "github_token_parameter_name" {
  description = "Name of an existing SSM SecureString containing a read-only GitHub token. The secret value is never stored in Terraform."
  type        = string

  validation {
    condition     = can(regex("^/[A-Za-z0-9_.\\-/]+$", var.github_token_parameter_name))
    error_message = "github_token_parameter_name must be an absolute SSM parameter name beginning with /."
  }
}

variable "service_port" {
  description = "Port exposed by the GordonQuant container."
  type        = number
  default     = 5000

  validation {
    condition     = var.service_port >= 1 && var.service_port <= 65535
    error_message = "service_port must be between 1 and 65535."
  }
}

variable "service_ingress_cidrs" {
  description = "CIDRs allowed to reach the service. An empty list uses the VPC CIDR."
  type        = list(string)
  default     = []
}

variable "root_volume_size" {
  description = "Size of the encrypted gp3 root volume in GiB."
  type        = number
  default     = 12

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}

variable "tags" {
  description = "Additional tags to apply to all supported resources."
  type        = map(string)
  default     = {}
}
