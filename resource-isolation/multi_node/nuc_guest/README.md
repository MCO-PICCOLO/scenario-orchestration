# Resource Isolation Demo — NUC Guest

Guest-node assets for the multi-node resource-isolation demo. Everything in this
folder runs **on the guest PC**; the master node drives the scenario over SSH and
serves the KUKSA databroker.

## Role of the guest node

- Runs the workload containers scheduled by pullpiri (LED controllers).
- Watches the master's KUKSA databroker for the button signal and toggles a CPU
  load (`stress-ng`) locally to create resource contention.
- Exposes Prometheus metrics and a Grafana dashboard so the two LED periods can
  be compared under load.

## Components

```
nuc_guest/
├── arduino/                 # guest-side Arduino sketch/assets
├── kuksa-bridge/            # polls the master databroker, toggles stress-ng
├── led-normal-controller/   # Normal LED workload (Python), Prometheus :9102
├── led-timpani-controller/  # TIMPANI LED workload (C + TIMPANI), Prometheus :9101
└── monitoring/              # Prometheus (:9090) + Grafana stack
```

### kuksa-bridge

- `kuksa-bridge/bridge.py` polls `Vehicle.Cabin.ResourceIsolation.ButtonPressed`
  from the master's KUKSA databroker (`KUKSA_HOST:55556`, gRPC).
- Toggle mode: on each button press it runs `script/trigger-on.sh` /
  `script/trigger-off.sh`, which start/stop `stress-ng` **directly on the host**
  (`setsid stress-ng --cpu 0 --cpu-method all --timeout 0`) — not as a container.
- `KUKSA_HOST` is left empty in [kuksa-bridge/.env](kuksa-bridge/.env);
  `preflight/prepare_guest.sh` fills it with the master IP before building the image.

### led-timpani-controller / led-normal-controller

- The two LED workloads launched by pullpiri when the rotary is turned on the master.
- Each exposes Prometheus metrics (TIMPANI: `:9101`, Normal: `:9102`) for their
  LED ON/OFF tick timing. See [monitoring/README.md](monitoring/README.md).

### monitoring

- Prometheus (`:9090`) scrapes the two controllers; Grafana visualizes the LED
  periods. Start/stop via `monitoring/start.sh` / `monitoring/stop.sh`.

## Prerequisites

- `podman` and `stress-ng` available on the guest.
- Network access to the master's KUKSA databroker at `KUKSA_HOST:55556`.
- Arduino uploaded and images built via the guest preflight step
  (`../test_script/preflight/prepare_guest.sh`).

## Notes

- This folder is orchestrated from the master via the multi-node flow; you do not
  normally run these components by hand. For the full procedure see
  [../test_script/README.md](../test_script/README.md).
- Expected result: under CPU load the **TIMPANI LED** stays ~500 ms while the
  **Normal LED** is delayed beyond 500 ms.
