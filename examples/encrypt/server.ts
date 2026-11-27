/**
 * The simplest server which encrypts and decrypts for gits (demo examples/encrypt/ENCRYPT_PROCESS.md).
 *
 * gits never encrypts by itself: for an element "SOURCE:e:TARGET" it sends one line to the unix
 * socket GITS_ENCRYPTION_SOCKET and waits for one line back:
 *
 *   encode "<plain file>" "<encrypted file>"     ->   ok encode "<encrypted file>"
 *   decode "<encrypted file>" "<plain file>"     ->   ok decode "<plain file>"
 *                                                     error <KIND> <message>
 *
 * and for "gits crypt rekey", only when GITS_DEMO_NEW_SSH_KEY is defined (else: error USAGE):
 *
 *   rekey  "<encrypted file>" "<encrypted file>" ->   ok rekey "<encrypted file>"     opened with GITS_DEMO_SSH_KEY,
 *   rewrap "<encrypted file>" "<encrypted file>" ->   ok rewrap "<encrypted file>"    afterwards only GITS_DEMO_NEW_SSH_KEY
 *                                                                                     opens it. rewrap: only the key
 *                                                                                     lines change, not the content
 *
 * A path is written like a JSON string. The reply is sent only after the output file is written:
 * gits waits for it, so when gits reads "ok" the file is there.
 *
 * The server decides nothing about a file: text or binary is detected by the library (mode "auto").
 * The encryption itself is the library of https://github.com/stopsopa/encrypt with an ssh key held
 * by ssh-agent.
 *
 * Usage (started by examples/encrypt/start.sh, which defines the variables from examples/encrypt/env.sh):
 *
 *   node examples/encrypt/server.ts          the server: listens until it is killed
 *   node examples/encrypt/server.ts test     a client: encrypts a file through the socket, decrypts it
 *                                            and compares. Exit code 0 when the server works
 *
 * Env vars:
 *   GITS_ENCRYPTION_SOCKET   the socket (required)
 *   GITS_DEMO_SSH_KEY        private key file (required); <file>.pub is read, the private one
 *                            has to be loaded in the agent of SSH_AUTH_SOCK
 *   GITS_DEMO_NEW_SSH_KEY    the same for the key files get by rekey / rewrap (optional)
 *   GITS_DEMO_ENCRYPT        checkout of the encrypt repository (required)
 *
 * What it prints is the log: "encrypted <file> -> <file>", "decrypted ...", "rekeyed ...", "rewrapped ...".
 *
 * The file from top to bottom:
 *   1. the request:  parse()                                  one line -> command, input, output
 *   2. the work:     encode(), decode(), rekey()              one function for each command
 *   3. the reply:    handle()                                 runs the work, builds "ok ..." / "error ..."
 *   4. the socket:   server()                                 listens, calls handle() for every line
 *   5. the test:     ask(), test()                            a client of the server above
 *
 * Run by Node directly (native type stripping, no flags, Node.js >= 22.18).
 */
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { connect, createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const th = (msg: string) => new Error(`examples/encrypt/server.ts error: ${msg}`);

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

/** The library. Loaded when the first request comes, then reused. */
function library() {
  return import(`${env("GITS_DEMO_ENCRYPT")}/typescript/dist/ssenc.node.ts`);
}

/** A key for the library: the public part from <file>.pub, the private one stays in the ssh-agent. */
function sshKey(file: string) {
  return {
    type: "ssh",
    publicKey: readFileSync(`${file}.pub`, "utf8"),
  };
}

/** The key which encrypts, and which opens what is stored. */
const currentKey = () => sshKey(env("GITS_DEMO_SSH_KEY"));

/** The key the stored files get by rekey / rewrap. */
function newKey(command: Command) {
  if (!process.env.GITS_DEMO_NEW_SSH_KEY) {
    throw th(`${command}: the server was started without GITS_DEMO_NEW_SSH_KEY`);
  }

  return sshKey(process.env.GITS_DEMO_NEW_SSH_KEY);
}

const isEncrypted = (content: Buffer) => content.subarray(0, 8).toString("latin1") === "#ssenc1 ";

async function encode({ input, output }: Request): Promise<void> {
  const { encrypt } = await library();

  const options: { mode: "auto"; previous?: Buffer } = { mode: "auto" };

  // an encrypted file which is already there is reused: only the edited lines change in it
  if (existsSync(output)) {
    const previous = readFileSync(output);

    if (isEncrypted(previous)) {
      options.previous = previous;
    }
  }

  const encrypted = await encrypt(readFileSync(input), currentKey(), options);

  writeFileSync(output, encrypted);
}

async function decode({ input, output }: Request): Promise<void> {
  const { decrypt } = await library();

  const plain = await decrypt(readFileSync(input), currentKey());

  writeFileSync(output, plain);
}

/** rekey: everything encrypted again. rewrap: only the key lines at the top replaced. */
async function rekey({ command, input, output }: Request): Promise<void> {
  const { rekey } = await library();

  const options = { rotateDataKey: command === "rekey" };

  const encrypted = await rekey(readFileSync(input), currentKey(), newKey(command), options);

  writeFileSync(output, encrypted);
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
    // the library gives a kind to its errors (USAGE, AUTH, MALFORMED, ENV): it tells gits
    // e.g. that a file is not encrypted at all, or that the key doesn't open it
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

    if (!isEncrypted(readFileSync(encrypted))) {
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
