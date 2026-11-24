/**
 * Technique: a promise for the reply, and "await" on it.
 *
 * Node cannot stop in the middle of a function and wait for the socket ("read" never blocks):
 * data arrives later, as an event. So the reply is wrapped in a promise which the event
 * resolves, and "await" is what stops the function until then. Only this function stops,
 * the rest of the program (timers, other requests) keeps running.
 *
 * This file: ONE request at a time. The next one is sent after the reply of the previous one.
 *
 * Usage (from the repository root, examples/wait/server.ts has to be running):
 *
 *   node examples/wait/await.ts "wait 1500 first" "wait 500 second"
 *   node examples/wait/await.ts --timeout 1000 "silent hello"       # no reply: gives up after 1000 ms, exit code 1
 *   node examples/wait/await.ts --socket /tmp/x.sock "wait 100 a"
 *
 * Run by Node directly (native type stripping, no flags, Node.js >= 22.18).
 */
import { connect } from "node:net";

export const DEFAULT_SOCKET = "examples/wait/tmp/wait.sock";

const th = (msg: string) => new Error(`examples/wait/await.ts error: ${msg}`);

export type Connection = {
  request: (line: string, timeoutMs?: number) => Promise<string>;
  close: () => void;
};

export function open(socketPath: string = DEFAULT_SOCKET): Promise<Connection> {
  return new Promise((ready, fail) => {
    const socket = connect(socketPath);
    let received = "";
    // the one who waits for the next reply line, if anybody does
    let waiting: { resolve: (line: string) => void; reject: (e: Error) => void } | null = null;

    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => {
      received += chunk;
      const at = received.indexOf("\n");
      if (at !== -1 && waiting) {
        const line = received.slice(0, at);
        received = received.slice(at + 1);
        const { resolve } = waiting;
        waiting = null;
        resolve(line); // <- this is what lets the "await" below continue
      }
    });
    socket.on("error", (e) => {
      fail(th(`socket >${socketPath}<: ${e.message}`));
      waiting?.reject(th(`socket >${socketPath}<: ${e.message}`));
    });
    socket.on("close", () => waiting?.reject(th(`connection closed before the reply`)));

    const request = (line: string, timeoutMs?: number) =>
      new Promise<string>((resolve, reject) => {
        if (waiting) {
          reject(th(`one request at a time, the previous one has no reply yet`));
          return;
        }
        let timer: NodeJS.Timeout | undefined;
        if (timeoutMs !== undefined) {
          timer = setTimeout(() => {
            waiting = null;
            reject(th(`no reply to >${line}< after ${timeoutMs} ms`));
          }, timeoutMs);
        }
        waiting = {
          resolve: (reply) => {
            clearTimeout(timer);
            resolve(reply);
          },
          reject: (e) => {
            clearTimeout(timer);
            reject(e);
          },
        };
        socket.write(line + "\n");
      });

    socket.on("connect", () => ready({ request, close: () => socket.destroy() }));
  });
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  let socketPath = DEFAULT_SOCKET;
  let timeoutMs: number | undefined;
  const lines: string[] = [];
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--socket") {
      socketPath = args[++i];
    } else if (args[i] === "--timeout") {
      timeoutMs = Number(args[++i]);
    } else {
      lines.push(args[i]);
    }
  }
  if (lines.length === 0 || args.includes("--help")) {
    console.log(`node examples/wait/await.ts [--socket PATH] [--timeout MS] "wait 1500 first" "wait 500 second"`);
    process.exit(1);
  }

  const started = Date.now();
  const log = (msg: string) => console.log(`[+${((Date.now() - started) / 1000).toFixed(2)}s] ${msg}`);

  // proof that only the function with "await" is stopped, not the whole program
  const tick = setInterval(() => log(`   ... the program is not frozen`), 400);

  const connection = await open(socketPath);
  try {
    for (const line of lines) {
      log(`send  >${line}<`);
      const reply = await connection.request(line, timeoutMs); // <- stops here until the reply arrives
      log(`reply >${reply}<`);
    }
  } catch (e) {
    console.log((e as Error).message);
    process.exitCode = 1;
  }
  clearInterval(tick);
  connection.close();
}
