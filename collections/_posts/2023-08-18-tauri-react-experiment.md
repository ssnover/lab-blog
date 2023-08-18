---
layout: post
title: "Experimenting with Tauri and React"
date: 2023-08-18
projects: [pkroam]
---

I've recently been tinkering with a project for which a TUI frontend was proving
to be not quite sufficiently convenient to develop as a demo and certainly not
user-friendly enough to use for a release of the project. This obviously called
for a GUI and previously I had made some barebones applications with `yew` and
compiled to WebAssembly, but I needed persistent storage and access to files in
the filesystem so that just wasn't going to cut it here.

I had heard of Tauri and the ability to design a frontend with web technologies,
but my previous forays into web had left me pretty frustrated. While there's
plenty of tutorials for writing applications of trivial complexity that worked
on all of the happy paths, you quickly run out of detailed documentation (or
at least, it's hard to find) once you venture out of the average web app. I had
a lot of trouble understanding the execution environment.

So, this time, while focusing on Tauri, I decided not to make a frontend web app.
I found a tutorial for making a web app with Typescript and React and followed it
to the point of establishing a good proof of concept: 
[a simple todolist app which allowed adding, deleting, and modifying todos](https://www.youtube.com/watch?v=knqz3_rPcKk).

Following along for about 90 minutes got me to a basic level of fluency with React
and I've had some exposure to Typescript before. The app just had one obvious 
problem: every time you refresh you lose all of your data. Since I'm also using
sqlite this seemed like a good excuse to tie it all together in a simple 
proof-of-concept.

I won't reiterate directions on how to set up your environment here as it exists
all over the internet in places that are updated more frequently by people more
knowledgeable in web technologies than I. That said, if you're interested in
running my code and tinkering, you'll need `npm` and `yarn` in addition to
all of the [dependencies Tauri's docs mention for your platform](https://tauri.app/v1/guides/getting-started/prerequisites/).

Instead, I'm just going to note all of the stumbling blocks I ran into while
they are fresh in my mind and maybe they'll help a fellow systems software
writer as they wade into a Tauri project of their own.

## Leveraging Rust
A major issue I ran into with just about every Tauri tutorial I could find was
that they seemed to be pretty much using Tauri as a bundling tool and executor
on desktop. I didn't see any mention of defining an API in Rust. Instead, Tauri
allows making a number of desktop environment APIs available to the frontend
application for operations like modifying files in the filesystem, manipulating
the windows, and executing other processes (among many other things).

This wasn't particularly hard to find in Tauri's docs, but the integration
especially with Typescript was a little annoying to manage.

First of all, on the Rust side, implementing an API for the frontend looks
like this:
```rust
#[tauri::command]
pub fn add_todo(todo_text: String, state: tauri::State<super::AppState>) {
    let todo = state.db_conn.lock().unwrap().add_todo(&todo_text).unwrap();
    state.todos.lock().unwrap().push(todo);
}

#[tauri::command]
pub fn get_todos(state: tauri::State<super::AppState>) -> Vec<Todo> {
    let todos = state.db_conn.lock().unwrap().get_todos().unwrap();
    todos
}

// ...
tauri::Builder::default()
    .manage(app_state)
    .invoke_handler(tauri::generate_handler![
        commands::add_todo,
        commands::get_todos,
    ])
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
```

All of the types in the API must be serializable and deserializable with `serde`
and application state can be passed to allow updating resources like a database
from within the function. Since these methods can be called in parallel, the 
types also need to be safe to access concurrently.

All of these handlers need to be passed to the `tauri::generate_handler` macro
to be available to the frontend.

On the frontend side, these commands can be accessed like this:

```typescript
export function add_todo(todo_text: string) {
  invoke("add_todo", { todoText: todo_text });
}

export function get_todos() {
  return invoke("get_todos").then((res: unknown) => {
    return res as Array<Todo>;
  });
}
```

This is where I hit my first real stumbling block. When Typescript calls a Javascript
API, the return value type is `unknown` which makes sense, but being new to this type
of interaction I had a hell of a time figuring out how to deal with it. It turns out
there is an `as` keyword that operates like Rust, although I didn't test to see what
happens when the cast is invalid.

Additionally, exposing my lack of understanding of how the fronend is supposed to execute
here, it returns a `Promise<T>` and there doesn't seem to be a way to `await` it like you
can with a `Future` in Rust. I thought that calling `then` would serve that purpose, but
that function *also* returned `Promise<T>`. Hence, calling `get_todos` looked like this:

```typescript
get_todos().then((todos: TodoData[]) => set_todo_list(todos));
```

## Managing the API
I pretty much just wrapped all of the calls to `invoke` in order to hide all of the details
above in the rest of the application. For only a handful of methods, this was not so bad.
For a larger application, this could grow to be quite a lot of boilerplate.

For keeping types in sync between Rust and Typescript, I used the `ts-rs` crate whereby I
was able to define all of my types in Rust and then generate the Typescript source. That
looked like this:
```rust
#[derive(Clone, Debug, Deserialize, Serialize, TS)]
#[ts(export, export_to = "../src/backend/models/")]
pub struct Todo {
    pub id: i32,
    pub todo: String,
    pub is_done: bool,
}
```

This allowed me to stick all of the exported types to be generated into a single
directory and maintain my sanity during development. One thing to note here is that
the exported source only generates when you call `cargo test` for some (probably
valid) reason. That detail tripped me up. The path supplied is also relative to the
root of the Cargo workspace, not to the source file.

## Spamming the API Calls
When I first ran the compiling application, I noticed immediately that my cooling fan
went wild and that the app was eating a ton of CPU. Additionally, modifications I
made to any of the items (like marking something done) were immediately overwritten.
The root cause here was the same: the main body of the application seems to run in
the render loop and so my `App` component was repeatedly hitting the database through
the `get_todos` endpoint. This makes sense, but took some searching to solve. The
equivalent problem comes up in React web apps as well when they're initializing
the application with an API call.

In order to get the application to just initialize once, I needed React's `useEffect`
API:
```typescript
useEffect(() => {
  get_todos().then((todos: TodoData[]) => set_todo_list(todos));
}, []);
```

On the other hand, this meant that every time I updated any of the application state
I had to modify the frontend data and the backend data. This could very easily
get out of sync. I probably want to come up with a solution whereby I can update the
todos on every change to them to reflect current backend state and also have some
kind of periodic timer that syncs the state as well just in case. That would also cut
down on the logic in the frontend, making it just a presentation and interaction layer.

## Development Environment
This was a small sticking point, but every time I ran `cargo tauri dev` it would first
execute such that a browser tab was opened like a normal React app, then it would
compile my Rust code and open a native window. The browser version of course did not
work or run because it had no access to the Tauri APIs. In order to fix this I installed
a package `cross-env` with yarn: `yarn add @cross-env`. Then I updated the 
`beforeDevCommand` value to `"yarn cross-env BROWSER=none yarn start"`. This fixed that.

## Conclusion
All in all, I was quite happy with the development experience and as I get more
comfortable with frontend web technologies I'm sure the experience will only get
smoother. If you're interested in tinkering with what I built, the code is here:
[tauri-taskify](https://github.com/ssnover/tauri-taskify).