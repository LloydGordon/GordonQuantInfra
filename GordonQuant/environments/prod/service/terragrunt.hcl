include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/ec2-service"
}

inputs = {
  name          = "gordonquant-prod"
  instance_type = "t4g.nano"
  subnet_id     = "subnet-0d76e3f6200d8aa5b"

  repository_url              = "https://github.com/LloydGordon/GordonQuant.git"
  git_tag                     = "v0.1.0"
  github_token_parameter_name = "/gordonquant/github-token"

  # Empty means allow port 5000 only from the VPC CIDR. Traffic arriving from
  # the WireGuard instance is NATed to its VPC private address.
  service_ingress_cidrs = []
}
