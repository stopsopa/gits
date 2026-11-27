#
# Runs all tests of gits: unit tests (cargo test) and then every tests/testNNN/test.sh, one after another.
# Exit code 1 when anything failed.
#
# Run it from the root of the repository, after compiling:
#
#   /bin/bash compile.sh
#   /bin/bash test.sh
#
# To run just one test call it directly:
#
#   /bin/bash tests/test003/test.sh
#
# When a new test is added in tests/ add it to the list below too.
#
# test001   --help, --version, GITS_SOURCE is required
# test002   init, diff, isinsync, push
# test003   init (restore from the storage), pull
# test004   state, find, list
# test005   migrate, migrate all, automatic migration
# test006   add
# test007   encrypted elements (SOURCE:e:TARGET) through GITS_ENCRYPTION_SOCKET,
#           with the real encoder process and the ssenc binary of submodules/encrypt
# test008   init with a template, url, move, GITS_SHELL
# test009   --update (slow: compiles gits three times)
# test010   Ctrl+C removes the temporary clone
# test011   tests/encoder/encoder-start.sh, tests/encoder/encoder-stop.sh, the wrapper gits.sh
# test012   lifecycle events: which events every command fires, what a script sees (dumps stay in tests/test012/tmp/dumps/)
# test013   lifecycle events: stopping a command, scripts from the config, the replaceable FIND,
#           the old names of the variables (GITSTORAGE...), gits events
# test014   add in a terminal: the interactive list (which files, which of them encrypted),
#           driven through a pseudo terminal by tests/terminal.py (needs python3)
# test015   GITS_PULL_TO_SYNC: the clone of the storage kept in one directory between the runs
# test016   gits crypt (status, encrypt, decrypt, rekey) and gits without the socket, through the
#           demo examples/encrypt: reset_setup.sh, the wrapper gits.sh, two keys
# test017   gits --env [export]: the env vars which are defined and differ from the default
#

CODE=0

# After every test: the configs left in tests/*/tmp (kept there to look at after a test) are
# renamed: gits.sh -> _gits.sh, gitstorage-config.sh -> _gitstorage-config.sh.
# Without it "gits state" / "gits find" called above this repository (e.g. in the home directory)
# lists them as projects. Every test removes its tmp at the beginning, so nothing depends on them.
function hide_configs {
  local FILE
  while IFS= read -r FILE; do
    if [[ -z "${FILE}" ]]; then
      continue
    fi
    mv -f "${FILE}" "$(dirname "${FILE}")/_$(basename "${FILE}")"
  done <<< "$(find tests -type f \( -name gits.sh -o -name gitstorage-config.sh \) -path '*/tmp/*')"
}

cat <<EEE

=============== cargo test ===============

EEE

cargo test || CODE=1

cat <<EEE

=============== tests/test001/test.sh ===============

EEE

/bin/bash tests/test001/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test002/test.sh ===============

EEE

/bin/bash tests/test002/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test003/test.sh ===============

EEE

/bin/bash tests/test003/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test004/test.sh ===============

EEE

/bin/bash tests/test004/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test005/test.sh ===============

EEE

/bin/bash tests/test005/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test006/test.sh ===============

EEE

/bin/bash tests/test006/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test007/test.sh ===============

EEE

/bin/bash tests/test007/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test008/test.sh ===============

EEE

/bin/bash tests/test008/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test009/test.sh ===============

EEE

/bin/bash tests/test009/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test010/test.sh ===============

EEE

/bin/bash tests/test010/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test011/test.sh ===============

EEE

/bin/bash tests/test011/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test012/test.sh ===============

EEE

/bin/bash tests/test012/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test013/test.sh ===============

EEE

/bin/bash tests/test013/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test014/test.sh ===============

EEE

/bin/bash tests/test014/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test015/test.sh ===============

EEE

/bin/bash tests/test015/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test016/test.sh ===============

EEE

/bin/bash tests/test016/test.sh || CODE=1

hide_configs

cat <<EEE

=============== tests/test017/test.sh ===============

EEE

/bin/bash tests/test017/test.sh || CODE=1

hide_configs

if [[ "${CODE}" = "0" ]]; then
  cat <<EEE

[ OK ] ${0}: all tests passed

EEE
else
  cat <<EEE

[ ERROR ] ${0}: some tests failed, look for "[ ERROR ]" above

EEE
fi

exit "${CODE}"
