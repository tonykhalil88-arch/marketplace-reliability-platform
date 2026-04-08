# ─── Production Environment ──────────────────────────────────────────────────
# Multi-region deployment: US (us-east-1) + AU (ap-southeast-2)
# High availability, strict SLO monitoring, Cloudflare geo-routing.

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
    key            = "production/product-catalog/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

# ─── Providers ───────────────────────────────────────────────────────────────

provider "aws" {
  region = "us-east-1"
  alias  = "us"

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  region = "ap-southeast-2"
  alias  = "au"

  default_tags {
    tags = local.common_tags
  }
}

provider "cloudflare" {}
provider "datadog" {}

locals {
  common_tags = {
    Environment = "production"
    Service     = "product-catalog"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

# ─── Data Sources: US Region ────────────────────────────────────────────────

data "aws_vpc" "us" {
  provider = aws.us
  tags     = { Name = "production-vpc-us" }
}

data "aws_subnets" "us_private" {
  provider = aws.us
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.us.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
}

data "aws_ecs_cluster" "us" {
  provider     = aws.us
  cluster_name = "production-cluster-us"
}

data "aws_lb" "us" {
  provider = aws.us
  name     = "production-alb-us"
}

data "aws_lb_listener" "us_https" {
  provider          = aws.us
  load_balancer_arn = data.aws_lb.us.arn
  port              = 443
}

data "aws_security_group" "us_alb" {
  provider = aws.us
  name     = "production-alb-sg-us"
  vpc_id   = data.aws_vpc.us.id
}

# ─── Data Sources: AU Region ────────────────────────────────────────────────

data "aws_vpc" "au" {
  provider = aws.au
  tags     = { Name = "production-vpc-au" }
}

data "aws_subnets" "au_private" {
  provider = aws.au
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.au.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
}

data "aws_ecs_cluster" "au" {
  provider     = aws.au
  cluster_name = "production-cluster-au"
}

data "aws_lb" "au" {
  provider = aws.au
  name     = "production-alb-au"
}

data "aws_lb_listener" "au_https" {
  provider          = aws.au
  load_balancer_arn = data.aws_lb.au.arn
  port              = 443
}

data "aws_security_group" "au_alb" {
  provider = aws.au
  name     = "production-alb-sg-au"
  vpc_id   = data.aws_vpc.au.id
}

# ─── ECS Service: US Region ─────────────────────────────────────────────────

module "ecs_service_us" {
  source = "../../modules/ecs-service"

  providers = {
    aws = aws.us
  }

  service_name       = "product-catalog"
  environment        = "production"
  aws_region         = "us-east-1"
  ecr_repository_url = "123456789.dkr.ecr.us-east-1.amazonaws.com/product-catalog"
  image_tag          = var.image_tag

  # Production resources — US is primary region, higher capacity
  cpu           = 512
  memory        = 1024
  desired_count = 3
  min_capacity  = 3
  max_capacity  = 20

  ecs_cluster_arn       = data.aws_ecs_cluster.us.arn
  ecs_cluster_name      = data.aws_ecs_cluster.us.cluster_name
  vpc_id                = data.aws_vpc.us.id
  private_subnet_ids    = data.aws_subnets.us_private.ids
  alb_listener_arn      = data.aws_lb_listener.us_https.arn
  alb_arn_suffix        = data.aws_lb.us.arn_suffix
  alb_security_group_id = data.aws_security_group.us_alb.id
  alb_rule_priority     = 100

  log_retention_days = 90

  tags = merge(local.common_tags, { Region = "us-east-1" })
}

# ─── ECS Service: AU Region ─────────────────────────────────────────────────

module "ecs_service_au" {
  source = "../../modules/ecs-service"

  providers = {
    aws = aws.au
  }

  service_name       = "product-catalog"
  environment        = "production"
  aws_region         = "ap-southeast-2"
  ecr_repository_url = "123456789.dkr.ecr.ap-southeast-2.amazonaws.com/product-catalog"
  image_tag          = var.image_tag

  # AU region — lower capacity, higher per-task resources for latency
  cpu           = 512
  memory        = 1024
  desired_count = 2
  min_capacity  = 2
  max_capacity  = 10

  ecs_cluster_arn       = data.aws_ecs_cluster.au.arn
  ecs_cluster_name      = data.aws_ecs_cluster.au.cluster_name
  vpc_id                = data.aws_vpc.au.id
  private_subnet_ids    = data.aws_subnets.au_private.ids
  alb_listener_arn      = data.aws_lb_listener.au_https.arn
  alb_arn_suffix        = data.aws_lb.au.arn_suffix
  alb_security_group_id = data.aws_security_group.au_alb.id
  alb_rule_priority     = 100

  log_retention_days = 90

  tags = merge(local.common_tags, { Region = "ap-southeast-2" })
}

# ─── Cloudflare: Multi-Region DNS + Load Balancing ──────────────────────────

module "cloudflare_dns" {
  source = "../../modules/cloudflare-dns"

  service_name      = "product-catalog"
  environment       = "production"
  account_id        = var.cloudflare_account_id
  zone_id           = var.cloudflare_zone_id
  subdomain         = "catalog"
  hostname          = "catalog.marketplace.com"
  origin_alb_dns    = data.aws_lb.us.dns_name
  us_origin_address = data.aws_lb.us.dns_name
  au_origin_address = data.aws_lb.au.dns_name

  enable_multi_region = true # Geo-routing between US and AU
  alert_email         = "platform-oncall@articore.com"
}

# ─── Datadog: Production SLO Monitoring ──────────────────────────────────────
# One set of monitors per marketplace — Redbubble and TeePublic
# may have different traffic patterns and SLO targets.

module "datadog_monitors_redbubble" {
  source = "../../modules/datadog-monitors"

  service_name  = "product-catalog"
  environment   = "production"
  marketplace   = "redbubble"
  slack_channel = "platform-prod-alerts"

  # Production SLO targets
  latency_target_ms      = 500
  latency_target_seconds = 0.5
  burn_rate_critical     = 14.4
  burn_rate_warning      = 6.0
  pagerduty_service      = "marketplace-oncall"

  tags = ["environment:production", "marketplace:redbubble"]
}

module "datadog_monitors_teepublic" {
  source = "../../modules/datadog-monitors"

  service_name  = "product-catalog"
  environment   = "production"
  marketplace   = "teepublic"
  slack_channel = "platform-prod-alerts"

  # TeePublic may have slightly different targets
  latency_target_ms      = 500
  latency_target_seconds = 0.5
  burn_rate_critical     = 14.4
  burn_rate_warning      = 6.0
  pagerduty_service      = "marketplace-oncall"

  tags = ["environment:production", "marketplace:teepublic"]
}

# ─── Variables ───────────────────────────────────────────────────────────────

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
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

output "us_ecs_service" {
  value = module.ecs_service_us.service_name
}

output "au_ecs_service" {
  value = module.ecs_service_au.service_name
}

output "service_url" {
  value = "https://catalog.marketplace.com"
}

output "redbubble_availability_slo_id" {
  value = module.datadog_monitors_redbubble.availability_slo_id
}

output "teepublic_availability_slo_id" {
  value = module.datadog_monitors_teepublic.availability_slo_id
}

output "redbubble_latency_slo_id" {
  value = module.datadog_monitors_redbubble.latency_slo_id
}
