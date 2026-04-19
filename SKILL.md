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
playwright-automation click e3 --session gallery-a1-headed
playwright-automation snapshot --session gallery-a1-headed
playwright-automation screenshot --session gallery-a1-headed --name after-click
```

For command syntax in each shell, read `references/shell-syntax.md`.

## Command Surface

Use these wrapper commands:

- `doctor`
- `open <url> --session <name> --mode <headed|headless> [--maximize]`
- `snapshot --session <name>`
- `screenshot --session <name> [--name <label>] [--full-page] [target]`
- `trace-start --session <name>`
- `trace-stop --session <name>`
- `sessions`
- `recover --session <name>`
- `cleanup --session <name>`
- `run ...` for passthrough to `playwright-cli` after the wrapper has set environment defaults
- `cli ...` and `raw ...` as explicit passthrough aliases for `run ...`

Use `run` for commands such as `click`, `fill`, `press`, `eval`, `console`, or `network` when there is no dedicated wrapper alias.
Use `--maximize` only with `--mode headed`; it injects a temporary config that starts Chromium-family browsers maximized.

## Workflow

1. Run `doctor`.
2. Open with explicit mode and named session.
3. Snapshot to get current refs.
4. Interact.
5. Snapshot again after state changes.
6. Capture artifacts when the step matters.
7. If a command fails, inspect the error prefix and use `recover --session <name>` before escalating.
8. If the same permission prompt keeps recurring, prefer a persisted approval for that specific wrapper command family before continuing the loop.

## Guardrails

- Do not omit `--mode` on `open`.
- Do not create a second session for the same agent unless you are intentionally abandoning the old one.
- Do not use `recover` without `--session`.
- Do not treat `doctor` as an installer; read its result first.
- Do not rely on `eval` or `run-code` as the default path when refs or standard CLI commands are enough.
- Do not assume the current environment can spawn browsers. In restricted sandboxes, `doctor` may report permission failures that require escalation or a different environment.
- Do not persist an approval that is broader than the repeated action requires. Wrapper-specific approval is preferred over approving a general shell interpreter.

## References

Open only what you need:

- `references/workflows.md` for common automation flows
- `references/recovery.md` for session lifecycle and recovery semantics
- `references/shell-syntax.md` for PowerShell and Git Bash syntax
- `references/troubleshooting.md` for permission, daemon, browser, and wrapper failures
