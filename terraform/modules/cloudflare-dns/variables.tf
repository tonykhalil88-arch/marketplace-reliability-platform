variable "service_name" {
  description = "Name of the service"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID for the domain"
  type        = string
}

variable "subdomain" {
  description = "Subdomain for the DNS record (e.g., 'catalog' for catalog.marketplace.com)"
  type        = string
}

variable "hostname" {
  description = "Full hostname (e.g., catalog.marketplace.com)"
  type        = string
}

variable "origin_alb_dns" {
  description = "DNS name of the primary ALB origin"
  type        = string
}

variable "us_origin_address" {
  description = "US region origin address for health checks and load balancing"
  type        = string
}

variable "au_origin_address" {
  description = "AU region origin address for health checks and load balancing"
  type        = string
  default     = ""
}

variable "enable_multi_region" {
  description = "Enable multi-region load balancing (US + AU)"
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address for health check alerts"
  type        = string
  default     = "platform-alerts@articore.com"
}
