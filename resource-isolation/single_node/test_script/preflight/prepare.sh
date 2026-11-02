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
# Single-node preflight: build all images, compile/upload Arduino sketches.
# Run directly on this machine.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"
# shellcheck source=../lib/utils.sh
source "${SCRIPT_DIR}/../lib/utils.sh"

main() {
  require_cmd docker
  require_cmd podman
  require_cmd arduino-cli

  info "=== Single-node preflight ==="
  info "BASE_DIR=${BASE_DIR}"
  [[ -d "${BASE_DIR}" ]] || { err "missing dir: ${BASE_DIR}"; exit 1; }

  # ── Arduino udev rules ────────────────────────────────────────────
  if [[ -f "${ARDUINO_DIR}/99-arduino-led.rules" ]]; then
    info "Apply udev rules for stable Arduino device names"
    run_sudo cp "${ARDUINO_DIR}/99-arduino-led.rules" /etc/udev/rules.d/99-arduino-led.rules
    run_sudo udevadm control --reload-rules
    run_sudo udevadm trigger
    sleep 1
    ls -al /dev/arduino_* 2>/dev/null || warn "/dev/arduino_* not found yet"
  else
    warn "99-arduino-led.rules not found: ${ARDUINO_DIR}/99-arduino-led.rules"
  fi

  # ── Arduino sketches ──────────────────────────────────────────────
  ensure_arduino_lib "Adafruit NeoPixel"
  info "Compile/upload Arduino sketches"
  ( cd "${ARDUINO_DIR}" && bash ./compile.sh && bash ./install.sh )

  # ── Container images ──────────────────────────────────────────────
  info "Build serial bridge image (docker compose)"
  ( cd "${SERIAL_BRIDGE_DIR}" && run_sudo docker compose build )

  info "Pull databroker image"
  run_sudo docker pull quay.io/eclipse-kuksa/kuksa-databroker:0.6.0

  info "Build LED controller images"
  ( cd "${BASE_DIR}/led-timpani-controller" && run_sudo podman build -t localhost/led-timpani-controller:latest . )
  ( cd "${BASE_DIR}/led-normal-controller" && run_sudo podman build -t localhost/led-normal-controller:latest . )

  info "Build kuksa-bridge image"
  # The kuksa-bridge container runs on the podman bridge network and must reach the
  # databroker via the host's LAN IP (127.0.0.1 would be the container itself).
  # Auto-fill KUKSA_HOST in the .env with this host's detected IP before building,
  # so the image is baked with the correct address (no hardcoding in .env).
  local kb_env="${BASE_DIR}/kuksa-bridge/.env"
  local host_ip
  host_ip="$(detect_node_ip)"
  [[ -n "${host_ip}" ]] || { err "Could not detect host IP for KUKSA_HOST"; exit 1; }
  info "Set KUKSA_HOST=${host_ip} in ${kb_env}"
  if grep -q '^KUKSA_HOST=' "${kb_env}"; then
    sed -i "s/^KUKSA_HOST=.*/KUKSA_HOST=${host_ip}/" "${kb_env}"
  else
    printf 'KUKSA_HOST=%s\n' "${host_ip}" >> "${kb_env}"
  fi
  ( cd "${BASE_DIR}/kuksa-bridge" && run_sudo podman build -t localhost/resiso-kuksa-bridge:latest . )

  info "Ensure stress-ng image"
  if ! run_sudo podman image exists localhost/stress-ng:latest; then
    run_sudo podman build -t localhost/stress-ng:latest - <<'EOF'
FROM alpine:latest
RUN apk add --no-cache stress-ng
ENTRYPOINT ["stress-ng"]
EOF
  fi

  [[ -f "${MONITORING_DIR}/docker-compose.yml" ]] || warn "monitoring compose file not found"

  info "=== Single-node preflight done ==="
}

main "$@"
