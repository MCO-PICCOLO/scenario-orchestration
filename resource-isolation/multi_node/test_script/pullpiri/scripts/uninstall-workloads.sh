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
# Removes the workload containers (and their pods) launched by the
# resource-isolation scenario, and nothing else. Must run as root, because
# Pullpiri's nodeagent creates them in the root podman store.
#
# Containers are matched by the images referenced in container-launch.yaml, so
# unrelated containers on the machine are left alone. Pullpiri's own pods
# (pullpiri-server / pullpiri-player) are removed by uninstall-pullpiri.sh and
# timpani-o by uninstall-timpani-o.sh.

log() { echo "[uninstall-workloads] $*"; }

[[ "${EUID}" -eq 0 ]] || { echo "[uninstall-workloads] ERROR: Please run as root: sudo $0" >&2; exit 1; }

IMAGES=(
  localhost/resiso-kuksa-bridge
  localhost/resiso-kuksa-bridge-guest
  localhost/led-timpani-controller
  localhost/led-normal-controller
)

for image in "${IMAGES[@]}"; do
  # Match any tag of the image.
  while IFS='|' read -r cid pod; do
    [[ -n "${cid}" ]] || continue
    if [[ -n "${pod}" ]]; then
      log "Removing pod ${pod} (container ${cid}, image ${image})"
      podman pod rm -f --ignore "${pod}" >/dev/null 2>&1 || true
    else
      log "Removing container ${cid} (image ${image})"
      podman rm -f --ignore "${cid}" >/dev/null 2>&1 || true
    fi
  done < <(podman ps -a --filter "ancestor=${image}" --format '{{.ID}}|{{.Pod}}' 2>/dev/null || true)
done

log "Done"
