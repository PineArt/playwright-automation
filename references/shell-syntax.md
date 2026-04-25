# Shell Syntax

Use this file for exact shell commands. `SKILL.md` intentionally keeps examples logical instead of duplicating every command twice.
The examples below assume the repository root is also the skill root. If you copied this repository into a global skills directory, keep the same relative structure and adjust only the absolute path you invoke from.
By default the wrappers use the current working directory as the workspace. Use `--workspace` when you need to target a different directory.

## PowerShell

Set a convenient wrapper variable:

```powershell
$pwauto = ".\scripts\playwright-automation.ps1"
$pwtarget = ".\scripts\target-first.ps1"
```

Recommended direct usage:

```powershell
& .\scripts\playwright-automation.ps1 doctor
& .\scripts\playwright-automation.ps1 open https://example.com --session gallery-a1-headed --mode headed
& .\scripts\playwright-automation.ps1 open https://example.com --session gallery-a1-headed --mode headed --maximize
& .\scripts\playwright-automation.ps1 snapshot --session gallery-a1-headed
& .\scripts\playwright-automation.ps1 screenshot --session gallery-a1-headed --name home
& .\scripts\playwright-automation.ps1 cookie set --session gallery-a1-headed --url http://127.0.0.1:5173 --name comreview_session --value-env TEST_COOKIE --path / --http-only
& .\scripts\playwright-automation.ps1 cookie list --session gallery-a1-headed --url http://127.0.0.1:5173 --redact
& .\scripts\playwright-automation.ps1 cookie clear --session gallery-a1-headed --url http://127.0.0.1:5173 --name comreview_session --path /
& .\scripts\playwright-automation.ps1 run click e3 --session gallery-a1-headed
& .\scripts\playwright-automation.ps1 cli click e3 --session gallery-a1-headed
& .\scripts\target-first.ps1 fill --session gallery-a1-headed --text "alice" --target "#username" --target e12
& .\scripts\playwright-automation.ps1 run fill "#password" "secret" --submit --session gallery-a1-headed
& .\scripts\target-first.ps1 click --session gallery-a1-headed --target "#login" --target e21 --settle-ms 2000
& .\scripts\playwright-automation.ps1 recover --session gallery-a1-headed
& .\scripts\playwright-automation.ps1 cleanup --session gallery-a1-headed
```

Explicit workspace example:

```powershell
& .\scripts\playwright-automation.ps1 --workspace C:\proj\app doctor
```

## Git Bash

Recommended direct usage:

```bash
bash ./scripts/playwright-automation.sh doctor
bash ./scripts/target-first.sh help
bash ./scripts/playwright-automation.sh open https://example.com --session gallery-a1-headed --mode headed
bash ./scripts/playwright-automation.sh open https://example.com --session gallery-a1-headed --mode headed --maximize
bash ./scripts/playwright-automation.sh snapshot --session gallery-a1-headed
bash ./scripts/playwright-automation.sh screenshot --session gallery-a1-headed --name home
export TEST_COOKIE
bash ./scripts/playwright-automation.sh cookie set --session gallery-a1-headed --url http://127.0.0.1:5173 --name comreview_session --value-env TEST_COOKIE --path / --http-only
bash ./scripts/playwright-automation.sh cookie list --session gallery-a1-headed --url http://127.0.0.1:5173 --redact
bash ./scripts/playwright-automation.sh cookie clear --session gallery-a1-headed --url http://127.0.0.1:5173 --name comreview_session --path /
bash ./scripts/playwright-automation.sh run click e3 --session gallery-a1-headed
bash ./scripts/playwright-automation.sh cli click e3 --session gallery-a1-headed
bash ./scripts/target-first.sh fill --session gallery-a1-headed --text "alice" --target "#username" --target e12
bash ./scripts/playwright-automation.sh run fill "#password" "secret" --submit --session gallery-a1-headed
bash ./scripts/target-first.sh click --session gallery-a1-headed --target "#login" --target e21 --settle-ms 2000
bash ./scripts/playwright-automation.sh recover --session gallery-a1-headed
bash ./scripts/playwright-automation.sh cleanup --session gallery-a1-headed
```

Explicit workspace example:

```bash
bash ./scripts/playwright-automation.sh --workspace /c/proj/app doctor
```

## Output Contract

Both shells should preserve:

- the same exit code
- the same artifact path convention
- the same `[pw-auto]` error prefix
- cookie values are redacted unless `cookie list --show-values` is explicitly requested
