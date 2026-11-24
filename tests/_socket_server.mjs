/**
 * Stand-in for the encoder process of submodules/encrypt (examples/socket/server.ts), for tests only.
 * It speaks the same protocol on a unix socket, the "encryption" is base64 of every line:
 *
 *   node tests/_socket_server.mjs <socket path> <key>
 *
 *   encode "<plain file>" "<encrypted file>"   ->  ok encode "<encrypted file>" 0ms
 *   decode "<encrypted file>" "<plain file>"   ->  ok decode "<plain file>" 0ms
 *                                                  error MALFORMED not an ssenc1 file ...   (input is not an encoded file)
 *                                                  error AUTH ...                           (encoded with another key)
 *
 * What it has in common with the real one, because gits relies on it:
 *   - a line which was not edited is encoded to the same text, so only edited lines change
 *   - a file which is not an encoded one is answered with MALFORMED, a wrong key with AUTH
 *   - nothing is written when the request fails
 */
import { createServer } from "node:net";
import { createInterface } from "node:readline";
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";

const [socketPath, key] = process.argv.slice(2);

if (!socketPath || !key) {
  console.error("tests/_socket_server.mjs error: usage: node tests/_socket_server.mjs <socket path> <key>");
  process.exit(1);
}

const HEADER = "#ssenc1 fake";
const QUOTED = String.raw`"(?:[^"\\]|\\.)*"`;
const REQUEST = new RegExp(String.raw`^\s*(encode|decode)\s+(${QUOTED})\s+(${QUOTED})\s*$`);

function handle(line) {
  const found = REQUEST.exec(line);
  if (!found) {
    return `error USAGE not a request >${line}<`;
  }
  const command = found[1];
  const input = JSON.parse(found[2]);
  const output = JSON.parse(found[3]);

  if (!input.startsWith("/") || !output.startsWith("/")) {
    return `error USAGE paths have to be absolute, got >${input}< >${output}<`;
  }
  if (!existsSync(input)) {
    return `error ENV input file doesn't exist >${input}<`;
  }

  const content = readFileSync(input, "latin1");

  if (command === "encode") {
    const lines = content.split("\n").map((l) => Buffer.from(`${key}|${l}`, "latin1").toString("base64"));
    writeFileSync(output, [`${HEADER} key=${key}`, ...lines].join("\n") + "\n", "latin1");
  } else {
    const [header, ...lines] = content.split("\n");
    if (!header.startsWith(HEADER)) {
      return "error MALFORMED not an ssenc1 file (missing '#ssenc1' header)";
    }
    if (header !== `${HEADER} key=${key}`) {
      return "error AUTH no key slot could be opened with the given key";
    }
    // the last element is the empty text after the final newline of the encoded file
    lines.pop();
    const plain = lines.map((l) => Buffer.from(l, "base64").toString("latin1").slice(key.length + 1));
    writeFileSync(output, plain.join("\n"), "latin1");
  }
  return `ok ${command} ${JSON.stringify(output)} 0ms`;
}

const server = createServer((socket) => {
  socket.on("error", () => socket.destroy());
  createInterface({ input: socket }).on("line", (line) => {
    let reply;
    try {
      reply = handle(line);
    } catch (e) {
      reply = `error ENV ${String(e.message).replace(/\s+/g, " ")}`;
    }
    console.log(`${line}   ->   ${reply}`);
    socket.write(reply + "\n");
  });
});

const stop = () => {
  server.close();
  try {
    unlinkSync(socketPath);
  } catch {}
  process.exit(0);
};

process.on("SIGTERM", stop);
process.on("SIGINT", stop);

server.listen(socketPath, () => console.log(`listening on ${socketPath}`));
