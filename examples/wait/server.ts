/**
 * A deliberately slow server on a unix socket, to try out the ways a client can stop and
 * wait for a reply (examples/SUMMARY.md). It does nothing useful: it replies after the time
 * the request asks for.
 *
 * A request is one line, a reply is one line:
 *
 *   wait 1500 hello     ->  done hello      after 1500 ms. Requests of one connection are handled
 *                                           one after another: replies come in the order of the requests
 *                                           (the encoder process of submodules/encrypt works like that)
 *   async 1500 hello    ->  done hello      after 1500 ms, but handled next to each other:
 *                                           a short one overtakes a long one
 *   silent hello        ->  (nothing)       the reply never comes
 *   anything else       ->  error ...       at once
 *
 * Usage (from the repository root):
 *
 *   node examples/wait/server.ts                      # listens on examples/wait/tmp/wait.sock
 *   node examples/wait/server.ts --socket /tmp/x.sock
 *   node examples/wait/server.ts --help
 *
 * - Prints one line for every request and every reply, with the time since the start.
 * - Stops on Ctrl+C or kill, and removes its socket file.
 *
 * Run by Node directly (native type stripping, no flags, Node.js >= 22.18).
 */
import { createServer, type Socket } from "node:net";
import { mkdirSync, rmSync } from "node:fs";
import { dirname } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

export const DEFAULT_SOCKET = "examples/wait/tmp/wait.sock";

const th = (msg: string) => new Error(`examples/wait/server.ts error: ${msg}`);

const started = Date.now();
const log = (msg: string) => console.log(`[+${((Date.now() - started) / 1000).toFixed(2)}s] ${msg}`);

function handle(socket: Socket, id: number) {
  let received = "";
  // "wait" requests of this connection, one after another
  let chain: Promise<void> = Promise.resolve();
  let pending = 0;
  let clientFinished = false;

  const reply = (line: string) => {
    log(`#${id} reply   >${line}<`);
    if (!socket.destroyed) {
      socket.write(line + "\n");
    }
  };

  // the client said "nothing more from me" (nc does that after its input ends):
  // the connection is closed after the last reply, not before
  const closeWhenDone = () => {
    if (clientFinished && pending === 0) {
      socket.end();
    }
  };

  const later = async (ms: number, text: string) => {
    await sleep(ms);
    reply(`done ${text}`);
  };

  const request = (line: string) => {
    log(`#${id} request >${line}<`);
    const [command, ...rest] = line.split(" ");
    if (command === "silent") {
      // counted as never finished: the connection stays open, the client waits for nothing
      pending += 1;
      return;
    }
    const ms = Number(rest[0]);
    const text = rest.slice(1).join(" ");
    if ((command !== "wait" && command !== "async") || !Number.isFinite(ms) || ms < 0) {
      reply(`error unknown request, use: wait MS TEXT | async MS TEXT | silent TEXT`);
      return;
    }
    pending += 1;
    const finished = () => {
      pending -= 1;
      closeWhenDone();
    };
    if (command === "wait") {
      chain = chain.then(() => later(ms, text)).then(finished);
    } else {
      later(ms, text).then(finished);
    }
  };

  socket.setEncoding("utf8");
  socket.on("data", (chunk: string) => {
    received += chunk;
    for (;;) {
      const at = received.indexOf("\n");
      if (at === -1) {
        break;
      }
      const line = received.slice(0, at).replace(/\r$/, "");
      received = received.slice(at + 1);
      if (line !== "") {
        request(line);
      }
    }
  });
  socket.on("end", () => {
    clientFinished = true;
    closeWhenDone();
  });
  socket.on("error", () => {});
  socket.on("close", () => log(`#${id} closed`));
}

export function serve(socketPath: string = DEFAULT_SOCKET) {
  mkdirSync(dirname(socketPath), { recursive: true });
  rmSync(socketPath, { force: true });
  let connections = 0;
  // allowHalfOpen: the client may close its side and still get the replies
  const server = createServer({ allowHalfOpen: true }, (socket) => {
    connections += 1;
    log(`#${connections} connected`);
    handle(socket, connections);
  });
  server.on("error", (e) => {
    throw th(`cannot listen on >${socketPath}<: ${e.message}`);
  });
  server.listen(socketPath, () => log(`listening on ${socketPath}`));
  const stop = () => {
    rmSync(socketPath, { force: true });
    process.exit(0);
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
  return server;
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  if (args.includes("--help")) {
    console.log(`node examples/wait/server.ts [--socket PATH]     default: ${DEFAULT_SOCKET}

requests:  wait MS TEXT | async MS TEXT | silent TEXT      reply: done TEXT`);
    process.exit(1);
  }
  const at = args.indexOf("--socket");
  serve(at === -1 ? DEFAULT_SOCKET : args[at + 1]);
}
