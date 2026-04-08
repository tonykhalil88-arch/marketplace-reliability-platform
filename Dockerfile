# ─── Stage 1: Build ──────────────────────────────────────────────────────────
FROM python:3.13-slim AS builder

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ─── Stage 2: Runtime ────────────────────────────────────────────────────────
FROM python:3.13-slim AS runtime

# Security: run as non-root
RUN groupadd -r appuser && useradd -r -g appuser -d /app appuser

WORKDIR /app

# Copy installed dependencies from builder
COPY --from=builder /install /usr/local

# Copy application code
COPY cmd/product-catalog/ .

# Metadata labels (OCI standard)
LABEL org.opencontainers.image.title="product-catalog"
LABEL org.opencontainers.image.description="Marketplace product catalog microservice"
LABEL org.opencontainers.image.source="https://github.com/marketplace-reliability-platform"

# Health check for container orchestrators
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

USER appuser

EXPOSE 8080

# Graceful shutdown: SIGTERM handled by the application
STOPSIGNAL SIGTERM

ENTRYPOINT ["python", "main.py"]
