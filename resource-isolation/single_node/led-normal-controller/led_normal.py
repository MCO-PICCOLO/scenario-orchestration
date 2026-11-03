#!/usr/bin/env python3
# /********************************************************************************
# * Copyright (c) 2026 Contributors to the Eclipse Foundation
# *
# * See the NOTICE file(s) distributed with this work for additional
# * information regarding copyright ownership.
# *
# * This program and the accompanying materials are made available under the
# * terms of the Apache License 2.0 which is available at
# * https://www.apache.org/licenses/LICENSE-2.0
# *
# * SPDX-License-Identifier: Apache-2.0
# ********************************************************************************/

"""
LED Normal Controller - Interval-based LED control

Architecture:
- Main Thread: State machine management, interval calculation, LED toggle
- Worker Thread: CPU load simulation (busy_work)
- Metrics Thread (daemon): Prometheus HTTP server (:9102)

State Machine:
- NORMAL: delay < 500ms, normal toggle
- STRESS: delay >= 500ms, slow toggle
- RECOVERY: Synchronize with timpani on STRESS → NORMAL transition
"""

import os
import sys
import time
import math
import signal
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

try:
    import serial
except ImportError:
    print("pyserial not installed. Run: pip install pyserial")
    sys.exit(1)

# Configuration
SERIAL_PORT = "/dev/arduino_led_normal"
BAUD_RATE = 115200
INTERVAL = 0.5  # 500ms
METRICS_PORT = 9102
SYNC_FILE = "/tmp/timpani_start"
LED_STATE_FILE = "/tmp/timpani_led_state"
DEFAULT_BUSY_ITERATIONS = 13_000_000

# Global state
g_running = True
g_metrics = {
    "delay_ms": 0.0,
    "interval_ms": 500.0,
    "led_state": 0,
    "signal_count": 0,
}


def get_env_int(name: str, default: int) -> int:
    """Read integer from environment variable"""
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


def read_timpani_state() -> bool | None:
    """Read timpani LED state file (for synchronization)"""
    try:
        with open(LED_STATE_FILE, "r") as f:
            return f.read().strip() == "1"
    except (IOError, OSError):
        return None


def resolve_cpu_affinity(default: int) -> int:
    """Prefer the current process affinity mask, but fall back to the host CPU count."""
    try:
        allowed = os.sched_getaffinity(0)
        if allowed:
            return max(allowed)
    except (AttributeError, OSError):
        pass
    cpu_count = os.cpu_count() or 1
    if cpu_count > 1:
        return max(0, min(default, cpu_count - 1))
    return default


class ComputationWorker:
    """Perform CPU load computation in separate thread"""

    def __init__(self):
        self._completed = threading.Event()
        self._thread: threading.Thread | None = None
        self.computation_time = 0.0

    def start(self, iterations: int):
        """Start computation"""
        self._completed.clear()
        self._thread = threading.Thread(target=self._run, args=(iterations,), daemon=True)
        self._thread.start()

    def _run(self, iterations: int):
        """Execute busy_work"""
        start = time.perf_counter()
        total = sum(i * i for i in range(iterations))
        _ = total  # Prevent unused warning
        self.computation_time = time.perf_counter() - start
        self._completed.set()

    def wait(self, timeout: float = None) -> bool:
        """Wait for completion"""
        return self._completed.wait(timeout)

    @property
    def is_completed(self) -> bool:
        return self._completed.is_set()


class MetricsHandler(BaseHTTPRequestHandler):
    """Prometheus metrics HTTP handler"""

    def log_message(self, *args):
        pass  # Disable logging

    def do_GET(self):
        body = (
            "# HELP led_delay_ms LED control delay in milliseconds\n"
            "# TYPE led_delay_ms gauge\n"
            f'led_delay_ms{{container="normal"}} {g_metrics["delay_ms"]:.2f}\n'
            "# HELP led_interval_ms LED toggle interval in milliseconds\n"
            "# TYPE led_interval_ms gauge\n"
            f'led_interval_ms{{container="normal"}} {g_metrics["interval_ms"]:.2f}\n'
            "# HELP led_state Current LED state (0=OFF, 1=ON)\n"
            "# TYPE led_state gauge\n"
            f'led_state{{container="normal"}} {g_metrics["led_state"]}\n'
            "# HELP led_signal_count Total LED toggle count\n"
            "# TYPE led_signal_count counter\n"
            f'led_signal_count{{container="normal"}} {g_metrics["signal_count"]}\n'
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body.encode())


def start_metrics_server():
    """Start Prometheus metrics server"""
    try:
        server = HTTPServer(("0.0.0.0", METRICS_PORT), MetricsHandler)
        print(f"[Metrics] Server listening on port {METRICS_PORT}")
        server.serve_forever()
    except Exception as e:
        print(f"[Metrics] Error: {e}", file=sys.stderr)


def shutdown_handler(sig, frame):
    """Shutdown signal handler"""
    global g_running
    g_running = False
    print("\nShutdown signal received")


def main():
    global g_running

    # Environment variables
    cpu_affinity = get_env_int("CPU_AFFINITY", resolve_cpu_affinity(12))
    busy_iterations = get_env_int("BUSY_ITERATIONS", DEFAULT_BUSY_ITERATIONS)

    # Remove stale sync state from previous runs.
    for stale in (SYNC_FILE, LED_STATE_FILE):
        try:
            if os.path.exists(stale):
                os.remove(stale)
        except OSError:
            pass

    # Set CPU affinity
    try:
        os.sched_setaffinity(0, {cpu_affinity})
        print(f"CPU affinity set to: {cpu_affinity}")
    except (OSError, AttributeError) as e:
        print(f"Warning: Could not set CPU affinity: {e}")

    # Signal handlers
    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)

    # Start metrics server (daemon)
    threading.Thread(target=start_metrics_server, daemon=True).start()

    print("=== LED Normal Controller ===")
    print(f"Serial: {SERIAL_PORT}, Interval: {INTERVAL*1000:.0f}ms, Iterations: {busy_iterations}")

    # Wait for sync file
    print(f"Waiting for sync file: {SYNC_FILE}")
    while g_running and not os.path.exists(SYNC_FILE):
        time.sleep(0.01)

    if not g_running:
        return

    print("Sync file detected, starting...")

    # Serial connection
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
        print(f"Serial connected: {SERIAL_PORT}")
    except serial.SerialException as e:
        print(f"Warning: Serial unavailable ({e}), dry-run mode")
        ser = None

    # Initialize state
    state = "NORMAL"  # NORMAL, STRESS, RECOVERY
    led_state = False
    signal_count = 0
    worker = ComputationWorker()

    # First toggle (simultaneous start with timpani)
    signal_count += 1
    led_state = True
    if ser:
        ser.write(b"1")
        ser.flush()
    g_metrics["led_state"] = 1
    g_metrics["signal_count"] = signal_count
    print(f"[Normal {signal_count}] LED ON (start)")

    last_signal_time = time.perf_counter()

    # Main Loop
    while g_running:
        # 1. Start computation
        worker.start(busy_iterations)

        # 2. Wait for computation completion
        while g_running and not worker.is_completed:
            time.sleep(0.001)

        if not g_running:
            break

        computation_ms = worker.computation_time * 1000

        # 3. Calculate next interval end point (align to 500ms units)
        elapsed = time.perf_counter() - last_signal_time
        intervals_to_wait = math.ceil(elapsed / INTERVAL)
        next_interval_end = last_signal_time + (intervals_to_wait * INTERVAL)

        # 4. Wait until interval end
        sleep_time = next_interval_end - time.perf_counter()
        if sleep_time > 0:
            time.sleep(sleep_time)

        current_time = time.perf_counter()
        actual_interval_ms = (current_time - last_signal_time) * 1000

        # 5. State transition and LED control
        if state == "STRESS" and computation_ms < 500:
            # RECOVERY: Synchronize with timpani
            timpani_state = read_timpani_state()
            if timpani_state is not None:
                led_state = timpani_state  # Sync (not toggle)
            else:
                led_state = not led_state  # fallback

            state = "NORMAL"
            log_prefix = "SYNC "
        elif computation_ms >= 500:
            # STRESS: Slow toggle
            state = "STRESS"
            led_state = not led_state
            log_prefix = "STRESS "
        else:
            # NORMAL: Normal toggle
            state = "NORMAL"
            led_state = not led_state
            log_prefix = ""

        # 6. Send LED
        signal_count += 1
        if ser:
            ser.write(b"1" if led_state else b"0")
            ser.flush()

        # 7. Calculate delay
        if computation_ms < 500:
            delay_ms = max(0, actual_interval_ms - 500)
        else:
            delay_ms = computation_ms

        # 8. Update metrics
        g_metrics["delay_ms"] = delay_ms
        g_metrics["interval_ms"] = actual_interval_ms
        g_metrics["led_state"] = 1 if led_state else 0
        g_metrics["signal_count"] = signal_count

        # 9. Log
        print(f"[Normal {signal_count}] {log_prefix}LED {'ON' if led_state else 'OFF'} "
              f"(interval: {actual_interval_ms:.1f}ms, delay: {delay_ms:.1f}ms)")

        last_signal_time = current_time

    # Cleanup
    if ser:
        ser.close()
    print("Shutdown complete")


if __name__ == "__main__":
    main()
