output "load_balancer_dns_name" {
  description = "Public DNS name assigned to the Application Load Balancer."
  value       = aws_lb.public.dns_name
}

output "public_url" {
  description = "Public HTTP URL for GordonQuant."
  value       = "http://${aws_lb.public.dns_name}"
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
