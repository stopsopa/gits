/**
 * Test fixture for lib/cli.test.ts - node.js twin of emit.sh.
 * Uses TypeScript syntax on purpose - run with native node type stripping (node 22.18+ / 23.6+).
 *
 * Steps:
 *   1. prints N lines to stdout (outN) and stderr (errN), waiting DELAY seconds between them
 *   2. prints value of env var CLI_FIXTURE_VAR as "env:<value>"
 *   3. prints its working directory as "pwd:<dir>"
 *   4. exits with given exit code
 *
 * Arguments (all optional):
 *   1 - number of lines        (default 3)
 *   2 - delay in seconds       (default 0.2, fractions allowed)
 *   3 - exit code              (default 0)
 *
 * Examples:
 *   node lib/cli.fixtures/emit.ts
 *     // out1..out3 + err1..err3, 0.2s apart, env:, pwd:<current dir>, exit 0
 *
 *   CLI_FIXTURE_VAR=hello node lib/cli.fixtures/emit.ts 2 0.5 7
 *     // out1, out2 (0.5s apart), env:hello, pwd:<current dir>, exit 7
 */

const linesCount: number = Number(process.argv[2] ?? 3);
const delayMs: number = Number(process.argv[3] ?? 0.2) * 1000;
const exitCode: number = Number(process.argv[4] ?? 0);

/**
 * Emits line i, then schedules next one after delay.
 * Timers instead of top-level await - no ESM syntax, so node doesn't print
 * "module type not specified" warning into stderr when package.json lacks "type".
 */
function emit(i: number): void {
  process.stdout.write(`out${i}\n`);
  process.stderr.write(`err${i}\n`);

  if (i < linesCount) {
    setTimeout(() => emit(i + 1), delayMs);
  }
  else {
    process.stdout.write(`env:${process.env.CLI_FIXTURE_VAR ?? ""}\n`);
    process.stdout.write(`pwd:${process.cwd()}\n`);

    // exitCode instead of process.exit() - lets stdout/stderr flush before exiting
    process.exitCode = exitCode;
  }
}

emit(1);
