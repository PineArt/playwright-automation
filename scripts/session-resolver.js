"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

function createHashKey(value) {
  return crypto.createHash("sha1").update(value).digest("hex").substring(0, 16);
}

function findWorkspaceDir(startDir) {
  let dir = startDir;
  for (let i = 0; i < 10; i += 1) {
    if (fs.existsSync(path.join(dir, ".playwright")))
      return dir;
    const parent = path.dirname(dir);
    if (parent === dir)
      break;
    dir = parent;
  }
  return "";
}

function packageRootCandidates() {
  const npmCache = process.env.npm_config_cache || process.env.NPM_CONFIG_CACHE;
  if (!npmCache)
    return [];
  const npxRoot = path.join(npmCache, "_npx");
  let entries;
  try {
    entries = fs.readdirSync(npxRoot, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter(entry => entry.isDirectory())
    .map(entry => path.join(npxRoot, entry.name, "node_modules", "playwright-core"))
    .filter(packageRoot => fs.existsSync(path.join(packageRoot, "package.json")))
    .sort();
}

function sessionFileCandidates(daemonRoot, workspaceRoot, session) {
  const workspaceDir = findWorkspaceDir(workspaceRoot);
  const hashSources = [workspaceDir, ...packageRootCandidates(), workspaceRoot];
  const name = `${session}.session`;
  const files = new Set();
  for (const source of hashSources) {
    if (source)
      files.add(path.join(daemonRoot, createHashKey(source), name));
  }
  files.add(path.join(daemonRoot, name));
  return files;
}

function resolveSessionSocket(daemonRoot, session, workspaceRoot) {
  const sockets = [];
  const invalid = [];
  for (const file of sessionFileCandidates(daemonRoot, workspaceRoot, session)) {
    let config;
    try {
      config = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (error) {
      if (error.code !== "ENOENT" && error.code !== "ENOTDIR")
        invalid.push(`session metadata '${file}' is not readable.`);
      continue;
    }
    if (typeof config?.socketPath !== "string" || !config.socketPath.trim()) {
      invalid.push(`session '${session}' metadata does not include a socket path in '${file}'.`);
      continue;
    }
    sockets.push(config.socketPath);
  }
  if (sockets.length > 1) {
    throw new Error(
      `session '${session}' has ambiguous metadata candidates (${sockets.length}) in workspace '${workspaceRoot}'. Check --workspace and --session.`
    );
  }
  if (sockets.length === 1)
    return sockets[0];
  throw new Error(invalid[0] || `session '${session}' is not open in workspace '${workspaceRoot}'. Run open first.`);
}

module.exports = { resolveSessionSocket };
