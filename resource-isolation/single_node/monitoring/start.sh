#!/bin/bash
# /********************************************************************************
# * Copyright (c) 2026 Contributors to the Eclipse Foundation
# *
# * See the NOTICE file(s) distributed with this work for additional
# * information regarding copyright ownership.
# *
# * This program and the accompanying materials are made available under the
# * terms of the Apache License 2.0 which is available at
# * https://www.apache.org/licenses/LICENSE-2.0
# *
# * SPDX-License-Identifier: Apache-2.0
# ********************************************************************************/

# Start Monitoring Stack (Prometheus + Grafana)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Starting LED Control Demo Monitoring ==="
echo ""

# Check if docker/podman is available
if command -v docker &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v podman-compose &> /dev/null; then
    COMPOSE_CMD="podman-compose"
else
    echo "Error: docker or podman-compose not found"
    exit 1
fi

cd "$SCRIPT_DIR"

# Start services
echo "Starting Prometheus and Grafana..."
$COMPOSE_CMD up -d

echo ""
echo "=== Monitoring Stack Started ==="
echo ""
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:3000 (admin/admin)"
echo ""
echo "  Dashboard:  LED Control Demo - TIMPANI vs Normal"
echo ""
echo "Waiting for metrics from LED controllers:"
echo "  - led-timpani-ctrl: http://localhost:9101/metrics"
echo "  - led-normal-ctrl:  http://localhost:9102/metrics"
echo ""
echo "To stop: $COMPOSE_CMD down"
