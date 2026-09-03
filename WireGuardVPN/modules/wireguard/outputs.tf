# Connection and administration details.
output "instance_id" {
  description = "EC2 instance ID of the WireGuard server."
  value       = aws_instance.wireguard.id
}

output "subnet_id" {
  description = "Subnet containing the WireGuard server."
  value       = data.aws_subnet.existing.id
}

output "vpc_id" {
  description = "VPC containing the WireGuard server."
  value       = data.aws_subnet.existing.vpc_id
}

output "public_ip" {
  description = "Automatically assigned public IPv4 address used as the WireGuard endpoint."
  value       = aws_instance.wireguard.public_ip
}

output "wireguard_endpoint" {
  description = "WireGuard endpoint for client configuration."
  value       = "${aws_instance.wireguard.public_ip}:${var.wireguard_port}"
}

output "ssm_start_session_command" {
  description = "Command for opening a shell without exposing SSH."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.wireguard.id}"
}

output "server_public_key_command" {
  description = "Run after connecting through SSM to retrieve the WireGuard server public key."
  value       = "sudo cat /etc/wireguard/server_public.key"
}
