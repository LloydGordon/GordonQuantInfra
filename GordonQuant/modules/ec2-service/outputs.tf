output "vpc_id" {
  description = "VPC containing the GordonQuant service."
  value       = data.aws_vpc.existing.id
}

output "subnet_id" {
  description = "Subnet containing the GordonQuant service."
  value       = data.aws_subnet.existing.id
}

output "service_port" {
  description = "TCP port exposed by the GordonQuant container."
  value       = var.service_port
}

output "instance_id" {
  description = "Persistent private EC2 instance running GordonQuant."
  value       = aws_instance.service.id
}

output "private_ip" {
  description = "Private VPC address of the persistent GordonQuant instance."
  value       = aws_instance.service.private_ip
}

output "service_url" {
  description = "Private GordonQuant URL reachable through the VPC or WireGuard tunnel."
  value       = "http://${aws_instance.service.private_ip}${var.service_port == 80 ? "" : ":${var.service_port}"}"
}

output "service_dns_name" {
  description = "DNS name resolving to the persistent service instance's private IP."
  value       = trimsuffix(aws_route53_record.service.fqdn, ".")
}

output "service_dns_url" {
  description = "Private GordonQuant URL using the Route 53 record, reachable through WireGuard or the VPC."
  value       = var.enable_tls ? "https://${trimsuffix(aws_route53_record.service.fqdn, ".")}" : "http://${trimsuffix(aws_route53_record.service.fqdn, ".")}${var.service_port == 80 ? "" : ":${var.service_port}"}"
}

output "tls_enabled" {
  description = "Whether the persistent instance terminates HTTPS locally with Nginx and Certbot."
  value       = var.enable_tls
}

output "launch_template_id" {
  description = "Launch Template used by the public ELB stack's Auto Scaling Group."
  value       = aws_launch_template.service.id
}

output "launch_template_version" {
  description = "Latest Launch Template version containing the selected GordonQuant release."
  value       = aws_launch_template.service.latest_version
}

output "deployed_git_tag" {
  description = "Git tag embedded in the Launch Template bootstrap."
  value       = var.git_tag
}

output "ssm_list_instances_command" {
  description = "Command that lists the persistent and ASG GordonQuant instance IDs for SSM access."
  value       = "aws ec2 describe-instances --region ${var.aws_region} --filters Name=tag:Name,Values=${var.name} Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text"
}

output "ssm_start_session_command" {
  description = "Command for opening an SSM shell on the persistent private instance."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.service.id}"
}
