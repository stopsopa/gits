# Release Notes

Each release has its own `## vX.Y.Z` section. The release workflow copies the section matching the pushed tag to the top of the GitHub release page (`bash/release_notes.sh`), so add the section before running `tag.sh` (`xx publish`). To see the page before releasing: `xx "release notes preview" vX.Y.Z`.

The longer story of every change, with the reasons: [CHANGES.md](CHANGES.md).

## v1.0.0

- **All variables are `GITS_*`** (was `GITSTORAGE*`): `GITS_SOURCE`, `GITS_SHELL`, `GITS_ENCRYPTION_SOCKET`, `GITS_TEMPLATE`, and in the config `GITS_TARGETDIR`, `GITS_LIST`. The old names are still read when the new one is not defined; `gits migrate` renames the two variables inside a config.
- **Lifecycle events**: your scripts run between the stages of every command. `GITS_<COMMAND>_<EVENT>`, `GITS_<COMMAND>_ALL`, `GITS_ALL` hold the path of a script, in the environment or in `.git/gits.sh`. `gits events` lists them, `gits events --examples <directory>` writes an example of each. See `LIFECYCLE.md`.
- **`gits add` in a terminal**: shows the found files as a list to tick, with a second box to mark a file as encrypted (`SOURCE:e:TARGET`). `ctrl+enter` writes (also `ctrl+j`, `ctrl+s`).
- **`find ... | gits add [-e]`**: paths of files from stdin, one per line, added without the list.
- **`gits diff`**: ends with the absolute paths of the local files which differ.
- **`gits pull --yes`**: takes the stored config first, so a list changed on another machine is used in the same run.
- **`gits --help`**: lists every env var gits reacts to: its value in the shell, the default, the value in use.
- **`gits isinsync`** without `GITS_SOURCE` exits with 2 (error) instead of 1.
