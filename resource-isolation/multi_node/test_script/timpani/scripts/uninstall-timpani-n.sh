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
# timpani-n runtime uninstall.
# Removes the native timpani-n package. The package's prerm hook stops and
# disables the systemd service, so no manual systemctl calls are needed here.

log() { echo "[uninstall-timpani-n] $*"; }
die() { echo "[uninstall-timpani-n] ERROR: $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Please run as root: sudo $0"

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        echo "${ID}"
    else
        die "Cannot detect OS — /etc/os-release not found."
    fi
}

OS=$(detect_os)
log "Detected OS: ${OS}"

# Belt-and-suspenders: ensure the service is stopped even if the package's
# prerm hook does not run for some reason.
systemctl stop timpani-n.service 2>/dev/null || true

log "Removing timpani-n package..."
case "${OS}" in
    ubuntu|debian)      dpkg -r timpani-n 2>/dev/null || apt-get remove -y timpani-n || true ;;
    centos|rhel|fedora) dnf remove -y timpani-n || true ;;
    *) die "Unsupported OS for timpani-n package removal: ${OS}" ;;
esac

systemctl daemon-reload 2>/dev/null || true
rm -f /etc/default/timpani-n
rm -rf /etc/systemd/system/timpani-n.service.d

log "Done."
