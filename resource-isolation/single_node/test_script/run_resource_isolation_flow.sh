#!/usr/bin/env bash
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
# Single-node orchestrator: start flow
# Everything runs locally on this machine. Env overrides: see config.env

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"
# shellcheck source=./lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

main() {
  require_cmd docker
  sudo_init

  NODE_IP="$(detect_node_ip)"
  [[ -n "${NODE_IP}" ]] || { err "Could not determine local node IP."; exit 1; }
  validate_node_name NODE_NAME "${NODE_NAME}"
  info "Node: name='${NODE_NAME}' ip='${NODE_IP}'"

  # Taken before anything starts: the Step 6 log watch looks for log lines from
  # this moment on, so a launch request sent during Steps 1-5 is still seen.
  RUN_START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  info "Step 1) docker compose up -d"
  # apiserver binds to NODE_IP (settings.yaml host.ip); pass it so the serial-bridge
  # reaches the apiserver on the same address instead of the docker host gateway.
  # NODE_NAME is rendered into the workload YAMLs by the serial-bridge.
  ( cd "${SERIAL_BRIDGE_DIR}" && MASTER_IP="${NODE_IP}" NODE_NAME="${NODE_NAME}" docker compose up -d )

  info "Step 2) pullpiri runtime install"
  run_sudo bash "${TEST_SCRIPT_DIR}/pullpiri/scripts/install-pullpiri.sh" "${NODE_IP}" "${NODE_NAME}"

  info "Step 3) restart nodeagent.service"
  run_sudo systemctl restart nodeagent.service

  info "Step 4) start monitoring script"
  ( cd "${MONITORING_DIR}" && ./start.sh )

  info "Step 5) start timpani-o (container)"
  # Load the timpani-o image and run it as a container (see install-timpani-o.sh).
  run_sudo env NODE_NAME="${NODE_NAME}" bash "${TEST_SCRIPT_DIR}/timpani/scripts/install-timpani-o.sh"
  info "Step 5) timpani-o container started (logs: sudo podman logs -f timpani-o)"

  echo
  warn "Step 6) After operating the Arduino, proceed with the YAML transmission."
  warn "Watching container '${DATABROKER_CONTAINER}' log for up to ${WAIT_LOG_TIMEOUT_SEC}s:"
  echo "       (regex: ${DATABROKER_LOG_REGEX})"

  set +e
  wait_for_container_log "${DATABROKER_CONTAINER}" "${DATABROKER_LOG_REGEX}" "${WAIT_LOG_TIMEOUT_SEC}" "${RUN_START_TS}"
  step6_rc=$?
  set -e

  case ${step6_rc} in
    0) info "Step 6 pattern matched" ;;
    1) warn "data broker container not found" ;;
    *) warn "Step 6 log watch timed out (code: ${step6_rc})" ;;
  esac

  if [[ ${step6_rc} -ne 0 ]]; then
    read -r -p "Continue with Step 7? [y/N] " ans
    if [[ ! "${ans}" =~ ^[Yy]$ ]]; then
      err "Aborted by user."
      exit 1
    fi
  fi

  info "Step 7) install & start timpani-n (systemd service)"
  run_sudo env NODE_NAME="${NODE_NAME}" NODE_IP="${NODE_IP}" \
    bash "${TEST_SCRIPT_DIR}/timpani/scripts/install-timpani-n.sh"
  info "Step 7) timpani-n service started (logs: sudo journalctl -u timpani-n -f)"

  info "Done."
}

main "$@"
