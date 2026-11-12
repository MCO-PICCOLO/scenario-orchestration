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
# Multi-node orchestrator: stop/teardown flow
# Env overrides: see config.env

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"
# shellcheck source=./lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

main() {
  require_cmd ssh
  require_cmd timeout
  resolve_auth_mode
  info "Auth mode: USE_SSHPASS=$USE_SSHPASS"

  # Every step is best-effort: a failure is reported but does not stop the
  # remaining cleanup. The script exits non-zero at the end if any step failed.
  info "Step 1) master: docker compose down"
  run_step "master docker compose down" on_master "cd '$MASTER_SERIAL_BRIDGE_DIR'; docker compose down"

  info "Step 2) guest: monitoring stop.sh"
  run_step "guest monitoring stop" on_guest "cd '$GUEST_MONITORING_DIR'; ./stop.sh"

  info "Step 3) stop timpani (guest: timpani-n package, master: timpani-o container)"
  run_step "guest uninstall-timpani-n"  on_guest_sudo  "bash '$GUEST_TEST_SCRIPT_DIR/timpani/scripts/uninstall-timpani-n.sh'"
  run_step "master uninstall-timpani-o" on_master_sudo "bash '$MASTER_TEST_SCRIPT_DIR/timpani/scripts/uninstall-timpani-o.sh'"

  info "Removing guest-to-TIMPANI-O forwarding rule"
  # Use the same node addresses as run; stop before changing config.env.
  local timpani_forward_rule
  timpani_forward_rule="-s '${GUEST_NODE_IP}/32' -p tcp --dport 7777 -m conntrack --ctstate NEW,ESTABLISHED \
    --ctorigdst '${MASTER_NODE_IP}' --ctorigdstport 7777 -m conntrack --ctstate DNAT -m comment --comment timpani-managed -j ACCEPT"

  # Also remove the legacy rule that had no ACCEPT target.
  local rule
  for rule in "${timpani_forward_rule}" "${timpani_forward_rule% -j ACCEPT}"; do
    on_master_sudo "
      if check_output=\$(LC_ALL=C iptables -w 5 -C FORWARD ${rule} 2>&1); then
        iptables -w 5 -D FORWARD ${rule}
      else
        rc=\$?
        if [ \"\$rc\" -ne 1 ] || [[ -n \"\$check_output\" && \"\$check_output\" != 'iptables: Bad rule (does a matching rule exist in that chain?).' ]]; then
          printf '%s\n' \"\$check_output\" >&2
          echo '[ERROR] Failed to check TIMPANI forwarding rule' >&2
          exit \"\$rc\"
        fi
        echo '[INFO] TIMPANI forwarding rule already absent'
      fi
    "
  done

  info "Step 4) guest: remove scenario workload containers (only the scenario's own images)"
  run_step "guest uninstall-workloads" on_guest_sudo "bash '$GUEST_TEST_SCRIPT_DIR/pullpiri/scripts/uninstall-workloads.sh'"

  info "Step 5) pullpiri runtime uninstall (guest nodeagent, then master)"
  # Run from here over the guest's own SSH connection, so no guest credentials
  # are ever handed to the master.
  run_step "guest uninstall-agent" on_guest_sudo "bash '$GUEST_TEST_SCRIPT_DIR/pullpiri/scripts/uninstall-agent.sh'"
  run_step "master uninstall-pullpiri" on_master_sudo "bash '$MASTER_TEST_SCRIPT_DIR/pullpiri/scripts/uninstall-pullpiri.sh'"

  if [[ ${TEARDOWN_FAILURES} -gt 0 ]]; then
    err "Teardown finished with ${TEARDOWN_FAILURES} failed step(s)."
    exit 1
  fi
  info "Teardown done."
}

main "$@"
