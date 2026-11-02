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

# Trigger CPU Load OFF - Stop workload

# All output goes to stdout so Python can capture it
{
    echo "========================================="
    echo "[CPU LOAD OFF] Stopping workload..."
    echo "Time: $(date)"
    echo "========================================="

    # Count processes before termination
    BEFORE=$(ps aux | grep -E "stress-ng" | grep -v grep | wc -l)
    ZOMBIE_BEFORE=$(ps aux | grep stress-ng | grep defunct | grep -v grep | wc -l)
    echo "Processes before: $BEFORE (zombies: $ZOMBIE_BEFORE)"
    
    # Step 1: Try graceful termination first (SIGTERM) to avoid zombies
    echo "Step 1: Graceful termination (SIGTERM)..."
    if [ -f /tmp/stress-ng/pgid ]; then
        PGID=$(cat /tmp/stress-ng/pgid 2>/dev/null)
        if [ ! -z "$PGID" ] && ps -p $PGID > /dev/null 2>&1; then
            echo "  Terminating process group: $PGID"
            kill -15 -$PGID 2>/dev/null || true
        fi
        rm -f /tmp/stress-ng/pgid
    fi
    
    pkill -15 stress-ng 2>/dev/null || true
    killall -15 stress-ng 2>/dev/null || true
    sleep 1
    
    # Step 2: Force kill if still running
    REMAINING=$(ps aux | grep stress-ng | grep -v grep | grep -v defunct | wc -l)
    if [ "$REMAINING" -gt 0 ]; then
        echo "Step 2: Force kill remaining processes..."
        pkill -9 stress-ng 2>/dev/null || true
        killall -9 stress-ng 2>/dev/null || true
        killall -9 stress-ng-cpu 2>/dev/null || true
        sleep 1
    fi
    
    # Step 3: Clean up zombies by waiting for parent to reap them
    echo "Step 3: Waiting for zombie cleanup..."
    sleep 2
    
    # Step 4: If zombies still exist, try to force cleanup
    ZOMBIE_CHECK=$(ps aux | grep stress-ng | grep defunct | grep -v grep | wc -l)
    if [ "$ZOMBIE_CHECK" -gt 0 ]; then
        echo "Step 4: Zombies detected ($ZOMBIE_CHECK), attempting cleanup..."
        
        # Find zombie parent processes
        ZOMBIE_PARENTS=$(ps -eo pid,ppid,stat,cmd | grep defunct | grep stress-ng | awk '{print $2}' | sort -u)
        
        if [ ! -z "$ZOMBIE_PARENTS" ]; then
            for ppid in $ZOMBIE_PARENTS; do
                if [ "$ppid" != "0" ] && [ "$ppid" != "1" ]; then
                    # Send SIGCHLD to parent to trigger zombie reaping
                    echo "  Sending SIGCHLD to parent: $ppid"
                    kill -CHLD $ppid 2>/dev/null || true
                fi
            done
            sleep 1
        fi
    fi
    
    sleep 1

    # Verify termination
    AFTER=$(ps aux | grep -E "stress-ng" | grep -v grep | wc -l)
    ZOMBIE_AFTER=$(ps aux | grep stress-ng | grep defunct | grep -v grep | wc -l)
    echo "Processes after: $AFTER (zombies: $ZOMBIE_AFTER)"
    
    if [ "$AFTER" -eq 0 ]; then
        echo "✓ All stress-ng processes terminated"
    else
        echo "⚠ Warning: $AFTER stress-ng process(es) still running ($ZOMBIE_AFTER zombies)"
        if [ "$ZOMBIE_AFTER" -gt 0 ]; then
            echo "⚠ Zombie processes require parent process cleanup"
            echo "Remaining zombie parent PIDs:"
            ps -eo pid,ppid,stat,comm | grep defunct | grep stress-ng | awk '{print $2}' | sort -u
        fi
    fi
}
