# Examples summary: send a request to a socket, stop, continue when the reply arrives

`submodules/encrypt/examples/SUMMARY.md` shows a process which listens on a unix socket and
answers requests ([socket-002](../submodules/encrypt/examples/SUMMARY.md#socket-002-encoder_process_on_a_socket)).
This file is about the other side: a program writes a request to the socket and has to **stop
there** until the reply comes back, then carry on with it. The ways to do that, each one to
run command by command. The code is in `examples/wait/`.

There are only two ideas behind all of them:

- **A blocking read.** The program asks the operating system for data from the socket. There
  is none yet, so the operating system puts the program to sleep (it uses no CPU) and wakes it
  up when data arrives. The line after `read` runs only then. Shell, Rust, Python, C, Go work
  this way out of the box.
- **A promise.** Node never sleeps in `read`: data arrives later, as an event. So the reply is
  wrapped in a promise which the event resolves, and `await` stops the function until then.
  Only that function stops, the rest of the program keeps running.

| Technique | What stops | Requests on the way at once | Shown in |
|---|---|---|---|
| `nc`: one process per request | the shell, until `nc` ends | one per `nc` | [wait-001](#wait-001-shell_nc_one_request) |
| zsh: connection kept open, `read` | the shell, in `read` | one | [wait-002](#wait-002-zsh_connection_kept_open) |
| Rust: blocking `read_line` (what `gits` does) | the whole program (or the thread) | one | [wait-003](#wait-003-rust_blocking_read) |
| Node: promise + `await`, one at a time | only the function with `await` | one | [wait-004](#wait-004-node_await_one_at_a_time) |
| Node: queue, replies matched by order | only the functions with `await` | many, the server has to reply in order | [wait-005](#wait-005-node_many_at_once_matched_by_order) |
| Node: map, replies matched by id | only the functions with `await` | many, in any order | [wait-006](#wait-006-node_many_at_once_matched_by_id) |
| Node: `spawnSync` of `nc` | the whole program | one | [wait-007](#wait-007-node_whole_program_stopped) |

Once per terminal:

```sh
export T=examples/wait/tmp
mkdir -p $T
```

## The server used by all cases

`examples/wait/server.ts` is slow on purpose, so that the waiting can be seen. A request is
one line, a reply is one line:

```
wait 1500 hello     ->  done hello      after 1500 ms; requests of one connection one after another,
                                        so replies come in the order of the requests
async 1500 hello    ->  done hello      after 1500 ms; handled next to each other,
                                        a short one overtakes a long one
silent hello        ->  (nothing)       the reply never comes
anything else       ->  error ...       at once
```

Start it in a **second terminal** and leave it there: it prints every request and every reply
with the time, which is worth watching next to the commands below.

```sh
node examples/wait/server.ts
```

Or in the background of the same terminal, with the log in a file:

```sh
node examples/wait/server.ts > $T/server.log 2>&1 &
SERVER=$!
tail -n 5 $T/server.log
```

## wait-001-shell_nc_one_request

`nc` connects, sends what it gets on standard input, prints what comes back, and ends when the
server closes the connection. The shell waits for `nc` like for any other command, so the next
line of a script runs after the reply. Nothing to program.

```sh
time (echo "wait 1500 hello" | nc -U $T/wait.sock)         # about 1.5 s, prints: done hello

REPLY_LINE="$(echo "wait 1000 hello" | nc -U $T/wait.sock)"    # the reply in a variable
echo "got >$REPLY_LINE<"

printf 'wait 500 a\nwait 100 b\n' | nc -U $T/wait.sock      # two requests, one connection: done a, done b
```

Two at the same time means two `nc` and two connections: 1 second together, not 2.

```sh
time ( (echo "wait 1000 a" | nc -U $T/wait.sock) & (echo "wait 1000 b" | nc -U $T/wait.sock) & wait )
```

- **How `nc` knows that it is over:** it does not know the protocol. It ends when the server
  closes the connection, and the server closes it after the last reply because `nc` said "nothing
  more from me" when its input ended. A server which keeps the connection open would keep `nc`
  waiting: see [When the reply never comes](#when-the-reply-never-comes).
- **Cost:** one process and one connection for every request (a few milliseconds).

## wait-002-zsh_connection_kept_open

zsh opens the socket itself. `print -u` writes the request, `read -u` is the blocking read:
it returns when a whole line arrived. The connection stays open for as many requests as you
like, and no process is started. (zsh only; bash has nothing built in for unix sockets.)

```sh
zmodload zsh/net/socket
zsocket $T/wait.sock                  # connect; the number of the connection is in $REPLY
FD=$REPLY

print -r -u $FD -- "wait 1500 hello"  # send: returns at once
read -r -u $FD ANSWER                 # stops here for about 1.5 s
echo "got >$ANSWER<"

for i in 1 2 3; do
  print -r -u $FD -- "wait 300 number $i"
  read -r -u $FD ANSWER; echo "got >$ANSWER<"
done

exec {FD}>&-                          # close the connection
```

Nothing forces you to read right after writing. The reply waits in the connection until you
read it:

```sh
zsocket $T/wait.sock; FD=$REPLY
print -r -u $FD -- "wait 1000 hello"
sleep 2; echo "doing something else meanwhile"
read -r -u $FD ANSWER; echo "got >$ANSWER<"          # returns at once: the reply was already there
exec {FD}>&-
```

## wait-003-rust_blocking_read

The same two steps in a program: write the line, read a line. `read_line` does not return
until the line is there. This is how `gits` talks to the encoder process (`src/socket.rs`).

```rust
stream.write_all(b"wait 1500 hello\n")?;
let mut reply = String::new();
reader.read_line(&mut reply)?;        // <- the program stops here
```

```sh
rustc examples/wait/client.rs -o $T/client          # once; std only, no cargo

$T/client "wait 1500 first" "wait 500 second"
```

```
[+0.00s] send  >wait 1500 first<
[+1.50s] reply >done first<
[+1.50s] send  >wait 500 second<
[+2.00s] reply >done second<
```

- **What stops:** the whole program, which is exactly what a command line tool wants. A
  program which has to do other things meanwhile puts the request in its own thread.
- **Cost:** nothing. A sleeping program uses no CPU, and there is nothing to set up.

## wait-004-node_await_one_at_a_time

Node cannot stop in `read`. `examples/wait/await.ts` wraps the reply in a promise: `request()`
writes the line and remembers "who waits"; the `data` event of the socket finds the end of the
line and resolves the promise; `await` continues.

```ts
const reply = await connection.request("wait 1500 first");   // <- only this function stops
```

```sh
node examples/wait/await.ts "wait 1500 first" "wait 500 second"
```

```
[+0.00s] send  >wait 1500 first<
[+0.40s]    ... the program is not frozen
[+0.80s]    ... the program is not frozen
[+1.20s]    ... the program is not frozen
[+1.50s] reply >done first<
[+1.50s] send  >wait 500 second<
[+1.60s]    ... the program is not frozen
[+2.00s] reply >done second<
```

The lines "the program is not frozen" come from a timer which fires every 400 ms: while the
function waits in `await`, the rest of the program keeps running. This version allows one
request at a time; a second `request()` before the reply of the first is refused.

## wait-005-node_many_at_once_matched_by_order

All requests are written at once. Each one puts "who waits" at the end of a queue, and every
reply line belongs to the first in the queue (`examples/wait/queue.ts`). Right as long as the
server replies in the order of the requests, like `wait` here and like the encoder process.

```sh
node examples/wait/queue.ts "wait 1000 first" "wait 100 second" "wait 500 third"
```

```
[+0.00s] send  >wait 1000 first<
[+0.00s] send  >wait 100 second<
[+0.00s] send  >wait 500 third<
[+1.00s] reply >done first<   for >wait 1000 first<
[+1.10s] reply >done second<   for >wait 100 second<
[+1.60s] reply >done third<   for >wait 500 third<
```

The same client against a server which replies when it is ready (`async`) hands the replies to
the wrong requests, without any error:

```sh
node examples/wait/queue.ts "async 1000 first" "async 100 second"
```

```
[+0.10s] reply >done second<   for >async 1000 first<
[+1.00s] reply >done first<   for >async 100 second<
```

- **Why bother:** nobody waits for the previous reply before sending, so with a server which
  works on one connection one request after another the total time is the same, but the client
  code can start everything at once (`Promise.all`) and continue with each reply as it comes.

## wait-006-node_many_at_once_matched_by_id

Every request carries a number, the server sends it back, and the client keeps a map
"number -> who waits" (`examples/wait/ids.ts`). The order of the replies no longer matters.

```
async 1000 #1 first    ->   done #1 first
```

```sh
node examples/wait/ids.ts "async 1000 first" "async 100 second" "async 500 third"
```

```
[+0.00s] send  >async 1000 first<
[+0.00s] send  >async 100 second<
[+0.00s] send  >async 500 third<
[+0.10s] reply >second<   for >async 100 second<
[+0.50s] reply >third<   for >async 500 third<
[+1.00s] reply >first<   for >async 1000 first<
```

One second for all three, each reply at the right request. The server has to take part: it
must give the number back. The encoder process of `submodules/encrypt` does not, and does not
need to, because it replies in order.

## wait-007-node_whole_program_stopped

When Node really has to stop (a script written top to bottom, no `await` anywhere):
`spawnSync` starts `nc` and does nothing until it ends (`examples/wait/sync.ts`). This is
[wait-001](#wait-001-shell_nc_one_request) called from Node.

```ts
const reply = request("wait 1500 first");     // <- no await, an ordinary function
```

```sh
node examples/wait/sync.ts "wait 1500 first" "wait 500 second"
```

```
[+0.00s] send  >wait 1500 first<
[+1.51s] reply >done first<
[+1.51s] send  >wait 500 second<
[+2.02s] reply >done second<
```

The same timer as in wait-004 is set here too, and it never prints: the whole program is
frozen while it waits, timers and other connections included. One process per request.

## When the reply never comes

Every way of waiting needs an answer to "for how long". `silent` never replies and keeps the
connection open.

```sh
time (echo "silent hello" | nc -w 1 -U $T/wait.sock); echo "exit code $?"   # nc gives up after 1 s of silence; no output, exit code 0

zsocket $T/wait.sock; FD=$REPLY
print -r -u $FD -- "silent hello"
read -r -t 1 -u $FD ANSWER; echo "exit code $?"                             # read -t 1: exit code 1 after 1 s
exec {FD}>&-

$T/client --timeout 1000 "silent hello"; echo "exit code $?"                # set_read_timeout: read_line returns an error
node examples/wait/await.ts --timeout 1000 "silent hello"; echo "exit code $?"   # a timer rejects the promise
node examples/wait/sync.ts --timeout 1000 "silent hello"; echo "exit code $?"    # spawnSync kills nc
```

- **`nc -w 1`** ends without output and with exit code 0, so an empty reply is the only sign.
  Without `-w` it waits forever.
- **After a timeout the connection is not usable any more** in the one-at-a-time and the queue
  versions: the late reply could still arrive and would be taken for the reply of the next
  request. Close it and connect again. With ids a late reply is simply ignored.
- **A closed connection** ends the waiting at once in every version (`read` returns "end of
  file", the promise is rejected): stop the server while a request waits to see it.

## How the program knows that the reply is complete

A socket delivers bytes, not messages: one reply can arrive in two pieces, two replies in one.
"The reply arrived" has to be defined by the protocol. Here and in `submodules/encrypt` it is
**one line**: everything up to `\n`. That is why every client above collects what arrives and
looks for the end of the line (`read -r`, `read_line`, `indexOf("\n")`) instead of taking
whatever one read returned. The other usual definitions are "everything until the connection
is closed" (what `nc` relies on) and "a number first which says how many bytes follow".

## Which one to use

- **A command line tool or a script that does one thing at a time** (like `gits`): the blocking
  read with a timeout, [wait-003](#wait-003-rust_blocking_read). In a shell script
  [wait-001](#wait-001-shell_nc_one_request), or [wait-002](#wait-002-zsh_connection_kept_open)
  when there are many requests.
- **Node:** [wait-004](#wait-004-node_await_one_at_a_time) when requests go one after another,
  [wait-005](#wait-005-node_many_at_once_matched_by_order) when several parts of the program
  send at the same time and the server replies in order,
  [wait-006](#wait-006-node_many_at_once_matched_by_id) when the server replies in any order.
  [wait-007](#wait-007-node_whole_program_stopped) only for small scripts.

## Clean up

```sh
kill $SERVER            # when it was started in the background; Ctrl+C in the second terminal otherwise
rm -rf $T
```
