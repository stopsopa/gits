/**
 * Technique: many requests on the way at once, replies matched BY ORDER.
 *
 * All requests are written to the socket at once, nobody waits for the previous reply.
 * Every request puts "who waits for it" at the end of a queue; every reply line belongs
 * to the first one in the queue. Correct only when the server replies in the order of the
 * requests ("wait" of examples/wait/server.ts, the encoder process of submodules/encrypt).
 * With a server which replies when it is ready ("async") the replies get mixed up -
 * try it, then see examples/wait/ids.ts.
 *
 * Usage (from the repository root, examples/wait/server.ts has to be running):
 *
 *   node examples/wait/queue.ts "wait 1000 first" "wait 100 second" "wait 500 third"
 *   node examples/wait/queue.ts "async 1000 first" "async 100 second"     # WRONG replies, on purpose
 *   node examples/wait/queue.ts --socket /tmp/x.sock "wait 100 a"
 *
 * Run by Node directly (native type stripping, no flags, Node.js >= 22.18).
 */
import { connect } from "node:net";

export const DEFAULT_SOCKET = "examples/wait/tmp/wait.sock";

const th = (msg: string) => new Error(`examples/wait/queue.ts error: ${msg}`);

export type Connection = {
  request: (line: string) => Promise<string>;
  close: () => void;
};

export function open(socketPath: string = DEFAULT_SOCKET): Promise<Connection> {
  return new Promise((ready, fail) => {
    const socket = connect(socketPath);
    let received = "";
    // everybody who waits for a reply, the oldest request first
    const queue: { resolve: (line: string) => void; reject: (e: Error) => void }[] = [];

    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => {
      received += chunk;
      for (;;) {
        const at = received.indexOf("\n");
        if (at === -1) {
          break;
        }
        const line = received.slice(0, at);
        received = received.slice(at + 1);
        queue.shift()?.resolve(line); // the first in the queue gets the reply
      }
    });
    const failAll = (e: Error) => {
      fail(e);
      while (queue.length > 0) {
        queue.shift()?.reject(e);
      }
    };
    socket.on("error", (e) => failAll(th(`socket >${socketPath}<: ${e.message}`)));
    socket.on("close", () => failAll(th(`connection closed before the reply`)));

    const request = (line: string) =>
      new Promise<string>((resolve, reject) => {
        queue.push({ resolve, reject });
        socket.write(line + "\n");
      });

    socket.on("connect", () => ready({ request, close: () => socket.destroy() }));
  });
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  let socketPath = DEFAULT_SOCKET;
  const lines: string[] = [];
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--socket") {
      socketPath = args[++i];
    } else {
      lines.push(args[i]);
    }
  }
  if (lines.length === 0 || args.includes("--help")) {
    console.log(`node examples/wait/queue.ts [--socket PATH] "wait 1000 first" "wait 100 second"`);
    process.exit(1);
  }

  const started = Date.now();
  const log = (msg: string) => console.log(`[+${((Date.now() - started) / 1000).toFixed(2)}s] ${msg}`);

  const connection = await open(socketPath);
  try {
    // every request is sent now, each "await" inside stops only its own small function
    await Promise.all(
      lines.map(async (line) => {
        log(`send  >${line}<`);
        const reply = await connection.request(line);
        log(`reply >${reply}<   for >${line}<`);
      }),
    );
  } catch (e) {
    console.log((e as Error).message);
    process.exitCode = 1;
  }
  connection.close();
}
