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
// Project : Rotary Encoder Gear Controller (Resource Isolation)
// Board : Arduino Uno R4 WiFi
// Features: Rotation-based gear level (80-120) with LED feedback
//           Button press sends "0" or "1" based on rotation value
//*******************************************************************************
#include <Adafruit_NeoPixel.h>

#define ENCODER_A_PIN 5
#define ENCODER_B_PIN 6
#define ENCODER_BUTTON_PIN 7
#define LED_PIN 8
#define N_LEDS 8

Adafruit_NeoPixel strip = Adafruit_NeoPixel(N_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

const uint32_t RED = Adafruit_NeoPixel::Color(255, 0, 0);
const uint32_t YELLOW = Adafruit_NeoPixel::Color(100, 100, 0);
const uint32_t GREEN = Adafruit_NeoPixel::Color(0, 100, 0);
const uint32_t OFF = 0;

int temp;
int temprotation = 100;
int rotation = 100;

int getEncoderTurn() {
  static int oldA = 0;
  static int oldB = 0;
  int result = 0;
  int newA = digitalRead(ENCODER_A_PIN);
  int newB = digitalRead(ENCODER_B_PIN);
  if (newA != oldA || newB != oldB){
    if (!oldA && newA){
      result = -(oldB * 2 - 1);
    }
  }

  oldA = newA;
  oldB = newB;
  return result;
}

void showAll(uint32_t c) {
    for (uint16_t i = 0; i < strip.numPixels(); i++) {
        strip.setPixelColor(i, c);
    }
    strip.show();
}

void show(int rotation) {
    int numYellow = 0;
    int numGreen = 0;
    if (rotation == 80) {
        numYellow = 8; numGreen = 0;
    } else if (rotation >= 81 && rotation <= 86) {
        numYellow = 7; numGreen = 1;
    } else if (rotation >= 87 && rotation <= 92) {
        numYellow = 6; numGreen = 2;
    } else if (rotation >= 93 && rotation <= 97) {
        numYellow = 5; numGreen = 3;
    } else if (rotation >= 98 && rotation <= 102) {
        numYellow = 4; numGreen = 4;
    } else if (rotation >= 103 && rotation <= 107) {
        numYellow = 3; numGreen = 5;
    } else if (rotation >= 108 && rotation <= 113) {
        numYellow = 2; numGreen = 6;
    } else if (rotation >= 114 && rotation <= 119) {
        numYellow = 1; numGreen = 7;
    } else if (rotation == 120) {
        numYellow = 0; numGreen = 8;
    }
    for (uint16_t i = 0; i < numYellow; i++) {
        strip.setPixelColor(i, YELLOW);
    }
    for (uint16_t i = numYellow; i < numYellow + numGreen; i++) {
        strip.setPixelColor(i, GREEN);
    }
    for (uint16_t i = numYellow + numGreen; i < strip.numPixels(); i++) {
        strip.setPixelColor(i, OFF);
    }
    strip.show();
}

void setup() {
    strip.setBrightness(40);
    strip.begin();
    showAll(OFF);

    pinMode(ENCODER_A_PIN, INPUT);
    pinMode(ENCODER_B_PIN, INPUT);
    pinMode(ENCODER_BUTTON_PIN, INPUT_PULLUP);
    Serial.begin(115200);
}

void loop() {
    int change = getEncoderTurn();
    const int ROTATION_MIN = 80;
    const int ROTATION_MAX = 120;
    if (change != temp) {
        // limit rotation value range
        int newRotation = rotation + change;
        if (newRotation < ROTATION_MIN) {
            newRotation = ROTATION_MIN;
        } else if (newRotation > ROTATION_MAX) {
            newRotation = ROTATION_MAX;
        }
        if (newRotation != rotation) {
            rotation = newRotation;
            // Only update LED, no serial transmission
            show(rotation);
        }
        temprotation = rotation;
    }
    temp = change;

    static int prevButton = 1;
    int currButton = digitalRead(ENCODER_BUTTON_PIN);
    if (prevButton == 1 && currButton == 0) {
        // Button pressed - send value based on rotation
        if (rotation == 120) {
            Serial.println(1);
        } else if (rotation == 80) {
            Serial.println(0);
        }

        rotation = 100;
        showAll(OFF);
    }
    prevButton = currButton;

    delay(1);
}