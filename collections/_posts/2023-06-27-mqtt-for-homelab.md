---
layout: post
title: "Using MQTT for IoT and Homelab Projects"
date: 2023-06-27
projects: [homelab]
---

I recently moved across town and unearthing some of the hardware I've purchased
but not found a use for ignited a spark of inspiration for tackling some Internet
of Things type projects in order to help the new place feel more like home. I
created a minimal setup on a single server in my last place, but since I decided
to incorporate some old laptops that were sitting and gathering dust, I started
thinking about easy ways to network applications between each other and to deploy
applications across multiple servers. What I arrived at is MQTT; I'll be giving an
overview of what MQTT is and how I'm using it in the article that follows!

# What is MQTT?

First of all, what is it? I'm not going to really delve into the history since its
not relevant and it's readily available if you check your friendly local search
engine, but in short MQTT (stands for Message Queuing Transport Technology) is 
something of a single bus over which multiple applications can talk, with a separate
channel for each "topic". For example, I might have a topic `co2_ppm` over which one
application, like a sensor, publishes CO2 data and another application, like a
database writer, subscribes to that data. The format of the data is raw bytes, so the
sender and receiver need to agree on how the contents should be formatted in addition
to the name of the topic (`co2_ppm` in this case).

How does this data get sent? Architecturally, we have three processes in the example
above: a publisher, a subscriber, and the important one being the intermediate broker.
The broker acts as the go between for every single application in the MQTT network.
When a publisher wants to publish data, it connects to the broker and tells it the 
name of the topic it wants to publish on before it starts publishing data *directly
to the broker*. When a subscriber wants to listen for data, it in turn connects to
the broker and requests that when the broker receives data on a topic that it kindly
forwards that data to the subscriber. By this way, any CO2 data that needs to be
communicated is sent to the broker and the broker sends it to the subscriber. This
flow is known as a pub-sub architecture.

At a glance, this sounds kind of inefficient. Why not just have the subscriber host
a TCP server and let the publisher connect? Well this is certainly a solution in the
simple example I brought up above, but it has some complications:
* What port should the subscriber host its TCP server on?
* If the subscriber needs to be updated, should the publisher application be stopped
and then restarted or should it just continually try to reconnect?
* Should the subcriber accept multiple clients at the same time?

The problem grows if we grow the problem a little bit: Maybe we add a second sensor
to measure CO2 in another room and a small little display hooked up to a Raspberry Pi
that wants that data. Now we might need the publishers to each connect to two servers
which means updating the application. Now what happens when one of the servers goes 
down? Crashing until all servers are available means more downtime.

MQTT with the broker solves many of these problems. The broker can process a high 
number of topics, from a high number of publishing applications, and pass it on to a
high number of subscribers. Each application just needs: a socket address (IP and 
port) for the broker, a topic name, and a serialization format. This makes 
applications easy to keep small and simple and makes the entire network of 
applications relatively easy to maintain.

# How am I using MQTT?

Since I've got a few servers on my network, I've selected a single one to host
the broker. With any additional application which I want to emit data or consume
data (or both), I can deploy to any server or even just to an embedded device (the
ESP-IDF library has built-in support for MQTT).

Presently, I've started my deployment small. I've got CO2 data being published
from my atmosensor client application which is making its way into the InfluxDB
via MQTT and Telegraf instead of the direct InfluxDB writing that was happening
before. I've also got an application utilizing the Eero API to check whether my
phone is on the network in order to act as a proxy of whether I'm home or not.

My use of this will evolve as it scales, but I'm intending to keep a single 
git repo which maintains all of my nodes with a list of topics in a single place
which should prevent accidentally mistyping a topic and the data not going through.
Since I write my applications in Rust, this approach has the added benefit of keeping
my serialization common. All of the datatypes I send over the wire via MQTT can be
Rust structs with serialization and deserialization by `serde` and `serde_json` and
since all of the applications are built with them, they should always be in common.
I'm currently using the [paho-mqtt crate](https://github.com/eclipse/paho.mqtt.rust)
for client support and I noticed they added support async in the last release. If
Rust isn't your cup of tea for some reason, there are mature libraries for MQTT in
every mainstream language including [C and C++](https://github.com/eclipse/paho.mqtt.c), 
[Python](https://github.com/eclipse/paho.mqtt.python), and [Go](https://github.com/eclipse/paho.mqtt.golang).

I'm also looking at moving `atmosensor` over from a USB implementation on the STM32
to an implementation on the ESP32-C3 which looks to have great support for Rust as
well and which allows me to leverage WiFi to make the placement of the sensor more
flexible! You can see my prototyping of that [here](https://github.com/ssnover/atmosensor/blob/bc70286ed1dc231e309f024e8f55aaf3130fdd63/atmosensor-esp32/src/main.rs).

For a broker, I'm using the Eclipse Mosquitto broker which is actually open source
and [maintained on GitHub](https://github.com/eclipse/mosquitto). This means the
broker and client implementation I'm using are both written in C and while they do
seem to work well, I'm still looking at alternatives written in Rust mainly because
I think the barrier to entry to developing systems project with Rust is lower and as
a result a project implemented in Rust will be healthier (in addition to all of the
usual benefits of Rust which are really relevant for networked systems).

I'll post a little about how I'm deploying these applications later on. In part
because it's a complete mess right now and in part because it's a big enough topic
that it deserves its own post outright!

# Integration with other IoT Services

While my goal personally is to develop a lot of my own applications in order to
try out different ideas and learn new technologies, a lot of people just want the
darn thing to work. Luckily, MQTT has widespread support in the ecosystem. There is
a [component for HomeAssistant](https://www.home-assistant.io/integrations/mqtt/) and
a [binding for openHAB](https://www.openhab.org/addons/bindings/mqtt/).

Eclipse hosts [their own broker for debugging purposes](https://test.mosquitto.org/). 
There are also cloud implementations from all the major providers including AWS IoT
Core, Azure IoT Hub, and GCP Cloud IoT Core.

# Getting Started

If you're interested in getting started tinkering with MQTT, the easiest way is 
probably to choose your language's client library and try to send some "Hello, world!"
messages over the test server. You can see some very simple examples for Rust in
the `paho-mqtt` crate's [example directory](https://github.com/eclipse/paho.mqtt.rust/blob/develop/examples/topic_publish.rs).

If you're on a Linux system, I find that the `mosquitto_sub` and `mosquitto_pub` tools
are invaluable for debugging a running network. They're available as apt packages on
Debian-based distros and likely the equivalent on other distros. Or you can build the
`mosquitto` [source code](https://github.com/eclipse/mosquitto).

# More Reading

I really only gave an overview of MQTT and the most straightforward use cases here. If
you're interested in learning more, these resources might be a good starting point:
* [Eclipse's Paho project page](https://wiki.eclipse.org/Paho) - for an additional list of links
* [Article by Steve's Interet Guide](http://www.steves-internet-guide.com/mqtt-works/) - for another explanation of the protocol with diagrams
* [Article by International Society of Automation](https://blog.isa.org/what-is-mqtt-and-how-can-industrial-automation-companies-use-it) - gives a little more of the industry context of why this technology is useful