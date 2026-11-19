output "load_balancer_dns_name" {
  description = "Public DNS name assigned to the Application Load Balancer."
  value       = aws_lb.public.dns_name
}

output "public_url" {
  description = "Public HTTPS URL for GordonQuant."
  value       = "https://${var.domain_name}"
}

output "domain_name" {
  description = "Route 53 domain pointing at the Application Load Balancer."
  value       = aws_route53_record.application.fqdn
}

output "certificate_arn" {
  description = "ARN of the validated ACM wildcard certificate attached to the HTTPS listener."
  value       = aws_acm_certificate_validation.public.certificate_arn
}

output "load_balancer_arn" {
  description = "ARN of the public Application Load Balancer."
  value       = aws_lb.public.arn
}

output "target_group_arn" {
  description = "ARN of the GordonQuant target group."
  value       = aws_lb_target_group.service.arn
}

output "autoscaling_group_name" {
  description = "Name of the two-instance GordonQuant Auto Scaling Group."
  value       = aws_autoscaling_group.service.name
}

output "desired_capacity" {
  description = "Desired number of GordonQuant instances behind the ALB."
  value       = aws_autoscaling_group.service.desired_capacity
}
