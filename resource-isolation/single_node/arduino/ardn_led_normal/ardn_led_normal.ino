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

//*******************************************************************************
// Project : LED Control for normal sleep-based scheduling
// Board : Arduino Uno R4 WiFi
// Description : Receives ON('1')/OFF('0') state from the container (sleep-based)
//               and sets the LED accordingly
//               This device runs without TIMPANI RT scheduling
//*******************************************************************************
#include <Adafruit_NeoPixel.h>

#define LED_PIN 6
#define N_LEDS 8

Adafruit_NeoPixel strip = Adafruit_NeoPixel(N_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

const uint32_t GREEN = Adafruit_NeoPixel::Color(0, 255, 0);  // green for the normal LED
const uint32_t OFF = 0;

bool ledOn = false;

void setup() {
    strip.setBrightness(100);
    strip.begin();
    showAll(OFF);

    Serial.begin(115200);
    while (!Serial) { }
    Serial.println("LED Normal Ready - Waiting for signals...");
}

void showAll(uint32_t c) {
    for (uint16_t i = 0; i < strip.numPixels(); i++) {
        strip.setPixelColor(i, c);
    }
    strip.show();
}

void loop() {
    if (Serial.available() > 0) {
        char c = Serial.read();
        if (c == '1') {
            ledOn = true;
            showAll(GREEN);
        } else if (c == '0') {
            ledOn = false;
            showAll(OFF);
        }
    }
    delay(1);
}
