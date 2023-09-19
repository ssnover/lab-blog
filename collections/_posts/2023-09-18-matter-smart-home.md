---
layout: post
title: "The Matter Protocol and Why I'm Excited About It"
date: 2023-09-18
---

I recently changed jobs and moved back into the domain of the smart home for my
day-to-day development. I'm currently working on and around Matter, which is a 
new protocol for smart home that's received quite a lot of industry backing in 
order to try to deliver on the vision of a smart home without the walled garden 
ecosystems which have dominated and confused consumers in the past.

If you haven't heard of Matter yet, I'm actually not too surprised. Despite 
it's release of the version 1.0 specification about a year ago, there haven't 
been an incredible amount of products out for it yet. Today I stopped by my 
local Best Buy and browsed through their Smart Home section. Not a single 
product on the shelf marketed support for Matter. I believe some of them did 
actually support it, but perhaps not at the time of launch (devices like the 
Hue bridge have added Matter functionality with a software update).

So what is Matter? It's essentially an evolution of the ZigBee data model (in 
fact they're specifications are somewhat shared and compatible) moved to 
IP-based networking transports. Whereas with ZigBee you needed to buy a device 
like the Hue bridge which had a ZigBee radio, the support for typical IP-based 
networks over Ethernet and WiFi lowers the barrier to entry quite a bit. The 
protocol also supports (and is intended primarily for) Thread, which is 
becoming increasingly common in invisible ways: most of those aforementioned 
ecosystems have quietly been adding hardware which allowed for Thread 
communication and got their devices certified as Matter controllers at the time 
of launch. Similarly, most modern phones can use Thread which means they can 
act as the entry point for configuring a device fresh out of it's box.

Now, I'm not particularly a fan of Thread if only because the number of 
implementations of the protocol are small (that I know of, only Google's 
official one) which makes working with it kind of a pain. However, since Matter 
also supports traditional transports as well (as long as they support IPv6), it 
lowers the barrier to developing open source devices which have a well-defined 
way to work together!

One of the most well-defined ways to do this is via Matter's concept of 
bridges. These are Matter devices which present a Matter interface and behave 
as a device, but are translating commands and data between Matter's 
representation and another protocol. This is how Philips Hue has decided to 
support Matter for their existing devices: simply implement a Matter bridge 
server as a software update on their existing hardware owned by existing 
customers, and now all of those devices can interface with other Matter devices.

Another Matter defined way for devices to interface is through bindings. While 
support for bindings in controllers and devices seems to be minimal at the 
moment, I think this will be a major way for open source devices to fit in and 
integrate in a way that's much less fragile and requiring significantly less 
custom implementation. Imagine a keyboard with some extra hotkeys which can be 
bound to trigger scenes on your bulbs. In the past, you'd have to consider what 
tyoe of lights you have: Lutron, Hue, Nanoleaf, etc? Then you'd use the API 
exposed by their bridge to control them. Upgrade your lights (or add another 
brand)? Then you get to rewrite your software. Matter could make that pain go 
away. This is going to be evolving as more controllers support bindings. 
Bindings are also fairly limited in what you can express to a client device 
(like a button keypad), so the behavior of the binding is highly dependent on 
what the device wants to do. This bolsters the case for custom open-source 
devices further.

I'm fairly excited with a couple projects for devices in mind. First, Lutron's 
Caseta does not currently implement a Matter bridge of any kind. I don't know 
if it ever will, but there's enough information about the LEAP protocol that it 
exposes out there to implement a Matter bridge that's hosted on a different 
piece of hardware. With the lack of button keypads out there for Matter 
currently, it'd be really nice to bring Lutron Pico remotes into the fold. 
Secondly, there's currently no device type defined for devices which simply 
view information and display it (or save it). This is another potential use 
case for bindings. With no device type defined, it requires a little more work: 
probably picking an arbitrary `u16` and hoping it never collides with an 
official one. Then you'll need your Matter controller to recognize it as a 
device which it can write bindings to; I'm using a SmartThings hub as my 
primary Matter controller which has the capability of loading custom Lua 
drivers which would make this possible.

All in all, I'm pretty excited for where Matter can go and how it can be 
leveraged by open source communities. If you're curious about the technical 
details of Matter, I recommend checking out the specifications (which require 
an e-mail address submission to the Connectivity Standards Alliance) and the 
implementations (both [the official one](https://github.com/project-chip/connectedhomeip) 
and a project that's somewhat less official in [the Rust implementation](https://github.com/project-chip/rs-matter)).