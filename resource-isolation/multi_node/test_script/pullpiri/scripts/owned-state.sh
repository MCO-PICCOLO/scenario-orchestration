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
# owned-state.sh  -  Ownership tracking for the files and directories that
# the resource-isolation install scripts create or replace.
#
# The uninstall scripts use it to remove only what the flow created and to
# restore anything that existed before the flow ran, instead of deleting
# whole directories such as /etc/pullpiri.
#
# Source this file from install/uninstall scripts running as root.
#
# State file entries (one per line):
#   created:<path>  the path did not exist before the flow created it
#   backup:<path>   the path existed before; the original was copied to
#                   <path>.resource-isolation.bak and is restored on uninstall
# An entry is written only the first time a path is claimed, so running an
# install again never overwrites the record of the original state.
# =============================================================

RESISO_ETC_DIR="/etc/pullpiri"
RESISO_STATE_FILE="${RESISO_ETC_DIR}/.resource-isolation-state"

# Paths used by the resource-isolation flow.
# The RocksDB directory is dedicated to this demo, so a pre-existing
# /etc/pullpiri/pullpiri_shared_rocksdb (and the data in it) is never touched.
RESISO_ROCKSDB_DIR="${RESISO_ETC_DIR}/resource_isolation_rocksdb"
RESISO_SETTINGS_FILE="${RESISO_ETC_DIR}/settings.yaml"
RESISO_LOG_DIR="/run/pullpirilog"

_resiso_log() { echo "[owned-state] $*"; }

# Create /etc/pullpiri (and the state file) if needed, recording that this flow
# created the directory.
resiso_init() {
  if [[ ! -d "${RESISO_ETC_DIR}" ]]; then
    mkdir -p "${RESISO_ETC_DIR}"
    echo "created:${RESISO_ETC_DIR}" >> "${RESISO_STATE_FILE}"
  fi
}

# True if the path already has an entry in the state file.
_resiso_recorded() {
  [[ -f "${RESISO_STATE_FILE}" ]] \
    && grep -qFx -e "created:$1" -e "backup:$1" "${RESISO_STATE_FILE}"
}

# True if the flow created the path (as opposed to replacing an existing one).
resiso_was_created() {
  [[ -f "${RESISO_STATE_FILE}" ]] && grep -qFx "created:$1" "${RESISO_STATE_FILE}"
}

_resiso_forget() {
  { grep -vFx -- "$1" "${RESISO_STATE_FILE}" || true; } > "${RESISO_STATE_FILE}.tmp"
  mv -f -- "${RESISO_STATE_FILE}.tmp" "${RESISO_STATE_FILE}"
}

# resiso_claim_file <path>
# Call before writing or replacing a file. A pre-existing file is backed up.
resiso_claim_file() {
  local p="$1"
  resiso_init
  _resiso_recorded "$p" && return 0
  if [[ -e "$p" ]]; then
    cp -a -- "$p" "${p}.resource-isolation.bak"
    echo "backup:${p}" >> "${RESISO_STATE_FILE}"
    _resiso_log "backed up existing ${p}"
  else
    echo "created:${p}" >> "${RESISO_STATE_FILE}"
  fi
}

# resiso_claim_dir <path>
# Call before creating a directory. Only directories that did not exist are
# recorded, so a pre-existing directory is never removed.
resiso_claim_dir() {
  local p="$1"
  resiso_init
  _resiso_recorded "$p" && return 0
  if [[ ! -e "$p" ]]; then
    echo "created:${p}" >> "${RESISO_STATE_FILE}"
  fi
}

# resiso_release <path>
# Undo resiso_claim_file / resiso_claim_dir: restore the backup, or remove the
# path if the flow created it. Paths the flow never claimed are left alone.
resiso_release() {
  local p="$1"
  if [[ -f "${RESISO_STATE_FILE}" ]] && grep -qFx "backup:${p}" "${RESISO_STATE_FILE}"; then
    if [[ -e "${p}.resource-isolation.bak" ]]; then
      mv -f -- "${p}.resource-isolation.bak" "$p"
      _resiso_log "restored original ${p}"
    else
      _resiso_log "WARNING: backup of ${p} is missing, leaving ${p} in place"
    fi
    _resiso_forget "backup:${p}"
  elif resiso_was_created "$p"; then
    rm -rf -- "$p"
    _resiso_log "removed ${p}"
    _resiso_forget "created:${p}"
  else
    _resiso_log "leaving ${p} untouched (not created by this flow)"
  fi
}

# Remove the state file once every claimed path has been released, and remove
# /etc/pullpiri itself only if the flow created it and it is now empty.
resiso_finish() {
  [[ -f "${RESISO_STATE_FILE}" ]] || return 0
  local remaining
  remaining="$(grep -cvE "^(created:${RESISO_ETC_DIR})?\$" "${RESISO_STATE_FILE}" || true)"
  [[ "${remaining:-0}" -eq 0 ]] || return 0
  local created_dir=0
  grep -qFx "created:${RESISO_ETC_DIR}" "${RESISO_STATE_FILE}" && created_dir=1
  rm -f -- "${RESISO_STATE_FILE}"
  if [[ ${created_dir} -eq 1 ]]; then
    rmdir -- "${RESISO_ETC_DIR}" 2>/dev/null || true
  fi
}
