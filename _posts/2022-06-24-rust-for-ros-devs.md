---
layout: post
title: "Guide to Rust for ROS Developers"
date: 2022-06-24 17:00:00 -0800
---
This is supposed to be an informal guide to act as a quickstart for developing in Rust as someone who is experienced in writing C++ for robotics. I’m hoping that this helps cut to the chase over some of the materials you might find online for getting started with Rust that can’t assume that you’re already familiar with the difference between stack and heap memory, what a compiler does, etc.

Installing a Rust toolchain on your system is very easy, but in case it changes I’ll just refer to docs that I know are constantly updated: [Installation](https://doc.rust-lang.org/book/ch01-01-installation.html).

# Hands-on Introduction
That being said, for a hands-on introduction to Rust, there is no better resource than the 3 projects that are guided through in The Rust Programming Language, available for free online. It’s a good baseline for getting familiar with the language syntax, idioms, and what’s available in the library. You can probably skip most other sections of the book as an experienced developer and instead use them as a reference.

The three projects are linked directly here:
1. [CLI Random Guessing Game](https://doc.rust-lang.org/book/ch02-00-guessing-game-tutorial.html)
2. [Simple grep Clone](https://doc.rust-lang.org/book/ch12-00-an-io-project.html)
3. [Synchronous HTTP Server](https://doc.rust-lang.org/book/ch20-00-final-project-a-web-server.html)

# IDE Support
CLion supports Rust and has a language server for syntax highlighting, auto-complete, etc. If you’re used to CLion for C++ development, this will likely be what you want.

VSCode has two useful extensions for working with Rust: rust-analyzer and Even Better TOML.

# Useful Libraries (Crates)
All of these can be found on [https://crates.io]() and their documentation can be found on [https://docs.rs]()
* **serde** and **serde_json** for serialization and deserialization
* **log** for logging
* **tokio** for various async things
* **tokio-modbus** for clients and servers for modbus
* **clap** for making command line applications
* **reqwest** for HTTP client
* **chrono** for timestamps
* **lazy_static** for declaring static lifetime variables that can be initialized lazily
* **async-trait** for making it possible to define async methods on traits
* **byteorder**, **num-derive**, **num-traits** for bit/byte logic
* **dashmap** for implementation of shared-state hashmap that is synced across threads

# Borrow Checker
The most infamous part of Rust that’s new relative to other mainstream languages is the infamous borrow checker. People on the internet who are new to Rust frequently express the feeling that they are “fighting the borrow checker”. This is because many patterns that people are used to in other languages tend to be difficult to prove correct/safe formally by the compiler.

The borrow checker is covered pretty well in the Book in chapter 4, but in short the borrow checker’s purpose is to ensure that one piece of code cannot invalidate the value of a variable while something else is referencing it. If you take a mutable reference to a variable, nothing else can take a reference to it until the mutable reference is no longer being used (the compiler can intelligently reduce the scope of references to make this less onerous). If you take an immutable reference, you can continue to take more immutable references, but you cannot take a mutable reference until all of the immutable references are out of scope.

There are several easy escape hatches when struggling with the borrow checker:
1. If you just want a copy of the object, you can derive the trait Copy and this will make it implicitly copyable. Almost all trivial datatypes implement this trait.
2. If you’re object is not trivially copyable, it makes sense to derive the trait `Clone`, which will make it so you can call `.clone()` on the struct. Many collections implement this and it’s analogous to a deep copy.
3. If you do not want to copy the object and need to share state, you can wrap your object in a `Mutex<T>` which will allow you to “copy” the object while wrapped in a mutex and then unlock the mutex if you need to modify the object. This makes the object `Sync`.
4. If you need share the state across threads, which is probably the most common use case, you can additionally wrap your object in an `Arc<T>` (atomic reference counted), making your object `Arc<Mutex<T>>`. This is a very common pattern. `Arc` makes the object `Send`.
5. The most analogous type to a `std::shared_ptr<T>` in Rust is an `Arc<Mutex<T>>`.

# Lifetimes
Another major feature of Rust is the existence of lifetimes as part of the type of references. If you take a reference to something, that reference will implicitly have a lifetime which is associated with it and you cannot pass that variable to a scope (or lifetime) larger than that of the object’s. This means that if you construct a variable in a function, take a reference to that variable, and try to return the reference the compiler will give you an error as the lifetime of the reference is bound to the lifetime of the temporary variable of the constructed object. This primarily comes up when passing references to structs for them to keep as member variables. This can be one of the nastier problems to circumvent and when many will resort to cloning. And that’s fine! C++ implicitly does a lot of cloning and unless you really need to share state or this cloning is happening in a hot loop it’s probably okay, even if it feels wrong.

Rust has first class support for asynchronous code which is very useful for networked or IO-driven workloads (like robotics). I have not worked extensively with async paradigms in other languages, but I’m of the understanding that Rust’s is considered to be different and non-traditional. Some things to note:

* There is no standard async runtime/executor: the two main ones are tokio and async-std
* Calling an async function does no work until await is called.
* You should not call blocking IO functions in async functions, as these can block all futures from executing (mutex locks are usually okay).
* Futures (async tasks) have the ability to be run on any thread by the executor, which means that lifetimes for objects borrowed by futures are strict (references generally need to be static, all shared memory needs to be sync).

Async is a big topic and can’t be properly covered in a paragraph or two here. The general workflow in an async program is to create a bunch of futures for the various asynchronous tasks that you want to run and then await on all of them. This can be done with a select, which will execute the futures until one of them returns, or it can be done with a join which will execute the futures until all of them return.

In a ROS paradigm, it likely makes sense to make subscriber callbacks behave as their own futures where they wait on a channel which delivers subscribed topic messages. Additionally, the main loop can behave as a future that awaits on whatever periodic data it needs. The main trick in async program design is figuring out the right paradigm for sharing data between tasks, its functionally very similar to figuring out data flow between ROS nodes.

Tokio maintains a pretty good tutorial on async here: [Tokio’s Async in Depth](https://tokio.rs/tokio/tutorial/async)

fasterthanlime has a blog post looking under the hood of how futures work: [Understanding Rust futures by going way too deep](https://fasterthanli.me/articles/understanding-rust-futures-by-going-way-too-deep)

# Additional Resources
Luckily, Rust developers tend to interact with the open source community and as a result there are a lot of high quality blog posts, books, videos, and other content floating around. Some people we’ve referenced in chats a lot include:

* fasterthanlime (runs blog [https://fasterthanli.me]())
* Jon Gjengset (author of Rust for Rustaceans, tokio developer, and puts up high quality YouTube videos on Rust)
* matklad (author of rust-analyzer and runs blog [https://matklad.github.io/]())
* Alice Rhyl (tokio developer, works on Rust in Android, runs blog [https://ryhl.io/]())

Community Resources:

* Rust Playground (like compiler explorer): [https://play.rust-lang.org/]()
* The Rust Programming Language (“The Book”): [https://doc.rust-lang.org/book/title-page.html]()
* Discord: people are pretty responsive to questions on the Rust official discord and the tokio discord
* r/rust: The Rust subreddit keeps a pinned post each week for small questions and there’s usually good discussions here as well
* The Rust Blog: [https://blog.rust-lang.org/]()
