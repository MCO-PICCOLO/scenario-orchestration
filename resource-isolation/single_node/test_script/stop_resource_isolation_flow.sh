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
# Single-node orchestrator: stop/teardown flow
# Everything runs locally on this machine. Env overrides: see config.env

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"
# shellcheck source=./lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

main() {
  require_cmd docker
  sudo_init

  # Every step is best-effort: a failure is reported but does not stop the
  # remaining cleanup. The script exits non-zero at the end if any step failed.
  info "Step 1) docker compose down"
  run_step "docker compose down" bash -c 'cd "$1" && docker compose down' _ "${SERIAL_BRIDGE_DIR}"

  info "Step 2) monitoring stop.sh"
  run_step "monitoring stop.sh" bash -c 'cd "$1" && ./stop.sh' _ "${MONITORING_DIR}"

  info "Step 3) stop timpani-o container and uninstall timpani-n package"
  run_step "uninstall-timpani-o" run_sudo bash "${TEST_SCRIPT_DIR}/timpani/scripts/uninstall-timpani-o.sh"
  run_step "uninstall-timpani-n" run_sudo bash "${TEST_SCRIPT_DIR}/timpani/scripts/uninstall-timpani-n.sh"

  info "Step 4) remove scenario workload containers (only the scenario's own images)"
  run_step "uninstall-workloads" run_sudo bash "${TEST_SCRIPT_DIR}/pullpiri/scripts/uninstall-workloads.sh"

  info "Step 5) pullpiri runtime uninstall"
  run_step "uninstall-pullpiri" run_sudo bash "${TEST_SCRIPT_DIR}/pullpiri/scripts/uninstall-pullpiri.sh"

  if [[ ${TEARDOWN_FAILURES} -gt 0 ]]; then
    err "Teardown finished with ${TEARDOWN_FAILURES} failed step(s)."
    exit 1
  fi
  info "Teardown done."
}

main "$@"
