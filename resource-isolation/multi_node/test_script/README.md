# Multi-node Resource Isolation Test

Scripts to start and stop the pullpiri + TIMPANI based resource-isolation
scenario across master and guest nodes. Running the `run/stop` scripts from the
master PC orchestrates both nodes over SSH.

## Layout

```
test_script/
├── config.env                        # settings (edit here only)
├── run_resource_isolation_flow.sh    # start (SSH orchestration)
├── stop_resource_isolation_flow.sh   # stop
├── preflight/
│   ├── prepare_master.sh             # run directly on the master node
│   └── prepare_guest.sh              # run directly on the guest node
├── lib/utils.sh                      # shared functions (SSH wrappers, etc.)
├── pullpiri/                         # pullpiri install/uninstall scripts, node config
└── timpani/                          # timpani-o/-n install/uninstall scripts, node config
```

## Prerequisites

- `sdv-blueprint` deployed on each node (paths set independently via
  `MASTER_BASE_DIR` / `GUEST_BASE_DIR` in config.env — they may differ)
- master: `docker`, `arduino-cli`, `podman`
- guest: `podman`, `arduino-cli`
- master PC: `ssh`, and `sshpass` (when using password authentication)
- Arduino boards: the udev rules ([master](../nuc_master/arduino/99-arduino.rules),
  [guest](../nuc_guest/arduino/99-arduino-led.rules)) are hardware-specific and
  depend on each board's USB serial. Replace every `ATTRS{serial}` value with the
  serial of your own boards before running the preflight scripts (find it with
  `udevadm info -a -n /dev/ttyACM0 | grep '{serial}' -m 1` or `arduino-cli board list`). This is a per-hardware configuration step and not a generic runtime setting.

## config.env

Edit only the **USER SETTINGS** section at the top.

| Variable | Description |
|----------|-------------|
| `MASTER_HOST` / `PORT` / `USER` / `PASS` | master SSH connection info |
| `GUEST_HOST` / `PORT` / `USER` / `PASS` | guest SSH connection info |
| `GUEST_NODE_IP` | guest internal-network IP. **Required** (used for the guest nodeagent) |
| `MASTER_NODE_IP` | master internal-network IP. **Required** (used for the serial-bridge, pullpiri, the guest nodeagent, timpani-n and the guest KUKSA bridge) |
| `MASTER_NODE_NAME` / `GUEST_NODE_NAME` | Pullpiri node names. Optional; empty = the node's real `hostname`. Must be different from each other. |
| `MASTER_BASE_DIR` / `GUEST_BASE_DIR` | `multi_node` path on each node |

**ADVANCED SETTINGS** (no change needed with defaults): sudo passwords, various
paths, TIMPANI locations, databroker log watch (`DATABROKER_LOG_REGEX`,
`WAIT_LOG_TIMEOUT_SEC`), SSH options (`USE_SSHPASS`, etc.).

**Credentials**: prefer SSH keys and passwordless sudo. Set
`MASTER_SUDO_PASS=""` / `GUEST_SUDO_PASS=""` for passwordless sudo (the scripts
then use `sudo -n`). Otherwise the sudo password defaults to the login password.
Passwords are never placed on a command line: SSH passwords go to `sshpass` via
the `SSHPASS` environment variable and sudo passwords go over the SSH connection's
stdin. Credentials stay on the machine running the scripts; the master is never
given the guest's credentials, and the guest nodeagent is installed and removed
over the script's own SSH connection to the guest. Export the passwords in your
shell rather than committing them to config.env.

> **kuksa-bridge address**: leave `KUKSA_HOST` in
> [../nuc_guest/kuksa-bridge/.env](../nuc_guest/kuksa-bridge/.env) empty.
> `prepare_guest.sh` fills it with the master IP (`MASTER_NODE_IP` or the default
> gateway) right before building the image.

## Scripts

| Script | Runs on | Role |
|--------|---------|------|
| `preflight/prepare_master.sh` | master | udev rules, Arduino upload, serial-bridge image build, databroker pull |
| `preflight/prepare_guest.sh` | guest | Arduino upload, led/kuksa-bridge/stress-ng image build (`KUKSA_HOST` auto-setup) |
| `run_resource_isolation_flow.sh` | master PC | resolve master IP -> start serial-bridge -> install pullpiri on master and nodeagent on guest -> monitoring/timpani-o -> wait for databroker log -> timpani-n |
| `stop_resource_isolation_flow.sh` | master PC | compose down, stop monitoring, kill timpani, remove the scenario's workload containers, uninstall nodeagent (guest) and pullpiri (master) |

## Test Procedure

### 1. Prepare (one-time, run directly on each node)

```bash
# on the master node
./preflight/prepare_master.sh

# on the guest node
./preflight/prepare_guest.sh
```

### 2. Start (master PC)

```bash
cd multi_node/test_script
./run_resource_isolation_flow.sh
```

The script drives both nodes over SSH in order, then waits for Arduino input at **Step 6**.

- **Turn the rotary to 120 and press its button** on the master -> workload containers are launched on the guest
- Once the script detects the master's databroker log (`api/artifact ... container-launch.yaml status=200`),
  it proceeds to **Step 7** (guest timpani-n) automatically

### 3. Observe

- **Press the joystick button** on the master to toggle the guest's CPU load (stress-ng)
- Compare the two LED periods in Grafana (`http://<guest-ip>:3000`)
  - TIMPANI LED: stays ~500ms regardless of load
  - Normal LED: delayed beyond 500ms under load

### 4. Stop (master PC)

```bash
./stop_resource_isolation_flow.sh
```

## Notes

- **Teardown only removes what the flow created.** The install scripts record what
  they create in `/etc/pullpiri/.resource-isolation-state` on each node and back up
  any pre-existing `settings.yaml`, `nodeagent.yaml`, `nodeagent.service` or
  `/opt/pullpiri/nodeagent` as `*.resource-isolation.bak`. The uninstall scripts
  remove only those items and restore the backups, so existing Pullpiri state is
  kept. The flow uses its own RocksDB directory
  (`/etc/pullpiri/resource_isolation_rocksdb`); an existing
  `pullpiri_shared_rocksdb` is never touched. Workload containers on the guest are
  removed by image (`pullpiri/scripts/uninstall-workloads.sh`), not with
  `podman rm --all`.
- Each teardown step is best-effort: a failed step is reported and the remaining
  steps still run; the script exits non-zero at the end if any step failed.
- The Step 6 log watch starts from the moment the run began (read from the master's
  clock), so a launch request sent before Step 6 is still detected.

- `GUEST_NODE_NAME` is the single source of truth for the guest's Pullpiri node name. The run flow applies
  it to the guest nodeagent, the workload YAMLs (`${NODE_NAME}` placeholder, rendered by the serial-bridge),
  the timpani node config (rendered by `install-timpani-o.sh`) and timpani-n. `MASTER_NODE_NAME` is
  applied to the master's `settings.yaml`, the master nodeagent and the timpani node config. Names may
  contain only `A-Z a-z 0-9 . _ -`.
- The workload YAMLs under `serial-bridge/pullpiri-yaml/` are templates and must be sent through the
  serial-bridge; posting them directly leaves the literal `${NODE_NAME}` in place.
- Scripts work regardless of the current working directory (paths are resolved relative to their own location)
