# Serial Bridge

Python serial bridge connecting Arduino devices to KUKSA Databroker and Pullpiri.

## Overview

This bridge reads input from Arduino devices and:
1. Sends the joystick button state to KUKSA Databroker and drives the LED Arduino (GREEN on press, OFF on release)
2. Sends YAML artifacts to Pullpiri based on the gear (rotary encoder) button input

## Build

Built via docker compose from the `serial-bridge` directory (image `serial-bridge:latest`):

```bash
cd ..
docker compose build
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABROKER_IP` | `resiso-databroker` | KUKSA Databroker hostname/IP |
| `DATABROKER_PORT` | `55555` | KUKSA Databroker port |
| `MASTER_IP` | `host.docker.internal` | Master's Pullpiri apiserver IP. The orchestrator passes `MASTER_NODE_IP`; falls back to the docker host gateway when unset |
| `NODE_NAME` | (none, required) | Guest Pullpiri node name. Replaces the `${NODE_NAME}` placeholder in the YAMLs under `pullpiri-yaml/` before they are sent. The orchestrator passes `GUEST_NODE_NAME` |

## Serial Ports

| Port | Device | Direction |
|------|--------|-----------|
| `/dev/arduino_joystick` | Joystick button | Input |
| `/dev/arduino_led` | NeoPixel LED | Output |
| `/dev/arduino_gear` | Rotary encoder button | Input |

## Data Flow

### Joystick → KUKSA + LED

1. Button press detected → Queue message `True`
2. Thread-DB sends to DataBroker: `Vehicle.Cabin.ResourceIsolation.ButtonPressed=True`
3. Main thread sends `GREEN\n` to LED Arduino
4. Button release → Same flow with `False` and `OFF\n`

### Gear → Pullpiri

The gear Arduino sends a single digit over serial when its button is pressed. The
`Thread-Gear` worker maps it to a workload YAML and posts it to Pullpiri. A repeated
value for the current mode is ignored.

| Gear input | Action | YAML sent |
|------------|--------|-----------|
| `1` | Launch the LED workloads (timpani + normal controllers) | `/yaml/container-launch.yaml` |
| `0` | Stop the LED workloads | `/yaml/container-stop.yaml` |

> The launch manifest starts two LED controllers: `led-timpani-controller` (a
> TIMPANI-scheduled real-time task) and `led-normal-controller` (a plain task).
> Under CPU stress the timpani LED keeps a steady blink period while the normal
> LED degrades — this is the resource-isolation effect the demo shows.

## YAML Artifacts

Located in `/yaml/` directory (mounted volume):
- `container-launch.yaml` - Sent when gear input is `1` (HIGH LOAD / LAUNCH)
- `container-stop.yaml` - Sent when gear input is `0` (LOW LOAD / STOP)