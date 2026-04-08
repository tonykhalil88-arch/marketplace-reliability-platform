"""Data models for the Product Catalog service."""

from enum import Enum
from typing import Optional

from pydantic import BaseModel


class HealthStatus(str, Enum):
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"


class DependencyHealth(BaseModel):
    name: str
    status: str
    latency_ms: float
    circuit_breaker_state: Optional[str] = None


class HealthResponse(BaseModel):
    status: HealthStatus
    service: str
    version: str
    region: str
    environment: str
    dependencies: list[DependencyHealth]
    uptime_seconds: float


class Product(BaseModel):
    id: str
    title: str
    artist: str
    category: str
    price: float
    marketplace: str  # "redbubble" or "teepublic"
    tags: list[str] = []
