# Using the ssh-agent of the system, with a separate key only for gits

The first demo ([examples/encrypt](../encrypt/ENCRYPT_PROCESS.md)) starts an ssh-agent of its
own and gives `ssenc` the path of a key file. This document explains why that is not necessary,
what really happens between `ssenc` and an agent, and how the agent which is always running on
your machine can be used, with one more key loaded into it only for encryption. The demo of
this directory ([ENCRYPT_PROCESS.md](ENCRYPT_PROCESS.md)) is built that way.

Short answers:

- `ssenc` doesn't need a key file. `--ssh-key` takes a public key file **or a fingerprint**
  (`SHA256:...`) of a key which is loaded in the agent. The first demo gives a file only because
  its `server.ts` was written that way.
- An agent has no names for keys. A key is identified by its **public key**; the fingerprint is
  the short form of it. That is the "name" to use.
- Yes, your key for GitHub and a second key for gits can live in the same agent. One thing in
  `~/.ssh/config` is worth doing then, see [Your GitHub key next to it](#your-github-key-next-to-it).
- Yes, the key can have a passphrase: you type it once, when you load the key (`ssh-add`).

Everything marked **checked** below was run with the `ssenc` binary of the demos
(`bin/ssenc`, copied by `encrypt.sh`) against a throwaway agent.

## What an agent is, and what it has no idea about

An ssh-agent is a process which holds private keys in memory and answers on a unix socket. Any
program finds it through the env var `SSH_AUTH_SOCK`. It can do only two things which matter here:

1. **list**: "which keys do you have?" It answers with the public key of each, and a comment.
2. **sign**: "sign these bytes with the key which has THIS public key." It answers with the
   signature. The private key never leaves the agent.

What it doesn't have:

- **no names.** The comment (`ssh-add -l` shows it at the end of each line) is only a label: the
  text from the key file, or the path of the file. It is not unique and it can't be used to ask
  for a key. A sign request names the key by its whole public key.
- **no idea about hosts.** The agent doesn't know that one key is "for GitHub" and another "for
  Bitbucket". It doesn't know about files either: after `ssh-add` the file on the disk is not
  read again, which is why you can remove it and everything keeps working.

```sh
ssh-add -l      # fingerprints:  256 SHA256:tSowzY8k...  comment (ED25519)
ssh-add -L      # whole public keys, the same lines as in the .pub files
```

The fingerprint is `SHA256:` + the hash of the public key. Two different keys never have the
same one, so it identifies a key as well as the public key itself. It is the same text which
`ssh-keygen -lf key.pub` prints, and which stands in every encrypted file (`#slot ssh ...`).

## How ssh picks a key for GitHub or Bitbucket

Your guess was right: by default it **tries them**.

1. ssh asks the agent for the list of keys.
2. For each key, in the order of the list, it sends only the **public** key to the server:
   "would you accept this one?" Nothing is signed yet, so this costs milliseconds.
3. The server answers no, or yes. On the first yes ssh asks the agent to sign, and you are in.

GitHub knows which account you are from the key which was accepted. Nothing is selected "by
domain", unless you say so yourself in `~/.ssh/config`:

```
Host github.com
  IdentityFile ~/.ssh/github_key
  IdentitiesOnly yes
```

`IdentityFile` says which key belongs to this host, `IdentitiesOnly yes` says "offer only that
one, not everything the agent has". ssh reads the `.pub` file to know which of the agent's keys
it is, the signing is still done by the agent.

## How ssenc picks a key

`ssenc` doesn't try keys. You tell it which one, with `--ssh-key`, in one of two forms:

| `--ssh-key` | What ssenc does with it |
| --- | --- |
| a path: `tmp/key.pub` | reads the **public** key from the file. The private key file is never opened |
| a fingerprint: `SHA256:gj38XF...` | asks the agent for its list and takes the key with this fingerprint. No file at all |

In both cases it ends up with a public key, and from there it is the same:

1. `ssenc` connects to the socket of `SSH_AUTH_SOCK`.
2. It asks the agent to **sign** a fixed text plus a random salt (the salt is stored in the
   file, in the `#slot` line) with that key.
3. The signature is turned into the key which locks the file (in the specification of the
   encrypt repository: `KEK = HKDF(signature, salt)`).
4. To decrypt, it looks in the file for the `#slot ssh ...` line with the fingerprint of the
   given key, reads the salt from it, asks the agent for the same signature again, and gets the
   same key again.

Two consequences:

- **Only `ssh-ed25519` and `ssh-rsa` keys work.** Step 4 needs the same signature for the same
  text every time. These two types give that, ECDSA and hardware (`sk-...`) keys don't.
  **Checked**: an ECDSA key gives `ENV: unsupported ssh key type ... only ssh-ed25519 and
  ssh-rsa give deterministic signatures`.
- **Whoever can talk to your agent can decrypt**, as long as the key is loaded. The socket is
  readable only by your user, so that means programs running as you.

**Checked**, with a key loaded in an agent and its two files removed from the disk:

```sh
ssenc encrypt --ssh-key "SHA256:gj38XF..." -i plain -o enc     # exit code 0, file is encrypted
ssenc decrypt --ssh-key "SHA256:gj38XF..." -i enc -o back      # exit code 0, content is back
ssenc decrypt --ssh-key other.pub -i enc -o back               # AUTH: no key slot could be opened with the given key
ssenc encrypt --ssh-key "SHA256:nothere" -i plain -o enc       # ENV: key SHA256:nothere is not loaded in ssh-agent (check: ssh-add -l)
```

So the answer to "why do we always give paths to key files": we don't have to. `server.ts` of
the first demo adds `.pub` to `GITS_ENCRYPTION_SSH_KEY` and passes that path. The one of this
directory passes the value as it is, so it can be a public key file or a fingerprint.

## A separate key for gits in your own agent

Create it once. With a passphrase, since it protects your secrets:

```sh
ssh-keygen -t ed25519 -C "gits-encryption" -f ~/.ssh/gits_encryption
ssh-keygen -lf ~/.ssh/gits_encryption.pub        # its fingerprint: SHA256:...   <- the "name" of the key
```

Load it, once per session of the agent. This is where the passphrase is asked, and only here:

```sh
ssh-add -l 
ssh-add -L
ssh-add ~/.ssh/gits_encryption
ssh-add -l                                       # it is in the list, next to your GitHub key
```

- **macOS** can keep the passphrase in the keychain, so you never type it again:
  `ssh-add --apple-use-keychain ~/.ssh/gits_encryption`. After a restart the agent is empty
  again, `ssh-add --apple-load-keychain` loads the keys back without asking.
- `ssh-add -t 8h ~/.ssh/gits_encryption` forgets the key after 8 hours, if you prefer that.
- Not loaded: gits doesn't hang, it stops with the `ENV` error shown above.

**Keep a copy of the private key file somewhere safe.** The agent is only memory. If the file
is gone and the agent restarts, nothing opens what was encrypted with that key.

### Your GitHub key next to it

After `ssh-add` of a second key, ssh offers **both** keys to every server, in the order of
`ssh-add -l`. For GitHub this is harmless as long as the gits key is not registered there: it is
refused and the next one is tried. It becomes a problem only when:

- the gits key is registered at GitHub too, under another account: you would be logged in as that one
- you have many keys loaded: a server closes the connection after a few refused ones (usually 6)

The `Host github.com` block with `IdentitiesOnly yes` from above removes both: ssh offers only
your GitHub key there, whatever else is loaded. `ssenc` is not affected by `~/.ssh/config` at
all, it never reads it.

### Changing the key later

Load the new key next to the old one and run `gits crypt rekey`: the server gets the old
fingerprint as the key which opens and the new one as the key the files get
([ENCRYPT_PROCESS.md, step 7](ENCRYPT_PROCESS.md#7-rekey-another-key-without-decrypting-to-the-storage)). Both have to be loaded during that one command.
Afterwards: `ssh-add -d ~/.ssh/old_key.pub` removes the old one from the agent.

## How the demo of this directory does it

Compared with [examples/encrypt](../encrypt/ENCRYPT_PROCESS.md), which has an agent of its own:

| File | examples/encrypt | this directory |
| --- | --- | --- |
| `env.sh` | `SSH_AUTH_SOCK` is set to a socket of the demo (`tmp/agent.sock`), the one of your terminal is ignored | `SSH_AUTH_SOCK` is not mentioned: the one of your terminal is used |
| `env.sh` | `GITS_ENCRYPTION_SSH_KEY`: path of the **private** key file | `GITS_ENCRYPTION_SSH_KEY`: the **fingerprint** of the key, `SHA256:...`. The default is read with `ssh-keygen -lf keys/key.pub`, because the demo generates its keys |
| `keys.sh` | creates the keys in `tmp/` | creates the keys in `keys/`, and says whether your agent has them. Loads nothing |
| `start.sh` | starts an agent, `ssh-add` of the key file(s), then the server | starts no agent, loads nothing and doesn't look into the agent: only the server and its test. A key which is not loaded makes the test fail, with what `ssenc` said |
| `stop.sh` | stops the server and the agent | stops the server |
| `server.ts` | passes `<value>.pub` to `ssenc --ssh-key` | passes the value as it is |
| `reset_setup.sh` | new keys every time | keeps the key files, and takes every key with `gits` in its label out of your agent (`ssh-add -d`) |
| `gits.sh`, gits itself | the same | the same |

Who loads the keys: you, with `ssh-add`. No script of this directory loads anything; the only
change a script makes in your agent is `reset_setup.sh` removing the keys which have `gits` in
their label: the two of the demo, and any other one named like that.

With your own key in place of the demo keys:

```sh
ssh-add ~/.ssh/gits_encryption                                  # once per session, passphrase asked here
export GITS_ENCRYPTION_SSH_PUBLIC_KEY"$(ssh-keygen -lf ~/.ssh/gits_encryption.pub | cut -d " " -f 2)"     # its fingerprint: SHA256:...
/bin/bash examples/encrypt_os_ssh_agent/gits.sh push --yes
```

(`export` keeps the variable for the whole terminal: every later command of the demo asks for
this key, also the ones of [ENCRYPT_PROCESS.md](ENCRYPT_PROCESS.md) which expect the key of the
demo. Back to the demo: `unset GITS_ENCRYPTION_SSH_KEY`.)

and for a rotation, both keys loaded:

```sh
ssh-add ~/.ssh/gits_encryption_new                              # the new key, next to the old one
GITS_ENCRYPTION_REKEY_SSH_KEY="$(ssh-keygen -lf ~/.ssh/gits_encryption_new.pub | cut -d " " -f 2)" /bin/bash examples/encrypt_os_ssh_agent/gits.sh crypt rekey --storage --yes
```

Two things to know:

- `start.sh` tests the server at every gits command (it encrypts and decrypts a small file).
  With a key which is loaded this is invisible. With `ssh-add -c` (confirm every use) you would
  be asked at every command, and once more for every file.
- A file encrypted with your real key in the storage of the demo is opened only by that key.

  WARNING`reset_setup.sh` brings the demo back to an empty storage so load ssh-add ~/.ssh/gits_encryption again
  WARNING`reset_setup.sh` brings the demo back to an empty storage so load ssh-add ~/.ssh/gits_encryption again
  WARNING`reset_setup.sh` brings the demo back to an empty storage so load ssh-add ~/.ssh/gits_encryption again
  WARNING`reset_setup.sh` brings the demo back to an empty storage so load ssh-add ~/.ssh/gits_encryption again
  WARNING`reset_setup.sh` brings the demo back to an empty storage so load ssh-add ~/.ssh/gits_encryption again

## No path to a public key: the fingerprint goes into the same parameter

`--ssh-key` is **not left out**. It stays in every call, only its value changes: the fingerprint
in place of the path. The code of `server.ts` is the same for both, `currentKey()` just returns
whatever `GITS_ENCRYPTION_SSH_KEY` holds:

```
ssenc encrypt --mode auto --ssh-key keys/key.pub      -i IN -o OUT      a path: the public key is read from the file
ssenc encrypt --mode auto --ssh-key "SHA256:gj38XF…"  -i IN -o OUT      a fingerprint: the public key is taken from the list of the agent
ssenc decrypt             --ssh-key "SHA256:gj38XF…"  -i IN -o OUT
```

Leaving `--ssh-key` out doesn't mean "take the key from the agent". An agent can hold many keys
and `ssenc` never guesses or tries them: it has to be told which one. Without any key it stops
(**checked**):

```
ssenc: USAGE: no key given: use --password-file, SSENC_PASSWORD or --ssh-key
```

(and with the env var `SSENC_PASSWORD` defined it would encrypt with that password, not with an
ssh key at all).

`rekey` works the same way, with two parameters, because it needs two keys: the one which opens
the file now, and the target, the one the file gets. Each is a path or a fingerprint,
independently of the other:

```
ssenc rekey --ssh-key "SHA256:<old key>" --new-ssh-key "SHA256:<new key>" -i IN -o OUT
            \__ opens what is stored __/ \__ THAT key: the target ______/
```

Both keys have to be loaded in the agent during that call: the old one signs to open the file,
the new one signs to lock it again. In the demo these are the two variables, and
`server.ts` (`rekey()`) puts them into those two parameters:

```sh
# --ssh-key: the key which opens what is stored
export GITS_ENCRYPTION_SSH_PUBLIC_KEY"$(ssh-keygen -lf ~/.ssh/gits_encryption.pub | cut -d " " -f 2)"

# --new-ssh-key: the target
GITS_ENCRYPTION_REKEY_SSH_KEY="$(ssh-keygen -lf ~/.ssh/gits_encryption_new.pub | cut -d " " -f 2)" /bin/bash gits.sh crypt rekey --storage --yes
```

Where a fingerprint comes from when there is no file: `ssh-add -l` prints it for every key the
agent has, the second word of each line. With the `.pub` file: `ssh-keygen -lf key.pub`. And
every encrypted file names the key which opens it, in its `#slot ssh <type> SHA256:...` line
(`gits crypt status` shows these).

## The header of every encrypted file

An encrypted file is text. It starts with a few lines which say how it was encrypted and which
keys open it, and only then comes the content. The beginning of a real one (`.env` of `repoa`):

```
#ssenc1 lines ws=1 pad=16
#slot ssh ssh-ed25519 SHA256:27aAYrNtj2ZPsUUb48Em9BCsut+NZyp0QdCmViUAC2M i3um7PsQW8-7mIZPXThp04skiXCAhXOlDqDZONe7E80 iFOSlNuid00CbVL39UoET-t8jFdBmNkjeSMBQkF7OVgtLr43ZfXzemdb7Wc1mTTB
n-pBkrLbk9nHrFyPi0kKL7UcoaoCRWMFfFMZdA_d3GPL9LbZK4Ob0NbYq8sxQrjF
OH8bfSXWHHqXK9WY_eSLBoWkeYkA3g3lDZBO2P8BJ9cEEt9Ixf4kPfquoSpxXR9F
```

The layout, always in this order:

```
#ssenc1 ...        exactly one: the header line
#slot ...          one or more: one line for each key which opens the file
#seal ...          optional, only in "lines" mode
<the content>      everything after them
```

Inside a line the fields are separated by exactly one space. That is why there are spaces in
the `#slot` line: it is one record with six fields. The long fields are binary data written in
base64url, an alphabet of letters, digits, `-` and `_`, which has no space in it, so a space is
a safe separator.

### Line 1: `#ssenc1 lines ws=1 pad=16`

| Field | Here | Meaning |
| --- | --- | --- |
| 1 | `#ssenc1` | "this is a file of the encrypt tool, format version 1". What gits looks for to tell an encrypted file from a plain one |
| 2 | `lines` | the mode: how the content below is stored. `lines`: every line of the original is encrypted by itself and stays one line, so a change of one line of the original changes one line here (small diffs in git). The other mode is `blob`, see below |
| 3 | `ws=1` | whitespace is preserved: spaces and tabs at the beginning and the end of a line stay as they are (readable), only what is between them is encrypted. An indented file keeps its shape. `ws=0`: the whole line is encrypted, also an empty one |
| 4 | `pad=16` | padding: before a line is encrypted it is filled up to a multiple of 16 bytes, so the length of an encrypted line doesn't give away the exact length of the original (a 3 character value and a 14 character one look the same). `pad=0`: no padding |

A binary file (or any file `ssenc` is told to keep as a whole) has the other form of this line:

```
#ssenc1 blob chunk=65536
```

| Field | Here | Meaning |
| --- | --- | --- |
| 2 | `blob` | the mode: the content is encrypted as a whole, in pieces, and written as lines of 76 characters. Nothing of the shape of the original is visible |
| 3 | `chunk=65536` | the size of one piece in bytes. Each piece is encrypted by itself, with its position, so pieces can't be reordered or cut off unnoticed |

Which mode is used is decided by `ssenc` (the server gives `--mode auto`): `lines` for a file
which is valid UTF-8 text, `blob` for everything else.

### Line 2: `#slot ssh ssh-ed25519 SHA256:27aA… i3um7P… iFOSlN…`

A slot is "one key which opens this file". The content is not encrypted with your ssh key
directly: it is encrypted with a random key made for this file (the data key), and each slot
holds a copy of that data key, locked with one of the keys which should open the file.

| Field | Here | Meaning |
| --- | --- | --- |
| 1 | `#slot` | marks a key line |
| 2 | `ssh` | the kind of key: an ssh key. The other kind is `pw`, a password |
| 3 | `ssh-ed25519` | the type of the ssh key (`ssh-ed25519` or `ssh-rsa`, no other type works) |
| 4 | `SHA256:27aAYrNtj2ZP…UAC2M` | **the fingerprint of the key which opens the file.** Not a secret: it only names the key |
| 5 | `i3um7PsQW8-7…e7E80` | the salt: 32 random bytes, made when the slot was created |
| 6 | `iFOSlNuid00C…mTTB` | the data key of this file, locked ("wrapped") with your ssh key |

How they are used to open the file:

1. `ssenc` finds the `#slot ssh` line whose fingerprint (field 4) is the one of the key you gave
   it (`--ssh-key`). No such line: `AUTH`, this key doesn't open the file.
2. It asks the agent to sign a fixed text plus the salt (field 5) with that key.
3. From the signature it makes a key, and with it unlocks field 6: that gives the data key.
4. The data key decrypts the content below.

Consequences which are visible in gits:

- **More keys, more lines.** A file encrypted for two keys has two `#slot` lines, each with its
  own salt and its own locked copy of the same data key. Any one of the keys opens the file.
- **`gits crypt rekey --rewrap-only` changes only this line**: a new slot for the new key, the
  same data key inside, the content below byte for byte the same.
- **`gits crypt rekey` (without it) changes everything**: a new data key, so every line of the
  content is different too.
- **`gits crypt status` reads field 4** of every stored file to show `[SHA256:...]`. It needs no
  key and no socket for that: the fingerprint is plain text.

A password slot looks like this, the same idea with a password in place of an ssh key:

```
#slot pw argon2id m=65536,t=3,p=4 <salt> <wrapped>
```

`argon2id m=...,t=...,p=...` are the settings of the function which turns the password into a
key (memory, rounds, threads). gits doesn't use passwords, the demo only ssh keys.

### `#seal`, when it is there

```
#seal <one field of base64url>
```

Only in `lines` mode and only when the file was encrypted with `--seal` (the demo doesn't). It
is a checksum of the header line and the whole content, made with the data key. Without it
every line is protected by itself, but lines could be removed or reordered unnoticed; with it
any such change is detected (`AUTH`).

### Which key opens this file?

Compare field 4 of the `#slot` line with the fingerprint of a key. `ssh-keygen -lf` prints the
fingerprint of a public key file (it only reads the file, nothing is created or changed):

```sh
head -n 2 "gits_source/git@github.com:demo__repoa.git/.env"      # ... #slot ssh ssh-ed25519 SHA256:27aAYr...UAC2M ...
ssh-keygen -lf tmp/key.pub                                       # 256 SHA256:U+99wU...9IC8  gits-demo-key (ED25519)     no
ssh-keygen -lf tmp/key2.pub                                      # 256 SHA256:27aAYr...UAC2M gits-demo-key2 (ED25519)    yes: key2 opens it
```

(`tmp/key.pub` is the path in `examples/encrypt`; in this directory the keys are `keys/key.pub`
and `keys/key2.pub`.) The same text is what the agent shows for a loaded key, so without any
file:

```sh
ssh-add -l                                # is a key with that fingerprint loaded?
```

and for every `:e:` file at once: `gits crypt status`, `gits crypt status all` or
`gits crypt status --storage`.

## Try it yourself: ask your agent to sign something

Everything `ssenc` does with the agent is one request: "sign these bytes with that key". The
same request can be made by hand with `ssh-keygen -Y sign`, a tool which is already on your
machine. The example uses the agent of your terminal (`SSH_AUTH_SOCK`, nothing is started) and
a key made only for it, which is removed at the end.

The commands were **checked**, against a throwaway agent. Run them in an empty directory:

```sh
mkdir -p /tmp/agent-demo && cd /tmp/agent-demo
```

### 1. Create a key and load it

```sh
ssh-keygen -t ed25519 -N "" -C "agent-demo" -f demo_key     # two files: demo_key (private), demo_key.pub (public)
                                                            # -N "": no passphrase. Leave -N out and it asks for one

ssh-add demo_key                          # Identity added: demo_key (agent-demo)
ssh-add -l                                # ... 256 SHA256:Gr0pY4... agent-demo (ED25519)    <- next to your own keys
```

From this moment the agent has the private key in its memory. To see that nothing reads the
file any more, remove it:

```sh
rm demo_key                               # only the private file. demo_key.pub stays: it says WHICH key
```

(For a real key keep a copy of that file somewhere safe: the agent forgets everything when it stops.)

### 2. Sign

```sh
echo "hello" > message.txt

ssh-keygen -Y sign -f demo_key.pub -n demo message.txt
#   Signing file message.txt
#   Write signature to message.txt.sig

cat message.txt.sig                       # -----BEGIN SSH SIGNATURE----- ... -----END SSH SIGNATURE-----
```

- `-f demo_key.pub`: a **public** key file. `ssh-keygen` can't sign with it, so it asks the
  agent of `SSH_AUTH_SOCK`: "sign this with the key which has this public key". The private
  file doesn't exist any more and it still works. This is exactly how `ssenc` refers to a key.
- `-n demo`: the namespace, a word which is signed together with the content. It says what the
  signature is for, so a signature made for one purpose can't be passed off as one for another
  (`ssenc` uses `ssenc-v1@stopsopa`, git uses `git`, an ssh login uses none of these).
- the result is in a new file, `message.txt.sig`. `message.txt` is not changed.

Sign the same file again and the signature is the same, byte for byte. That is the property
`ssenc` is built on (it turns the signature into the key which locks a file, so it has to get
the same one again when it opens the file), and why only `ssh-ed25519` and `ssh-rsa` keys work.

```sh
cp message.txt.sig first.sig && rm message.txt.sig
ssh-keygen -Y sign -f demo_key.pub -n demo message.txt
cmp first.sig message.txt.sig && echo "the same signature"
```

### 3. Verify

Verifying needs no agent and no private key: only the public key. Anybody who has
`demo_key.pub` can do it. `ssh-keygen` wants the public keys it should trust in a file, one
line for each: a name, then the public key.

```sh
echo "me@example.com $(cat demo_key.pub)" > allowed_signers

ssh-keygen -Y verify -f allowed_signers -I me@example.com -n demo -s message.txt.sig < message.txt
#   Good "demo" signature for me@example.com with ED25519 key SHA256:Gr0pY4...

echo "hellO" > changed.txt
ssh-keygen -Y verify -f allowed_signers -I me@example.com -n demo -s message.txt.sig < changed.txt
#   Signature verification failed: incorrect signature          (one letter is different)

ssh-keygen -Y verify -f allowed_signers -I me@example.com -n other -s message.txt.sig < message.txt
#   fails too: the namespace is part of what was signed
```

Without a list of trusted keys, only "is this a correct signature, and of which key":

```sh
ssh-keygen -Y check-novalidate -n demo -s message.txt.sig < message.txt
#   Good "demo" signature with ED25519 key SHA256:Gr0pY4...
```

### 4. Remove the key from the agent

```sh
ssh-add -d demo_key.pub                   # Identity removed. -d takes the public key file
ssh-add -l                                # only your own keys again
ssh-keygen -Y sign -f demo_key.pub -n demo message.txt        # fails now: nobody has the private key
cd / && rm -rf /tmp/agent-demo
```

### What else an agent is for

An agent itself can do very little, on purpose. Its whole job: hold private keys, **list** their
public parts, **sign** with one of them, and let keys be **added**, **removed** and **locked**.
It never gives a private key back, and it can't encrypt or decrypt anything. Everything below is
some program asking for a signature.

What signatures are used for:

| | Who asks the agent | What for |
| --- | --- | --- |
| ssh login | `ssh`, `scp`, `sftp`, `rsync` | the server sends a challenge, the agent signs it, the server checks it with your public key. `git clone git@github.com:...` is this too |
| signing a file | `ssh-keygen -Y sign` | the example above: proof that the owner of a key wrote exactly this content |
| signing git commits and tags | `git`, through `ssh-keygen -Y sign` | `git config gpg.format ssh`, `git config user.signingkey ~/.ssh/key.pub`, then `git commit -S`. GitHub shows "Verified" when the public key is registered there as a signing key |
| encryption | `ssenc` | not a feature of the agent: `ssenc` asks for a signature and derives an encryption key from it |
| login on a far machine | `ssh -A` (agent forwarding) | a machine you logged in to can ask **your** agent for signatures, to log in further. The keys stay with you. Only for machines you trust: while you are connected, root there can use your agent |

Managing what is loaded, all with `ssh-add`:

| Command | |
| --- | --- |
| `ssh-add <file>` | load a private key (asks for its passphrase once) |
| `ssh-add -l`, `ssh-add -L` | list: fingerprints, or whole public keys |
| `ssh-add -d <file>.pub`, `ssh-add -D` | remove one key, or all of them |
| `ssh-add -t 8h <file>` | load a key which the agent forgets by itself after 8 hours |
| `ssh-add -c <file>` | load a key which asks you to confirm every single use (needs a program for that question, `ssh-askpass`) |
| `ssh-add -x`, `ssh-add -X` | lock the agent with a password (it refuses everything, also listing and removing), and unlock it |
| `ssh-add -T <file>.pub` | test: can the agent really sign with this key? Signs and verifies, exit code 0 when yes |
| `ssh-add --apple-use-keychain <file>` | macOS: load, and keep the passphrase in the keychain |

What an agent does **not** do: it has no names for keys, no idea which key is for which host,
no log of who asked. Any program running as your user can ask it to sign, so a loaded key is
usable by everything you run, for as long as it is loaded (`-t` and `-c` limit that).
