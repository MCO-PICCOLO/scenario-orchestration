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
# lib/utils.sh  ─  Shared shell functions
# Source after config.env so SSH_CONNECT_TIMEOUT_SEC etc. are set.
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
# The name ends up in YAML, string replacement and shell arguments, so only a
# conservative character set is accepted.
validate_node_name() {
  local label="$1" value="$2"
  [[ "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    err "${label} is empty or invalid ('${value}'). Allowed: A-Z a-z 0-9 . _ - (must start with a letter or digit)."
    exit 1
  }
}

# ── SSH options (uses vars from config.env) ───────────────────
SSH_COMMON_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="${HOME}/.ssh/known_hosts"
  -o LogLevel=ERROR
  -o ConnectTimeout="${SSH_CONNECT_TIMEOUT_SEC:-10}"
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=2
)

# ── SSH auth mode resolution ──────────────────────────────────
resolve_auth_mode() {
  if [[ "${USE_SSHPASS:-auto}" == "auto" ]]; then
    if command -v sshpass >/dev/null 2>&1; then
      USE_SSHPASS="1"
    else
      USE_SSHPASS="0"
      warn "sshpass not installed: falling back to SSH key authentication mode."
    fi
  fi
  if [[ "${USE_SSHPASS}" == "1" ]]; then
    require_cmd sshpass
    if [[ -z "${MASTER_PASS:-}" || -z "${GUEST_PASS:-}" ]]; then
      err "Password authentication requires MASTER_PASS and GUEST_PASS to be set in config.env."
      exit 1
    fi
  fi
}

# ── Remote command execution ──────────────────────────────────
# run_remote <host> <port> <user> <pass> <remote_cmd> [stdin_data]
# The SSH password is handed to sshpass through the SSHPASS environment
# variable (`sshpass -e`), so it never appears in a process command line.
# stdin_data (optional) is written to the remote command's stdin on every
# attempt; without it the remote command gets an empty stdin.
run_remote() {
  local host="$1" port="$2" user="$3" pass="$4" remote_cmd="$5" stdin_data="${6-}"
  local rc=0
  local timeout_sec="${REMOTE_CMD_TIMEOUT_SEC:-180}"

  if [[ "${USE_SSHPASS}" == "1" ]]; then
    printf '%s' "$stdin_data" | SSHPASS="$pass" timeout "${timeout_sec}s" \
      sshpass -e ssh "${SSH_COMMON_OPTS[@]}" \
        -o NumberOfPasswordPrompts=1 -p "$port" "$user@$host" "$remote_cmd" \
      || rc=${PIPESTATUS[1]}
    return "$rc"
  fi

  printf '%s' "$stdin_data" | timeout "${timeout_sec}s" \
    ssh "${SSH_COMMON_OPTS[@]}" -o BatchMode=yes -p "$port" "$user@$host" "$remote_cmd" \
    || rc=${PIPESTATUS[1]}
  if [[ $rc -eq 255 && -n "$pass" ]] && command -v sshpass >/dev/null 2>&1; then
    warn "Key authentication failed ($user@$host:$port). Retrying with password authentication."
    rc=0
    printf '%s' "$stdin_data" | SSHPASS="$pass" timeout "${timeout_sec}s" \
      sshpass -e ssh "${SSH_COMMON_OPTS[@]}" \
        -o NumberOfPasswordPrompts=1 -p "$port" "$user@$host" "$remote_cmd" \
      || rc=${PIPESTATUS[1]}
  fi
  return "$rc"
}

# ── Remote sudo execution ─────────────────────────────────────
# The sudo password is sent over the SSH connection's stdin to `sudo -S`, so it
# is never part of the ssh arguments or the remote command line. With an empty
# sudo password, `sudo -n` is used (passwordless sudo) and nothing is sent.
run_remote_sudo() {
  local host="$1" port="$2" user="$3" pass="$4" sudo_pass="$5" remote_cmd="$6"
  local qcmd
  printf -v qcmd '%q' "$remote_cmd"
  if [[ -n "$sudo_pass" ]]; then
    run_remote "$host" "$port" "$user" "$pass" \
      "sudo -S -p '' bash -lc $qcmd" "${sudo_pass}"$'\n'
  else
    run_remote "$host" "$port" "$user" "$pass" \
      "sudo -n bash -lc $qcmd"
  fi
}

# Best-effort step runner: run_step <description> <command...>
# On failure prints a warning and counts it in TEARDOWN_FAILURES so the caller
# can finish the remaining steps and report at the end.
TEARDOWN_FAILURES=0
run_step() {
  local desc="$1"; shift
  if ! "$@"; then
    warn "${desc} failed (continuing with the remaining steps)"
    TEARDOWN_FAILURES=$(( TEARDOWN_FAILURES + 1 ))
  fi
}

# ── Per-node convenience wrappers ─────────────────────────────
# Use the node credentials from config.env and prepend `set -e` to every
# remote command, so callers only pass the command itself.
on_master()      { run_remote      "$MASTER_HOST" "$MASTER_PORT" "$MASTER_USER" "$MASTER_PASS"                    "set -e; $1"; }
on_master_sudo() { run_remote_sudo "$MASTER_HOST" "$MASTER_PORT" "$MASTER_USER" "$MASTER_PASS" "$MASTER_SUDO_PASS" "set -e; $1"; }
on_guest()       { run_remote      "$GUEST_HOST"  "$GUEST_PORT"  "$GUEST_USER"  "$GUEST_PASS"                     "set -e; $1"; }
on_guest_sudo()  { run_remote_sudo "$GUEST_HOST"  "$GUEST_PORT"  "$GUEST_USER"  "$GUEST_PASS"  "$GUEST_SUDO_PASS"  "set -e; $1"; }

# ── Node name resolution ──────────────────────────────────────
# An empty MASTER_NODE_NAME / GUEST_NODE_NAME falls back to that node's real
# hostname, then both are validated. Must run after resolve_auth_mode.
resolve_node_names() {
  [[ -n "${MASTER_NODE_NAME}" ]] || MASTER_NODE_NAME="$(on_master 'hostname')"
  [[ -n "${GUEST_NODE_NAME}" ]]  || GUEST_NODE_NAME="$(on_guest 'hostname')"
  validate_node_name MASTER_NODE_NAME "${MASTER_NODE_NAME}"
  validate_node_name GUEST_NODE_NAME "${GUEST_NODE_NAME}"
  [[ "${MASTER_NODE_NAME}" != "${GUEST_NODE_NAME}" ]] || {
    err "MASTER_NODE_NAME and GUEST_NODE_NAME are both '${MASTER_NODE_NAME}'; set distinct names in config.env."
    exit 1
  }
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

# ── Wait for a container log pattern on the master node ───────
# Watches DATABROKER_CONTAINER's logs on master for a regex until it matches or
# times out. Uses config.env vars: DATABROKER_CONTAINER, DATABROKER_LOG_REGEX,
# WAIT_LOG_TIMEOUT_SEC. Optional $1: UTC RFC3339 timestamp (master clock) to
# read logs from, normally RUN_START_TS, so a launch request sent before the
# watch begins is not missed. Defaults to the time of this call.
# Returns 0 on match, 124 on timeout / container not found.
# The remote SSH command timeout is bumped past the watch window so the watch is
# not killed early by REMOTE_CMD_TIMEOUT_SEC.
wait_for_master_container_log() {
  local since="${1:-}"
  local remote_cmd
  remote_cmd="$(cat <<REMOTE
c='${DATABROKER_CONTAINER}'
docker ps --format '{{.Names}}' | grep -Fx "\$c" >/dev/null 2>&1 || \
  c=\$(docker ps --format '{{.Names}}' | grep -m1 -E 'resiso-serial-bridge|databroker|broker' || true)
[[ -n "\$c" ]] || { echo '[WARN] data broker container not found'; exit 124; }
echo "[INFO] watching container: \$c"
ts='${since}'
[[ -n "\$ts" ]] || ts=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
end=\$((\$(date +%s) + ${WAIT_LOG_TIMEOUT_SEC}))
while [[ \$(date +%s) -lt \$end ]]; do
  docker logs --since "\$ts" "\$c" 2>&1 | grep -m1 -E '${DATABROKER_LOG_REGEX}' >/dev/null && exit 0
  sleep 2
done
exit 124
REMOTE
)"
  # Give the SSH command enough time to cover the whole watch window.
  local prev_timeout="${REMOTE_CMD_TIMEOUT_SEC:-180}" rc=0
  REMOTE_CMD_TIMEOUT_SEC=$(( WAIT_LOG_TIMEOUT_SEC + 30 ))
  on_master "${remote_cmd}" || rc=$?
  REMOTE_CMD_TIMEOUT_SEC="${prev_timeout}"
  return "${rc}"
}
