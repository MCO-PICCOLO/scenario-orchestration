# Resource isolation Demo - NUC Master

This folder contains the NUC Master setup for the resource-isolation demonstration.

## Prerequisites

### Required Docker Images

The following Docker images must be built beforehand:

- `serial-bridge:latest` - Bridge connecting Arduino and KUKSA/Pullpiri
- `quay.io/eclipse-kuksa/kuksa-databroker:0.6.0` - KUKSA databroker (official image, published on host port `55556` → container `55555`)

### Build Docker Images

```bash
# Build Serial bridge image
cd nuc_master/serial-bridge
docker compose build
```

**Verify:**
```bash
docker images | grep serial-bridge
# serial-bridge   latest   ...
```

KUKSA databroker is automatically pulled from docker-compose.yml.

## Arduino Setup

See [arduino](./arduino/README.md) for details

**Summary:**
1. Fix device path with udev rules configuration
2. Compile and upload Arduino firmware
3. 3 boards: Joystick, LED, Gear

## Hardware Setup

- **3 Arduino UNO R4 WiFi boards:**
  - `ardn_stick` - Joystick with button (input)
  - `ardn_led` - NeoPixel LED strip (output)
  - `ardn_gear` - Rotary encoder with LED ring (input)

## Architecture

### Data Flow

1. **Joystick Button → LED + KUKSA**
   - `ardn_stick` detects button press/release
   - Sends signal to `bridge.py`
   - `bridge.py` forwards to:
     - Local `ardn_led` Arduino (GREEN on press, OFF on release)
     - KUKSA databroker (for Guest to receive)

2. **Rotary Encoder → Pullpiri**
   - `ardn_gear` detects rotation (CW/CCW)
   - `bridge.py` manages state-based filtering:
     - state=0 or -1: Only CW allowed → LAUNCH
     - state=1: Only CCW allowed → STOP
     - Invalid direction → RED LED
   - Sends YAML artifact to Pullpiri via HTTP API (`http://<MASTER_IP>:47099/api/artifact`).
     `MASTER_IP` is injected into the `resiso-serial-bridge` container by the
     orchestrator (`MASTER_NODE_IP` from `config.env`); it falls back to the docker host
     gateway when run manually.

## Components

### Arduino Programs

- `../../common/arduino/ardn_stick/ardn_stick.ino` - Joystick button detection
- `../../common/arduino/ardn_led/ardn_led.ino` - LED controller (GREEN/RED/OFF)
- `../../common/arduino/ardn_gear/ardn_gear.ino` - Rotary encoder with state machine

The sketches are shared with single_node and live in
[common/arduino](../../common/arduino).

### Python Bridge

- `serial-bridge/serial/bridge.py` - Main bridge connecting Arduino ↔ KUKSA ↔ Pullpiri
  - Main Thread: Joystick → DataBroker + LED Control
  - Thread-DB: DataBroker worker (queue consumer)
  - Thread-Gear: Gear → YAML artifacts (CW/CCW)

### Pullpiri YAML

YAML artifacts for Pullpiri container orchestration on the Guest node. These files
define container deployment specifications sent to Pullpiri via HTTP API when the
rotary encoder is rotated on the Master node. They are mounted into the
`resiso-serial-bridge` container (`./pullpiri-yaml:/yaml`) and posted by
`bridge.py`.

| File | Trigger | Action |
|------|---------|--------|
| `serial-bridge/pullpiri-yaml/container-launch.yaml` | Rotary CW | Launch LED controller containers |
| `serial-bridge/pullpiri-yaml/container-stop.yaml` | Rotary CCW | Stop LED controller containers |

**Schedule configuration (in `container-launch.yaml`):**

```yaml
spec:
  - name: led_timpani
    priority: 50
    policy: FIFO
    cpu_affinity: 4096      # CPU core 12 (0x1000)
    period: 500000          # 500ms in microseconds
    release_time: 0
    runtime: 10000          # 10ms
    deadline: 500000        # 500ms
    node_id: ${NODE_NAME}   # replaced by bridge.py with GUEST_NODE_NAME (config.env)
    max_dmiss: 3            # Max deadline misses before alert
```

## Running

### 1. Start Docker Compose

```bash
cd nuc_master/serial-bridge
docker compose up -d
```

**Verify:**
```bash
docker compose ps
# NAME                   IMAGE                                          STATUS
# resiso-databroker      quay.io/eclipse-kuksa/kuksa-databroker:0.6.0   Up
# resiso-serial-bridge   serial-bridge:latest                           Up
```

### 2. Stop

```bash
docker compose down
```
