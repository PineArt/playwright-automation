---
name: playwright-automation
description: Robust Playwright CLI browser automation with explicit headed or headless mode, deterministic session handling, artifact conventions, and recovery guardrails. Use when Codex or Claude needs to automate a real browser from the terminal for navigation, form filling, screenshots, snapshots, tracing, UI debugging, or data extraction without defaulting to Playwright test specs.
---

# Playwright Automation

Use this skill to drive a real browser through `@playwright/cli` with explicit mode selection, one-agent-one-session discipline, and predictable artifact handling.
Treat `headed` and `headless` as peer modes. Do not open a browser without an explicit `--mode`.

## Core Rules

- Always invoke the wrapper scripts, not the raw CLI, unless debugging the wrapper itself.
- Always pass `--mode headed` or `--mode headless` to `open`.
- Keep one session per agent instance. Reuse that named session instead of starting extra browser instances.
- Snapshot before using refs like `e12`.
- Re-snapshot after navigation, modals, tab changes, or any major DOM update.
- Store artifacts under `output/playwright/<session>/`.
- Prefer `doctor` before blaming the page or the wrapper.
- Use `recover` conservatively. Do not kill sessions unless you explicitly choose a destructive flag.
- In hosts that support persisted approval rules, prefer a narrowly scoped persistent approval for repeated wrapper commands instead of re-requesting one-off approval every time.
- Keep persisted approval scope tight. Approve the concrete wrapper or browser helper prefix you need, not a broad shell prefix that would allow unrelated commands.

## Entrypoints

This repository is the skill root.
If someone clones this repository, they should be able to copy the repository directory directly into a Codex or Claude skills directory and use it as-is.

Examples:

- clone repo -> copy repo folder to `$CODEX_HOME/skills/playwright-automation`
- clone repo -> copy repo folder to Claude's skills directory under `playwright-automation`

Use the script that matches the current shell:

- PowerShell: `scripts/playwright-automation.ps1`
- Git Bash: `scripts/playwright-automation.sh`

If the skill is installed somewhere else, use that installed path instead.
The wrappers use the current working directory as the workspace by default.
Override the workspace explicitly with `--workspace <path>` or `PW_AUTO_WORKSPACE`.

Logical command pattern:

```text
playwright-automation <command> [args] [options]
```

The wrappers normalize:

- explicit mode enforcement for `open`
- existing-session navigation through `goto` and `reload`
- current-workspace defaults instead of install-location defaults
- session and artifact environment defaults
- deterministic error prefixes
- safer recovery and cleanup entrypoints

## Quick Start

Use a session name that identifies the agent and mode, for example `gallery-a1-headed` or `gallery-a1-headless`.

Core loop:

```text
playwright-automation doctor
playwright-automation open https://example.com --session gallery-a1-headed --mode headed
playwright-automation snapshot --session gallery-a1-headed
playwright-automation target-first click --session gallery-a1-headed --target "#primary-action" --target e3 --settle-ms 1500
playwright-automation snapshot --session gallery-a1-headed
playwright-automation screenshot --session gallery-a1-headed --name after-click
```

For command syntax in each shell, read `references/shell-syntax.md`.

## Command Surface

Use these wrapper commands:

- `doctor`
- `open <url> --session <name> --mode <headed|headless> [--maximize] [--http-username-env <ENV> --http-password-env <ENV> | --http-credentials-file <path>]`
- `goto <url> --session <name>`
- `reload --session <name>`
- `snapshot --session <name>`
- `screenshot --session <name> [--name <label>] [--full-page] [target]`
- `trace-start --session <name>`
- `trace-stop --session <name>`
- `target-first <fill|click> ...` for selector-first, ref-fallback interactions
- `cookie set --session <name> --url <url> --name <cookie_name> --value-env <ENV_NAME> [--path /] [--domain <domain>] [--same-site Strict|Lax|None] [--secure] [--http-only]`
- `cookie set --session <name> --url <url> --name <cookie_name> --value-file <path> [same options]`
- `cookie list --session <name> --url <url> [--redact|--show-values]`
- `cookie clear --session <name> --url <url> --name <cookie_name> [--path /] [--domain <domain>]`
- `sessions`
- `recover --session <name>`
- `cleanup --session <name>`
- `run ...` for passthrough to `playwright-cli` after the wrapper has set environment defaults
- `cli ...` and `raw ...` as explicit passthrough aliases for `run ...`

Use `run` for commands such as `click`, `fill`, `press`, `eval`, `console`, or `network` when there is no dedicated wrapper alias.
Use `open` only to create or intentionally recreate a browser page. It can reset page-level in-memory state; after injecting cookies or storage into an existing session, use `reload` or `goto`, not another `open`.
Use `goto` to navigate an existing session without reopening it. Use `reload` when the current URL, hash route, or newly injected cookie should be re-read by the app.
Use `--maximize` only with `--mode headed`; it injects a temporary config that starts Chromium-family browsers maximized.
Use `target-first` when you want a lightweight ordered fallback such as stable selector first and latest snapshot ref last. Prefer scoped selectors such as `table button.some-row-action`, exact role/label selectors when available, and refs from the latest snapshot when text selectors are ambiguous.
Use `open` HTTP credential options for browser Basic Auth challenges. Prefer `--http-username-env` with `--http-password-env`, or `--http-credentials-file` with JSON `{"username":"...","password":"..."}`. Raw credential values are intentionally unsupported, and wrapper output redacts credentials.
Use `cookie` for login-state injection during local UI verification. Always provide `--session` and `--url`; the wrapper does not infer origin or domain. Prefer `--value-env` or `--value-file` for secrets. Cookie values are redacted by default and are only shown by `cookie list` when `--show-values` is explicitly provided. `cookie set` success only proves the browser context accepted the cookie; verify with `cookie list`, `reload` or `goto`, `snapshot`, and an app-level authenticated state check such as `/api/auth/session` or visible page state.

## Workflow

1. Run `doctor`.
2. Open with explicit mode and named session.
3. Snapshot to get current refs.
4. Interact. Prefer stable selectors first and refs from the latest snapshot second.
5. For submit-oriented or SPA flows, prefer `fill --submit`, `press Enter`, or `target-first ... --settle-ms`; do not treat a click followed by an immediate `eval` as a failure conclusion.
6. Snapshot again after state changes.
7. Capture artifacts when the step matters.
8. If a command fails, inspect the error prefix. Wrapper path, session setup, selector ambiguity, and strict-mode errors are automation failures, not product failures.
9. If the same permission prompt keeps recurring, prefer a persisted approval for that specific wrapper command family before continuing the loop.

## Guardrails

- Do not omit `--mode` on `open`.
- Do not call `open` after cookie or storage injection unless you intentionally want to rebuild the page/session surface; use `reload` or `goto` for existing sessions.
- Do not create a second session for the same agent unless you are intentionally abandoning the old one.
- Do not use `recover` without `--session`.
- Do not treat `doctor` as an installer; read its result first.
- Do not rely on `eval` or `run-code` as the default path when refs or standard CLI commands are enough. Diagnostic reads such as `document.title`, error-overlay checks, or app-session endpoint checks are acceptable.
- Do not default to snapshot refs when you already have a stable unique selector; keep refs as the fallback.
- Do not put Basic Auth passwords on the command line. Use the `open` HTTP credential env/file options so credentials are not echoed in output.
- Do not use `run eval` with `document.cookie` for login-state injection. Use the `cookie` command so HttpOnly cookies work and values are not echoed in command output.
- Do not assume the current environment can spawn browsers. In restricted sandboxes, `doctor` may report permission failures that require escalation or a different environment.
- Do not persist an approval that is broader than the repeated action requires. Wrapper-specific approval is preferred over approving a general shell interpreter.

## References

Open only what you need:

- `references/workflows.md` for common automation flows
- `references/recovery.md` for session lifecycle and recovery semantics
- `references/shell-syntax.md` for PowerShell and Git Bash syntax
- `references/troubleshooting.md` for permission, daemon, browser, and wrapper failures
