/*
 * The interactive list of "gits add": which of the found files go to .git/gits.sh, and which
 * of them as encrypted elements (SOURCE:e:TARGET).
 *
 *     add enc  file
 *   > [x] [ ]  .env
 *     [x] [x]  config/secret.json
 *     [ ]      config/public.json          <- the "enc" box exists only in ticked rows,
 *                                             the paths stay in one column anyway
 *
 * Three parts, the first two are pure (no terminal) and covered by unit tests:
 *
 *   parse_key()   bytes sent by the terminal -> Key
 *   Menu          the state: Menu::key() changes it, Menu::render() gives the lines of the screen
 *   select()      raw mode, alternate screen, the loop: read keys, draw, restore the terminal
 *
 * Use:
 *
 *   if menu::interactive() {
 *       match menu::select(rows, hidden)? {
 *           Outcome::Done(picked) => ...   // Vec<(index of the row, encrypt)>
 *           Outcome::Cancelled => ...
 *           Outcome::Interrupted => ...    // Ctrl+C
 *       }
 *   }
 *
 * Keys:
 *
 *   arrows (or h j k l)       move: up / down between the files, left / right between the two boxes
 *   home end pgup pgdn        first / last file, a page up / down
 *   space                     tick / untick the box under the cursor
 *   a  n  i                   column "add": all on, all off, invert
 *   A  N  I                   column "enc", only among the ticked rows: all on, all off, invert
 *   ctrl+enter                write the ticked files to the config
 *   q  esc  ctrl+c            leave, nothing is written
 *
 * About ctrl+enter: a terminal sends the same byte for Enter and for Ctrl+Enter unless it is asked
 * to tell them apart. select() asks for it in both existing ways (the kitty keyboard protocol and
 * modifyOtherKeys of xterm); a terminal which knows neither ignores the request. For those ctrl+j
 * and ctrl+s do the same (ctrl+j is the byte some terminals send for ctrl+enter).
 * Enter alone never writes anything.
 */

use std::io::Write;

use crate::util::interrupted;

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Key {
    Up,
    Down,
    Left,
    Right,
    Home,
    End,
    PageUp,
    PageDown,
    Space,
    Enter,
    // ctrl+enter, ctrl+j, ctrl+s
    Submit,
    Esc,
    // ctrl+c
    Interrupt,
    Char(char),
    Unknown,
}

// modifiers of "CSI code ; modifiers u" and "CSI 27 ; modifiers ; code ~": 1 + bits, 4 is ctrl, 2 is alt
fn key_of_code(code: u32, modifiers: u32) -> Key {
    let bits = modifiers.saturating_sub(1);
    let ctrl = bits & 4 != 0;
    let alt = bits & 2 != 0;
    match (code, ctrl) {
        (13, true) => Key::Submit,
        (13, false) => Key::Enter,
        (27, _) => Key::Esc,
        (32, false) => Key::Space,
        (99, true) => Key::Interrupt,
        (106, true) | (115, true) => Key::Submit,
        (c, false) if !alt => match char::from_u32(c) {
            Some(ch) if ch.is_ascii_graphic() => Key::Char(ch),
            _ => Key::Unknown,
        },
        _ => Key::Unknown,
    }
}

/**
 * The first key in the bytes and how many bytes it took.
 * None: the bytes are the beginning of a sequence, more have to be read.
 */
pub fn parse_key(bytes: &[u8]) -> Option<(Key, usize)> {
    let first = *bytes.first()?;
    match first {
        0x0d => Some((Key::Enter, 1)),
        0x0a | 0x13 => Some((Key::Submit, 1)),
        0x03 => Some((Key::Interrupt, 1)),
        b' ' => Some((Key::Space, 1)),
        0x1b => {
            let second = *bytes.get(1)?;
            match second {
                b'[' => {
                    // parameters, then one final byte 0x40..=0x7e
                    let end = bytes[2..].iter().position(|b| (0x40..=0x7e).contains(b))?;
                    let last = bytes[2 + end];
                    let text = String::from_utf8_lossy(&bytes[2..2 + end]).to_string();
                    // "13;5:1" -> [13, 5]: what is after ":" (kind of the event) is not needed
                    let numbers: Vec<u32> = text
                        .split(';')
                        .map(|p| {
                            p.split(':')
                                .next()
                                .unwrap_or("")
                                .trim_start_matches(['?', '>', '<', '='])
                                .parse()
                                .unwrap_or(0)
                        })
                        .collect();
                    let number = |i: usize, default: u32| match numbers.get(i) {
                        Some(0) | None => default,
                        Some(n) => *n,
                    };
                    let key = match last {
                        b'A' => Key::Up,
                        b'B' => Key::Down,
                        b'C' => Key::Right,
                        b'D' => Key::Left,
                        b'H' => Key::Home,
                        b'F' => Key::End,
                        b'u' => key_of_code(number(0, 0), number(1, 1)),
                        b'~' => match number(0, 0) {
                            1 | 7 => Key::Home,
                            4 | 8 => Key::End,
                            5 => Key::PageUp,
                            6 => Key::PageDown,
                            27 => key_of_code(number(2, 0), number(1, 1)),
                            _ => Key::Unknown,
                        },
                        _ => Key::Unknown,
                    };
                    Some((key, 3 + end))
                }
                b'O' => {
                    let key = match *bytes.get(2)? {
                        b'A' => Key::Up,
                        b'B' => Key::Down,
                        b'C' => Key::Right,
                        b'D' => Key::Left,
                        b'H' => Key::Home,
                        b'F' => Key::End,
                        _ => Key::Unknown,
                    };
                    Some((key, 3))
                }
                // alt + key
                _ => Some((Key::Unknown, 2)),
            }
        }
        c if c.is_ascii_graphic() => Some((Key::Char(c as char), 1)),
        _ => Some((Key::Unknown, 1)),
    }
}

#[derive(Debug, PartialEq)]
pub enum Outcome {
    // (index of the row, encrypt) of every ticked row, in the order of the rows
    Done(Vec<(usize, bool)>),
    Cancelled,
    Interrupted,
}

struct Row {
    label: String,
    add: bool,
    enc: bool,
}

pub struct Menu {
    rows: Vec<Row>,
    // files which were found but are in the config already: only mentioned
    hidden: usize,
    row: usize,
    // 0: box "add", 1: box "enc"
    col: usize,
    top: usize,
    message: String,
}

const HELP: [&str; 5] = [
    "  arrows: move      space: tick or untick the box under the cursor",
    "  column add:  a all   n none   i invert",
    "  column enc:  A all   N none   I invert    (only the ticked rows)",
    "  ctrl+enter: add the ticked files to the config (also ctrl+j, ctrl+s)",
    "  q / esc: leave, nothing is written",
];

// lines of the screen which are not rows: title, empty, header | empty, message, help
const CHROME: usize = 3 + 2 + HELP.len();

fn cut(text: &str, width: usize) -> String {
    text.chars().take(width).collect()
}

// the end of a path says more than its beginning
fn cut_left(text: &str, width: usize) -> String {
    let count = text.chars().count();
    if count <= width {
        return text.to_string();
    }
    if width == 0 {
        return String::new();
    }
    let tail: String = text.chars().skip(count - (width - 1)).collect();
    format!("…{tail}")
}

impl Menu {
    // rows: (path as it is shown, ticked, encrypted)
    pub fn new(rows: Vec<(String, bool, bool)>, hidden: usize) -> Menu {
        Menu {
            rows: rows
                .into_iter()
                .map(|(label, add, enc)| Row {
                    label,
                    add,
                    enc: add && enc,
                })
                .collect(),
            hidden,
            row: 0,
            col: 0,
            top: 0,
            message: String::new(),
        }
    }

    fn picked(&self) -> Vec<(usize, bool)> {
        self.rows
            .iter()
            .enumerate()
            .filter(|(_, r)| r.add)
            .map(|(i, r)| (i, r.enc))
            .collect()
    }

    // page: number of rows visible at once. Some: the menu is over
    pub fn key(&mut self, key: Key, page: usize) -> Option<Outcome> {
        self.message.clear();
        let last = self.rows.len().saturating_sub(1);
        let page = page.max(1);
        match key {
            Key::Up | Key::Char('k') => self.row = self.row.saturating_sub(1),
            Key::Down | Key::Char('j') => self.row = (self.row + 1).min(last),
            Key::Left | Key::Char('h') => self.col = 0,
            Key::Right | Key::Char('l') => self.col = 1,
            Key::Home => self.row = 0,
            Key::End => self.row = last,
            Key::PageUp => self.row = self.row.saturating_sub(page),
            Key::PageDown => self.row = (self.row + page).min(last),
            Key::Space => {
                if let Some(row) = self.rows.get_mut(self.row) {
                    if self.col == 0 {
                        row.add = !row.add;
                        // the box "enc" of a row which is not ticked doesn't exist
                        row.enc = false;
                    } else if row.add {
                        row.enc = !row.enc;
                    } else {
                        // "encrypt" asked for a file which is not ticked: it means both
                        row.add = true;
                        row.enc = true;
                    }
                }
            }
            Key::Char('a') => self.rows.iter_mut().for_each(|r| r.add = true),
            Key::Char('n') => self.rows.iter_mut().for_each(|r| {
                r.add = false;
                r.enc = false;
            }),
            Key::Char('i') => self.rows.iter_mut().for_each(|r| {
                r.add = !r.add;
                r.enc = false;
            }),
            Key::Char('A') => self.rows.iter_mut().for_each(|r| r.enc = r.add),
            Key::Char('N') => self.rows.iter_mut().for_each(|r| r.enc = false),
            Key::Char('I') => self.rows.iter_mut().for_each(|r| r.enc = r.add && !r.enc),
            Key::Enter => {
                self.message =
                    "Enter alone does nothing: ctrl+enter adds the ticked files (or ctrl+j, ctrl+s)"
                        .to_string();
            }
            Key::Submit => {
                let picked = self.picked();
                if picked.is_empty() {
                    self.message = "no file is ticked: tick some, or leave with q".to_string();
                } else {
                    return Some(Outcome::Done(picked));
                }
            }
            Key::Esc | Key::Char('q') => return Some(Outcome::Cancelled),
            Key::Interrupt => return Some(Outcome::Interrupted),
            Key::Char(_) | Key::Unknown => {}
        }
        // the row of the cursor is always visible
        if self.row < self.top {
            self.top = self.row;
        }
        if self.row >= self.top + page {
            self.top = self.row + 1 - page;
        }
        None
    }

    pub fn page(height: usize) -> usize {
        height.saturating_sub(CHROME).max(1)
    }

    /**
     * Lines of the whole screen, never more than height and never wider than width.
     * styled: with escape sequences (colors, reverse video under the cursor). Without them the
     * cursor is still visible: ">" before the row.
     */
    pub fn render(&self, width: usize, height: usize, styled: bool) -> Vec<String> {
        let paint = |code: &str, text: &str| {
            if styled {
                format!("\x1b[{code}m{text}\x1b[0m")
            } else {
                text.to_string()
            }
        };
        let page = Menu::page(height);
        let picked = self.picked();
        let encrypted = picked.iter().filter(|(_, e)| *e).count();

        let mut title = format!(
            "  gits add: {} found, {} ticked, {} encrypted",
            self.rows.len(),
            picked.len(),
            encrypted
        );
        if self.hidden > 0 {
            title.push_str(&format!("   ({} already in the config)", self.hidden));
        }

        let mut lines = vec![
            paint("1", &cut(&title, width)),
            String::new(),
            paint("2", &cut("    add enc  file", width)),
        ];

        // "  > [x] [x]  " is 13 columns, the path starts in the same column in every row
        let room = width.saturating_sub(13);
        for (i, row) in self.rows.iter().enumerate().skip(self.top).take(page) {
            let here = i == self.row;
            let add = if row.add { "[x]" } else { "[ ]" };
            let enc = match (row.add, row.enc) {
                (true, true) => "[x]",
                (true, false) => "[ ]",
                // no box, the same width
                (false, _) => "   ",
            };
            let add = match (here && self.col == 0, row.add) {
                (true, _) => paint("7", add),
                (false, true) => paint("32", add),
                (false, false) => add.to_string(),
            };
            let enc = match (here && self.col == 1, row.add && row.enc) {
                (true, _) => paint("7", enc),
                (false, true) => paint("33", enc),
                (false, false) => enc.to_string(),
            };
            let label = cut_left(&row.label, room);
            let label = if row.add { label } else { paint("2", &label) };
            lines.push(format!(
                "  {} {add} {enc}  {label}",
                if here { ">" } else { " " }
            ));
        }

        let above = self.top;
        let below = self.rows.len().saturating_sub(self.top + page);
        lines.push(if above + below > 0 {
            paint(
                "2",
                &cut(&format!("    ... above: {above}, below: {below}"), width),
            )
        } else {
            String::new()
        });
        lines.push(paint("33", &cut(&format!("  {}", self.message), width)));
        for help in HELP {
            lines.push(paint("2", &cut(help, width)));
        }
        lines.truncate(height.max(1));
        lines
    }
}

// The menu needs a person: stdin is a terminal (echo "" | gits add ... is the way to say
// "no list"), and there is a terminal to draw on
pub fn interactive() -> bool {
    unsafe { libc::isatty(0) == 1 && libc::isatty(1) == 1 }
}

// a person can be asked: stdin is a terminal (not a pipe, a file or /dev/null)
pub fn stdin_is_terminal() -> bool {
    unsafe { libc::isatty(0) == 1 }
}

// what a key means for confirm(). None: not an answer, wait for the next one
fn answer(key: &Key) -> Option<bool> {
    match key {
        Key::Enter | Key::Char('y') | Key::Char('Y') => Some(true),
        Key::Esc | Key::Interrupt | Key::Char('q') | Key::Char('n') | Key::Char('N') => Some(false),
        _ => None,
    }
}

/**
 * Prints the prompt and waits for one key: Enter (or y) is true, Esc (or n, q, ctrl+c) is false.
 * Only for a terminal on stdin (stdin_is_terminal()). The terminal is given back as it was.
 */
pub fn confirm(prompt: &str) -> Result<bool, String> {
    let mut saved: libc::termios = unsafe { std::mem::zeroed() };
    if unsafe { libc::tcgetattr(0, &mut saved) } != 0 {
        return Err("can't read the settings of the terminal".to_string());
    }
    let mut raw = saved;
    // a key arrives at once and is not printed; ctrl+c stays a signal. read() returns after
    // 0.1 s also without a key: time to notice a signal, and that Esc was not the start of a sequence
    raw.c_lflag &= !(libc::ICANON | libc::ECHO);
    raw.c_cc[libc::VMIN] = 0;
    raw.c_cc[libc::VTIME] = 1;
    if unsafe { libc::tcsetattr(0, libc::TCSAFLUSH, &raw) } != 0 {
        return Err("can't switch the terminal to read one key".to_string());
    }
    out(&format!("{prompt} "));

    let mut pending: Vec<u8> = Vec::new();
    let result = loop {
        if interrupted() {
            break Ok(false);
        }
        let mut buffer = [0u8; 64];
        let count =
            unsafe { libc::read(0, buffer.as_mut_ptr() as *mut libc::c_void, buffer.len()) };
        let mut decided = None;
        if count > 0 {
            pending.extend_from_slice(&buffer[..count as usize]);
        } else if count < 0 {
            let error = std::io::Error::last_os_error();
            if error.kind() != std::io::ErrorKind::Interrupted {
                break Err(format!("can't read from the terminal: {error}"));
            }
        } else if !pending.is_empty() {
            // nothing came after the beginning of a sequence: Esc alone is the key Esc
            if pending == [0x1b] {
                decided = Some(false);
            }
            pending.clear();
        }
        // without raw mode Enter arrives as a line feed
        if pending.first() == Some(&b'\n') {
            decided = Some(true);
        }
        while decided.is_none() {
            let Some((key, used)) = parse_key(&pending) else {
                break;
            };
            pending.drain(..used);
            decided = answer(&key);
        }
        if let Some(yes) = decided {
            break Ok(yes);
        }
    };

    unsafe { libc::tcsetattr(0, libc::TCSAFLUSH, &saved) };
    out(match result {
        Ok(true) => "go on\n",
        _ => "stop\n",
    });
    result
}

fn size() -> (usize, usize) {
    let mut ws: libc::winsize = unsafe { std::mem::zeroed() };
    let ok = unsafe { libc::ioctl(1, libc::TIOCGWINSZ, &mut ws) } == 0;
    if ok && ws.ws_col > 0 && ws.ws_row > 0 {
        (ws.ws_col as usize, ws.ws_row as usize)
    } else {
        (80, 24)
    }
}

fn out(text: &str) {
    let mut stdout = std::io::stdout();
    let _ = stdout.write_all(text.as_bytes());
    let _ = stdout.flush();
}

// the terminal as select() needs it; Drop gives it back as it was, also on an error path
struct Raw {
    saved: libc::termios,
}

impl Raw {
    fn enter() -> Result<Raw, String> {
        let mut saved: libc::termios = unsafe { std::mem::zeroed() };
        if unsafe { libc::tcgetattr(0, &mut saved) } != 0 {
            return Err("can't read the settings of the terminal".to_string());
        }
        let mut raw = saved;
        unsafe { libc::cfmakeraw(&mut raw) };
        // read() returns after 0.1 s also without a key: time to notice a signal, a lone Esc, a new size
        raw.c_cc[libc::VMIN] = 0;
        raw.c_cc[libc::VTIME] = 1;
        if unsafe { libc::tcsetattr(0, libc::TCSAFLUSH, &raw) } != 0 {
            return Err("can't switch the terminal to raw mode".to_string());
        }
        // alternate screen, no cursor, "tell ctrl+enter from enter": kitty protocol, modifyOtherKeys
        out("\x1b[?1049h\x1b[?25l\x1b[>1u\x1b[>4;1m");
        Ok(Raw { saved })
    }
}

impl Drop for Raw {
    fn drop(&mut self) {
        out("\x1b[>4;0m\x1b[<u\x1b[?25h\x1b[?1049l");
        unsafe { libc::tcsetattr(0, libc::TCSAFLUSH, &self.saved) };
    }
}

fn draw(menu: &Menu, width: usize, height: usize) {
    let styled = std::env::var_os("NO_COLOR").is_none();
    let lines = menu.render(width, height, styled);
    let mut screen = String::from("\x1b[H");
    screen.push_str(&lines.join("\x1b[K\r\n"));
    screen.push_str("\x1b[K\x1b[J");
    out(&screen);
}

/**
 * Shows the menu and returns when the person decided.
 * rows: (path as it is shown, ticked at the beginning, encrypted at the beginning).
 */
pub fn select(rows: Vec<(String, bool, bool)>, hidden: usize) -> Result<Outcome, String> {
    let mut menu = Menu::new(rows, hidden);
    let _raw = Raw::enter()?;

    let (mut width, mut height) = size();
    draw(&menu, width, height);

    let mut pending: Vec<u8> = Vec::new();
    loop {
        if interrupted() {
            return Ok(Outcome::Interrupted);
        }

        let mut buffer = [0u8; 64];
        let count =
            unsafe { libc::read(0, buffer.as_mut_ptr() as *mut libc::c_void, buffer.len()) };
        let mut redraw = false;

        if count > 0 {
            pending.extend_from_slice(&buffer[..count as usize]);
        } else if count < 0 {
            let error = std::io::Error::last_os_error();
            if error.kind() != std::io::ErrorKind::Interrupted {
                return Err(format!("can't read from the terminal: {error}"));
            }
        } else if !pending.is_empty() {
            // nothing came after the beginning of a sequence: Esc alone is the key Esc
            let key = if pending == [0x1b] {
                Key::Esc
            } else {
                Key::Unknown
            };
            pending.clear();
            if let Some(outcome) = menu.key(key, Menu::page(height)) {
                return Ok(outcome);
            }
            redraw = true;
        }

        while let Some((key, used)) = parse_key(&pending) {
            pending.drain(..used);
            if let Some(outcome) = menu.key(key, Menu::page(height)) {
                return Ok(outcome);
            }
            redraw = true;
        }

        let now = size();
        if now != (width, height) {
            (width, height) = now;
            // the cursor has to stay visible in the new height
            menu.key(Key::Unknown, Menu::page(height));
            redraw = true;
        }
        if redraw {
            draw(&menu, width, height);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn menu(count: usize) -> Menu {
        Menu::new(
            (0..count)
                .map(|i| (format!("f{i}.txt"), true, false))
                .collect(),
            0,
        )
    }

    fn state(m: &Menu) -> String {
        m.rows
            .iter()
            .map(|r| match (r.add, r.enc) {
                (true, true) => 'E',
                (true, false) => 'x',
                (false, _) => '.',
            })
            .collect()
    }

    fn keys(m: &mut Menu, list: &[Key]) -> Option<Outcome> {
        for key in list {
            if let Some(outcome) = m.key(*key, 10) {
                return Some(outcome);
            }
        }
        None
    }

    #[test]
    fn confirm_keys() {
        assert_eq!(answer(&Key::Enter), Some(true));
        assert_eq!(answer(&Key::Char('y')), Some(true));
        assert_eq!(answer(&Key::Esc), Some(false));
        assert_eq!(answer(&Key::Interrupt), Some(false));
        assert_eq!(answer(&Key::Char('n')), Some(false));
        assert_eq!(answer(&Key::Char('x')), None);
        assert_eq!(answer(&Key::Space), None);
    }

    #[test]
    fn parses_keys() {
        assert_eq!(parse_key(b"\x1b[A"), Some((Key::Up, 3)));
        assert_eq!(parse_key(b"\x1b[B"), Some((Key::Down, 3)));
        assert_eq!(parse_key(b"\x1b[C"), Some((Key::Right, 3)));
        assert_eq!(parse_key(b"\x1b[D"), Some((Key::Left, 3)));
        assert_eq!(parse_key(b"\x1bOA"), Some((Key::Up, 3)));
        assert_eq!(parse_key(b"\x1b[1;5A"), Some((Key::Up, 6)));
        assert_eq!(parse_key(b"\x1b[5~"), Some((Key::PageUp, 4)));
        assert_eq!(parse_key(b"\x1b[6~"), Some((Key::PageDown, 4)));
        assert_eq!(parse_key(b" "), Some((Key::Space, 1)));
        assert_eq!(parse_key(b"a"), Some((Key::Char('a'), 1)));
        assert_eq!(parse_key(b"A"), Some((Key::Char('A'), 1)));
        assert_eq!(parse_key(b"\x03"), Some((Key::Interrupt, 1)));
        // only the first key is taken
        assert_eq!(parse_key(b"\x1b[Bxyz"), Some((Key::Down, 3)));
        // the beginning of a sequence: wait for the rest
        assert_eq!(parse_key(b""), None);
        assert_eq!(parse_key(b"\x1b"), None);
        assert_eq!(parse_key(b"\x1b["), None);
        assert_eq!(parse_key(b"\x1b[13;"), None);
    }

    #[test]
    fn enter_is_not_ctrl_enter() {
        assert_eq!(parse_key(b"\r"), Some((Key::Enter, 1)));
        // kitty keyboard protocol
        assert_eq!(parse_key(b"\x1b[13;5u"), Some((Key::Submit, 7)));
        assert_eq!(parse_key(b"\x1b[13;5:1u"), Some((Key::Submit, 9)));
        assert_eq!(parse_key(b"\x1b[13u"), Some((Key::Enter, 5)));
        assert_eq!(parse_key(b"\x1b[13;2u"), Some((Key::Enter, 7)));
        assert_eq!(parse_key(b"\x1b[27u"), Some((Key::Esc, 5)));
        assert_eq!(parse_key(b"\x1b[99;5u"), Some((Key::Interrupt, 7)));
        assert_eq!(parse_key(b"\x1b[106;5u"), Some((Key::Submit, 8)));
        assert_eq!(parse_key(b"\x1b[115;5u"), Some((Key::Submit, 8)));
        assert_eq!(parse_key(b"\x1b[97;5u"), Some((Key::Unknown, 7)));
        // modifyOtherKeys of xterm
        assert_eq!(parse_key(b"\x1b[27;5;13~"), Some((Key::Submit, 10)));
        assert_eq!(parse_key(b"\x1b[27;2;13~"), Some((Key::Enter, 10)));
        // terminals which know neither: ctrl+j, ctrl+s
        assert_eq!(parse_key(b"\n"), Some((Key::Submit, 1)));
        assert_eq!(parse_key(b"\x13"), Some((Key::Submit, 1)));
    }

    #[test]
    fn ticking() {
        let mut m = menu(3);
        assert_eq!(state(&m), "xxx");
        // box "add" of the first row
        keys(&mut m, &[Key::Space]);
        assert_eq!(state(&m), ".xx");
        // box "enc" of the second row
        keys(&mut m, &[Key::Down, Key::Right, Key::Space]);
        assert_eq!(state(&m), ".Ex");
        keys(&mut m, &[Key::Space]);
        assert_eq!(state(&m), ".xx");
        // "enc" of a row which is not ticked ticks both
        keys(&mut m, &[Key::Up, Key::Space]);
        assert_eq!(state(&m), "Exx");
        // unticking "add" removes "enc": ticked again it is plain
        keys(&mut m, &[Key::Left, Key::Space, Key::Space]);
        assert_eq!(state(&m), "xxx");
    }

    #[test]
    fn shortcuts_of_both_columns() {
        let mut m = menu(4);
        keys(&mut m, &[Key::Char('n')]);
        assert_eq!(state(&m), "....");
        keys(&mut m, &[Key::Char('a')]);
        assert_eq!(state(&m), "xxxx");
        keys(&mut m, &[Key::Space, Key::Char('i')]);
        assert_eq!(state(&m), "x...");
        keys(&mut m, &[Key::Char('i')]);
        assert_eq!(state(&m), ".xxx");

        // the shortcuts of "enc" touch only ticked rows
        keys(&mut m, &[Key::Char('A')]);
        assert_eq!(state(&m), ".EEE");
        keys(&mut m, &[Key::Char('N')]);
        assert_eq!(state(&m), ".xxx");
        keys(&mut m, &[Key::Down, Key::Right, Key::Space, Key::Char('I')]);
        assert_eq!(state(&m), ".xEE");
        // "all off" of the column "add" leaves no encryption behind
        keys(&mut m, &[Key::Char('n'), Key::Char('a')]);
        assert_eq!(state(&m), "xxxx");
    }

    #[test]
    fn only_ctrl_enter_ends_with_a_result() {
        let mut m = menu(3);
        assert_eq!(keys(&mut m, &[Key::Enter]), None);
        assert!(m.message.contains("ctrl+enter"));
        keys(
            &mut m,
            &[Key::Down, Key::Space, Key::Down, Key::Right, Key::Space],
        );
        assert_eq!(
            keys(&mut m, &[Key::Submit]),
            Some(Outcome::Done(vec![(0, false), (2, true)]))
        );

        let mut m = menu(2);
        assert_eq!(keys(&mut m, &[Key::Char('n'), Key::Submit]), None);
        assert!(m.message.contains("no file is ticked"));
        assert_eq!(keys(&mut m, &[Key::Char('q')]), Some(Outcome::Cancelled));
        assert_eq!(keys(&mut menu(1), &[Key::Esc]), Some(Outcome::Cancelled));
        assert_eq!(
            keys(&mut menu(1), &[Key::Interrupt]),
            Some(Outcome::Interrupted)
        );
    }

    #[test]
    fn paths_stay_in_one_column() {
        let mut m = Menu::new(
            vec![
                ("one.txt".to_string(), true, true),
                ("two.txt".to_string(), true, false),
                ("three.txt".to_string(), false, false),
            ],
            2,
        );
        keys(&mut m, &[Key::Down]);
        let lines = m.render(80, 24, false);
        assert_eq!(
            lines[0],
            "  gits add: 3 found, 2 ticked, 1 encrypted   (2 already in the config)"
        );
        assert_eq!(lines[2], "    add enc  file");
        assert_eq!(lines[3], "    [x] [x]  one.txt");
        assert_eq!(lines[4], "  > [x] [ ]  two.txt");
        // no box "enc" in a row which is not ticked, the path is where it is in the other rows
        assert_eq!(lines[5], "    [ ]      three.txt");
        for (line, label) in lines[3..6].iter().zip(["one.txt", "two.txt", "three.txt"]) {
            assert_eq!(line.find(label), Some(13));
        }
    }

    #[test]
    fn scrolls_and_fits_the_screen() {
        let mut m = menu(30);
        // 24 lines of the screen: 14 rows at once
        let page = Menu::page(24);
        assert_eq!(page, 14);
        for _ in 0..20 {
            m.key(Key::Down, page);
        }
        assert_eq!(m.row, 20);
        assert_eq!(m.top, 7);
        let lines = m.render(40, 24, false);
        assert_eq!(lines.len(), 24);
        assert!(lines.iter().all(|l| l.chars().count() <= 40));
        assert!(lines[3].ends_with("f7.txt"));
        assert!(lines.iter().any(|l| l == "  > [x] [ ]  f20.txt"));
        assert!(lines[17].contains("above: 7, below: 9"));

        m.key(Key::Home, page);
        assert_eq!((m.row, m.top), (0, 0));
        m.key(Key::End, page);
        assert_eq!((m.row, m.top), (29, 16));
        m.key(Key::PageUp, page);
        assert_eq!(m.row, 15);

        // a long path keeps its end
        assert_eq!(cut_left("directory/sub/file.txt", 10), "…/file.txt");
        // a screen smaller than the frame still shows one row
        assert_eq!(Menu::page(3), 1);
        assert!(menu(5).render(20, 3, false).len() <= 3);
    }
}
