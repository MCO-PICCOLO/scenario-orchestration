# Resource Isolation Demo

A demo that shows the timing-accuracy difference between a **TIMPANI-scheduled
workload** and a **normal periodic (sleep) workload** under CPU load, using
physical LEDs.

- **Normal workload**: keeps a 500ms period with `sleep(0.5s)` -> the period
  drifts once CPU load rises
- **TIMPANI workload**: activated on a 500ms period by the TIMPANI scheduler ->
  keeps an accurate period regardless of load

> See [Introduction.md](./Introduction.md) for background and design intent.

## How It Works

```
[Joystick button]  ->  serial-bridge  ->  KUKSA Databroker  ->  kuksa-bridge  ->  stress-ng ON/OFF (toggle CPU load)
[Rotary turn]      ->  serial-bridge  ->  Pullpiri          ->  workload containers Launch / Terminate
[TIMPANI signal]   ->  led-timpani-controller  ->  LED (accurate 500ms)
[Normal sleep]     ->  led-normal-controller   ->  LED (delayed under load)
```

There is a single key signal: `Vehicle.Cabin.ResourceIsolation.ButtonPressed`
(written by serial-bridge, read by kuksa-bridge).

## Layout

Two deployment modes are provided.

| Mode | Description | Location |
|------|-------------|----------|
| **single_node** | Everything runs on one PC (no SSH) | [single_node/](./single_node) |
| **multi_node** | Split across master / guest nodes | [multi_node/](./multi_node) |

Each mode shares the same sub-folder structure. The multi_node structure is
split into `nuc_master` and `nuc_guest`, each containing the sub-folders that
belong to that node. The Arduino sketches used by both modes are kept once in
[common/arduino](./common/arduino).

```
<mode>/
├── arduino/           # compile / install scripts and udev rules
├── serial-bridge/     # serial <-> KUKSA / Pullpiri bridge, VSS spec, workload YAML
├── kuksa-bridge/      # subscribes to the button signal -> controls stress-ng
├── led-*-controller/  # LED control containers (timpani / normal)
├── monitoring/        # Prometheus + Grafana
└── test_script/       # run automation scripts *
```

## Usage

Both start and stop go through `test_script`. Configuration is done by editing
only the **USER SETTINGS** section at the top of `test_script/config.env`.

### Single Node

Runs on one PC. See
[single_node/test_script/README.md](./single_node/test_script/README.md) for details.

```bash
cd single_node/test_script

./preflight/prepare.sh              # 1) one-time: build images + upload Arduino
./run_resource_isolation_flow.sh    # 2) start
./stop_resource_isolation_flow.sh   # 3) stop
```

### Multi Node

Run preflight on each node first, then run the flow from the master PC. See
[multi_node/test_script/README.md](./multi_node/test_script/README.md) for details.

```bash
# one-time on each node
./preflight/prepare_master.sh       # on the master node
./preflight/prepare_guest.sh        # on the guest node

# on the MASTER PC
cd multi_node/test_script
./run_resource_isolation_flow.sh    # start (orchestrates both nodes over SSH)
./stop_resource_isolation_flow.sh   # stop
```

## Testing

After running `run_resource_isolation_flow.sh`:

1. **Turn the rotary to 120 and press its button** -> workload containers are launched.
   (once the flow detects the databroker log, it proceeds automatically)
2. **Press the joystick button** -> toggles the CPU load (stress-ng).
3. **Grafana dashboard** (`http://<node-ip>:3000`) -> compare the two LED periods.
   - TIMPANI LED: stays ~500ms regardless of load
   - Normal LED: period grows beyond 500ms under load

## Notes

- Detailed values such as paths and image versions can be overridden in the
  **ADVANCED SETTINGS** section of `config.env`.
