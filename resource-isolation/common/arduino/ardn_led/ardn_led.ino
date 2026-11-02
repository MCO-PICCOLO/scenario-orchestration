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

#include <Adafruit_NeoPixel.h>
#define PIN 6
#define N_LEDS 8

Adafruit_NeoPixel strip = Adafruit_NeoPixel(N_LEDS, PIN, NEO_GRB + NEO_KHZ800);

const uint32_t RED = Adafruit_NeoPixel::Color(255, 0, 0);
const uint32_t GREEN = Adafruit_NeoPixel::Color(0, 255, 0);
const uint32_t OFF = 0;

void showAll(uint32_t c) {
    for (uint16_t i = 0; i < strip.numPixels(); i++) {
        strip.setPixelColor(i, c);
    }
    strip.show();
}

void setup() {
    strip.setBrightness(100);
    strip.begin();
    showAll(OFF);
    Serial.begin(115200);
    while (!Serial) { }
}

void loop() {
    if (Serial.available() > 0) {
        String cmd = Serial.readStringUntil('\n');
        cmd.trim();
        
        if (cmd == "GREEN") {
            showAll(GREEN);
        } else if (cmd == "RED") {
            showAll(RED);
        } else if (cmd == "OFF") {
            showAll(OFF);
        }
    }
    delay(10);
}
