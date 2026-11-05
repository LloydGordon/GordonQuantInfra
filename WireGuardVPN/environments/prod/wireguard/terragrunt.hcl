include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/wireguard"
}

inputs = {
  name          = "wireguard-vpn-prod"
  instance_type = "t4g.nano"
  subnet_id     = "subnet-0d76e3f6200d8aa5b"

  # Generate each client key locally. Only commit public keys here.
  peers = [
    {
      name        = "Ubuntu laptop"
      public_key  = "bxKrwepS7xlDijgB+AAec5diNXN3sA8vy/8gOkK2VWY="
      allowed_ips = ["10.8.0.2/32"]
    }
  ]
}
