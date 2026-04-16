param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
$script:PwAutoScriptDir = $PSScriptRoot

function Fail([string]$Message, [int]$Code = 1) {
    Write-Error "[pw-auto] $Message"
    exit $Code
}

function Resolve-WorkspaceRoot {
    return (Resolve-Path (Join-Path $script:PwAutoScriptDir "..\\..\\..\\..")).Path
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

function Add-ForwardTokens {
    param(
        [ref]$Target,
        [string[]]$Tokens,
        [string[]]$SkipNames
    )

    for ($i = 0; $i -lt $Tokens.Length; $i++) {
        $token = $Tokens[$i]
        $skip = $false
        foreach ($name in $SkipNames) {
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
            $Target.Value += $token
        }
    }
}

function New-Timestamp {
    return (Get-Date).ToString("yyyyMMdd-HHmmss")
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
    & (Resolve-Npx) @listArgs
    $listExit = $LASTEXITCODE
    if ($listExit -ne 0) {
        exit $listExit
    }

    Write-Output "[pw-auto] doctor completed. If browser open still fails with EPERM or spawn errors, the runtime is restricting browser startup."
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

    Build-CommonEnv | Out-Null

    $cli = Build-CliPrefix
    $cli += @("--session", $session, "open", $url)

    Add-ForwardTokens -Target ([ref]$cli) -Tokens $rest -SkipNames @("--mode", "--session")

    if ($mode -eq "headed") {
        $cli += "--headed"
    }

    & (Resolve-Npx) @cli
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Output "[pw-auto] session '$session' open failed. Run recover --session $session or inspect troubleshooting.md."
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
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipNames @("--session")
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
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipNames @("--session", "--name")

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
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipNames @("--session")
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
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipNames @("--session")
    Invoke-PlaywrightCli -CliArguments $cli
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
    Add-ForwardTokens -Target ([ref]$cli) -Tokens $Tokens -SkipNames @("--session")
    & (Resolve-Npx) @cli
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        if ($session) {
            Write-Output "[pw-auto] command failed for session '$session'. Run recover --session $session if the browser is stuck."
        }
    }
    exit $exitCode
}

if (-not $Arguments -or $Arguments.Length -eq 0) {
    Fail "missing command. Use doctor, open, snapshot, screenshot, trace-start, trace-stop, sessions, recover, cleanup, or run."
}

$command = $Arguments[0]
$restArgs = @()
if ($Arguments.Length -gt 1) {
    $restArgs = $Arguments[1..($Arguments.Length - 1)]
}

switch ($command) {
    "doctor" { Invoke-Doctor }
    "open" { Invoke-Open -Tokens $restArgs }
    "snapshot" { Invoke-Snapshot -Tokens $restArgs }
    "screenshot" { Invoke-Screenshot -Tokens $restArgs }
    "trace-start" { Invoke-TraceStart -Tokens $restArgs }
    "trace-stop" { Invoke-TraceStop -Tokens $restArgs }
    "sessions" { Invoke-Sessions }
    "recover" { Invoke-Recover -Tokens $restArgs }
    "cleanup" { Invoke-Cleanup -Tokens $restArgs }
    "run" { Invoke-Run -Tokens $restArgs }
    default { Fail "unknown command '$command'." }
}
