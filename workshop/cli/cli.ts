/**
 * Small wrapper around child_process.spawn.
 *
 * Runs a program with arguments (no shell involved - args are passed as-is),
 * lets caller listen to stdout and stderr separately while they flow,
 * and resolves promise once the process exits and its streams are closed.
 *
 * Steps:
 *  1. spawn program with args, env = process.env merged with options.env
 *  2. forward every stdout/stderr chunk to options.onStdout / options.onStderr
 *  3. also collect whole stdout/stderr into strings
 *  4. resolve { code, signal, stdout, stderr } on 'close' (non-zero code does NOT reject)
 *  5. reject only when process could not be started (e.g. ENOENT - program not found)
 *
 * Examples:
 *
 *   import { cli } from "./cli.ts";
 *
 *   // simple - just wait for result
 *   const { code, stdout } = await cli("ls", ["-la", "/tmp"]);
 *
 *   // stream output live as it flows
 *   await cli("bash", ["-c", "echo out; echo err >&2"], {
 *     onStdout: (chunk) => process.stdout.write(chunk),
 *     onStderr: (chunk) => process.stderr.write(chunk),
 *   });
 *
 *   // inject env vars (merged on top of process.env)
 *   await cli("node", ["script.js"], { env: { NODE_ENV: "production" } });
 *
 *   // remove inherited env var from child (undefined value = not passed)
 *   await cli("node", ["script.js"], { env: { NODE_OPTIONS: undefined } });
 *
 *   // run with ONLY given env vars (process.env not inherited)
 *   await cli("node", ["script.js"], { env: { PATH: "/usr/bin" }, inheritEnv: false });
 *
 *   // run in different directory (working directory of the child process)
 *   await cli("git", ["status"], { pwd: "/some/repo" });
 *
 *   // everything together
 *   const { code } = await cli("bash", ["deploy.sh"], {
 *     pwd: "/some/repo",
 *     env: { STAGE: "prod" },
 *     onStdout: (chunk) => process.stdout.write(chunk),
 *   });
 */

import { spawn } from "node:child_process";

export type CliOptions = {
  // extra env vars, merged on top of process.env (unless inheritEnv: false)
  env?: Record<string, string | undefined>;
  // default true - set false to pass ONLY options.env to the child
  inheritEnv?: boolean;
  // working directory for the child process (default: current process.cwd())
  pwd?: string;
  // called with every stdout chunk as it arrives
  onStdout?: (chunk: string) => void;
  // called with every stderr chunk as it arrives
  onStderr?: (chunk: string) => void;
};

export type CliResult = {
  // exit code, null if process was killed by signal
  code: number | null;
  // signal which killed the process, null if exited normally
  signal: NodeJS.Signals | null;
  stdout: string;
  stderr: string;
};

export function cli(program: string, args: string[] = [], options: CliOptions = {}): Promise<CliResult> {
  const { env = {}, inheritEnv = true, pwd, onStdout, onStderr } = options;

  return new Promise((resolve, reject) => {
    const child = spawn(program, args, {
      cwd: pwd,
      env: inheritEnv ? { ...process.env, ...env } : env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");

    child.stdout.on("data", (chunk: string) => {
      stdout += chunk;
      onStdout?.(chunk);
    });

    child.stderr.on("data", (chunk: string) => {
      stderr += chunk;
      onStderr?.(chunk);
    });

    // 'error' fires when process couldn't be spawned (or killed failed)
    child.on("error", reject);

    // 'close' (not 'exit') - guarantees stdout/stderr were fully flushed
    child.on("close", (code, signal) => {
      resolve({ code, signal, stdout, stderr });
    });
  });
}
