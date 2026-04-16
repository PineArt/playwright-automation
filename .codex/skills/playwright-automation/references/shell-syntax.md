# Shell Syntax

Use this file for exact shell commands. `SKILL.md` intentionally keeps examples logical instead of duplicating every command twice.

## PowerShell

Set a convenient wrapper variable:

```powershell
$pwauto = ".\.codex\skills\playwright-automation\scripts\playwright-automation.ps1"
```

Recommended direct usage:

```powershell
& .\.codex\skills\playwright-automation\scripts\playwright-automation.ps1 doctor
& .\.codex\skills\playwright-automation\scripts\playwright-automation.ps1 open https://example.com --session gallery-a1-headed --mode headed
& .\.codex\skills\playwright-automation\scripts\playwright-automation.ps1 snapshot --session gallery-a1-headed
& .\.codex\skills\playwright-automation\scripts\playwright-automation.ps1 screenshot --session gallery-a1-headed --name home
& .\.codex\skills\playwright-automation\scripts\playwright-automation.ps1 run click e3 --session gallery-a1-headed
& .\.codex\skills\playwright-automation\scripts\playwright-automation.ps1 recover --session gallery-a1-headed
& .\.codex\skills\playwright-automation\scripts\playwright-automation.ps1 cleanup --session gallery-a1-headed
```

## Git Bash

Recommended direct usage:

```bash
bash ./.codex/skills/playwright-automation/scripts/playwright-automation.sh doctor
bash ./.codex/skills/playwright-automation/scripts/playwright-automation.sh open https://example.com --session gallery-a1-headed --mode headed
bash ./.codex/skills/playwright-automation/scripts/playwright-automation.sh snapshot --session gallery-a1-headed
bash ./.codex/skills/playwright-automation/scripts/playwright-automation.sh screenshot --session gallery-a1-headed --name home
bash ./.codex/skills/playwright-automation/scripts/playwright-automation.sh run click e3 --session gallery-a1-headed
bash ./.codex/skills/playwright-automation/scripts/playwright-automation.sh recover --session gallery-a1-headed
bash ./.codex/skills/playwright-automation/scripts/playwright-automation.sh cleanup --session gallery-a1-headed
```

## Output Contract

Both shells should preserve:

- the same exit code
- the same artifact path convention
- the same `[pw-auto]` error prefix
