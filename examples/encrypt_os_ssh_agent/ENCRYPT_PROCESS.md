# Encryption which starts and stops with gits, with a key from your own ssh-agent

A self-contained demo. `gits` stores some files encrypted (elements `SOURCE:e:TARGET` of the
config), but it never encrypts by itself: it sends requests to a process listening on a unix
socket. Here that process lives only as long as one `gits` command, and the key it encrypts
with is taken from **the ssh-agent which is already running in your terminal** (`SSH_AUTH_SOCK`):
a separate key, only for gits, loaded there by you next to the keys you already have.

The same demo with an agent of its own, which never touches yours:
[examples/encrypt](../encrypt/ENCRYPT_PROCESS.md). Why and how one agent can serve both your
GitHub key and a key for gits: [USE_OS_SSH_WITH_SEPARATE_SSH_KEY.md](USE_OS_SSH_WITH_SEPARATE_SSH_KEY.md).

```
/bin/bash examples/encrypt_os_ssh_agent/gits.sh diff
        |
        |  defines the env vars (env.sh), GITS_START=start.sh, GITS_EXIT=stop.sh, starts the gits binary
        v
      gits ---- GITS_START -----> start.sh   once, before anything else:
        |                                    server.js on the socket
        |                                    + a test: a file encrypted, decrypted, compared
        |                                      (it fails when the key is not in your ssh-agent).
        |                                    gits waits. A failure stops gits.
        |
        |  ... the command itself: encode / decode requests to the socket ...
        |
        +------ GITS_EXIT ------> stop.sh    once, the last thing:
                                             server stopped, its socket removed.
                                             Your agent and the keys in it are not touched.
                                             Always: also after an error, Ctrl+C, kill.
```

`GITS_START` and `GITS_EXIT` are not lifecycle events of a command (those are
`GITS_DIFF_START`, `GITS_PUSH_BEFORE_COPY`, ... see `gits --help`): each is one variable for
every command, and its script runs exactly once in one start of gits.

Everything is in `examples/encrypt_os_ssh_agent/`:

| File | |
|---|---|
| [env.sh](env.sh) | every env var of the demo, in one place. The other scripts source it |
| [keys.sh](keys.sh) | creates two ssh keys in `keys/`: `key` (in use) and `key2` (to change to), and says whether they are loaded in your agent. It loads nothing itself |
| [start.sh](start.sh) | starts the server and tests the encryption. It doesn't look into the agent: a key which is not loaded makes the test fail |
| [stop.sh](stop.sh) | stops the server |
| [server.ts](server.ts) | the server behind the socket: request, work, reply, socket, test, in that order |
| [encrypt.sh](encrypt.sh) | copies the binary which encrypts (`ssenc`) to `bin/` and turns `server.ts` into `server.js` (esbuild) |
| `package.json` | one line, `"type": "module"`: `server.js` is an ES module |
| [USE_OS_SSH_WITH_SEPARATE_SSH_KEY.md](USE_OS_SSH_WITH_SEPARATE_SSH_KEY.md) | what an ssh-agent is, how `ssenc` picks a key in it, a separate key next to your GitHub key |
| [../encrypt/ENCRYPT_IN_GITS_PLAN.md](../encrypt/ENCRYPT_IN_GITS_PLAN.md) | the design of what steps 6 and 7 show: gits without the socket, `gits crypt` |
| [gits.sh](gits.sh) | the wrapper you call in place of `gits` |
| [reset_setup.sh](reset_setup.sh) | brings the demo to its state 0: removes and creates again everything below (the keys: kept as files, taken out of your agent) |
| `gits_source/` | generated: the storage, a local git repository (`GITS_SOURCE` of the demo) |
| `repoa/`, `repob/` | generated: two projects to play with |
| `keys/` | generated: the two keys. The files are not removed by `reset_setup.sh` |
| `tmp/` | generated: socket and pid file of the server |
| `server.js` | generated: what `start.sh` runs, `server.ts` as JavaScript |
| `bin/ssenc` | generated: a copy of the Rust binary of [encrypt](https://github.com/stopsopa/encrypt), the program which really encrypts |
| `server.log` | generated: log of the server |

Everything generated is ignored by git.

Needs: an ssh-agent running in your terminal (`echo "${SSH_AUTH_SOCK}"`, `ssh-add -l`),
Node.js >= 22.18, `pnpm`, `ssh-keygen` / `ssh-add` and the compiled gits
(`/bin/bash compile.sh`) and a checkout of [encrypt](https://github.com/stopsopa/encrypt) in
`__linked/STOPSOPA__encrypt/STOPSOPA__encrypt` or `submodules/encrypt` (with `cargo`, when its
binary is not built yet), or the `ssenc` binary installed by you (`GITS_DEMO_SSENC`).

Who does what: gits sends a request to the socket, `server.js` listens there and starts the
binary `ssenc` for every request, `ssenc` asks the ssh-agent of `SSH_AUTH_SOCK` and writes the file.

**Your own ssh-agent is used.** No script of the demo starts an agent or stops one, and none
loads a key: loading the two keys of the demo is a step you do yourself
([step 3](#3-the-keys-ssh-add)). The only thing a script changes in your agent:
`reset_setup.sh` takes out **every key which has `gits` in its label** (`ssh-add -d`; the label
is the last column of `ssh-add -l`), so that every start from scratch begins with "the keys are
not loaded". That is the two keys of the demo (`gits-os-agent-demo-key`, `...-key2`), and also
any other key with such a label, e.g. `gits-demo-key` or a `gits-encryption` of your own: after a
reset load that one again yourself. Keys without `gits` in the label are not used and not changed.

All commands below are run from the root of this repository.

## The order

`reset_setup.sh` is the preparation of everything, and the way back to the beginning. Nothing
else has to be prepared by hand:

| Step | | Before it |
|---|---|---|
| 1 | `reset_setup.sh`: state 0 | nothing. **Always the first command** |
| 2 | the variables | only reading |
| 3 | the keys: what happens without them, then `ssh-add` | step 1 (it created them). **Again after every `reset_setup.sh`**: it takes the keys out of your agent |
| 4 | the server by hand | step 3 (it needs the key in the agent) |
| 5 | gits through the wrapper | step 3. Played before? run `reset_setup.sh` and the `ssh-add` of step 3 again: the step expects an empty storage |
| 6 | the whole storage plain / encrypted / another key | `reset_setup.sh` again and `ssh-add` (the first commands of the step) |
| 7 | rekey | `reset_setup.sh` again and `ssh-add` (the first commands of the step) |

Steps 5, 6 and 7 are three independent ways through, each one starts from state 0. Whenever
something doesn't look like the guide says (a file not in sync, an `AUTH` error because the
storage is stored with `key2` from an earlier step): `/bin/bash examples/encrypt_os_ssh_agent/reset_setup.sh`,
the `ssh-add` of step 3, and start the step again. It can be run at any moment and as many times as you want; it removes
only what it generated itself, and from your agent only the keys with `gits` in their label.

## 1. State 0: reset_setup.sh

```sh
/bin/bash examples/encrypt_os_ssh_agent/reset_setup.sh
```

The first command of the demo, and again whenever you want to start from scratch (see
[the order](#the-order)). It stops what runs, takes every key with `gits` in its label out of
your agent (`removed from the ssh-agent: gits-os-agent-demo-key`, ...), removes everything
generated and creates it again:

| | |
|---|---|
| `gits_source/` | the storage: an empty git repository. Not bare, so after a push its files can be looked at |
| `repoa/` | a project. In git: `README.md`, `src/app.js`, `config/default.json`. Ignored by git: `.env`, `config/local.json` |
| `repob/` | a project. In git: `README.md`, `main.sh`. Ignored by git: `.env.local`, `secrets/token.txt`, `secrets/cert.bin` (binary), `notes.txt` |
| `keys/key`, `keys/key2` | the two keys (and their `.pub`): created the first time, the files are **kept** by every next reset. Not loaded in the agent after it |
| `server.js`, `bin/ssenc` | built / copied again by [encrypt.sh](encrypt.sh) |

`encrypt.sh` does three things:

1. copies the binary `rust/target/release/ssenc` from the checkout of
   [encrypt](https://github.com/stopsopa/encrypt) to `bin/ssenc` (and builds it there first, when
   it is not built: `rust/compile.sh`). Skipped when `GITS_DEMO_SSENC` points to your own binary
2. `pnpm install` in the root of this repository, only when `esbuild` is not there yet
3. `esbuild`: `server.ts` -> `server.js`

```sh
/bin/bash examples/encrypt_os_ssh_agent/encrypt.sh     # after an edit of server.ts (start.sh does it too)
```

In both projects it already ran, through the wrapper, `gits init` (creates `.git/gits.sh`)
and `gits add` for the ignored files (`gits add -e` for the secret ones):

```sh
cat examples/encrypt_os_ssh_agent/repoa/.git/gits.sh
```

```sh
GITS_TARGETDIR="git@github.com:demo__repoa.git"
GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
    "../.env:e:$GITS_TARGETDIR/.env"                               # :e: stored encrypted
    "../config/local.json::$GITS_TARGETDIR/config/local.json"      # ::  stored as it is
)
```

It needs no key in the agent: `gits init` and `gits add` encrypt nothing, and the script calls
the wrapper without the socket for them.

It ends with `state 0 is ready`, and with the `ssh-add` command of step 3: after a reset the
keys are never loaded. Nothing is pushed yet. The remote `origin` of the projects (`git@github.com:demo/repoa.git`)
is never contacted: gits only takes the name of the directory in the storage from it.

## 2. The variables: env.sh

| Variable | Default | |
|---|---|---|
| `GITS_SOURCE` | `examples/encrypt_os_ssh_agent/gits_source` | **the storage.** gits reads it. Always the one of the demo: `GITS_SOURCE` of your terminal (your real storage) is ignored, the demo can't push there. Somewhere else: `GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES` |
| `GITS_ENCRYPTION_SOCKET` | `examples/encrypt_os_ssh_agent/tmp/ssenc.sock` | **the socket.** gits reads it: where it sends its requests. At most about 100 characters. Defined as an empty text (`GITS_ENCRYPTION_SOCKET= /bin/bash gits.sh ...`): no socket, the wrapper starts gits without it and without `start.sh` / `stop.sh` |
| `GITS_ENCRYPTION_SSH_KEY` | the fingerprint of `keys/key`: `$(ssh-keygen -lf keys/key.pub \| cut -d " " -f 2)` | the one variable which says which ssh key is used: it encrypts and it opens what is stored. The key has to be loaded in the agent; this only says **which** of the keys there, by its fingerprint: `SHA256:...`, the second word of what `ssh-keygen -lf <file>.pub` and `ssh-add -l` print. Not a path: once a key is loaded, no file of it is needed. It goes to `ssenc --ssh-key` as it is. Only `start.sh` and `server.ts` use it |
| `GITS_ENCRYPTION_REKEY_SSH_KEY` | empty | empty by default and it should stay so. Only for the one example of step 7, `gits crypt rekey`, which needs two keys at the same time: the key the stored files get in place of `GITS_ENCRYPTION_SSH_KEY`. A fingerprint too, given only in that command. That key has to be loaded in the agent too |
| `SSH_AUTH_SOCK` | the one of your terminal | **not defined by the demo.** The ssh-agent: `start.sh` asks it which keys it has, `ssenc` asks it to sign. Whatever your terminal has is used |
| `GITS_DEMO_LOG` | `examples/encrypt_os_ssh_agent/server.log` | log of the server. Empty (`GITS_DEMO_LOG=""`): no log |
| `GITS_DEMO_SSENC` | `examples/encrypt_os_ssh_agent/bin/ssenc` | the binary `server.js` starts for every request: `rust/target/release/ssenc` of the encrypt repository. A path, or a name found in `PATH` (`GITS_DEMO_SSENC=ssenc` when you installed it) |
| `GITS_DEMO_ENCRYPT` | `__linked/STOPSOPA__encrypt/STOPSOPA__encrypt`, then `submodules/encrypt` | only `encrypt.sh`: the checkout the binary is copied from |
| `GITS_DEMO_BIN` | `bin/<arch>/gits` | the gits binary `gits.sh` starts |
| `GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES` | `examples/encrypt_os_ssh_agent` | where everything generated goes: `gits_source/`, `repoa/`, `repob/`, `keys/`, `tmp/`, `server.log` |

A variable defined in the terminal wins over the default (besides `GITS_SOURCE`): `GITS_DEMO_LOG="" /bin/bash examples/encrypt_os_ssh_agent/gits.sh diff`.

## 3. The keys: ssh-add

Step 1 created the files, and nothing loaded them anywhere:

```sh
ls examples/encrypt_os_ssh_agent/keys     # key key.pub key2 key2.pub
ssh-add -l                                # your own keys, none of the demo (gits-os-agent-demo-...)
```

`key` is the one in use, `key2` is there to change to (steps 6 and 7). Both without a
passphrase, to keep the demo short; a real key should have one, see [step 9](#9-for-real).

**First without the key.** Try to use the encryption now. The wrapper starts `start.sh`, the
server starts, and its test asks `ssenc` to encrypt a file. `ssenc` asks your agent for the key
with the fingerprint of `GITS_ENCRYPTION_SSH_KEY`, and the agent doesn't have it:

```sh
cd examples/encrypt_os_ssh_agent/repoa
/bin/bash ../gits.sh push --yes; echo "exit code $?"
#   examples/encrypt_os_ssh_agent/server.ts error: the server replied >error ENV key SHA256:... is not loaded in ssh-agent (check: ssh-add -l)<
#   .../start.sh error: encryption through GITS_ENCRYPTION_SOCKET=>...< doesn't work, log: ...
#   gits error: GITS_START: script >.../start.sh< ended with exit code 1
#   exit code 1
ls ../gits_source                         # nothing was pushed
ls ../tmp                                 # empty: stop.sh ran, no server is left
cd ../../..
```

gits stopped before it did anything: nothing is stored, and nothing was stored plain in place of
encrypted. That is what happens every time the key is missing (a new session, a restart of the
machine, after `reset_setup.sh`).

**Now load them.** The one thing of this demo which you do by hand:

```sh
ssh-add examples/encrypt_os_ssh_agent/keys/key examples/encrypt_os_ssh_agent/keys/key2
ssh-add -l                                # two more lines: ... gits-os-agent-demo-key (ED25519), ... gits-os-agent-demo-key2 (ED25519)
/bin/bash examples/encrypt_os_ssh_agent/keys.sh        # the key is already there (twice), both keys are loaded in the ssh-agent of this terminal
```

From now on the agent can sign with them, and the two private key files are not read by anything
any more. What tells `ssenc` which of the loaded keys to use is `GITS_ENCRYPTION_SSH_KEY`: the
fingerprint of the key, the text `ssh-add -l` shows for it. `ssh-keygen -lf` prints it for a
public key file, as the second word of its line:

```sh
ssh-keygen -lf examples/encrypt_os_ssh_agent/keys/key.pub                      # 256 SHA256:... gits-os-agent-demo-key (ED25519)
ssh-keygen -lf examples/encrypt_os_ssh_agent/keys/key.pub | cut -d " " -f 2    # SHA256:...     <- the value of the variable
```

`env.sh` runs exactly that for its default, and every command below which needs the other key
gives `"$(ssh-keygen -lf keys/key2.pub | cut -d " " -f 2)"`: the demo generates its keys, so it
can't have their fingerprints written down. With a key of your own you write the fingerprint
itself (`GITS_ENCRYPTION_SSH_KEY="SHA256:..."`), and the `.pub` file is not needed either.

The encryption works now. A command which changes nothing, to see it (the push itself is step 5):

```sh
(cd examples/encrypt_os_ssh_agent/repoa && /bin/bash ../gits.sh diff)     # no error any more: the files are compared (nothing is stored yet)
```

The keys stay loaded until `reset_setup.sh` takes them out, you remove them
([step 10](#10-clean-up)), the agent is restarted (a restart of the machine), or you log out.
After that: the `ssh-add` line again.

`reset_setup.sh` keeps the key files and only unloads the keys (every loaded key with `gits`
in its label). `keys.sh` by itself creates a
key which is missing, never replaces one, and says which of them the agent doesn't have:

```sh
/bin/bash examples/encrypt_os_ssh_agent/keys.sh
```

Your other keys keep working as before. With more keys in the agent `ssh` offers all of them to a
server, [USE_OS_SSH_WITH_SEPARATE_SSH_KEY.md](USE_OS_SSH_WITH_SEPARATE_SSH_KEY.md#your-github-key-next-to-it)
says when that matters and what to put into `~/.ssh/config`.

## 4. The server and the socket by hand: start.sh, stop.sh

Not needed for the rest (gits will call them), only to see what they do. It needs the key loaded (step 3).

```sh
/bin/bash examples/encrypt_os_ssh_agent/start.sh; echo "exit code $?"     # 0: the encryption works
ls examples/encrypt_os_ssh_agent/tmp                   # server.pid ssenc.sock
cat examples/encrypt_os_ssh_agent/server.log           # listening on ..., then the test: one file encrypted, one decrypted
```

`start.sh` does two things and ends only when both worked:

1. `node examples/encrypt_os_ssh_agent/server.js` in the background, listening on `GITS_ENCRYPTION_SOCKET`
   (`encrypt.sh` runs first when `server.js` or the binary is missing, or `server.ts` is newer)
2. `node examples/encrypt_os_ssh_agent/server.js test`: through the socket a file is encrypted, decrypted and
   compared. The server and `ssenc` inherit `SSH_AUTH_SOCK`: this is where a key which is not
   loaded shows up (step 3)

**Talk to the socket yourself.** The server is running now, and what gits does with it is no
more than this: one line of text to the socket, one line back. `nc -U` connects to a unix
socket; a path has to be absolute (a relative one would be read from the directory of the
server) and in quotes:

```sh
# one request: the line goes to the socket, the reply line is printed.
# sleep: nc must not close the connection before the reply came
function ask { (echo "${1}"; sleep 0.3) | nc -U examples/encrypt_os_ssh_agent/tmp/ssenc.sock; }

mkdir -p examples/encrypt_os_ssh_agent/tmp/hand
H="${PWD}/examples/encrypt_os_ssh_agent/tmp/hand"
printf "API_KEY=by-hand\nDB_PASSWORD=secret\n" > "${H}/plain.txt"

ask "encode \"${H}/plain.txt\" \"${H}/encrypted.txt\""       # ok encode ".../hand/encrypted.txt"
cat "${H}/encrypted.txt"                  # #ssenc1 lines ..., #slot ssh ssh-ed25519 SHA256:..., then one line for each line

ask "decode \"${H}/encrypted.txt\" \"${H}/back.txt\""        # ok decode ".../hand/back.txt"
diff "${H}/plain.txt" "${H}/back.txt" && echo identical

# a binary file: the same request, ssenc stores it in its other form
head -c 100 /dev/urandom > "${H}/plain.bin"
ask "encode \"${H}/plain.bin\" \"${H}/encrypted.bin\""
head -1 "${H}/encrypted.bin"              # #ssenc1 blob ...

# errors are replies too: gits shows them and stops
ask "decode \"${H}/plain.txt\" \"${H}/x.txt\""               # error MALFORMED not an ssenc1 file (missing '#ssenc1' header)
ask "hello"                               # error USAGE ... not a request >hello<
ask "rekey \"${H}/encrypted.txt\" \"${H}/rekeyed.txt\""      # error USAGE ... started without GITS_ENCRYPTION_REKEY_SSH_KEY (step 7)

tail -8 examples/encrypt_os_ssh_agent/server.log       # every request above: encrypted / decrypted / error, with the paths
rm -rf examples/encrypt_os_ssh_agent/tmp/hand
```

Now stop it:

```sh
/bin/bash examples/encrypt_os_ssh_agent/stop.sh        # prints nothing
ls examples/encrypt_os_ssh_agent/tmp                   # empty: no socket, no pid file, nothing runs
ssh-add -l                                # your agent is as it was: the keys are still loaded
/bin/bash examples/encrypt_os_ssh_agent/stop.sh        # again: nothing to stop, still exit code 0
```

## 5. gits through the wrapper

From here it is yours to play with. One way through, from state 0 (if you already pushed
something: `/bin/bash examples/encrypt_os_ssh_agent/reset_setup.sh` and the `ssh-add` of step 3 first):

```sh
cd examples/encrypt_os_ssh_agent

/bin/bash gits.sh state                   # both projects: files are not in sync (nothing stored yet)

cd repoa
/bin/bash ../gits.sh push --yes           # '../.env' -> '.../.env' (encrypted)
cd ../repob
/bin/bash ../gits.sh push --yes
cd ..

/bin/bash gits.sh state                   # COUNT_SUCCESS : 2

cat "gits_source/git@github.com:demo__repoa.git/.env"                 # #ssenc1 ...: encrypted
cat "gits_source/git@github.com:demo__repoa.git/config/local.json"    # as it is
cat repoa/.env                            # the local file is as it was

cd repoa
/bin/bash ../gits.sh isinsync; echo "exit code $?"                    # 0
echo "API_KEY=changed" > .env
/bin/bash ../gits.sh diff                 # -API_KEY=repoa-abc123 +API_KEY=changed: compared decrypted
/bin/bash ../gits.sh pull --yes           # storage -> local files: .env is back
cat .env
cd ..
```

Nobody started or stopped anything by hand. After every command nothing is left:

```sh
ls tmp                                    # empty: no socket, no pid file
```

And the log says which file was encrypted and which decrypted, with paths (the first two lines
after every `listening` are the test of `start.sh`, in a temporary directory):

```sh
cat server.log
```

```
2026-11-26T19:21:08.015Z listening on .../examples/encrypt_os_ssh_agent/tmp/ssenc.sock
2026-11-26T19:21:08.276Z encrypted /var/folders/.../gits-demo-PYLxrg/plain -> /var/folders/.../gits-demo-PYLxrg/encrypted
2026-11-26T19:21:08.280Z decrypted /var/folders/.../gits-demo-PYLxrg/encrypted -> /var/folders/.../gits-demo-PYLxrg/back
2026-11-26T19:21:08.377Z encrypted .../repoa/.env -> .../repoa/1571/git@github.com:demo__repoa.git/.env
```

## 6. The whole storage: plain, encrypted, plain again, another key

gits knows nothing about keys. It knows the socket, and it can tell whether a stored file is
an encrypted one (a text file starting with the lines `#ssenc1 ...` + `#slot ...`). From that:

| | stored plain (or not stored yet) | stored encrypted |
|---|---|---|
| **no `GITS_ENCRYPTION_SOCKET`**, or nobody answers on it | `:e:` is ignored: transported as it is | error: the socket is needed |
| **`GITS_ENCRYPTION_SOCKET`** | used as it is; the next push encrypts it | decrypted / encrypted through the socket |

and `gits crypt` changes the form of what is already stored. Start from scratch (the storage
of step 5 is already encrypted, this step begins with an empty one):

```sh
cd examples/encrypt_os_ssh_agent                       # skip when you are already there
/bin/bash reset_setup.sh                  # also: removed from the ssh-agent: gits-os-agent-demo-key, gits-os-agent-demo-key2
ssh-add keys/key keys/key2                # so load them again
```

**No socket: `:e:` is ignored.** `GITS_ENCRYPTION_SOCKET=` in front of the wrapper defines the
variable as an empty text for that one command: gits runs without the socket, and the wrapper
starts neither `start.sh` nor `stop.sh`. `push` and `pull` list the `:e:` files first and wait
for you: Enter goes on without encryption, Esc stops (in a script, without a terminal, there is
only the warning):

```sh
cd repoa
GITS_ENCRYPTION_SOCKET= /bin/bash ../gits.sh push --yes   # WITHOUT ENCRYPTION ... '../.env', press Enter: files are transported as they are
cat "../gits_source/git@github.com:demo__repoa.git/.env"  # plain text
GITS_ENCRYPTION_SOCKET= /bin/bash ../gits.sh diff         # files are in sync
cd ..
```

**The socket appears.** What is stored plain still works, and `gits crypt status` shows the form.

What `/bin/bash ../gits.sh crypt encrypt --yes` does, step by step. It works only on the storage
(`GITS_SOURCE`), never directly in it: on a clone of it, which is pushed back at the end. So it is
the same for a storage which is a directory on this machine (this demo) and one on GitHub.

1. **The wrapper and `start.sh`.** `gits.sh` defines the variables and starts the real binary;
   gits runs `start.sh` (`GITS_START`) first: server, socket, a test with the key of your agent. Not part of
   gits itself: with your own setup the socket just has to be there.
2. **The config of the project.** gits looks for `.git/gits.sh` of the repository you are in
   (`repoa`) and executes it, to get `GITS_LIST`. No config: an error, nothing else happens.
3. **The `:e:` elements.** From the list only the elements `SOURCE:e:TARGET` are taken, and
   of each only the TARGET: the path of the file in the storage
   (`git@github.com:demo__repoa.git/.env`). SOURCE, the local file (`repoa/.env`), is not
   used from here on: it is not read, not compared, not changed. It doesn't even have to exist.
4. **The clone.** gits clones `GITS_SOURCE` (`git clone`, whatever the address is: a directory
   or `git@github.com:...`) to a directory with a random name in the current directory. With
   GitHub this is the moment the files are downloaded. Everything below happens in that clone.
5. **The form of every target.** For each TARGET gits opens the file in the clone and reads its
   beginning: text which starts with `#ssenc1 lines|blob ...` and `#slot ...` lines is
   *encrypted*, any other file is *plain*, no file is *missing* (never pushed). No key and no
   socket is needed for that.
6. **What is to do.** Only the *plain* ones. Encrypted and missing ones are skipped. Nothing
   plain: `nothing to do`, exit code 0, the clone is removed.
7. **Without `--yes` it ends here**: the list of the files is printed, exit code 1, nothing is
   changed.
8. **The socket.** With `--yes`, `GITS_ENCRYPTION_SOCKET` has to be defined and somebody has
   to answer on it, otherwise it is an error (there is no "go on without encryption" here, unlike
   push: encrypting is the only thing this command does).
9. **One request per file.** For each plain file, in the clone: the file is moved aside
   (`.env` -> a temporary name next to it), and gits sends
   `encode "<clone>/.../<temporary name>" "<clone>/.../.env"` through the socket and waits for
   the reply. The server starts `ssenc encrypt`, which reads the first file and writes the
   encrypted one in the place of the original. `ok`: the plain copy is removed. `error`: the
   plain file is moved back, gits stops, the clone is removed, **nothing was pushed**, so the
   storage is as it was (also the files which were already encrypted in the clone).
10. **One commit.** `git add -A` and `git commit -m "gits crypt encrypt (project, 1 files)"`
    in the clone.
11. **One push.** `git push origin HEAD`: to the directory `gits_source` in this demo, to GitHub
    when `GITS_SOURCE` points there. Only now the storage changes.
12. **Cleaning.** The clone is removed, `stop.sh` (`GITS_EXIT`) stops the server.

Compared with `/bin/bash ../gits.sh push --yes`: steps 1, 2, 4, 10, 11 and 12 are the same. The
difference is what gets into the clone between them:

- `push` takes **every** element of the list (`::` and `:e:`), and copies the **local** file
  (SOURCE) over the one in the clone (through `encode` for `:e:`, a plain copy for `::`). So the
  storage ends up with what you have locally.
- `crypt encrypt` takes only the `:e:` elements, and encrypts the file **which is already in the
  clone**. The storage ends up with the same content as before, in the other form. Local changes
  you didn't push stay local.

When the local files are the same as the stored ones, both give the same result.

Encrypting changes only the newest commit of the storage: the plain version of the file is still
in its git history (`git -C gits_source log -p`), on GitHub too.

The commands:

```sh
cd repoa
/bin/bash ../gits.sh diff                 # '...' is marked :e: but it is stored not encrypted ... in sync
/bin/bash ../gits.sh crypt status         # plain      git@github.com:demo__repoa.git/.env
/bin/bash ../gits.sh crypt encrypt        # without --yes: only the list of what would change
/bin/bash ../gits.sh crypt encrypt --yes  # the stored .env is encrypted; the local one is not touched
cd ../repob
/bin/bash ../gits.sh push --yes           # a push with the socket encrypts too
cd ..

/bin/bash gits.sh crypt status all        # encrypted: 4, each with [SHA256:...]: the fingerprint of the key

ssh-keygen -lf keys/key.pub               # the same fingerprint 
    # (It prints the fingerprint of the public key in keys/key.pub. It changes nothing: no key is created or modified.)

head -n 1 "gits_source/git@github.com:demo__repob.git/secrets/token.txt"   # #ssenc1 lines ...  text: line by line
head -n 1 "gits_source/git@github.com:demo__repob.git/secrets/cert.bin"    # #ssenc1 blob ...   binary: as a whole
```

Text or binary is decided by `ssenc` (the server passes `--mode auto`), not by gits and
not by the server.

**No socket any more, but the files are encrypted.** That is an error, nothing is touched:

```sh
cd repoa
GITS_ENCRYPTION_SOCKET= /bin/bash ../gits.sh diff         # ... is stored encrypted but env var GITS_ENCRYPTION_SOCKET is not defined
cd ..
```

**Decrypt the entire storage.** `--storage`: every encrypted file found in it, whatever config
it belongs to:

```sh
/bin/bash gits.sh crypt decrypt --storage         # the list - but that is pretty useless, 
/bin/bash gits.sh crypt decrypt --storage --yes   # clones remote to tempdir, decrypts all :e:, one commit, one push, rm tempdir
# we will never want to decrypt all in GITS_SOURCE
```

The three scopes of `crypt decrypt`. All of them do the same afterwards (one clone of the
storage, decrypting in the clone, one commit, one push), they differ only in which files are
looked at:

- **`crypt decrypt`**: run inside a project. gits reads the `.git/gits.sh` of that project,
  takes only its `:e:` elements, and looks at those files in the storage. The ones stored
  encrypted are decrypted. `::` elements and files of other projects are never looked at.
- **`crypt decrypt all`**: the same, for many projects in one run:
  1. gits looks below the current directory for every project which has a `.git/gits.sh` (the
     search of `gits state`). From `examples/encrypt_os_ssh_agent` it finds `repoa` and `repob`.
  2. Every found config is executed and its `:e:` elements are collected into one list of paths
     in the storage. A config which fails to load: an error which names the project, before
     anything is cloned.
  3. The storage is cloned once, every path of the list is checked, the encrypted ones are
     decrypted.
  4. One commit and one push for all projects together: `gits crypt decrypt (all, N files)`.

  So it depends on where you run it: only the projects below the current directory, only their
  `:e:` files. No project found: `nothing found`, exit code 0.
- **`crypt decrypt --storage`**: no config is read at all. gits goes over every file of the
  clone of `GITS_SOURCE` (without `.git`) and decrypts every one which is encrypted. The widest
  of the three: also files of projects which are not on this machine, and files which are
  encrypted but not marked `:e:` in any config any more.

How a file is recognised as an encrypted one, in all three: gits reads its beginning in the
clone. It has to be text (no NUL byte in the first 8000 bytes: encrypted output is always text,
also of a binary file) and start with the line `#ssenc1 lines ...` or `#ssenc1 blob ...`
followed by at least one `#slot ...` line. No key and no socket is needed for that. Everything
else is left as it is.

```sh
cat "gits_source/git@github.com:demo__repoa.git/.env"                         # plain text again
cmp repob/secrets/cert.bin "gits_source/git@github.com:demo__repob.git/secrets/cert.bin" && echo identical
git -C gits_source log --oneline                  # gits crypt decrypt (storage, 4 files)
(cd repoa && GITS_ENCRYPTION_SOCKET= /bin/bash ../gits.sh diff)    # works without the socket again
```

**Encrypt everything again, with the other key.** `all`: the `:e:` elements of every project
below the current directory (only a config says what should be encrypted, so there is no
`encrypt --storage`):

What the next command does, step by step:

1. **`GITS_ENCRYPTION_SSH_KEY="$(ssh-keygen -lf keys/key2.pub | cut -d " " -f 2)"`**: for this
   one command the key is `key2`, named by its fingerprint (`ssh-keygen -lf` reads it from the
   public key file, `cut` takes the second word: `SHA256:...`). The key is already loaded in
   your agent (step 3). Nothing else knows about keys: not gits, not the storage.
2. **`gits.sh`** defines `GITS_SOURCE`, `GITS_ENCRYPTION_SOCKET`, `GITS_START=start.sh`,
   `GITS_EXIT=stop.sh` and starts the gits binary with `crypt encrypt all --yes`.
3. **gits runs `start.sh`** (`GITS_START`, once, before anything else): `server.js` listening
   on the socket, one file encrypted and decrypted as a test, with `key2` of your agent.
4. **`all`: gits looks for configs.** Every `.git/gits.sh` below the current directory, here
   `repoa` and `repob`. Each one is loaded and its `:e:` elements are collected: one file of
   `repoa`, three of `repob`. A config is the only thing that says "this file should be encrypted".
5. **gits clones the storage once**, into a temporary directory, and looks at how each of those
   four files is stored: plain (after the decrypt above), already encrypted, or not there.
   `encrypt` takes only the plain ones; the other two kinds are skipped.
6. **For each plain file one request goes to the socket**: `encode "<file>" "<file>"`, both
   paths inside the clone. gits waits for the reply before it sends the next one.
7. **`server.js` starts the binary** for that request: `ssenc encrypt --mode auto --ssh-key
   SHA256:... -i <file> -o <file>`. `ssenc` decides text or binary by itself, asks your agent
   for a signature made with `key2`, writes the encrypted file. The server replies `ok encode ...`
   (or `error ...`: then gits stops and nothing is changed in the storage).
8. **One commit, one push**: `gits crypt encrypt (all, 4 files)`. The storage now has the four
   files encrypted with `key2`.
9. **gits removes the clone and runs `stop.sh`** (`GITS_EXIT`): the server is stopped.

What is encrypted is what was **stored** (the plain files in the storage). The local files in
`repoa/` and `repob/` are not read and not changed. Without `--yes` steps 6 to 8 don't happen:
gits only lists the files it would encrypt.

```sh
GITS_ENCRYPTION_SSH_KEY="$(ssh-keygen -lf keys/key2.pub | cut -d " " -f 2)" /bin/bash gits.sh crypt encrypt all --yes
# we will never want to decrypt all in GITS_SOURCE
# WARNING: ACTUALLY NO, THIS IS USEFUL, YOU CAN DECODE THEN ENCODE AND RESET HARD 2 COMMITS COMMIT ALL AND ONLY THEN PUSH
# WARNING: ACTUALLY NO, THIS IS USEFUL, YOU CAN DECODE THEN ENCODE AND RESET HARD 2 COMMITS COMMIT ALL AND ONLY THEN PUSH
# WARNING: ACTUALLY NO, THIS IS USEFUL, YOU CAN DECODE THEN ENCODE AND RESET HARD 2 COMMITS COMMIT ALL AND ONLY THEN PUSH
# WARNING: ACTUALLY NO, THIS IS USEFUL, YOU CAN DECODE THEN ENCODE AND RESET HARD 2 COMMITS COMMIT ALL AND ONLY THEN PUSH
# WARNING: ACTUALLY NO, THIS IS USEFUL, YOU CAN DECODE THEN ENCODE AND RESET HARD 2 COMMITS COMMIT ALL AND ONLY THEN PUSH
# WARNING: ACTUALLY NO, THIS IS USEFUL, YOU CAN DECODE THEN ENCODE AND RESET HARD 2 COMMITS COMMIT ALL AND ONLY THEN PUSH
# WARNING: ACTUALLY NO, THIS IS USEFUL, YOU CAN DECODE THEN ENCODE AND RESET HARD 2 COMMITS COMMIT ALL AND ONLY THEN PUSH
# WARNING: ACTUALLY NO, THIS IS USEFUL, YOU CAN DECODE THEN ENCODE AND RESET HARD 2 COMMITS COMMIT ALL AND ONLY THEN PUSH

/bin/bash gits.sh crypt status --storage          # encrypted: 4, the fingerprint of key2
ssh-keygen -lf keys/key2.pub

(cd repoa && /bin/bash ../gits.sh diff)                          # AUTH: the first key doesn't open it
(cd repoa && GITS_ENCRYPTION_SSH_KEY="$(ssh-keygen -lf ../keys/key2.pub | cut -d " " -f 2)" /bin/bash ../gits.sh diff)   # files are in sync
```

From now on the key of this storage is `key2`: either change the default of
`GITS_ENCRYPTION_SSH_KEY` in `env.sh` (`keys/key.pub` -> `keys/key2.pub`), or keep giving it.
To not repeat the long form, keep the fingerprint in a variable of the terminal; it is the same
text from every directory:

```sh
KEY2="$(ssh-keygen -lf keys/key2.pub | cut -d " " -f 2)"      # SHA256:..., also shown by: ssh-add -l
echo "${KEY2}"
(cd repoa && GITS_ENCRYPTION_SSH_KEY="${KEY2}" /bin/bash ../gits.sh diff)     # files are in sync
```

## 7. Rekey: another key without decrypting to the storage

In step 6 the storage was plain for a moment (one commit with every secret readable).
`gits crypt rekey` goes from one key to another directly. From scratch again:

```sh
/bin/bash reset_setup.sh                  # still in examples/encrypt_os_ssh_agent: empty storage, the same key files, not loaded
ssh-add keys/key keys/key2
(cd repoa && /bin/bash ../gits.sh push --yes)
(cd repob && /bin/bash ../gits.sh push --yes)
/bin/bash gits.sh crypt status all        # encrypted: 4, the fingerprint of key
```

The server has to know both keys: `GITS_ENCRYPTION_SSH_KEY` opens what is stored (`key`),
`GITS_ENCRYPTION_REKEY_SSH_KEY` is what the files get. Both are in your agent (the `ssh-add`
above), and the server answers the requests `rekey` / `rewrap` only when the
second variable is given:

```sh
/bin/bash gits.sh crypt rekey --storage --yes                              # USAGE: the server was started without GITS_ENCRYPTION_REKEY_SSH_KEY
GITS_ENCRYPTION_REKEY_SSH_KEY="$(ssh-keygen -lf keys/key2.pub | cut -d " " -f 2)" /bin/bash gits.sh crypt rekey --storage         # the list
GITS_ENCRYPTION_REKEY_SSH_KEY="$(ssh-keygen -lf keys/key2.pub | cut -d " " -f 2)" /bin/bash gits.sh crypt rekey --storage --yes   # one commit, one push
  # this one is decoding and encoding in one go - produces just one commit - much safer if we don't want to even for the moment decode in the remote
  # this one is decoding and encoding in one go - produces just one commit - much safer if we don't want to even for the moment decode in the remote
  # this one is decoding and encoding in one go - produces just one commit - much safer if we don't want to even for the moment decode in the remote
  # this one is decoding and encoding in one go - produces just one commit - much safer if we don't want to even for the moment decode in the remote
  # this one is decoding and encoding in one go - produces just one commit - much safer if we don't want to even for the moment decode in the remote

/bin/bash gits.sh crypt status --storage                                   # the fingerprint of key2 everywhere

(cd repoa && /bin/bash ../gits.sh diff)                          # AUTH: key is out
  # default key is no longer good because we have rekeyed all files in the repo
  # default key is no longer good because we have rekeyed all files in the repo
  # default key is no longer good because we have rekeyed all files in the repo
  # default key is no longer good because we have rekeyed all files in the repo
  # default key is no longer good because we have rekeyed all files in the repo

(cd repoa && GITS_ENCRYPTION_SSH_KEY="$(ssh-keygen -lf ../keys/key2.pub | cut -d " " -f 2)" /bin/bash ../gits.sh diff)   # files are in sync
```

`--rewrap-only` replaces only the key line at the top of each file, the content stays byte for
byte (a small diff; but someone with the old key and an old copy can still read later versions).
Here back to `key`, only for `repoa`:

```sh
cd repoa
git -C ../gits_source log --oneline | head -n 1
GITS_ENCRYPTION_SSH_KEY="$(ssh-keygen -lf ../keys/key2.pub | cut -d " " -f 2)" GITS_ENCRYPTION_REKEY_SSH_KEY="$(ssh-keygen -lf ../keys/key.pub | cut -d " " -f 2)" /bin/bash ../gits.sh crypt rekey --rewrap-only --yes
git -C ../gits_source show --stat HEAD            # one file, one line changed
/bin/bash ../gits.sh diff                         # key opens repoa again
cd ..
/bin/bash gits.sh crypt status --storage          # repoa: key, repob: key2
```

Keep in mind: a rekey doesn't clean the history of the storage. Old commits stay readable with
the old key; when a key leaked, the secrets themselves have to be changed.

## 8. How it is wired

The substance of the wrapper, [gits.sh](gits.sh):

```sh
source "${_DIR}/env.sh"                    # GITS_SOURCE, GITS_ENCRYPTION_SOCKET and the rest
export GITS_START="${_DIR}/start.sh"
export GITS_EXIT="${_DIR}/stop.sh"
"${GITS_DEMO_BIN}" "${@}"
```

- **`GITS_SOURCE`**: the storage, here `gits_source/`.
- **`GITS_ENCRYPTION_SOCKET`**: where gits sends `encode "<file>" "<file>"` / `decode ...`.
- **`GITS_START`**: its script runs once, as the first thing of a command, before any of its
  [lifecycle events](../../LIFECYCLE.md). gits waits for it, and a script which fails stops the
  command: gits goes on only when the test of the encryption passed.
- **`GITS_EXIT`**: its script runs once, as the last thing of every
  start of gits, like `trap ... EXIT` in a shell. After a command which worked or failed, after
  Ctrl+C, `kill` (SIGTERM), a closed terminal (SIGHUP). Only `kill -9` can't be caught by anything.

Try the ways out:

```sh
cd repoa                          # from examples/encrypt_os_ssh_agent

# a start which fails (a fingerprint of no key): gits stops before doing anything, and stop.sh still ran
GITS_ENCRYPTION_SSH_KEY="SHA256:nosuchkey" /bin/bash ../gits.sh diff; echo "exit code $?"
ls ../tmp                         # empty

# a key which is not in the agent (like in step 3): the same
ssh-add -d ../keys/key.pub        # out of your agent (-d takes the public key file)
/bin/bash ../gits.sh diff         # ... error ENV key SHA256:... is not loaded in ssh-agent (check: ssh-add -l)
ssh-add ../keys/key               # back in
/bin/bash ../gits.sh diff         # files are in sync

# Ctrl+C in the middle: make the config slow, start, press Ctrl+C while it sleeps
echo 'sleep 10' >> .git/gits.sh
/bin/bash ../gits.sh diff         # ... press Ctrl+C
ls ../tmp                         # empty: stopped anyway
sed -i.bak '/^sleep 10$/d' .git/gits.sh && rm .git/gits.sh.bak
cd ..
```

For what has no lifecycle events (`--help`, `--version`, `events`, `list`) `GITS_START` is not run:
nothing is started for them, and `stop.sh` finds nothing to stop.

## 9. For real

- your own key in place of the two of the demo, with a passphrase. It is asked once, by
  `ssh-add`, not by gits:

  ```sh
  ssh-keygen -t ed25519 -C "gits-encryption" -f ~/.ssh/gits_encryption
  ssh-add ~/.ssh/gits_encryption                       # macOS, passphrase kept in the keychain: ssh-add --apple-use-keychain ...
  ssh-keygen -lf ~/.ssh/gits_encryption.pub            # SHA256:...
  ```

  and in `env.sh` the default of `GITS_ENCRYPTION_SSH_KEY`: that fingerprint, written as it is
  (`"${GITS_ENCRYPTION_SSH_KEY:-SHA256:...}"`), no `ssh-keygen` there any more. Only `ssh-ed25519` and `ssh-rsa` keys work. Keep a copy of the
  private key file: the agent is only memory.
  More: [USE_OS_SSH_WITH_SEPARATE_SSH_KEY.md](USE_OS_SSH_WITH_SEPARATE_SSH_KEY.md)
- the key is not loaded (a new session, a restart): gits doesn't hang and doesn't push anything
  plain, the test of `start.sh` fails and gits stops (step 3)
- a storage on GitHub works as it is: gits clones and pushes with the keys of the same agent
- the binary: install `rust/target/release/ssenc` of the encrypt repository where you keep your
  programs and point `GITS_DEMO_SSENC` in `env.sh` to it (a path, or `ssenc` when it is in `PATH`).
  `encrypt.sh` copies nothing then, and `bin/` is not needed
- `alias gits='/bin/bash /path/to/examples/encrypt_os_ssh_agent/gits.sh'`
- one gits at a time: two commands running together share the socket, and the one which ends
  first stops the server of the other
- every command pays for the start (about half a second). A server which stays running:
  `tests/encoder/encoder-start.sh`, [examples/SUMMARY.md, case 007](../SUMMARY.md#case-007-encrypted_files)

## 10. Clean up

Back to state 0: `/bin/bash examples/encrypt_os_ssh_agent/reset_setup.sh` (the key files stay, the
keys are taken out of your agent). To
remove everything, from the root of this repository. **First the keys out of your agent**, while
their `.pub` files are still there:

```sh
ssh-add -d examples/encrypt_os_ssh_agent/keys/key.pub examples/encrypt_os_ssh_agent/keys/key2.pub     # or: /bin/bash examples/encrypt_os_ssh_agent/reset_setup.sh
ssh-add -l                                # only your own keys

/bin/bash examples/encrypt_os_ssh_agent/stop.sh
rm -rf examples/encrypt_os_ssh_agent/tmp examples/encrypt_os_ssh_agent/keys examples/encrypt_os_ssh_agent/gits_source examples/encrypt_os_ssh_agent/repoa examples/encrypt_os_ssh_agent/repob examples/encrypt_os_ssh_agent/server.log examples/encrypt_os_ssh_agent/server.js examples/encrypt_os_ssh_agent/bin
```

The files are already removed and the keys are still in the agent: `ssh-add -l` shows them
(`gits-os-agent-demo-key`, `gits-os-agent-demo-key2`), `ssh-add -L > all.pub` writes the public
keys of everything loaded, one per line; keep only the line to remove in a file and give it to
`ssh-add -d`.
