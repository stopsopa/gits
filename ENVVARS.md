GITS_SOURCE=git@github.com:stopsopa/gitstorage.git
    defined in the ~/.bashrc or ~/.zshrc
    (was: GITSTORAGESOURCE)

GITS_TARGETDIR="git@github.com:stopsopa__gitstorage.git"
    # normally exist in .git/gits.sh, together with GITS_LIST
    (was: GITSTORAGETARGETDIR, GITSTORAGELIST, in .git/gitstorage-config.sh)

GITS_TEMPLATE="https://"
    (was: GITSTORAGETEMPLATE)

GITS_SHELL="/bin/bash"
    (was: GITSTORAGETESHELL)

GITS_ENCRYPTION_SOCKET=""
    (was: GITSTORAGETENCRYPTIONSOCKET)

GITS_<COMMAND>_<EVENT>="~/.gits/events/script.sh"
GITS_<COMMAND>_ALL="~/.gits/events/script.sh"
GITS_ALL="~/.gits/events/script.sh"
    lifecycle scripts, in the environment or in .git/gits.sh
    see LIFECYCLE.md, list of all of them: gits events

GITS_EXIT="~/.gits/events/exit.sh"
    script which runs as the last thing of every start of gits, however it ends
    (like trap EXIT of a shell), only from the environment. See LIFECYCLE.md

All of the above are given to every lifecycle script (the first five with the values gits uses),
together with GITS_EVENT_* - see LIFECYCLE.md, chapter Reference.

The old names (GITSTORAGE...) are still read when the new one is not defined.

The full list of what gits reacts to, with the value of each in your shell, its default and
the value gits ends up using: gits --help
