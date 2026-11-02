# LED TIMPANI Controller

C-based LED controller using TIMPANI real-time signal (SIGRTMIN+2).

## Overview

This controller receives periodic signals from **TIMPANI-N** runtime and toggles an LED accordingly.
Unlike sleep-based approaches, signal-based control maintains precise timing even under CPU load.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   LED TIMPANI Controller                    │
│                                                             │
│  ┌─────────────────┐  SIGRTMIN+2   ┌─────────────────────┐ │
│  │   Main Thread   │◄──────────────│     TIMPANI-N       │ │
│  │  (sigtimedwait) │               │  (500ms periodic)   │ │
│  └────────┬────────┘               └─────────────────────┘ │
│           │                                                 │
│           ▼                                                 │
│  ┌─────────────────┐                                        │
│  │  Arduino LED    │   Serial: /dev/arduino_led_timpani     │
│  │  (toggle ON/OFF)│   Baud: 115200                         │
│  └─────────────────┘                                        │
│                                                             │
│  ┌─────────────────┐                                        │
│  │  Worker Thread  │   Continuous busy_work (CPU load sim)  │
│  │  (busy_work)    │   Iterations: BUSY_ITERATIONS env      │
│  └─────────────────┘                                        │
│                                                             │
│  ┌─────────────────┐                                        │
│  │  Metrics Thread │   HTTP :9101/metrics (Prometheus)      │
│  │  (HTTP server)  │                                        │
│  └─────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
```

## Build

### Local Build

```bash
make clean && make
```

### Docker Build

```bash
sudo podman build -t localhost/led-timpani-controller:latest .
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BUSY_ITERATIONS` | `13000000` | Number of iterations for busy_work loop |

## Prometheus Metrics

Exposed on port **9101** at `/metrics`:

| Metric | Type | Description |
|--------|------|-------------|
| `led_delay_ms` | gauge | Time from signal receipt to LED toggle (ms) |
| `led_interval_ms` | gauge | Actual interval between toggles (ms) |
| `led_state` | gauge | Current LED state (0=OFF, 1=ON) |
| `led_signal_count` | counter | Total number of LED toggles |

```bash
curl http://localhost:9101/metrics
```

## Synchronization

- Creates `/tmp/timpani_start` file on first signal (triggers led-normal-controller start)
- Writes current LED state to `/tmp/timpani_led_state` (for recovery sync)

## Process Name

Sets process name to `led_timpani` via `prctl(PR_SET_NAME)` for TIMPANI-N identification.

## Expected Behavior

| Condition | Interval | Delay |
|-----------|----------|-------|
| No CPU Load | ~500ms | <1ms |
| High CPU Load | **~500ms** | <1ms |

**Key Point**: TIMPANI signal delivery is independent of CPU load, so timing remains precise.

