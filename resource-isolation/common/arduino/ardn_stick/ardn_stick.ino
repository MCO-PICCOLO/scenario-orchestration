//*******************************************************************************
// Copyright (c) 2026 Contributors to the Eclipse Foundation
//
// See the NOTICE file(s) distributed with this work for additional
// information regarding copyright ownership.
//
// This program and the accompanying materials are made available under the
// terms of the Apache License 2.0 which is available at
// https://www.apache.org/licenses/LICENSE-2.0
//
// SPDX-License-Identifier: Apache-2.0
//
//*******************************************************************************

/*
  Joystick button detection - sends button state only
  Board: Arduino Uno R4 
  Component: Joystick Module
  Note: LED control is handled by ardn_led via serial bridge
*/

const int swPin = 8; // Joystick button
const unsigned long READ_DELAY_MS = 50; // ms

void setup() {
    Serial.begin(115200);
    delay(100);  // Short delay instead of blocking wait
    pinMode(swPin, INPUT_PULLUP);
    Serial.println("[STICK] Joystick Button Monitor Started");
}

void loop() {
    static int prevBtn = 1;
    int btn = digitalRead(swPin);

    // Button pressed (transition from 1 to 0)
    if (prevBtn == 1 && btn == 0) {
        Serial.println("1");
    }
    // Button released (transition from 0 to 1)
    else if (prevBtn == 0 && btn == 1) {
        Serial.println("0");
    }

    prevBtn = btn;
    delay(READ_DELAY_MS);
}
