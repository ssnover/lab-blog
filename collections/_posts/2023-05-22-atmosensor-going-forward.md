---
layout: post
title: "Atmosensor MVP, and Going Forward"
date: 2023-05-22
projects: [atmosensor]
---

After several flurries of on-and-off development over the last several months,
I actually managed to arrive at a minimum viable implementation for the main
thrust of the Atmosensor project! It's not pretty right now, but that's also
kind of the point!

Just as quick recap of what's actually implemented so far:
1. A schematic and PCB design for a board which queries data from a sensor over
I2C and can be queried in turn over a USB serial port.
2. A [firmware in Rust](https://github.com/ssnover/atmosensor/tree/77ca9d8f50d82b906bc9abff5b472a62e4fd171e/atmosensor-fw) 
that facilitates the above data transfer on the STM32 microcontroller.
3. A [client in Rust](https://github.com/ssnover/atmosensor/tree/77ca9d8f50d82b906bc9abff5b472a62e4fd171e/atmosensor-host-apps/atmosensord)
that runs on my home server, querying data and tucking it into a local InfluxDB
instance.
4. Various tools that support the development of the above.

The end result of all of the above is a dashboard with plots like this:
![Atmosensor Dash](/assets/img/20230522-atmosensor-dash.png)

But! That does not mark the end of the project, at least in my mind. For one
thing, I actually have more data that can be pulled from the SCD30 sensor that
is measuring the CO2 concentration and I have a QWIIC connector on there which 
can connect the I2C bus to additional sensors. This project also isn't about
collecting the data for its own sake, it'd be nice to display this data in a
more convenient form factor that an Influx dashboard in a way that can inform
decisions like opening the windows and turning on fans.

In addition to all that, CO2 levels (and other data I can collect) are not
actually a big worry for me. Part of the impetus for the atmosensor project was
to build something I can continue to hack on over time and try out different
ideas for structuring applications and to try out new types of software outside
my wheelhouse entirely. The Influx dashboard looks nice, but it is a great
opportunity to try out a less trivial Yew application which essentially does
the same thing (though maybe safer to expose outside my network and not 
requiring authentication to my Influx server).

With that said, some projects I have more immediately in mind:
* Try a new version of the firmware that utilizes [`freertos-rs`](https://docs.rs/freertos_rs/latest/freertos_rs/) 
bindings or even a Rust-based RTOS like [`drone`](https://docs.rs/drone/latest/drone/).
* A [Yew](https://yew.rs/)-based dashboard for displaying the data.
* I actually have all the parts to make my own version of these [dot-matrix
widget displays](https://tidbyt.com/) and it'd be cool to display my sensor
data on there (maybe with a prompt to open a window).
* Break out parts of the `atmosensor-tui` into a library which allows anyone
who implements a trait or two to have a handy TUI of their own. This would also
make it easier for me to implement a TUI which communicates with the already
running `atmosensord` application on my server to see what is being sent and
received and allow me to remotely debug on my laptop.
* I'd like to add a request ID to the serial protocol to make it possible to
associate requests and responses over the wire.
* Dovetailing off the previous, I'd like to experiment with a nicer wrapper
over the `atmosensor-client` with methods that can be awaited for a matching
response, i.e. `client.request_co2_data().await` which would poll until a
response with the CO2 data or an error is received. I'd could do a sloppy
version of this now, but it needs request-response association to be done right.
* I'd like to try out `tokio-tracing` and log aggregation services. Currently
all of my logs are just being printed out into `stdout` which is not ideal if
my server reboots and there was an important message in the output.
* A mock implementation of the firmware device for testing application code
against.
* I got stumped trying to get this to run in docker, something was wrong with
USB communications specifically, so it'd be great to figure that out and do a
proper deployment pipeline for updates via a container.
* A firmware bootloader application so I can deploy firmware updates remotely
as well.
* Maybe try to write a set of python bindings for the `atmosensor-client` crate
with [`pyo3`](https://pyo3.rs/).

At my current rate, the above list ought to keep me busy until... 2030...? It's
a long list and there's lot of interesting experiments on there to say the
least. I'm hoping that as the implementation of these get to be less trivial
and more specific that I can turn some of these into blogposts in their own
right. We'll see what the future holds!