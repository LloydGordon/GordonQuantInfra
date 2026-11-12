output "instance_id" {
  description = "EC2 instance ID running GordonQuant."
  value       = aws_instance.service.id
}

output "private_ip" {
  description = "Private VPC address of the GordonQuant service."
  value       = aws_instance.service.private_ip
}

output "service_url" {
  description = "Private URL to reach through the VPC or WireGuard tunnel."
  value       = "http://${aws_instance.service.private_ip}:${var.service_port}"
}

output "deployed_git_tag" {
  description = "Git tag requested by the SSM deployment association."
  value       = var.git_tag
}

output "ssm_start_session_command" {
  description = "Command for opening an SSM shell on the service instance."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.service.id}"
}

output "deployment_association_id" {
  description = "SSM Association ID responsible for deploying the selected tag."
  value       = aws_ssm_association.deploy.association_id
}
