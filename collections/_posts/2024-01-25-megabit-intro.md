---
layout: post
title: "My Sabbatical Project: Megabit"
date: 2024-01-25
projects: [megabit]
---

I've been on sabbatical for a little over a month now, but I've not been idle! When I decided that I was going to take some time off, I knew that I was going to want to take advantage of the time not just to relax, but also to pick up some new skills and build out a larger project to explore some technologies that I think are cool. In this post, I'll give a high level of what that project is going to look like.

## What is it?

The plan is to build a retro-style display with a 64x32 pixel screen which can display customizable images, notifications, or small pieces of information. What I'm imagining is almost entirely my take on the [Tidbyt, a cool little device which I get advertised constantly](https://tidbyt.com/). The device has an RGB screen with relatively large pixels and allows development of applications which render on the screen to show the time, the weather, sports game scores, and even nyan cat.

I am calling my take on this display Megabit, and it differs from the Tidbyt in a couple key ways:
* It will run Linux and all of the rendering will happen on the device
* Apps for the device will be compiled to WebAssembly instead of their Golang sandbox running their custom Starlark apps.

I came to these differences for a couple different reasons, but the principal one being: I really, really, really dislike when IoT devices can't function without an internet connection. And that's just how the Tidbyt is designed since the rendering happens in a cloud service. The other big reason is that this an excuse to learn Yocto and to explore WebAssembly as a sandboxed application environment.

## What's inside

For the hardware, I'm budgeting based around the fact that I don't have an income right now so I'm trying to use hardware I already had lying around. So no custom PCB or anything fancy. For Linux, I'll be running on a BeagleBone Black which has a 32-bit ARM processor and hopefully enough compute for this to be a success. I'll also be using the Arduino Nano 33 BLE as a coprocessor (actually runs an ARM nRF52840 microcontroller instead of AVR!); it will be in charge of running the screen based on USB-serial commands nominally, but also act as a Bluetooth device for loading WiFi network credentials onto the device on first usage.

The software components are still a little bit up in the air to some degree. Things I know I want to develop:
* A runner which executes WebAssembly apps for the express purpose of updating the screen.
* A coprocessor firmware which actually drives the screen updates.
* A simulator so I can test without the actual hardware.

Luckily, I've actually already finished the simulator! It's using a pseudoterminal to set up a pretend serial port and then forwards commands to a Yew app which runs in the browser and let's me visualize the LEDs on the Arduino, but also the screen and has a button like the device eventually will.

I made a start on the coprocessor firmware, with the intention originally to write it with ZephyrRTOS. After struggling along with some pretty lackluster documentation, atrocious C APIs, and implementing COBS from scratch around a ring-buffer, I hit a crash that I was having a pretty abysmal time debugging since I don't want to solder to the tiny SWD pins. Rather than have a miserable time with the firmware, I think I'm going to switch course and make use of `embassy` to write the whole firmware in Rust. This will just be more comfortable and is fun for the sake of the meme of writing the entire project completely in Rust.

I've not really made a start on the app runner other than exercising the basic controls of the simulator. I've been searching around for a way to run WebAssembly such that it could import custom functions which could drive the hardware and the leading candidate is `wasmi` right now which I've experimented with the basics of. Some unknowns here that I may or may not try to solve are things like being able to cancel execution and composing the resources that an app can access (i.e. permissions for sockets, filesystem, etc.).

There are also some stretch goals and aspirational bits for the project. I want to build this out like it was a real product, even though I have no intention of making it one. That means making a barely functional app at a minimum for downloading megabit apps onto the device from some kind of cloud "store". That would mean learning Kotlin and Android development which I've always wanted to do, but frankly just aren't super relevant. An alternative I'm considering is a web application which manages a lot of these things, but there's some considering to be done there yet.

## Where to find source code

I've made a top-level repository which will link to all of the component repositories as a directory of sorts. You can find that [here](https://github.com/ssnover/megabit). Naturally, all of the source will be on GitHub and I'll be referencing it here as I build out the project more.