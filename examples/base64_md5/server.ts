/**
 * An encoder process for gits which encrypts NOTHING (demo examples/base64_md5/ENCRYPT_PROCESS.md).
 *
 * gits never encrypts by itself: for an element "SOURCE:e:TARGET" it sends one line to the unix
 * socket GITS_ENCRYPTION_SOCKET and waits for one line back:
 *
 *   encode "<plain file>" "<encoded file>"     ->   ok encode "<encoded file>"
 *   decode "<encoded file>" "<plain file>"     ->   ok decode "<plain file>"
 *                                                   error <KIND> <message>
 *
 * What "encode" means is decided here, not in gits. Here it is the most primitive thing which
 * still has the two properties gits relies on: it can be turned back, and an encoded file can
 * be told from a plain one. The encoded file is one line:
 *
 *   <md5 of the base64 text>:<base64 of the content of the plain file>
 *
 *   encode   base64 of the bytes of the file, md5 (hex) of that base64 text, both joined with ":"
 *   decode   split at the first ":", the md5 of the second part has to be the first part
 *            (otherwise: error MALFORMED, the file is not an encoded one), base64 back to bytes
 *
 * It is NOT encryption: anybody can decode it, there is no key. The point of the demo is that
 * gits works the same with it as with real encryption, because gits knows only the protocol.
 * Three things gits learns from outside:
 *
 *   - encode / decode: the requests above
 *   - "error MALFORMED ...": the reply which says "this file is not an encoded one". gits then
 *     uses a stored file as it is (a ":e:" file which was stored before there was a socket)
 *   - whether a stored file is an encoded one, without asking the server: detect.sh
 *     (env var GITS_ENCRYPTION_DETECT), the same rule as isEncoded() below
 *
 * rekey / rewrap ("gits crypt rekey") are refused with "error USAGE ...": there are no keys.
 *
 * A path is written like a JSON string. The reply is sent only after the output file is written.
 *
 * Usage (started by examples/base64_md5/start.sh, which defines the variables from examples/base64_md5/env.sh).
 * TypeScript executed by Node directly (type stripping, Node.js >= 22.18), nothing is built:
 *
 *   node examples/base64_md5/server.ts          the server: listens until it is killed
 *   node examples/base64_md5/server.ts test     a client: encodes a file through the socket, decodes it
 *                                               and compares. Exit code 0 when the server works
 *
 * Env vars:
 *   GITS_ENCRYPTION_SOCKET   the socket (required)
 *
 * What it prints is the log: "encoded <file> -> <file>", "decoded <file> -> <file>".
 *
 * The file from top to bottom:
 *   1. the request:  parse()                         one line -> command, input, output
 *   2. the work:     encode(), decode()              the format
 *   3. the reply:    handle()                        runs the work, builds "ok ..." / "error ..."
 *   4. the socket:   server()                        listens, calls handle() for every line
 *   5. the test:     ask(), test()                   a client of the server above
 */
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { connect, createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const th = (msg: string) => new Error(`examples/base64_md5/server.ts error: ${msg}`);

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

/** An error with its kind for the reply. MALFORMED tells gits: the file is not an encoded one. */
class KindError extends Error {
  kind: string;

  constructor(kind: string, message: string) {
    super(message);

    this.kind = kind;
  }
}

const md5 = (text: string) => createHash("md5").update(text).digest("hex");

// <32 hex characters>:<base64>, one line
const ENCODED = /^([0-9a-f]{32}):([A-Za-z0-9+/]*=*)\n$/;

/** The base64 part of an encoded text, or null when the text is not an encoded one. */
export function isEncoded(text: string): string | null {
  const found = ENCODED.exec(text);

  if (!found || md5(found[2]) !== found[1]) {
    return null;
  }

  return found[2];
}

function encode({ input, output }: Request): void {
  const data = readFileSync(input).toString("base64");

  writeFileSync(output, `${md5(data)}:${data}\n`);
}

function decode({ input, output }: Request): void {
  // latin1: every byte is one character, also of a binary file which is not an encoded one
  const data = isEncoded(readFileSync(input, "latin1"));

  if (data === null) {
    throw new KindError("MALFORMED", "not a base64_md5 file (expected one line: <md5 of the base64>:<base64>)");
  }

  writeFileSync(output, Buffer.from(data, "base64"));
}

function rekey({ command }: Request): void {
  throw new KindError("USAGE", `${command}: there are no keys in base64_md5, nothing to change`);
}

const WORK: Record<Command, { run: (request: Request) => void; done: string }> = {
  encode: { run: encode, done: "encoded" },
  decode: { run: decode, done: "decoded" },
  rekey: { run: rekey, done: "rekeyed" },
  rewrap: { run: rekey, done: "rewrapped" },
};

// ---------------------------------------------------------------- 3. the reply

/** One request line -> one reply line. Never throws: an error is a reply too. */
export function handle(line: string): string {
  try {
    const request = parse(line);

    const { run, done } = WORK[request.command];

    run(request);

    log(`${done} ${request.input} -> ${request.output}`);

    return `ok ${request.command} ${JSON.stringify(request.output)}`;
  } catch (e) {
    const error = e as Error & { kind?: string };

    // a file which can't be read or written: the environment, not the request
    const kind = error.kind ?? ((error as NodeJS.ErrnoException).code ? "ENV" : "USAGE");

    const message = error.message.replace(/\s+/g, " "); // the reply is one line

    log(`error ${line.trim()}: ${error.message}`);

    return `error ${kind} ${message}`;
  }
}

// ---------------------------------------------------------------- 4. the socket

/** Listens on the socket; every line of a connection is one request, answered with one line. */
export function server(): void {
  const socketFile = env("GITS_ENCRYPTION_SOCKET");

  const listener = createServer((connection) => {
    const lines = createInterface({ input: connection });

    lines.on("line", (line) => connection.write(`${handle(line)}\n`));

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

/** Encodes a file through the socket, decodes it and compares. Throws when anything is wrong. */
export async function test(): Promise<void> {
  const content = "test of the encoding\n";

  const dir = mkdtempSync(join(tmpdir(), "gits-demo-"));

  const plain = join(dir, "plain");
  const encoded = join(dir, "encoded");
  const back = join(dir, "back");

  const quote = (path: string) => JSON.stringify(path);

  try {
    writeFileSync(plain, content);

    const replies = await ask([
      `encode ${quote(plain)} ${quote(encoded)}`,
      `decode ${quote(encoded)} ${quote(back)}`,
    ]);

    const failed = replies.find((reply) => !reply.startsWith("ok "));

    if (failed) {
      throw th(`the server replied >${failed}<`);
    }

    if (isEncoded(readFileSync(encoded, "latin1")) === null) {
      throw th("the file was not encoded");
    }

    if (readFileSync(back, "utf8") !== content) {
      throw th("decoded file differs");
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
