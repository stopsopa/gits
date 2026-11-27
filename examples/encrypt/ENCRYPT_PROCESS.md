# Encryption which starts and stops with gits

A self-contained demo. `gits` stores some files encrypted (elements `SOURCE:e:TARGET` of the
config), but it never encrypts by itself: it sends requests to a process listening on a unix
socket. Here that process lives only as long as one `gits` command:

```
/bin/bash examples/encrypt/gits.sh diff
        |
        |  defines the env vars (env.sh), GITS_START=start.sh, GITS_EXIT=stop.sh, starts the gits binary
        v
      gits ---- GITS_START -----> start.sh   once, before anything else:
        |                                    ssh-agent with the key + server.ts on the socket
        |                                    + a test: a file encrypted, decrypted, compared.
        |                                    gits waits. A failure stops gits.
        |
        |  ... the command itself: encode / decode requests to the socket ...
        |
        +------ GITS_EXIT ------> stop.sh    once, the last thing:
                                             server and agent stopped, sockets removed.
                                             Always: also after an error, Ctrl+C, kill.
```

`GITS_START` and `GITS_EXIT` are not lifecycle events of a command (those are
`GITS_DIFF_START`, `GITS_PUSH_BEFORE_COPY`, ... see `gits --help`): each is one variable for
every command, and its script runs exactly once in one start of gits.

Everything is in `examples/encrypt/`:

| File | |
|---|---|
| [env.sh](env.sh) | every env var of the demo, in one place. The other scripts source it |
| [keys.sh](keys.sh) | creates two ssh keys: `key` (in use) and `key2` (to change to) |
| [start.sh](start.sh) | starts the agent and the server, tests the encryption |
| [stop.sh](stop.sh) | stops them |
| [server.ts](server.ts) | the server behind the socket: request, work, reply, socket, test, in that order |
| [ENCRYPT_IN_GITS_PLAN.md](ENCRYPT_IN_GITS_PLAN.md) | the design of what steps 6 and 7 show: gits without the socket, `gits crypt` |
| [gits.sh](gits.sh) | the wrapper you call in place of `gits` |
| [reset_setup.sh](reset_setup.sh) | brings the demo to its state 0: removes and creates again everything below |
| `gits_source/` | generated: the storage, a local git repository (`GITS_SOURCE` of the demo) |
| `repoa/`, `repob/` | generated: two projects to play with |
| `tmp/` | generated: key, sockets, pid files |
| `server.log` | generated: log of the server |

Everything generated is ignored by git.

Needs: Node.js >= 22.18, `ssh-keygen` / `ssh-agent` / `ssh-add`, the compiled gits
(`/bin/bash compile.sh`) and a checkout of [encrypt](https://github.com/stopsopa/encrypt) in
`__linked/STOPSOPA__encrypt/STOPSOPA__encrypt` (somewhere else: `GITS_DEMO_ENCRYPT` in `env.sh`,
e.g. `submodules/encrypt`).

Your own ssh-agent and your own keys are not touched: the demo has an agent of its own.

All commands below are run from the root of this repository.

## The order

`reset_setup.sh` is the preparation of everything, and the way back to the beginning. Nothing
else has to be prepared by hand:

| Step | | Before it |
|---|---|---|
| 1 | `reset_setup.sh`: state 0 | nothing. **Always the first command** |
| 2, 3 | the variables and the keys | only reading |
| 4 | the server by hand | step 1 once (it needs the keys) |
| 5 | gits through the wrapper | step 1. Played before? run `reset_setup.sh` again: the step expects an empty storage |
| 6 | the whole storage plain / encrypted / another key | `reset_setup.sh` again (the first command of the step) |
| 7 | rekey | `reset_setup.sh` again (the first command of the step) |

Steps 5, 6 and 7 are three independent ways through, each one starts from state 0. Whenever
something doesn't look like the guide says (a file not in sync, an `AUTH` error because the
storage is stored with `key2` from an earlier step): `/bin/bash examples/encrypt/reset_setup.sh`
and start the step again. It can be run at any moment and as many times as you want; it removes
only what it generated itself.

## 1. State 0: reset_setup.sh

```sh
/bin/bash examples/encrypt/reset_setup.sh
```

The first command of the demo, and again whenever you want to start from scratch (see
[the order](#the-order)). It stops what runs, removes everything generated and creates it again:

| | |
|---|---|
| `gits_source/` | the storage: an empty git repository. Not bare, so after a push its files can be looked at |
| `repoa/` | a project. In git: `README.md`, `src/app.js`, `config/default.json`. Ignored by git: `.env`, `config/local.json` |
| `repob/` | a project. In git: `README.md`, `main.sh`. Ignored by git: `.env.local`, `secrets/token.txt`, `secrets/cert.bin` (binary), `notes.txt` |
| `tmp/key`, `tmp/key2` | two new keys (and their `.pub`) |

In both projects it already ran, through the wrapper, `gits init` (creates `.git/gits.sh`)
and `gits add` for the ignored files (`gits add -e` for the secret ones):

```sh
cat examples/encrypt/repoa/.git/gits.sh
```

```sh
GITS_TARGETDIR="git@github.com:demo__repoa.git"
GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
    "../.env:e:$GITS_TARGETDIR/.env"                               # :e: stored encrypted
    "../config/local.json::$GITS_TARGETDIR/config/local.json"      # ::  stored as it is
)
```

It ends with `state 0 is ready`. Nothing is pushed yet. The remote `origin` of the projects (`git@github.com:demo/repoa.git`)
is never contacted: gits only takes the name of the directory in the storage from it.

## 2. The variables: env.sh

| Variable | Default | |
|---|---|---|
| `GITS_SOURCE` | `examples/encrypt/gits_source` | **the storage.** gits reads it. Always the one of the demo: `GITS_SOURCE` of your terminal (your real storage) is ignored, the demo can't push there. Another one: `GITS_DEMO_SOURCE` |
| `GITS_ENCRYPTION_SOCKET` | `examples/encrypt/tmp/ssenc.sock` | **the socket.** gits reads it: where it sends its requests. At most about 100 characters |
| `GITS_DEMO_SSH_KEY` | `key` = `examples/encrypt/tmp/key` | the ssh key which encrypts and which opens what is stored (private key file, the public one is `<file>.pub`). Only `start.sh` and `server.ts` use it. A name without a directory is a file in `tmp/`: `GITS_DEMO_SSH_KEY=key2` |
| `GITS_DEMO_NEW_SSH_KEY` | not defined | only for `gits crypt rekey`: the key the stored files get in place of `GITS_DEMO_SSH_KEY` |
| `GITS_DEMO_NO_SOCKET` | not defined | `1`: the wrapper starts gits without `GITS_ENCRYPTION_SOCKET` and without `start.sh` / `stop.sh` |
| `GITS_DEMO_LOG` | `examples/encrypt/server.log` | log of the server. Empty (`GITS_DEMO_LOG=""`): no log |
| `GITS_DEMO_AGENT` | `examples/encrypt/tmp/agent.sock` | socket of the ssh-agent of the demo |
| `GITS_DEMO_ENCRYPT` | `__linked/STOPSOPA__encrypt/STOPSOPA__encrypt` | checkout of the encrypt repository |
| `GITS_DEMO_BIN` | `bin/<arch>/gits` | the gits binary `gits.sh` starts |
| `GITS_DEMO_WORK` | `examples/encrypt` | where everything generated goes: `gits_source/`, `repoa/`, `repob/`, `tmp/`, `server.log` |
| `GITS_DEMO_TMP` | `examples/encrypt/tmp` | keys, sockets, pid files |

A variable defined in the terminal wins over the default (besides `GITS_SOURCE`): `GITS_DEMO_LOG="" /bin/bash examples/encrypt/gits.sh diff`.

## 3. The keys: keys.sh

Step 1 created them, there is nothing to run here:

```sh
ls examples/encrypt/tmp                   # key key.pub key2 key2.pub
```

`key` is the one in use, `key2` is there to change to (steps 6 and 7). Both without a passphrase.

`reset_setup.sh` removes them and calls `keys.sh` for new ones, so after every reset the keys are
different: what an older storage was encrypted with is gone together with that storage.
`keys.sh` by itself only creates a key which is missing and never replaces one:

```sh
/bin/bash examples/encrypt/keys.sh        # both are there: nothing is changed
```

## 4. The server and the socket by hand: start.sh, stop.sh

Not needed for the rest (gits will call them), only to see what they do. It needs the keys of step 1.

```sh
/bin/bash examples/encrypt/start.sh; echo "exit code $?"     # 0: the encryption works
ls examples/encrypt/tmp                   # agent.pid agent.sock key key.pub key2 key2.pub server.pid ssenc.sock
cat examples/encrypt/server.log           # listening on ..., then the test: one file encrypted, one decrypted
```

`start.sh` does three things and ends only when all of them worked:

1. an ssh-agent listening on `examples/encrypt/tmp/agent.sock`, with the key loaded
2. `node examples/encrypt/server.ts` in the background, listening on `GITS_ENCRYPTION_SOCKET`
3. `node examples/encrypt/server.ts test`: through the socket a file is encrypted, decrypted and compared

```sh
/bin/bash examples/encrypt/stop.sh        # prints nothing
ls examples/encrypt/tmp                   # key key.pub key2 key2.pub: no sockets, no pid files, nothing runs
/bin/bash examples/encrypt/stop.sh        # again: nothing to stop, still exit code 0
```

## 5. gits through the wrapper

From here it is yours to play with. One way through, from state 0 (if you already pushed
something: `/bin/bash examples/encrypt/reset_setup.sh` first):

```sh
cd examples/encrypt

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
ls tmp                                    # key key.pub key2 key2.pub: no socket, no pid file
```

And the log says which file was encrypted and which decrypted, with paths (the first two lines
after every `listening` are the test of `start.sh`, in a temporary directory):

```sh
cat server.log
```

```
2026-11-26T19:21:08.015Z listening on .../examples/encrypt/tmp/ssenc.sock
2026-11-26T19:21:08.276Z encrypted /var/folders/.../gits-demo-PYLxrg/plain -> /var/folders/.../gits-demo-PYLxrg/encrypted
2026-11-26T19:21:08.280Z decrypted /var/folders/.../gits-demo-PYLxrg/encrypted -> /var/folders/.../gits-demo-PYLxrg/back
2026-11-26T19:21:08.377Z encrypted .../repoa/.env -> .../repoa/1571/git@github.com:demo__repoa.git/.env
```

## 6. The whole storage: plain, encrypted, plain again, another key

gits knows nothing about keys. It knows the socket, and it can tell whether a stored file is
an encrypted one (a text file starting with the lines `#ssenc1 ...` + `#slot ...`). From that:

| | stored plain (or not stored yet) | stored encrypted |
|---|---|---|
| **no `GITS_ENCRYPTION_SOCKET`** | `:e:` is ignored: transported as it is | error: the socket is needed |
| **`GITS_ENCRYPTION_SOCKET`** | used as it is; the next push encrypts it | decrypted / encrypted through the socket |

and `gits crypt` changes the form of what is already stored. Start from scratch (the storage
of step 5 is already encrypted, this step begins with an empty one):

```sh
cd examples/encrypt                       # skip when you are already there
/bin/bash reset_setup.sh
```

**No socket: `:e:` is ignored.** `GITS_DEMO_NO_SOCKET=1` makes the wrapper start gits without
`GITS_ENCRYPTION_SOCKET` (and without `start.sh` / `stop.sh`):

```sh
cd repoa
GITS_DEMO_NO_SOCKET=1 /bin/bash ../gits.sh push --yes     # ':e:' is ignored, files are transported as they are
cat "../gits_source/git@github.com:demo__repoa.git/.env"  # plain text
GITS_DEMO_NO_SOCKET=1 /bin/bash ../gits.sh diff           # files are in sync
cd ..
```

**The socket appears.** What is stored plain still works, and `gits crypt status` shows the form:

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
ssh-keygen -lf tmp/key.pub                # the same fingerprint
head -n 1 "gits_source/git@github.com:demo__repob.git/secrets/token.txt"   # #ssenc1 lines ...  text: line by line
head -n 1 "gits_source/git@github.com:demo__repob.git/secrets/cert.bin"    # #ssenc1 blob ...   binary: as a whole
```

Text or binary is decided by the library (the server passes `mode: "auto"`), not by gits and
not by the server.

**No socket any more, but the files are encrypted.** That is an error, nothing is touched:

```sh
cd repoa
GITS_DEMO_NO_SOCKET=1 /bin/bash ../gits.sh diff           # ... is stored encrypted but env var GITS_ENCRYPTION_SOCKET is not defined
cd ..
```

**Decrypt the entire storage.** `--storage`: every encrypted file found in it, whatever config
it belongs to:

```sh
/bin/bash gits.sh crypt decrypt --storage         # the list
/bin/bash gits.sh crypt decrypt --storage --yes   # one commit, one push
cat "gits_source/git@github.com:demo__repoa.git/.env"                         # plain text again
cmp repob/secrets/cert.bin "gits_source/git@github.com:demo__repob.git/secrets/cert.bin" && echo identical
git -C gits_source log --oneline                  # gits crypt decrypt (storage, 4 files)
(cd repoa && GITS_DEMO_NO_SOCKET=1 /bin/bash ../gits.sh diff)    # works without the socket again
```

**Encrypt everything again, with the other key.** `all`: the `:e:` elements of every project
below the current directory (only a config says what should be encrypted, so there is no
`encrypt --storage`):

```sh
GITS_DEMO_SSH_KEY=key2 /bin/bash gits.sh crypt encrypt all --yes
/bin/bash gits.sh crypt status --storage          # encrypted: 4, the fingerprint of key2
ssh-keygen -lf tmp/key2.pub

(cd repoa && /bin/bash ../gits.sh diff)                          # AUTH: the first key doesn't open it
(cd repoa && GITS_DEMO_SSH_KEY=key2 /bin/bash ../gits.sh diff)   # files are in sync
```

From now on the key of this storage is `key2`: either write it into `env.sh`
(`GITS_DEMO_SSH_KEY` default) or keep giving `GITS_DEMO_SSH_KEY=key2`.

## 7. Rekey: another key without decrypting to the storage

In step 6 the storage was plain for a moment (one commit with every secret readable).
`gits crypt rekey` goes from one key to another directly. From scratch again:

```sh
/bin/bash reset_setup.sh                  # still in examples/encrypt: new keys, empty storage
(cd repoa && /bin/bash ../gits.sh push --yes)
(cd repob && /bin/bash ../gits.sh push --yes)
/bin/bash gits.sh crypt status all        # encrypted: 4, the fingerprint of key
```

The server has to know both keys: `GITS_DEMO_SSH_KEY` opens what is stored (`key`),
`GITS_DEMO_NEW_SSH_KEY` is what the files get. `start.sh` loads both into the agent and the
server answers the requests `rekey` / `rewrap` only then:

```sh
/bin/bash gits.sh crypt rekey --storage --yes                              # USAGE: the server was started without GITS_DEMO_NEW_SSH_KEY
GITS_DEMO_NEW_SSH_KEY=key2 /bin/bash gits.sh crypt rekey --storage         # the list
GITS_DEMO_NEW_SSH_KEY=key2 /bin/bash gits.sh crypt rekey --storage --yes   # one commit, one push
/bin/bash gits.sh crypt status --storage                                   # the fingerprint of key2 everywhere

(cd repoa && /bin/bash ../gits.sh diff)                          # AUTH: key is out
(cd repoa && GITS_DEMO_SSH_KEY=key2 /bin/bash ../gits.sh diff)   # files are in sync
```

`--rewrap-only` replaces only the key line at the top of each file, the content stays byte for
byte (a small diff; but someone with the old key and an old copy can still read later versions).
Here back to `key`, only for `repoa`:

```sh
cd repoa
git -C ../gits_source log --oneline | head -n 1
GITS_DEMO_SSH_KEY=key2 GITS_DEMO_NEW_SSH_KEY=key /bin/bash ../gits.sh crypt rekey --rewrap-only --yes
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
cd repoa                          # from examples/encrypt

# a start which fails (no such key): gits stops before doing anything, and stop.sh still ran
GITS_DEMO_SSH_KEY=/no/such/key /bin/bash ../gits.sh diff; echo "exit code $?"
ls ../tmp                         # key key.pub key2 key2.pub

# Ctrl+C in the middle: make the config slow, start, press Ctrl+C while it sleeps
echo 'sleep 10' >> .git/gits.sh
/bin/bash ../gits.sh diff         # ... press Ctrl+C
ls ../tmp                         # key key.pub key2 key2.pub: stopped anyway
sed -i.bak '/^sleep 10$/d' .git/gits.sh && rm .git/gits.sh.bak
cd ..
```

For what has no lifecycle events (`--help`, `--version`, `events`, `list`) `GITS_START` is not run:
nothing is started for them, and `stop.sh` finds nothing to stop.

## 9. For real

- your key is already in your own agent: in `start.sh` drop the two commands of its part 1
  (`ssh-agent`, `ssh-add`), in `stop.sh` the line of the agent, and point `GITS_DEMO_SSH_KEY`
  to your key (`~/.ssh/id_ed25519`); the server then asks the agent of `SSH_AUTH_SOCK`
- `alias gits='/bin/bash /path/to/examples/encrypt/gits.sh'`
- one gits at a time: two commands running together share the socket, and the one which ends
  first stops the server of the other
- every command pays for the start (about half a second). A server which stays running:
  `tests/encoder/encoder-start.sh`, [examples/SUMMARY.md, case 007](../SUMMARY.md#case-007-encrypted_files)

## 10. Clean up

Back to state 0: `/bin/bash examples/encrypt/reset_setup.sh`. To remove everything generated,
from the root of this repository:

```sh
/bin/bash examples/encrypt/stop.sh
rm -rf examples/encrypt/tmp examples/encrypt/gits_source examples/encrypt/repoa examples/encrypt/repob examples/encrypt/server.log
```
