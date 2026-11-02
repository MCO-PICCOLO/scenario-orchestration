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

# =============================================================
# lib/utils.sh  ─  Shared shell functions (single-node, local only)
# Source after config.env.
# =============================================================

# ── Log helpers ──────────────────────────────────────────────
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERROR] $*" >&2; }

# ── Command existence check ───────────────────────────────────
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Required command not found: $1"
    exit 1
  }
}

# ── Node name validation ──────────────────────────────────────
# The name ends up in YAML, string replacement and shell arguments, so
# only a conservative character set is accepted.
validate_node_name() {
  local label="$1" value="$2"
  [[ "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    err "${label} is empty or invalid ('${value}'). Allowed: A-Z a-z 0-9 . _ - (must start with a letter or digit)."
    exit 1
  }
}

# ── Local node IP detection ───────────────────────────────────
# Prints an explicit NODE_IP if set, otherwise the first non-loopback
# IPv4 address of this machine.
detect_node_ip() {
  if [[ -n "${NODE_IP:-}" ]]; then
    echo "${NODE_IP}"
    return
  fi
  hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^127\.' | head -n1
}

# ── Local sudo execution ──────────────────────────────────────
# Credentials are never placed on a command line: SUDO_PASS (if set) is fed to
# `sudo -S` through stdin, so it does not show up in `ps` or /proc/*/cmdline.
# With no SUDO_PASS, sudo uses its own prompt or passwordless configuration.
run_sudo() {
  if [[ -n "${SUDO_PASS:-}" ]]; then
    printf '%s\n' "${SUDO_PASS}" | sudo -S -p '' "$@"
  else
    sudo "$@"
  fi
}

# Validates sudo access once, up front, so a wrong or missing password fails
# immediately instead of in the middle of the flow. Without SUDO_PASS this
# prompts interactively (or succeeds silently for passwordless sudo).
sudo_init() {
  require_cmd sudo
  if [[ -n "${SUDO_PASS:-}" ]]; then
    printf '%s\n' "${SUDO_PASS}" | sudo -S -p '' -v 2>/dev/null \
      || { err "sudo authentication failed: check SUDO_PASS."; exit 1; }
  else
    sudo -v || { err "sudo authentication failed."; exit 1; }
  fi
}

# ── Best-effort step runner ───────────────────────────────────
# run_step <description> <command...>
# Runs the command; on failure prints a warning and records it in
# TEARDOWN_FAILURES so the caller can finish the remaining steps and report.
TEARDOWN_FAILURES=0
run_step() {
  local desc="$1"; shift
  if ! "$@"; then
    warn "${desc} failed (continuing with the remaining steps)"
    TEARDOWN_FAILURES=$(( TEARDOWN_FAILURES + 1 ))
  fi
}

# ── Arduino library check/install ────────────────────────────
ensure_arduino_lib() {
  local lib="${1:-Adafruit NeoPixel}"
  if arduino-cli lib list | grep -qF "$lib"; then
    info "Arduino lib already installed: $lib"
  else
    info "Installing Arduino lib: $lib"
    arduino-cli lib install "$lib"
  fi
}

# ── Wait for a container log pattern ──────────────────────────
# Watches a docker container's logs for a regex until it matches or times out.
# Args: <container name> <log regex> <timeout sec> [since (UTC, RFC3339)]
# `since` should be the start of the run (RUN_START_TS) so a launch request sent
# before this watch begins is not missed; it defaults to the time of this call.
# Returns: 0 on match, 1 if no container found, 124 on timeout.
wait_for_container_log() {
  local name="$1" regex="$2" timeout="$3" since="${4:-}"
  local c="${name}"
  if ! docker ps --format '{{.Names}}' | grep -Fx "${c}" >/dev/null 2>&1; then
    c="$(docker ps --format '{{.Names}}' | grep -m1 -E 'resiso-serial-bridge|databroker|broker' || true)"
  fi
  [[ -n "${c}" ]] || return 1

  info "watching container: ${c}"
  local ts end
  ts="${since:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  end=$(( $(date +%s) + timeout ))
  while [[ $(date +%s) -lt ${end} ]]; do
    if docker logs --since "${ts}" "${c}" 2>&1 | grep -m1 -E "${regex}" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 124
}
