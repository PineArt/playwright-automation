# Recovery

Use this file when a browser session stops responding, refs go stale repeatedly, or an agent needs to resume work without creating a new browser instance.

## Session States

- `active`: browser is alive and commands work
- `stale`: browser exists but the last refs or page state are no longer trustworthy
- `orphaned`: session metadata exists but the browser or daemon is not responding
- `closed`: browser was intentionally closed

## Recovery Principles

- Recovery is conservative by default.
- Recovery acts on one named session only.
- Recovery does not kill all browser processes unless you choose a destructive command outside the normal wrapper flow.
- Recovery should preserve existing artifacts on disk.

## Normal Recovery Path

1. Re-run `snapshot`.
2. If the command still fails, run `recover --session <name>`.
3. Re-open with the same `--session` only if recovery reports that the old session is gone.
4. Capture a screenshot after recovery before proceeding.

## What `recover` Should Do

`recover --session <name>` should:

1. verify the session exists or report that it does not
2. attempt a non-destructive attach or liveness check
3. if that fails, close only that named session
4. tell the agent to reopen the same session explicitly if needed

## What `recover` Should Not Do

- do not kill all sessions
- do not delete artifacts
- do not start a fresh browser silently
- do not change mode automatically

## Cleanup

Use `cleanup --session <name>` when you are done with a session.

This should:

1. close the browser for that session
2. optionally remove session data for that session
3. leave artifacts under `output/playwright/<session>/` intact

