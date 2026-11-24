/**
 * Tests for lib/cli.ts using native node test runner.
 *
 * Uses process.execPath (current node binary) as the spawned program
 * so tests don't depend on any external tools.
 *
 * Fixture programs in lib/cli.fixtures/ (emit.sh - bash, emit.ts - node with native type stripping)
 * simulate a real slow program: delayed stdout/stderr, env var, pwd and exit code.
 *
 * Run:
 *   node --test lib/cli.test.ts
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cli, type CliOptions } from "./cli.ts";

const node = process.execPath;

const fixturesDir = join(import.meta.dirname, "cli.fixtures");

/**
 * Strip debugger-related vars (e.g. VS Code auto attach) so child node processes
 * don't print "Debugger listening..." into stderr and don't slow down startup.
 * undefined value = var removed from child env.
 */
const noDebug: CliOptions["env"] = {
  NODE_OPTIONS: undefined,
  VSCODE_INSPECTOR_OPTIONS: undefined,
};

test("collects stdout and resolves with exit code 0", async () => {
  const result = await cli(node, ["-e", "process.stdout.write('hello')"], { env: noDebug });

  assert.equal(result.code, 0);
  assert.equal(result.signal, null);
  assert.equal(result.stdout, "hello");
  assert.equal(result.stderr, "");
});

test("passes arguments as-is (no shell interpretation)", async () => {
  const result = await cli(node, ["-e", "console.log(JSON.stringify(process.argv.slice(1)))", "a b", "$HOME", "*"]);

  assert.deepEqual(JSON.parse(result.stdout), ["a b", "$HOME", "*"]);
});

test("streams stdout and stderr separately to callbacks", async () => {
  const outChunks: string[] = [];
  const errChunks: string[] = [];

  const result = await cli(node, ["-e", "process.stdout.write('out1'); process.stderr.write('err1');"], {
    env: noDebug,
    onStdout: (chunk) => outChunks.push(chunk),
    onStderr: (chunk) => errChunks.push(chunk),
  });

  assert.equal(outChunks.join(""), "out1");
  assert.equal(errChunks.join(""), "err1");
  assert.equal(result.stdout, "out1");
  assert.equal(result.stderr, "err1");
});

test("callbacks receive data before process exits", async () => {
  const events: string[] = [];
  let settled = false;
  let settledWhenFirstChunk: boolean | undefined;

  // print, wait, print again - first chunk must arrive while promise is still pending
  const script = "console.log('first'); setTimeout(() => console.log('second'), 300);";

  const promise = cli(node, ["-e", script], {
    env: noDebug,
    onStdout: (chunk) => {
      settledWhenFirstChunk ??= settled;
      events.push(chunk.trim());
    },
  }).finally(() => {
    settled = true;
  });

  await promise;

  assert.equal(settledWhenFirstChunk, false);
  assert.deepEqual(events, ["first", "second"]);
});

/**
 * Same scenario against both fixture programs (bash and node/ts):
 * slow stdout/stderr + injected env var + pwd + exit code, all captured in one call.
 */
const fixtures: { name: string; program: string; args: string[] }[] = [
  { name: "bash emit.sh", program: "bash", args: [join(fixturesDir, "emit.sh")] },
  { name: "node emit.ts", program: node, args: [join(fixturesDir, "emit.ts")] },
];

for (const fixture of fixtures) {
  test(`${fixture.name}: slow stdout/stderr streamed, env + pwd seen by child, exit code captured`, async () => {
    // realpath because on macOS tmpdir is a symlink (/var -> /private/var)
    const dir = realpathSync(tmpdir());
    const start = Date.now();

    const outChunks: { text: string; at: number }[] = [];
    const errChunks: string[] = [];

    let settled = false;
    let settledWhenFirstChunk: boolean | undefined;

    // 3 lines, 0.2s apart, exit code 5
    const result = await cli(fixture.program, [...fixture.args, "3", "0.2", "5"], {
      env: { ...noDebug, CLI_FIXTURE_VAR: "with spaces & $pecial" },
      pwd: dir,
      onStdout: (chunk) => {
        settledWhenFirstChunk ??= settled;
        outChunks.push({ text: chunk, at: Date.now() - start });
      },
      onStderr: (chunk) => errChunks.push(chunk),
    }).finally(() => {
      settled = true;
    });

    // output was streaming while process was still running
    assert.equal(settledWhenFirstChunk, false);

    // chunks spread in time (not all delivered at once at the end)
    const firstAt = outChunks.find((c) => c.text.includes("out1"))?.at ?? -1;
    const lastAt = outChunks.find((c) => c.text.includes("out3"))?.at ?? -1;
    assert.ok(lastAt - firstAt >= 300, `chunks not spread in time: ${JSON.stringify(outChunks)}`);

    // full stdout: lines + env var seen by child + its working directory
    assert.equal(result.stdout, `out1\nout2\nout3\nenv:with spaces & $pecial\npwd:${dir}\n`);
    assert.equal(outChunks.map((c) => c.text).join(""), result.stdout);

    // stderr kept separately
    assert.equal(result.stderr, "err1\nerr2\nerr3\n");
    assert.equal(errChunks.join(""), result.stderr);

    // exit code captured in the same call
    assert.equal(result.code, 5);
    assert.equal(result.signal, null);
  });

  test(`${fixture.name}: exit code 0 and default pwd`, async () => {
    const result = await cli(fixture.program, [...fixture.args, "1", "0", "0"], { env: noDebug });

    assert.equal(result.code, 0);
    assert.equal(result.stdout, `out1\nenv:\npwd:${realpathSync(process.cwd())}\n`);
    assert.equal(result.stderr, "err1\n");
  });
}

test("resolves (not rejects) on non-zero exit code", async () => {
  const result = await cli(node, ["-e", "console.error('boom'); process.exit(3)"], { env: noDebug });

  assert.equal(result.code, 3);
  assert.equal(result.stderr.trim(), "boom");
});

test("injects env vars merged with process.env", async () => {
  const result = await cli(node, ["-e", "console.log(process.env.CLI_TEST_VAR + '|' + (process.env.PATH ? 'has-path' : 'no-path'))"], {
    env: { CLI_TEST_VAR: "injected" },
  });

  assert.equal(result.stdout.trim(), "injected|has-path");
});

test("inheritEnv: false passes only given env", async () => {
  const result = await cli(node, ["-e", "console.log(process.env.CLI_TEST_VAR + '|' + (process.env.PATH ? 'has-path' : 'no-path'))"], {
    env: { CLI_TEST_VAR: "only" },
    inheritEnv: false,
  });

  assert.equal(result.stdout.trim(), "only|no-path");
});

test("reports signal when process is killed", async () => {
  const result = await cli(node, ["-e", "process.kill(process.pid, 'SIGTERM')"]);

  assert.equal(result.code, null);
  assert.equal(result.signal, "SIGTERM");
});

test("rejects when program does not exist", async () => {
  await assert.rejects(cli("/non/existing/program-xyz", []), { code: "ENOENT" });
});
