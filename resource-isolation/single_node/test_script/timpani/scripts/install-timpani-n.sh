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
# Single-node timpani-n runtime install.
# Installs the prebuilt timpani-n native package (.deb/.rpm) from ARTIFACTS_DIR.
# The package ships /usr/bin/timpani-n and a `timpani-n` systemd service that
# reads its arguments from /etc/default/timpani-n (TIMPANI_N_ARGS). This script
# writes those args (node name, node IP) and starts the service.
#
# Required via environment:
#   NODE_IP     host address timpani-n connects to (positional arg)
# Overridable via environment:
#   NODE_NAME          node id passed with -n (default: hostname)
#   TIMPANI_N_ARGS     full arg string; overrides the composed default if set
#   TIMPANI_N_VERSION  package version to install (default 2.0.0)
#   ARTIFACTS_DIR      dir holding the prebuilt packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NODE_NAME="${NODE_NAME:-$(hostname)}"
TIMPANI_N_VERSION="${TIMPANI_N_VERSION:-2.0.0}"
# Local artifacts dir holding the prebuilt packages (resource-isolation/artifacts).
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${SCRIPT_DIR}/../../../../artifacts}"

log() { echo "[install-timpani-n] $*"; }
die() { echo "[install-timpani-n] ERROR: $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Please run as root: sudo $0"
[[ -n "${NODE_IP:-}" ]] || die "NODE_IP must be set (host address for timpani-n)"

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

# ---------------------------------------------------------------------------
# install_timpani_n — install the native package from ARTIFACTS_DIR.
# The package marks system dirs (/etc/default, /usr/lib/systemd*) as its own,
# which conflicts with base packages; the --force-overwrite/--replacefiles
# flags ignore those file/dir ownership conflicts.
# ---------------------------------------------------------------------------
install_timpani_n() {
    local pkg
    case "${OS}" in
        ubuntu|debian)
            pkg="${ARTIFACTS_DIR}/timpani-n-${TIMPANI_N_VERSION}-Linux.deb"
            [[ -f "${pkg}" ]] || die "Package not found: ${pkg}"
            log "Installing ${pkg}..."
            dpkg -i --force-overwrite "${pkg}" || apt-get install -f -y
            ;;
        centos|rhel|fedora)
            pkg="${ARTIFACTS_DIR}/timpani-n-${TIMPANI_N_VERSION}-Linux.rpm"
            [[ -f "${pkg}" ]] || die "Package not found: ${pkg}"
            log "Installing ${pkg}..."
            rpm -Uvh --replacefiles --replacepkgs "${pkg}" \
                || die "Failed to install ${pkg}"
            ;;
        *)
            die "Unsupported OS for timpani-n package install: ${OS}"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# configure_and_start — write runtime args and (re)start the systemd service.
# Matches the previous manual launch: -n <node> -s -l 4 -P 80 <host ip>
# ---------------------------------------------------------------------------
configure_and_start() {
    local args="${TIMPANI_N_ARGS:--n ${NODE_NAME} -s -l 4 -P 80 ${NODE_IP}}"
    log "Writing /etc/default/timpani-n (TIMPANI_N_ARGS=\"${args}\")"
    mkdir -p /etc/default
    printf 'TIMPANI_N_ARGS="%s"\n' "${args}" > /etc/default/timpani-n

    # timpani-n does not exit on SIGTERM, so the packaged unit would hang for the
    # default 90s stop timeout before systemd SIGKILLs it. A drop-in kills it
    # immediately on stop/restart. (Kept in /etc so a package reinstall of the
    # unit does not clobber it.)
    log "Writing timpani-n stop-timeout drop-in..."
    mkdir -p /etc/systemd/system/timpani-n.service.d
    cat > /etc/systemd/system/timpani-n.service.d/override.conf <<'EOF'
[Service]
KillSignal=SIGKILL
TimeoutStopSec=5s
EOF

    log "Enabling and starting timpani-n service..."
    systemctl daemon-reload
    systemctl enable timpani-n.service
    systemctl restart timpani-n.service

    sleep 2
    if systemctl is-active --quiet timpani-n; then
        log "timpani-n service is running."
    else
        journalctl -u timpani-n -n 40 --no-pager || true
        die "timpani-n service failed to start. Check: journalctl -u timpani-n"
    fi
}

install_timpani_n
configure_and_start

log "Done. Status: systemctl status timpani-n | Logs: journalctl -u timpani-n -f"
