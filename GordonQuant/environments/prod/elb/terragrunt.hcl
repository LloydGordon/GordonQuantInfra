include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/public-alb"
}

dependency "service" {
  config_path = "../service"

  mock_outputs_allowed_terraform_commands = ["validate"]
  mock_outputs = {
    launch_template_id      = "lt-0123456789abcdef0"
    launch_template_version = "1"
    service_port            = 5000
    subnet_id               = "subnet-0d76e3f6200d8aa5b"
    vpc_id                  = "vpc-0123456789abcdef0"
  }
}

inputs = {
  name = "gordonquant-prod"

  vpc_id                  = dependency.service.outputs.vpc_id
  launch_template_id      = dependency.service.outputs.launch_template_id
  launch_template_version = tostring(dependency.service.outputs.launch_template_version)
  service_port            = dependency.service.outputs.service_port

  # An internet-facing ALB requires subnets in at least two availability zones.
  subnet_ids = [
    dependency.service.outputs.subnet_id,
    "subnet-0d8e8a3398c5de545", # us-east-1a
  ]

  public_ingress_cidrs = ["0.0.0.0/0"]
  health_check_path    = "/healthz"

  asg_min_size         = 2
  asg_desired_capacity = 2
  asg_max_size         = 2
}
