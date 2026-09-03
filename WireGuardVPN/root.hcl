terraform_version_constraint  = ">= 1.10.0, < 2.0.0"
terragrunt_version_constraint = ">= 0.77.0, < 2.0.0"

locals {
  environment = basename(dirname(get_terragrunt_dir()))
  region      = "us-east-1"
  account_id  = get_env("AWS_ACCOUNT_ID", "491117466808")
}

remote_state {
  backend = "s3"

  config = {
    bucket       = "gordonquantinfra-${local.account_id}-terraform-state"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.region
    encrypt      = true
    use_lockfile = true

    s3_bucket_tags = {
      ManagedBy = "Terragrunt"
      Project   = "WireGuardVPN"
    }
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.region}"

      default_tags {
        tags = {
          Environment = "${local.environment}"
          ManagedBy   = "Terraform"
          Project     = "WireGuardVPN"
        }
      }
    }
  EOF
}

inputs = {
  aws_region = local.region
  tags = {
    Environment = local.environment
  }
}
