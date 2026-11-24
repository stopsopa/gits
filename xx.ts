// github edit  : https://github.com/stopsopa/xx/edit/main/templates/xx.ts

// in order to run any xx command with custom export env var:
// (shopt -s expand_aliases; export ENVFILE=.env.ci; xx "docker up")

// 🚀 -
// ✅ -
// ⚙️  -
// 🗑️  -
// 🛑 -
// to call other xx commands from inside any xx command use:
//    shopt -s expand_aliases && source ~/.bashrc
// after that just do:
//   xx <command_name>
const S = "\\";
const GRAY = "\x1b[38;5;244m",
  BLACK = "\x1b[30m",
  RED = "\x1b[31m",
  GREEN = "\x1b[32m",
  YELLOW = "\x1b[33m",
  BLUE = "\x1b[34m",
  MAGENTA = "\x1b[35m",
  CYAN = "\x1b[36m",
  WHITE = "\x1b[37m",
  BOLD = "\x1b[1m",
  REVERSE = "\x1b[7m",
  RESET = "\x1b[0m";

const enter = `printf '\n${GREEN}Press Enter to continue (any other key exits)...${RESET}\n';old=$(stty -g);stty -icanon -echo
IFS= read -r -n1 k 2>/dev/null||IFS= read -r k;stty "$old"
[ -n "$k" ]&&exit 0;`;

const esc = `printf '\n${GREEN}Press any key to continue (Esc to exit)...${RESET}\n';old=$(stty -g);stty -icanon -echo
IFS= read -r -n1 k 2>/dev/null||IFS= read -r k;stty "$old"
[ "$k" = "$(printf '\\033')" ]&&exit 0;`;

type Command = {
  // shell script, written to xx_generated.sh and executed with /bin/bash
  command: string;
  // shown under the menu for selected row. Default: name of the command
  description?: string;
  // default true: ask "Run command?" before running
  confirm?: boolean;
  // default false. true = run in the current shell (source) instead of /bin/bash
  source?: boolean;
  // lower goes first. Missing means 0, so negative = top, positive = bottom
  order?: number;
};

type Commands = Record<string, Command>;

type Ctx = {
  // arguments given after the name of the command: xx <name> [args]
  args: string[];
  // directory xx was called in
  cwd: string;
  // path of this file
  configPath: string;
};

export default (setup: Commands, ctx: Ctx): Commands => {
  return {
    help: {
      command: `
set -e

cat <<EEE

  🐙 GitHub: $(git ls-remote --get-url origin | awk '{\$1=\$1};1' | tr -d '\\n' | sed -E 's/git@github\\.com:([^/]+)\\/(.+)\\.git/https:\\/\\/github.com\\/\\1\\/\\2/g')

  Meta repository: other repositories mounted here as git submodules.

    directory            repository                                        tracked branch
    encrypt              git@github.com:stopsopa/encrypt.git               main
    stopsopa.github.io   git@github.com:stopsopa/stopsopa.github.io.git    master

  This repository does not store the files of the submodules, only (in .gitmodules)
  their url + branch and (in the commit) the exact commit each of them is pinned to.

  xx "submodule add"       once, ever        register the submodules and commit the result
  xx "submodule install"   once per clone    download the submodules at the pinned commits
  xx "submodule update"    when you want     move the pins to the newest commit of the tracked branches
  xx "submodule status"    anytime           where the pins are and how far behind the branches

EEE
`,
      description: `what is this repository and how to work with its submodules`,
      source: false,
      confirm: false,
    },
    [`submodule add`]: {
      command: `
set -e

if git config -f .gitmodules --get submodule.encrypt.url > /dev/null 2>&1; then
  echo "encrypt: already registered in .gitmodules, skipping"
else
  git submodule add -b main git@github.com:stopsopa/encrypt.git encrypt
fi

if git config -f .gitmodules --get submodule.stopsopa.github.io.url > /dev/null 2>&1; then
  echo "stopsopa.github.io: already registered in .gitmodules, skipping"
else
  git submodule add -b master git@github.com:stopsopa/stopsopa.github.io.git stopsopa.github.io
fi

echo ""
git submodule status

cat <<EEE

.gitmodules and the pinned commits are staged. To finish, commit them:

    git commit -m "add submodules"
    git push

EEE
`,
      description: `one time: register encrypt (main) and stopsopa.github.io (master) as submodules. Safe to run again`,
    },
    [`submodule install`]: {
      command: `
set -e

# from now on git pull / checkout / switch in this repository also move the submodules to the pinned commits
git config submodule.recurse true

git submodule update --init --recursive

echo ""
git submodule status
`,
      description: `after a fresh clone: download all submodules at the commits pinned by this repository`,
      confirm: false,
    },
    [`submodule update`]: {
      command: `
set -e

git submodule update --init --remote

echo ""
git submodule status
echo ""
git --no-pager diff --submodule=log

cat <<EEE

If commits are listed above, the pins moved. Record that in this repository:

    git add encrypt stopsopa.github.io
    git commit -m "bump submodules"
    git push

EEE
`,
      description: `move every submodule to the newest commit of its tracked branch (branch is in .gitmodules). Commit afterwards`,
    },
    [`submodule status`]: {
      command: `
set -e

git submodule status
echo ""

git submodule foreach --quiet '
branch="\$(git config -f "\$toplevel/.gitmodules" --get "submodule.\$name.branch")"
git fetch --quiet origin "\$branch"
echo "\$name"
echo "  branch      : \$(git symbolic-ref --short -q HEAD || echo "detached HEAD")"
echo "  here        : \$(git log -1 --format="%h %cs %s" HEAD)"
echo "  newest      : \$(git log -1 --format="%h %cs %s" "origin/\$branch")  (origin/\$branch)"
echo "  behind by   : \$(git rev-list --count "HEAD..origin/\$branch") commit(s)"
echo "  uncommitted : \$(git status --porcelain | wc -l | tr -d " ") file(s)"
echo ""
'
`,
      description: `pinned commit of every submodule and how far it is behind its tracked branch (fetches)`,
      confirm: false,
    },
    ...setup,
  };
};
