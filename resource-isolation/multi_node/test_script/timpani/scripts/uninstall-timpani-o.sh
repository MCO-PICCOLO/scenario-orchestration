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
# timpani-o runtime uninstall.
# Stops and removes the manually-run container (image kept).
# The container is created by install-timpani-o.sh as root, so this must run as
# root too — otherwise `podman rm` targets the rootless store and finds nothing.

log() { echo "[uninstall-timpani] $*"; }
die() { echo "[uninstall-timpani] ERROR: $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Please run as root: sudo $0"

log "Removing container 'timpani-o'"
podman rm -f "timpani-o" 2>/dev/null || true

# Rendered node config created by install-timpani-o.sh (only this file/dir).
rm -f /run/resource-isolation/node_configurations.yaml
rmdir /run/resource-isolation 2>/dev/null || true

log "Done"