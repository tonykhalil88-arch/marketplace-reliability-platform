output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.this.id
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.this.arn
}

output "security_group_id" {
  description = "Security group ID of the ECS tasks"
  value       = aws_security_group.service.id
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.this.name
}
