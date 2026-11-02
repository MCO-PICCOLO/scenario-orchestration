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

import serial
import sys
import threading
import queue
import json
import time
import os
import re
import requests

from kuksa_client import KuksaClientThread

# Serial ports for each Arduino
PORT_JOYSTICK = "/dev/arduino_joystick"  # ttyACM2 - Joystick input
PORT_LED = "/dev/arduino_led"            # ttyACM1 - LED output
PORT_GEAR = "/dev/arduino_gear"          # ttyACM0 - Gear (log only)
BAUD = 115200

def send_to_databroker(client, button_state):
    """Send button state to KUKSA databroker"""
    try:
        client.setValue("Vehicle.Cabin.ResourceIsolation.ButtonPressed", json.dumps(button_state))
        print(f"✓ Sent to databroker: ButtonPressed={button_state}")
    except Exception as e:
        print(f"✗ Databroker setValue error: {e}", file=sys.stderr)

def databroker_worker(client, q, stop_event):
    """Worker thread to send data to KUKSA databroker"""
    while not stop_event.is_set():
        try:
            button_state = q.get(timeout=0.5)
        except queue.Empty:
            continue
        try:
            send_to_databroker(client, button_state)
        except Exception as e:
            print(f"Databroker send error: {e}", file=sys.stderr)
        q.task_done()

def render_yaml(body: str) -> str:
    """Replace the ${NODE_NAME} placeholder with the Pullpiri node name.

    NODE_NAME is set by the orchestrator (config.env) and must equal the name the
    nodeagent and timpani-n register with.
    """
    node_name = os.environ.get('NODE_NAME', '')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', node_name):
        raise ValueError(
            f"NODE_NAME is empty or invalid ({node_name!r}); set it in test_script/config.env "
            "and start the bridge through run_resource_isolation_flow.sh")
    return body.replace('${NODE_NAME}', node_name)

def send_yaml_artifact(yaml_path: str):
    # Single-node: pullpiri apiserver runs on the same host
    master_ip = os.environ.get('MASTER_IP', '127.0.0.1')
    url = f'http://{master_ip}:47099/api/artifact'
    try:
        with open(yaml_path, 'r', encoding='utf-8') as f:
            body = render_yaml(f.read())
        headers = {'Content-Type': 'text/plain'}
        response = requests.post(url, headers=headers, data=body, timeout=5)
        print(f"[POST] {url} yaml={os.path.basename(yaml_path)} status={response.status_code}")
        if response.status_code != 200:
            print(f"Response: {response.text}")
    except Exception as e:
        print(f"send_yaml_artifact error: {e}", file=sys.stderr)

def handle_gear_yaml(stop_event):
    """Thread: Monitor gear rotary encoder button presses
    Button pressed at rotation 80 → "0" → LOW LOAD mode
    Button pressed at rotation 120 → "1" → HIGH LOAD mode
    """
    prev_yaml_state = -1
    while not stop_event.is_set():
        try:
            with serial.Serial(PORT_GEAR, BAUD, timeout=1) as s_gear:
                print(f"[Thread-Gear] Monitor started: {PORT_GEAR}")
                while not stop_event.is_set():
                    raw = s_gear.readline()
                    
                    if not raw:
                        time.sleep(0.01)
                        continue
                    
                    try:
                        line = raw.decode(errors="replace").strip()
                    except Exception as e:
                        print(f"Gear decode error: {e}", file=sys.stderr)
                        continue
                        
                    if not line:
                        continue
                    
                    # Only process "0" or "1" from button presses
                    if line.isdigit():
                        if line == "0":
                            if prev_yaml_state == 0:
                                print("[Gear] Already in LOW LOAD mode, skipping")
                                continue
                            prev_yaml_state = 0
                            print("=" * 50)
                            print("[Gear] LOW LOAD MODE (Normal)")
                            print("=" * 50)
                            send_yaml_artifact('/yaml/container-stop.yaml')
                            time.sleep(1)
                        elif line == "1":
                            if prev_yaml_state == 1:
                                print("[Gear] Already in HIGH LOAD mode, skipping")
                                continue
                            prev_yaml_state = 1
                            print("=" * 50)
                            print("[Gear] HIGH LOAD MODE (Timpani)")
                            print("=" * 50)
                            send_yaml_artifact('/yaml/container-launch.yaml')
                            time.sleep(1)
                    else:
                        # Log any other messages
                        print(f"[Gear] Message: {line}")
                    
                    time.sleep(0.05)
        except (serial.SerialException, OSError) as e:
            print(f"Gear serial error: {e}. Retrying...", file=sys.stderr)
            time.sleep(1)
        except Exception as e:
            print(f"Gear thread error: {e}. Retrying...", file=sys.stderr)
            time.sleep(1)

def main(q, stop_event):
    """Main thread: Monitor joystick button and control LED colors
    Button press → DataBroker + GREEN LED
    Button release → DataBroker + OFF LED
    """
    while not stop_event.is_set():
        try:
            with serial.Serial(PORT_JOYSTICK, BAUD, timeout=1) as s_joystick, \
                 serial.Serial(PORT_LED, BAUD, timeout=1) as s_led:
                print(f"[Main-Joystick] Monitor started: {PORT_JOYSTICK}")
                print(f"[Main-LED] Monitor started: {PORT_LED}")
                last_btn = 0
                
                while not stop_event.is_set():
                    raw = s_joystick.readline()
                    if not raw:
                        time.sleep(0.01)
                        continue
                    
                    line = raw.decode(errors="replace").strip()
                    if not line:
                        continue

                    # Skip debug messages
                    if line.startswith("["):
                        continue
                    
                    btn = None
                    if line == "1":
                        btn = 1
                    elif line == "0":
                        btn = 0
                    
                    if btn is None:
                        continue
                    
                    if btn != last_btn:
                        if btn == 1:
                            print(f"[Joystick] PRESSED → DataBroker + LED GREEN")
                            q.put(True)
                            
                            # Send GREEN command to LED
                            try:
                                s_led.write(b"GREEN\n")
                            except Exception as e:
                                print(f"Failed to send GREEN to LED: {e}", file=sys.stderr)
                        else:
                            print(f"[Joystick] RELEASED → DataBroker + LED OFF")
                            q.put(False)
                            
                            # Send OFF command to LED
                            try:
                                s_led.write(b"OFF\n")
                            except Exception as e:
                                print(f"Failed to send OFF to LED: {e}", file=sys.stderr)
                        
                        last_btn = btn
                        
                    time.sleep(0.01)

        except (serial.SerialException, OSError) as e:
            print(f"Joystick/LED serial error: {e}. Reconnecting...", file=sys.stderr)
            time.sleep(1)
        except Exception as e:
            print(f"Joystick/LED loop error: {e}. Retrying...", file=sys.stderr)
            time.sleep(1)

if __name__ == "__main__":
    stop_event = threading.Event()
    client = None
    
    try:
        databroker_ip = os.environ.get('DATABROKER_IP', 'resiso-databroker')
        databroker_port = int(os.environ.get('DATABROKER_PORT', '55555'))
        
        print(f"Connecting to KUKSA databroker at {databroker_ip}:{databroker_port}")
        
        client = KuksaClientThread(config={
            'protocol': 'grpc', 
            'ip': databroker_ip, 
            'port': databroker_port,
            'insecure': True
        })
        client.start()
        
        print("Waiting for databroker connection...")
        time.sleep(2)
        print("✓ Ready to send signals")
        
        q = queue.Queue()
        
        t_db = threading.Thread(target=databroker_worker, args=(client, q, stop_event), daemon=True)
        t_db.start()
        
        t_gear = threading.Thread(target=handle_gear_yaml, args=(stop_event,), daemon=True)
        t_gear.start()
        
        main(q, stop_event)
        
    except KeyboardInterrupt:
        print("Stopped by user.")
    finally:
        print("Cleaning up resources...")
        stop_event.set()
        if 't_db' in locals(): t_db.join(timeout=1)
        if 't_gear' in locals(): t_gear.join(timeout=1)
        if client:
            client.stop()
        print("Goodbye.")
        sys.exit(0)
