//! Technique: a blocking read.
//!
//! The simplest one, and what gits does (src/socket.rs): write the request line to the socket,
//! then read a line from it. "read" doesn't return until the line is there - the operating
//! system puts the program to sleep (no CPU used) and wakes it up when data arrives.
//! Nothing else is needed: no promise, no callback, no thread.
//!
//! A read timeout decides how long to wait when the reply never comes.
//!
//! Usage (from the repository root, examples/wait/server.ts has to be running):
//!
//!   rustc examples/wait/client.rs -o examples/wait/tmp/client          # once, std only, no cargo
//!
//!   examples/wait/tmp/client "wait 1500 first" "wait 500 second"
//!   examples/wait/tmp/client --timeout 1000 "silent hello"       # no reply: gives up after 1000 ms, exit code 1
//!   examples/wait/tmp/client --socket /tmp/x.sock "wait 100 a"

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

const DEFAULT_SOCKET: &str = "examples/wait/tmp/wait.sock";

fn main() {
    let mut socket_path = DEFAULT_SOCKET.to_string();
    let mut timeout: Option<Duration> = None;
    let mut lines: Vec<String> = Vec::new();

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--socket" => socket_path = args.next().unwrap_or_default(),
            "--timeout" => {
                let ms: u64 = args.next().and_then(|v| v.parse().ok()).unwrap_or(0);
                timeout = Some(Duration::from_millis(ms));
            }
            _ => lines.push(arg),
        }
    }
    if lines.is_empty() {
        println!(r#"examples/wait/tmp/client [--socket PATH] [--timeout MS] "wait 1500 first" "wait 500 second""#);
        std::process::exit(1);
    }

    let started = Instant::now();
    let stamp = || format!("[+{:.2}s]", started.elapsed().as_secs_f64());

    let stream = match UnixStream::connect(&socket_path) {
        Ok(stream) => stream,
        Err(e) => {
            println!("examples/wait/client.rs error: cannot connect to >{socket_path}<: {e}");
            std::process::exit(1);
        }
    };
    // None = wait forever
    stream.set_read_timeout(timeout).unwrap();

    let mut reader = BufReader::new(stream);

    for line in lines {
        println!("{} send  >{line}<", stamp());
        reader.get_mut().write_all(format!("{line}\n").as_bytes()).unwrap();

        let mut reply = String::new();
        // <- the program stops here until a whole line arrived (or the timeout passed)
        match reader.read_line(&mut reply) {
            Ok(0) => {
                println!("examples/wait/client.rs error: connection closed before the reply");
                std::process::exit(1);
            }
            Ok(_) => println!("{} reply >{}<", stamp(), reply.trim_end()),
            Err(e) => {
                println!("{} examples/wait/client.rs error: no reply to >{line}<: {e}", stamp());
                std::process::exit(1);
            }
        }
    }
}
