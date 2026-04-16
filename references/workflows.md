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
3. `run fill ...` or `run click ...`.
4. `snapshot`.
5. `screenshot --name submitted`.

## UI Debugging

When a flow is visually wrong:

1. Prefer `--mode headed`.
2. Use `snapshot`.
3. Use `screenshot --name before-fix`.
4. Use `run console` or `run network`.
5. Use `trace-start` before suspicious actions.
6. Use `trace-stop` after reproducing.

## Data Extraction

Use `snapshot` first and prefer standard commands.
Use `run eval ...` only when the CLI does not already expose the needed behavior.

## Parallel Work

This skill does not support multiple sessions for the same agent.
If an agent needs a clean slate, close or clean up the old session first.

