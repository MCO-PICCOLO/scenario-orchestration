# Single-node Resource Isolation Test

Scripts to start and stop the pullpiri + TIMPANI based resource-isolation
scenario on a single PC. pullpiri, nodeagent, TIMPANI, monitoring and the
containers all run locally (no SSH, no guest node).

## Layout

```
test_script/
├── config.env                        # settings (edit here only)
├── run_resource_isolation_flow.sh    # start
├── stop_resource_isolation_flow.sh   # stop
├── preflight/prepare.sh              # one-time: build images + upload Arduino
├── lib/utils.sh                      # shared functions
├── pullpiri/                         # pullpiri install/uninstall scripts, node config
└── timpani/                          # timpani-o/-n install/uninstall scripts, node config
```

## Prerequisites

- `docker`, `podman`, `arduino-cli` installed on this PC
- Local `sudo` access. By default sudo prompts once at the start of each flow. For
  non-interactive runs use passwordless sudo, or export `SUDO_PASS` (it is sent to
  sudo through stdin, never as a command-line argument)
- Arduino boards: the udev rules in
  [../arduino/99-arduino-led.rules](../arduino/99-arduino-led.rules) are
  hardware-specific and depend on each board's USB serial. Replace every
  `ATTRS{serial}` value with the serial of your own boards before running
  `prepare.sh` (find it with `udevadm info -a -n /dev/ttyACM0 | grep '{serial}' -m 1` or `arduino-cli board list`). This is a per-hardware configuration step and not a generic runtime setting.

## config.env

Edit only the **USER SETTINGS** section at the top. Defaults cover the rest.

| Variable | Description | Default |
|----------|-------------|---------|
| `NODE_NAME` | This machine's Pullpiri node name. Single source of truth: applied to the nodeagent, the workload YAMLs (`${NODE_NAME}` placeholder, rendered by the serial-bridge), the timpani node config and timpani-n. Allowed characters: `A-Z a-z 0-9 . _ -` | `hostname` |
| `NODE_IP` | Local IP used by pullpiri apiserver/nodeagent. Empty = auto-detect first non-loopback IP | (auto) |
| `BASE_DIR` | Path to the `single_node` directory | repo path |
| `SUDO_PASS` | Local sudo password. Empty = interactive prompt | (empty) |

> **kuksa-bridge address**: leave `KUKSA_HOST` in
> [../kuksa-bridge/.env](../kuksa-bridge/.env) empty. `prepare.sh` fills it with
> this host's IP right before building the image.

## Scripts

| Script | Role |
|--------|------|
| `preflight/prepare.sh` | Apply udev rules, compile/upload Arduino, build container images (one-time) |
| `run_resource_isolation_flow.sh` | Start serial-bridge -> install pullpiri -> restart nodeagent -> start monitoring -> run timpani-o container -> wait for databroker log -> install & start timpani-n package |
| `stop_resource_isolation_flow.sh` | compose down, stop monitoring, remove timpani-o container, uninstall timpani-n package, remove the scenario's workload containers, uninstall pullpiri |

## Test Procedure

### 1. Prepare (one-time)

```bash
cd single_node/test_script
./preflight/prepare.sh
```

Builds images and uploads the Arduino sketches (includes `KUKSA_HOST` auto-setup).

### 2. Start

```bash
./run_resource_isolation_flow.sh
```

The script runs automatically and waits for Arduino input at **Step 6**.

- **Turn the rotary to 120 and press its button** -> launch workload containers (serial-bridge POSTs the YAML to pullpiri)
- Once the script detects the databroker log (`api/artifact ... container-launch.yaml status=200`), it proceeds to **Step 7** (timpani-n) automatically

### 3. Observe

- **Press the joystick button** to toggle the CPU load (stress-ng)
- Compare the two LED periods in Grafana (`http://<node-ip>:3000`)
  - TIMPANI LED: stays ~500ms regardless of load
  - Normal LED: delayed beyond 500ms under load

### 4. Stop

```bash
./stop_resource_isolation_flow.sh
```

## Notes

- **Teardown only removes what the flow created.** `install-pullpiri.sh` and
  `install-agent.sh` record what they create in `/etc/pullpiri/.resource-isolation-state`
  and back up any pre-existing `settings.yaml`, `nodeagent.yaml`, `nodeagent.service`
  or `/opt/pullpiri/nodeagent` as `*.resource-isolation.bak`. The uninstall scripts
  remove only those items and restore the backups, so existing Pullpiri state is
  kept. The flow uses its own RocksDB directory
  (`/etc/pullpiri/resource_isolation_rocksdb`); an existing
  `pullpiri_shared_rocksdb` is never touched. Workload containers are removed by
  image (`uninstall-workloads.sh`), not with `podman rm --all`.
- Each teardown step is best-effort: a failed step is reported and the remaining
  steps still run; the script exits non-zero at the end if any step failed.
- The Step 6 log watch starts from the moment the run began, so a launch request
  sent before Step 6 is still detected.

- **timpani-o** runs as a Podman container (image pulled from
  `ghcr.io/mco-piccolo/timpani-o:latest` and launched by
  `timpani/scripts/install-timpani-o.sh`; logs via
  `sudo podman logs -f timpani-o`)
- **timpani-n** is installed from a prebuilt native package (`.deb`/`.rpm`) in
  the [../../artifacts](../../artifacts) directory by
  `timpani/scripts/install-timpani-n.sh` and runs as the `timpani-n` systemd
  service (logs via `sudo journalctl -u timpani-n -f`)
- Detailed values such as paths and image versions can be overridden in the **ADVANCED SETTINGS** section of config.env
- Scripts work regardless of the current working directory (paths are resolved relative to their own location)
