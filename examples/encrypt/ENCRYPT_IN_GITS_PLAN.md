# Plan: encryption in gits (without the socket, encrypt all, decrypt all, rekey)

Status: **implemented**, with the decisions listed in "Decisions". What is different from the
first version of this plan is in "Changed on the way". The steps to try everything by hand are
at the end, and in full in [ENCRYPT_PROCESS.md](ENCRYPT_PROCESS.md) (steps 6 and 7); the same
steps are the test `tests/test016`.

The encryption itself is the library of
`__linked/STOPSOPA__encrypt/STOPSOPA__encrypt` (called "encrypt" below, its
`examples/SUMMARY.md` was the source for this design).

## Goal

- an element `SOURCE:e:TARGET` without `GITS_ENCRYPTION_SOCKET`: `:e:` is ignored, the file is
  transported as it is
- with `GITS_ENCRYPTION_SOCKET`: gits encrypts and decrypts through the socket at the right moments
- a way to: encrypt everything which is `:e:`, decrypt everything, change the key (rekey)
- for all of it: a way to tell whether a file is already encrypted

## Principle: gits never knows about keys

gits knows two things: the socket, and whether a file looks encrypted. Which key encrypts and
which key opens a file is the business of the server behind the socket. No key names and no
second set of variables in gits.

And the server decides nothing about a file either: it passes the data to the library
(since then: it starts the binary `ssenc` of the same repository, `GITS_DEMO_SSENC`). Text or
binary (`lines` or `blob` mode) is detected by the library, the server only asks for `mode: "auto"`.

## What the design of encrypt dictates

- **Detection is `inspect`.** It needs no key: it returns the mode and the key slots, or
  `MALFORMED` for "not an encrypted file".
- **Encrypted output is always ASCII text**, also for binary input (blob mode). So a binary
  file is never an encrypted one.
- **`decrypt` and `rekey` use one named key.** Not "any key the agent holds": the server has
  to be told which key opens the existing files.
- **An update copies the key lines.** `encrypt` with the existing encrypted file as `previous`
  reuses its data key and its `#slot` lines (lines which were not edited stay identical). So
  changing the key of the server changes nothing in the stored files, and a key which doesn't
  open the previous version gives `AUTH`. Keys of a stored file change only through `rekey`.
- **`rekey(file, oldKey, newKeys, { rotateDataKey })`**: one old key, any number of new ones.
  `rotateDataKey: false` (`--rewrap-only`) replaces only the key lines and leaves the rest
  byte for byte.

## Detection in gits

`src/crypt.rs`, function `slots`. No socket and no key needed:

1. binary (a NUL byte in the first 8000 bytes, the rule of git): **not encrypted**
2. text: **encrypted** only when the first line is `#ssenc1 lines ...` or `#ssenc1 blob ...`
   and it is followed by at least one `#slot ...` line

The `#slot` lines also give what opens the file: the fingerprint of an ssh key
(`SHA256:...`) or `password`. `gits crypt status` prints them.

Only files of `:e:` elements are tested. A `::` file which happens to look like an encrypted
one is left alone (the scope `--storage` is the exception: it takes every file which looks
encrypted, lists it, and changes nothing without `--yes`).

## What `:e:` does

| | stored plain (or not stored yet) | stored encrypted |
|---|---|---|
| **no socket** | transported as it is, with a notice that `:e:` is ignored | **error: the socket is needed**, nothing is touched |
| **socket** | pull / diff use it as it is and say so; push encrypts it | decrypted / encrypted through the socket |

- the top right cell: transporting ciphertext as it is would overwrite the local `.env` with
  ciphertext on pull, and a push would silently replace encrypted files by plain ones the
  first time the server isn't running (and the plain text stays in the git history). So: no
  socket means everything plain, and once a file is encrypted going back takes an explicit
  `gits crypt decrypt`
- the bottom left cell needs no special code for push: `encode` onto a stored plain file
  finds no previous encrypted version and encrypts from scratch
- `error AUTH` from the server is explained: the file is stored with another key

## The socket protocol: two new requests

```
encode  "in" "out"     ->  ok encode "out"       as before
decode  "in" "out"     ->  ok decode "out"       as before
rekey   "in" "out"     ->  ok rekey "out"        rekey(file, KEY, NEWKEYS): everything encrypted again
rewrap  "in" "out"     ->  ok rewrap "out"       the same with rotateDataKey: false, only the key lines
```

The keys stay with the server. It has one key which opens what is stored and encrypts new
files, and, only for a rotation, the new keys:

| | the server of this demo (`server.ts`) |
|---|---|
| the key in use | `GITS_DEMO_SSH_KEY` |
| the new key, only for `rekey` / `rewrap` | `GITS_DEMO_NEW_SSH_KEY` |

- without a new key a `rekey` / `rewrap` request answers `error USAGE`
- a file which the key in use doesn't open answers `error AUTH`
- a rotation server lives for one command: `GITS_START` starts it with both keys, `GITS_EXIT` stops it
- gits never sends the same path as input and output: the result is written next to the
  file and renamed after a successful reply, so a failed request leaves the file as it was

## gits commands

```
gits crypt status            every ':e:' file: stored encrypted (and the keys which open it:
                             fingerprints of ssh keys), plain, or not stored yet. Needs no socket
gits crypt encrypt --yes     ':e:' files stored plain -> encrypted          (request encode)
gits crypt decrypt --yes     files stored encrypted -> plain                (request decode)
gits crypt rekey --yes       files stored encrypted -> the new keys         (request rekey)
gits crypt rekey --rewrap-only --yes       only the key lines change       (request rewrap)

scope, after the verb:
  (nothing)    the ':e:' elements of this project (.git/gits.sh)
  all          the ':e:' elements of every project below the current directory
  --storage    every file of the storage which is encrypted, whatever config it belongs to,
               also projects which are not on this machine (not for encrypt: only a config
               says what should be encrypted)

Without --yes: only the list of files which would change, exit code 1.
```

Each of them: one clone of the storage, one request per file, one commit
(`gits crypt <verb> (<scope>, <n> files)`), one push. Only the storage is changed, local
files are not touched. A failed request stops everything before the commit.

Lifecycle: the command is `crypt` (`GITS_CRYPT_START`, ... 14 events, no events per file).

## Decisions

| Question | Decision |
|---|---|
| new requests in the protocol, or two sockets (old key, new key)? | new requests `rekey`, `rewrap`: the plain text never touches the disk, one server |
| rotation: a mode chosen at the start of the server, or always? | chosen at the start: the server knows the new key only when it is given one |
| no socket + stored encrypted | an error |
| `gits crypt <verb>` or `gits encrypt` / `decrypt` / `rekey`? | `gits crypt <verb>` |
| socket + stored plain: in sync or not? | **in sync** when the content is the same (see below) |

## Changed on the way

- **"socket + stored plain" stays in sync.** The first version proposed "not in sync, because
  a push would change the storage". Kept as it was before: `diff` / `isinsync` / `state`
  compare the content, and say in the output that the file is stored not encrypted. The form
  is the job of `gits crypt status`. (An `isinsync` which says "not in sync" while no line
  differs would send every script using it into a push.)
- **`--mode auto` is not a decision of the server.** The server passes `mode: "auto"` to the
  library and the library detects text / binary. The demo server lost its `seal` option with
  it: a seal is an error in blob mode, and the server should not have to know which mode it is.
- **The server of encrypt itself (`examples/socket/server.ts`) is not changed.** It is another
  repository. `rekey` / `rewrap` are answered by `examples/encrypt/server.ts` of this demo.
  With the server of encrypt: `gits crypt status | encrypt | decrypt` work, `rekey` answers
  `error USAGE`.
- **Rekey to several new keys** (old + new for a transition across machines) is possible in
  the library, the demo server takes one new key.

## What was built

| Where | What |
|---|---|
| `src/crypt.rs` | detection (`slots`), `gits crypt` |
| `src/socket.rs` | requests `rekey`, `rewrap`; `AUTH` explained |
| `src/ops.rs` | `without_socket`: the table "What `:e:` does" for diff, isinsync, push, pull, state |
| `src/events.rs`, `src/main.rs` | command `crypt`: events, arguments, `--help` |
| `examples/encrypt/server.ts` | `rekey`, `rewrap`, `GITS_DEMO_NEW_SSH_KEY`, `mode: "auto"` |
| `examples/encrypt/env.sh`, `keys.sh`, `start.sh`, `gits.sh`, `reset_setup.sh` | two keys (`key`, `key2`), a key by its name, the new key in the agent, `GITS_DEMO_NO_SOCKET`, `GITS_DEMO_WORK`, a binary file in `repob` |
| `tests/test016` | both sequences below, 34 checks |
| docs | `README.md` (9. Encrypted files), `gits --help`, `LIFECYCLE.md`, `CHANGES.md`, `ENCRYPT_PROCESS.md` |

## Try it by hand

Everything from `examples/encrypt`. `/bin/bash gits.sh` is gits with the server started and
stopped around every command; `GITS_DEMO_NO_SOCKET=1` in front of it: gits without the socket.

### A. plain, encrypted, the whole storage decrypted, encrypted with another key

```sh
cd examples/encrypt
/bin/bash reset_setup.sh                                  # gits_source, repoa, repob, tmp/key, tmp/key2

# no socket: ':e:' is ignored
cd repoa
GITS_DEMO_NO_SOCKET=1 /bin/bash ../gits.sh push --yes
cat "../gits_source/git@github.com:demo__repoa.git/.env"  # plain text

# the socket appears
/bin/bash ../gits.sh diff                                 # marked :e: but stored not encrypted ... in sync
/bin/bash ../gits.sh crypt status                         # plain
/bin/bash ../gits.sh crypt encrypt --yes                  # encrypted in the storage
cd ../repob
/bin/bash ../gits.sh push --yes                           # a push encrypts too (cert.bin: blob mode)
cd ..
/bin/bash gits.sh crypt status all                        # encrypted: 4, the fingerprint of key

# no socket + stored encrypted: an error
(cd repoa && GITS_DEMO_NO_SOCKET=1 /bin/bash ../gits.sh diff)

# decrypt the entire storage
/bin/bash gits.sh crypt decrypt --storage --yes
cat "gits_source/git@github.com:demo__repoa.git/.env"     # plain text again
(cd repoa && GITS_DEMO_NO_SOCKET=1 /bin/bash ../gits.sh diff)    # works without the socket again

# encrypt again, with the other key
GITS_DEMO_SSH_KEY=key2 /bin/bash gits.sh crypt encrypt all --yes
/bin/bash gits.sh crypt status --storage                  # the fingerprint of key2
(cd repoa && /bin/bash ../gits.sh diff)                   # AUTH: key doesn't open it
(cd repoa && GITS_DEMO_SSH_KEY=key2 /bin/bash ../gits.sh diff)   # in sync
```

### B. from scratch: encrypted, then rekey

```sh
/bin/bash reset_setup.sh                                  # still in examples/encrypt
(cd repoa && /bin/bash ../gits.sh push --yes)
(cd repob && /bin/bash ../gits.sh push --yes)
/bin/bash gits.sh crypt status all                        # encrypted: 4, the fingerprint of key

/bin/bash gits.sh crypt rekey --storage --yes             # USAGE: the server has no new key
GITS_DEMO_NEW_SSH_KEY=key2 /bin/bash gits.sh crypt rekey --storage --yes
/bin/bash gits.sh crypt status --storage                  # the fingerprint of key2

(cd repoa && /bin/bash ../gits.sh diff)                   # AUTH: key is out
(cd repoa && GITS_DEMO_SSH_KEY=key2 /bin/bash ../gits.sh diff)   # in sync

# only the key line, back to key, only repoa
(cd repoa && GITS_DEMO_SSH_KEY=key2 GITS_DEMO_NEW_SSH_KEY=key /bin/bash ../gits.sh crypt rekey --rewrap-only --yes)
git -C gits_source show --stat HEAD                       # one file, one line
/bin/bash gits.sh crypt status --storage                  # repoa: key, repob: key2
```

The test of exactly this: `/bin/bash tests/test016/test.sh` (it works in
`tests/test016/tmp/demo`, not here).

## Left open

- `rekey` / `rewrap` (and maybe several `--new-ssh-key`) in the server of the encrypt
  repository, so the long-running encoder of `tests/encoder/encoder-start.sh` can rotate too
- a rekey doesn't clean the history of the storage: old commits stay readable with the old key
- two gits commands at the same time on the storage: `gits crypt` rewrites many files in one
  commit, a push from another machine in between is refused by git (run it again)
