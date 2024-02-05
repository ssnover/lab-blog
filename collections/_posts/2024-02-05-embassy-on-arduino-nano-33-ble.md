---
layout: post
title: "Running Embassy (Rust) on Arduino Nano 33 BLE"
date: 2024-02-05
projects: [megabit]
---

Just a quick one from some debugging I've done this morning. Some debugging that was rather obvious in retrospect, but nonetheless I couldn't find any mentions of it in a quick search.

I've been trying to flash some examples from [embassy-rs](https://github.com/embassy-rs/embassy) onto my Arduino Nano 33 BLE this morning. These examples primarily assume that you're using `probe-rs` to flash and they even include it as the cargo runner executable. However, the Arduino board is all flashed over USB using `bossac` and as a result the provided linker scripts just don't suffice.

I was able to flash the board with the `blinky` example after doing an objcopy to a binary format, however the board just sat and wouldn't blink the LED. After double checking on my NRF52840-DK board that there was nothing actually wrong with the ELF file being generated, I did some digging into the files packaged with Arduino.

I eventually stumbled upon the [linker script](https://github.com/arduino/ArduinoCore-mbed/blob/d63f3ab813c634697165cca39b9b3aff01cb59df/variants/ARDUINO_NANO33BLE/linker_script.ld)! Naturally, to account for the bootloader which makes it so that `bossac` can flash code, the `FLASH` region starts at `0x10000` or `64K`. I modified the [`memory.x`](https://github.com/embassy-rs/embassy/blob/f9cba604a51b81209efa1a81123928bb876f2033/examples/nrf52840/memory.x) provided with the `nrf52840` examples in embassy and was able to get it working. My final linker script looks like this:

```
MEMORY {
    /*
        Basic usage for the nRF52840_xxAA
        FLASH : ORIGIN = 0x00000000, LENGTH = 1024K
        RAM : ORIGIN = 0x20000000, LENGTH = 256K
    */

    /*
        Parameters for usage with bossac (Arduino Nano 33 BLE)
    */
    FLASH : ORIGIN = 0x10000, LENGTH = (1024K - 0x10000)
    RAM : ORIGIN = 0x20000000, LENGTH = 256K

    /*
        If using nRF52840 with nrf-softdevice S140 7.3.0, use these
        FLASH : ORIGIN = 0x00027000, LENGTH = 868K
        RAM : ORIGIN = 0x20020000, LENGTH = 128K
    */
}
```

I hope this makes it into some search engine results and saves someone some time!