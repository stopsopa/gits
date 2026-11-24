create PLAN.md for tool submodules/stopsopa.github.io/gitstorage.sh what does it do. Like you would prepare it for AI to create it from scratch

focus not on implementation but on what does it do.

And I will also provide explanation what does it do right here. And just consolidate it.

The purpose of this tool is to have command `gits state` which list like this

(first of all when this program is executed it always checks if env var GITSTORAGESOURCE=git@github.com:stopsopa/gitstorage.git exist and is not empty, that will become important later. If not defined or empty program stops with clear error. This env var have to be defined for this command to work)

(we will have to have here some more env vars for dealing with encryption, but I will have to figure out that later)

```


~/Workspace szdz √ gits state
====================================================================================================================











====================================================================================================================
_TARGETGITDIR: /Users/szdz/Workspace/cb48
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 1 : 10 >./bible/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/bible"
  gits diff

cloning directory '/Users/szdz/Workspace/cb48/git@github.com:stopsopa__gitstorage.git' for './bible/.git/gitstorage-config.sh'
Cloning into '.'...
remote: Enumerating objects: 9220, done.
remote: Counting objects: 100% (538/538), done.
remote: Compressing objects: 100% (211/211), done.
remote: Total 9220 (delta 418), reused 366 (delta 273), pack-reused 8682 (from 3)
Receiving objects: 100% (9220/9220), 1.85 MiB | 2.76 MiB/s, done.
Resolving deltas: 100% (5674/5674), done.
cloned..
before checkout vvv
Updated 0 paths from the index
after checkout ^^^
    files are in sync
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 2 : 10 >./SPECIAL_storage/SPECIAL_storage/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/SPECIAL_storage/SPECIAL_storage"
  gits diff

all good IntelliJIdea2022.1
directory '/Users/szdz/Workspace/cb48/git@github.com:stopsopa__gitstorage.git' for './SPECIAL_storage/SPECIAL_storage/.git/gitstorage-config.sh' already exist
before checkout vvv
Updated 0 paths from the index
after checkout ^^^
    files are not in sync
On branch master
Your branch is up to date with 'origin/master'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
  modified:   git@github.com:stopsopa__gitstorage.git/szm114/Workspace/pull.sh
  modified:   git@github.com:stopsopa__gitstorage.git/szm114_root/.claude/settings.json

no changes added to commit (use "git add" and/or "git commit -a")
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 3 : 10 >./SPECIAL_web/SPECIAL_web/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/SPECIAL_web/SPECIAL_web"
  gits diff

directory '/Users/szdz/Workspace/cb48/git@github.com:stopsopa__gitstorage.git' for './SPECIAL_web/SPECIAL_web/.git/gitstorage-config.sh' already exist
before checkout vvv
Updated 2 paths from the index
after checkout ^^^
    files are in sync
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 4 : 10 >./STOPSOPA__checkout-kata/STOPSOPA__checkout-kata/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/STOPSOPA__checkout-kata/STOPSOPA__checkout-kata"
  gits diff

directory '/Users/szdz/Workspace/cb48/git@github.com:stopsopa__gitstorage.git' for './STOPSOPA__checkout-kata/STOPSOPA__checkout-kata/.git/gitstorage-config.sh' already exist
before checkout vvv
Updated 0 paths from the index
after checkout ^^^
    files are in sync
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 5 : 10 >./STOPSOPA__gphotos-research/STOPSOPA__gphotos-research/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/STOPSOPA__gphotos-research/STOPSOPA__gphotos-research"
  gits diff

directory '/Users/szdz/Workspace/cb48/git@github.com:stopsopa__gitstorage.git' for './STOPSOPA__gphotos-research/STOPSOPA__gphotos-research/.git/gitstorage-config.sh' already exist
before checkout vvv
Updated 0 paths from the index
after checkout ^^^
    files are in sync
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 6 : 10 >./STOPSOPA__nearform/STOPSOPA__nearform/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/STOPSOPA__nearform/STOPSOPA__nearform"
  gits diff

directory '/Users/szdz/Workspace/cb48/git@github.com:stopsopa__gitstorage.git' for './STOPSOPA__nearform/STOPSOPA__nearform/.git/gitstorage-config.sh' already exist
before checkout vvv
Updated 0 paths from the index
after checkout ^^^
    files are in sync
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 7 : 10 >./STOPSOPA__os-browser-bridge/STOPSOPA__os-browser-bridge/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/STOPSOPA__os-browser-bridge/STOPSOPA__os-browser-bridge"
  gits diff

directory '/Users/szdz/Workspace/cb48/git@github.com:stopsopa__gitstorage.git' for './STOPSOPA__os-browser-bridge/STOPSOPA__os-browser-bridge/.git/gitstorage-config.sh' already exist
before checkout vvv
Updated 0 paths from the index
after checkout ^^^
    files are in sync
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 8 : 10 >./STOPSOPA__roles/STOPSOPA__roles/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/STOPSOPA__roles/STOPSOPA__roles"
  gits diff

directory '/Users/szdz/Workspace/cb48/git@github.com:stopsopa__gitstorage.git' for './STOPSOPA__roles/STOPSOPA__roles/.git/gitstorage-config.sh' already exist
before checkout vvv
Updated 0 paths from the index
after checkout ^^^
    files are in sync
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 9 : 10 >./STOPSOPA__telazekah/STOPSOPA__telazekah/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/STOPSOPA__telazekah/STOPSOPA__telazekah"
  gits diff

directory '/Users/szdz/Workspace/cb48/git@github.com:stopsopa__gitstorage.git' for './STOPSOPA__telazekah/STOPSOPA__telazekah/.git/gitstorage-config.sh' already exist
before checkout vvv
Updated 0 paths from the index
after checkout ^^^
    files are in sync
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 10 : 10 >./STOPSOPA__tsdi-lite/STOPSOPA__tsdi-lite/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/STOPSOPA__tsdi-lite/STOPSOPA__tsdi-lite"
  gits diff

directory '/Users/szdz/Workspace/cb48/git@github.com:stopsopa__gitstorage.git' for './STOPSOPA__tsdi-lite/STOPSOPA__tsdi-lite/.git/gitstorage-config.sh' already exist
before checkout vvv
Updated 0 paths from the index
after checkout ^^^
    files are in sync

COUNT_SUCCESS : 9
COUNT_ERROR   : 1


gitstorage.sh cleaning /Users/szdz/Workspace/cb48


```

as  you can see it finds all directories with ... good question. you have to find the `find` command which is executed and document it under description of that command..

well generally it finds all directories in pwd (recursive)  which have config which this script can handle. and presents some information but most importantly header like

```



>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 2 : 10 >./SPECIAL_storage/SPECIAL_storage/.git/gitstorage-config.sh<

  cd "/Users/szdz/Workspace/SPECIAL_storage/SPECIAL_storage"
  gits diff


```

here is delimiter header, separating each separate found directory in the report with 2 of 10 and so on for each

and most important

 cd "/Users/szdz/Workspace/SPECIAL_storage/SPECIAL_storage"
  gits diff

and I take that cd [directory] and gits diff and paste it as is in other terminal

that moves me to that directory and executes gits diff


`gits diff` is another important command from this tool

document it..

Executing it present stdout like this:
which is really git diff. What git diff ? I will explain in a moment.

```


~ szdz √   cd "/Users/szdz/Workspace/SPECIAL_storage/SPECIAL_storage"
  gits diff

all good IntelliJIdea2022.1
_TARGETGITDIR: /Users/szdz/Workspace/SPECIAL_storage/SPECIAL_storage/97da
Cloning into '.'...
remote: Enumerating objects: 9220, done.
remote: Counting objects: 100% (538/538), done.
remote: Compressing objects: 100% (211/211), done.
remote: Total 9220 (delta 418), reused 366 (delta 273), pack-reused 8682 (from 3)
Receiving objects: 100% (9220/9220), 1.85 MiB | 2.45 MiB/s, done.
Resolving deltas: 100% (5674/5674), done.
/Users/szdz/Workspace/SPECIAL_storage/SPECIAL_storage/97da

    files are not in sync

diff --git a/git@github.com:stopsopa__gitstorage.git/szm114/Workspace/pull.sh b/git@github.com:stopsopa__gitstorage.git/szm114/Workspace/pull.sh
index 9aad023..693d2de 100644
--- a/git@github.com:stopsopa__gitstorage.git/szm114/Workspace/pull.sh
+++ b/git@github.com:stopsopa__gitstorage.git/szm114/Workspace/pull.sh
@@ -377,6 +377,8 @@ clone git@github.com:stopsopa/securenv.git stopsopa

 clone git@github.com:stopsopa/citybank.git stopsopa

-clone git@github.com:Citi/coding-workshop-participant.git stopsopa
+clone git@github.com:Citi/coding-workshop-participant.git stopsopa
+
+clone git@github.com:stopsopa/gits.git stopsopa

 # unset STOP_NVM_CMD
diff --git a/git@github.com:stopsopa__gitstorage.git/szm114_root/.claude/settings.json b/git@github.com:stopsopa__gitstorage.git/szm114_root/.claude/settings.json
index eec2616..4eddb19 100644
--- a/git@github.com:stopsopa__gitstorage.git/szm114_root/.claude/settings.json
+++ b/git@github.com:stopsopa__gitstorage.git/szm114_root/.claude/settings.json
@@ -35,6 +35,11 @@
   "enabledPlugins": {
     "swift-lsp@claude-plugins-official": true
   },
+  "modelSettings": {
+    "claude-fable-5-2": {
+      "effortLevel": "high"
+    }
+  },
   "theme": "auto",
   "comment": "to select sounds run /bin/bash pages/ai/harness/sounds/sounds.sh from stopsopa.github.io from terminal"
 }
On branch master
Your branch is up to date with 'origin/master'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
    modified:   szm114/Workspace/pull.sh
    modified:   szm114_root/.claude/settings.json

no changes added to commit (use "git add" and/or "git commit -a")
final url https://github.com/stopsopa/gitstorage/tree/master/git@github.com:stopsopa__gitstorage.git

gitstorage.sh cleaning /Users/szdz/Workspace/SPECIAL_storage/SPECIAL_storage/97da


```


but generally what this command is doing is looking in that directory for file in location

.git/gitstorage-config.sh

and once found, and usually it is found because we wouldn't be here if not `gits state`

then it tries to determine random name for directory which doesn't exist and creates it. and then enters it and clones

repository to it from GITSTORAGESOURCE=git@github.com:stopsopa/gitstorage.git (whatever repostiory os specified here)

then it looks for directory in that random directory. It looks for directory which is specified in GITSTORAGETARGETDIR.

and this is where magic starts:

then it looks into list GITSTORAGELIST and you have to think about it as key value list:
left side (let's call this side SOURCE) is path which have to resolved from pwd (we expand ~ to current user directory if present) and right side (let's call it TARGET) is path in repository GITSTORAGESOURCE. That's why we have paths like  "~/.zshrc::$GITSTORAGETARGETDIR/.zshrc", because we don't want to repeat name of directory.

so we define that directory specific to this directory we are in once and reuse it for each element on the list using that variable.

(btw that variable value is derrived from current git repository remote origin. Remote origin is transformed in specific way - find it in the code of submodules/stopsopa.github.io/gitstorage.sh and downstream)


so script iterates over that list and copies all SOURCES to TARGETS. and then generates git diff -> which is the diff which is visible in the snapshot presented above from `gits diff` (then after that command is finished then bash trap kicks in and entire random directory is removed - so everything is every ephemeral, we clone and swap files just to show diff and removing directory)

That allows user to inspect what has changed from last commit.

Then there is another command: `gits push --yes`

(I use --yes to make distinction from git push --force, to don't mistake these two by accident, there is the same reasoning for gits pull --yes)

so gits push --yes actually pushes all changes to GITSTORAGESOURCE.

There is also gits pull --yes - which obviously do the oposite -> it pulls repository to temporary directory

then copies all TARGET to SOURCE then then removes random directory.

There is also another command `gits init` which generates .git/gitstorage-config.sh and entire content is pulled from particular place online. I don't care about it. we will pull in our new implementation whatever is specified in env var GITSTORAGETEMPLATE but we will update GITSTORAGETARGETDIR in it with our new value derrived from git remote origin.

So as you can see our implementation have to be able to deal with config files like doc/gitstorage-config.sh which are in shell script format. 

So in order to execute these we have to execute them from PWD using shell specified in env var GITSTORAGETESHELL="/bin/bash" which by default will be /bin/bash but that value wins only when GITSTORAGETESHELL is not defined.

We also have --help page (btw --help page should also present current found values from env vars this script looks for, and default values, and final value wchich wins - present that in the form of a table)

(--help page shouldn't fail when GITSTORAGESOURCE is not defined but it should mark it in red as problematic for running other commands - because that value is required)

# current help page

```

/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh isinsync
/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh diff
/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh pull
/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh push
/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh url
/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh move git@xxx:project/source-repo.git git@yyy/target-repo.git
/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh init
  # generate gitstorage-config.sh for the first time for given directory (dir have to contain .git)

/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh add [file|directory]
  # register files from path in gitstorage-config.sh

/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh lock [file|directory]
  # add files given by path to .git/xxlockdir and register in gitstorage-config.sh

/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh -c "gitstorage-config.sh"
  # you can specify different config

/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh state
  # will look for each  anywhere in current PWD and check if files pointed by it are up to date

/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh existing
  # will look for all .git directories and try to determine if there is gitstorage-config.sh for it
  # if yes then it will pull it with all tools around it

/bin/bash /Users/szdz/Workspace/SPECIAL_web/SPECIAL_web/gitstorage.sh clean
  # will look for all gitstorage-config.sh and remove them in current PWD
```

as you can see we have some more commands: in new implementation we will only focus on some of the:

`gits isinsync` which will do pretty much most of the same operations as `gits diff` but what it will only produce is exit code: exit 0 when all is in sync for this directory. and exit 1 when it is not in sync.

`gits url` should just determine url (for user to click on it with ctrl to open in the browser) by combining GITSTORAGESOURCE and GITSTORAGETARGETDIR from .git/gitstorage-config.sh and process it to produce github url

it would be nice to also have `gits add [dir/file]` which would add files specified by `[dir/file]` to our local .git/gitstorage-config.sh. Obvously that command have to be executed like all of them (except `gits state`) in the directory where .git/gitstorage-config.sh exist in pwd. but important is that gits add [dir/file] will only add to config, it will not do anything else. This gives user chance to review it.

It would be nice to also hwave command `gits find` which would execute that magical `find` cli command to find all directories with .git/gitstorage-config.sh and list relative paths from pwd to these directories. This way we could use that list for some extra maintenance commands I write later in bash - but don't worry about these commands, just implement gits find.

it would be nice to have `move git@xxx:project/source-repo.git git@yyy/target-repo.git` which would generate procedure on stdout to migrate given directory to different directory... That is useful when we want to change remote origin for given directory, and have in our GITSTORAGESOURCE directory which match naturally to our new 

That's all; we don't care about `gits lock` and `gits -c [different config]` and `gits existing` and `git clean` we just don't look into them and we will not move these to new implementation.






