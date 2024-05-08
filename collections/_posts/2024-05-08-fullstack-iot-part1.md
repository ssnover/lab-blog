---
layout: post
title: "Developing Full-Stack Rust Applications with WebSockets, Part 1"
date: 2024-05-08
projects: [megabit]
---

This post will be the first in a multi-part series covering the development of local web apps with a focus towards the type of application you might need for a connected home IoT product. In this series, I'll be walking through standing up a Rust binary which runs on a Linux device and hosts a web app which can be used for configuration of the device or visualization of the data. We'll be making use of major Rust libraries like [`yew`](https://yew.rs/), [`tokio`](https://tokio.rs/), and [`axum`](https://tokio.rs/blog/2021-07-announcing-axum).

However in this post, the goal will just be to get an HTTP server up and running with an endpoint for issuing a health check and an endpoint for establishing a WebSocket. We'll use a command line tool to verify we can send and receive packets on the [WebSocket transport](https://www.rfc-editor.org/rfc/rfc6455).

## The Workspace
Here's a little bit of the lay of the land. There's a couple conventions I use for setting up a project in order to make writing all of the code in one VSCode project convenient and setting up CI in one repository easy.

The high level of the repository will look something like this
```
$ exa --tree -a iot-server/
iot-server
├── .git
│  └── ...
├── .vscode
│  └── settings.json
├── backend
│  ├── Cargo.toml
│  └── src
│     └── main.rs
└── frontend
   ├── Cargo.toml
   └── src
      └── main.rs
```

Don't worry about the contents of the `frontend` project right now, we'll get into that in Part 2.

First, we'll make some changes to `.vscode/settings.json`. The Rust Analyzer plugin will automatically select a `Cargo.toml` and build the project for the host architecture, but we can override it which will be convenient later while working on the frontend.

Set it up to look like this:
```
{
    "rust-analyzer.check.allTargets": false,
    //"rust-analyzer.cargo.target": "wasm32-unknown-unknown",
    "rust-analyzer.linkedProjects": [
        // Uncomment for the project you're actively working on
        "backend/Cargo.toml",
        //"frontend/Cargo.toml",
    ],
}
```

This will set Rust Analyzer to build the backend for the host architecture. Later, when we start working on the frontend web app, we'll be compiling for WebAssembly as the target. You can uncomment the target setting and change the linked project, then reload the Rust Analyzer server to get code completion.

## Goals for the Backend
Let's talk about the goal for the backend by the end of this post. We'll be using `tokio` and `axum` to standup an HTTP server with two endpoints: one for a health check which can be used remotely to check the server is up and one which upgrades to the WebSocket connection.

### Dependencies
Rather than introduce dependencies piecemeal throughout the post, here's all of the dependencies that you'll need for this chapter. Add them to the `Cargo.toml` for the backend project.

```toml
[dependencies]
anyhow = { version = "1" }
async-channel = { version = "2.1" }
axum = { version = "0.7.5", features = ["tokio", "ws"] }
clap = { version = "4.4", features = ["derive"] }
futures-util = { version = "0.3" }
tokio = { version = "1.0", features = ["full"] }
tower-http = { version = "0.5.0", features = ["fs", "trace"] }
tracing = { version = "0.1" }
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
```

You can verify all of those pull and compile with the default generated `main.rs` that cargo will generate and then compilations will be fast as you work.

## Servicing Health Checks
We'll start off as simple as possible, while keeping a mind for the future. We'll be setting up the HTTP server with just a single endpoint: the health check. All this endpoint needs to do is return `200 OK` when queried. This serves as a handy way to check on the service remotely.

Starting off with our entry point in the `main` function:

```rust
use axum::{extract::ConnectInfo, response::IntoResponse};
use std::net::SocketAddr;
use tower_http::trace::{DefaultMakeSpan, TraceLayer};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let port = 8080;

    serve_web_app(port).await?;

    Ok(())
}
```

First we'll set up [`tracing`](https://tokio.rs/tokio/topics/tracing) to report info level logs, define a value for the port we'll be listening on and immediately entering an async function for serving the web app, `serve_web_app`.

The meat of the implementation is in this little `serve_web_app` function:

```rust
async fn serve_web_app(port: u16) -> anyhow::Result<()> {
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(addr).await?;

    tracing::info!("Listening on {}", listener.local_addr()?);
    let app = axum::Router::new()
        .route("/health_check", axum::routing::get(handle_health_check))
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(DefaultMakeSpan::default().include_headers(true)),
        );
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await?;

    Ok(())
}
```

We'll setup the server to listen on TCP on the specified port, specifically using IP address `0.0.0.0`, as opposed to `127.0.0.1` ([what's the difference?](https://superuser.com/questions/949428/whats-the-difference-between-127-0-0-1-and-0-0-0-0)). This allows the server to be accessible to other devices on the network, which you'll want on the production deployment for an IoT device since you're likely accessing it from a different device.

The `axum::Router` uses the builder pattern to build up a router. We'll just start with our health check endpoint which will be serviced with a handler function called `handle_health_check` (shown later). Then we'll add a layer with a trait from the `tower_http` crate implemented on `axum::Router`. This plugs it into the `tracing` infrastructure we set up in `main`. Additionally, any `tracing` logs made in the handler functions will get integrated into the larger spans which can be handy for debugging.

Finally, we plug the router into our TCP listener to run the app. The `into_make_service_with_connect_info` method gives access to peer address of the connection to the handler which I find is useful for debugging as well.

Finally, and perhaps rather undramatically, we get to the health check endpoint, which has a very simple scope after all the boilerplate is setup:

```rust
async fn handle_health_check(ConnectInfo(addr): ConnectInfo<SocketAddr>) -> impl IntoResponse {
    tracing::info!("Received health check from address: {addr}");
    ()
}
```

And that's all that is required to get started! Run it and access the endpoint either with `curl` or your web browser and you should see some output like this:

```sh
$ RUST_LOG=debug cargo run
    Finished dev [unoptimized + debuginfo] target(s) in 0.07s
     Running `/barge/cargo-target/debug/iot-server`
2024-05-06T21:15:02.745430Z  INFO iot_server: Listening on 0.0.0.0:8080
2024-05-06T21:15:06.308944Z DEBUG request{method=GET uri=/health_check version=HTTP/1.1 headers={"host": "127.0.0.1:8080", "user-agent": "curl/7.81.0", "accept": "*/*"}}: tower_http::trace::on_request: started processing request
2024-05-06T21:15:06.309026Z  INFO request{method=GET uri=/health_check version=HTTP/1.1 headers={"host": "127.0.0.1:8080", "user-agent": "curl/7.81.0", "accept": "*/*"}}: iot_server: Received health check from address: 127.0.0.1:58252
2024-05-06T21:15:06.309068Z DEBUG request{method=GET uri=/health_check version=HTTP/1.1 headers={"host": "127.0.0.1:8080", "user-agent": "curl/7.81.0", "accept": "*/*"}}: tower_http::trace::on_response: finished processing request latency=0 ms status=200
```

You can see our message we planted in the handler: "Received health check from address". You can also see that the logging coming from `tower_http` can be quite verbose, I generally leave it turned off for that reason as it can be kind of noisy. 

## Serving WebSockets
With a lot of the boilerplate out of the way, we can get to the actual reason we're here: setting up our connection between frontend and backend!

First we need to set up a little bit of application state which is accessible to endpoint handlers. In particular, it's convenient to have another task which handles requests from the WebSocket connection and so whenever an HTTP client requests an upgrade to a WebSocket connection the spun-up task can access application information in an organized way that is not reliant on the transport layer.

We'll add two channels for bidirectional communication with this hypothetical message handling task and pass half of each into the HTTP server:

In `main`,
```rust
use async_channel::{Receiver, Sender};

async fn main() -> anyhow::Result<()> {
    // --snip--
    let port = 8080;
    let (from_ws_tx, from_ws_rx) = async_channel::unbounded();
    let (to_ws_tx, to_ws_rx) = async_channel::unbounded();

    serve_web_app(port, from_ws_tx, to_ws_rx).await?;
    // --snip--
}
```

In `serve_web_app`,
```rust
#[derive(Clone)]
struct AppState {
    to_ws_handler: Receiver<Vec<u8>>,
    from_ws_handler: Sender<Vec<u8>>,
}

async fn serve_web_app(
    port: u16,
    from_ws_tx: Sender<Vec<u8>>,
    to_ws_rx: Receiver<Vec<u8>>,
) -> anyhow::Result<()> {
    // --snip--
    let app_state = AppState {
        to_ws_handler: to_ws_rx,
        from_ws_handler: from_ws_tx,
    };

    tracing::info!("Listening on {}", listener.local_addr()?);
    let app = axum::Router::new()
        .route("/health_check", axum::routing::get(handle_health_check))
        .with_state(app_state)
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(DefaultMakeSpan::default().include_headers(true)),
        );

    // --snip--
}
```

Adding this `with_state` method to the `axum::Router` allows passing a cloneable state object which can be passed to each handler in its function parameters, similar to the `ConnectInfo<SocketAddr>` we used in the health check endpoint. (Axum refers to these as extractors, and it leverages [destructuring like this](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=d46916449b66f891a459941fc2cea303))

With that available, we can now add the endpoint for upgrading HTTP requests to WebSocket connections. This takes the form of just adding another route on the endpoint `/ws` (this can actually be whatever you'd like), which we service with the `handle_ws_connection`.

```rust
use axum::extract::{ws::WebSocket, State, WebSocketUpgrade};

async fn serve_web_app(
    port: u16,
    from_ws_tx: Sender<Vec<u8>>,
    to_ws_rx: Receiver<Vec<u8>>,
) -> anyhow::Result<()> {
    // --snip--

    let app = axum::Router::new()
        .route("/health_check", axum::routing::get(handle_health_check))
        .route("/ws", axum::routing::get(handle_ws_connection))
        .with_state(app_state)
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(DefaultMakeSpan::default().include_headers(true)),
        );

    // --snip--
}

async fn handle_ws_connection(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
) -> impl IntoResponse {
    tracing::info!("Client at {addr} requested a WebSocket connection");

    let AppState {
        to_ws_handler: to_ws,
        from_ws_handler: from_ws,
    } = state;

    ws.on_failed_upgrade(|err| tracing::error!("Failed to upgrade connection: {err}"))
        .on_upgrade(move |socket| socket_task(socket, from_ws, to_ws))
}

```

Handling a request on the endpoint primarily consists in trying to upgrade from an HTTP request to a persistent WebSocket connection. `axum` provides some convenient types for this where you just provide a callback for success and a callback for failure. There isn't much to do if there's a failure, just log and move on. 

In the happy path, we set up the persistent async task responsible for shuffling messages between clients and the backend service which can process those messages (and generate its own as responses or unprompted reports). Since the communication is bidirectional, we can just split into two futures.

```rust
use axum::extract::ws::Message;
use futures_util::{
    stream::{SplitSink, SplitStream},
    SinkExt, StreamExt,
};

async fn socket_task(ws: WebSocket, from_ws_tx: Sender<Vec<u8>>, to_ws_rx: Receiver<Vec<u8>>) {
    let (sender, receiver) = ws.split();

    tokio::select! {
        _ = handle_incoming_ws_message(receiver, from_ws_tx) => {},
        _ = handle_outgoing_payloads(sender, to_ws_rx) => {},
    };
}

async fn handle_outgoing_payloads(
    mut sender: SplitSink<WebSocket, Message>,
    to_ws_rx: Receiver<Vec<u8>>,
) {
    while let Ok(msg) = to_ws_rx.recv().await {
        if let Err(err) = sender.send(Message::Binary(msg)).await {
            tracing::error!("Unable to send message to web client: {err}");
            break;
        }
    }
}
```

If we make the content of our channel communication the same as a message coming over the WebSocket connection, we can just read messages straight out of the channel receiver and insert them into the `Message::Binary` variant. There are a few different variants of `Message`, but we'll stick to `Binary` for our application layer communication. The receiving side requires a little more handling due to the different types of messages we can receive.

```rust
async fn handle_incoming_ws_message(
    mut receiver: SplitStream<WebSocket>,
    from_ws_tx: Sender<Vec<u8>>,
) {
    while let Some(msg) = receiver.next().await {
        match msg {
            Ok(Message::Binary(msg)) => {
                tracing::debug!("Received {} bytes from client", msg.len());
                if let Err(_) = from_ws_tx.send(msg).await {
                    tracing::warn!("Closing WebSocket connection from the server side");
                    break;
                }
            }
            Ok(Message::Text(_)) => {
                tracing::warn!("Received unexpected text from WebSocket client");
            }
            Ok(Message::Ping(_) | Message::Pong(_)) => {}
            Ok(Message::Close(_)) => {
                tracing::info!("WebSocket client closed the connection");
                break;
            }
            Err(err) => {
                tracing::error!("Communication with WebSocket client interrupted: {err}");
                break;
            }
        }
    }
}
```

We treat the receiver side of the `WebSocket` handle just like a channel, but there's many different variants of message. `Message::Binary` is the type we'll stick to for application messages, so those will be ferried along to the message handler over the channel. If we get an error, that indicates the channel is closed so we can exit the handler. `Message::Text` is an alternate variant of message we could use, but we'll ignore them with a warning since we're not using them. `Message::Ping` and `Message::Pong` are handled by the server, so we can ignore these as well. Finally, we have `Message::Close` which can be sent by the client before a proactive disconnect.

### Quick Test
That was a lot of code in that last section. Before proceeding, it's good to do a quick sanity check that nothing has gone horribly wrong. For that, we can use [`websocat`](https://github.com/vi/websocat); a tool for sending and receiving data from WebSockets in the shell. You can install with 
```sh
$ cargo install websocat
```

Run your server application in another shell and then let's fire up `websocat` to send a message.

You can try:
```sh
$ websocat ws://0.0.0.0:8080/ws
```

Then type a message followed by the `Enter` key and you should see a warning in the application trace logs: "Received unexpected text from WebSocket client". The WebSocket communication is working! You can send binary messages instead of text as well:
```sh
$ websocat --binary ws://0.0.0.0:8080/ws
hello world

```
And if you have debug logs enabled, you'll see "Received 12 bytes from client".

## Handling Messages
As you can see above, debugging is currently a little awkward when all we have to go by are log messages. Messages that are sent ought to be visible and verifiable in some way. We'll wrap up part 1 by setting up the task that's actually handling the messages to do some very basic handling of messages.

Back in our `main` function, there is a warning about two unused variables. The other side of our channels! We'll launch our message handling task from `main` as well.

```rust
async fn main() -> anyhow::Result<()> {
    // --snip--

    let port = 8080;
    let (from_ws_tx, from_ws_rx) = async_channel::unbounded();
    let (to_ws_tx, to_ws_rx) = async_channel::unbounded();

    tokio::select! {
        web_app_result = serve_web_app(port, from_ws_tx, to_ws_rx) => { web_app_result? },
        handler_result = handle_messages(from_ws_rx, to_ws_tx) => { handler_result? },
    }
}

async fn handle_messages(from_ws: Receiver<Vec<u8>>, to_ws: Sender<Vec<u8>>) -> anyhow::Result<()> {
    while let Ok(msg) = from_ws.recv().await {
        if let Ok(msg) = std::str::from_utf8(&msg[..]) {
            tracing::debug!("Received message: {msg}");
            let response = msg.to_uppercase();
            if let Err(_) = to_ws.send(response.into_bytes()).await {
                tracing::error!("Channel disconnected; exiting");
                break;
            }
        }
    }

    Ok(())
}
```

For now, the message handler behaves very simply: it tries to parse a UTF-8 encoded string and if it can then it responds with the uppercase form of that string:

```sh
$ websocat --binary ws://0.0.0.0:8080/ws
hello world
HELLO WORLD
```

We'll turn this into something more useful in the next chapter, but that wraps up this post!

## Summary
In this post, I covered how to set up an async Rust program which serves an HTTP server with an endpoint to check the liveness of the server and an endpoint for creating a WebSocket connection to the server. We piped messages from that connection to a message handler task which processed the message and responded.

In the next post, we'll switch gears and use Yew to build a frontend application in Rust which can utilize this WebSocket communication to communicate with the backend.

If you're following along and want to compare what code you've written with where I'm at so far, feel free to check out [this branch of the repository on GitHub](https://github.com/ssnover/iot-server/tree/ch1-backend-websockets)!