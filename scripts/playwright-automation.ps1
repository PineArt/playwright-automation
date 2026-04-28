param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
$script:PwAutoScriptDir = $PSScriptRoot
$script:PwAutoWorkspaceOverride = ""

function Fail([string]$Message, [int]$Code = 1) {
    Write-Error "[pw-auto] $Message"
    exit $Code
}

function Write-Help {
    param(
        [string]$CommandName = ""
    )

    $lines = @()
    switch ($CommandName) {
        "" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] <command> [args] [options]",
                "[pw-auto] commands:",
                "[pw-auto]   doctor       print workspace paths and playwright-cli session state",
                "[pw-auto]   open         open a URL with explicit --mode and --session",
                "[pw-auto]   goto         navigate an existing session without reopening it",
                "[pw-auto]   reload       reload the current page in an existing session",
                "[pw-auto]   snapshot     capture current refs for an existing session",
                "[pw-auto]   screenshot   save a screenshot under output/playwright/<session>/",
                "[pw-auto]   trace-start  start Playwright tracing for a session",
                "[pw-auto]   trace-stop   stop Playwright tracing for a session",
                "[pw-auto]   cookie       set, list, or clear cookies without echoing values",
                "[pw-auto]   target-first selector-first, ref-fallback fill/click helper",
                "[pw-auto]   sessions     list active Playwright CLI sessions",
                "[pw-auto]   recover      attempt non-destructive recovery for one session",
                "[pw-auto]   cleanup      close one session and optionally delete its data",
                "[pw-auto]   run|cli|raw  pass a subcommand through to playwright-cli",
                "[pw-auto] help:",
                "[pw-auto]   playwright-automation help",
                "[pw-auto]   playwright-automation help <command>",
                "[pw-auto]   playwright-automation <command> --help",
                "[pw-auto] notes:",
                "[pw-auto]   open requires both --session <name> and --mode headed|headless",
                "[pw-auto]   wrappers use the current working directory as workspace unless --workspace is set",
                "[pw-auto]   help output is local and does not invoke npx, browsers, or daemon setup"
            )
        }
        "doctor" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] doctor",
                "[pw-auto] description: print resolved workspace, daemon, artifacts path, CLI version, and session list",
                "[pw-auto] notes:",
                "[pw-auto]   creates local workspace directories if needed",
                "[pw-auto]   does not install browsers"
            )
        }
        "open" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] open <url> --session <name> --mode <headed|headless> [--maximize] [--http-username-env <ENV> --http-password-env <ENV> | --http-credentials-file <path>] [extra playwright-cli open flags]",
                "[pw-auto] description: open a browser page in a named session",
                "[pw-auto] required:",
                "[pw-auto]   <url>",
                "[pw-auto]   --session <name>",
                "[pw-auto]   --mode headed|headless",
                "[pw-auto] notes:",
                "[pw-auto]   headed maps to playwright-cli open --headed",
                "[pw-auto]   --maximize injects a temporary config so Chromium-family browsers start maximized",
                "[pw-auto]   Basic Auth uses Playwright context httpCredentials from env vars or a JSON file",
                "[pw-auto]   --http-credentials-file expects JSON: {`"username`":`"...`",`"password`":`"...`"}",
                "[pw-auto]   raw HTTP credential values are unsupported and credentials are never printed",
                "[pw-auto]   open is a create/recreate entrypoint; use goto or reload for an existing stateful session",
                "[pw-auto]   extra flags are forwarded except wrapper-only options"
            )
        }
        "goto" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] goto <url> --session <name> [extra playwright-cli goto flags]",
                "[pw-auto] description: navigate an existing session without reopening or recreating it",
                "[pw-auto] required:",
                "[pw-auto]   <url>",
                "[pw-auto]   --session <name>",
                "[pw-auto] notes:",
                "[pw-auto]   use after cookie/state injection when the existing page should consume the new state"
            )
        }
        "reload" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] reload --session <name> [extra playwright-cli reload flags]",
                "[pw-auto] description: reload the current page in an existing session",
                "[pw-auto] required:",
                "[pw-auto]   --session <name>",
                "[pw-auto] notes:",
                "[pw-auto]   use after cookie/state injection or same-hash route checks"
            )
        }
        "snapshot" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] snapshot --session <name> [extra playwright-cli snapshot flags]",
                "[pw-auto] description: capture current refs for an existing session",
                "[pw-auto] required:",
                "[pw-auto]   --session <name>"
            )
        }
        "screenshot" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] screenshot --session <name> [--name <label>] [--full-page] [target]",
                "[pw-auto] description: save a screenshot under output/playwright/<session>/",
                "[pw-auto] required:",
                "[pw-auto]   --session <name>",
                "[pw-auto] notes:",
                "[pw-auto]   default name is 'page'",
                "[pw-auto]   prints the saved filename on success"
            )
        }
        "trace-start" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] trace-start --session <name> [extra playwright-cli tracing-start flags]",
                "[pw-auto] description: start Playwright tracing for a session",
                "[pw-auto] required:",
                "[pw-auto]   --session <name>"
            )
        }
        "trace-stop" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] trace-stop --session <name> [extra playwright-cli tracing-stop flags]",
                "[pw-auto] description: stop Playwright tracing for a session",
                "[pw-auto] required:",
                "[pw-auto]   --session <name>"
            )
        }
        "cookie" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] cookie <set|list|clear> --session <name> --url <url> [options]",
                "[pw-auto] description: safely set, list, or clear cookies in an existing Playwright session",
                "[pw-auto] commands:",
                "[pw-auto]   cookie set --session <name> --url <url> --name <cookie_name> --value-env <ENV_NAME> [--path /] [--domain <domain>] [--same-site Strict|Lax|None] [--secure] [--http-only]",
                "[pw-auto]   cookie set --session <name> --url <url> --name <cookie_name> --value-file <path> [same options]",
                "[pw-auto]   cookie clear --session <name> --url <url> --name <cookie_name> [--path /] [--domain <domain>]",
                "[pw-auto]   cookie list --session <name> --url <url> [--redact|--show-values]",
                "[pw-auto] required:",
                "[pw-auto]   --session <name>",
                "[pw-auto]   --url <url>",
                "[pw-auto] notes:",
                "[pw-auto]   values are redacted by default and never printed by set or clear",
                "[pw-auto]   set reads values from --value-env or --value-file; raw --value is intentionally unsupported",
                "[pw-auto]   list redacts values unless --show-values is explicitly provided",
                "[pw-auto]   --url is always required; the wrapper does not guess origin or domain",
                "[pw-auto]   cookie set success only proves injection; verify with cookie list, reload/goto, snapshot, and app auth state"
            )
        }
        "target-first" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] target-first <fill|click> --session <name> [options]",
                "[pw-auto] description: invoke scripts/target-first.ps1 through the main wrapper entrypoint",
                "[pw-auto] examples:",
                "[pw-auto]   playwright-automation target-first fill --session <name> --text <value> --target <stable selector> --target e12",
                "[pw-auto]   playwright-automation target-first click --session <name> --target <stable selector> --target e21 --settle-ms 1500",
                "[pw-auto] notes:",
                "[pw-auto]   order targets as scoped stable selectors first and latest snapshot refs last",
                "[pw-auto]   if a selector is ambiguous, add a container scope, exact role/label, or latest snapshot ref"
            )
        }
        "sessions" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] sessions",
                "[pw-auto] description: list active Playwright CLI sessions for the resolved workspace"
            )
        }
        "recover" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] recover --session <name>",
                "[pw-auto] description: try attach first, then attempt a non-destructive close for the named session",
                "[pw-auto] required:",
                "[pw-auto]   --session <name>",
                "[pw-auto] notes:",
                "[pw-auto]   if close succeeds, reopen explicitly with the same --session and --mode"
            )
        }
        "cleanup" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] cleanup --session <name> [--delete-data]",
                "[pw-auto] description: close one session and optionally delete its stored data",
                "[pw-auto] required:",
                "[pw-auto]   --session <name>",
                "[pw-auto] notes:",
                "[pw-auto]   without --delete-data, artifacts remain under output/playwright/<session>/"
            )
        }
        "run" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] run|cli|raw [--session <name>] <playwright-cli subcommand> [args]",
                "[pw-auto] description: pass a command through to playwright-cli after wrapper environment setup",
                "[pw-auto] notes:",
                "[pw-auto]   use this for click, fill, press, console, network, eval, run-code, and similar commands",
                "[pw-auto]   if --session is present, the wrapper prefixes it before forwarding"
            )
        }
        "cli" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] run|cli|raw [--session <name>] <playwright-cli subcommand> [args]",
                "[pw-auto] description: pass a command through to playwright-cli after wrapper environment setup",
                "[pw-auto] notes:",
                "[pw-auto]   use this for click, fill, press, console, network, eval, run-code, and similar commands",
                "[pw-auto]   if --session is present, the wrapper prefixes it before forwarding"
            )
        }
        "raw" {
            $lines = @(
                "[pw-auto] usage: playwright-automation [--workspace <path>] run|cli|raw [--session <name>] <playwright-cli subcommand> [args]",
                "[pw-auto] description: pass a command through to playwright-cli after wrapper environment setup",
                "[pw-auto] notes:",
                "[pw-auto]   use this for click, fill, press, console, network, eval, run-code, and similar commands",
                "[pw-auto]   if --session is present, the wrapper prefixes it before forwarding"
            )
        }
        default {
            Fail "unknown help topic '$CommandName'."
        }
    }

    foreach ($line in $lines) {
        Write-Output $line
    }
    exit 0
}

function Resolve-WorkspaceRoot {
    $candidate = ""
    if ($script:PwAutoWorkspaceOverride) {
        $candidate = $script:PwAutoWorkspaceOverride
    } elseif ($env:PW_AUTO_WORKSPACE) {
        $candidate = $env:PW_AUTO_WORKSPACE
    } elseif ($env:PLAYWRIGHT_AUTOMATION_WORKSPACE) {
        $candidate = $env:PLAYWRIGHT_AUTOMATION_WORKSPACE
    } else {
        return (Get-Location).Path
    }

    try {
        return (Resolve-Path -LiteralPath $candidate).Path
    } catch {
        Fail "workspace path '$candidate' does not exist."
    }
}

function Resolve-Npx {
    if (Get-Command npx.cmd -ErrorAction SilentlyContinue) {
        return "npx.cmd"
    }
    if (Get-Command npx -ErrorAction SilentlyContinue) {
        return "npx"
    }
    Fail "npx was not found on PATH."
}

function Resolve-Node {
    if (Get-Command node.exe -ErrorAction SilentlyContinue) {
        return "node.exe"
    }
    if (Get-Command node -ErrorAction SilentlyContinue) {
        return "node"
    }
    Fail "node was not found on PATH."
}

function Invoke-PlaywrightCli {
    param(
        [string[]]$CliArguments
    )

    $npxCommand = Resolve-Npx
    & $npxCommand @CliArguments
    $exitCode = $LASTEXITCODE
    exit $exitCode
}

function Get-OptionValue {
    param(
        [string[]]$Tokens,
        [string]$Name
    )

    for ($i = 0; $i -lt $Tokens.Length; $i++) {
        $token = $Tokens[$i]
        if ($token -eq $Name -and $i + 1 -lt $Tokens.Length) {
            return $Tokens[$i + 1]
        }
        if ($token.StartsWith("$Name=")) {
            return $token.Substring($Name.Length + 1)
        }
    }
    return ""
}

function Has-Flag {
    param(
        [string[]]$Tokens,
        [string]$Flag
    )

    foreach ($token in $Tokens) {
        if ($token -eq $Flag) {
            return $true
        }
    }
    return $false
}

function Has-OptionToken {
    param(
        [string[]]$Tokens,
        [string]$Name
    )

    foreach ($token in $Tokens) {
        if ($token -eq $Name -or $token.StartsWith("$Name=")) {
            return $true
        }
    }
    return $false
}

function Has-AnyOpenHttpCredentialsOption {
    param(
        [string[]]$Tokens
    )

    foreach ($name in @("--http-username-env", "--http-password-env", "--http-credentials-file", "--http-username", "--http-password", "--http-credentials")) {
        if (Has-OptionToken -Tokens $Tokens -Name $name) {
            return $true
        }
    }
    return $false
}

function Ensure-SessionOption {
    param(
        [string[]]$Tokens
    )

    $session = Get-OptionValue -Tokens $Tokens -Name "--session"
    if (-not $session) {
        Fail "missing required --session <name>."
    }
    return $session
}

function Build-CommonEnv {
    $workspaceRoot = Resolve-WorkspaceRoot
    $outputBase = Join-Path $workspaceRoot "output"
    $outputRoot = Join-Path $outputBase "playwright"
    $daemonRoot = Join-Path $workspaceRoot ".playwright-daemon"
    $npmCache = Join-Path $workspaceRoot ".npm-cache"

    New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $daemonRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $npmCache | Out-Null

    $env:PLAYWRIGHT_DAEMON_SESSION_DIR = $daemonRoot
    $env:npm_config_cache = $npmCache

    return @{
        WorkspaceRoot = $workspaceRoot
        OutputRoot = $outputRoot
        DaemonRoot = $daemonRoot
    }
}

function Build-CliPrefix {
    return @("--yes", "--package", "@playwright/cli", "playwright-cli")
}

function Test-SessionMetadataExists {
    param(
        [hashtable]$Paths,
        [string]$Session
    )
    $direct = Join-Path $Paths.DaemonRoot "$Session.session"
    if (Test-Path -LiteralPath $direct) {
        return $true
    }
    $matches = Get-ChildItem -LiteralPath $Paths.DaemonRoot -Recurse -Filter "$Session.session" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    return $null -ne $matches
}

function Resolve-ConfigPath {
    param(
        [hashtable]$Paths,
        [string]$ConfigValue
    )

    if (-not $ConfigValue) {
        return ""
    }
    if ([System.IO.Path]::IsPathRooted($ConfigValue)) {
        return $ConfigValue
    }
    return (Join-Path $Paths.WorkspaceRoot $ConfigValue)
}

function Ensure-MapValue {
    param(
        [System.Collections.IDictionary]$Parent,
        [string]$Key
    )

    if (-not $Parent.Contains($Key) -or -not ($Parent[$Key] -is [System.Collections.IDictionary])) {
        $Parent[$Key] = @{}
    }
    return $Parent[$Key]
}

function Resolve-OpenBaseConfigPath {
    param(
        [hashtable]$Paths,
        [string[]]$Tokens
    )

    $configValue = Get-OptionValue -Tokens $Tokens -Name "--config"
    if (Has-OptionToken -Tokens $Tokens -Name "--config") {
        if (-not $configValue) {
            Fail "missing value for --config."
        }
        return (Resolve-ConfigPath -Paths $Paths -ConfigValue $configValue)
    }

    $defaultConfig = Join-Path (Join-Path $Paths.WorkspaceRoot ".playwright") "cli.config.json"
    if (Test-Path -LiteralPath $defaultConfig) {
        return $defaultConfig
    }
    return ""
}

function New-OpenConfig {
    param(
        [hashtable]$Paths,
        [string[]]$Tokens,
        [string]$Session,
        [bool]$Maximize
    )

    $baseConfigPath = Resolve-OpenBaseConfigPath -Paths $Paths -Tokens $Tokens
    $configDir = Join-Path ([System.IO.Path]::GetTempPath()) "pw-auto"
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $safeSession = $Session -replace '[^A-Za-z0-9._-]', '_'
    $tempPath = Join-Path $configDir ("open-{0}-{1}-{2}.json" -f $safeSession, (New-Timestamp), ([guid]::NewGuid().ToString("N")))
    $helperPath = Join-Path $script:PwAutoScriptDir "open-config-helper.js"
    $helperArgs = @("--workspace-root", $Paths.WorkspaceRoot, "--target", $tempPath)
    if ($baseConfigPath) {
        $helperArgs += @("--base", $baseConfigPath)
    }
    if ($Maximize) {
        $helperArgs += "--maximize"
        $browserSelection = Get-OptionValue -Tokens $Tokens -Name "--browser"
        if ($browserSelection) {
            $helperArgs += @("--browser", $browserSelection)
        }
    }
    $helperArgs += "--"
    $helperArgs += $Tokens

    & (Resolve-Node) $helperPath @helperArgs
    $helperExit = $LASTEXITCODE
    if ($helperExit -ne 0) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        exit $helperExit
    }
    return $tempPath
}

function Add-ForwardTokens {
    param(
        [ref]$Target,
        [string[]]$Tokens,
        [string[]]$SkipValueNames = @(),
        [string[]]$SkipFlags = @()
    )

    for ($i = 0; $i -lt $Tokens.Length; $i++) {
        $token = $Tokens[$i]
        $skip = $false
        foreach ($name in $SkipValueNames) {
            if ($token -eq $name) {
                $i += 1
                $skip = $true
                break
            }
            if ($token.StartsWith("$name=")) {
                $skip = $true
                break
            }
        }
        if (-not $skip) {
            foreach ($name in $SkipFlags) {
                if ($token -eq $name) {
                    $skip = $true
                    break
                }
            }
        }
        if (-not $skip) {
            $Target.Value += $token
        }
    }
}

function New-Timestamp {
    return (Get-Date).ToString("yyyyMMdd-HHmmss")
}

function Extract-WrapperOptions {
    param(
        [string[]]$Tokens
    )

    $clean = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Tokens.Length; $i++) {
        $token = $Tokens[$i]
        if ($token -eq "--workspace") {
            if ($i + 1 -ge $Tokens.Length) {
                Fail "missing value for --workspace."
            }
            $script:PwAutoWorkspaceOverride = $Tokens[$i + 1]
            $i += 1
            continue
        }
        if ($token.StartsWith("--workspace=")) {
            $script:PwAutoWorkspaceOverride = $token.Substring("--workspace=".Length)
            continue
        }
        $clean.Add($token)
    }
    return ,$clean.ToArray()
}

function Is-HelpToken {
    param(
        [string]$Token
    )

    return $Token -in @("help", "--help", "-h")
}

function Invoke-Doctor {
    $paths = Build-CommonEnv
    Write-Output "[pw-auto] workspace=$($paths.WorkspaceRoot)"
    Write-Output "[pw-auto] daemon=$($paths.DaemonRoot)"
    Write-Output "[pw-auto] artifacts=$($paths.OutputRoot)"

    Resolve-Npx | Out-Null

    $helpArgs = Build-CliPrefix
    $helpArgs += @("--version")
    & (Resolve-Npx) @helpArgs
    $versionExit = $LASTEXITCODE
    if ($versionExit -ne 0) {
        exit $versionExit
    }

    $listArgs = Build-CliPrefix
    $listArgs += @("list")
    $listOutput = & (Resolve-Npx) @listArgs 2>&1 | Out-String
    $listExit = $LASTEXITCODE
    Write-Output $listOutput.TrimEnd()
    if ($listExit -ne 0) {
        exit $listExit
    }

    Write-Output "[pw-auto] note: 'playwright-cli list' reports browser sessions, not installed browser binaries."
    Write-Output "[pw-auto] doctor completed."
    exit 0
}

function Invoke-Open {
    param(
        [string[]]$Tokens
    )

    if ($Tokens.Length -lt 1) {
        Fail "open requires a URL."
    }

    $url = $Tokens[0]
    $rest = @()
    if ($Tokens.Length -gt 1) {
        $rest = $Tokens[1..($Tokens.Length - 1)]
    }

    $session = Ensure-SessionOption -Tokens $rest
    $mode = Get-OptionValue -Tokens $rest -Name "--mode"
    if (-not $mode) {
        Fail "open requires --mode headed or --mode headless."
    }
    if ($mode -ne "headed" -and $mode -ne "headless") {
        Fail "invalid mode '$mode'. Use headed or headless."
    }
    $maximize = Has-Flag -Tokens $rest -Flag "--maximize"
    if ($maximize -and $mode -ne "headed") {
        Fail "--maximize requires --mode headed."
    }
    $hasHttpCredentials = Has-AnyOpenHttpCredentialsOption -Tokens $rest

    $paths = Build-CommonEnv
    if (Test-SessionMetadataExists -Paths $paths -Session $session) {
        Write-Output "[pw-auto] warning: session '$session' already has metadata; open can recreate page/in-memory state. Use goto or reload for existing cookie/state verification."
    }

    $cli = Build-CliPrefix
    $cli += @("--session", $session, "open", $url)

    $skipValueNames = @("--mode", "--session")
    $skipFlags = @()
    if ($hasHttpCredentials) {
        $skipValueNames += @("--http-username-env", "--http-password-env", "--http-credentials-file", "--http-username", "--http-password", "--http-credentials")
    }
    if (($maximize -or $hasHttpCredentials) -and (Has-OptionToken -Tokens $rest -Name "--config")) {
        $skipValueNames += "--config"
    }
    if ($maximize) {
        $skipFlags += "--maximize"
        if (Has-OptionToken -Tokens $rest -Name "--browser") {
            $skipValueNames += "--browser"
        }
    }
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $rest -SkipValueNames $skipValueNames -SkipFlags $skipFlags

    if ($mode -eq "headed") {
        $cli += "--headed"
    }
    $tempConfigPath = ""
    if ($maximize -or $hasHttpCredentials) {
        Remove-Item Env:PLAYWRIGHT_MCP_VIEWPORT_SIZE -ErrorAction SilentlyContinue
        $tempConfigPath = New-OpenConfig -Paths $paths -Tokens $rest -Session $session -Maximize $maximize
        $cli += @("--config", $tempConfigPath)
    }

    try {
        & (Resolve-Npx) @cli
        $exitCode = $LASTEXITCODE
    } finally {
        if ($tempConfigPath) {
            Remove-Item -LiteralPath $tempConfigPath -Force -ErrorAction SilentlyContinue
        }
    }
    if ($exitCode -ne 0) {
        Write-Output "[pw-auto] session '$session' open failed. Run recover --session $session or inspect troubleshooting.md."
    } elseif ($hasHttpCredentials) {
        Write-Output "[pw-auto] httpCredentials applied username=<redacted> password=<redacted>"
    }
    exit $exitCode
}

function Invoke-Snapshot {
    param(
        [string[]]$Tokens
    )
    $session = Ensure-SessionOption -Tokens $Tokens
    Build-CommonEnv | Out-Null
    $cli = Build-CliPrefix
    $cli += @("--session", $session, "snapshot")
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipValueNames @("--session")
    Invoke-PlaywrightCli -CliArguments $cli
}

function Invoke-Goto {
    param(
        [string[]]$Tokens
    )
    if ($Tokens.Length -lt 1) {
        Fail "goto requires a URL."
    }

    $url = $Tokens[0]
    $rest = @()
    if ($Tokens.Length -gt 1) {
        $rest = $Tokens[1..($Tokens.Length - 1)]
    }
    $session = Ensure-SessionOption -Tokens $rest
    Build-CommonEnv | Out-Null
    $cli = Build-CliPrefix
    $cli += @("--session", $session, "goto", $url)
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $rest -SkipValueNames @("--session")
    Invoke-PlaywrightCli -CliArguments $cli
}

function Invoke-Reload {
    param(
        [string[]]$Tokens
    )
    $session = Ensure-SessionOption -Tokens $Tokens
    Build-CommonEnv | Out-Null
    $cli = Build-CliPrefix
    $cli += @("--session", $session, "reload")
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipValueNames @("--session")
    Invoke-PlaywrightCli -CliArguments $cli
}

function Invoke-Screenshot {
    param(
        [string[]]$Tokens
    )
    $paths = Build-CommonEnv
    $session = Ensure-SessionOption -Tokens $Tokens
    $sessionDir = Join-Path $paths.OutputRoot $session
    New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null

    $name = Get-OptionValue -Tokens $Tokens -Name "--name"
    if (-not $name) {
        $name = "page"
    }
    $filename = Join-Path $sessionDir ("{0}-{1}.png" -f $name, (New-Timestamp))

    $cli = Build-CliPrefix
    $cli += @("--session", $session, "screenshot", "--filename", $filename)
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipValueNames @("--session", "--name")

    & (Resolve-Npx) @cli
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        Write-Output "[pw-auto] screenshot=$filename"
    }
    exit $exitCode
}

function Invoke-TraceStart {
    param(
        [string[]]$Tokens
    )
    $session = Ensure-SessionOption -Tokens $Tokens
    Build-CommonEnv | Out-Null
    $cli = Build-CliPrefix
    $cli += @("--session", $session, "tracing-start")
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipValueNames @("--session")
    Invoke-PlaywrightCli -CliArguments $cli
}

function Invoke-TraceStop {
    param(
        [string[]]$Tokens
    )
    $session = Ensure-SessionOption -Tokens $Tokens
    Build-CommonEnv | Out-Null
    $cli = Build-CliPrefix
    $cli += @("--session", $session, "tracing-stop")
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipValueNames @("--session")
    Invoke-PlaywrightCli -CliArguments $cli
}

function Invoke-Cookie {
    param(
        [string[]]$Tokens
    )
    if ($Tokens.Length -lt 1) {
        Fail "cookie requires set, list, or clear."
    }
    $paths = Build-CommonEnv
    $nodeCommand = ""
    if (Get-Command node.exe -ErrorAction SilentlyContinue) {
        $nodeCommand = "node.exe"
    } elseif (Get-Command node -ErrorAction SilentlyContinue) {
        $nodeCommand = "node"
    } else {
        Fail "node was not found on PATH."
    }
    $helperPath = Join-Path $script:PwAutoScriptDir "cookie-helper.js"
    & $nodeCommand $helperPath "--output-root" $paths.OutputRoot "--workspace-root" $paths.WorkspaceRoot "--daemon-root" $paths.DaemonRoot @Tokens
    $exitCode = $LASTEXITCODE
    exit $exitCode
}

function Invoke-TargetFirst {
    param(
        [string[]]$Tokens
    )
    $helper = Join-Path $script:PwAutoScriptDir "target-first.ps1"
    $previousWorkspace = $env:PW_AUTO_WORKSPACE
    if ($script:PwAutoWorkspaceOverride) {
        $env:PW_AUTO_WORKSPACE = Resolve-WorkspaceRoot
    }
    try {
        & $helper @Tokens
        $exitCode = $LASTEXITCODE
    } finally {
        if ($null -eq $previousWorkspace) {
            Remove-Item Env:PW_AUTO_WORKSPACE -ErrorAction SilentlyContinue
        } else {
            $env:PW_AUTO_WORKSPACE = $previousWorkspace
        }
    }
    exit $exitCode
}

function Invoke-Sessions {
    Build-CommonEnv | Out-Null
    $cli = Build-CliPrefix
    $cli += @("list")
    Invoke-PlaywrightCli -CliArguments $cli
}

function Invoke-Recover {
    param(
        [string[]]$Tokens
    )
    $session = Ensure-SessionOption -Tokens $Tokens
    Build-CommonEnv | Out-Null

    $attach = Build-CliPrefix
    $attach += @("attach", $session, "--session", $session)
    & (Resolve-Npx) @attach
    $attachExit = $LASTEXITCODE
    if ($attachExit -eq 0) {
        Write-Output "[pw-auto] session '$session' attached successfully."
        exit 0
    }

    Write-Output "[pw-auto] attach failed for '$session'. Attempting non-destructive close of the named session."
    $close = Build-CliPrefix
    $close += @("--session", $session, "close")
    & (Resolve-Npx) @close
    $closeExit = $LASTEXITCODE
    if ($closeExit -eq 0) {
        Write-Output "[pw-auto] session '$session' closed. Re-open it explicitly with the same --session and --mode."
        exit 0
    }

    Write-Output "[pw-auto] recovery failed for '$session'. Inspect output/playwright/$session and troubleshooting.md."
    exit $closeExit
}

function Invoke-Cleanup {
    param(
        [string[]]$Tokens
    )
    $session = Ensure-SessionOption -Tokens $Tokens
    Build-CommonEnv | Out-Null

    $close = Build-CliPrefix
    $close += @("--session", $session, "close")
    & (Resolve-Npx) @close
    $closeExit = $LASTEXITCODE
    if ($closeExit -ne 0) {
        exit $closeExit
    }

    if (Has-Flag -Tokens $Tokens -Flag "--delete-data") {
        $delete = Build-CliPrefix
        $delete += @("--session", $session, "delete-data")
        & (Resolve-Npx) @delete
        $deleteExit = $LASTEXITCODE
        exit $deleteExit
    }

    Write-Output "[pw-auto] session '$session' closed. Artifacts remain under output/playwright/$session."
    exit 0
}

function Invoke-Run {
    param(
        [string[]]$Tokens
    )
    if ($Tokens.Length -lt 1) {
        Fail "run requires a playwright-cli command."
    }
    Build-CommonEnv | Out-Null
    $session = Get-OptionValue -Tokens $Tokens -Name "--session"
    $cli = Build-CliPrefix
    if ($session) {
        $cli += @("--session", $session)
    }
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipValueNames @("--session")
    & (Resolve-Npx) @cli
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        if ($session) {
            Write-Output "[pw-auto] command failed for session '$session'. Run recover --session $session if the browser is stuck."
        }
    }
    exit $exitCode
}

$Arguments = Extract-WrapperOptions -Tokens $Arguments

if (-not $Arguments -or $Arguments.Length -eq 0) {
    Write-Help
}

if (Is-HelpToken -Token $Arguments[0]) {
    if ($Arguments.Length -gt 1) {
        Write-Help -CommandName $Arguments[1]
    }
    Write-Help
}

$command = $Arguments[0]
$restArgs = @()
if ($Arguments.Length -gt 1) {
    $restArgs = $Arguments[1..($Arguments.Length - 1)]
}

if ($restArgs.Length -gt 0 -and (Is-HelpToken -Token $restArgs[0])) {
    Write-Help -CommandName $command
}

switch ($command) {
    "--help" { Write-Help }
    "-h" { Write-Help }
    "doctor" { Invoke-Doctor }
    "open" { Invoke-Open -Tokens $restArgs }
    "goto" { Invoke-Goto -Tokens $restArgs }
    "reload" { Invoke-Reload -Tokens $restArgs }
    "snapshot" { Invoke-Snapshot -Tokens $restArgs }
    "screenshot" { Invoke-Screenshot -Tokens $restArgs }
    "trace-start" { Invoke-TraceStart -Tokens $restArgs }
    "trace-stop" { Invoke-TraceStop -Tokens $restArgs }
    "cookie" { Invoke-Cookie -Tokens $restArgs }
    "target-first" { Invoke-TargetFirst -Tokens $restArgs }
    "sessions" { Invoke-Sessions }
    "recover" { Invoke-Recover -Tokens $restArgs }
    "cleanup" { Invoke-Cleanup -Tokens $restArgs }
    "run" { Invoke-Run -Tokens $restArgs }
    "cli" { Invoke-Run -Tokens $restArgs }
    "raw" { Invoke-Run -Tokens $restArgs }
    default { Fail "unknown command '$command'." }
}
