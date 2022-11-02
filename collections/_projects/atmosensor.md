---
layout: project
name: "Atmosensor"
tag: atmosensor
repo: https://github.com/ssnover/atmosensor
summary: "Sensor endpoint for collecting CO2, P2.5, P10, and other environment data."
---

## Overview
This project is aiming to develop and build an open-source hardware design
with accompanying open-source firmware and software for retrieving sensor data
for reporting the data to a centralized server. Metrics being measured for
this project include CO2 ppm, P2.5 ppm, P10 ppm, temperature, atmospheric
pressure, and relative humidity thanks to a Sensirion SCD30 sensor and a Bosch
BME688.

## Components
Eventually, the project will grow to include:
* A schematic and printed circuit board design in KiCAD
* A firmware for reading sensors and reporting the data via USB in Rust
* A Rust program for polling and controlling the hardware and reporting the data into a time-series database.
* A browser-based display of some kind to show ranges of the time-series data.