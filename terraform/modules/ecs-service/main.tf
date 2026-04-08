terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
  }
}

# ─── ECS Fargate Service Module ──────────────────────────────────────────────
# Deploys a containerized microservice on ECS Fargate.
# Used alongside Kubernetes — Articore runs both K8s and ECS,
# so this demonstrates fluency with their full compute stack.
#
# Key design decisions:
#   - Fargate (serverless) over EC2 for reduced operational overhead
#   - Multi-AZ task placement for high availability
#   - ALB health checks aligned with application /health endpoint
#   - CloudWatch log group with retention policy

# ─── Task Definition ─────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "this" {
  family                   = var.service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = var.service_name
      image = "${var.ecr_repository_url}:${var.image_tag}"

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "REGION", value = var.aws_region },
        { name = "PORT", value = tostring(var.container_port) },
        { name = "SERVICE_VERSION", value = var.image_tag },
        # Datadog unified service tags via environment variables
        { name = "DD_SERVICE", value = var.service_name },
        { name = "DD_ENV", value = var.environment },
        { name = "DD_VERSION", value = var.image_tag },
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.container_port}/health')\" || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = var.service_name
        }
      }

      # Graceful shutdown — ECS sends SIGTERM, app handles drain
      stopTimeout = 30
    }
  ])

  tags = var.tags
}

# ─── ECS Service ─────────────────────────────────────────────────────────────

resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Deploy new tasks before draining old ones (like K8s maxUnavailable=0)
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Circuit breaker at the ECS level — rolls back if new tasks fail to stabilize
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  # Spread tasks across AZs for high availability
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # Ignore desired_count changes from autoscaling
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = var.tags
}

# ─── Auto Scaling ────────────────────────────────────────────────────────────

resource "aws_appautoscaling_target" "this" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale on CPU — aligns with Kubernetes HPA behavior
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.service_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = aws_appautoscaling_target.this.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Scale on ALB request count per target
resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.service_name}-request-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = aws_appautoscaling_target.this.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.alb_arn_suffix}/${aws_lb_target_group.this.arn_suffix}"
    }
    target_value       = 1000.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# ─── ALB Target Group ────────────────────────────────────────────────────────

resource "aws_lb_target_group" "this" {
  name        = "${var.service_name}-${var.environment}"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for Fargate

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  # Deregistration delay — gives in-flight requests time to complete
  # (matches preStopHook in Kubernetes deployment)
  deregistration_delay = 30

  tags = var.tags
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = var.alb_listener_arn
  priority     = var.alb_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = ["/api/products*", "/health", "/metrics"]
    }
  }

  tags = var.tags
}

# ─── Security Group ──────────────────────────────────────────────────────────

resource "aws_security_group" "service" {
  name_prefix = "${var.service_name}-"
  vpc_id      = var.vpc_id
  description = "Security group for ${var.service_name} ECS tasks"

  # Inbound: only from ALB
  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "Allow traffic from ALB"
  }

  # Outbound: allow all (for calling downstream services, ECR, CloudWatch)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ─── IAM Roles ───────────────────────────────────────────────────────────────

resource "aws_iam_role" "execution" {
  name = "${var.service_name}-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name = "${var.service_name}-task-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# ─── CloudWatch Logs ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.service_name}/${var.environment}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
