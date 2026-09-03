include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/wireguard"
}

inputs = {
  name          = "wireguard-vpn-dev"
  instance_type = "t4g.nano"
  subnet_id     = "subnet-0d76e3f6200d8aa5b"

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
