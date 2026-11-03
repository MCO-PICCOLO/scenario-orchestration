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
# timpani-o runtime install (manual container smoke test).
# Pulls the timpani-o image from the registry and runs it directly with
# `podman run`, then checks the container stayed up. Only timpani-o is started
# here (timpani-n is started later, in Step 7 of the resource-isolation flow).
#
# Overridable via environment:
#   MASTER_NODE_NAME    master node name written into the node config (required)
#   GUEST_NODE_NAME     guest node name written into the node config (required)
#   NODE_CONFIG_YAML    ready-made node_configurations.yaml to mount instead of
#                       rendering ../config/node_configurations.yaml.template
#   TIMPANI_O_IMAGE     container image tag (default ghcr.io/mco-piccolo/timpani-o:latest)
#   TIMPANI_O_GRPC_PORT gRPC port to publish (default 50052)
#   TIMPANI_O_DATA_PORT data port to publish (default 7777)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NODE_CONFIG_TEMPLATE="${SCRIPT_DIR}/../config/node_configurations.yaml.template"
NODE_CONFIG_YAML="${NODE_CONFIG_YAML:-}"
RENDER_DIR="/run/resource-isolation"
TIMPANI_O_IMAGE="${TIMPANI_O_IMAGE:-ghcr.io/mco-piccolo/timpani-o:latest}"
TIMPANI_O_NAME="timpani-o"
TIMPANI_O_GRPC_PORT="${TIMPANI_O_GRPC_PORT:-50052}"
TIMPANI_O_DATA_PORT="${TIMPANI_O_DATA_PORT:-7777}"
# Path the config is mounted to inside the container (matches the image layout).
CONFIG_IN_CONTAINER="/timpani-o/examples/node_configurations.yaml"

log() { echo "[install-timpani-o] $*"; }
die() { echo "[install-timpani-o] ERROR: $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Please run as root: sudo $0"

build_cpu_list() {
    if [[ -n "${AVAILABLE_CPUS:-}" ]]; then
        printf '%s' "${AVAILABLE_CPUS}"
        return 0
    fi
    printf '%s' "[12, 13, 14, 15]"
}

# --- render the node config from the template --------------------------------
render_node_config() {
    local master="${MASTER_NODE_NAME:-}" guest="${GUEST_NODE_NAME:-}" var
    for var in master guest; do
        [[ "${!var}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
            || die "${var^^}_NODE_NAME is empty or invalid ('${!var}'); set it in config.env"
    done
    [[ "${master}" != "${guest}" ]] \
        || die "MASTER_NODE_NAME and GUEST_NODE_NAME must differ (both '${master}')"
    [[ -f "${NODE_CONFIG_TEMPLATE}" ]] || die "Template not found: ${NODE_CONFIG_TEMPLATE}"

    local content master_cpus guest_cpus
    master_cpus="$(build_cpu_list)"
    guest_cpus="$(build_cpu_list)"
    content="$(<"${NODE_CONFIG_TEMPLATE}")"
    content="${content//\$\{MASTER_NODE_NAME\}/${master}}"
    content="${content//\$\{GUEST_NODE_NAME\}/${guest}}"
    content="${content//\$\{MASTER_AVAILABLE_CPUS\}/${master_cpus}}"
    content="${content//\$\{GUEST_AVAILABLE_CPUS\}/${guest_cpus}}"
    install -d -m 0755 "${RENDER_DIR}"
    NODE_CONFIG_YAML="${RENDER_DIR}/node_configurations.yaml"
    printf '%s\n' "${content}" > "${NODE_CONFIG_YAML}"
    log "Rendered ${NODE_CONFIG_YAML} (master='${master}', guest='${guest}', master_cpus=${master_cpus}, guest_cpus=${guest_cpus})"
}

# --- pull the image and run the container -----------------------------------
run_timpani_o() {
    [[ -n "${NODE_CONFIG_YAML}" ]] || render_node_config
    [[ -f "${NODE_CONFIG_YAML}" ]] || die "Node config not found: ${NODE_CONFIG_YAML}"

    log "Pulling image ${TIMPANI_O_IMAGE}..."
    podman pull "${TIMPANI_O_IMAGE}" || die "Failed to pull ${TIMPANI_O_IMAGE}"

    log "Starting container..."
    podman rm -f "${TIMPANI_O_NAME}" 2>/dev/null || true

    # -s/-d/-c must be passed explicitly, otherwise timpani-o starts with
    # "NodeConfigManager is not loaded" and scheduling fails.
    podman run -d \
        --name "${TIMPANI_O_NAME}" \
        --publish "${TIMPANI_O_GRPC_PORT}:${TIMPANI_O_GRPC_PORT}" \
        --publish "${TIMPANI_O_DATA_PORT}:${TIMPANI_O_DATA_PORT}" \
        --volume "${NODE_CONFIG_YAML}:${CONFIG_IN_CONTAINER}:ro" \
        "${TIMPANI_O_IMAGE}" \
        -s "${TIMPANI_O_GRPC_PORT}" -d "${TIMPANI_O_DATA_PORT}" -c "${CONFIG_IN_CONTAINER}" \
        || die "Failed to start timpani-o container"

    # Smoke test: podman run -d returns 0 even if the container dies right away,
    # so confirm it is still up and dump recent logs.
    sleep 3
    if ! podman ps --format '{{.Names}}' | grep -Fxq "${TIMPANI_O_NAME}"; then
        podman logs "${TIMPANI_O_NAME}" 2>&1 | tail -n 40 || true
        die "Smoke test failed: '${TIMPANI_O_NAME}' container exited"
    fi
    log "Smoke test passed: '${TIMPANI_O_NAME}' is running. Recent logs:"
    podman logs "${TIMPANI_O_NAME}" 2>&1 | tail -n 20 || true
}

run_timpani_o

log "Done. Status: podman ps | Logs: podman logs -f ${TIMPANI_O_NAME}"
