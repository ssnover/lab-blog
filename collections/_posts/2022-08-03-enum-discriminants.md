---
layout: post
title: "Exploring Enum Discriminants for Data-Carrying Enums"
date: 2022-08-03 17:45:00 -0800
---
I've been back-burnering thinking about how to simply represent a binary protocol in Rust with a relatively concise deserialization mechanism for quite some time. I frequently write binary protocols whereby data is packed and the data is not self-describing (like CBOR and JSON). So if I have a command carrying data I might have a string of bytes like these:

```
010089abcdef
010112341234
```

Where this would represent a 2-byte command identifier `0100` and perhaps the data is a 32-bit value or two 16-bit values. In order to know the format of the data, one would need to map the command id to a struct. These types can currently be represented in Rust as such:

```rust
#[repr(u16)]
enum CommandId {
    ExampleCmdA = 0x0100,
    ExampleCmdB = 0x0101,
    // ...
}

struct ExampleCmdAData {
    data: u32,
}

struct ExampleCmdBData {
    data: u16,
    data2: u16,
}
```

This is all well and good, and very similar to how I've represented this pattern in C++. However, it's totally possible to do this (warning slideware, noise omitted):

```rust
let input_payload: &[u8] = [0x01, 0x00, 0x89, 0xab, 0xcd, 0xef];
let mut cursor = std::io::Cursor::new(input_payload);
let cmd_id = CommandId::from_u16(cursor.read_u16()).unwrap();
assert_eq!(cmd_id, CommandId::ExampleCmdA);
let b_data = ExampleCmdBData::from_slice(&input_payload[2..]);
assert_eq!(b_data.data, 0x89ab);
assert_eq!(b_data.data2, 0xcdef);
```

This is wrong! And verbose! It'd be great if the type system could associate this data for us. It also has problems in that it's difficult to write a single function which returns the payload data deserialized. You have to store the data on the heap and make use of a trait, which makes it hard to access the interal data. We can at least leverage code generation in order to arrive at the matching if we could solve the problem of returning a generic piece of data, maybe with:

```rust
#[repr(u16)]
enum CommandId {
    ExampleCmdA = 0x0100,
    ExampleCmdB = 0x0101,
    // ...
}

enum CommandData {
    ExampleCmdA(ExampleCmdAData),
    ExampleCmdB(ExmapleCmdBData),
}

impl CommandData {
    fn from_slice(data: &[u8]) -> Self {
        let mut cursor = std::io::Cursor::new(input_payload);
        match CommandId::from_u16(cursor.read_u16()).unwrap() {
            CommandId::ExampleCmdA => 
                CommandData::ExampleCmdA(ExampleCmdAData::from_slice(&data[2..])),
            CommandId::ExampleCmdB => 
                CommandData::ExampleCmdB(ExampleCmdBData::from_slice(&data[2..])),
        }
    }
}
```

This is pretty easy to generate to get this correct, either with a separate code generation tool or a macro. But it still feels silly that it's this verbose. As your protocol grows, you'll also run into the issue that [large match statements use a lot of stack space](https://github.com/rust-lang/rust/issues/34283), particularly problematic if you're trying to parse your binary packet on an embedded system with limited resources or perhaps a WebAssembly frontend application.

Well I recently came across this [merged RFC for safely passing data-carrying enums over FFI](https://rust-lang.github.io/rfcs/2195-really-tagged-unions.html). At the very bottom in the Future Extensions section is a harmless little bullet point: "Allow specifying tag's value: `#[repr(u32)] MyEnum { A(u32) = 2, B = 5 }`". This is exactly what's needed to simplify the above!

```rust
enum CommandData {
    ExampleCmdA(ExampleCmdAData) = 0x0100,
    ExampleCmdB(ExmapleCmdBData) = 0x0101,
}
```

If you try to compile the above, you'll find that the compiler helpfully points you to an [open issue which has implemented the feature](https://github.com/rust-lang/rust/issues/60553), but it is not yet stable. You need this flag to enable it:

```rust
#![feature(arbitrary_enum_discriminant)]

enum CommandData {
    ExampleCmdA(ExampleCmdAData) = 0x0100,
    ExampleCmdB(ExmapleCmdBData) = 0x0101,
}
```

I'll be keeping an eye on this feature for when it's stabilized. I'm hoping that it leads to being able to use `serde` to avoid generating the switch statements above in source code, although it may end up resulting in the same thing. It'd be nice to leverage `serde` for that though.