# Connection and administration details.
output "instance_id" {
  description = "EC2 instance ID of the WireGuard server."
  value       = aws_instance.wireguard.id
}

output "public_ip" {
  description = "Stable public IPv4 address used as the WireGuard endpoint."
  value       = aws_eip.wireguard.public_ip
}

output "wireguard_endpoint" {
  description = "WireGuard endpoint for client configuration."
  value       = "${aws_eip.wireguard.public_ip}:${var.wireguard_port}"
}

output "ssm_start_session_command" {
  description = "Command for opening a shell without exposing SSH."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.wireguard.id}"
}

output "server_public_key_command" {
  description = "Run after connecting through SSM to retrieve the WireGuard server public key."
  value       = "sudo cat /etc/wireguard/server_public.key"
}
