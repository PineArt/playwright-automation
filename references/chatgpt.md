# ChatGPT in Chrome on Windows

Use an absolute path to `scripts/chatgpt.mjs` in the installed skill. The helper calls its sibling PowerShell wrapper by default. Set `CHATGPT_PLAYWRIGHT_WRAPPER` to an absolute path to override it.

```powershell
$chatgpt = 'C:\path\to\playwright-automation\scripts\chatgpt.mjs'
$chatgptWorkspace = 'D:\path\to\browser-workspace'
node $chatgpt open --workspace $chatgptWorkspace --session chatgpt-persistent
node $chatgpt probe --workspace $chatgptWorkspace --session chatgpt-persistent
node $chatgpt work --workspace $chatgptWorkspace --session chatgpt-persistent
node $chatgpt ask --workspace $chatgptWorkspace --session chatgpt-persistent --prompt 'Your question'
```

- `open` opens headed Chrome with a persistent profile or reuses the open session. Complete sign-in manually in Chrome when requested.
- `probe` reports the resolved workspace, composer visibility, and the latest completed response when available.
- `work` selects Work and verifies High reasoning effort. It opens the new-chat page if the mode selector is unavailable in the current conversation.
- `ask` submits to the active Chat or Work composer and waits for a new completed response. On a post-submit timeout, check the browser before retrying.

By default, the workspace is the current directory. Relative workspace arguments resolve against that directory. Use the same explicit absolute workspace and session name for every command when sharing a logged-in Chrome session across projects. Different workspaces have separate Playwright sessions, even if their session names match. The workspace directory must already exist. Keep Playwright output and browser state local.

If an older wrapper left a browser running in the user cache, its session name can still occupy the Chrome daemon pipe. Use a fresh session name and sign in manually when migrating to the workspace-scoped wrapper.
