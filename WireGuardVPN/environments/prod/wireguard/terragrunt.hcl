include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/wireguard"
}

inputs = {
  name               = "wireguard-vpn-prod"
  instance_type      = "t4g.nano"
  vpc_cidr           = "10.43.0.0/16"
  public_subnet_cidr = "10.43.0.0/24"

  # Generate each client key locally. Only commit public keys here.
  # peers = [
  #   {
  #     name        = "laptop"
  #     public_key  = "REPLACE_WITH_CLIENT_PUBLIC_KEY"
  #     allowed_ips = ["10.8.0.2/32"]
  #   }
  # ]
  peers = []
}

