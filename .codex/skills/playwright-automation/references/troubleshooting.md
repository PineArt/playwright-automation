# Troubleshooting

Use this file when the wrapper fails before a browser action completes.

## `doctor` Reports Missing `npx`

Install Node.js and npm first. The wrapper depends on `npx`.

## `open` Fails Because Mode Was Not Provided

This is expected. The skill requires explicit mode on every `open`.

Fix the command by adding one of:

- `--mode headed`
- `--mode headless`

## `open` Fails With `EPERM` On Windows

There are two common causes:

1. the Playwright daemon tried to write under a restricted cache directory
2. the current environment blocked process spawning for browser startup

The wrapper should redirect daemon session data into the workspace, but a restricted sandbox can still block `spawn`.

Interpretation:

- if `doctor` reports daemon directory issues, fix the local daemon path first
- if `doctor` reports spawn or process permission issues, the environment needs different permissions or a less restricted runtime

## Git Bash Works Interactively But Fails In An Agent Host

If `bash --version` works in your normal Git Bash terminal but the same command fails when launched by an agent host, the problem is usually the host restriction, not the wrapper script.

Interpretation:

- interactive Git Bash success means the local Git for Windows install is fine
- agent-side `bash.exe` failure means the current sandbox, security policy, or host integration is blocking Git Bash startup

In that case:

- keep Git Bash support in the published skill
- document PowerShell as the safer fallback for restricted Windows agent hosts
- validate the Git Bash wrapper from a normal Git Bash shell before blaming the skill

## Session Exists But Commands Keep Failing

1. run `snapshot` again
2. run `recover --session <name>`
3. if recovery says the session is gone, reopen with the same `--session` and explicit `--mode`

## Too Many Browser Instances

This usually means the same agent opened multiple sessions instead of reusing one.

Fix:

1. pick one session name for the agent
2. reuse it across steps
3. run `sessions` to inspect active sessions
4. run `cleanup --session <name>` on unused sessions

## PowerShell Says Success After A Failing CLI Call

This is a wrapper bug. The PowerShell entrypoint must capture and return the raw `playwright-cli` exit code immediately.
