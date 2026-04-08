#!/bin/bash
set -ex

# Install dependencies
dnf install -y python3.11 python3.11-pip git

# Clone the repo
cd /home/ec2-user
git clone https://github.com/tonykhalil88-arch/marketplace-reliability-platform.git app
cd app

# Install Python dependencies
python3.11 -m pip install -r requirements.txt

# Create a systemd service for auto-start and resilience
cat > /etc/systemd/system/product-catalog.service << 'UNIT'
[Unit]
Description=Product Catalog Microservice
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/app/cmd/product-catalog
Environment=ENVIRONMENT=production
Environment=REGION=ap-southeast-2
Environment=SERVICE_VERSION=demo
ExecStart=/usr/bin/python3.11 main.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# Fix ownership
chown -R ec2-user:ec2-user /home/ec2-user/app

# Start the service
systemctl daemon-reload
systemctl enable product-catalog
systemctl start product-catalog
