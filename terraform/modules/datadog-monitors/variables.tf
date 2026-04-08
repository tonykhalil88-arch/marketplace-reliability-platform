variable "service_name" {
  description = "Name of the service to monitor"
  type        = string
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "marketplace" {
  description = "Marketplace identifier (redbubble, teepublic)"
  type        = string
  default     = "redbubble"
}

variable "latency_target_ms" {
  description = "Latency SLO target in milliseconds"
  type        = number
  default     = 500
}

variable "latency_target_seconds" {
  description = "Latency SLO target in seconds (used in metric queries)"
  type        = number
  default     = 0.5
}

variable "burn_rate_critical" {
  description = "Critical burn rate threshold (1-hour window). 14.4x = budget exhausted in ~2 hours"
  type        = number
  default     = 14.4
}

variable "burn_rate_warning" {
  description = "Warning burn rate threshold (6-hour window). 6x = budget exhausted in ~5 days"
  type        = number
  default     = 6.0
}

variable "slack_channel" {
  description = "Slack channel for alert notifications (without #)"
  type        = string
  default     = "platform-alerts"
}

variable "pagerduty_service" {
  description = "PagerDuty service key for page-level alerts"
  type        = string
  default     = "marketplace-oncall"
}

variable "tags" {
  description = "Additional tags for all Datadog resources"
  type        = list(string)
  default     = []
}
