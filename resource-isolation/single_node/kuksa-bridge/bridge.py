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
KUKSA Subscriber Bridge
Subscribes to button press signals from KUKSA databroker
and executes shell script to trigger workload (toggle mode)
"""
import sys
import json
import time
import subprocess
import threading
import os
from pathlib import Path
from kuksa_client import KuksaClientThread
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Shell scripts for toggle mode
TRIGGER_ON_SCRIPT = os.environ.get('TRIGGER_ON_SCRIPT', '/app/script/trigger-on.sh')
TRIGGER_OFF_SCRIPT = os.environ.get('TRIGGER_OFF_SCRIPT', '/app/script/trigger-off.sh')

# Global state for workload toggle
workload_running = False

def trigger_workload_on():
    """Execute shell script to start CPU load workload"""
    try:
        print(f" Executing ON script: {TRIGGER_ON_SCRIPT}")
        
        # Check if script exists
        if not os.path.exists(TRIGGER_ON_SCRIPT):
            print(f" Script not found: {TRIGGER_ON_SCRIPT}", file=sys.stderr)
            return False
        
        # Execute shell script with bash
        result = subprocess.run(
            ['bash', TRIGGER_ON_SCRIPT],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Always print output for debugging
        print(f"   Return code: {result.returncode}")
        if result.stdout:
            print(f"   STDOUT: {result.stdout.strip()}")
        else:
            print(f"   STDOUT: (empty)")
        if result.stderr:
            print(f"   STDERR: {result.stderr.strip()}")
        
        if result.returncode == 0:
            print(f" ON script executed successfully")
            return True
        else:
            print(f" ON script failed with code {result.returncode}", file=sys.stderr)
            return False
                
    except subprocess.TimeoutExpired:
        print(f" ON script execution timeout", file=sys.stderr)
        return False
    except Exception as e:
        print(f" Error executing ON script: {e}", file=sys.stderr)
        return False

def trigger_workload_off():
    """Execute shell script to stop CPU load workload"""
    try:
        print(f" Executing OFF script: {TRIGGER_OFF_SCRIPT}")
        
        # Check if script exists
        if not os.path.exists(TRIGGER_OFF_SCRIPT):
            print(f" Script not found: {TRIGGER_OFF_SCRIPT}", file=sys.stderr)
            return False
        
        # Execute shell script with bash
        result = subprocess.run(
            ['bash', TRIGGER_OFF_SCRIPT],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Always print output for debugging
        print(f"   Return code: {result.returncode}")
        if result.stdout:
            print(f"   STDOUT: {result.stdout.strip()}")
        else:
            print(f"   STDOUT: (empty)")
        if result.stderr:
            print(f"   STDERR: {result.stderr.strip()}")
        
        if result.returncode == 0:
            print(f" OFF script executed successfully")
            return True
        else:
            print(f" OFF script failed with code {result.returncode}", file=sys.stderr)
            return False
                
    except subprocess.TimeoutExpired:
        print(f" OFF script execution timeout", file=sys.stderr)
        return False
    except Exception as e:
        print(f" Error executing OFF script: {e}", file=sys.stderr)
        return False

def toggle_workload():
    """Toggle workload on/off"""
    global workload_running
    
    if workload_running:
        # Turn OFF
        print(" Toggle: Turning OFF workload")
        if trigger_workload_off():
            workload_running = False
    else:
        # Turn ON
        print(" Toggle: Turning ON workload")
        if trigger_workload_on():
            workload_running = True

def get_button_state(client):
    """Get current button state from KUKSA databroker"""
    try:
        b = client.getValue("Vehicle.Cabin.ResourceIsolation.ButtonPressed")
        
        if isinstance(b, str):
            b = json.loads(b)
        val = b.get('value') if isinstance(b, dict) else None
        
        if isinstance(val, str):
            val = json.loads(val)
        button_state = val.get('value') if isinstance(val, dict) else None
        
        return button_state
    except Exception as e:
        print(f"Databroker getValue error: {e}", file=sys.stderr)
        return None

def main():
    print("=== KUKSA Subscriber Bridge (Resource Isolation) ===")
    print("Polling: Vehicle.Cabin.ResourceIsolation.ButtonPressed")
    print("Mode: Toggle (ON/OFF)")
    
    # Initialize KUKSA client
    # KUKSA_HOST is the databroker address (loaded from the .env file).
    #   single-node : this host's LAN IP
    #   multi-node  : the master node's IP
    kuksa_host = os.environ.get('KUKSA_HOST', '127.0.0.1')
    kuksa_port = int(os.environ.get('KUKSA_PORT', '55556'))
    kuksa_protocol = os.environ.get('KUKSA_PROTOCOL', 'grpc')

    print(f"Connecting to KUKSA databroker at {kuksa_host}:{kuksa_port} (protocol: {kuksa_protocol})")

    config = {
        'protocol': kuksa_protocol,
        'ip': kuksa_host,
        'port': kuksa_port,
        'insecure': True
    }
    
    client = KuksaClientThread(config=config)
    client.start()
    
    # Wait for connection
    time.sleep(2)
    
    try:
        signal_path = "Vehicle.Cabin.ResourceIsolation.ButtonPressed"
        print(f"Polling {signal_path}...")
        print(" Polling active. Waiting for button events...")
        
        # Track previous state to detect changes
        prev_state = None
        
        # Keep running - poll for button state
        while True:
            current_state = get_button_state(client)
            
            # Detect state change from False to True (button press)
            if current_state != prev_state:
                if current_state == True or current_state == "true" or current_state == 1:
                    print(f" Button PRESSED detected (toggle trigger)")
                    # Execute toggle in a separate thread to avoid blocking
                    threading.Thread(target=toggle_workload, daemon=True).start()
                elif current_state == False or current_state == "false" or current_state == 0:
                    print(f" Button RELEASED (no action)")
                
                prev_state = current_state
            
            time.sleep(0.1)  # Poll every 100ms
            
    except KeyboardInterrupt:
        print("\nStopping...")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
    finally:
        client.stop()
        print("Stopped.")

if __name__ == "__main__":
    main()

