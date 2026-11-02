# LED Normal Controller

Python-based LED controller using sleep-based interval timing.

## Overview

This controller uses `time.sleep()` to maintain a 500ms LED toggle interval.
Under CPU load, sleep timing becomes imprecise, causing delayed LED toggles.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   LED Normal Controller                     │
│                                                             │
│  ┌─────────────────┐                                        │
│  │   Main Thread   │   State Machine:                       │
│  │  (state machine)│   - NORMAL: delay < 500ms              │
│  │                 │   - STRESS: delay >= 500ms (skips)     │
│  └────────┬────────┘   - RECOVERY: sync with timpani        │
│           │                                                 │
│           ▼                                                 │
│  ┌─────────────────┐                                        │
│  │  Arduino LED    │   Serial: /dev/arduino_led_normal      │
│  │  (toggle ON/OFF)│   Baud: 115200                         │
│  └─────────────────┘                                        │
│                                                             │
│  ┌─────────────────┐                                        │
│  │ Computation     │   CPU load simulation (busy_work)      │
│  │    Worker       │   Iterations: BUSY_ITERATIONS env      │
│  └─────────────────┘                                        │
│                                                             │
│  ┌─────────────────┐                                        │
│  │  Metrics Thread │   HTTP :9102/metrics (Prometheus)      │
│  │  (daemon)       │                                        │
│  └─────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
```

## Build

```bash
sudo podman build -t localhost/led-normal-controller:latest .
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BUSY_ITERATIONS` | `13000000` | Number of iterations for busy_work computation |

## Prometheus Metrics

Exposed on port **9102** at `/metrics`:

| Metric | Type | Description |
|--------|------|-------------|
| `led_delay_ms` | gauge | Computation time or interval deviation (ms) |
| `led_interval_ms` | gauge | Actual interval between toggles (ms) |
| `led_state` | gauge | Current LED state (0=OFF, 1=ON) |
| `led_signal_count` | counter | Total number of LED toggles |

```bash
curl http://localhost:9102/metrics
```

## State Machine

### NORMAL State
- Computation completes within interval (< 500ms)
- LED toggles on schedule
- `delay_ms` = actual_interval - 500ms

### STRESS State
- Computation exceeds interval (>= 500ms)
- LED toggle is **SKIPPED** for this interval
- `delay_ms` = computation time (shows how much delayed)

### RECOVERY State
- Transitioning from STRESS → NORMAL
- Reads timpani LED state from `/tmp/timpani_led_state`
- Synchronizes to match timpani (no toggle, just set)

## Synchronization

- Waits for `/tmp/timpani_start` file before starting (created by led-timpani-controller)
- Reads `/tmp/timpani_led_state` during RECOVERY to sync with timpani
- First LED toggle happens immediately after sync file detected

## Expected Behavior

| Condition | Interval | Delay |
|-----------|----------|-------|
| No CPU Load | ~500ms | <50ms |
| High CPU Load | **>500ms** | **>500ms** |

**Key Point**: Under CPU load, sleep-based timing degrades because:
1. `time.sleep()` is not precise under CPU contention
2. Computation (busy_work) must complete before LED toggle
3. Total interval = computation_time + sleep_overhead

This demonstrates why **TIMPANI signal-based control** is superior for real-time tasks.

