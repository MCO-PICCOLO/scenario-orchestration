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

SYSTEMD_FILE="/etc/systemd/system/nodeagent.service"
YAML_FILE="/etc/pullpiri/nodeagent.yaml"
BIN_FILE="/opt/pullpiri/nodeagent"
BIN_DIR="/opt/pullpiri"

systemctl stop nodeagent.service || true

# Only disable the unit if install-agent.sh created it. A pre-existing unit is
# restored below and keeps its original enablement.
if resiso_was_created "$SYSTEMD_FILE"; then
	systemctl disable nodeagent.service || true
fi

# Remove what install-agent.sh created and restore anything it replaced.
resiso_release "$SYSTEMD_FILE"
systemctl daemon-reload || true
resiso_release "$YAML_FILE"
resiso_release "$BIN_FILE"
resiso_release "$BIN_DIR"
resiso_finish
