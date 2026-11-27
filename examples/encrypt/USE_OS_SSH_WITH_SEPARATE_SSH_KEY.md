# Using the ssh-agent of the system, with a separate key only for gits

The demo ([ENCRYPT_PROCESS.md](ENCRYPT_PROCESS.md)) starts an ssh-agent of its own and gives
`ssenc` the path of a key file. This document explains why, what really happens between `ssenc`
and an agent, and what would have to change to use the agent which is always running on your
machine, with one more key loaded into it only for encryption.

Short answers:

- `ssenc` doesn't need a key file. `--ssh-key` takes a public key file **or a fingerprint**
  (`SHA256:...`) of a key which is loaded in the agent. The demo gives a file only because
  `server.ts` was written that way.
- An agent has no names for keys. A key is identified by its **public key**; the fingerprint is
  the short form of it. That is the "name" to use.
- Yes, your key for GitHub and a second key for gits can live in the same agent. One thing in
  `~/.ssh/config` is worth doing then, see [Your GitHub key next to it](#your-github-key-next-to-it).
- Yes, the key can have a passphrase: you type it once, when you load the key (`ssh-add`).

Everything marked **checked** below was run with the `ssenc` binary of this demo
(`examples/encrypt/bin/ssenc`) against a throwaway agent.

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

So the answer to "why do we always give paths to key files": we don't have to. `server.ts` adds
`.pub` to `GITS_ENCRYPTION_SSH_KEY` and passes that path; it could pass a fingerprint just as well.

## A separate key for gits in your own agent

Create it once. With a passphrase, since it protects your secrets:

```sh
ssh-keygen -t ed25519 -C "gits-encryption" -f ~/.ssh/gits_encryption
ssh-keygen -lf ~/.ssh/gits_encryption.pub        # its fingerprint: SHA256:...   <- the "name" of the key
```

Load it, once per session of the agent. This is where the passphrase is asked, and only here:

```sh
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
fingerprint as the key which opens and the new one as the key the files get (step 7 of
[ENCRYPT_PROCESS.md](ENCRYPT_PROCESS.md)). Both have to be loaded during that one command.
Afterwards: `ssh-add -d ~/.ssh/old_key.pub` removes the old one from the agent.

## What would change in the demo

Your idea works: `GITS_DEMO_AGENT` optional. Defined: `start.sh` starts an agent of its own
and loads the key files, like now. Not defined: nothing is started, the server inherits
`SSH_AUTH_SOCK` of your terminal, and `ssenc` finds its key in your agent by fingerprint.

Nothing of this is done yet. The changes:

| File | Change |
| --- | --- |
| `env.sh` | `GITS_DEMO_AGENT` without a default: empty means "the agent of the terminal". (To keep the demo and `tests/test016` as they are, they would define it themselves) |
| `start.sh` | the block "1. The agent" (`ssh-agent`, both `ssh-add`) and the check that the key file exists: only when `GITS_DEMO_AGENT` is defined |
| `stop.sh` | nothing: without `agent.pid` it kills no agent. It must not remove the socket file of an agent it didn't start, and with an empty `GITS_DEMO_AGENT` it doesn't |
| `server.ts` | `currentKey()` and `newKey()` add `.pub` today. They would pass the value as it is when it starts with `SHA256:`, and add `.pub` otherwise |
| `gits.sh`, gits itself | nothing |

Then, with your own agent:

```sh
ssh-add ~/.ssh/gits_encryption                                  # once per session, passphrase asked here
export GITS_ENCRYPTION_SSH_KEY="SHA256:..."                     # from: ssh-keygen -lf ~/.ssh/gits_encryption.pub
/bin/bash gits.sh push --yes                                    # GITS_DEMO_AGENT is not defined: your agent is used
```

and for a rotation:

```sh
GITS_ENCRYPTION_REKEY_SSH_KEY="SHA256:<new key>" /bin/bash gits.sh crypt rekey --storage --yes
```

A path of a key file keeps working in both modes (`GITS_ENCRYPTION_SSH_KEY=~/.ssh/gits_encryption`
would read `~/.ssh/gits_encryption.pub`), the fingerprint only makes the files unnecessary.

Two things to know before doing it:

- `start.sh` tests the server at every gits command (it encrypts and decrypts a small file).
  With a key which is loaded this is invisible. With `ssh-add -c` (confirm every use) you would
  be asked at every command, and once more for every file.
- A file encrypted with your real key in the storage of the demo is opened only by that key.
  `reset_setup.sh` brings the demo back to its own keys and an empty storage.
