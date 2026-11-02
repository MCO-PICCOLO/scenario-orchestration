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
# Single-node pullpiri runtime uninstall.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./owned-state.sh
source "${SCRIPT_DIR}/owned-state.sh"

podman pod stop -t 0 pullpiri-player || true
podman pod rm -f --ignore pullpiri-player || true
podman pod stop -t 0 pullpiri-server || true
podman pod rm -f --ignore pullpiri-server || true

sleep 1

# Remove only what install-pullpiri.sh created and restore anything it replaced.
# Pre-existing Pullpiri state (other files under /etc/pullpiri, its own RocksDB
# data, an existing settings.yaml) is left intact.
resiso_release "${RESISO_ROCKSDB_DIR}"
resiso_release "${RESISO_SETTINGS_FILE}"
resiso_release "${RESISO_LOG_DIR}"

# Single-node: the nodeagent runs on this same machine.
# uninstall-agent.sh also removes the ownership state once nothing is left.
bash "${SCRIPT_DIR}/uninstall-agent.sh"
