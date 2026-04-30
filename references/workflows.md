# Playwright Automation Workflows

Use this file when the basic loop in `SKILL.md` is not enough.

## Standard Loop

1. Run `doctor`.
2. Open with `--session` and `--mode`.
3. Snapshot.
4. Interact.
5. Re-snapshot when the UI changes.
6. Save evidence in `output/playwright/<session>/`.

`open` is the browser-page create/recreate entrypoint. Once a session exists, prefer `goto` and `reload` so injected cookies, local storage, and current tab state are not lost unexpectedly.

## Remote Or Authenticated Apps

Use this short preflight before automating a live remote app, an LDAP/form-login app, or any app where the local checkout may not be the running surface.

1. Confirm the authoritative URL, host, port, and route outside the wrapper first. Do not infer the target from an old dev-server port or a staging checkout.
2. Open exactly that URL with one named session and explicit mode.
3. Run `snapshot` before choosing selectors. Do not fill a login card from guessed selectors.
4. Verify whether the browser is unauthenticated, form-authenticated, cookie-authenticated, or behind HTTP Basic Auth before running UI checks.
5. If authenticated browser evidence is required and the browser is unauthenticated, run the manual-first login flow before falling back to non-browser evidence or recording a browser-auth gap.
6. After manual login, state load, or cookie injection, use `reload` or `goto`, then `snapshot`, then an app-state check such as `/api/auth/session` or a visible authenticated element.
7. If the page content is unexpected, inspect the loaded page, console, network, and exact origin before treating it as a product bug.

For remote apps such as a daemonized SPA or a Django portal, the browser result is only meaningful after the real running URL and login state have been proven. A successful `open` plus a login screen, 302, error overlay, blank shell, or wrong port is not yet product verification.

Only record a browser-auth gap after one of these has happened: headed login is unavailable in the current environment, the human cannot complete login, the human has not signaled that login is complete, or the post-login auth probe still fails. Otherwise, ask the human to complete login first.

## Manual-First Login Reuse

Use this as the default authenticated workflow for real accounts, SSO, MFA, CAPTCHA, or any app where credentials should not pass through agent commands.

### Same Live Session

1. Open a headed session: `playwright-automation open <url> --session <name> --mode headed`.
2. The human enters credentials directly in the browser and completes any MFA, SSO, or CAPTCHA.
3. The human tells the agent that login is complete.
4. The agent runs `snapshot` and an app-specific auth probe, such as `/api/auth/session` or a visible authenticated element.
5. Continue in the same named session with `goto` or `reload`; do not call `open` again unless you intentionally recreate the page surface.

This path only works while the Playwright session remains alive. If the browser, daemon, or machine restarts, use the saved-state path below.

### Saved State Across Runs

After the same live session is authenticated and verified:

```text
playwright-automation state save --session local-a1-headed
```

The wrapper prints the state file path. The file can contain cookies, localStorage tokens, and sessionStorage values. It is stored under ignored `output/playwright/<session>/` by default, but it is still a credential file; delete or rotate it after use.

To reuse it later:

```text
playwright-automation open <url> --session local-a1-headed --mode headed
playwright-automation state load --session local-a1-headed --file output/playwright/local-a1-headed/storage-state-20260429-120000.json
playwright-automation reload --session local-a1-headed
playwright-automation snapshot --session local-a1-headed
playwright-automation run run-code "async page => ({ status: (await (await page.request.get('<auth-session-url>')).status()), url: page.url(), title: await page.title() })" --session local-a1-headed
```

`state load` success only proves the browser context accepted stored state. Server-side sessions can expire, be revoked, or require fresh CSRF flows. Always run `reload` or `goto`, then `snapshot`, then an app-specific auth probe before product checks.

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
4. Use `playwright-automation target-first fill --text ... --target "<stable selector>" --target e12`.
5. For submit-oriented flows, prefer `run fill ... --submit` on the final editable field or `run press Enter`.
6. If a button is still needed, use `playwright-automation target-first click --target "<stable selector>" --target e21 --settle-ms 1500`.
7. `snapshot`.
8. `screenshot --name submitted`.

Example:

```text
playwright-automation target-first fill --session login-headed --text my-user --target "#username" --target e12
playwright-automation run fill "#password" my-pass --submit --session login-headed
playwright-automation run eval "() => new Promise((resolve) => setTimeout(resolve, 2000))" --session login-headed
playwright-automation snapshot --session login-headed
```

For React, Vue, or other SPA flows, add an explicit settle or wait after clicks that trigger routing, list expansion, or async rendering. A click followed immediately by `eval` can read the old DOM and should not be treated as a product failure by itself.

## Cookie Login State

Use this when a local app accepts an existing session cookie and you need to verify UI after login without running the form login flow.

```text
playwright-automation open http://127.0.0.1:5173 --session local-a1-headless --mode headless
playwright-automation cookie set --session local-a1-headless --url http://127.0.0.1:5173 --name app_session --value-env APP_SESSION --path / --http-only
playwright-automation cookie list --session local-a1-headless --url http://127.0.0.1:5173 --redact
playwright-automation reload --session local-a1-headless
playwright-automation snapshot --session local-a1-headless
playwright-automation run run-code "async page => ({ status: (await (await page.request.get('http://127.0.0.1:5173/api/auth/session')).status()), url: page.url(), title: await page.title() })" --session local-a1-headless
```

If `cookie set` succeeds but `cookie list` returns `count=0`, or the page still shows the login view after `reload`/`goto`, classify the current result as session-state verification failure, not an authenticated UI failure. Re-check `--url`, `--domain`, `--path`, `--secure`, `sameSite`, and whether the app reads a different cookie name.

Do not set a cookie and then call `open` again unless you are intentionally recreating the browser page. Use `reload` for the same URL, or `goto <url> --session <name>` for a route change inside the existing session.

## Wait Templates

Use `--settle-ms` for simple post-action delay:

```text
playwright-automation target-first click --session local-a1-headless --target "table button.windchill-link-button >> text=Shanghai项目" --target e42 --settle-ms 3000
```

Wait for a selector:

```text
playwright-automation run run-code "async page => { await page.waitForSelector('.flush-panel', { timeout: 5000 }); return await page.locator('.flush-panel').count(); }" --session local-a1-headless
```

Wait for text:

```text
playwright-automation run run-code "async page => { await page.getByText('交付件', { exact: true }).waitFor({ timeout: 5000 }); return true; }" --session local-a1-headless
```

Wait for a DOM predicate:

```text
playwright-automation run run-code "async page => page.waitForFunction(() => document.querySelectorAll('.flush-panel').length > 0, null, { timeout: 5000 })" --session local-a1-headless
```

Check an auth/session endpoint from the page context:

```text
playwright-automation run run-code "async page => { const res = await page.request.get('http://127.0.0.1:5173/api/auth/session'); return { status: res.status(), body: await res.text() }; }" --session local-a1-headless
```

## Hash Routes

Hash route changes are SPA state changes, not full browser reloads.

- `open <url#route>` may create or recreate the browser page.
- `goto <url#route> --session <name>` navigates inside the existing session.
- Setting `window.location.href` or `window.location.hash` to the same hash may not rerun auth checks or route loaders.
- `reload --session <name>` forces the current route to re-read cookies and app bootstrap state.

After cookie injection, prefer `reload` for the same hash route or `goto` for a materially different route, then `snapshot` and app-state verification.

## UI Debugging

When a flow is visually wrong:

1. Prefer `--mode headed`.
2. Use `snapshot`.
3. Use `screenshot --name before-fix`.
4. If refs are flaky, retry the step with selector-first ordering through `target-first`.
5. Use `run console` or `run network`.
6. Use `trace-start` before suspicious actions.
7. Use `trace-stop` after reproducing.

For text selectors, scope first. Prefer selectors like `table button.windchill-link-button >> text=Shanghai项目`, exact role/label locators when available, or a ref from the latest snapshot. If `target-first` reports `automation-failure=selector-not-unique`, fix the automation selector before judging the product.

## Result Classification

Treat these as automation failures:

- wrong wrapper path or missing script entrypoint
- session not open, stale, or unexpectedly recreated
- selector strict-mode violation or multi-match ambiguity
- click/eval race before React or route rendering settles
- using an old snapshot ref after navigation or DOM refresh

Treat a product verification failure as valid only after the automation has:

- used the expected existing session
- verified cookies/storage or login state when relevant
- waited for the async UI condition that should appear
- captured a fresh snapshot or screenshot
- checked console/network/auth endpoint when the UI state is ambiguous

## Data Extraction

Use `snapshot` first and prefer standard commands.
Use `run eval ...` or `run run-code ...` only when the CLI does not already expose the needed behavior.

Keep inline JavaScript small. Long one-shot strings are brittle in PowerShell and harder to diagnose than a selector command, a wait template, or a short probe.

Use the CLI's accepted shapes:

```text
playwright-automation run eval "() => document.title" --session local-a1-headless
playwright-automation run eval "(element) => element.textContent" "button.submit" --session local-a1-headless
playwright-automation run run-code "async page => ({ url: page.url(), title: await page.title() })" --session local-a1-headless
```

Use `eval` for small page or element expressions; when a target is provided, the function receives that element as its single argument. Use `run-code` when you need the Playwright `page` object, waits, requests, or multiple operations.

Do not use object-destructuring forms such as `({ page }) => ...` unless the underlying CLI command explicitly documents that shape for the command you are invoking.

## Parallel Work

This skill does not support multiple sessions for the same agent.
If an agent needs a clean slate, close or clean up the old session first.
