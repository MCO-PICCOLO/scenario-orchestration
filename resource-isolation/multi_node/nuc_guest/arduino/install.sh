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

FQBN="arduino:renesas_uno:unor4wifi"
# Sketches are shared between single_node and multi_node.
SKETCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../common/arduino" && pwd)"

resolve_port() {
	local symlink="$1"
	if [[ ! -e "$symlink" ]]; then
		echo "[ERROR] Missing device: $symlink" >&2
		exit 1
	fi
	readlink -f "$symlink"
}

TIMPANI_PORT="$(resolve_port /dev/arduino_led_timpani)"
NORMAL_PORT="$(resolve_port /dev/arduino_led_normal)"

echo "Uploading ardn_led_timpani to ${TIMPANI_PORT} (/dev/arduino_led_timpani)..."
arduino-cli upload -p "${TIMPANI_PORT}" --fqbn "${FQBN}" "${SKETCH_DIR}/ardn_led_timpani"

echo "Uploading ardn_led_normal to ${NORMAL_PORT} (/dev/arduino_led_normal)..."
arduino-cli upload -p "${NORMAL_PORT}" --fqbn "${FQBN}" "${SKETCH_DIR}/ardn_led_normal"

echo "Upload complete!"
