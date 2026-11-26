# Encryption which starts and stops with gits

A self-contained demo. `gits` stores some files encrypted (elements `SOURCE:e:TARGET` of the
config), but it never encrypts by itself: it sends requests to a process listening on a unix
socket. Here that process lives only as long as one `gits` command:

```
/bin/bash examples/gits.sh diff
        |
        |  defines the env vars (env.sh), starts the gits binary
        v
      gits ---- event START ----> start.sh   ssh-agent with the key + server.ts on the socket
        |                                    + a test: a file encrypted, decrypted, compared.
        |                                    gits waits. A failure stops gits.
        |
        |  ... the command itself: encode / decode requests to the socket ...
        |
        +------ GITS_EXIT ------> stop.sh    server and agent stopped, sockets removed.
                                             Always: also after an error, Ctrl+C, kill.
```

Everything is in `examples/`:

| File | |
|---|---|
| [env.sh](env.sh) | every env var of the demo, in one place. The other scripts source it |
| [keys.sh](keys.sh) | creates the ssh key |
| [start.sh](start.sh) | starts the agent and the server, tests the encryption |
| [stop.sh](stop.sh) | stops them |
| [server.ts](server.ts) | the server behind the socket, about 100 lines |
| [gits.sh](gits.sh) | the wrapper you call in place of `gits` |
| `server.log` | log of the server (ignored by git) |
| `tmp/` | everything generated: key, sockets, pid files (ignored by git) |

Needs: Node.js >= 22.18, `ssh-keygen` / `ssh-agent` / `ssh-add`, the compiled gits
(`/bin/bash compile.sh`) and a checkout of [encrypt](https://github.com/stopsopa/encrypt) in
`__linked/STOPSOPA__encrypt/STOPSOPA__encrypt` (somewhere else: `GITS_DEMO_ENCRYPT` in `env.sh`,
e.g. `submodules/encrypt`).

Your own ssh-agent and your own keys are not touched: the demo has an agent of its own.

All commands below are run from the root of this repository.

## 1. The variables: env.sh

| Variable | Default | |
|---|---|---|
| `GITS_ENCRYPTION_SOCKET` | `examples/tmp/ssenc.sock` | **the socket.** The only one gits itself reads: where it sends its requests. At most about 100 characters |
| `GITS_DEMO_SSH_KEY` | `examples/tmp/key` | the ssh key (private key file, the public one is `<file>.pub`). Only `keys.sh`, `start.sh` and `server.ts` use it |
| `GITS_DEMO_LOG` | `examples/server.log` | log of the server. Empty (`GITS_DEMO_LOG=""`): no log |
| `GITS_DEMO_AGENT` | `examples/tmp/agent.sock` | socket of the ssh-agent of the demo |
| `GITS_DEMO_ENCRYPT` | `__linked/STOPSOPA__encrypt/STOPSOPA__encrypt` | checkout of the encrypt repository |
| `GITS_DEMO_BIN` | `bin/<arch>/gits` | the gits binary `gits.sh` starts |
| `GITS_DEMO_TMP` | `examples/tmp` | where everything generated goes |

A variable defined in the terminal wins over the default: `GITS_DEMO_LOG="" /bin/bash examples/gits.sh diff`.

## 2. The key: keys.sh

```sh
/bin/bash examples/keys.sh        # examples/tmp/key and examples/tmp/key.pub, no passphrase
/bin/bash examples/keys.sh        # already there: nothing is changed
```

## 3. The server and the socket by hand: start.sh, stop.sh

Not needed for the rest (gits will call them), only to see what they do.

```sh
/bin/bash examples/start.sh; echo "exit code $?"     # 0: the encryption works
ls examples/tmp                   # agent.pid agent.sock key key.pub server.pid ssenc.sock
cat examples/server.log           # listening on ..., then the test: one file encrypted, one decrypted
```

`start.sh` does three things and ends only when all of them worked:

1. an ssh-agent listening on `examples/tmp/agent.sock`, with the key loaded
2. `node examples/server.ts` in the background, listening on `GITS_ENCRYPTION_SOCKET`
3. `node examples/server.ts test`: through the socket a file is encrypted, decrypted and compared

```sh
/bin/bash examples/stop.sh        # prints nothing
ls examples/tmp                   # key key.pub: no sockets, no pid files, nothing runs
/bin/bash examples/stop.sh        # again: nothing to stop, still exit code 0
```

## 4. Something to work with

A storage and a project with one secret file, both in `examples/tmp/play`. In real life the
storage is your private repository and `GITS_SOURCE` is already defined: then skip this step.

```sh
P="$PWD/examples/tmp/play"
rm -rf "$P" && mkdir -p "$P"

git init -q "$P/storage"
git -C "$P/storage" config receive.denyCurrentBranch updateInstead
export GITS_SOURCE="$P/storage"           # only in this terminal

git init -q "$P/project"
git -C "$P/project" remote add origin git@github.com:demo/secret.git
echo "API_KEY=abc123" > "$P/project/.env"

cat <<'EEE' > "$P/project/.git/gits.sh"
GITS_TARGETDIR="git@github.com:demo__secret.git"
GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
    "../.env:e:$GITS_TARGETDIR/.env"
)
EEE
```

`:e:` in the second element: `.env` is stored encrypted.

## 5. gits through the wrapper

`W` is the wrapper with an absolute path, because the commands `cd` around:

```sh
W="$PWD/examples/gits.sh"

cd "$P/project"
/bin/bash $W push --yes           # '../.env' -> '.../.env' (encrypted)

cat "$P/storage/git@github.com:demo__secret.git/.env"      # #ssenc1 ...: encrypted
cat .env                                                   # API_KEY=abc123: the local file is as it was

/bin/bash $W isinsync; echo "exit code $?"                 # 0
echo "API_KEY=changed" > .env
/bin/bash $W diff                 # -API_KEY=abc123 +API_KEY=changed: compared decrypted

cd "$P"
/bin/bash $W state                # every project below: here one, not in sync
```

Nobody started or stopped anything by hand. After every command nothing is left:

```sh
ls "$P/../"                       # key key.pub play: no socket, no pid file
```

And the log says which file was encrypted and which decrypted, with paths (the first two lines
after every `listening` are the test of `start.sh`, in a temporary directory):

```sh
cat "$P/../../server.log"
```

```
2026-11-26T19:21:08.015Z listening on .../examples/tmp/ssenc.sock
2026-11-26T19:21:08.276Z encrypted /var/folders/.../gits-demo-PYLxrg/plain -> /var/folders/.../gits-demo-PYLxrg/encrypted
2026-11-26T19:21:08.280Z decrypted /var/folders/.../gits-demo-PYLxrg/encrypted -> /var/folders/.../gits-demo-PYLxrg/back
2026-11-26T19:21:08.377Z decrypted .../play/0519/git@github.com:demo__secret.git/.env -> .../play/0519/git@github.com:demo__secret.git/....
```

## 6. How it is wired

The whole wrapper, [gits.sh](gits.sh), is three lines of substance:

```sh
source "${_DIR}/env.sh"                    # GITS_ENCRYPTION_SOCKET and the rest
export GITS_ALL="${_DIR}/start.sh"
export GITS_EXIT="${_DIR}/stop.sh"
"${GITS_DEMO_BIN}" "${@}"
```

- **`GITS_ENCRYPTION_SOCKET`**: where gits sends `encode "<file>" "<file>"` / `decode ...`.
- **`GITS_ALL`** is the script of every [lifecycle event](../LIFECYCLE.md). `start.sh` looks at
  its first argument and does something only for `START`, the first event of every command.
  gits waits for a script of an event, and a `START` script which fails stops the command:
  gits goes on only when the test of the encryption passed.
- **`GITS_EXIT`** is not an event of a command: its script runs as the last thing of every
  start of gits, like `trap ... EXIT` in a shell. After a command which worked or failed, after
  Ctrl+C, `kill` (SIGTERM), a closed terminal (SIGHUP). Only `kill -9` can't be caught by anything.

Try the ways out:

```sh
cd "$P/project"

# a start which fails (no such key): gits stops before doing anything, and stop.sh still ran
GITS_DEMO_SSH_KEY=/no/such/key /bin/bash $W diff; echo "exit code $?"
ls "$P/../"                       # key key.pub play

# Ctrl+C in the middle: make the config slow, start, press Ctrl+C while it sleeps
echo 'sleep 10' >> .git/gits.sh
/bin/bash $W diff                 # ... press Ctrl+C
ls "$P/../"                       # key key.pub play: stopped anyway
sed -i.bak '/^sleep 10$/d' .git/gits.sh && rm .git/gits.sh.bak
```

Commands without lifecycle events (`--help`, `--version`, `events`, `list`) have no `START`:
nothing is started for them, and `stop.sh` finds nothing to stop.

## 7. For real

- your key is already in your own agent: in `start.sh` drop the two commands of step 1
  (`ssh-agent`, `ssh-add`), in `stop.sh` the line of the agent, and point `GITS_DEMO_SSH_KEY`
  to your key (`~/.ssh/id_ed25519`); the server then asks the agent of `SSH_AUTH_SOCK`
- `alias gits='/bin/bash /path/to/examples/gits.sh'`
- one gits at a time: two commands running together share the socket, and the one which ends
  first stops the server of the other
- every command pays for the start (about half a second). A server which stays running:
  `tests/encoder/encoder-start.sh`, [SUMMARY.md, case 007](SUMMARY.md#case-007-encrypted_files)

## 8. Clean up

```sh
cd "$P/../../.."                  # the root of this repository
/bin/bash examples/stop.sh
rm -rf examples/tmp examples/server.log
unset GITS_SOURCE P W             # GITS_SOURCE: open a new terminal to get your own back
```
