import type { IncomingMessage, ServerResponse } from "node:http";
import * as crypto from "node:crypto";

export type NextFunction = (err?: unknown) => void;

export interface RequestLike extends IncomingMessage {
  url?: string;
  path?: string;
  method?: string;
  headers: IncomingMessage["headers"];
  body?: unknown;
}

export interface ResponseLike extends ServerResponse {}

export type ExpressMiddleware = (
  req: RequestLike,
  res: ResponseLike,
  next: NextFunction,
) => void | Promise<void>;

export interface SecurityMiddlewares {
  signout: ExpressMiddleware;
  secure: ExpressMiddleware;
  verifyAuth: (cookieHeader: string | undefined) => boolean;
}

export interface CreateSecurityMiddlewaresOptions {
  username?: string;
  password?: string;
  auth?: string; // fallback if "username:password" format is passed directly
  cookieMaxAgeMinutes?: number;
}

/**
 * Creates an HMAC-SHA256 base64url-encoded signature for timestamp.
 */
function createSignature(timestampStr: string, secretKey: string): string {
  return crypto
    .createHmac("sha256", secretKey)
    .update(timestampStr)
    .digest("base64url");
}

/**
 * Generates the auth cookie value: <base64url(timestamp)>.<base64url(hmac_signature)>
 */
function generateAuthCookieValue(secretKey: string): string {
  const nowSeconds = Math.floor(Date.now() / 1000).toString();
  const timestampEncoded = Buffer.from(nowSeconds, "utf8").toString(
    "base64url",
  );
  const signature = createSignature(nowSeconds, secretKey);
  return `${timestampEncoded}.${signature}`;
}

/**
 * Parses and verifies the auth cookie.
 * Reject malformed or invalid cookies, future timestamps, or expired timestamps.
 */
function verifyAuthCookie(
  cookieHeader: string | undefined,
  signingKey: string,
  maxAgeMinutes: number,
): boolean {
  if (!cookieHeader) {
    return false;
  }

  // Find "auth=" cookie
  const match = cookieHeader
    .split(";")
    .map((c) => c.trim())
    .find((c) => c.startsWith("auth="));

  if (!match) {
    return false;
  }

  const cookieVal = match.slice("auth=".length);
  const dotIdx = cookieVal.indexOf(".");
  if (dotIdx === -1) {
    return false;
  }

  const timestampEncoded = cookieVal.slice(0, dotIdx);
  const signature = cookieVal.slice(dotIdx + 1);

  if (!timestampEncoded || !signature) {
    return false;
  }

  let timestampStr: string;
  try {
    timestampStr = Buffer.from(timestampEncoded, "base64url").toString("utf8");
  } catch {
    return false;
  }

  const timestampSeconds = parseInt(timestampStr, 10);
  if (isNaN(timestampSeconds) || timestampSeconds.toString() !== timestampStr) {
    return false;
  }

  const expectedSignature = createSignature(timestampStr, signingKey);
  const sigBuf = Buffer.from(signature);
  const expectedBuf = Buffer.from(expectedSignature);

  if (sigBuf.length !== expectedBuf.length) {
    return false;
  }

  if (!crypto.timingSafeEqual(sigBuf, expectedBuf)) {
    return false;
  }

  const currentSeconds = Math.floor(Date.now() / 1000);
  // Reject future timestamps (allow up to 60s clock skew)
  if (timestampSeconds > currentSeconds + 60) {
    return false;
  }

  // Reject expired cookies
  const maxAgeSeconds = maxAgeMinutes * 60;
  if (currentSeconds - timestampSeconds > maxAgeSeconds) {
    return false;
  }

  return true;
}

/**
 * Constant-time comparison between two strings.
 */
function safeEqual(a: string, b: string): boolean {
  const aBuf = Buffer.from(a, "utf8");
  const bBuf = Buffer.from(b, "utf8");
  if (aBuf.length !== bBuf.length) {
    return false;
  }
  return crypto.timingSafeEqual(aBuf, bBuf);
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function renderLoginForm(targetUrl: string, errorMsg?: string): string {
  const safeTargetUrl = escapeHtml(targetUrl);
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Login</title>
  <style>
    body {
      font-family: monospace;
      padding: 32px 16px;
      margin: 0;
      background: #323232;
      color: #e0e0e0;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 80vh;
      box-sizing: border-box;
    }
    .login-box {
      width: 100%;
      max-width: 380px;
      padding: 24px;
      background: #252525;
      border: 3px solid #ff8c00;
      outline: 3px solid #cd853f;
      outline-offset: 0;
      box-sizing: border-box;
    }
    h2 {
      margin-top: 0;
      margin-bottom: 20px;
      color: #ff8c00;
      font-size: 20px;
    }
    .form-group {
      margin-bottom: 16px;
    }
    label {
      display: block;
      margin-bottom: 6px;
      color: #cd853f;
      font-size: 14px;
    }
    input[type="text"], input[type="password"] {
      width: 100%;
      box-sizing: border-box;
      padding: 8px 10px;
      background: #1e1e1e;
      border: 1px solid #555;
      color: #fff;
      font-family: monospace;
      font-size: 14px;
    }
    input[type="text"]:focus, input[type="password"]:focus {
      outline: none;
      border-color: #ff8c00;
    }
    .btn {
      width: 100%;
      padding: 10px;
      background: #ff8c00;
      border: none;
      color: #111;
      font-family: monospace;
      font-size: 15px;
      font-weight: bold;
      cursor: pointer;
      margin-top: 8px;
    }
    .btn:hover {
      background: #ffa500;
    }
    .error {
      background: #4a1515;
      color: #ff8080;
      padding: 8px 10px;
      margin-bottom: 16px;
      border: 1px solid #a32222;
      font-size: 13px;
    }
  </style>
</head>
<body>
  <div class="login-box">
    <h2>Sign in</h2>
    ${errorMsg ? `<div class="error" data-testid="login-error">${escapeHtml(errorMsg)}</div>` : ""}
    <form method="POST" action="${safeTargetUrl}">
      <input type="hidden" name="__auth_form" value="1">
      <div class="form-group">
        <label for="username">Username</label>
        <input type="text" id="username" name="username" required autocomplete="username" autofocus>
      </div>
      <div class="form-group">
        <label for="password">Password</label>
        <input type="password" id="password" name="password" required autocomplete="current-password">
      </div>
      <button type="submit" class="btn" data-testid="login-submit">Login</button>
    </form>
  </div>
</body>
</html>`;
}

function parseUrlEncodedBody(
  req: RequestLike,
): Promise<Record<string, string>> {
  if (req.body && typeof req.body === "object") {
    const result: Record<string, string> = {};
    for (const [key, value] of Object.entries(
      req.body as Record<string, unknown>,
    )) {
      result[key] = String(value);
    }
    return Promise.resolve(result);
  }

  return new Promise((resolve) => {
    let body = "";
    req.on("data", (chunk: Buffer | string) => {
      body += chunk;
      // Protection against huge payload attacks
      if (body.length > 1e6) {
        req.destroy();
      }
    });
    req.on("end", () => {
      const result: Record<string, string> = {};
      const params = new URLSearchParams(body);
      for (const [key, value] of params.entries()) {
        result[key] = value;
      }
      resolve(result);
    });
    req.on("error", () => {
      resolve({});
    });
  });
}

/**
 * Creates security middlewares (signout and secure) compatible with Express.
 *
 * Example usage:
 *   const securityMiddlewares = createSecurityMiddlewares({
 *     username: "admin",
 *     password: "secretpassword",
 *     cookieMaxAgeMinutes: 120,
 *   });
 *
 *   app.use("/logout", securityMiddlewares.signout);
 *   app.use(securityMiddlewares.secure);
 */
export function createSecurityMiddlewares(
  options: CreateSecurityMiddlewaresOptions = {},
): SecurityMiddlewares {
  if ((!options.username || !options.password) && options.auth) {
    const colonIdx = options.auth.indexOf(":");
    if (colonIdx !== -1) {
      options.username = options.auth.slice(0, colonIdx);
      options.password = options.auth.slice(colonIdx + 1);
    }
  }

  const enabled = Boolean(options.username && options.password);
  const signingKey = enabled ? `${options.username}:${options.password}` : "";
  const maxAgeMinutes = options.cookieMaxAgeMinutes || 720; // 12 hours default

  /**
   * signout middleware: clears auth cookie and redirects to root or handles method not allowed
   */
  const signout: ExpressMiddleware = async (req, res, next) => {
    if (req.method === "POST") {
      res.writeHead(303, {
        Location: "/",
        "Set-Cookie":
          "auth=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0",
        "Cache-Control": "no-store",
      });
      res.end();
      return;
    }

    if (req.method === "GET") {
      res.writeHead(405, {
        "Content-Type": "text/plain; charset=utf-8",
        Allow: "POST",
      });
      res.end("405 Method Not Allowed");
      return;
    }

    next();
  };

  /**
   * secure middleware: ensures authenticated request or handles inline login form submission / displays login page
   */
  const secure: ExpressMiddleware = async (req, res, next) => {
    // If authentication is disabled, continue immediately
    if (!enabled) {
      next();
      return;
    }

    // Check if valid auth cookie exists
    const isAuthenticated = verifyAuthCookie(
      req.headers.cookie,
      signingKey,
      maxAgeMinutes,
    );
    
    if (isAuthenticated) {
      next();
      return;
    }

    const reqUrl = req.url || "/";

    // Handle login form submission (POST)
    const contentType = req.headers["content-type"] || "";
    if (
      req.method === "POST" &&
      contentType.includes("application/x-www-form-urlencoded")
    ) {
      const formData = await parseUrlEncodedBody(req);

      if (formData.__auth_form === "1") {
        const inputUser = formData.username || "";
        const inputPass = formData.password || "";

        const isValidUser = safeEqual(inputUser, options.username || "");
        const isValidPass = safeEqual(inputPass, options.password || "");

        if (isValidUser && isValidPass) {
          const cookieValue = generateAuthCookieValue(signingKey);
          const maxAgeSeconds = maxAgeMinutes * 60;

          res.writeHead(303, {
            Location: reqUrl,
            "Set-Cookie": `auth=${cookieValue}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${maxAgeSeconds}`,
            "Cache-Control": "no-store",
          });
          res.end();
          return;
        }

        // Failed login: re-render form at current URL with generic error
        res.writeHead(401, {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store",
        });
        res.end(renderLoginForm(reqUrl, "Invalid username or password"));
        return;
      }
    }

    // Unauthenticated GET (or non-form request): serve login form directly at requested URL
    res.writeHead(401, {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    });
    res.end(renderLoginForm(reqUrl));
  };

  const verifyAuth = (cookieHeader: string | undefined): boolean => {
    if (enabled) {
      return verifyAuthCookie(cookieHeader, signingKey, maxAgeMinutes);
    }
    return true;
  };

  return {
    signout,
    secure,
    verifyAuth,
  };
}
