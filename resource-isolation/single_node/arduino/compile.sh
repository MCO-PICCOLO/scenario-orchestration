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

# Compile LED Arduino sketches for the single node
set -euo pipefail

# Sketches are shared between single_node and multi_node.
SKETCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../common/arduino" && pwd)"
FQBN="arduino:renesas_uno:unor4wifi"

for sketch in ardn_stick ardn_led ardn_gear ardn_led_timpani ardn_led_normal; do
	arduino-cli compile --fqbn "${FQBN}" "${SKETCH_DIR}/${sketch}"
done
