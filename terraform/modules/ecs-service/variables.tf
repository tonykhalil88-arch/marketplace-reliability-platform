variable "service_name" {
  description = "Name of the ECS service"
  type        = string
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the service image"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Fargate task CPU units (1 vCPU = 1024)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Initial desired task count"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of tasks for autoscaling"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks for autoscaling"
  type        = number
  default     = 10
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for task placement"
  type        = list(string)
}

variable "alb_listener_arn" {
  description = "ARN of the ALB listener"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (for autoscaling metrics)"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB"
  type        = string
}

variable "alb_rule_priority" {
  description = "Priority for the ALB listener rule"
  type        = number
  default     = 100
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
