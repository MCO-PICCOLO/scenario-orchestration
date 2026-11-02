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
# Single-node pullpiri runtime install.
# Usage: install-pullpiri.sh [NODE_IP] [NODE_NAME]
#   NODE_IP    local node IP (auto-detected from the first NIC if omitted)
#   NODE_NAME  Pullpiri node name (default: this machine's hostname); must match
#              the name used in the workload YAMLs and the timpani node config

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./owned-state.sh
source "${SCRIPT_DIR}/owned-state.sh"

if [ -n "${1:-}" ]; then
	NODE_IP="$1"
else
	NODE_IP="$(hostname -I | awk '{print $1}')"
fi

HOST_NAME="${2:-$(hostname)}"
if [[ ! "${HOST_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
	echo "ERROR: Invalid NODE_NAME - '${HOST_NAME}'" >&2
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
  ip: ${NODE_IP}
  type: vehicle
  role: master
dds:
  idl_path: src/vehicle/dds/idl
  domain_id: 100
EOF

bash "${SCRIPT_DIR}/pullpiri-server.sh" "${NODE_IP}"
bash "${SCRIPT_DIR}/pullpiri-player.sh" "${NODE_IP}"

sleep 1

# Single-node: the nodeagent runs on this same machine.
bash "${SCRIPT_DIR}/install-agent.sh" "${NODE_IP}" "${NODE_IP}" "${HOST_NAME}"
