# ─── Staging Environment ─────────────────────────────────────────────────────
# Single-region (US) deployment for testing and validation.
# Lower resource allocation, relaxed SLO thresholds.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.20"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.40"
    }
  }

  backend "s3" {
    bucket         = "articore-terraform-state"
    key            = "staging/product-catalog/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "staging"
      Service     = "product-catalog"
      Team        = "platform"
      ManagedBy   = "terraform"
    }
  }
}

provider "cloudflare" {
  # API token set via CLOUDFLARE_API_TOKEN env var
}

provider "datadog" {
  # API/App keys set via DD_API_KEY / DD_APP_KEY env vars
}

# ─── Data Sources ────────────────────────────────────────────────────────────

data "aws_vpc" "main" {
  tags = { Name = "staging-vpc" }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
}

data "aws_ecs_cluster" "main" {
  cluster_name = "staging-cluster"
}

data "aws_lb" "main" {
  name = "staging-alb"
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.main.arn
  port              = 443
}

data "aws_security_group" "alb" {
  name   = "staging-alb-sg"
  vpc_id = data.aws_vpc.main.id
}

# ─── ECS Service ─────────────────────────────────────────────────────────────

module "ecs_service" {
  source = "../../modules/ecs-service"

  service_name       = "product-catalog"
  environment        = "staging"
  aws_region         = "us-east-1"
  ecr_repository_url = "123456789.dkr.ecr.us-east-1.amazonaws.com/product-catalog"
  image_tag          = var.image_tag

  # Lower resources for staging
  cpu           = 256
  memory        = 512
  desired_count = 1
  min_capacity  = 1
  max_capacity  = 3

  ecs_cluster_arn       = data.aws_ecs_cluster.main.arn
  ecs_cluster_name      = data.aws_ecs_cluster.main.cluster_name
  vpc_id                = data.aws_vpc.main.id
  private_subnet_ids    = data.aws_subnets.private.ids
  alb_listener_arn      = data.aws_lb_listener.https.arn
  alb_arn_suffix        = data.aws_lb.main.arn_suffix
  alb_security_group_id = data.aws_security_group.alb.id
  alb_rule_priority     = 100

  log_retention_days = 7 # Short retention in staging

  tags = {
    Environment = "staging"
    Service     = "product-catalog"
    Team        = "platform"
  }
}

# ─── Cloudflare DNS ──────────────────────────────────────────────────────────

module "cloudflare_dns" {
  source = "../../modules/cloudflare-dns"

  service_name      = "product-catalog"
  environment       = "staging"
  account_id        = var.cloudflare_account_id
  zone_id           = var.cloudflare_zone_id
  subdomain         = "catalog-staging"
  hostname          = "catalog-staging.marketplace.com"
  origin_alb_dns    = data.aws_lb.main.dns_name
  us_origin_address = data.aws_lb.main.dns_name

  enable_multi_region = false # Single region in staging
}

# ─── Datadog Monitoring ──────────────────────────────────────────────────────

module "datadog_monitors" {
  source = "../../modules/datadog-monitors"

  service_name  = "product-catalog"
  environment   = "staging"
  marketplace   = "redbubble"
  slack_channel = "platform-staging-alerts"

  # Relaxed thresholds for staging — we still want alerting
  # but don't want staging noise paging anyone
  latency_target_ms      = 1000 # 1s in staging (vs 500ms in prod)
  latency_target_seconds = 1.0
  burn_rate_critical     = 20.0 # Higher threshold in staging
  burn_rate_warning      = 10.0
  pagerduty_service      = "staging-notifications" # No paging in staging

  tags = ["environment:staging"]
}

# ─── Variables ───────────────────────────────────────────────────────────────

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "ecs_service_name" {
  value = module.ecs_service.service_name
}

output "service_url" {
  value = "https://catalog-staging.marketplace.com"
}

output "availability_slo_id" {
  value = module.datadog_monitors.availability_slo_id
}
