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
# Master preflight: build images, compile/upload Arduino sketches
# Run directly on the master node.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"
# shellcheck source=../lib/utils.sh
source "${SCRIPT_DIR}/../lib/utils.sh"

main() {
  require_cmd docker
  require_cmd arduino-cli

  info "=== Master preflight ==="
  info "NUC_MASTER_DIR=$MASTER_NUC_MASTER_DIR"
  [[ -d "$MASTER_NUC_MASTER_DIR" ]] || { err "missing dir: $MASTER_NUC_MASTER_DIR"; exit 1; }

  if [[ -f "$MASTER_ARDUINO_DIR/99-arduino.rules" ]]; then
    info "Apply udev rules for stable Arduino device names"
    sudo cp "$MASTER_ARDUINO_DIR/99-arduino.rules" /etc/udev/rules.d/99-arduino.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    sleep 1
    ls -al /dev/arduino_* 2>/dev/null || warn "/dev/arduino_* not found yet"
  else
    warn "99-arduino.rules not found: $MASTER_ARDUINO_DIR/99-arduino.rules"
  fi

  info "Compile/upload Arduino sketches"
  ensure_arduino_lib "Adafruit NeoPixel"
  cd "$MASTER_ARDUINO_DIR"
  bash ./compile.sh
  bash ./install.sh

  info "Build serial bridge image (docker compose)"
  cd "$MASTER_SERIAL_BRIDGE_DIR"
  sudo docker compose build

  info "Pull databroker image"
  sudo docker pull quay.io/eclipse-kuksa/kuksa-databroker:0.6.0

  info "=== Master preflight done ==="
}

main "$@"
