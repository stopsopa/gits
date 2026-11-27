use std::ffi::{OsStr, OsString};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;

/**
 * The one place where gits starts other programs (git, the shell reading the config, curl, ...).
 * Rust version of workshop/cli/cli.ts, the same behaviour:
 *
 *  1. the program is started with the arguments as they are, no shell is involved
 *  2. env of the child = env of gits + options.env (None removes a variable),
 *     or only options.env when inherit_env is false
 *  3. working directory of the child = options.pwd (default: the one of gits)
 *  4. stdin of the child is closed (/dev/null)
 *  5. every chunk of stdout / stderr is given to on_stdout / on_stderr while it flows
 *  6. whole stdout and stderr are also collected and returned
 *  7. returns when the program ended and both streams are closed. An exit code other than 0
 *     is NOT an error, the caller looks at `code`
 *  8. Err only when the program could not be started (not found, not executable)
 *
 * Differences to cli.ts: it blocks instead of returning a promise, and the output is bytes,
 * not text (a download is not text, and a chunk may end in the middle of a character):
 * use stdout_text() / stderr_text() for text.
 *
 *   // simple - just wait for the result
 *   let out = cli("git", ["status", "-s"], Options::new().pwd(&repo))?;
 *
 *   // output shown to the user while it flows (and collected too)
 *   cli("git", ["push", "origin", "HEAD"], Options::new().pwd(&repo).forward())?;
 *
 *   // env: added, removed, or nothing inherited
 *   cli("node", ["script.js"], Options::new().env("NODE_ENV", "production"))?;
 *   cli("node", ["script.js"], Options::new().env_remove("NODE_OPTIONS"))?;
 *   cli("node", ["script.js"], Options::new().env("PATH", "/usr/bin").inherit_env(false))?;
 *
 *   // own handling of the chunks
 *   cli("bash", ["deploy.sh"], Options::new().on_stdout(|chunk| seen.extend_from_slice(chunk)))?;
 */
pub fn cli<P, I, S>(program: P, args: I, options: Options) -> io::Result<Output>
where
    P: AsRef<OsStr>,
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let Options {
        env,
        inherit_env,
        pwd,
        mut on_stdout,
        mut on_stderr,
        stdout_into_stderr,
    } = options;

    let mut command = Command::new(program);
    command
        .args(args)
        .stdin(Stdio::null());

    // stdout_into_stderr: the child writes both to ONE pipe, like "2>&1" of a shell. Two pipes
    // are read by two threads, and which chunk comes first would be a matter of luck
    let merged = if stdout_into_stderr {
        let (read, write) = io::pipe()?;
        command.stdout(write.try_clone()?).stderr(write);
        Some(read)
    } else {
        command.stdout(Stdio::piped()).stderr(Stdio::piped());
        None
    };

    if !inherit_env {
        command.env_clear();
    }
    for (name, value) in env {
        match value {
            Some(value) => command.env(name, value),
            None => command.env_remove(name),
        };
    }
    if let Some(pwd) = pwd {
        command.current_dir(pwd);
    }

    let mut child = command.spawn()?;
    // it holds the writing ends of the merged pipe: with them open the pipe would never end
    drop(command);

    // both streams have to be read at the same time (a full pipe of one would block the program),
    // the chunks come to this thread in the order they arrived
    let (sender, receiver) = mpsc::channel::<(Stream, Vec<u8>)>();
    let readers = [
        reader(Stream::Stdout, child.stdout.take(), sender.clone()),
        reader(Stream::Stderr, child.stderr.take(), sender.clone()),
        reader(Stream::Stderr, merged, sender),
    ];

    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    for (stream, chunk) in receiver {
        match stream {
            Stream::Stdout => {
                if let Some(callback) = on_stdout.as_mut() {
                    callback(&chunk);
                }
                stdout.extend_from_slice(&chunk);
            }
            Stream::Stderr => {
                if let Some(callback) = on_stderr.as_mut() {
                    callback(&chunk);
                }
                stderr.extend_from_slice(&chunk);
            }
        }
    }

    for handle in readers.into_iter().flatten() {
        let _ = handle.join();
    }

    let status = child.wait()?;

    Ok(Output {
        code: status.code(),
        signal: signal_of(&status),
        stdout,
        stderr,
    })
}

type Callback<'a> = Box<dyn FnMut(&[u8]) + 'a>;

pub struct Options<'a> {
    // extra env vars on top of the env of gits (unless inherit_env is false), None = removed for the child
    env: Vec<(OsString, Option<OsString>)>,
    // default true - false passes ONLY `env` to the child
    inherit_env: bool,
    // working directory of the child (default: the one of gits)
    pwd: Option<PathBuf>,
    // called with every chunk of stdout as it arrives
    on_stdout: Option<Callback<'a>>,
    // called with every chunk of stderr as it arrives
    on_stderr: Option<Callback<'a>>,
    // stdout of the child is its stderr ("2>&1"): everything arrives as stderr, in the order it was written
    stdout_into_stderr: bool,
}

// env / env_remove / inherit_env: part of the interface (and tested), gits itself has no use for them yet
#[allow(dead_code)]
impl<'a> Options<'a> {
    pub fn new() -> Self {
        Options {
            env: Vec::new(),
            inherit_env: true,
            pwd: None,
            on_stdout: None,
            on_stderr: None,
            stdout_into_stderr: false,
        }
    }

    // what the child prints on stdout goes to its stderr, like "2>&1": one stream, the order kept
    pub fn stdout_into_stderr(mut self) -> Self {
        self.stdout_into_stderr = true;
        self
    }

    pub fn pwd(mut self, pwd: impl AsRef<Path>) -> Self {
        self.pwd = Some(pwd.as_ref().to_path_buf());
        self
    }

    pub fn env(mut self, name: impl AsRef<OsStr>, value: impl AsRef<OsStr>) -> Self {
        self.env.push((
            name.as_ref().to_os_string(),
            Some(value.as_ref().to_os_string()),
        ));
        self
    }

    pub fn env_remove(mut self, name: impl AsRef<OsStr>) -> Self {
        self.env.push((name.as_ref().to_os_string(), None));
        self
    }

    pub fn inherit_env(mut self, inherit: bool) -> Self {
        self.inherit_env = inherit;
        self
    }

    pub fn on_stdout(mut self, callback: impl FnMut(&[u8]) + 'a) -> Self {
        self.on_stdout = Some(Box::new(callback));
        self
    }

    pub fn on_stderr(mut self, callback: impl FnMut(&[u8]) + 'a) -> Self {
        self.on_stderr = Some(Box::new(callback));
        self
    }

    // stdout of the child goes to stdout of gits, while it flows
    pub fn forward_stdout(self) -> Self {
        self.on_stdout(|chunk| {
            let mut out = io::stdout();
            let _ = out.write_all(chunk);
            let _ = out.flush();
        })
    }

    // stderr of the child goes to stderr of gits, while it flows
    pub fn forward_stderr(self) -> Self {
        self.on_stderr(|chunk| {
            let mut err = io::stderr();
            let _ = err.write_all(chunk);
            let _ = err.flush();
        })
    }

    // both: the user sees what the program prints, like when it was started by hand
    pub fn forward(self) -> Self {
        self.forward_stdout().forward_stderr()
    }
}

impl Default for Options<'_> {
    fn default() -> Self {
        Options::new()
    }
}

#[derive(Debug)]
pub struct Output {
    // exit code, None when the program was killed by a signal
    pub code: Option<i32>,
    // signal which killed the program, None when it ended normally
    pub signal: Option<i32>,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

impl Output {
    pub fn success(&self) -> bool {
        self.code == Some(0)
    }

    pub fn stdout_text(&self) -> String {
        String::from_utf8_lossy(&self.stdout).to_string()
    }

    pub fn stderr_text(&self) -> String {
        String::from_utf8_lossy(&self.stderr).to_string()
    }

    // for messages: "exit code 1", "killed by signal 2"
    pub fn status(&self) -> String {
        match (self.code, self.signal) {
            (Some(code), _) => format!("exit code {code}"),
            (None, Some(signal)) => format!("killed by signal {signal}"),
            (None, None) => "ended in unknown way".to_string(),
        }
    }
}

#[derive(Clone, Copy)]
enum Stream {
    Stdout,
    Stderr,
}

fn reader<R: Read + Send + 'static>(
    stream: Stream,
    pipe: Option<R>,
    sender: mpsc::Sender<(Stream, Vec<u8>)>,
) -> Option<thread::JoinHandle<()>> {
    let mut pipe = pipe?;
    Some(thread::spawn(move || {
        let mut buffer = [0u8; 8192];
        loop {
            match pipe.read(&mut buffer) {
                Ok(0) => break,
                Ok(n) => {
                    if sender.send((stream, buffer[..n].to_vec())).is_err() {
                        break;
                    }
                }
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
    }))
}

fn signal_of(status: &std::process::ExitStatus) -> Option<i32> {
    use std::os::unix::process::ExitStatusExt;
    status.signal()
}

// the same cases as workshop/cli/cli.test.ts, with /bin/sh as the program
#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::{Cell, RefCell};
    use std::time::{Duration, Instant};

    fn sh(script: &str, options: Options) -> Output {
        cli("/bin/sh", ["-c", script], options).unwrap()
    }

    #[test]
    fn collects_stdout_and_exit_code_0() {
        let out = sh("printf hello", Options::new());
        assert_eq!(out.code, Some(0));
        assert_eq!(out.signal, None);
        assert_eq!(out.stdout_text(), "hello");
        assert_eq!(out.stderr_text(), "");
        assert!(out.success());
    }

    #[test]
    fn arguments_as_they_are_no_shell() {
        let out = cli("printf", ["%s|", "a b", "$HOME", "*"], Options::new()).unwrap();
        assert_eq!(out.stdout_text(), "a b|$HOME|*|");
    }

    #[test]
    fn stdout_into_stderr_keeps_the_order() {
        // many times: with two pipes the order was a matter of luck
        for _ in 0..50 {
            let out = sh(
                "echo 1; echo 2 >&2; echo 3; echo 4 >&2",
                Options::new().stdout_into_stderr(),
            );
            assert_eq!(out.stdout_text(), "");
            assert_eq!(out.stderr_text(), "1\n2\n3\n4\n");
        }
    }

    #[test]
    fn stdout_and_stderr_separately_to_callbacks() {
        let seen_out = RefCell::new(Vec::new());
        let seen_err = RefCell::new(Vec::new());
        let out = sh(
            "printf out1; printf err1 >&2",
            Options::new()
                .on_stdout(|chunk| seen_out.borrow_mut().extend_from_slice(chunk))
                .on_stderr(|chunk| seen_err.borrow_mut().extend_from_slice(chunk)),
        );
        assert_eq!(seen_out.borrow().as_slice(), b"out1");
        assert_eq!(seen_err.borrow().as_slice(), b"err1");
        assert_eq!(out.stdout_text(), "out1");
        assert_eq!(out.stderr_text(), "err1");
    }

    #[test]
    fn callbacks_get_data_while_the_program_runs() {
        let start = Instant::now();
        let first_at: Cell<Option<Duration>> = Cell::new(None);
        let out = sh(
            "echo first; sleep 0.5; echo second",
            Options::new().on_stdout(|_| {
                if first_at.get().is_none() {
                    first_at.set(Some(start.elapsed()));
                }
            }),
        );
        let total = start.elapsed();
        let first = first_at.get().unwrap();
        assert!(
            total - first >= Duration::from_millis(300),
            "first chunk after {first:?}, the end after {total:?}"
        );
        assert_eq!(out.stdout_text(), "first\nsecond\n");
    }

    #[test]
    fn non_zero_exit_code_is_not_an_error() {
        let out = sh("echo boom >&2; exit 3", Options::new());
        assert_eq!(out.code, Some(3));
        assert_eq!(out.signal, None);
        assert_eq!(out.stderr_text(), "boom\n");
        assert!(!out.success());
        assert_eq!(out.status(), "exit code 3");
    }

    #[test]
    fn env_added_to_the_inherited_one() {
        let out = sh(
            r#"echo "$CLI_TEST_VAR|${PATH:+has-path}""#,
            Options::new().env("CLI_TEST_VAR", "with spaces & $pecial"),
        );
        assert_eq!(out.stdout_text(), "with spaces & $pecial|has-path\n");
    }

    #[test]
    fn env_removed() {
        // HOME, not PATH: a shell started without PATH gives itself a default one
        let out = sh(
            r#"echo "${HOME:-no-home}|${PATH:+has-path}""#,
            Options::new().env_remove("HOME"),
        );
        assert_eq!(out.stdout_text(), "no-home|has-path\n");
    }

    #[test]
    fn only_given_env_when_not_inherited() {
        let out = sh(
            r#"echo "$CLI_TEST_VAR|${HOME:-no-home}""#,
            Options::new()
                .env("CLI_TEST_VAR", "only")
                .inherit_env(false),
        );
        assert_eq!(out.stdout_text(), "only|no-home\n");
    }

    #[test]
    fn pwd_of_the_child() {
        let dir = std::fs::canonicalize(std::env::temp_dir()).unwrap();
        let out = sh("pwd -P", Options::new().pwd(&dir));
        assert_eq!(out.stdout_text().trim_end(), dir.to_str().unwrap());

        let here = std::fs::canonicalize(std::env::current_dir().unwrap()).unwrap();
        let out = sh("pwd -P", Options::new());
        assert_eq!(out.stdout_text().trim_end(), here.to_str().unwrap());
    }

    #[test]
    fn signal_which_killed_the_program() {
        let out = sh("kill -TERM $$", Options::new());
        assert_eq!(out.code, None);
        assert_eq!(out.signal, Some(libc::SIGTERM));
        assert_eq!(out.status(), format!("killed by signal {}", libc::SIGTERM));
    }

    #[test]
    fn error_when_the_program_does_not_exist() {
        let e = cli("/non/existing/program-xyz", [""; 0], Options::new()).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::NotFound);
    }

    #[test]
    fn output_bigger_than_a_pipe_on_both_streams() {
        let out = sh(
            "i=0; while [ $i -lt 20000 ]; do echo 0123456789; echo abcdefghij >&2; i=$((i+1)); done",
            Options::new(),
        );
        assert_eq!(out.stdout.len(), 20000 * 11);
        assert_eq!(out.stderr.len(), 20000 * 11);
    }
}
