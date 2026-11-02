
# LED Control Demo - Grafana Monitoring

This is a Grafana monitoring system for visualizing LED ON/OFF tick events of TIMPANI vs Normal LED controllers.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Single Node                             │
│                                                            │
│  ┌──────────────────┐       ┌──────────────────┐           │
│  │ led-timpani-ctrl │       │ led-normal-ctrl  │           │
│  │   (C + TIMPANI)  │       │     (Python)     │           │
│  │   Port: 9101     │       │   Port: 9102     │           │
│  └────────┬─────────┘       └────────┬─────────┘           │
│           │                          │                     │
│           │   Prometheus Metrics     │                     │
│           └──────────┬───────────────┘                     │
│                      │                                   │
│           ┌──────────▼───────────┐                        │
│           │     Prometheus       │                        │
│           │     Port: 9090       │                        │
│           └──────────┬───────────┘                        │
│                      │                                   │
│           ┌──────────▼───────────┐                        │
│           │      Grafana         │                        │
│           │     Port: 3000       │                        │
│           └──────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

## Collected Metrics

| Metric             | Description                                         | Unit  |
|--------------------|-----------------------------------------------------|-------|
| `led_signal_count` | Total LED toggle count (source for ON/OFF ticks)    | count |
| `led_interval_ms`  | Actual LED toggle interval                          | ms    |
| `led_state`        | Current LED state (0=OFF, 1=ON)                     | -     |

## Usage


### 1. Start Monitoring System

```bash
./start.sh
```

### 2. Access Grafana

- URL: http://localhost:3000
- Default account: admin / admin
- Dashboard: "LED Control Demo - TIMPANI vs Normal"

### 3. Start LED Controllers

Both LED controller containers must be running:

```bash
# led-timpani-ctrl (Port 9101 must be exposed)
# led-normal-ctrl (Port 9102 must be exposed)
```

### 4. Load Testing

Run a stress container to simulate CPU load:

```bash
podman run --rm -d stress-ng --cpu 4 --timeout 30s
```

## Dashboard Panel Description

### LED ON/OFF Tick Timeline
- Real-time comparison of ON/OFF toggle ticks between TIMPANI and Normal controllers
- Tick events are derived from `led_signal_count` increments
- Spikes (1) indicate a toggle event occurred in that short window

### LED Toggle Interval
- Shows actual interval compared to expected 500ms
- TIMPANI maintains 500ms even under load
- Normal interval increases under load

### Current Stats
- Shows current tick, signal count, and LED state
- Includes 1-minute average toggle rate

## Troubleshooting

### Prometheus Not Collecting Metrics

```bash
# Check each controller's metrics endpoint
curl http://localhost:9101/metrics  # timpani
curl http://localhost:9102/metrics  # normal
```

### No Data in Grafana

1. Check Prometheus data source connection
2. Check time range (recommend Last 2 minutes)
3. Enable auto-refresh (500ms)


## Stop Monitoring

```bash
./stop.sh
```

## Notes

- `network_mode: host` allows containers to access the host network directly
- Prometheus scrape interval: 100ms (for finer ON/OFF tick capture)
- Grafana refresh: 200ms~500ms (for real-time monitoring)
