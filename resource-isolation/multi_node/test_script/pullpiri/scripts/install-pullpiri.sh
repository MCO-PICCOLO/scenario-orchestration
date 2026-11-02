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
# Master-side pullpiri runtime install (server, player, master nodeagent).
# Usage: install-pullpiri.sh [MASTER_IP] [MASTER_NODE_NAME]
#   MASTER_IP         master node IP (auto-detected from the first NIC if omitted)
#   MASTER_NODE_NAME  master Pullpiri node name (default: the master's hostname)
# The guest nodeagent is installed separately by the orchestrator
# (run_resource_isolation_flow.sh) over its own SSH connection.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./owned-state.sh
source "${SCRIPT_DIR}/owned-state.sh"

if [ -n "${1:-}" ]; then
	MASTER_IP="$1"
else
	MASTER_IP="$(hostname -I | awk '{print $1}')"
fi

HOST_NAME="${2:-$(hostname)}"
if [[ ! "${HOST_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
	echo "ERROR: Invalid MASTER_NODE_NAME - '${HOST_NAME}'" >&2
	exit 1
fi

# Existing Pullpiri state under /etc/pullpiri is preserved: this flow uses its
# own RocksDB directory and backs up any pre-existing settings.yaml. See
# owned-state.sh; uninstall-pullpiri.sh removes or restores only these items.
resiso_claim_dir "${RESISO_ROCKSDB_DIR}"
mkdir -p "${RESISO_ROCKSDB_DIR}"
chown 1001:1001 "${RESISO_ROCKSDB_DIR}"

resiso_claim_dir "${RESISO_LOG_DIR}"
mkdir -p "${RESISO_LOG_DIR}"

resiso_claim_file "${RESISO_SETTINGS_FILE}"
cat > "${RESISO_SETTINGS_FILE}" << EOF
host:
  name: ${HOST_NAME}
  ip: ${MASTER_IP}
  type: vehicle
  role: master
dds:
  idl_path: src/vehicle/dds/idl
  domain_id: 100
EOF

bash "${SCRIPT_DIR}/pullpiri-server.sh" "${MASTER_IP}"
bash "${SCRIPT_DIR}/pullpiri-player.sh" "${MASTER_IP}"

sleep 1

bash "${SCRIPT_DIR}/install-agent.sh" "${MASTER_IP}" "${MASTER_IP}" "${HOST_NAME}"
