#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function fail(message, code = 1) {
  console.error(`[pw-auto] ${message}`);
  process.exit(code);
}

function consumeHelperOptions(tokens) {
  const options = {
    base: "",
    target: "",
    workspaceRoot: "",
    maximize: false,
    browser: "",
    openTokens: []
  };
  let i = 0;
  for (; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token === "--") {
      i += 1;
      break;
    }
    if (token === "--base") {
      if (i + 1 >= tokens.length)
        fail("missing value for helper --base.");
      options.base = tokens[i + 1];
      i += 1;
      continue;
    }
    if (token === "--target") {
      if (i + 1 >= tokens.length)
        fail("missing value for helper --target.");
      options.target = tokens[i + 1];
      i += 1;
      continue;
    }
    if (token === "--workspace-root") {
      if (i + 1 >= tokens.length)
        fail("missing value for helper --workspace-root.");
      options.workspaceRoot = tokens[i + 1];
      i += 1;
      continue;
    }
    if (token === "--maximize") {
      options.maximize = true;
      continue;
    }
    if (token === "--browser") {
      if (i + 1 >= tokens.length)
        fail("missing value for helper --browser.");
      options.browser = tokens[i + 1];
      i += 1;
      continue;
    }
    fail(`unknown helper option '${token}'.`);
  }
  options.openTokens = tokens.slice(i);
  if (!options.target)
    fail("missing helper --target.");
  if (!options.workspaceRoot)
    fail("missing helper --workspace-root.");
  return options;
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

function hasOption(tokens, name) {
  return tokens.some(token => token === name || token.startsWith(`${name}=`));
}

function hasAnyOption(tokens, names) {
  return names.some(name => hasOption(tokens, name));
}

function resolveInputPath(filePath, workspaceRoot) {
  if (path.isAbsolute(filePath))
    return filePath;
  return path.resolve(workspaceRoot, filePath);
}

function readJsonFile(filePath, label, workspaceRoot) {
  const resolved = resolveInputPath(filePath, workspaceRoot);
  if (!fs.existsSync(resolved))
    fail(`${label} '${filePath}' does not exist.`);
  if (!fs.statSync(resolved).isFile())
    fail(`${label} '${filePath}' is not a file.`);
  try {
    const raw = fs.readFileSync(resolved, "utf8");
    return raw.trim() ? JSON.parse(raw) : {};
  } catch {
    fail(`${label} '${filePath}' is not valid JSON.`);
  }
}

function readBaseConfig(basePath, workspaceRoot) {
  if (!basePath)
    return {};
  const config = readJsonFile(basePath, "config file", workspaceRoot);
  if (!config || typeof config !== "object" || Array.isArray(config))
    fail(`config file '${basePath}' must contain a JSON object.`);
  return config;
}

function ensureObject(parent, key) {
  if (!parent[key] || typeof parent[key] !== "object" || Array.isArray(parent[key]))
    parent[key] = {};
  return parent[key];
}

function readHttpCredentials(tokens, workspaceRoot) {
  const rawOptions = ["--http-username", "--http-password", "--http-credentials"];
  if (hasAnyOption(tokens, rawOptions))
    fail("raw HTTP credential values are unsupported. Use --http-username-env/--http-password-env or --http-credentials-file.");

  const usernameEnv = getOption(tokens, "--http-username-env");
  const passwordEnv = getOption(tokens, "--http-password-env");
  const credentialsFile = getOption(tokens, "--http-credentials-file");

  if (credentialsFile && (usernameEnv || passwordEnv))
    fail("open accepts either --http-credentials-file or --http-username-env/--http-password-env, not both.");
  if ((usernameEnv && !passwordEnv) || (!usernameEnv && passwordEnv))
    fail("open requires both --http-username-env and --http-password-env when using environment credentials.");

  if (credentialsFile) {
    const credentials = readJsonFile(credentialsFile, "HTTP credentials file", workspaceRoot);
    if (!credentials || typeof credentials !== "object" || Array.isArray(credentials))
      fail(`HTTP credentials file '${credentialsFile}' must contain a JSON object.`);
    const username = credentials.username;
    const password = credentials.password;
    if (typeof username !== "string" || !username)
      fail("HTTP credentials file must contain a non-empty string username.");
    if (typeof password !== "string" || !password)
      fail("HTTP credentials file must contain a non-empty string password.");
    return { username, password };
  }

  if (usernameEnv && passwordEnv) {
    if (!Object.prototype.hasOwnProperty.call(process.env, usernameEnv))
      fail(`environment variable '${usernameEnv}' does not exist.`);
    if (!Object.prototype.hasOwnProperty.call(process.env, passwordEnv))
      fail(`environment variable '${passwordEnv}' does not exist.`);
    const username = process.env[usernameEnv] || "";
    const password = process.env[passwordEnv] || "";
    if (!username)
      fail(`environment variable '${usernameEnv}' is empty.`);
    if (!password)
      fail(`environment variable '${passwordEnv}' is empty.`);
    return { username, password };
  }

  return null;
}

function applyMaximize(config, browserName) {
  const browser = ensureObject(config, "browser");
  const selectedBrowser = browserName || browser.browserName || "";
  if (selectedBrowser === "firefox" || selectedBrowser === "webkit")
    fail("--maximize is supported only for Chromium-family browsers.");

  const launchOptions = ensureObject(browser, "launchOptions");
  if (selectedBrowser) {
    if (selectedBrowser === "chrome" || selectedBrowser.startsWith("chrome-")) {
      browser.browserName = "chromium";
      launchOptions.channel = selectedBrowser;
    } else if (selectedBrowser === "msedge" || selectedBrowser.startsWith("msedge-")) {
      browser.browserName = "chromium";
      launchOptions.channel = selectedBrowser;
    } else {
      browser.browserName = selectedBrowser;
    }
  }

  const launchArgs = Array.isArray(launchOptions.args) ? launchOptions.args.map(String) : [];
  if (!launchArgs.includes("--start-maximized"))
    launchArgs.push("--start-maximized");
  launchOptions.args = launchArgs;

  const contextOptions = ensureObject(browser, "contextOptions");
  contextOptions.viewport = null;
}

function applyHttpCredentials(config, credentials) {
  if (!credentials)
    return;
  const browser = ensureObject(config, "browser");
  const contextOptions = ensureObject(browser, "contextOptions");
  contextOptions.httpCredentials = {
    username: credentials.username,
    password: credentials.password
  };
}

function writeConfig(target, config) {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, `${JSON.stringify(config, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o600
  });
}

function main() {
  const options = consumeHelperOptions(process.argv.slice(2));
  const config = readBaseConfig(options.base, options.workspaceRoot);
  const credentials = readHttpCredentials(options.openTokens, options.workspaceRoot);
  if (options.maximize)
    applyMaximize(config, options.browser);
  applyHttpCredentials(config, credentials);
  writeConfig(options.target, config);
}

main();
