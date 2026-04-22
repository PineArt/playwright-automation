# Playwright Automation Workflows

Use this file when the basic loop in `SKILL.md` is not enough.

## Standard Loop

1. Run `doctor`.
2. Open with `--session` and `--mode`.
3. Snapshot.
4. Interact.
5. Re-snapshot when the UI changes.
6. Save evidence in `output/playwright/<session>/`.

## Why One Agent Maps To One Session

The skill assumes one agent owns one session.
Reuse the same session for repeated steps so you do not launch extra browser instances.

If the same agent needs to continue work later:

- re-run commands with the same `--session`
- use `recover --session <name>` if the daemon or browser got into a bad state

If a different agent is doing separate work:

- use a different session name
- use a different artifact subdirectory

## Suggested Session Naming

Use:

```text
<project>-<agent>-<mode>
```

Examples:

- `gallery-a1-headed`
- `gallery-a1-headless`
- `checkout-critic-headed`

This keeps artifact paths and recovery commands obvious.

## Form Submission

1. `open` with explicit mode and session.
2. `snapshot`.
3. Prefer stable selectors first and latest snapshot refs second.
4. Use `target-first fill --text ... --target "<stable selector>" --target e12`.
5. For submit-oriented flows, prefer `run fill ... --submit` on the final editable field or `run press Enter`.
6. If a button is still needed, use `target-first click --target "<stable selector>" --target e21 --settle-ms 1500`.
7. `snapshot`.
8. `screenshot --name submitted`.

Example:

```text
target-first fill --session login-headed --text my-user --target "#username" --target e12
playwright-automation run fill "#password" my-pass --submit --session login-headed
playwright-automation run eval "() => new Promise((resolve) => setTimeout(resolve, 2000))" --session login-headed
playwright-automation snapshot --session login-headed
```

## UI Debugging

When a flow is visually wrong:

1. Prefer `--mode headed`.
2. Use `snapshot`.
3. Use `screenshot --name before-fix`.
4. If refs are flaky, retry the step with selector-first ordering through `target-first`.
5. Use `run console` or `run network`.
6. Use `trace-start` before suspicious actions.
7. Use `trace-stop` after reproducing.

## Data Extraction

Use `snapshot` first and prefer standard commands.
Use `run eval ...` only when the CLI does not already expose the needed behavior.

## Parallel Work

This skill does not support multiple sessions for the same agent.
If an agent needs a clean slate, close or clean up the old session first.
