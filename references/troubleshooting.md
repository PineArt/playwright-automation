# Troubleshooting

Use this file when the wrapper fails before a browser action completes.

## `doctor` Reports Missing `npx`

Install Node.js and npm first. The wrapper depends on `npx`.

## `doctor` Shows `(no browsers)`

`doctor` currently prints the output of `playwright-cli list`.

That command lists browser sessions. In this context, `(no browsers)` means
there are no active Playwright CLI browser sessions in the current workspace.
It does not mean Chrome, Firefox, or WebKit are missing from the machine.

This is normal before the first successful `open`, and it can also appear
after sessions have been closed or cleaned up.

If `open` still fails after this, inspect the concrete command error. Browser
startup failures such as `EPERM`, process spawning restrictions, or runtime
installation issues need to be diagnosed from the actual failure path, not
from the session list alone.

## `open` Fails Because Mode Was Not Provided

This is expected. The skill requires explicit mode on every `open`.

Fix the command by adding one of:

- `--mode headed`
- `--mode headless`

## `open` Succeeds But Existing State Disappears

`open` is a create/recreate entrypoint. It can rebuild the page surface for a named session, and that can lose in-memory page state or make earlier state injection look ineffective.

Typical symptom:

- `cookie set` printed success
- then another `open` ran for the same session
- `cookie list` returns `count=0`, or the page is back on the login screen

Use this sequence instead:

1. `cookie set ...`
2. `cookie list ...`
3. `reload --session <name>` for the same URL, or `goto <url> --session <name>` for another route
4. `snapshot --session <name>`
5. verify `/api/auth/session` or an authenticated page element

If the wrapper warns that a session already has metadata, treat a repeated `open` as a state-sensitive action and prefer `goto` or `reload`.

## `open --maximize` Does Not Maximize The Window

The wrapper-level `--maximize` flag is implemented by generating a temporary
Playwright CLI config with:

- `browser.launchOptions.args += ["--start-maximized"]`
- `browser.contextOptions.viewport = null`

This is intended for Chromium-family browsers. It is not supported for
Firefox or WebKit.

Checks:

- make sure `open` also includes `--mode headed`
- avoid pairing `--maximize` with `--browser firefox` or `--browser webkit`
- the generated temporary config is deleted after `open` returns
- if you already set `--config`, ensure that file contains valid JSON so the wrapper can merge into it

## `open` Basic Auth Does Not Log In

Use the wrapper HTTP credential options for browser Basic Auth challenges:

- `--http-username-env <ENV> --http-password-env <ENV>`
- `--http-credentials-file <path>`

The credentials file must be JSON with non-empty string `username` and `password` fields.
Raw credential values are intentionally unsupported on the command line.

Checks:

- confirm both env vars exist and are non-empty
- confirm the server is issuing an HTTP Basic challenge (`WWW-Authenticate: Basic ...`)
- do not use these options for form-based login; use normal page interactions or cookie injection instead

## Cookie Injection Succeeds But The Page Is Not Logged In

`cookie set` success means Playwright accepted a cookie into the browser context. It does not prove the application considers the page authenticated.

Check:

- `cookie list --session <name> --url <origin> --redact` returns the expected cookie count and domain/path
- the app uses the same cookie name that was injected
- `--url`, `--domain`, and `--path` match the page origin and request path
- `--secure` is not used for a plain `http://` local URL
- `sameSite=None` cookies are also `--secure` where the browser requires it
- after injection, you used `reload` or `goto`, not another `open`
- `/api/auth/session` or the visible authenticated UI confirms login state

If cookie storage is correct but the page remains on the login screen, inspect `run network` and `run console` before calling it a product bug.

## `open` Fails With `EPERM` On Windows

There are two common causes:

1. the Playwright daemon tried to write under a restricted cache directory
2. the current environment blocked process spawning for browser startup

The wrapper should redirect daemon session data into the workspace, but a restricted sandbox can still block `spawn`.

Interpretation:

- if `doctor` reports daemon directory issues, fix the local daemon path first
- if `doctor` reports spawn or process permission issues, the environment needs different permissions or a less restricted runtime

If the host supports persisted approval rules and you expect to repeat the same wrapper command:

- prefer approving the concrete wrapper command prefix for future runs
- do not approve a broad shell prefix just to suppress repeated prompts
- if browser launch uses a separate helper binary such as `chrome.exe`, that helper may need its own narrowly scoped persisted approval

## The Skill Was Copied To A Global Skills Directory

That is supported.

The wrappers should still operate on the current working directory, not on the skill installation directory.

If they target the wrong directory:

- run `doctor` and inspect the printed `workspace=...` line
- pass `--workspace <path>` explicitly
- or set `PW_AUTO_WORKSPACE` for the current shell session

## Wrapper Or Helper Path Is Wrong

Prefer the main entrypoint:

- PowerShell: `.\scripts\playwright-automation.ps1 target-first ...`
- Git Bash: `bash ./scripts/playwright-automation.sh target-first ...`

Direct helper paths still work when needed:

- PowerShell: `.\scripts\target-first.ps1 ...`
- Git Bash: `bash ./scripts/target-first.sh ...`

If a command fails because `target-first.ps1` was run from the skill root without the `scripts\` prefix, classify that as an automation failure and retry through `playwright-automation target-first`.

## Selector Strict Mode Or Multiple Matches

Playwright strict-mode failures mean the automation selector is ambiguous. Do not count this as a product verification failure.

Typical symptoms:

- `strict mode violation`
- `resolved to 2 elements`
- a text selector such as `button:has-text('...')` matches both a list row and a detail card

Fix:

- add a container scope such as `table button.windchill-link-button >> text=Shanghai项目`
- use exact role or label locators when available
- re-run `snapshot` and use a ref from the latest snapshot

`target-first` reports this as `automation-failure=selector-not-unique` when the underlying CLI error is recognizable.

## Click Then Immediate Eval Reads Old DOM

React and other SPA frameworks may render asynchronously after a click. A command sequence like click -> immediate `eval` can read the pre-click DOM.

Use one of:

- `playwright-automation target-first click ... --settle-ms 1500`
- `run run-code "async page => { await page.waitForSelector(...); return ... }"`
- `run run-code "async page => page.waitForFunction(...)"` for a DOM predicate

Only judge the product after the wait condition, a fresh `snapshot`, or a screenshot confirms the post-action state.

## Hash Route Does Not Re-run App Checks

Setting `window.location.href` or `window.location.hash` to the same hash route may not trigger a route reload or auth/session re-check.

Use:

- `goto <url#route> --session <name>` when the route is changing
- `reload --session <name>` when the route is the same but cookies or app bootstrap state changed

Then take a fresh `snapshot`.

## `open` Succeeds But Page Content Is Wrong

This is a loaded-page failure class, not necessarily a wrapper failure. `open` and `snapshot` can both succeed while the browser is showing the wrong content.

Common local-dev symptoms:

- a Vite or webpack error overlay
- a blank SPA shell such as an empty `#app` or `#root`
- text such as `502`, `503`, `Bad Gateway`, or `ECONNREFUSED`
- a different application because another process owns the same port

Checks:

- `snapshot --session <name>` and inspect the visible page text
- `run console --session <name>` for build/runtime errors
- `run network --session <name>` for failed API or proxy requests
- verify the exact host and port outside the wrapper when the page content does not match the target app

Keep this classification separate from product UX failure until the expected app route has actually rendered.

## Git Bash Works Interactively But Fails In An Agent Host

If `bash --version` works in your normal Git Bash terminal but the same command fails when launched by an agent host, the problem is usually the host restriction, not the wrapper script.

Interpretation:

- interactive Git Bash success means the local Git for Windows install is fine
- agent-side `bash.exe` failure means the current sandbox, security policy, or host integration is blocking Git Bash startup

In that case:

- keep Git Bash support in the published skill
- document PowerShell as the safer fallback for restricted Windows agent hosts
- validate the Git Bash wrapper from a normal Git Bash shell before blaming the skill

If repeated approvals are the main friction:

- prefer PowerShell when the host already has a persisted approval for the PowerShell wrapper path
- keep approvals path-specific and task-specific so the same rule can be reused safely

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
