# gits doesn't know what "encrypted" means: base64 + md5 behind the socket

`gits` stores some files encoded (elements `SOURCE:e:TARGET` of the config), but it never
encodes anything by itself: it sends requests to a process listening on a unix socket. What that
process does with a file is its own business.

The two other demos ([examples/encrypt](../encrypt/ENCRYPT_PROCESS.md),
[examples/encrypt_os_ssh_agent](../encrypt_os_ssh_agent/ENCRYPT_PROCESS.md)) put real encryption
behind the socket: the binary `ssenc` of [encrypt](https://github.com/stopsopa/encrypt), ssh
keys, an ssh-agent. This one puts there the most primitive thing possible, to show that gits
works the same, because it is not tied to that project:

```
<md5 of the base64 text>:<base64 of the content of the file>
```

One line. For `API_KEY=repoa-abc123` + `DB_PASSWORD=repoa-secret`:

```
e4a146662f49e4b2ef9318f33bca65f2:QVBJX0tFWT1yZXBvYS1hYmMxMjMKREJfUEFTU1dPUkQ9cmVwb2Etc2VjcmV0Cg==
```

**It protects nothing.** Anybody can turn base64 back, there is no key. Don't use it for
secrets. It has only the two properties gits relies on: it can be turned back, and an encoded
file can be told from a plain one (split at the `:`, compute the md5 of the second part, compare
with the first).

## What gits knows, and from where

Three things, none of them about a format:

| What | Where it comes from | In this demo |
|---|---|---|
| how a file is encoded and decoded | the requests `encode "<in>" "<out>"` / `decode "<in>" "<out>"` to `GITS_ENCRYPTION_SOCKET`, the reply `ok ...` or `error <KIND> <message>` | [server.ts](server.ts) |
| "this file is not an encoded one" while decoding | the reply `error MALFORMED ...`. gits then uses the stored file as it is (a `:e:` file stored before there was a socket) | [server.ts](server.ts), `decode()` |
| whether a stored file is an encoded one, **without** the socket (`gits crypt status`, the error "stored encrypted but there is no socket", what `crypt encrypt` / `decrypt` have to do) | the script of `GITS_ENCRYPTION_DETECT`: `<script> <file>`, exit code 0 yes, 1 no | [detect.sh](detect.sh) |

The third one is the only place where gits has a rule of its own: without
`GITS_ENCRYPTION_DETECT` it recognises the files of the encrypt project (`#ssenc1 ...` +
`#slot ...`). With the variable that rule is not used at all.

```
/bin/bash examples/base64_md5/gits.sh diff
        |
        |  defines the env vars (env.sh), GITS_START=start.sh, GITS_EXIT=stop.sh, starts the gits binary
        v
      gits ---- GITS_START -----> start.sh   once: server.ts on the socket + a test
        |
        |  ... encode / decode requests to the socket ...           -> server.ts
        |  ... "is this stored file an encoded one?" ...            -> detect.sh
        |
        +------ GITS_EXIT ------> stop.sh    once, the last thing: the server stopped
```

Everything is in `examples/base64_md5/`:

| File | |
|---|---|
| [env.sh](env.sh) | every env var of the demo, in one place. The other scripts source it |
| [server.ts](server.ts) | the server behind the socket: the whole "encryption" is two small functions, `encode()` and `decode()` |
| [detect.sh](detect.sh) | tells gits whether a stored file is an encoded one (`GITS_ENCRYPTION_DETECT`) |
| [start.sh](start.sh) | starts the server, tests it |
| [stop.sh](stop.sh) | stops it |
| [gits.sh](gits.sh) | the wrapper you call in place of `gits` |
| [reset_setup.sh](reset_setup.sh) | brings the demo to its state 0: removes and creates again everything below |
| `package.json` | one line, `"type": "module"`: `server.ts` is an ES module |
| `gits_source/` | generated: the storage, a local git repository (`GITS_SOURCE` of the demo) |
| `GITS_PULL_TO_SYNC/` | generated: the clone of the storage which gits keeps between its commands |
| `repoa/`, `repob/` | generated: two projects to play with |
| `tmp/` | generated: socket and pid file of the server |
| `server.log` | generated: log of the server |

Everything generated is ignored by git.

Needs: Node.js >= 22.18 (it runs `server.ts` directly, nothing is built) and the compiled gits
(`/bin/bash compile.sh`). No ssh key, no ssh-agent, no other repository, no `pnpm`.

All commands below are run from the root of this repository.

## 1. State 0: reset_setup.sh

```sh
/bin/bash examples/base64_md5/reset_setup.sh
```

The first command, and again whenever you want to start from scratch. It creates the storage
(`gits_source/`, empty) and two projects with `.git/gits.sh` already made by `gits init` and
`gits add`:

```sh
cat examples/base64_md5/repoa/.git/gits.sh
```

```sh
GITS_TARGETDIR="git@github.com:demo__repoa.git"
GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
    "../.env:e:$GITS_TARGETDIR/.env"                               # :e: stored encoded
    "../config/local.json::$GITS_TARGETDIR/config/local.json"      # ::  stored as it is
)
```

`repob` has three `:e:` files, one of them binary (`secrets/cert.bin`). Nothing is pushed yet.

## 2. The variables: env.sh

| Variable | Default | |
|---|---|---|
| `GITS_SOURCE` | `examples/base64_md5/gits_source` | **the storage.** gits reads it. Always the one of the demo: `GITS_SOURCE` of your terminal is ignored |
| `GITS_PULL_TO_SYNC` | `examples/base64_md5/GITS_PULL_TO_SYNC` | the clone of the storage, kept between the commands. gits reads it. Always the one of the demo |
| `GITS_ENCRYPTION_SOCKET` | `examples/base64_md5/tmp/base64_md5.sock` | **the socket.** gits reads it: where it sends its requests. Defined as an empty text (`GITS_ENCRYPTION_SOCKET= /bin/bash gits.sh ...`): no socket, the wrapper starts gits without it and without `start.sh` / `stop.sh` |
| `GITS_ENCRYPTION_DETECT` | `examples/base64_md5/detect.sh` | **the detection.** gits reads it: the script which says whether a stored file is an encoded one. Defined as an empty text: the built-in rule of gits (step 6) |
| `GITS_DEMO_LOG` | `examples/base64_md5/server.log` | log of the server. Empty (`GITS_DEMO_LOG=""`): no log |
| `GITS_DEMO_BIN` | `bin/<arch>/gits` | the gits binary `gits.sh` starts |
| `GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES` | `examples/base64_md5` | where everything generated goes |

## 3. The server and the format by hand

Not needed for the rest (gits calls `start.sh` and `stop.sh` itself), only to see the whole
"encryption" of this demo:

```sh
/bin/bash examples/base64_md5/start.sh; echo "exit code $?"     # 0: the server answers, a file went there and back

# one request: the line goes to the socket, the reply line is printed
function ask { (echo "${1}"; sleep 0.3) | nc -U examples/base64_md5/tmp/base64_md5.sock; }

mkdir -p examples/base64_md5/tmp/hand
H="${PWD}/examples/base64_md5/tmp/hand"
printf "hello\n" > "${H}/plain.txt"

ask "encode \"${H}/plain.txt\" \"${H}/encoded.txt\""          # ok encode ".../hand/encoded.txt"
cat "${H}/encoded.txt"                    # 6b70b3a2e20c0f3fe876d8a107b7753d:aGVsbG8K
```

Take it apart with the tools of your system, nothing of the demo:

```sh
cut -d : -f 2 "${H}/encoded.txt" | base64 -d                  # hello
cut -d : -f 2 "${H}/encoded.txt" | tr -d "\n" | md5           # macOS. Linux: md5sum. The same text as before the colon
```

And back, and what the server says to a file which is not an encoded one:

```sh
ask "decode \"${H}/encoded.txt\" \"${H}/back.txt\""           # ok decode ".../hand/back.txt"
diff "${H}/plain.txt" "${H}/back.txt" && echo identical

ask "decode \"${H}/plain.txt\" \"${H}/x.txt\""                # error MALFORMED not a base64_md5 file ...
ask "rekey \"${H}/encoded.txt\" \"${H}/x.txt\""               # error USAGE rekey: there are no keys in base64_md5 ...
```

The script gits uses for the same question, without the server:

```sh
/bin/bash examples/base64_md5/detect.sh "${H}/encoded.txt"; echo "exit code $?"     # md5:6b70b3a2...   exit code 0
/bin/bash examples/base64_md5/detect.sh "${H}/plain.txt"; echo "exit code $?"       # exit code 1

rm -rf examples/base64_md5/tmp/hand
/bin/bash examples/base64_md5/stop.sh
```

## 4. gits through the wrapper

One way through, from state 0:

```sh
cd examples/base64_md5

/bin/bash gits.sh state                   # both projects: files are not in sync (nothing stored yet)

cd repoa
/bin/bash ../gits.sh push --yes           # '../.env' -> '.../.env' (encrypted)
cd ../repob
/bin/bash ../gits.sh push --yes
cd ..

/bin/bash gits.sh state                   # COUNT_SUCCESS : 2

cat "gits_source/git@github.com:demo__repoa.git/.env"                 # <md5>:<base64>, one line
cat "gits_source/git@github.com:demo__repoa.git/config/local.json"    # as it is (a :: element)
cat "gits_source/git@github.com:demo__repob.git/secrets/cert.bin"     # the binary file: the same form
cat repoa/.env                            # the local file is as it was

cd repoa
/bin/bash ../gits.sh isinsync; echo "exit code $?"                    # 0
echo "API_KEY=changed" > .env
/bin/bash ../gits.sh diff                 # -API_KEY=repoa-abc123 +API_KEY=changed: compared decoded
/bin/bash ../gits.sh pull --yes           # storage -> local files: .env is back
cat .env
cd ..
```

gits says "encrypted" in its messages: that is its word for "went through the socket". What
really happened is in the log:

```sh
cat server.log                            # encoded .../repoa/.env -> .../GITS_PULL_TO_SYNC/git@github.com:demo__repoa.git/.env
```

## 5. gits crypt: the form of what is stored

```sh
/bin/bash gits.sh crypt status all        # still in examples/base64_md5
```

```
':e:' files of all projects below the current directory, as they are stored:

  encrypted  git@github.com:demo__repoa.git/.env  [md5:e4a146662f49e4b2ef9318f33bca65f2]
  encrypted  git@github.com:demo__repob.git/.env.local  [md5:...]
  encrypted  git@github.com:demo__repob.git/secrets/cert.bin  [md5:...]
  encrypted  git@github.com:demo__repob.git/secrets/token.txt  [md5:...]

encrypted: 4, plain: 0, not stored yet: 0
```

No socket is used for this. For every file gits ran `detect.sh <file>`: exit code 0 made the
line `encrypted`, and what the script printed (`md5:...`) is what stands in `[...]`. With real
encryption that place shows the fingerprint of the key which opens the file; here there is no
key, so the script prints the checksum. It could print anything, or nothing.

The other verbs work the same way as with real encryption, one clone, one commit, one push:

```sh
/bin/bash gits.sh crypt decrypt --storage         # the list of what would change
/bin/bash gits.sh crypt decrypt --storage --yes   # every encoded file of the storage is plain again
cat "gits_source/git@github.com:demo__repoa.git/.env"                 # plain text
(cd repoa && GITS_ENCRYPTION_SOCKET= /bin/bash ../gits.sh diff)       # works without the socket: nothing is encoded

/bin/bash gits.sh crypt encrypt all --yes         # the ':e:' files of both projects encoded again
/bin/bash gits.sh crypt status all                # encrypted: 4

(cd repoa && GITS_ENCRYPTION_SOCKET= /bin/bash ../gits.sh diff)       # ... is stored encrypted but env var GITS_ENCRYPTION_SOCKET is not defined
```

The last line is `detect.sh` again: without a socket gits has nobody to ask, and it still knows
that the stored file can't be used as it is.

`rekey` makes no sense here, and it is the server which says so:

```sh
/bin/bash gits.sh crypt rekey --storage --yes     # USAGE rekey: there are no keys in base64_md5 ... Nothing was changed in the storage
```

## 6. Without GITS_ENCRYPTION_DETECT

Defined as an empty text the wrapper removes the variable, and gits uses its built-in rule, which
knows only the files of the encrypt project:

```sh
GITS_ENCRYPTION_DETECT= /bin/bash gits.sh crypt status all            # encrypted: 0, plain: 4
```

The four files are still encoded in the storage, gits just can't tell. With the socket `diff`,
`push` and `pull` keep working (there the server decides, with its `error MALFORMED`), but
everything which looks at a stored file without the server is wrong: `crypt status`,
`crypt decrypt` finds nothing to do, and without the socket gits would copy the encoded text into
your project as if it was the content. That is what the variable is for: **another format behind
the socket needs its own detection script.**

## 7. For another format of your own

- the server: answer `encode "<in>" "<out>"` and `decode "<in>" "<out>"` with `ok <command> "<out>"`
  after the output file is written, or with `error <KIND> <message>`. `MALFORMED` for a file
  which is not in your format, `AUTH` when the key doesn't open it. `rekey` / `rewrap` only when
  you have keys to change
- the script of `GITS_ENCRYPTION_DETECT`: exit code 0 for a file in your format (what it prints
  is shown by `gits crypt status`), 1 for any other file, another code for an error. It gets one
  argument, the absolute path of the file. It should be fast: `crypt ... --storage` runs it for
  every file of the storage
- gits itself: nothing to change

## 8. Clean up

Back to state 0: `/bin/bash examples/base64_md5/reset_setup.sh`. To remove everything generated,
from the root of this repository:

```sh
/bin/bash examples/base64_md5/stop.sh
rm -rf examples/base64_md5/tmp examples/base64_md5/gits_source examples/base64_md5/GITS_PULL_TO_SYNC examples/base64_md5/repoa examples/base64_md5/repob examples/base64_md5/server.log
```
