/**
 * Technique: many requests on the way at once, replies matched BY ID.
 *
 * Every request carries a number, the server sends it back in the reply, and the client keeps
 * a map "number -> who waits for it". The order of the replies doesn't matter any more, so the
 * server is free to answer a short request before a long one.
 *
 * Here the number is simply the first word of TEXT (the server gives TEXT back as it is):
 *
 *   async 1000 #1 first    ->   done #1 first
 *
 * Usage (from the repository root, examples/wait/server.ts has to be running):
 *
 *   node examples/wait/ids.ts "async 1000 first" "async 100 second" "async 500 third"
 *   node examples/wait/ids.ts --socket /tmp/x.sock "async 100 a"
 *
 * Give the requests without numbers, they are added here.
 *
 * Run by Node directly (native type stripping, no flags, Node.js >= 22.18).
 */
import { connect } from "node:net";

export const DEFAULT_SOCKET = "examples/wait/tmp/wait.sock";

const th = (msg: string) => new Error(`examples/wait/ids.ts error: ${msg}`);

export type Connection = {
  // command: "wait" | "async", the reply is TEXT as the server gave it back (without the number)
  request: (command: string, ms: number, text: string) => Promise<string>;
  close: () => void;
};

export function open(socketPath: string = DEFAULT_SOCKET): Promise<Connection> {
  return new Promise((ready, fail) => {
    const socket = connect(socketPath);
    let received = "";
    let lastId = 0;
    // number of the request -> who waits for its reply
    const waiting = new Map<string, { resolve: (line: string) => void; reject: (e: Error) => void }>();

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
        // "done #7 some text"
        const match = line.match(/^done (#\d+) ?(.*)$/);
        if (!match) {
          continue;
        }
        const [, id, text] = match;
        waiting.get(id)?.resolve(text); // the one with this number gets the reply
        waiting.delete(id);
      }
    });
    const failAll = (e: Error) => {
      fail(e);
      for (const one of waiting.values()) {
        one.reject(e);
      }
      waiting.clear();
    };
    socket.on("error", (e) => failAll(th(`socket >${socketPath}<: ${e.message}`)));
    socket.on("close", () => failAll(th(`connection closed before the reply`)));

    const request = (command: string, ms: number, text: string) =>
      new Promise<string>((resolve, reject) => {
        lastId += 1;
        const id = `#${lastId}`;
        waiting.set(id, { resolve, reject });
        socket.write(`${command} ${ms} ${id} ${text}\n`);
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
    console.log(`node examples/wait/ids.ts [--socket PATH] "async 1000 first" "async 100 second"`);
    process.exit(1);
  }

  const started = Date.now();
  const log = (msg: string) => console.log(`[+${((Date.now() - started) / 1000).toFixed(2)}s] ${msg}`);

  const connection = await open(socketPath);
  try {
    await Promise.all(
      lines.map(async (line) => {
        const [command, ms, ...text] = line.split(" ");
        log(`send  >${line}<`);
        const reply = await connection.request(command, Number(ms), text.join(" "));
        log(`reply >${reply}<   for >${line}<`);
      }),
    );
  } catch (e) {
    console.log((e as Error).message);
    process.exitCode = 1;
  }
  connection.close();
}
