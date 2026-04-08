.PHONY: run test lint docker-build docker-push clean

SERVICE_NAME := product-catalog
IMAGE_TAG    ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "local")
REGISTRY     ?= 123456789.dkr.ecr.us-east-1.amazonaws.com

# ─── Local Development ───────────────────────────────────────────────────────

run:
	cd cmd/product-catalog && python main.py

install:
	pip install -r requirements.txt

test:
	cd cmd/product-catalog && python -m pytest tests/ -v --tb=short

lint:
	ruff check cmd/product-catalog/
	ruff format --check cmd/product-catalog/

# ─── Docker ──────────────────────────────────────────────────────────────────

docker-build:
	docker build -t $(SERVICE_NAME):$(IMAGE_TAG) .
	docker tag $(SERVICE_NAME):$(IMAGE_TAG) $(SERVICE_NAME):latest

docker-run:
	docker run --rm -p 8080:8080 \
		-e ENVIRONMENT=development \
		-e REGION=us-east-1 \
		$(SERVICE_NAME):latest

docker-push:
	docker tag $(SERVICE_NAME):$(IMAGE_TAG) $(REGISTRY)/$(SERVICE_NAME):$(IMAGE_TAG)
	docker push $(REGISTRY)/$(SERVICE_NAME):$(IMAGE_TAG)

# ─── Helm ────────────────────────────────────────────────────────────────────

helm-lint:
	helm lint ./helm-chart -f helm-chart/values-production.yaml

helm-template:
	helm template $(SERVICE_NAME) ./helm-chart -f helm-chart/values-production.yaml

# ─── Terraform ───────────────────────────────────────────────────────────────

tf-validate:
	cd terraform/environments/staging && terraform init -backend=false && terraform validate

tf-plan:
	cd terraform/environments/staging && terraform plan

# ─── Cleanup ─────────────────────────────────────────────────────────────────

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
