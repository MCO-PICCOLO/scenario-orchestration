# KUKSA Bridge - Resource Isolation (Single Node)

KUKSA databroker client running on a single node.
Polls a button signal from the local databroker and toggles a CPU workload
(`stress-ng`) on the host via shell scripts.

## Overview

This bridge polls the `Vehicle.Cabin.ResourceIsolation.ButtonPressed` signal from the local KUKSA databroker.
When a button press is detected, it toggles the `stress-ng` workload to simulate CPU load.

```
┌─────────────────┐     ┌─────────────────┐
│  KUKSA Broker   │────▶│  KUKSA Bridge   │
│  (Port 55556)   │     │  (this)         │
└─────────────────┘     └────────┬────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │   stress-ng     │
                        │   (CPU Load)    │
                        └─────────────────┘
```

All components run on the same host, so the bridge connects to the databroker over `127.0.0.1`.

## Configuration

Container settings are managed via the `.env` file.

```bash
# KUKSA Databroker Configuration
KUKSA_HOST=127.0.0.1
KUKSA_PORT=55556
KUKSA_PROTOCOL=grpc

# Shell scripts for toggle mode
TRIGGER_ON_SCRIPT=/app/script/trigger-on.sh
TRIGGER_OFF_SCRIPT=/app/script/trigger-off.sh
```

## Deployment

In the single-node flow you do not run this container by hand:

- The image `localhost/resiso-kuksa-bridge:latest` is built by
  [../test_script/preflight/prepare.sh](../test_script/preflight/prepare.sh).
- pullpiri launches/stops it via
  [../serial-bridge/pullpiri-yaml/container-launch.yaml](../serial-bridge/pullpiri-yaml/container-launch.yaml) /
  [container-stop.yaml](../serial-bridge/pullpiri-yaml/container-stop.yaml).

### Build manually (optional)

```bash
cd resource-isolation/single_node/kuksa-bridge
sudo podman build -t localhost/resiso-kuksa-bridge:latest .
```

The Dockerfile COPYs `bridge.py`, `.env` and `script/` into the image, so no
volume mounts are required to run it.

### Logs

```bash
sudo podman logs resiso-kuksa-bridge -f      # follow
sudo podman logs resiso-kuksa-bridge --tail=20
```

## Behavior

1. **KUKSA Databroker Connection**
   - Host: `127.0.0.1` (local databroker)
   - Port: `55556` (resource-isolation databroker), gRPC
   - Signal (polled): `Vehicle.Cabin.ResourceIsolation.ButtonPressed`

2. **Button Event Handling** (toggle)
   - Button press (toggle ON) → execute `trigger-on.sh`
   - Next press (toggle OFF) → execute `trigger-off.sh`

3. **Workload Control**
   - ON: `setsid stress-ng --cpu 0 --cpu-method all --timeout 0` (runs on the host)
   - OFF: terminates the stress-ng process group / all `stress-ng` processes

## Shell Scripts

### trigger-on.sh
- Kills any existing stress-ng processes
- Starts stress-ng in the background
- Uses all CPU cores with various stress methods

### trigger-off.sh
- Terminates all stress-ng processes
- Verifies clean termination

## Notes

- The bridge runs in toggle mode: each button press alternates ON/OFF.
- `stress-ng` runs on the host, detached from the bridge process (`setsid`).
- `.env` values are baked in at build time; rebuild the image to change them.
- For the full single-node demo procedure, see
  [../test_script/README.md](../test_script/README.md).

