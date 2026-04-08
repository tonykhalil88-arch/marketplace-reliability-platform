output "availability_slo_id" {
  description = "ID of the availability SLO (use in dashboards and reports)"
  value       = datadog_service_level_objective.availability.id
}

output "latency_slo_id" {
  description = "ID of the latency SLO"
  value       = datadog_service_level_objective.latency.id
}

output "burn_rate_page_monitor_id" {
  description = "ID of the critical burn rate monitor (P1)"
  value       = datadog_monitor.availability_burn_rate_page.id
}

output "burn_rate_ticket_monitor_id" {
  description = "ID of the warning burn rate monitor (P3)"
  value       = datadog_monitor.availability_burn_rate_ticket.id
}

output "latency_monitor_id" {
  description = "ID of the latency degradation monitor (P2)"
  value       = datadog_monitor.latency_p99.id
}

output "circuit_breaker_monitor_id" {
  description = "ID of the circuit breaker alert (P2)"
  value       = datadog_monitor.circuit_breaker_open.id
}

output "post_deploy_monitor_id" {
  description = "ID of the post-deploy error spike monitor"
  value       = datadog_monitor.post_deploy_error_spike.id
}

output "slo_dashboard_config" {
  description = "Configuration block for embedding SLOs in a Datadog dashboard"
  value = {
    availability_slo_id = datadog_service_level_objective.availability.id
    latency_slo_id      = datadog_service_level_objective.latency.id
  }
}
