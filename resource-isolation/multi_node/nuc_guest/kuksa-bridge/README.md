# KUKSA Bridge - Resource Isolation Guest

KUKSA databroker client running on the NUC Guest.
Polls a button signal from the master's databroker and toggles a CPU workload
(`stress-ng`) on the guest host via shell scripts.

## Overview

This bridge polls `Vehicle.Cabin.ResourceIsolation.ButtonPressed` from the
master's KUKSA databroker. When a button press is detected, it toggles the
`stress-ng` workload to simulate CPU load.

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Master Node    │────▶│  KUKSA Broker   │────▶│  KUKSA Bridge   │
│  (Button Press) │     │  (Port 55556)   │     │  (this)         │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │   stress-ng     │
                                                │   (CPU Load)    │
                                                └─────────────────┘
```

## Configuration

Settings are read from the `.env` file (baked into the image at build time).

### .env File Format

```bash
# Master node's KUKSA databroker address.
# Leave KUKSA_HOST empty: preflight/prepare_guest.sh fills it with the master IP
# before building the image.
KUKSA_HOST=
KUKSA_PORT=55556
KUKSA_PROTOCOL=grpc

# Shell scripts for toggle mode
TRIGGER_ON_SCRIPT=/app/script/trigger-on.sh
TRIGGER_OFF_SCRIPT=/app/script/trigger-off.sh
```

## Deployment

In the multi-node demo you do not run this container by hand:

- The image `localhost/resiso-kuksa-bridge-guest:latest` is built by
  [../../test_script/preflight/prepare_guest.sh](../../test_script/preflight/prepare_guest.sh).
- pullpiri launches/stops it via the master's
  [container-launch.yaml](../../nuc_master/serial-bridge/pullpiri-yaml/container-launch.yaml) /
  [container-stop.yaml](../../nuc_master/serial-bridge/pullpiri-yaml/container-stop.yaml).

### Build manually (optional)

```bash
cd multi_node/nuc_guest/kuksa-bridge
sudo podman build -t localhost/resiso-kuksa-bridge-guest:latest .
```

The Dockerfile COPYs `bridge.py`, `.env` and `script/` into the image, so no
volume mounts are required to run it.

### Logs

```bash
sudo podman logs resiso-kuksa-bridge-guest -f      # follow
sudo podman logs resiso-kuksa-bridge-guest --tail=20
```

## Behavior

1. **KUKSA Databroker Connection**
   - Address: `KUKSA_HOST:55556` (master's resource-isolation databroker), gRPC
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
- Starts stress-ng in background using nohup+disown
- Uses all CPU cores with various stress methods

### trigger-off.sh
- Terminates all stress-ng processes
- Verifies clean termination

## Notes

- The bridge runs in toggle mode: each button press alternates ON/OFF.
- `stress-ng` runs on the host, detached from the bridge process (`setsid`).
- `.env` values are baked in at build time; rebuild the image to change them.
- For the full multi-node demo procedure, see
  [../../test_script/README.md](../../test_script/README.md).

