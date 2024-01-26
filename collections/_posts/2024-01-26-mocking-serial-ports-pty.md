---
layout: post
title: "Mocking Serial Ports with Pseudoterminals"
date: 2024-01-26
projects: [megabit]
---

One of the very first tools that I want when I'm developing an embedded system is some kind of virtual device that I can test against without needing to bring a breadboard and piles of cables with me everywhere I sit down to develop. This even more so if most of the system's logic sits in on the host side above the firmware application. 

When developing the [simulator](https://github.com/ssnover/megabit-runner/tree/main/simulator) for Megabit, the natural point to simulate was the serial port, and I decided to do it in a way where I wouldn't need to make even a single change to the Linux host application.

This post covers how I used pseudoterminals in Rust to emulate a serial port, the pitfalls I ran into, and where I'll be investigating the next time I take a swing at this problem.

## What are Pseudoterminals

In Linux, you can pretty much always get a terminal if you can just find the primary UART pins. On a consumer product like a laptop, these are hidden away inside of an enclosure and made inaccessible. On development boards usually you can plug into some headers to get this shell interface. In this way, serial terminals and a shell are intrinsically linked on Linux and if you look into methods of mocking a serial port, you'll find that the same tool is used for virtual terminal connections as well: pseudoterminals.

At it's core, pseudoterminals are a two-sided serial port where both sides are available on the filesystem as character devices. Communication is bidirectional just like serial and there are syscalls for managing these devices which on Linux are generally handled by the `ptmx` device which is a multiplexer for these PTY (pseudoterminal) devices.

When you open a `pty` device on Linux, two file descriptors are handed back; one for the host side (called `master`) and one for the device side (called `slave`). The device side is typically a file like `/dev/pts/{0-9}` and the host side will be `/dev/ptmx`. When you write to one file, the data is available to be read from the other.

## Pseudoterminals in Rust

As far as I'm aware, this is a Linux-specific feature and to implement this I used the [`nix` crate](https://docs.rs/nix/latest/nix/). With the `term` feature enabled, you get access to the `pty` module, and a wrapper for the syscalls required for setting up a pseudoterminal successfully in the form of `nix::pty::openpty` which takes some arguments which may be relevant for piping virtual terminals together but not for serial ports. This API returns some file descriptors and you can use `nix::unistd::ttyname` in order to get the file paths for each of those descriptors. In particular, since you can't predict the path to the device side of the pseudoterminal, I let my program create a symlink to a consistent path with the device side path.

My implementation for construction of my virtual serial port looked something like this:
```rust
pub struct VirtualSerial {
    host_file: tokio::fs::File,
    _host_path: std::path::PathBuf,
    _device_file: tokio::fs::File,
    device_path: std::path::PathBuf,
}

impl VirtualSerial {
    pub fn new(symlink_path: impl AsRef<Path>) -> io::Result<Self> {
        let OpenptyResult { master, slave } = pty::openpty(None, None).expect("Failed to open pty");
        let serial = Self {
            _host_path: nix::unistd::ttyname(master.as_raw_fd()).expect("Valid fd for pty"),
            host_file: unsafe { tokio::fs::File::from_raw_fd(master.into_raw_fd()) },
            device_path: nix::unistd::ttyname(slave.as_raw_fd()).expect("Valid fd for pty"),
            _device_file: unsafe { tokio::fs::File::from_raw_fd(slave.into_raw_fd()) },
        };
        
        if symlink_path.as_ref().exists() {
            std::fs::remove_file(symlink_path.as_ref())?;
        }
        std::os::unix::fs::symlink(&serial.device_path, symlink_path)?;
        Ok(serial)
    }
}
```

I believe it is necessary to keep the file descriptors in scope and not closed, so I maintain their lifetimes in the `VirtualSerial` struct.

Once wrapped into a `tokio::fs::File`, you can do all of the reading and writing you expect on the `host_file`, including splitting it into `ReadHalf` and `WriteHalf`. However, I ran into some problems here personally.

## Issues with PTYs and tokio::fs::File

I did an initial test to make sure everything was working as I expected for reading and writing and then I integrated this into my full simulator program but with a pretty major change: I split the read and write halves and then used them in different tokio tasks.

In particular, I have one context which is taking in unencoded payloads of bytes via a channel, doing some work to encode them, and then writing the buffer out. So that task spends most of it's time awaiting on the channel reciever. The other context is reading from the pseudoterminal to take in commands from the host application with `AsyncReadExt::read_buf`. When it receives bytes, it decodes them and then writes those bytes to a channel. So it spends most of its time awaiting on the `ReadBuf` future.

An immediate problem I noticed was that the reader was starving the writer such that none of my writes were going through. After digging through the archives of the `tokio` Discord I came across mention that `tokio::fs::File` is not truly async in the same way as a socket, it actually locks access to the inner file when split and so the `ReadBuf` future was able to starve the writing of bytes.

After some messing around with the reader context, I eventually came to a solution that looked approximately like this:
```rust
let mut incoming_buffer = Vec::with_capacity(1024);
loop {
    if let Ok(Err(err)) = tokio::time::timeout(
        Duration::from_millis(5),
        reader.read_buf(&mut incoming_buffer),
    )
    .await
    {
        tracing::error!("Error reading from the pty: {err}");
    }

    if incoming_buffer.len() >= 3 {
        tracing::trace!("Got data");
        if process_bytes(&incoming_buffer[..]) {
            if let Err(err) = to_simulator.send(decoded_data).await {
                tracing::error!("Failed to send serial payload: {err}");
                break;
            }
            incoming_buffer.clear();;
        }
    }

    tokio::time::sleep(Duration::from_millis(5)).await;
}
```

On each iteration of the loop I combine the `ReadBuf` future with a timeout of 5 milliseconds and no matter which future completes first I add a sleep of 5 milliseconds with the hope of giving the writer task sufficient time to write out any payload it had waiting. This would add some latency, but certainly an acceptable amount for a simulator. I tested it with a terminal and verified I was now getting responses when I sent requests. I happily went on to develop more of my simulator.

Finally, I wanted to add a button to the frontend. When the button is pressed, the device will report a short message indicating that happened over serial so that the host application can process it. The host application does not poll for this, it's completely driven by the device side. And this revealed the failure of my attempt to fix the write starving above.

It seems that when the timeout occurs, it does not actually cause the `ReadHalf` to release the lock, because again `tokio::fs::File` is not truly async. This means the only way to get data written out is for the `ReadBuf` future to actually complete and if the host application is sitting and waiting for a button press (i.e. not sending messages), this actually gets stuck and the writer is starved again. 

Since this is a simulator and not production code, I settled on a hack: the host application sends a periodic `ping` payload which helps to free up the lock and allows async reports to get written out of the simulator. It is not super satisfying though and I'd like to eventually figure out a fix.

## Avenues to Explore

While chatting about my problem with the very helpful members of the `tokio` discord server, I was simultaneously doing some research on alternative options. I essentially came to two options: 
1. figure out some way to turn that `/dev/ptmx` file into a `SerialPort` that [`tokio-serial`](https://docs.rs/tokio-serial/latest/tokio_serial/) would be able to work with, or 
2. mock serial ports with something other than pseudoterminals

I've done some light checking through the APIs of `tokio-serial` and `mio-serial` and it's certainly not possible with the existing APIs as far as I can tell. It might be possible with sufficient hacking at the internals, but I'll probably not resort to that.

There's also another possible mechanism for mocking serial ports, a Linux kernel module called [`tty0tty`](https://github.com/freemed/tty0tty). It essentially allows setting up both ends on `/dev/tnt{0-9}` paths rather than going through the pseudoterminal multiplexer. It's installable from `apt`, but I'm most curious about investigating a way to determine those paths programmatically as I don't want to use shell scripts to manage setting up symlinks to paths before running programs. Still, it seems more promising than tearing into private fields and methods of existing crates.

Finally, while jotting down some of the above research I came across [`AsyncFd`](https://docs.rs/tokio/latest/tokio/io/unix/struct.AsyncFd.html) from tokio which is maybe a more generic wrapper than `tokio::fs::File` for wrapping a file descriptor into an async-compatible object. That will require further research still.

## Conclusion

I've got a hack in place, and that's sufficient for my use case for now minus the small annoyance in the corner of my mind when I'm using the simulator and know that it is held together with duct tape. I may revisit this some other day, but this is the solution I've got so far for mocking serial ports on Linux with Rust. Hope it helps!