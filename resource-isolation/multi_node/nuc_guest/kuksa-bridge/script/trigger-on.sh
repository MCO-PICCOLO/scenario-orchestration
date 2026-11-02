#!/bin/bash
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

# Trigger CPU Load ON - Start workload

# All output goes to stdout so Python can capture it
{
    echo "========================================="
    echo "[CPU LOAD ON] Starting workload..."
    echo "Time: $(date)"
    echo "========================================="

    # Check if stress-ng is already running
    if pgrep -x "stress-ng" > /dev/null; then
        echo "⚠ stress-ng is already running, killing..."
        pkill -9 -g $(pgrep -x stress-ng | head -1) 2>/dev/null || true
        pkill -9 stress-ng 2>/dev/null
        killall -9 stress-ng 2>/dev/null
        sleep 2
    fi

    # Start stress-ng in a new process group using setsid
    # This ensures all child processes are in the same group for easy cleanup
    setsid stress-ng --cpu 0 --cpu-method all --timeout 0 >/dev/null 2>&1 &
    STRESS_PID=$!
    
    # Save the process group ID for cleanup
    mkdir -p /tmp/stress-ng
    echo $STRESS_PID > /tmp/stress-ng/pgid
    
    sleep 2

    # Verify process is running
    if ps -p $STRESS_PID > /dev/null 2>&1; then
        PROC_COUNT=$(pgrep -x "stress-ng" | wc -l)
        PGID=$(ps -o pgid= -p $STRESS_PID | tr -d ' ')
        echo "✓ CPU Load started (PID: $STRESS_PID | PGID: $PGID)"
        echo "✓ Total stress-ng processes: $PROC_COUNT"
    else
        # Double check with pgrep (process might have forked)
        PROC_COUNT=$(pgrep -x "stress-ng" | wc -l)
        if [ "$PROC_COUNT" -gt 0 ]; then
            echo "✓ CPU Load started (forked, $PROC_COUNT processes)"
        else
            echo "✗ Failed to start stress-ng (no processes found)"
            # Non-zero so the caller does not mark the workload as running.
            exit 1
        fi
    fi
}
