---
layout: post
title: "Building GBA Games in Rust"
date: 2024-02-07
projects: []
---

![GBA Screen Recording of Conway's Game of Life](/assets/img/20240207-conway.gif)

A couple years ago I was interested in implementing Conway's Game of Life since it's pretty simple and seemed like a fun little project to sharpen my skills in Rust. I had a pretty major problem though: I needed a way to actually show the output of the simulation. Now, I'm not much of a web developer or desktop app builder so the idea of learning these technologies just to show a screen and add some user interaction was daunting. However, I have a lot of experience in embedded systems and fortuitously, I caught an announcement of a new release of the [`gba` crate](https://docs.rs/gba/latest/gba/)!

I put more than a thousand hours into my GameBoy Advance as a kid and have put many more into playing games on GBA emulators since then. It holds a lot of nostalgia for me and the thought of building a game for this hardware in 2022 felt especially novel.

In this post I won't actually be talking about Conway's Game of Life too in depth, I'll just give this brief explanation and if you want to know more go check out the [Wikipedia page](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life). In Conway's game of life, you have a 2D grid of boolean states. Given a set of states, you can evaluate a set of simple rules which decide if a given element is 'alive' or 'dead' in the next state. These simple rules give rise to surprising complexity (and are fun to look at).

For the remainder of the post I'll be talking about the basics of the device hardware, how to get button input, and how to put pixels on the screen. Some more advanced topics I'm not covering include: save files, audio, link cable communication, or sprites.

## Device Hardware
I mentioned in the introduction that developing for the GBA was interesting to me due to my background as an embedded system. And this system is about embedded as they come in the modern day. The GBA has no network connectivity, limited serial connectivity (with the link cable), and just 10 buttons in total. Not only that, but the hardware is extremely limited with no sign of an operating system or filesystem in sight.

Check out the [GBA's Wikipedia page](https://en.wikipedia.org/wiki/Game_Boy_Advance) for as many details as you could want, but some particular important specs for a would-be game developer are the CPU frequency of 16.78 MHz (about 1/200 the frequency of a modern desktop CPU), the screen size of 240 pixels wide by 160 pixels tall, and memory of 32 KB (expandable with memory on the cartridge). The screen refresh rate is also very important, it comes in just shy of 60 fps.

Finally, I'll note the processor: a 32-bit ARM7TDMI. Don't let the name fool you, this processor runs the ARM v4 instruction set which is positively ancient (not surprising when you consider its from 1994, older than the author of this very post!).

## Development
At this point you might be wondering how we can even make Rust compile for a processor as old as this. You can find a full list of [all platforms Rust supports in the rustc documentation](https://doc.rust-lang.org/nightly/rustc/platform-support.html). These are split into tiers where tier 1 targets work with very little setup and as you increase in number support varies (as do resources spent on making sure the tooling works). If you continue scrolling through the incredibly long list of supported target triples, you'll eventually come to `armv4t-none-eabi`, but we'll actually go further to `thumbv4t-none-eabi` at the direction of the `gba` crate's documentation. This will also require a `nightly` toolchain.

I won't specify the exact structure of your Cargo workspace and what dependencies you need to install here as it may change in the future. Instead take a look at the documentation for the `gba` crate which should get you sorted.

For actually testing your game, you'll naturally not be able to just run what comes out of `rustc`. So unless you happen to have a means of flashing the resulting ROM file onto a cartridge and also happen to be in possession of the original hardware, I recommend downloading an emulator. If you're concerned about the legality of emulators, just know that as long as you're running your own games, or other freely available ROMs made and shared by other developers, you are completely in the clear. On Linux I like to use `mgba-qt` as it has nice tools for attaching a gdb client or taking screen recordings.

## Application Structure

As above, this section isn't going to show any runnable code, mainly just talk about concepts and how writing programs for GBA is different than a desktop program. See the [examples](https://github.com/rust-console/gba/tree/main/examples) provided with the `gba` repository for specifics.

Unlike a typical program which is built for taking user input and showing something on a screen, GBA games are very resource limited and for the purposes of structuring an application we're RAM constrained. As such, we're not going to build this declarative tiered behemoth of structs describing UI elements and callbacks, we have to be simpler than that or we'll overflow the stack in a hurry. That also means you're not likely to find a convenient framework for composing a UI, it's just too expensive from a RAM and code space overhead perspective.

Instead, we're going to start at the very top level with a main function that looks something like this:

```rust

fn main() -> ! {
	init_some_hardware();
	init_some_software_state();

	loop {
		check_for_user_inputs();
		process_user_inputs_and_software_state();
		render_to_the_screen();

		VBlankIntrWait();
	}
}
```

Most of that is slideware and/or pseudocode, but it's still worth mentioning a couple things. First of all, this device has absolutely nothing useful to do if the program exits, as a result we return the special `!` type which indicates to Rust that this function should never ever exit. There is no X button in top corner to click when you're done playing a game, you just turn it off (with or without saving first).

Secondly, we use the function `VBlankIntrWait` in order to lock our main loop frequency to that of the refresh rate of the screen (~60 Hz). You don't necessarily have to do this, but you could conceivably render "too fast" such that a frame is overwritten before it even has a chance for it to be displayed to the screen. Note that this doesn't guarantee that the main loop actually runs at 60 Hz, it's totally possible for the code in the loop to run too slow and to miss the interrupt.

With the high level out of the way, let's get into some of those pseudocode functions.

## Detecting Button Presses
Since we're making a game (even one that runs itself like a cellular automata), one of the first things to think about is user input. Sometimes you want something to happen when a button is pressed or maybe only when it's held or released. You might need to build up a state machine to detect that the timing of the [Konami code](https://en.wikipedia.org/wiki/Konami_Code) was just right.

No matter what your application, the basic interface to the button states is the same from a software perspective: the button is either pressed when you read it's state or it's not. It's a boolean.

However, that's not the whole story! If you choose to poll the button states, as I've done in my game, there's some complications. If your game is healthily running at 60 fps, each run through your mainloop will be around 16 milliseconds. If you want a button press to trigger an action, you may not want it to trigger every single time you read the button state as pressed, and a player could easily press and release the button only after 40 milliseconds had passed, leading to that button reporting a `true` state for 2-3 cycles.

At an even smaller time scale, buttons are hardware and that means that behind that boolean state is a physical conductor being moved into place to conduct a signal. This not a clean state transition in the real world. As this [Hackaday blogpost](https://hackaday.com/2015/12/09/embed-with-elliot-debounce-your-noisy-buttons-part-i/) shows, a single button press can actually register as multiple presses and releases. If you're working on an emulator, you probably won't see this unless the author of that emulator was looking for extreme realism, but it's good to know about.

In order to potentially solve both of the above problems, I used a technique known as debouncing and then added statefulness around it. See the [source here](https://github.com/ssnover/game-of-life/blob/main/src/keys.rs). On each check of the keys, I check the register associated with the key states and track the amount of time since the last state change. By restricting the frequency with which the state can change, I prevent noise from hardware bounces. Additionally, by tracking previous state, I can return more information than `Pressed` or `Released` for button state. I do this with the `KeyState::change` function which can describe if the button has experienced a rising edge (a change from released to pressed) or a falling edge (a change from pressed to released). This way, I can detect only the change in the press of the A button so that I don't trigger the same action repeatedly.

If you scan through more of that source you'll notice that I'm not debouncing all of the keys. Specifically, I'm not doing so for the directional pad because I want to repeat an action (moving a cursor around the screen) so long as the button is held. In your game, you may have some buttons that should be debounced and others that aren't or maybe even buttons that are conditionally debounced.

One final note I have is that the responsiveness of your debounced buttons is dependent on your main loop frequency if you are polling. If an iteration of your main loop runs slow sometimes and fast other times, you'll notice in how quickly the game responds to inputs (and sometimes it might miss the input and not respond). A more robust means of checking inputs can be performed with hardware interrupts, which I won't discuss here but are explained at length in the [Tonc documentation](https://www.coranac.com/tonc/text/interrupts.htm).

### About Time and Timers
This isn't worth having it's own section, but since I mentioned them: there's no system time or way to sync with an external source of time on a GBA. So how can we measure how long something took or how long has passed since something happened?

Embedded hardware commonly has simple hardware called timers and in general they operate like this: there's a memory-mapped register somewhere that starts at `0` and periodically counts up by one. How quickly it counts is usually configurable by dividing the input frequency. The timer I'm using on the GBA starts at a frequency of the main CPU frequency at around 16 MHz, but can prescaled so that timers count slower than that. This gives a unit of time not in seconds, but in cycles.

## Putting Pixels on the Screen
With inputs out of the way, naturally we can jump to outputting to the screen (which simultaneously tests our input code).

The GBA has a few different ways of expressing control of the screen. The simplest and most intuitive (but not necessarily most performant) is video mode 3. In this mode you're simply writing in a region of memory where each pixel gets 2 bytes for color and every time the screen draws it simply copies what is in that memory region in order to show pixels on the screen.

"2 bytes?" you might be wondering. Modern devices pretty much universally have at least 24-bit color resolution where each channel of red, green, and blue get 8 bits. Not so on the GBA! The GBA uses an encoding known as RGB555 where each channel gets 5 bits. This saves a byte for each pixel which can make rendering 50% faster in this mode, which is good for us, but less good if you want to render a color rich display. In my case, I'm actually only using 3 different colors, so this is plenty.

The `gba` library defines a constant `VIDEO3_VRAM` which has methods for indexing into the memory region by the pixel's row and column number and then writing pixel colors like this:
```rust
VIDEO3_VRAM.index(row, col).write(Color::GREEN);
```

You'll find it convenient to build up abstractions in layers over this. For example, individual pixels are kind of small to act as cells or the cursor (at least for my old eyes), so I made each cell a 2x2 pixel.

Now, writing to every pixel in the buffer means writing to quite a lot of memory, especially if the program is going to do it at 60 fps on a processor only running at 16 MHz! The total number of pixels is 38,400 and if you're like me and trying to overwrite every single one every frame you might notice... Some strange stuff.

In my case, I was rendering every cell as alive or dead. Then I was rendering the cursor if the game was in Edit mode. Now, this initially seemed fine, but a curious thing would happen if I moved the cursor towards the top of the screen: it would disappear above a certain line! And not always on the same exact line of pixels! It turns out, I was overrunning my 16 ms timer for rendering each frame.

We'll talk about ways to mitigate this and do less work on each frame in the next section.

For a moment, I'll just mention that there are other video modes which are slightly more complicated to use, but they can be significantly faster by moving some of the rendering to the video processor instead of the CPU. Check out the resources mentioned in the conclusion for more information.

## We Need to Go Faster
All performance techniques are going to be highly specific to the game being made, but some are reusable in theory so I think they can be worth mentioning. Two of these I implemented and the third I thought about but it turned out not to be necessary.

The first and most obvious is that just because the screen is able to update at 60 fps that doesn't mean that your game actually has to run at that. In the case of cellular automata, the speed doesn't actually matter that much and you don't have to update the automata state at 60 Hz, it can be much slower. One way to do this would be with timer and counting the number of VBLANK interrupts. I just added a rolling counter so I step the automata state every N frames.

The second is an attempt to solve the problem mentioned above on how long it takes to overwrite the entire screen buffer. Much of the screen is actually not changing on every frame, but only small subsets of it are. If you can define a sensible way to mark subsets as needing to be redrawn, you can save a significant amount of time. In my case, those subsets were each row. I made an array of bits where each bit represented whether the row needed to be updated and marked rows as "dirty" during the automata step function. This saves a lot of time copying zeroes into regions of memory that are already zero.

The third is an extension of the above, but is more specific to the algorithm I'm displaying. It didn't end up being necessary and was complicated so I avoided it but it consists in determining bounding boxes of various subregions which have active cells. Since areas with no active cells cannot become spontaneously active, they can be ignored entirely. Meanwhile small subregions can remain active (and move slowly). In some cases where most of the screen is filled with dead cells, this should be even faster for rendering and would also reduce the time to compute the automata steps.

## Sources of Randomness
Since the game starts with a blank screen (where all cells are dead), it can be kind of daunting to use the cursor to draw out the initial state that you want to start with. Unless you're trying to build and observe some specific state in Conway's Game of Life, its cumbersome. One way to overcome this would be a way to seed the current state such that random cells became alive. Then you could run it and just watch it play out.

Unsurprisingly, there is no `/dev/random` file available here and without a standard library implementation there's no way to simply generate random numbers. Luckily, the `rand::RngCore` trait is `no_std` compatible and there are some existing implementations for freestanding environments like the one we're developing for.

A common algorithm for systems like this is based on taking an initial seed and calculating random data based on a number of bit [XORing and right shifting](https://en.wikipedia.org/wiki/Xorshift). The implementation of that algorithm is available in the crate [`rand_xoshiro`](https://docs.rs/rand_xoshiro/latest/rand_xoshiro/). Once seeded, it can continuously supply random numbers which we can use in our program. But where do we get our random seed?

In some embedded systems, an external parameter like sampling the noise on an analog pin is used to seed. The GBA doesn't have any analog pins though, so we need to rely on another external parameter: the user interactions. 

In this case, I actually reseeded every time the user presses the `Select` button which triggers the randomization. The seed is drawn from the current value of the system timer. This means that the seed will be different every time (as opposed to if you seeded at the beginning of the program). This is a popular approach: in the GBA Pokemon games the random seed is drawn from the timer a single time at the moment the user advances from the Start screen.

This approach is sufficient to give data that appears random, which is suitable for games. It is **NOT** suitable as a sole source of randomness for applications which need to be cryptographically secure. Going back to the example of Pokemon games: there's a whole class of manipulations based around seeding randomness because the creation of the seed is within control of the user!

## Conclusion and Getting Truly Advanced
With the above you should have enough information to get started writing small games for the GBA in Rust and experimenting with writing code for truly constrained devices! However, this is obviously far from the necessary knowledge to rewrite your favorite GBA titles from scratch.

If you want to learn more about the GameBoy Advance hardware and the available software interfaces, you'll find that a lot of that information exists and is documented in C. However, nothing should prevent translating that same code to an equivalent in Rust. The most helpful resource here was linked as appropriate above, but I'll call it out again in the conclusion here: the [Tonc guide by Jasper Vijn](https://www.coranac.com/tonc/text/toc.htm). It's pretty comprehensive with lots of examples and is invaluable even if you never write a single line of C.

As far as Rust resources, there's the [`gba`](https://github.com/rust-console/gba/tree/main) crate which I used here. It's great for getting started as the abstractions are very thin and the resulting code will look much more like the C equivalent. There's also the [`agb`](https://crates.io/crates/agb) crate which provides higher level abstractions than `gba` along with some additional tooling.

Finally, here's the [repo for my game of life implementation](https://github.com/ssnover/game-of-life/tree/main) which you should feel free to use as an example or even a base for your own game if you like.

Good luck and have fun making games!