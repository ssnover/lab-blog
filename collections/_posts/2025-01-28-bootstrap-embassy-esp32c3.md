---
layout: post
title: "Bootstrapping embassy-rs on ESP32C3"
date: 2025-01-28
---

I've been itching to write some software for hardware lately and since I have recently acquired an air purifier it seemed like an opportune time to try to get a sensor publishing data that I can use as the basis for automatically controlling that purifier. I've had [this board](https://www.sparkfun.com/sparkfun-indoor-air-quality-combo-sensor-scd41-sen55-qwiic.html) from Sparkfun for a little while which combines a SCD41 and SEN55 air quality sensors so that seems like a good confluence of motivation.

I also happen to have an ESP32C3 devkit sitting around and since this is a new project, that's going to be the subject of this post today. It's always a bit of a pain getting to that first LED blink on a new board with Rust, so much more than getting a hosted system to print "Hello, World!". That being said, it's still miles easier than getting an LED to blink on a new board with C or C++ unless you're using a lot of vendor tools and libraries that you'll probably have to toss once you're writing your real application.

One of the ways that the Rust embedded community tries to make this easier is to use templates so that you don't have to know about the nitty gritty linker details and extra command line arguments passed to some tools. You should use these if you want to get up and running quickly. They'll stay up to date as the template repository can be easily updated as the tooling changes.

I for some reason dislike the templates. Some of them feel overly opinionated and once your project is generated with them it can lock you into certain patterns. This probably stems from bad experiences with code generators from STMicroelectronics and Renesas which would inevitably start you off with a `main.c` full of tech debt with global variables galore, unreadable function signatures, lots of macros, and lots of stringly typed APIs where certain function names must *EXACTLY* match a function name deep in a linker file. These aren't valid complaints of any Rust template I've used to date. You should use them.

But if you're like me and have an instinctual need to avoid them, read on as I'm going to walk through exactly what the bare minimum needed project configuration is to get an LED to blink in Rust on an ESP32C3 with the embassy runtime. This will probably be out of date relatively shortly after I write this so I'll also include explanations which may provide clues as to how to solve emerging issues. [The final repository state to achieve a blinking LED is here](https://github.com/ssnover/matter-atmosensor/tree/1cab711ec221c10f7b55267ba5eef4964e217897).

## Crate Dependencies
After you run `cargo init` you'll have a typical hosted main which prints "Hello world" and a blank canvas in your project on which to start your adventure.

In this case the minimum set of dependencies looks like the below:
```toml
embassy-executor = { version = "0.7", features = ["task-arena-size-20480"] }
embassy-time = "0.4.0"
esp-backtrace = { version = "0.15.0", features = ["esp32c3", "exception-handler", "panic-handler", "println"] }
esp-hal = { version = "0.23.1", features = ["esp32c3", "log"] }
esp-hal-embassy = { version = "0.6", features = ["esp32c3"] }
esp-println = { version = "0.13.0", features = ["esp32c3", "log"] }
```

Let's walk through what they each provide. For each I pulled the most recent version from crates.io.

### embassy-executor
This one is pretty self-explanatory. It provides the actual async executor which powers the whole runtime. I pulled the `"task-arena-size-20480"` feature from the [examples in the esp-hal repo](https://github.com/esp-rs/esp-hal/blob/2ff28b14b58d3d726aafc0456143e5022b06f0e6/examples/Cargo.toml).
The feature decides the size of the array from which async tasks are allocated from. It basically acts as the stack memory for all of your tasks and if you run out of it your program panics. 20kB ought to be enough for now.

### embassy-time
Provides the `Timer` and `Duration` types which will be used to wait between state changes of the LED.

### esp-backtrace
This crate provides the panic handler for the system. In no_std programs, the user needs to provide a panic handler implementation. For this hardware, this crate provides it, along with an exception handler. I tried compiling without the `exception-handler` feature enabled and it still complained about a missing panic handler so it seems both are required. The `println` feature allows it to report a panic backtrace via the `esp_println` crate.

The documentation also notes that some extra arguments need to be passed at build time, we'll talk about that later.

This is also the first crate which requires the hardware specific feature `esp32c3`. Probably self-evident, but if you don't add this feature the crate will error at compile time to let you know you need to select one and only one hardware target.

### esp-hal
This crate provides the hardware abstraction layer for accessing the hardware peripherals. It also implements a number of the `embedded-hal` and `embedded-hal-async` traits on its peripherals which is handy for writing more generic implementations of your application.

The `log` feature allows some of its internals to log. I haven't actually seen any of these emitted at runtime, but it might save you from some debugging heartache to have it enabled.

Finally and importantly, it provides the linker script specific to your hardware.

### esp-hal-embassy
This crate primarily provides the bootstrapping of the executor. It provides a macro to wrap your main function in some boilerplate which launches it as an async task which the embassy executor can poll and it exports the linker name for the entrypoint. I'll dig into that later.

### esp-println
This crate adds a println function which is handy when you're first getting started as you're likely still plugged into USB and want to see debug output in your shell after you flash the program. It also sets up a global logger singleton (thanks to the `log` feature) so you can use the `log` crate and associated macros to write data on that channel.


That takes us through all the dependencies, although there's a little more to add. You'll pretty much always want to compile in release mode unless you have a JTAG debugger. The compile time logs will note this as there's a pretty big execution time penalty in a debug build in addition to code size penalty. I grabbed this profile configuration from the examples' `Cargo.toml` as well:

```toml
[profile.release]
codegen-units = 1
opt-level = 3
lto = 'fat'
overflow-checks = false
```

This tunes the overall binary size and the amount of optimization by setting the number of codegen-units, the optimization level, and the link-time optimization strategy (requires more RAM and time to link all of the object files but the linker can optimize more aggressively).

Overflow checks are for controlling the behavior when an integer overflow occurs. This has runtime cost so disabling has execution time and code size savings. It is just something to be mindful of when using unsigned types though as you'll likely never run the code in debug and see the runtime panic.

You can read up on all of the options available in the [Cargo reference document page on profiles](https://doc.rust-lang.org/cargo/reference/profiles.html).

## Build script
Most embedded systems projects in Rust require a build script as you'll need to tell the compiler and linker how to turn your compiled code into a binary that the microcontroller can actually execute. The linker file is [provided by one of the crates we linked in so](https://github.com/esp-rs/esp-hal/tree/main/esp-hal/ld/esp32c3) we don't have to write that, just a short and sweet build script in the project's root `build.rs`:

```rust
fn main() {
    println!("cargo:rustc-link-arg=-Tlinkall.x");
}
```

If you need to alter this for some reason (i.e. maybe you want to be able to keep a bootloader and two application images stored on the device), it's worth going to go find the original to modify.

## Cargo config
You'll next need to create a hidden `.cargo` folder with `config.toml` inside. This controls the default target and allows configuring what happens when you run `cargo run`.

```toml
[build]
target = "riscv32imc-unknown-none-elf"
rustflags = ["-C", "force-frame-pointers"]

[target.riscv32imc-unknonwn-none-elf]
runner = "espflash flash --monitor"

[env]
ESP_LOG="INFO"
```

Under `[build]`, you can specify the target which for this hardware is `riscv32imc-unknown-none-elf` (you'll also want to `rustup target add`) the toolchain for that target. You also specify any extra flags to the compiler. Here we go back to the documentation of `esp-backtrace` to grab two flags which should be passed to enable the backtraces to be formed and printed. The rustc documentation has some [information on this flag](https://doc.rust-lang.org/rustc/codegen-options/index.html#force-frame-pointers) but it's not particularly illuminating. This [StackOverflow post](https://stackoverflow.com/questions/74650564/is-frame-pointer-necessary-for-riscv-assembly) was a little more helpful. In particular, frame pointers seem to make it easier to unwind the stack which makes it clear why `esp-backtrace` would want that.

The next section just allows overwriting the `cargo run` behavior to use a custom subcommand. For this you'll need to `cargo install cargo-espflash` but then you can just use `cargo run` to build and flash your code to your device.

FInally, the `[env]` section allows setting some environment variables before invoking rustc and this one sets the minimum log severity for the `esp_println` logger functionality.

## vscode config
Add another hidden directory `.vscode` containing a `settings.json`  with contents like this:

```json
{
    "rust-analyzer.check.allTargets": false
}
```

This will tell rust-analyzer to stop trying to compile tests with `cargo check` which will always error for `no_std` projects and leaves an error on the line of source which specifies that it's a `no_std` project.

## main.rs

At long last, that brings us to the actual source code of the blinking application! The whole thing is pretty short luckily.

```rust
#![no_std]
#![no_main]

use embassy_time::{Duration, Timer};
use esp_backtrace as _;
use esp_hal::{gpio, timer::timg::TimerGroup};

#[esp_hal_embassy::main]
async fn main(_spawner: embassy_executor::Spawner) {
    esp_println::logger::init_logger_from_env();
    let peripherals = esp_hal::init(esp_hal::Config::default());

    esp_println::println!("Init!");

    let timer_group_0 = TimerGroup::new(peripherals.TIMG0);
    esp_hal_embassy::init(timer_group_0.timer0);

	let mut led = gpio::Output::new(peripherals.GPIO0, gpio::Level::Low);
	let mut led_state = false;
    led.set_level(led_state.into());

    loop {
        Timer::after(Duration::from_millis(5000)).await;
        led_state = !led_state;
        led.set_level(led_state.into());
    }
}
```

Let's start with the directives at the top:
```rust
#![no_std]
#![no_main]
```

The first tells the Rust compiler not to add in or link the Rust standard library. Instead the application will have access only to the `core` library which is a subset of the standard library.

The second tells the Rust compiler not to look for a function named `main` as the entrypoint. We will still end up with a function named `main` (though not where you expect), but it won't be visible to the Rust compiler, only to the LLVM linker.

Next we have our imports:
```rust
use embassy_time::{Duration, Timer};
use esp_backtrace as _;
use esp_hal::{gpio, timer::timg::TimerGroup};
```

The only thing particularly noteworthy here is the import of `esp_backtrace`. Its documentation notes that it should be imported in this way and this is required for the panic handler to actually link. I think otherwise the compiler tries to prune this crate.

Then we get to our main function, we're going to focus on this proc-macro for a moment:

```rust
#[esp_hal_embassy::main]
async fn main(_spawner: embassy_executor::Spawner) {
    // contents
}
```

This is the main thing provided by the `esp_hal_embassy` and it's doing a lot of work behind the scenes! It's worth running `cargo expand` to see what all it's doing:

```rust
async fn ____embassy_main_task(spawner: embassy_executor::Spawner) {
    {
        // contents
    }
}

fn __embassy_main(
    spawner: embassy_executor::Spawner,
) -> ::embassy_executor::SpawnToken<impl Sized> {
    const POOL_SIZE: usize = 1;
    static POOL: ::embassy_executor::_export::TaskPoolRef = ::embassy_executor::_export::TaskPoolRef::new();
    unsafe {
        POOL.get::<_, POOL_SIZE>()
            ._spawn_async_fn(move || ____embassy_main_task(spawner))
    }
}

unsafe fn __make_static<T>(t: &mut T) -> &'static mut T {
    ::core::mem::transmute(t)
}

#[export_name = "main"]
pub fn __risc_v_rt__main() -> ! {
    let mut executor = ::esp_hal_embassy::Executor::new();
    let executor = unsafe { __make_static(&mut executor) };
    executor
        .run(|spawner| {
            spawner.must_spawn(__embassy_main(spawner));
        })
}```

Note I elided a few attributes that are effectively just noise and the body of the main function. The first thing this macro does is take the body of our `main` function and put it inside a new function `____embassy_main_task` so this is no longer our entrypoint. As we keep scrolling, we see `__embassy_main` which appears to be doing the work of grabbing an appropriate size chunk of memory from the arena allocator and then spawning our main function as a task.

Then we get to the actual Rust entrypoint. This `__risc_v_rt__main` function is still not the actual first code that gets executed, there will be some instructions run as part of the RISC-V runtime and they're likely all assembly. This function gets an attribute `#[export_name = "main"]` which essentially aliases the symbol for the linker (which has no idea what programming language the application is written in, it just expects the entrypoint to be named `main`). This function constructs the embassy executor and spawns the main task.

So that's how everything is working under the hood. If you're still curious, you ought to have a much better starting point for exploring what all of those `embassy` functions are doing and how the runtime works now.

## main.rs body

I'm not going to go over every line of code in this as much of it is not specific to this hardware and will look familiar to many embassy projects.

The first thing that the main function does is initialize the logger singleton (configured by the environment variable at compile time). Then it grabs the peripherals struct. It's possible to configure the watchdog and the system clocks with the `esp_hal::Config` struct, but that's not necessary to blink an LED.

```rust
esp_println::logger::init_logger_from_env();
let peripherals = esp_hal::init(esp_hal::Config::default());
```

Then we initialize some additional data used by embassy: 
```rust
let timer_group_0 = TimerGroup::new(peripherals.TIMG0);
esp_hal_embassy::init(timer_group_0.timer0);
```

This appears to set up a wake up interrupt for the executor when the system is in low power mode and then also sets up a singleton timer which allows using the shorthand for blocking the current task (this is the timer it takes).

After that, you're free to set up your hardware to blink an LED. Mine only had an addressable RGB LED so I hooked up an LED and a resistor to one of my GPIO pins instead.

```rust
let mut led = gpio::Output::new(peripherals.GPIO0, gpio::Level::Low);
let mut led_state = false;
led.set_level(led_state.into());

loop {
	Timer::after(Duration::from_millis(5000)).await;
	led_state = !led_state;
	led.set_level(led_state.into());
}
```

## Check your build

After all that, you should be able to do a `cargo run --release` and see your application build then flash onto the chip. Watch that LED blink a couple times and then get back to the interesting part of your application!