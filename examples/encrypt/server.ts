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
 * The server decides nothing about a file: text or binary is detected by the library (mode "auto").
 *
 * (a path is written like a JSON string). The encryption itself is the library of
 * https://github.com/stopsopa/encrypt with an ssh key held by ssh-agent.
 *
 * Usage (started by examples/encrypt/start.sh, which defines the variables from examples/encrypt/env.sh):
 *
 *   node examples/encrypt/server.ts          the server: listens until it is killed
 *   node examples/encrypt/server.ts test     a client: encrypts a file through the socket, decrypts it
 *                                    and compares. Exit code 0 when the server works
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
  if (!value) throw th(`env var ${name} is not defined`);
  return value;
}

/** One request line -> one reply line. */
export async function handle(line: string): Promise<string> {
  const { encrypt, decrypt, rekey } = await import(`${env("GITS_DEMO_ENCRYPT")}/typescript/dist/ssenc.node.ts`);
  const ssh = (file: string) => ({ type: "ssh", publicKey: readFileSync(`${file}.pub`, "utf8") });
  const done: Record<string, string> = { encode: "encrypted", decode: "decrypted", rekey: "rekeyed", rewrap: "rewrapped" };
  try {
    const key = ssh(env("GITS_DEMO_SSH_KEY"));
    const found = /^(encode|decode|rekey|rewrap) ("(?:[^"\\]|\\.)*") ("(?:[^"\\]|\\.)*")$/.exec(line.trim());
    if (!found) throw th(`not a request >${line}<`);
    const [command, input, output] = [found[1], JSON.parse(found[2]), JSON.parse(found[3])];
    if (command === "encode") {
      // an encrypted file which is already there is reused: only the edited lines change in it
      const previous = existsSync(output) ? readFileSync(output) : undefined;
      const reuse = previous?.subarray(0, 8).toString("latin1") === "#ssenc1 ";
      writeFileSync(output, await encrypt(readFileSync(input), key, reuse ? { mode: "auto", previous } : { mode: "auto" }));
    } else if (command === "decode") {
      writeFileSync(output, await decrypt(readFileSync(input), key));
    } else {
      if (!process.env.GITS_DEMO_NEW_SSH_KEY) throw th(`${command}: the server was started without GITS_DEMO_NEW_SSH_KEY`);
      const options = { rotateDataKey: command === "rekey" };
      writeFileSync(output, await rekey(readFileSync(input), key, ssh(env("GITS_DEMO_NEW_SSH_KEY")), options));
    }
    console.log(`${new Date().toISOString()} ${done[command]} ${input} -> ${output}`);
    return `ok ${command} ${JSON.stringify(output)}`;
  } catch (e) {
    // the kind (USAGE, AUTH, MALFORMED, ENV) tells gits e.g. that a file is not encrypted at all
    const error = e as Error & { kind?: string };
    console.log(`${new Date().toISOString()} error ${line.trim()}: ${error.message}`);
    return `error ${error.kind ?? "USAGE"} ${error.message.replace(/\s+/g, " ")}`;
  }
}

/** Listens on the socket; requests of one connection are answered in their order. */
export function server(): void {
  const umask = process.umask(0o077); // only the owner can connect
  createServer((socket) => {
    let queue = Promise.resolve();
    createInterface({ input: socket }).on("line", (line) => {
      queue = queue.then(async () => void socket.write((await handle(line)) + "\n"));
    });
    socket.on("error", () => socket.destroy());
  }).listen(env("GITS_ENCRYPTION_SOCKET"), () => {
    process.umask(umask);
    console.log(`${new Date().toISOString()} listening on ${env("GITS_ENCRYPTION_SOCKET")}`);
  });
}

/** Sends the requests through the socket one after another, resolves with the replies. */
function ask(requests: string[]): Promise<string[]> {
  return new Promise((resolve, reject) => {
    const replies: string[] = [];
    const socket = connect(env("GITS_ENCRYPTION_SOCKET"));
    socket.on("error", (e) => reject(th(`can't connect to the socket: ${e.message}`)));
    createInterface({ input: socket }).on("line", (line) => {
      replies.push(line);
      if (replies.length === requests.length) {
        socket.end();
        resolve(replies);
      } else {
        socket.write(requests[replies.length] + "\n");
      }
    });
    socket.write(requests[0] + "\n");
  });
}

/** Encrypts a file through the socket, decrypts it and compares. Throws when anything is wrong. */
export async function test(): Promise<void> {
  const dir = mkdtempSync(join(tmpdir(), "gits-demo-"));
  try {
    const [plain, encrypted, back] = ["plain", "encrypted", "back"].map((name) => JSON.stringify(join(dir, name)));
    writeFileSync(JSON.parse(plain), "test of the encryption\n");
    const replies = await ask([`encode ${plain} ${encrypted}`, `decode ${encrypted} ${back}`]);
    const failed = replies.find((reply) => !reply.startsWith("ok "));
    if (failed) throw th(`the server replied >${failed}<`);
    if (!readFileSync(JSON.parse(encrypted), "utf8").startsWith("#ssenc1 ")) throw th("the file was not encrypted");
    if (readFileSync(JSON.parse(back), "utf8") !== "test of the encryption\n") throw th("decrypted file differs");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

if (import.meta.main) {
  if (process.argv[2] === "test") {
    test().catch((e) => {
      console.error((e as Error).message);
      process.exit(1);
    });
  } else {
    server();
  }
}
