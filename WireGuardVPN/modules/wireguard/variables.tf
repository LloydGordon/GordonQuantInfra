# Public inputs for the reusable WireGuard module.
variable "aws_region" {
  description = "AWS region in which to create the VPN server."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix used for resources and tags."
  type        = string
  default     = "wireguard-vpn"
}

variable "instance_type" {
  description = "ARM64 EC2 instance type. t4g.nano is the cheapest generally available on-demand option in us-east-1."
  type        = string
  default     = "t4g.nano"
}

variable "subnet_id" {
  description = "Existing public subnet in which to launch the WireGuard server."
  type        = string

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid AWS subnet ID."
  }
}

variable "wireguard_port" {
  description = "UDP port on which WireGuard listens."
  type        = number
  default     = 51820

  validation {
    condition     = var.wireguard_port >= 1 && var.wireguard_port <= 65535
    error_message = "wireguard_port must be between 1 and 65535."
  }
}

variable "wireguard_server_address" {
  description = "WireGuard address assigned to the server interface."
  type        = string
  default     = "10.8.0.1/24"
}

variable "wireguard_client_cidrs" {
  description = "Public source networks allowed to send WireGuard UDP traffic. Use narrower CIDRs when clients have stable public addresses."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "peers" {
  description = "WireGuard client public keys and the VPN addresses routed to each client. Never put client private keys here."
  type = list(object({
    name        = string
    public_key  = string
    allowed_ips = list(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for peer in var.peers : length(trimspace(peer.name)) > 0 &&
      length(trimspace(peer.public_key)) > 0 &&
      length(peer.allowed_ips) > 0
    ])
    error_message = "Every peer needs a name, public key, and at least one allowed IP."
  }
}

variable "root_volume_size" {
  description = "Size of the encrypted gp3 root volume in GiB."
  type        = number
  default     = 8
}

variable "tags" {
  description = "Additional tags to apply to all supported resources."
  type        = map(string)
  default     = {}
}
