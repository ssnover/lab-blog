---
layout: post
title: "Flashing a Zephyr Image to Arduino Nano 33 BLE"
date: 2023-12-18
projects: [megabit]
---

I've been following the [Getting Started](https://docs.zephyrproject.org/latest/develop/getting_started/index.html#flash-the-sample) guide for Zephyr and got to the point of testing flashing the blinky sample onto the microcontroller. Unfortunately, the native `west flash` did not just work. Looking at the output, the command being invoked by `west flash` is:
`/home/ssnover/.local/opt/zephyr-sdk-0.16.4/sysroots/x86_64-pokysdk-linux/usr/bin/bossac -p /dev/ttyACM0 -R -e -w -v -b /home/ssnover/zephyrproject/zephyr/build/zephyr/zephyr.bin`

Initially, this command failed with a message: `No device found on /dev/ttyACM0` and it seems for the Arduino Nano 33 BLE I'm using, this can be fixed by putting the device into bootloader mode by double tapping the reset button. It is in bootloader mode whenever the orange LED next to the USB port is pulsing.

After putting it in bootloader mode, I re-ran and got a different result: `SAM-BA operation failed`.

I did some testing with the Arduino IDE and found that it didn't have this problem, and extracted the command invocation from it, initially substituting in the Zephyr bossac and image paths: `~/.local/opt/zephyr-sdk-0.16.4/sysroots/x86_64-pokysdk-linux/usr/bin/bossac -d -p /dev/ttyACM0 -U -i -e -w build/zephyr/zephyr.bin` and got the same result.

Next, I tried with the bossac version packaged with Arduino and managed to get a success: `~/.arduino15/packages/arduino/tools/bossac/1.9.1-arduino2/bossac -d -p /dev/ttyACM0 -U -i -e -w build/zephyr/zephyr.bin `

Then, I added the `-R` flag to tell bossac to reset the board after flashing which causes the application image to boot after flashing:
`~/.arduino15/packages/arduino/tools/bossac/1.9.1-arduino2/bossac -d -p /dev/ttyACM0 -U -i -e -w -R build/zephyr/zephyr.bin`

Finally, I noticed that the Arduino IDE was able to program the board repeatedly without physical intervention and the firmware image runs (meaning it is no longer in bootloader mode). I noticed a `-a` flag which the help text describes as "erase and reset via Arduino 1200 baud hack", but I'm still not clear on how this flag needs to be used as I couldn't figure out a chain of commands to get it to work consistently. This invocation yields an error message `Failed to open port at 1200bps`: `~/.arduino15/packages/arduino/tools/bossac/1.9.1-arduino2/bossac -d -p /dev/ttyACM0 -a`

Just as a bit of debug info, the versions of bossac included with the Arduino IDE and Zephyr SDK respectively are:
* Arduino IDE `Version 1.9.1-17-g89f3556`
* Zephyr SDK `Version 1.9.1-14-g3532de8-dirty`
