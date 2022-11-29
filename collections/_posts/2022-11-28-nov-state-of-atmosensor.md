---
layout: post
title: "Current State of Atmosensor as of November 2022"
date: 2022-11-28 17:00:00 -0800
projects: [atmosensor]
---

I hit a pretty good milestone yesterday so it seemed opportune timing to write
something of a retrospective and goal-setting post for the project.

## What's Done So Far
![TUI Screenshot](/assets/img/20221128-atmosensor-tui.png)

I was happy to achieve a useful milestone yesterday where I was able to plug
in the atmosensor board via USB, pull a debug serial terminal, send a two-byte
application ping command, and receive a two-byte response from the board via
the debug terminal! That said, currently these applications are a mess. Both 
exist in single  `main.rs` files and are in heavy need of refactoring.

The `atmosensor-tui` application in particular is a *second* re-implementation 
of a tool that I had at a previous job for testing communications with a device 
that talked a simple binary protocol. At this point it feels justifiable to try 
to break that out into a library with a pluggable device transport so that
some others can benefit (and so I can stop maintaining a very similar source
project in two places).

For the microcontroller application things are even worse. I'm currently doing
COBS decoding and encoding inside of the ISR handler, though I've implemented
a simple interrupt-safe ring buffer in order to transport incoming packets to
the application context so that'll be an early refactor. I'd like to also start
splitting things into various modules per responsibility including having 
multiple tasks called from the main loop. That's not even getting started with
driver development! There are libraries available for the sensors that I
selected, even in Rust, however I noticed one issue: the construction of the
library struct instances take the I2C driver by move. Since both of my devices
are on one bus, this makes it impossible for me to use these libraries without
breaking some of the guarantees of Rust. I'm pretty puzzled by this since it
seems like it's common throughout the ecosystem and I'm not sure what the
usual solution is. I'm going to end up re-writing these drivers to take a the
I2C driver by reference on every method call. Unfortunate, but no other
workaround is immediately obvious.

As I develop the drivers I'll be quickly expanding the protocol for USB as this
is the easiest way to debug for me. I'm not expecting any scripts for generating
protocol structs soon as I can get by without that automation for a while, but
it's on my radar as it'd also make it easier to improve the TUI to give a preview
of the fields available after the two command bytes are typed in or other
possibilities like being able to browse over the previous binary commands in the
history to see what all of the data is wihtout having the memorize the protocol.

Once the firmware application is fairly stable, I'll be looking at developing
a proper PC host application for reading data and storing it somewhere, but
that still appears to be a ways off. I should probably start thinking about
designing an enclosure for this too...

![Atmosensor](/assets/img/20221128-atmosensor-hw.png)
