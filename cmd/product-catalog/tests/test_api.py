"""
Tests for the Product Catalog API.
Validates endpoints, SLO-relevant behaviors, and reliability patterns.
"""

import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient
from main import app


@pytest.fixture
def client():
    return TestClient(app)


# ─── Product Listing ────────────────────────────────────────────────────────

class TestListProducts:
    def test_returns_products(self, client):
        resp = client.get("/api/products")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) > 0
        assert "title" in data[0]
        assert "marketplace" in data[0]

    def test_filter_by_marketplace(self, client):
        resp = client.get("/api/products?marketplace=inkvault")
        assert resp.status_code == 200
        for product in resp.json():
            assert product["marketplace"] == "inkvault"

    def test_filter_by_category(self, client):
        resp = client.get("/api/products?category=stickers")
        assert resp.status_code == 200
        for product in resp.json():
            assert product["category"] == "stickers"

    def test_correlation_id_propagated(self, client):
        resp = client.get(
            "/api/products",
            headers={"X-Correlation-ID": "test-corr-123"},
        )
        assert resp.headers["X-Correlation-ID"] == "test-corr-123"

    def test_generates_correlation_id_if_missing(self, client):
        resp = client.get("/api/products")
        assert "X-Correlation-ID" in resp.headers
        assert len(resp.headers["X-Correlation-ID"]) > 0


# ─── Product Detail ─────────────────────────────────────────────────────────

class TestGetProduct:
    def test_existing_product(self, client):
        resp = client.get("/api/products/prod-001")
        assert resp.status_code == 200
        data = resp.json()
        assert data["id"] == "prod-001"
        assert data["title"] == "Neon Samurai Nightfall"

    def test_nonexistent_product_returns_404(self, client):
        resp = client.get("/api/products/prod-999")
        assert resp.status_code == 404

    def test_product_detail_returns_enriched_response(self, client):
        """Product detail should return valid product data with enrichment attempt."""
        resp = client.get("/api/products/prod-001")
        data = resp.json()
        assert data["id"] == "prod-001"
        # The response should contain the base product fields
        assert "title" in data
        assert "artist" in data
        assert "marketplace" in data


# ─── Health Check ────────────────────────────────────────────────────────────

class TestHealth:
    def test_health_endpoint(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] in ["healthy", "degraded", "unhealthy"]
        assert data["service"] == "product-catalog"
        assert "dependencies" in data
        assert "uptime_seconds" in data

    def test_health_includes_region(self, client):
        resp = client.get("/health")
        data = resp.json()
        assert "region" in data

    def test_health_shows_dependency_status(self, client):
        resp = client.get("/health")
        deps = resp.json()["dependencies"]
        assert any(d["name"] == "artist-service" for d in deps)


# ─── Metrics ─────────────────────────────────────────────────────────────────

class TestMetrics:
    def test_metrics_endpoint_returns_prometheus_format(self, client):
        # Make a request first to generate some metrics
        client.get("/api/products")
        resp = client.get("/metrics")
        assert resp.status_code == 200
        body = resp.text
        assert "http_requests_total" in body
        assert "http_request_duration_seconds" in body

    def test_metrics_include_service_labels(self, client):
        client.get("/api/products")
        resp = client.get("/metrics")
        assert 'service="product-catalog"' in resp.text

    def test_server_timing_header(self, client):
        """Verify Server-Timing header for browser devtools integration."""
        resp = client.get("/api/products")
        assert "Server-Timing" in resp.headers
