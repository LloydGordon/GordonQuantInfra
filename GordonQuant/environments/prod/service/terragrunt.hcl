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
  service_port  = 80

  route53_zone_name   = "gordonquant.app"
  route53_record_name = "dev.gordonquant.app"
  enable_tls          = true

  # Optional: set this to receive Let's Encrypt account and expiry notices.
  certificate_email        = "ben9750@gmail.com"
  dns_wait_timeout_seconds = 900

  repository_url              = "https://github.com/LloydGordon/GordonQuant.git"
  git_tag                     = "v0.1.0"
  github_token_parameter_name = "/gordonquant/github-token"

  # Empty means allow the HTTP/HTTPS listeners only from the VPC CIDR. Traffic
  # arriving from the WireGuard instance is NATed to its VPC private address.
  service_ingress_cidrs = []
}
