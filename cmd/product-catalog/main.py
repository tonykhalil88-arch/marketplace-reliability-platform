"""
Product Catalog Microservice
Simulates a marketplace product catalog (Redbubble/TeePublic style)
with reliability patterns: circuit breaker, structured logging,
graceful shutdown, and Prometheus metrics.
"""

import asyncio
import logging
import os
import signal
import time
import uuid
from contextlib import asynccontextmanager
from enum import Enum
from typing import Optional

import pathlib

import uvicorn
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles

from circuit_breaker import CircuitBreaker
from metrics import MetricsCollector, metrics_middleware
from models import Product, HealthResponse, HealthStatus, DependencyHealth

# ─── Configuration ──────────────────────────────────────────────────────────

REGION = os.getenv("REGION", "us-east-1")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
SERVICE_NAME = "product-catalog"
SERVICE_VERSION = os.getenv("SERVICE_VERSION", "0.1.0")
PORT = int(os.getenv("PORT", "8080"))
SHUTDOWN_TIMEOUT = int(os.getenv("SHUTDOWN_TIMEOUT", "30"))

# Simulated latency thresholds per region (ms)
REGION_LATENCY = {
    "us-east-1": 50,    # New York
    "ap-southeast-2": 80,  # Melbourne
}

# ─── Structured Logging ────────────────────────────────────────────────────

class StructuredFormatter(logging.Formatter):
    """JSON structured log formatter with correlation ID support."""

    def format(self, record):
        import json
        log_entry = {
            "timestamp": self.formatTime(record),
            "level": record.levelname,
            "service": SERVICE_NAME,
            "version": SERVICE_VERSION,
            "region": REGION,
            "environment": ENVIRONMENT,
            "message": record.getMessage(),
            "logger": record.name,
        }
        if hasattr(record, "correlation_id"):
            log_entry["correlation_id"] = record.correlation_id
        if hasattr(record, "duration_ms"):
            log_entry["duration_ms"] = record.duration_ms
        if hasattr(record, "status_code"):
            log_entry["status_code"] = record.status_code
        if hasattr(record, "path"):
            log_entry["path"] = record.path
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_entry)


handler = logging.StreamHandler()
handler.setFormatter(StructuredFormatter())
logger = logging.getLogger(SERVICE_NAME)
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# ─── Simulated Data ────────────────────────────────────────────────────────

PRODUCTS = [
    Product(
        id="prod-001",
        title="Cosmic Cat Galaxy Design",
        artist="stellar_designs",
        category="t-shirts",
        price=25.99,
        marketplace="redbubble",
        tags=["cat", "galaxy", "space", "cosmic"],
    ),
    Product(
        id="prod-002",
        title="Retro Sunset Mountain",
        artist="nature_arts",
        category="stickers",
        price=3.49,
        marketplace="teepublic",
        tags=["retro", "sunset", "mountain", "nature"],
    ),
    Product(
        id="prod-003",
        title="Programmer Coffee Loop",
        artist="dev_humor",
        category="mugs",
        price=14.99,
        marketplace="redbubble",
        tags=["programming", "coffee", "humor", "developer"],
    ),
    Product(
        id="prod-004",
        title="Watercolor Botanical Set",
        artist="flora_studio",
        category="stationery",
        price=8.99,
        marketplace="teepublic",
        tags=["watercolor", "botanical", "flowers", "art"],
    ),
    Product(
        id="prod-005",
        title="Minimalist Geometric Bear",
        artist="geo_wildlife",
        category="phone-cases",
        price=19.99,
        marketplace="redbubble",
        tags=["minimalist", "geometric", "bear", "wildlife"],
    ),
]

# ─── Dependencies (simulated) ──────────────────────────────────────────────

artist_service_breaker = CircuitBreaker(
    name="artist-service",
    failure_threshold=5,
    recovery_timeout=30.0,
    half_open_max_calls=3,
)

async def call_artist_service(artist_id: str) -> dict:
    """Simulate calling the artist service with circuit breaker protection."""
    async def _call():
        # Simulate variable latency and occasional failures
        import random
        latency = random.gauss(
            REGION_LATENCY.get(REGION, 60), 15
        )
        await asyncio.sleep(max(0, latency) / 1000)

        # 5% failure rate to demonstrate circuit breaker
        if random.random() < 0.05:
            raise Exception("artist-service: connection timeout")

        return {
            "artist_id": artist_id,
            "verified": True,
            "total_sales": random.randint(100, 50000),
        }

    return await artist_service_breaker.call(_call)

# ─── Graceful Shutdown ──────────────────────────────────────────────────────

shutdown_event = asyncio.Event()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle with graceful shutdown."""
    logger.info("Starting product-catalog service", extra={
        "region": REGION,
        "environment": ENVIRONMENT,
    })

    loop = asyncio.get_event_loop()

    def _signal_handler():
        logger.info("Shutdown signal received, draining connections...")
        shutdown_event.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, _signal_handler)
        except NotImplementedError:
            # Windows doesn't support add_signal_handler
            signal.signal(sig, lambda s, f: _signal_handler())

    yield

    logger.info("Shutting down gracefully", extra={
        "timeout_seconds": SHUTDOWN_TIMEOUT,
    })
    # Allow in-flight requests to complete
    await asyncio.sleep(2)
    logger.info("Shutdown complete")

# ─── Application ────────────────────────────────────────────────────────────

app = FastAPI(
    title="Product Catalog API",
    description="Marketplace product catalog with reliability patterns",
    version=SERVICE_VERSION,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)

metrics = MetricsCollector(service_name=SERVICE_NAME, region=REGION)
app.middleware("http")(metrics_middleware(metrics))

# ─── Middleware: Correlation ID ─────────────────────────────────────────────

@app.middleware("http")
async def correlation_id_middleware(request: Request, call_next):
    correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
    request.state.correlation_id = correlation_id
    response = await call_next(request)
    response.headers["X-Correlation-ID"] = correlation_id
    return response

# ─── Routes ─────────────────────────────────────────────────────────────────

@app.get("/api/products", response_model=list[Product])
async def list_products(
    request: Request,
    marketplace: Optional[str] = None,
    category: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
):
    """
    List products from the catalog.
    Supports filtering by marketplace (redbubble/teepublic) and category.
    """
    results = PRODUCTS

    if marketplace:
        results = [p for p in results if p.marketplace == marketplace]
    if category:
        results = [p for p in results if p.category == category]

    total = len(results)
    results = results[offset : offset + limit]

    logger.info(
        f"Listed {len(results)} products (total: {total})",
        extra={
            "correlation_id": getattr(request.state, "correlation_id", None),
            "path": "/api/products",
        },
    )

    return results


@app.get("/api/products/{product_id}", response_model=Product)
async def get_product(request: Request, product_id: str):
    """
    Get a single product by ID.
    Enriches response with artist data via the artist service (circuit breaker protected).
    """
    product = next((p for p in PRODUCTS if p.id == product_id), None)
    if not product:
        metrics.record_error("product_not_found")
        return JSONResponse(status_code=404, content={"error": "Product not found"})

    # Enrich with artist data (circuit breaker protected)
    try:
        artist_data = await call_artist_service(product.artist)
        enriched = product.model_dump()
        enriched["artist_info"] = artist_data
    except Exception as e:
        # Degrade gracefully — return product without artist enrichment
        logger.warning(
            f"Artist service unavailable, returning degraded response: {e}",
            extra={
                "correlation_id": getattr(request.state, "correlation_id", None),
                "circuit_breaker_state": artist_service_breaker.state.value,
            },
        )
        enriched = product.model_dump()
        enriched["artist_info"] = None
        enriched["_degraded"] = True

    return enriched


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """
    Health check endpoint with dependency status.
    Used by Kubernetes liveness/readiness probes.
    """
    artist_svc_healthy = artist_service_breaker.state.value != "open"

    dependencies = [
        DependencyHealth(
            name="artist-service",
            status="healthy" if artist_svc_healthy else "degraded",
            latency_ms=REGION_LATENCY.get(REGION, 60),
            circuit_breaker_state=artist_service_breaker.state.value,
        ),
    ]

    overall = HealthStatus.HEALTHY if artist_svc_healthy else HealthStatus.DEGRADED

    if shutdown_event.is_set():
        overall = HealthStatus.UNHEALTHY

    return HealthResponse(
        status=overall,
        service=SERVICE_NAME,
        version=SERVICE_VERSION,
        region=REGION,
        environment=ENVIRONMENT,
        dependencies=dependencies,
        uptime_seconds=time.time() - metrics.start_time,
    )


@app.get("/metrics")
async def prometheus_metrics():
    """
    Expose metrics in Prometheus text format.
    Compatible with Datadog agent's Prometheus check.
    """
    return Response(
        content=metrics.to_prometheus_format(),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )


# ─── Frontend ───────────────────────────────────────────────────────────────

STATIC_DIR = pathlib.Path(__file__).parent / "static"


@app.get("/", include_in_schema=False)
async def serve_frontend():
    """Serve the marketplace frontend."""
    return FileResponse(STATIC_DIR / "index.html")


# ─── Entrypoint ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=PORT,
        log_level="info",
        access_log=False,  # We handle our own structured logging
    )
