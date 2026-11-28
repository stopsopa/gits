/**
 * The simplest server which encrypts and decrypts for gits (demo examples/encrypt_os_ssh_agent/ENCRYPT_PROCESS.md).
 *
 * gits never encrypts by itself: for an element "SOURCE:e:TARGET" it sends one line to the unix
 * socket GITS_ENCRYPTION_SOCKET and waits for one line back:
 *
 *   encode "<plain file>" "<encrypted file>"     ->   ok encode "<encrypted file>"
 *   decode "<encrypted file>" "<plain file>"     ->   ok decode "<plain file>"
 *                                                     error <KIND> <message>
 *
 * and for "gits crypt rekey", only when GITS_ENCRYPTION_REKEY_SSH_KEY is defined (else: error USAGE):
 *
 *   rekey  "<encrypted file>" "<encrypted file>" ->   ok rekey "<encrypted file>"     opened with GITS_ENCRYPTION_SSH_KEY,
 *   rewrap "<encrypted file>" "<encrypted file>" ->   ok rewrap "<encrypted file>"    afterwards only GITS_ENCRYPTION_REKEY_SSH_KEY
 *                                                                                     opens it. rewrap: only the key
 *                                                                                     lines change, not the content
 *
 * A path is written like a JSON string. The reply is sent only after the output file is written:
 * gits waits for it, so when gits reads "ok" the file is there.
 *
 * The server doesn't encrypt by itself either: for every request it starts the program "ssenc"
 * (the Rust binary of https://github.com/stopsopa/encrypt, where it is: GITS_DEMO_SSENC) with the
 * two files and the ssh key, waits for it, and turns its exit code into the reply:
 *
 *   encode   ssenc encrypt --mode auto --ssh-key <key> -i <plain> -o <encrypted>
 *   decode   ssenc decrypt --ssh-key <key> -i <encrypted> -o <plain>
 *   rekey    ssenc rekey --ssh-key <key> --new-ssh-key <new key> -i <encrypted> -o <encrypted>
 *   rewrap   the same with --rewrap-only
 *
 * <key> is GITS_ENCRYPTION_SSH_KEY exactly as it is: the fingerprint (SHA256:...) of a key
 * which is loaded in the ssh-agent. No key file is read by anybody. (ssenc also takes a public
 * key file there.)
 *
 * So the server decides nothing about a file: text or binary is detected by ssenc (--mode auto),
 * and an encrypted file which is already at the output is reused by it (only edited lines change).
 * The private key stays in the ssh-agent of SSH_AUTH_SOCK: ssenc asks it. In this demo that is
 * the agent of the terminal gits was started in (nobody starts another one): the server
 * inherits SSH_AUTH_SOCK from start.sh, and ssenc inherits it from the server.
 *
 * This file is not run directly: examples/encrypt_os_ssh_agent/encrypt.sh turns it (esbuild) into server.js.
 *
 * Usage (started by examples/encrypt_os_ssh_agent/start.sh, which defines the variables from examples/encrypt_os_ssh_agent/env.sh):
 *
 *   /bin/bash examples/encrypt_os_ssh_agent/encrypt.sh    server.ts -> server.js, and a copy of ssenc in bin/
 *   node examples/encrypt_os_ssh_agent/server.js          the server: listens until it is killed
 *   node examples/encrypt_os_ssh_agent/server.js test     a client: encrypts a file through the socket, decrypts it
 *                                            and compares. Exit code 0 when the server works
 *
 * Env vars:
 *   GITS_ENCRYPTION_SOCKET   the socket (required)
 *   GITS_ENCRYPTION_SSH_KEY          which key (required): its fingerprint, SHA256:...
 *                                    The key has to be loaded in the agent of SSH_AUTH_SOCK
 *   GITS_ENCRYPTION_REKEY_SSH_KEY    the same for the key files get by rekey / rewrap (optional)
 *   SSH_AUTH_SOCK                    the ssh-agent (read by ssenc, not by this file)
 *   GITS_DEMO_SSENC          the ssenc binary (required): a path, or a name found in PATH
 *
 * What it prints is the log: "encrypted <file> -> <file>", "decrypted ...", "rekeyed ...", "rewrapped ...".
 *
 * The file from top to bottom:
 *   1. the request:  parse()                                  one line -> command, input, output
 *   2. the work:     ssenc(), encode(), decode(), rekey()     one function for each command, each starts ssenc
 *   3. the reply:    handle()                                 runs the work, builds "ok ..." / "error ..."
 *   4. the socket:   server()                                 listens, calls handle() for every line
 *   5. the test:     ask(), test()                            a client of the server above
 *
 * server.js is plain JavaScript, for Node.js >= 22.18.
 */
import { execFile } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { connect, createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const th = (msg: string) => new Error(`examples/encrypt_os_ssh_agent/server.ts error: ${msg}`);

function env(name: string): string {
  const value = process.env[name];

  if (!value) {
    throw th(`env var ${name} is not defined`);
  }

  return value;
}

const log = (message: string) => console.log(`${new Date().toISOString()} ${message}`);

// ---------------------------------------------------------------- 1. the request

type Command = "encode" | "decode" | "rekey" | "rewrap";

type Request = {
  command: Command;
  input: string;
  output: string;
};

// a path in quotes, like a JSON string: "/a/b c.txt", "/a/\"q\".enc"
const QUOTED = `"(?:[^"\\\\]|\\\\.)*"`;

const REQUEST = new RegExp(`^(encode|decode|rekey|rewrap) (${QUOTED}) (${QUOTED})$`);

function parse(line: string): Request {
  const found = REQUEST.exec(line.trim());

  if (!found) {
    throw th(`not a request >${line}<`);
  }

  return {
    command: found[1] as Command,
    input: JSON.parse(found[2]),
    output: JSON.parse(found[3]),
  };
}

// ---------------------------------------------------------------- 2. the work

/** An error of ssenc, with its kind for the reply: USAGE, AUTH, MALFORMED or ENV. */
class SsencError extends Error {
  kind: string;

  constructor(kind: string, message: string) {
    super(message);

    this.kind = kind;
  }
}

// exit codes of ssenc. 0: done, the whole output was written
const KINDS: Record<number, string> = {
  1: "USAGE",
  2: "AUTH", // the key doesn't open the file, or the file was modified
  3: "MALFORMED", // not an encrypted file at all
  4: "ENV", // no ssh-agent, or the key is not in it
};

/** Starts ssenc with the arguments and waits for its end. On an error nothing is written to the output. */
function ssenc(args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    execFile(env("GITS_DEMO_SSENC"), args, (error, _stdout, stderr) => {
      if (!error) {
        resolve();

        return;
      }

      if (typeof error.code !== "number") {
        reject(new SsencError("ENV", `can't start GITS_DEMO_SSENC=>${env("GITS_DEMO_SSENC")}<: ${error.message}`));

        return;
      }

      // stderr of ssenc: "ssenc: <KIND>: <message>"
      const message = stderr.trim().replace(/^ssenc: [A-Z]+: /, "");

      reject(new SsencError(KINDS[error.code] ?? "USAGE", message));
    });
  });
}

/** The key which encrypts, and which opens what is stored: its fingerprint (SHA256:...), as it is. */
const currentKey = () => env("GITS_ENCRYPTION_SSH_KEY");

/** The key the stored files get by rekey / rewrap. */
function newKey(command: Command): string {
  if (!process.env.GITS_ENCRYPTION_REKEY_SSH_KEY) {
    throw th(`${command}: the server was started without GITS_ENCRYPTION_REKEY_SSH_KEY`);
  }

  return process.env.GITS_ENCRYPTION_REKEY_SSH_KEY;
}

function encode({ input, output }: Request): Promise<void> {
  return ssenc(["encrypt", "--mode", "auto", "--ssh-key", currentKey(), "-i", input, "-o", output]);
}

function decode({ input, output }: Request): Promise<void> {
  return ssenc(["decrypt", "--ssh-key", currentKey(), "-i", input, "-o", output]);
}

/** rekey: everything encrypted again. rewrap: only the key lines at the top replaced. */
function rekey({ command, input, output }: Request): Promise<void> {
  const args = ["rekey", "--ssh-key", currentKey(), "--new-ssh-key", newKey(command)];

  if (command === "rewrap") {
    args.push("--rewrap-only");
  }

  return ssenc([...args, "-i", input, "-o", output]);
}

const WORK: Record<Command, { run: (request: Request) => Promise<void>; done: string }> = {
  encode: { run: encode, done: "encrypted" },
  decode: { run: decode, done: "decrypted" },
  rekey: { run: rekey, done: "rekeyed" },
  rewrap: { run: rekey, done: "rewrapped" },
};

// ---------------------------------------------------------------- 3. the reply

/** One request line -> one reply line. Never throws: an error is a reply too. */
export async function handle(line: string): Promise<string> {
  try {
    const request = parse(line);

    const { run, done } = WORK[request.command];

    await run(request);

    log(`${done} ${request.input} -> ${request.output}`);

    return `ok ${request.command} ${JSON.stringify(request.output)}`;
  } catch (e) {
    // the kind (USAGE, AUTH, MALFORMED, ENV) tells gits e.g. that a file is not encrypted
    // at all, or that the key doesn't open it
    const error = e as Error & { kind?: string };

    const kind = error.kind ?? "USAGE";

    const message = error.message.replace(/\s+/g, " "); // the reply is one line

    log(`error ${line.trim()}: ${error.message}`);

    return `error ${kind} ${message}`;
  }
}

// ---------------------------------------------------------------- 4. the socket

/** Listens on the socket; requests of one connection are answered one after another, in their order. */
export function server(): void {
  const socketFile = env("GITS_ENCRYPTION_SOCKET");

  const listener = createServer((connection) => {
    // every next request waits for the reply of the previous one
    let previous: Promise<void> = Promise.resolve();

    const lines = createInterface({ input: connection });

    lines.on("line", (line) => {
      previous = previous.then(async () => {
        const reply = await handle(line);

        connection.write(`${reply}\n`);
      });
    });

    connection.on("error", () => connection.destroy());
  });

  // the socket file is created by listen(): with this umask only the owner can connect
  const umask = process.umask(0o077);

  listener.listen(socketFile, () => {
    process.umask(umask);

    log(`listening on ${socketFile}`);
  });
}

// ---------------------------------------------------------------- 5. the test

/** A client: sends the requests through the socket one after another, resolves with the replies. */
function ask(requests: string[]): Promise<string[]> {
  return new Promise((resolve, reject) => {
    const replies: string[] = [];

    const connection = connect(env("GITS_ENCRYPTION_SOCKET"));

    const send = (request: string) => connection.write(`${request}\n`);

    connection.on("error", (e) => reject(th(`can't connect to the socket: ${e.message}`)));

    createInterface({ input: connection }).on("line", (reply) => {
      replies.push(reply);

      if (replies.length < requests.length) {
        send(requests[replies.length]);

        return;
      }

      connection.end();

      resolve(replies);
    });

    send(requests[0]);
  });
}

/** Encrypts a file through the socket, decrypts it and compares. Throws when anything is wrong. */
export async function test(): Promise<void> {
  const content = "test of the encryption\n";

  const dir = mkdtempSync(join(tmpdir(), "gits-demo-"));

  const plain = join(dir, "plain");
  const encrypted = join(dir, "encrypted");
  const back = join(dir, "back");

  const quote = (path: string) => JSON.stringify(path);

  try {
    writeFileSync(plain, content);

    const replies = await ask([
      `encode ${quote(plain)} ${quote(encrypted)}`,
      `decode ${quote(encrypted)} ${quote(back)}`,
    ]);

    const failed = replies.find((reply) => !reply.startsWith("ok "));

    if (failed) {
      throw th(`the server replied >${failed}<`);
    }

    if (!readFileSync(encrypted, "utf8").startsWith("#ssenc1 ")) {
      throw th("the file was not encrypted");
    }

    if (readFileSync(back, "utf8") !== content) {
      throw th("decrypted file differs");
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

async function cli(): Promise<void> {
  if (process.argv[2] === "test") {
    try {
      await test();
    } catch (e) {
      console.error((e as Error).message);

      process.exit(1);
    }

    return;
  }

  server();
}

if (import.meta.main) {
  cli();
}
