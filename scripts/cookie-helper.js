#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const net = require("net");
const path = require("path");

function fail(message, code = 1) {
  console.error(`[pw-auto] ${message}`);
  process.exit(code);
}

function getOption(tokens, name) {
  for (let i = 0; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token === name) {
      if (i + 1 >= tokens.length)
        fail(`missing value for ${name}.`);
      return tokens[i + 1];
    }
    if (token.startsWith(`${name}=`))
      return token.slice(name.length + 1);
  }
  return "";
}

function hasFlag(tokens, name) {
  return tokens.includes(name);
}

function consumeHelperOptions(tokens) {
  let outputRoot = "";
  let workspaceRoot = "";
  let daemonRoot = "";
  const clean = [];
  for (let i = 0; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token === "--output-root") {
      if (i + 1 >= tokens.length)
        fail("missing value for --output-root.");
      outputRoot = tokens[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--output-root=")) {
      outputRoot = token.slice("--output-root=".length);
      continue;
    }
    if (token === "--workspace-root") {
      if (i + 1 >= tokens.length)
        fail("missing value for --workspace-root.");
      workspaceRoot = tokens[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--workspace-root=")) {
      workspaceRoot = token.slice("--workspace-root=".length);
      continue;
    }
    if (token === "--daemon-root") {
      if (i + 1 >= tokens.length)
        fail("missing value for --daemon-root.");
      daemonRoot = tokens[i + 1];
      i += 1;
      continue;
    }
    if (token.startsWith("--daemon-root=")) {
      daemonRoot = token.slice("--daemon-root=".length);
      continue;
    }
    clean.push(token);
  }
  if (!outputRoot)
    fail("missing helper --output-root.");
  if (!workspaceRoot)
    fail("missing helper --workspace-root.");
  if (!daemonRoot)
    fail("missing helper --daemon-root.");
  return {
    outputRoot: path.resolve(outputRoot),
    workspaceRoot: path.resolve(workspaceRoot),
    daemonRoot: path.resolve(daemonRoot),
    tokens: clean
  };
}

function requireOption(tokens, name) {
  const value = getOption(tokens, name);
  if (!value)
    fail(`missing required ${name} <value>.`);
  return value;
}

function parseUrl(rawUrl) {
  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    fail(`invalid --url '${rawUrl}'.`);
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:")
    fail(`invalid --url '${rawUrl}'. Cookie operations require http or https.`);
  return parsed;
}

function parseSameSite(value) {
  if (!value)
    return "";
  const normalized = value.toLowerCase();
  if (normalized === "strict")
    return "Strict";
  if (normalized === "lax")
    return "Lax";
  if (normalized === "none")
    return "None";
  fail(`invalid --same-site '${value}'. Use Strict, Lax, or None.`);
}

function resolveInputPath(filePath) {
  if (path.isAbsolute(filePath))
    return filePath;
  return path.resolve(process.cwd(), filePath);
}

function readValue(tokens) {
  const valueEnv = getOption(tokens, "--value-env");
  const valueFile = getOption(tokens, "--value-file");
  if (!valueEnv && !valueFile)
    fail("cookie set requires --value-env <ENV_NAME> or --value-file <path>.");
  if (valueEnv && valueFile)
    fail("cookie set accepts only one of --value-env or --value-file.");
  if (valueEnv) {
    if (!Object.prototype.hasOwnProperty.call(process.env, valueEnv))
      fail(`environment variable '${valueEnv}' does not exist.`);
    return process.env[valueEnv] || "";
  }
  const resolved = resolveInputPath(valueFile);
  if (!fs.existsSync(resolved))
    fail(`value file '${valueFile}' does not exist.`);
  if (!fs.statSync(resolved).isFile())
    fail(`value file '${valueFile}' is not a file.`);
  return fs.readFileSync(resolved, "utf8").replace(/\r?\n$/, "");
}

function validateCookieName(name) {
  if (!name)
    fail("missing required --name <cookie_name>.");
  if (/[\s;=]/.test(name))
    fail("invalid cookie name. Cookie names cannot contain whitespace, ';', or '='.");
}

function validateCookieValue(value) {
  if (/[;\r\n]/.test(value))
    fail("invalid cookie value. Cookie values cannot contain ';' or line breaks.");
}

function buildPayload(operation, tokens) {
  const session = requireOption(tokens, "--session");
  const rawUrl = requireOption(tokens, "--url");
  const url = parseUrl(rawUrl);

  if (operation === "set") {
    const name = requireOption(tokens, "--name");
    validateCookieName(name);
    const value = readValue(tokens);
    validateCookieValue(value);
    const sameSite = parseSameSite(getOption(tokens, "--same-site"));
    const domain = getOption(tokens, "--domain") || url.hostname;
    const pathValue = getOption(tokens, "--path") || "/";
    const cookie = {
      name,
      value,
      domain,
      path: pathValue
    };
    if (sameSite)
      cookie.sameSite = sameSite;
    if (hasFlag(tokens, "--secure"))
      cookie.secure = true;
    if (hasFlag(tokens, "--http-only"))
      cookie.httpOnly = true;
    return {
      session,
      operation,
      url: rawUrl,
      name,
      domain,
      path: pathValue,
      cliArgs: {
        _: ["cookie-set", name, value],
        domain,
        path: pathValue,
        secure: !!cookie.secure,
        httpOnly: !!cookie.httpOnly,
        ...(sameSite ? { sameSite } : {})
      },
      showValues: false
    };
  }

  if (operation === "clear") {
    const name = requireOption(tokens, "--name");
    validateCookieName(name);
    const domain = getOption(tokens, "--domain") || "";
    const pathValue = getOption(tokens, "--path") || "";
    return {
      session,
      operation,
      url: rawUrl,
      name,
      domain,
      path: pathValue,
      cliArgs: {
        _: ["run-code", buildClearCode({
          url: rawUrl,
          name,
          domain,
          path: pathValue
        })]
      },
      showValues: false
    };
  }

  if (operation === "list") {
    if (hasFlag(tokens, "--redact") && hasFlag(tokens, "--show-values"))
      fail("cookie list accepts either --redact or --show-values, not both.");
    const showValues = hasFlag(tokens, "--show-values");
    return {
      session,
      operation,
      url: rawUrl,
      cliArgs: {
        _: ["run-code", buildListCode(rawUrl, showValues)]
      },
      showValues
    };
  }

  fail(`unknown cookie command '${operation}'. Use set, clear, or list.`);
}

function buildListCode(url, showValues) {
  return `async page => {
  const cookies = await page.context().cookies([${JSON.stringify(url)}]);
  return {
    operation: "list",
    url: ${JSON.stringify(url)},
    cookies: cookies.map(cookie => ({
      name: cookie.name,
      domain: cookie.domain,
      path: cookie.path,
      expires: cookie.expires,
      httpOnly: !!cookie.httpOnly,
      secure: !!cookie.secure,
      sameSite: cookie.sameSite || "",
      value: ${showValues ? "cookie.value" : JSON.stringify("<redacted>")}
    }))
  };
}`;
}

function buildClearCode({ url, name, domain, path: cookiePath }) {
  return `async page => {
  const input = ${JSON.stringify({ url, name, domain, path: cookiePath })};
  const normalizeDomain = value => (value || "").replace(/^\\./, "");
  const domainMatches = (cookieDomain, requestedDomain) => {
    if (!requestedDomain)
      return true;
    return normalizeDomain(cookieDomain) === normalizeDomain(requestedDomain);
  };
  const cookies = await page.context().cookies([input.url]);
  const matches = cookies.filter(cookie => {
    return cookie.name === input.name &&
      domainMatches(cookie.domain, input.domain) &&
      (!input.path || cookie.path === input.path);
  });
  for (const cookie of matches) {
    await page.context().clearCookies({
      name: cookie.name,
      domain: cookie.domain,
      path: cookie.path
    });
  }
  return {
    operation: "clear",
    name: input.name,
    url: input.url,
    domain: input.domain || "",
    path: input.path || "",
    cleared: matches.length
  };
}`;
}

function createWorkspaceHash(workspaceRoot) {
  return crypto.createHash("sha1").update(workspaceRoot).digest("hex").substring(0, 16);
}

function sessionFilePath(daemonRoot, session) {
  return path.join(daemonRoot, `${session}.session`);
}

function findSessionConfig(daemonRoot, session, workspaceRoot) {
  const candidates = [];
  const configuredPath = sessionFilePath(daemonRoot, session);
  if (fs.existsSync(configuredPath))
    candidates.push(configuredPath);

  const workspaceHash = createWorkspaceHash(workspaceRoot);
  const fallbackPath = path.join(daemonRoot, workspaceHash, `${session}.session`);
  if (fs.existsSync(fallbackPath))
    candidates.push(fallbackPath);

  for (const file of findSessionFiles(daemonRoot, session)) {
    if (!candidates.includes(file))
      candidates.push(file);
  }

  if (!candidates.length)
    return null;

  candidates.sort((a, b) => {
    const aTime = fs.statSync(a).mtimeMs;
    const bTime = fs.statSync(b).mtimeMs;
    return bTime - aTime;
  });
  const file = candidates[0];
  return { file, config: readSessionConfig(file) };
}

function readSessionConfig(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    fail(`session metadata '${file}' is not readable.`);
  }
}

function findSessionFiles(root, session) {
  const matches = [];
  const target = `${session}.session`;
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
      } else if (entry.isFile() && entry.name === target) {
        matches.push(fullPath);
      }
    }
  }
  return matches;
}

function sendSocketMessage(socketPath, method, params) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    const pending = [];
    let settled = false;

    const finish = (error, value) => {
      if (settled)
        return;
      settled = true;
      socket.destroy();
      if (error)
        reject(error);
      else
        resolve(value);
    };

    socket.setTimeout(30000, () => finish(new Error("timed out while contacting Playwright session.")));
    socket.on("connect", () => {
      const message = JSON.stringify({
        id: 1,
        method,
        params
      });
      socket.write(`${message}\n`, error => {
        if (error)
          finish(error);
      });
    });
    socket.on("data", buffer => {
      let end = buffer.indexOf("\n");
      if (end === -1) {
        pending.push(buffer);
        return;
      }
      pending.push(buffer.slice(0, end));
      const text = Buffer.concat(pending).toString();
      try {
        const response = JSON.parse(text);
        if (response.error)
          finish(new Error(response.error));
        else
          finish(null, response.result);
      } catch (error) {
        finish(error);
      }
    });
    socket.on("error", error => finish(error));
    socket.on("close", () => {
      if (!settled)
        finish(new Error("session closed before returning a result."));
    });
  });
}

async function runTool({ workspaceRoot, daemonRoot, payload }) {
  const sessionInfo = findSessionConfig(daemonRoot, payload.session, workspaceRoot);
  if (!sessionInfo)
    fail(`session '${payload.session}' is not open. Run open first.`);

  const config = sessionInfo.config || {};
  const socketPath = config.socketPath;
  if (!socketPath)
    fail(`session '${payload.session}' metadata does not include a socket path.`);

  const params = {
    args: payload.cliArgs,
    cwd: workspaceRoot,
    raw: true,
    json: false
  };

  try {
    return await sendSocketMessage(socketPath, "run", params);
  } catch (error) {
    fail(safeSessionError(payload.session, payload.operation, error.message));
  }
}

function safeSessionError(session, operation, message) {
  const text = message || "";
  if (/ENOENT|ECONNREFUSED|not open|Session closed|closed before returning/i.test(text))
    return `session '${session}' is not open. Run open first.`;
  if (/Cookie should have|Invalid cookie|Protocol error|Storage\.setCookies|browserContext\.addCookies|clearCookies|cookie/i.test(text))
    return `cookie ${operation} failed because the cookie scope was rejected by Playwright. Check --url, --domain, --path, --secure, and --same-site.`;
  return `cookie ${operation} failed. Run recover --session ${session} if the browser is stuck.`;
}

function parseToolText(result) {
  const text = (result && result.text ? String(result.text) : "").trim();
  if (!text)
    return {};
  try {
    return JSON.parse(text);
  } catch {
    const first = text.indexOf("{");
    const last = text.lastIndexOf("}");
    if (first >= 0 && last > first) {
      try {
        return JSON.parse(text.slice(first, last + 1));
      } catch {
        return {};
      }
    }
  }
  return {};
}

function formatCookie(cookie, showValues) {
  let line = `[pw-auto] cookie name=${cookie.name} domain=${cookie.domain} path=${cookie.path} expires=${cookie.expires} httpOnly=${cookie.httpOnly} secure=${cookie.secure} sameSite=${cookie.sameSite}`;
  if (showValues)
    line += ` value=${cookie.value === undefined ? "" : cookie.value}`;
  return line;
}

function emitSuccess(payload, result) {
  if (payload.operation === "set") {
    console.log(`[pw-auto] cookie set name=${payload.name} url=${payload.url} domain=${payload.domain} path=${payload.path} value=<redacted>`);
    return;
  }
  if (payload.operation === "clear") {
    const parsed = parseToolText(result);
    console.log(`[pw-auto] cookie clear name=${payload.name} url=${payload.url} domain=${payload.domain || "<url>"} path=${payload.path || "<any>"} cleared=${parsed.cleared || 0}`);
    return;
  }
  if (payload.operation === "list") {
    const parsed = parseToolText(result);
    const cookies = Array.isArray(parsed.cookies) ? parsed.cookies : [];
    console.log(`[pw-auto] cookies url=${payload.url} count=${cookies.length}${payload.showValues ? " value=<shown>" : ""}`);
    for (const cookie of cookies)
      console.log(formatCookie(cookie, payload.showValues));
  }
}

async function main() {
  const { workspaceRoot, daemonRoot, tokens } = consumeHelperOptions(process.argv.slice(2));
  if (!tokens.length)
    fail("cookie requires set, clear, or list.");
  const operation = tokens[0];
  const rest = tokens.slice(1);
  const payload = buildPayload(operation, rest);
  const result = await runTool({ workspaceRoot, daemonRoot, payload });
  if (result && result.isError)
    fail(safeSessionError(payload.session, operation, result.text));
  emitSuccess(payload, result);
}

main().catch(error => fail(error && error.message ? error.message : String(error)));
