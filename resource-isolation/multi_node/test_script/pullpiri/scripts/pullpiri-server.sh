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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./owned-state.sh
source "${SCRIPT_DIR}/owned-state.sh"

if [ -n "${1:-}" ]; then
	MASTER_IP="$1"
else
	MASTER_IP="$(hostname -I | awk '{print $1}')"
fi

ROCKSDB_VERSION="v11.18.0"
ROCKSDB_IMAGE="ghcr.io/mco-piccolo/pullpiri-rocksdb:${ROCKSDB_VERSION}"

VERSION="v0.7.2-fix.01"
CONTAINER_IMAGE="ghcr.io/eclipse-pullpiri/pullpiri:${VERSION}"

echo "Running server with image: ${CONTAINER_IMAGE}"

podman pod create \
  --name pullpiri-server \
  --network host \
  --pid host

podman run -d \
  --pod pullpiri-server \
  --name pullpiri-rocksdbservice \
  --user 0:0 \
  -e RUST_LOG="info" \
  -v "${RESISO_ROCKSDB_DIR}":/data:Z \
  ${ROCKSDB_IMAGE} \
  rocksdbservice --path /data --addr 0.0.0.0 --port 47007

podman run -d \
  --pod pullpiri-server \
  --name pullpiri-apiserver \
  -e ROCKSDB_SERVICE_URL="http://${MASTER_IP}:47007" \
  -v /etc/pullpiri/settings.yaml:/etc/pullpiri/settings.yaml:Z \
  -v /run/pullpirilog/:/run/pullpirilog/ \
  ${CONTAINER_IMAGE} \
  /pullpiri/apiserver

podman run -d \
  --pod pullpiri-server \
  --name pullpiri-policymanager \
  -e ROCKSDB_SERVICE_URL="http://${MASTER_IP}:47007" \
  -v /etc/pullpiri/settings.yaml:/etc/pullpiri/settings.yaml:Z \
  -v /run/pullpirilog/:/run/pullpirilog/ \
  ${CONTAINER_IMAGE} \
  /pullpiri/policymanager

podman run -d \
  --pod pullpiri-server \
  --name pullpiri-monitoringserver \
  -e ROCKSDB_SERVICE_URL="http://${MASTER_IP}:47007" \
  -v /etc/pullpiri/settings.yaml:/etc/pullpiri/settings.yaml:Z \
  -v /run/pullpirilog/:/run/pullpirilog/ \
  ${CONTAINER_IMAGE} \
  /pullpiri/monitoringserver

podman run -d \
  --pod pullpiri-server \
  --name pullpiri-logservice \
  -e ROCKSDB_SERVICE_URL="http://${MASTER_IP}:47007" \
  -v /etc/pullpiri/settings.yaml:/etc/pullpiri/settings.yaml:Z \
  -v /run/pullpirilog/:/run/pullpirilog/ \
  ${CONTAINER_IMAGE} \
  /pullpiri/logservice

podman run -d \
  --pod pullpiri-server \
  --name pullpiri-settingsservice \
  -e ROCKSDB_SERVICE_URL="http://${MASTER_IP}:47007" \
  -v /etc/pullpiri/settings.yaml:/etc/pullpiri/settings.yaml:Z \
  -v /run/pullpirilog/:/run/pullpirilog/ \
  ${CONTAINER_IMAGE} \
  /pullpiri/settingsservice --bind-address=${MASTER_IP} --bind-port=8080 --log-level=debug
