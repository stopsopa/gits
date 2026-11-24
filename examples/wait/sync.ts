/**
 * Technique: really stop the whole Node program, with a helper process.
 *
 * Node has no blocking read on a socket, but it has spawnSync: start a program and do nothing
 * until it ends. The program here is "nc": it sends the request, waits for the reply, ends.
 * The function is an ordinary one (no promise, no await) - the price is that EVERYTHING
 * in the program is frozen while it waits, and one process is started for every request.
 *
 * Usage (from the repository root, examples/wait/server.ts has to be running):
 *
 *   node examples/wait/sync.ts "wait 1500 first" "wait 500 second"
 *   node examples/wait/sync.ts --timeout 1000 "silent hello"       # no reply: gives up after 1000 ms, exit code 1
 *   node examples/wait/sync.ts --socket /tmp/x.sock "wait 100 a"
 *
 * Run by Node directly (native type stripping, no flags, Node.js >= 22.18).
 */
import { spawnSync } from "node:child_process";

export const DEFAULT_SOCKET = "examples/wait/tmp/wait.sock";

const th = (msg: string) => new Error(`examples/wait/sync.ts error: ${msg}`);

export function request(line: string, socketPath: string = DEFAULT_SOCKET, timeoutMs?: number): string {
  // nothing else happens in this program until nc ends
  const result = spawnSync("nc", ["-U", socketPath], {
    input: line + "\n",
    encoding: "utf8",
    timeout: timeoutMs,
  });
  if (result.error) {
    const timedOut = (result.error as NodeJS.ErrnoException).code === "ETIMEDOUT";
    throw th(timedOut ? `no reply to >${line}< after ${timeoutMs} ms` : `cannot run nc: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw th(`nc failed for >${line}<: ${result.stderr.trim()}`);
  }
  return result.stdout.replace(/\n$/, "");
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
    console.log(`node examples/wait/sync.ts [--socket PATH] [--timeout MS] "wait 1500 first" "wait 500 second"`);
    process.exit(1);
  }

  const started = Date.now();
  const log = (msg: string) => console.log(`[+${((Date.now() - started) / 1000).toFixed(2)}s] ${msg}`);

  // this timer can't fire while request() waits: the whole program is stopped
  const tick = setInterval(() => log(`   ... the program is not frozen`), 400);

  try {
    for (const line of lines) {
      log(`send  >${line}<`);
      const reply = request(line, socketPath, timeoutMs); // <- no await
      log(`reply >${reply}<`);
    }
  } catch (e) {
    console.log((e as Error).message);
    process.exitCode = 1;
  }
  clearInterval(tick);
}
