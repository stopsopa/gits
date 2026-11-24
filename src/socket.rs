use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::time::Duration;

/**
 * Client of the encoder process (submodules/encrypt/examples/socket): gits never encrypts by
 * itself and starts no program for it, it asks the process listening on a unix socket.
 *
 * One request per line, one reply line per request:
 *
 *   encode "<plain file>" "<encrypted file>"     ->   ok encode "<encrypted file>" 3ms
 *   decode "<encrypted file>" "<plain file>"     ->   ok decode "<plain file>" 2ms
 *                                                     error MALFORMED not an ssenc1 file ...
 *
 * A path is written like a JSON string. Paths are always sent absolute: a relative one would be
 * resolved against the directory the server was started in.
 */
pub const ENV_SOCKET: &str = "GITSTORAGETENCRYPTIONSOCKET";

#[derive(Debug)]
pub struct EncError {
    // USAGE | AUTH | MALFORMED | ENV from the server, IO when the connection itself failed
    pub kind: String,
    pub message: String,
}

impl EncError {
    fn io(message: String) -> Self {
        EncError {
            kind: "IO".to_string(),
            message,
        }
    }

    // the input is not an encrypted file at all
    pub fn malformed(&self) -> bool {
        self.kind == "MALFORMED"
    }
}

impl std::fmt::Display for EncError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} {}", self.kind, self.message)
    }
}

pub struct Encoder {
    reader: BufReader<UnixStream>,
}

// connection is opened when the first encrypted element is met and kept for all the others
pub struct Lazy {
    path: Option<String>,
    encoder: Option<Encoder>,
}

impl Lazy {
    pub fn new(path: Option<String>) -> Self {
        Lazy {
            path,
            encoder: None,
        }
    }

    pub fn get(&mut self) -> Result<&mut Encoder, String> {
        if self.encoder.is_none() {
            let path = self.path.as_deref().ok_or_else(|| {
                format!(
                    "the config has encrypted elements (SOURCE:e:TARGET) but env var {ENV_SOCKET} is not defined, \
                     it has to point to the unix socket of the encoder process"
                )
            })?;
            self.encoder = Some(Encoder::connect(path)?);
        }
        Ok(self.encoder.as_mut().unwrap())
    }
}

impl Encoder {
    pub fn connect(path: &str) -> Result<Self, String> {
        let stream = UnixStream::connect(path).map_err(|e| {
            format!("can't connect to the encoder process on socket {ENV_SOCKET}=>{path}<: {e} (is it running?)")
        })?;
        // an agent asking for a touch / passphrase can take a while, but never forever
        let _ = stream.set_read_timeout(Some(Duration::from_secs(120)));
        let _ = stream.set_write_timeout(Some(Duration::from_secs(30)));
        Ok(Encoder {
            reader: BufReader::new(stream),
        })
    }

    pub fn encode(&mut self, plain: &Path, encrypted: &Path) -> Result<(), EncError> {
        self.request("encode", plain, encrypted)
    }

    pub fn decode(&mut self, encrypted: &Path, plain: &Path) -> Result<(), EncError> {
        self.request("decode", encrypted, plain)
    }

    fn request(&mut self, command: &str, input: &Path, output: &Path) -> Result<(), EncError> {
        let line = format_request(command, input, output).map_err(EncError::io)?;
        let stream = self.reader.get_mut();
        stream
            .write_all(line.as_bytes())
            .and_then(|_| stream.flush())
            .map_err(|e| EncError::io(format!("can't send request to the encoder process: {e}")))?;

        let mut reply = String::new();
        let read = self
            .reader
            .read_line(&mut reply)
            .map_err(|e| EncError::io(format!("no reply from the encoder process: {e}")))?;
        if read == 0 {
            return Err(EncError::io(
                "the encoder process closed the connection without a reply".to_string(),
            ));
        }
        parse_reply(reply.trim_end_matches(['\r', '\n']))
    }
}

pub fn format_request(command: &str, input: &Path, output: &Path) -> Result<String, String> {
    Ok(format!("{command} {} {}\n", quote(input)?, quote(output)?))
}

// JSON string
fn quote(path: &Path) -> Result<String, String> {
    let text = path.to_str().ok_or_else(|| {
        format!(
            "path >{}< is not valid UTF-8, can't be sent to the encoder process",
            path.display()
        )
    })?;
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    Ok(out)
}

pub fn parse_reply(reply: &str) -> Result<(), EncError> {
    if reply.starts_with("ok ") {
        return Ok(());
    }
    if let Some(rest) = reply.strip_prefix("error ") {
        let (kind, message) = rest.split_once(' ').unwrap_or((rest, ""));
        return Err(EncError {
            kind: kind.to_string(),
            message: message.to_string(),
        });
    }
    Err(EncError::io(format!(
        "unexpected reply from the encoder process >{reply}<"
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_format() {
        assert_eq!(
            format_request("encode", Path::new("/a/b c.txt"), Path::new("/a/\"q\".enc")).unwrap(),
            "encode \"/a/b c.txt\" \"/a/\\\"q\\\".enc\"\n"
        );
        assert_eq!(
            format_request("decode", Path::new("/a\\b"), Path::new("/c")).unwrap(),
            "decode \"/a\\\\b\" \"/c\"\n"
        );
    }

    #[test]
    fn reply_parsing() {
        assert!(parse_reply("ok encode \"/a\" 3ms").is_ok());
        let e = parse_reply("error MALFORMED not an ssenc1 file (missing '#ssenc1' header)")
            .unwrap_err();
        assert!(e.malformed());
        assert_eq!(e.message, "not an ssenc1 file (missing '#ssenc1' header)");
        let e = parse_reply("error AUTH no key slot could be opened").unwrap_err();
        assert_eq!(e.kind, "AUTH");
        assert!(!e.malformed());
        assert_eq!(parse_reply("whatever").unwrap_err().kind, "IO");
    }
}
