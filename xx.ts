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
    /*
    ## The commands

    | Command | When | What it runs |
    |---|---|---|
    | `xx "submodule add"` | once, ever | `git submodule add -b main … encrypt` and `-b master … stopsopa.github.io`; skips any already in `.gitmodules` |
    | `xx "submodule install"` | once per clone | `git submodule update --init --recursive`, plus `git config submodule.recurse true` |
    | `xx "submodule update"` | when you want newer code | `git submodule update --init --remote`, then lists the commits that came in |
    | `xx "submodule status"` | anytime | per submodule: branch, current commit, newest remote commit, how far behind, uncommitted files |

    To get going: run `xx "submodule add"`, then `git add xx.ts && git commit && git push`.

    ## How submodules work

    The parent repo never stores the submodule's files. It stores two things:

    - **`.gitmodules`**: path, URL and branch of each submodule.
    - **A pinned commit**: the exact SHA of each submodule, recorded in the parent's commit.

    The parent always pins a commit; it never follows a branch. The branch in `.gitmodules` is only a hint telling `update --remote` where to look for the newest commit.

    ## How many operations

    Three, plus status:

    1. **Add** (once ever): register the URL and branch, then commit `.gitmodules` and the pin.
    2. **Install** (once per clone): download each submodule at its pinned commit. `git clone --recurse-submodules` does the same in one go.
    3. **Update** (whenever you choose): move the pins to the tip of the tracked branches, then `git add encrypt stopsopa.github.io && git commit` in the parent. Without that commit, nobody else sees the bump.

    Staying on track day to day needs no extra command: with `submodule.recurse true`, a plain `git pull` or `git switch` in the parent also moves the submodules to whatever is pinned.

    ## Things that catch people out

    - **Detached HEAD**: after install or update, a submodule sits on a commit, not a branch. To work inside one, run `git switch main` (or `master`) there first, commit and push there, then commit the new pin in the parent.
    - **Push order**: push the submodule before the parent, otherwise the parent pins a commit nobody else can fetch.
    - **Dirty parent**: `git status` in the parent showing `modified: encrypt (new commits)` just means the submodule is on a different commit than the pin. Either commit it (a bump) or run `xx "submodule install"` to go back to the pin.
    */
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
