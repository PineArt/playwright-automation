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

function getOptions(tokens, name) {
  const values = [];
  for (let i = 0; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token === name) {
      if (i + 1 >= tokens.length)
        fail(`missing value for ${name}.`);
      values.push(tokens[i + 1]);
      i += 1;
      continue;
    }
    if (token.startsWith(`${name}=`))
      values.push(token.slice(name.length + 1));
  }
  return values;
}

function hasFlag(tokens, name) {
  return tokens.includes(name);
}

function hasOption(tokens, name) {
  return tokens.some(token => token === name || token.startsWith(`${name}=`));
}

function requireOption(tokens, name) {
  const value = getOption(tokens, name);
  if (!value)
    fail(`missing required ${name} <value>.`);
  return value;
}

function parsePositiveInt(value, name, defaultValue) {
  if (!value)
    return defaultValue;
  if (!/^[0-9]+$/.test(value))
    fail(`${name} must be a non-negative integer.`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed))
    fail(`${name} is too large.`);
  return parsed;
}

function parseAtLeastOneInt(value, name) {
  const parsed = parsePositiveInt(value, name, 0);
  if (parsed < 1)
    fail(`${name} must be at least 1.`);
  return parsed;
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

function safePathSegment(value) {
  const safe = String(value || "").replace(/[^A-Za-z0-9._-]/g, "_");
  return safe || "probe";
}

function timestamp() {
  const now = new Date();
  const pad = value => String(value).padStart(2, "0");
  return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
}

function artifactPath(outputRoot, session, operation, name) {
  const sessionDir = path.join(outputRoot, safePathSegment(session));
  fs.mkdirSync(sessionDir, { recursive: true });
  const label = safePathSegment(name || operation);
  return path.join(sessionDir, `${label}-${timestamp()}.json`);
}

function createWorkspaceHash(workspaceRoot) {
  return crypto.createHash("sha1").update(workspaceRoot).digest("hex").substring(0, 16);
}

function sessionFilePath(daemonRoot, session) {
  return path.join(daemonRoot, `${session}.session`);
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

function readSessionConfig(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    fail(`session metadata '${file}' is not readable.`);
  }
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

  candidates.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  const file = candidates[0];
  return { file, config: readSessionConfig(file) };
}

function sendSocketMessage(socketPath, method, params, timeoutMs) {
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

    socket.setTimeout(timeoutMs, () => finish(new Error("timed out while contacting Playwright session.")));
    socket.on("connect", () => {
      const message = JSON.stringify({ id: 1, method, params });
      socket.write(`${message}\n`, error => {
        if (error)
          finish(error);
      });
    });
    socket.on("data", buffer => {
      const end = buffer.indexOf("\n");
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

  const socketPath = sessionInfo.config && sessionInfo.config.socketPath;
  if (!socketPath)
    fail(`session '${payload.session}' metadata does not include a socket path.`);

  const params = {
    args: { _: ["run-code", payload.code] },
    cwd: workspaceRoot,
    raw: true,
    json: false
  };

  try {
    return await sendSocketMessage(socketPath, "run", params, payload.socketTimeoutMs);
  } catch (error) {
    fail(safeSessionError(payload.session, payload.operation, error.message));
  }
}

function safeSessionError(session, operation, message) {
  const text = message || "";
  if (/ENOENT|ECONNREFUSED|not open|Session closed|closed before returning/i.test(text))
    return `session '${session}' is not open. Run open first.`;
  const compact = text.replace(/\s+/g, " ").slice(0, 240);
  if (compact)
    return `probe ${operation} failed: ${compact}`;
  return `probe ${operation} failed. Run recover --session ${session} if the browser is stuck.`;
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

function buildNetworkCode(input) {
  return `async page => {
  const input = ${JSON.stringify(input)};
  const startedAtMs = Date.now();
  const events = [];
  const pendingBodies = [];
  let lastIncludedEventAtMs = startedAtMs;
  let trigger = { type: input.trigger.type, status: "none", elapsedMs: 0 };
  const compilePattern = value => input.regex ? new RegExp(value) : String(value);
  const includes = input.includes.map(compilePattern);
  const excludes = input.excludes.map(compilePattern);
  const matchesPattern = (pattern, value) => input.regex ? pattern.test(value) : value.includes(pattern);
  const shouldInclude = rawUrl => {
    const url = String(rawUrl || "");
    if (includes.length && !includes.some(pattern => matchesPattern(pattern, url)))
      return false;
    if (excludes.some(pattern => matchesPattern(pattern, url)))
      return false;
    return /^https?:/i.test(url);
  };
  const touch = () => {
    lastIncludedEventAtMs = Date.now();
  };
  const recordRequest = request => {
    const url = request.url();
    if (!shouldInclude(url))
      return;
    touch();
    events.push({
      phase: "request",
      timeMs: Date.now() - startedAtMs,
      method: request.method(),
      url,
      resourceType: request.resourceType(),
      navigationRequest: request.isNavigationRequest()
    });
  };
  const recordResponse = response => {
    const request = response.request();
    const url = request.url();
    if (!shouldInclude(url))
      return;
    touch();
    const item = {
      phase: "response",
      timeMs: Date.now() - startedAtMs,
      method: request.method(),
      url,
      status: response.status(),
      statusText: response.statusText(),
      ok: response.ok()
    };
    events.push(item);
    if (input.includeBodies) {
      item.bodyStatus = "pending";
      const bodyTask = response.text().then(text => {
        item.bodyStatus = "ok";
        item.bodyLength = text.length;
        item.body = text.length > input.bodyMaxChars ? text.slice(0, input.bodyMaxChars) : text;
        item.bodyTruncated = text.length > input.bodyMaxChars;
      }).catch(error => {
        item.bodyStatus = "error";
        item.bodyError = error && error.message ? error.message : String(error);
      });
      pendingBodies.push(bodyTask);
    }
  };
  page.on("request", recordRequest);
  page.on("response", recordResponse);
  let stopReason = "duration";
  try {
    if (input.trigger.type !== "none") {
      const triggerStartedAtMs = Date.now();
      trigger = { type: input.trigger.type, status: "started", elapsedMs: 0 };
      try {
        if (input.trigger.type === "reload") {
          await page.reload({ waitUntil: input.trigger.waitUntil });
        } else if (input.trigger.type === "goto") {
          await page.goto(input.trigger.url, { waitUntil: input.trigger.waitUntil });
        } else if (input.trigger.type === "click") {
          await page.locator(input.trigger.selector).click();
        } else if (input.trigger.type === "select") {
          await page.locator(input.trigger.selector).selectOption(input.trigger.value);
        }
        trigger.status = "ok";
      } catch (error) {
        trigger.status = "error";
        trigger.error = error && error.message ? error.message : String(error);
      }
      trigger.elapsedMs = Date.now() - triggerStartedAtMs;
      lastIncludedEventAtMs = Date.now();
    }
    await new Promise(resolve => {
      const tick = () => {
        const now = Date.now();
        if (input.untilQuietMs > 0 && now - lastIncludedEventAtMs >= input.untilQuietMs) {
          stopReason = "quiet";
          resolve();
          return;
        }
        if (now - startedAtMs >= input.durationMs) {
          stopReason = "duration";
          resolve();
          return;
        }
        const nextQuiet = input.untilQuietMs > 0 ? Math.max(25, input.untilQuietMs - (now - lastIncludedEventAtMs)) : 100;
        const nextDuration = Math.max(25, input.durationMs - (now - startedAtMs));
        page.waitForTimeout(Math.min(100, nextQuiet, nextDuration)).then(tick);
      };
      page.waitForTimeout(0).then(tick);
    });
  } finally {
    page.off("request", recordRequest);
    page.off("response", recordResponse);
  }
  if (pendingBodies.length) {
    const bodyGraceMs = Math.min(Math.max(Math.floor(input.durationMs / 4), 1000), 5000);
    await Promise.race([
      Promise.allSettled(pendingBodies),
      page.waitForTimeout(bodyGraceMs)
    ]);
  }
  const requestCounts = {};
  const statusCounts = {};
  for (const event of events) {
    if (event.phase === "request") {
      const key = event.method + " " + event.url;
      requestCounts[key] = (requestCounts[key] || 0) + 1;
    }
    if (event.phase === "response") {
      const key = String(event.status);
      statusCounts[key] = (statusCounts[key] || 0) + 1;
    }
  }
  const duplicateRequestKeys = Object.entries(requestCounts)
    .filter(([, count]) => count > 1)
    .map(([key, count]) => ({ key, count }));
  return {
    operation: "network",
    startedAt: new Date(startedAtMs).toISOString(),
    elapsedMs: Date.now() - startedAtMs,
    stopReason,
    capture: {
      startsAt: "command-invocation",
      durationMs: input.durationMs,
      untilQuietMs: input.untilQuietMs || null
    },
    filters: {
      include: input.includes,
      exclude: input.excludes,
      dialect: input.regex ? "regex" : "substring"
    },
    trigger,
    bodyPolicy: {
      included: !!input.includeBodies,
      maxChars: input.includeBodies ? input.bodyMaxChars : 0
    },
    summary: {
      requestCount: events.filter(event => event.phase === "request").length,
      responseCount: events.filter(event => event.phase === "response").length,
      requestCounts,
      statusCounts,
      duplicateRequestKeys
    },
    events
  };
}`;
}

function buildWaitOptionCode(input) {
  return `async page => {
  const input = ${JSON.stringify(input)};
  const startedAt = Date.now();
  const takeSnapshot = async () => page.locator(input.selector).evaluateAll((elements, innerInput) => {
    const first = elements[0] || null;
    if (!first) {
      return {
        selectorCount: elements.length,
        optionMode: "missing",
        optionCount: 0,
        options: []
      };
    }
    const isSelect = first.tagName && first.tagName.toLowerCase() === "select";
    const optionNodes = isSelect ? Array.from(first.options || []) : Array.from(first.querySelectorAll('[role="option"]'));
    const options = optionNodes.map((option, index) => {
      const text = (option.textContent || "").trim();
      const attrValue = option.getAttribute("value");
      const dataValue = option.getAttribute("data-value");
      return {
        index,
        value: attrValue !== null ? attrValue : (dataValue !== null ? dataValue : text),
        text,
        disabled: !!option.disabled || option.getAttribute("aria-disabled") === "true",
        selected: !!option.selected || option.getAttribute("aria-selected") === "true"
      };
    });
    return {
      selectorCount: elements.length,
      optionMode: isSelect ? "select" : "role-option",
      optionCount: options.length,
      options
    };
  }, input);
  const matches = snapshot => {
    if (input.predicate === "non-empty")
      return snapshot.options.some(option => String(option.value).length > 0);
    if (input.predicate === "count-at-least")
      return snapshot.optionCount >= input.countAtLeast;
    if (input.predicate === "value") {
      const expected = String(input.value);
      return snapshot.options.some(option => String(input.matchText ? option.text : option.value) === expected);
    }
    return false;
  };
  let snapshot = await takeSnapshot();
  while (!matches(snapshot) && Date.now() - startedAt < input.timeoutMs) {
    await page.waitForTimeout(100);
    snapshot = await takeSnapshot();
  }
  const success = matches(snapshot);
  return {
    operation: "wait-option",
    success,
    status: success ? "ok" : "timeout",
    elapsedMs: Date.now() - startedAt,
    timeoutMs: input.timeoutMs,
    selector: input.selector,
    predicate: {
      type: input.predicate,
      value: input.value || "",
      countAtLeast: input.countAtLeast || null,
      field: input.predicate === "value" ? (input.matchText ? "text" : "value") : null,
      match: "exact"
    },
    snapshot
  };
}`;
}

function buildStyleCode(input) {
  return `async page => {
  const input = ${JSON.stringify(input)};
  const elements = await page.locator(input.selector).evaluateAll((nodes, innerInput) => {
    return nodes.map((node, index) => {
      const computed = window.getComputedStyle(node);
      const styles = {};
      for (const property of innerInput.properties)
        styles[property] = computed.getPropertyValue(property);
      const text = (node.textContent || "").trim().replace(/\\s+/g, " ");
      return {
        index,
        styles,
        textSample: text.length > innerInput.textMaxChars ? text.slice(0, innerInput.textMaxChars) : text,
        textTruncated: text.length > innerInput.textMaxChars
      };
    });
  }, input);
  return {
    operation: "style",
    selector: input.selector,
    properties: input.properties,
    count: elements.length,
    elements
  };
}`;
}

function buildNetworkPayload(tokens) {
  const session = requireOption(tokens, "--session");
  const durationMs = parsePositiveInt(getOption(tokens, "--duration-ms"), "--duration-ms", 5000);
  const untilQuietMs = parsePositiveInt(getOption(tokens, "--until-quiet-ms"), "--until-quiet-ms", 0);
  if (durationMs < 1)
    fail("--duration-ms must be at least 1.");
  const includeBodies = hasFlag(tokens, "--include-bodies");
  const bodyMaxChars = parsePositiveInt(getOption(tokens, "--body-max-chars"), "--body-max-chars", 2048);
  if (includeBodies && bodyMaxChars < 1)
    fail("--body-max-chars must be at least 1.");
  const trigger = buildNetworkTrigger(tokens);
  const input = {
    durationMs,
    untilQuietMs,
    includes: getOptions(tokens, "--include"),
    excludes: getOptions(tokens, "--exclude"),
    regex: hasFlag(tokens, "--regex"),
    includeBodies,
    bodyMaxChars,
    trigger
  };
  if (input.regex) {
    for (const pattern of input.includes.concat(input.excludes)) {
      try {
        new RegExp(pattern);
      } catch (error) {
        fail(`invalid regex pattern '${pattern}': ${error.message}`);
      }
    }
  }
  if (includeBodies)
    console.error("[pw-auto] warning: network response bodies may contain secrets and are saved to the probe artifact.");
  return {
    session,
    operation: "network",
    name: getOption(tokens, "--name") || "network",
    socketTimeoutMs: Math.max(45000, durationMs + 15000),
    code: buildNetworkCode(input)
  };
}

function buildNetworkTrigger(tokens) {
  const hasReload = hasFlag(tokens, "--reload");
  const gotoUrl = getOption(tokens, "--goto");
  const clickSelector = getOption(tokens, "--click");
  const selectSelector = getOption(tokens, "--select");
  const actionCount = [hasReload, !!gotoUrl, !!clickSelector, !!selectSelector].filter(Boolean).length;
  if (actionCount > 1)
    fail("network accepts at most one trigger: --reload, --goto, --click, or --select.");
  const waitUntil = getOption(tokens, "--wait-until") || "load";
  if (!["load", "domcontentloaded", "networkidle", "commit"].includes(waitUntil))
    fail("--wait-until must be load, domcontentloaded, networkidle, or commit.");
  if (hasReload)
    return { type: "reload", waitUntil };
  if (gotoUrl)
    return { type: "goto", url: gotoUrl, waitUntil };
  if (clickSelector)
    return { type: "click", selector: clickSelector };
  if (selectSelector) {
    const value = getOption(tokens, "--value");
    if (!hasOption(tokens, "--value"))
      fail("network --select requires --value <value>.");
    return { type: "select", selector: selectSelector, value };
  }
  return { type: "none" };
}

function buildWaitOptionPayload(tokens) {
  const session = requireOption(tokens, "--session");
  const selector = requireOption(tokens, "--selector");
  const hasValue = hasOption(tokens, "--value");
  const hasNonEmpty = hasFlag(tokens, "--non-empty");
  const countAtLeastValue = getOption(tokens, "--count-at-least");
  const hasCountAtLeast = !!countAtLeastValue;
  const predicateCount = [hasValue, hasNonEmpty, hasCountAtLeast].filter(Boolean).length;
  if (predicateCount !== 1)
    fail("wait-option requires exactly one of --value, --non-empty, or --count-at-least <n>.");
  if (!hasValue && hasFlag(tokens, "--match-text"))
    fail("wait-option --match-text is only valid with --value.");
  const input = {
    selector,
    predicate: hasValue ? "value" : (hasNonEmpty ? "non-empty" : "count-at-least"),
    value: getOption(tokens, "--value"),
    countAtLeast: hasCountAtLeast ? parseAtLeastOneInt(countAtLeastValue, "--count-at-least") : 0,
    matchText: hasFlag(tokens, "--match-text"),
    timeoutMs: parsePositiveInt(getOption(tokens, "--timeout-ms"), "--timeout-ms", 5000)
  };
  if (input.timeoutMs < 1)
    fail("--timeout-ms must be at least 1.");
  return {
    session,
    operation: "wait-option",
    name: getOption(tokens, "--name") || "wait-option",
    socketTimeoutMs: Math.max(30000, input.timeoutMs + 10000),
    code: buildWaitOptionCode(input)
  };
}

function buildStylePayload(tokens) {
  const session = requireOption(tokens, "--session");
  const selector = requireOption(tokens, "--selector");
  const properties = getOptions(tokens, "--property");
  if (!properties.length)
    fail("style requires at least one --property <css-name>.");
  const input = {
    selector,
    properties,
    textMaxChars: parsePositiveInt(getOption(tokens, "--text-max-chars"), "--text-max-chars", 120)
  };
  return {
    session,
    operation: "style",
    name: getOption(tokens, "--name") || "style",
    socketTimeoutMs: 30000,
    code: buildStyleCode(input)
  };
}

function buildPayload(tokens) {
  if (!tokens.length)
    fail("probe requires network, wait-option, or style.");
  const operation = tokens[0];
  const rest = tokens.slice(1);
  if (operation === "network")
    return buildNetworkPayload(rest);
  if (operation === "wait-option")
    return buildWaitOptionPayload(rest);
  if (operation === "style")
    return buildStylePayload(rest);
  fail(`unknown probe command '${operation}'. Use network, wait-option, or style.`);
}

function writeArtifact(outputRoot, payload, data) {
  const file = artifactPath(outputRoot, payload.session, payload.operation, payload.name);
  const enriched = {
    ...data,
    artifact: file
  };
  fs.writeFileSync(file, `${JSON.stringify(enriched, null, 2)}\n`, "utf8");
  return { file, enriched };
}

function emitSummary(payload, enriched) {
  console.log(`[pw-auto] probe ${payload.operation} artifact=${enriched.artifact}`);
  if (payload.operation === "network") {
    const summary = enriched.summary || {};
    const trigger = enriched.trigger || {};
    const triggerFailed = trigger.status === "error";
    console.log(`[pw-auto] probe network requests=${summary.requestCount || 0} responses=${summary.responseCount || 0} duplicateRequestKeys=${(summary.duplicateRequestKeys || []).length} trigger=${trigger.status || "none"}`);
    if (triggerFailed)
      console.error(`[pw-auto] probe network trigger ${trigger.type || "unknown"} failed: ${trigger.error || "unknown"}`);
    return triggerFailed ? 1 : 0;
  }
  if (payload.operation === "wait-option") {
    const snapshot = enriched.snapshot || {};
    console.log(`[pw-auto] probe wait-option status=${enriched.status} optionMode=${snapshot.optionMode || ""} optionCount=${snapshot.optionCount || 0}`);
    return enriched.success ? 0 : 1;
  }
  if (payload.operation === "style") {
    console.log(`[pw-auto] probe style count=${enriched.count || 0}`);
    return 0;
  }
  return 0;
}

async function main() {
  const { outputRoot, workspaceRoot, daemonRoot, tokens } = consumeHelperOptions(process.argv.slice(2));
  const payload = buildPayload(tokens);
  const result = await runTool({ workspaceRoot, daemonRoot, payload });
  if (result && result.isError)
    fail(safeSessionError(payload.session, payload.operation, result.text));
  const parsed = parseToolText(result);
  if (!parsed || !parsed.operation)
    fail(`probe ${payload.operation} returned no JSON result.`);
  const { enriched } = writeArtifact(outputRoot, payload, parsed);
  const exitCode = emitSummary(payload, enriched);
  process.exit(exitCode);
}

main().catch(error => fail(error && error.message ? error.message : String(error)));
