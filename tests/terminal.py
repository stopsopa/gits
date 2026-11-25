"""
Runs a program in a pseudo terminal and presses keys in it: the way to test the interactive
list of "gits add" (src/menu.rs), which shows up only when stdin and stdout are a terminal.

    python3 tests/terminal.py "<keys>" <program> [arguments...]

    python3 tests/terminal.py "DOWN SPACE RIGHT CTRL_ENTER" bin/darwin-arm64/gits add dir

<keys>: names separated by spaces, pressed one after another once the program has drawn
its first screen:

    UP DOWN LEFT RIGHT HOME END PGUP PGDN SPACE ESC
    ENTER         what Enter sends (\\r)
    CTRL_ENTER    what a terminal with the kitty keyboard protocol sends for ctrl+enter
    CTRL_ENTER_X  the same from a terminal with modifyOtherKeys (xterm)
    CTRL_J CTRL_S CTRL_C
    anything else is typed as it is: a n i A N I q

Prints nothing of what the program draws (a screen full of escape sequences) besides what it
printed after it left the alternate screen, then exits with the exit code of the program.
With SCREEN=1 in the environment the last drawn screen is printed too, without colors.

The terminal is 80 x 24. Needs only python3, no modules to install. Not used by gits itself.
"""

import fcntl
import os
import pty
import re
import select
import struct
import sys
import termios
import time

KEYS = {
    "UP": b"\x1b[A",
    "DOWN": b"\x1b[B",
    "RIGHT": b"\x1b[C",
    "LEFT": b"\x1b[D",
    "HOME": b"\x1b[H",
    "END": b"\x1b[F",
    "PGUP": b"\x1b[5~",
    "PGDN": b"\x1b[6~",
    "SPACE": b" ",
    "ESC": b"\x1b",
    "ENTER": b"\r",
    "CTRL_ENTER": b"\x1b[13;5u",
    "CTRL_ENTER_X": b"\x1b[27;5;13~",
    "CTRL_J": b"\n",
    "CTRL_S": b"\x13",
    "CTRL_C": b"\x03",
}


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        sys.exit(1)

    keys = sys.argv[1].split()
    command = sys.argv[2:]

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(command[0], command)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))

    output = b""

    def read(seconds):
        nonlocal output
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if fd in ready:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    return False
                if not chunk:
                    return False
                output += chunk
        return True

    # the first screen: its last line is the help about q / esc
    alive = True
    started = time.time()
    while alive and b"nothing is written" not in output and time.time() - started < 10:
        alive = read(0.05)

    for key in keys:
        if not alive:
            break
        try:
            os.write(fd, KEYS.get(key, key.encode()))
        except OSError:
            break
        # longer than the 0.1 s after which a lone Esc is taken as the key Esc
        alive = read(0.25)

    # a program which is still there after all the keys: it would wait for ever
    started = time.time()
    while alive and time.time() - started < 5:
        alive = read(0.05)
    if alive:
        os.kill(pid, 9)

    _, status = os.waitpid(pid, 0)
    code = os.waitstatus_to_exitcode(status)

    text = output.decode("utf-8", "replace").replace("\r", "")
    if os.environ.get("SCREEN") == "1":
        screens = text.split("\x1b[?1049l")[0].split("\x1b[H")
        last = re.sub(r"\x1b\[[0-9;?<>=]*[A-Za-z]", "", screens[-1])
        print("\n".join(line.rstrip() for line in last.split("\n")))
    else:
        # what was printed after the alternate screen was left
        print(text.split("\x1b[?1049l")[-1].replace("\x1b[?25h", ""), end="")

    if alive:
        sys.stderr.write("tests/terminal.py error: the program didn't end after the keys, killed\n")
        sys.exit(99)
    sys.exit(code if code >= 0 else 128 - code)


main()
