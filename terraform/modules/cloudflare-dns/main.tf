terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.20"
    }
  }
}

# ─── Cloudflare DNS & Security Module ────────────────────────────────────────
# Manages DNS records, failover, and WAF rules for the marketplace.
#
# Cloudflare sits in front of both the US and AU regions, providing:
#   - Geo-based traffic routing (US users → us-east-1, AU/APAC → ap-southeast-2)
#   - Automatic failover if a region becomes unhealthy
#   - WAF rules to protect product catalog API endpoints
#   - Page rules for caching static product data at the edge

# ─── DNS Records ─────────────────────────────────────────────────────────────

# Primary CNAME pointing to the load balancer
resource "cloudflare_record" "primary" {
  zone_id = var.zone_id
  name    = var.subdomain
  content = var.origin_alb_dns
  type    = "CNAME"
  proxied = true # Traffic flows through Cloudflare (enables WAF, caching, DDoS)
  ttl     = 1    # Auto TTL when proxied

  comment = "Primary endpoint for ${var.service_name} (${var.environment})"
}

# ─── Health Checks ───────────────────────────────────────────────────────────
# Monitor each region independently for failover decisions

resource "cloudflare_healthcheck" "us" {
  zone_id     = var.zone_id
  name        = "${var.service_name}-us-health"
  address     = var.us_origin_address
  type        = "HTTPS"
  port        = 443
  method      = "GET"
  path        = "/health"
  timeout     = 5
  retries     = 2
  interval    = 60
  description = "Health check for US region (${var.service_name})"

  header {
    header = "Host"
    values = [var.hostname]
  }
}

resource "cloudflare_healthcheck" "au" {
  count = var.enable_multi_region ? 1 : 0

  zone_id     = var.zone_id
  name        = "${var.service_name}-au-health"
  address     = var.au_origin_address
  type        = "HTTPS"
  port        = 443
  method      = "GET"
  path        = "/health"
  timeout     = 5
  retries     = 2
  interval    = 60
  description = "Health check for AU region (${var.service_name})"

  header {
    header = "Host"
    values = [var.hostname]
  }
}

# ─── Load Balancing (Geo-based with failover) ───────────────────────────────
# Routes traffic to the nearest healthy region.
# If AU region is down, all traffic fails over to US (and vice versa).

resource "cloudflare_load_balancer_pool" "us" {
  account_id = var.account_id
  name       = "${var.service_name}-us-pool"

  origins {
    name    = "us-east-1"
    address = var.us_origin_address
    enabled = true
    weight  = 1.0

    header {
      header = "Host"
      values = [var.hostname]
    }
  }

  notification_email = var.alert_email
  minimum_origins    = 1

  monitor = cloudflare_load_balancer_monitor.default.id
}

resource "cloudflare_load_balancer_pool" "au" {
  count = var.enable_multi_region ? 1 : 0

  account_id = var.account_id
  name       = "${var.service_name}-au-pool"

  origins {
    name    = "ap-southeast-2"
    address = var.au_origin_address
    enabled = true
    weight  = 1.0

    header {
      header = "Host"
      values = [var.hostname]
    }
  }

  notification_email = var.alert_email
  minimum_origins    = 1

  monitor = cloudflare_load_balancer_monitor.default.id
}

resource "cloudflare_load_balancer_monitor" "default" {
  account_id     = var.account_id
  type           = "https"
  method         = "GET"
  path           = "/health"
  timeout        = 5
  retries        = 2
  interval       = 60
  expected_codes = "200"
  description    = "Health monitor for ${var.service_name}"

  header {
    header = "Host"
    values = [var.hostname]
  }
}

resource "cloudflare_load_balancer" "this" {
  count = var.enable_multi_region ? 1 : 0

  zone_id          = var.zone_id
  name             = var.hostname
  default_pool_ids = [cloudflare_load_balancer_pool.us.id]
  fallback_pool_id = cloudflare_load_balancer_pool.us.id
  proxied          = true

  # Geo-based steering: route to nearest region
  steering_policy = "geo"

  # US pool serves Americas and Europe
  # AU pool serves Asia-Pacific
  region_pools {
    region   = "WNAM"
    pool_ids = [cloudflare_load_balancer_pool.us.id]
  }
  region_pools {
    region   = "ENAM"
    pool_ids = [cloudflare_load_balancer_pool.us.id]
  }
  region_pools {
    region   = "WEU"
    pool_ids = [cloudflare_load_balancer_pool.us.id]
  }
  region_pools {
    region   = "EEU"
    pool_ids = [cloudflare_load_balancer_pool.us.id]
  }
  region_pools {
    region   = "OC"
    pool_ids = [cloudflare_load_balancer_pool.au[0].id]
  }
  region_pools {
    region   = "SEAS"
    pool_ids = [cloudflare_load_balancer_pool.au[0].id]
  }
  region_pools {
    region   = "NEAS"
    pool_ids = [cloudflare_load_balancer_pool.au[0].id]
  }
}

# ─── WAF Custom Rules ───────────────────────────────────────────────────────
# Protect the product catalog API from abuse

resource "cloudflare_ruleset" "waf" {
  zone_id = var.zone_id
  name    = "${var.service_name}-waf-rules"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  # Rate limit on product listing endpoint (prevents scraping)
  rules {
    action      = "block"
    expression  = "(http.request.uri.path contains \"/api/products\" and rate.requests_per_period gt 100 and rate.period eq 60)"
    description = "Rate limit product catalog API - block excessive scraping"
    enabled     = true
  }

  # Block requests without valid user agent (bot protection)
  rules {
    action      = "challenge"
    expression  = "(http.request.uri.path contains \"/api/products\" and http.user_agent eq \"\")"
    description = "Challenge requests with empty user agent on product endpoints"
    enabled     = true
  }
}

# ─── Cache Rules ─────────────────────────────────────────────────────────────
# Cache product listing responses at the edge to reduce origin load.
# Product pages change infrequently — a 60s edge cache dramatically
# reduces load during traffic spikes (e.g., artist promotions).

resource "cloudflare_ruleset" "cache" {
  zone_id = var.zone_id
  name    = "${var.service_name}-cache-rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules {
    action      = "set_cache_settings"
    expression  = "(http.request.uri.path contains \"/api/products\" and http.request.method eq \"GET\")"
    description = "Cache product listing responses at edge"
    enabled     = true

    action_parameters {
      cache = true
      edge_ttl {
        mode    = "override_origin"
        default = 60 # 60 second edge cache for product listings
      }
      browser_ttl {
        mode    = "override_origin"
        default = 30
      }
    }
  }
}
