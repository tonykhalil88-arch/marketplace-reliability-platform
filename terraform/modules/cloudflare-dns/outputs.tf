output "dns_record_id" {
  description = "ID of the primary DNS record"
  value       = cloudflare_record.primary.id
}

output "hostname" {
  description = "Full hostname of the service"
  value       = var.hostname
}

output "load_balancer_id" {
  description = "ID of the Cloudflare load balancer (if multi-region enabled)"
  value       = var.enable_multi_region ? cloudflare_load_balancer.this[0].id : null
}

output "us_pool_id" {
  description = "ID of the US origin pool"
  value       = cloudflare_load_balancer_pool.us.id
}
