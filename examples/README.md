# TLDR

This is first implementation [encrypt/](encrypt/ENCRYPT_PROCESS.md) 

But then I realised that I could actually reuse OS ssh-agent - one thing less to bother in start.sh and I could actually protect that ssh key with passowrd because it wouldn't be so annoying to be asked just once per session, hence [encrypt_os_ssh_agent/](encrypt_os_ssh_agent/ENCRYPT_PROCESS.md)



# Examples

| Directory | What it is |
| --- | --- |
| [encrypt/](encrypt/ENCRYPT_PROCESS.md) | gits with encryption, **with an ssh-agent of its own** | 
| [encrypt_os_ssh_agent/](encrypt_os_ssh_agent/ENCRYPT_PROCESS.md) | the same, **with the ssh-agent of your terminal** and a separate key loaded into it |
| [base64_md5/](base64_md5/ENCRYPT_PROCESS.md) | gits with an encoder process which is **not encryption at all** (`<md5>:<base64>`): proof that gits knows only the socket protocol |
| [wait/](wait/SUMMARY.md) | not about gits: ways for a program to send a request to a unix socket and wait for the reply |
| [SUMMARY.md](SUMMARY.md) | every use case of gits, command by command, in a directory `s/` |

## encrypt and encrypt_os_ssh_agent

Both are the same demo: a wrapper `gits.sh` used in place of `gits`, which starts a small server
on a unix socket before every command (`GITS_START=start.sh`) and stops it after it
(`GITS_EXIT=stop.sh`). gits sends its `encode` / `decode` requests to that socket, the server
starts the binary `ssenc` for each of them, and `ssenc` asks an ssh-agent to do the work with
an ssh key. Each directory has its own storage, two projects (`repoa`, `repob`) and two keys,
created by its `reset_setup.sh`, and the same guide `ENCRYPT_PROCESS.md` with the same steps.

They differ in one thing: **which ssh-agent holds the key**.

| | [encrypt/](encrypt/ENCRYPT_PROCESS.md) | [encrypt_os_ssh_agent/](encrypt_os_ssh_agent/ENCRYPT_PROCESS.md) |
| --- | --- | --- |
| The agent | a private one: `start.sh` starts it for every gits command, `stop.sh` kills it | the one already running in your terminal (`SSH_AUTH_SOCK`). Nothing is started or stopped |
| `SSH_AUTH_SOCK` | set by `env.sh` to `tmp/agent.sock`; the one of your terminal is ignored | not touched: whatever your terminal has |
| Who loads the key | `start.sh` (`ssh-add` of the key file), every command | you: `ssh-add keys/key keys/key2`, a step of the guide |
| `GITS_ENCRYPTION_SSH_KEY` | path of the private key file (`tmp/key`) | which of the loaded keys: its fingerprint (`SHA256:...`), no path |
| The private key file | needed at every command | needed only for `ssh-add` |
| A key with a passphrase | not practical: it would be asked at every gits command | fine: asked once, by `ssh-add` |
| Your own agent | never touched | used: two demo keys are added to it by you, and removed by `reset_setup.sh` (or by you) |
| Keys after `reset_setup.sh` | new ones | the same files, no longer loaded in the agent |
| The key is missing | can't happen, `start.sh` loads it | shown in the guide: the test of `start.sh` fails (`key SHA256:... is not loaded in ssh-agent`), gits stops, nothing is pushed |
| Test | `tests/test016` | `tests/test018` (with a private agent in the role of "the agent of the terminal") |

Which one to look at:

- **encrypt/**: to see the whole mechanism without any risk for your own setup. Everything it
  needs is created and removed by its scripts.
- **encrypt_os_ssh_agent/**: the setup for real use. One agent holds your key for GitHub and a
  separate key only for gits, the key can have a passphrase, and it can be changed
  (`gits crypt rekey`) without touching the GitHub one. The background is in
  [USE_OS_SSH_WITH_SEPARATE_SSH_KEY.md](encrypt_os_ssh_agent/USE_OS_SSH_WITH_SEPARATE_SSH_KEY.md).

## base64_md5

The same wrapper, the same projects, the same gits commands, but behind the socket there is no
`ssenc`, no ssh key and no ssh-agent: a server of its own which stores a file as one line,
`<md5 of the base64 text>:<base64 of the content>`. It protects nothing and is not meant to.

It is there to show, and to test (`tests/test019`), that gits is not tied to the encrypt
project. gits knows three things, all from outside: the requests `encode` / `decode`, the reply
`error MALFORMED` ("not an encoded file"), and the script of `GITS_ENCRYPTION_DETECT`, which
says whether a stored file is an encoded one when there is no server to ask
(`gits crypt status`). The last one is the only place where gits has a rule of its own (the
files of the encrypt project), and the variable replaces it.

It is also the smallest of the three to read: no keys, nothing to build, `server.ts` runs as it is.
