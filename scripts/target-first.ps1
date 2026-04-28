param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message, [int]$Code = 1) {
    Write-Error "[pw-auto] $Message"
    exit $Code
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

function Get-OptionValues {
    param(
        [string[]]$Tokens,
        [string]$Name
    )

    $values = @()
    for ($i = 0; $i -lt $Tokens.Length; $i++) {
        $token = $Tokens[$i]
        if ($token -eq $Name -and $i + 1 -lt $Tokens.Length) {
            $values += $Tokens[$i + 1]
            $i += 1
            continue
        }
        if ($token.StartsWith("$Name=")) {
            $values += $token.Substring($Name.Length + 1)
        }
    }
    return ,$values
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

function Invoke-WrapperCapture {
    param(
        [string[]]$WrapperArguments
    )

    $wrapper = Join-Path $PSScriptRoot "playwright-automation.ps1"
    $output = & $wrapper @WrapperArguments 2>&1 | Out-String
    return @{
        Output = $output.TrimEnd()
        ExitCode = $LASTEXITCODE
    }
}

function Test-SelectorNotUnique {
    param(
        [string]$Output
    )
    if (-not $Output) {
        return $false
    }
    return $Output -match '(?i)strict mode violation|resolved to \d+ elements|locator.*matched|matched \d+ elements|matches \d+ elements'
}

function Show-SelectorNotUniqueDiagnostic {
    param(
        [string]$Target
    )
    Write-Output "[pw-auto] automation-failure=selector-not-unique target=$Target"
    Write-Output "[pw-auto] suggestion=add a container scope, use an exact role/label selector, or fall back to a ref from the latest snapshot"
}

function Show-Help {
    @(
        "[pw-auto] usage:",
        "[pw-auto]   target-first.ps1 fill --session <name> --text <value> --target <target> [--target <target> ...] [--submit] [--settle-ms <ms>]",
        "[pw-auto]   target-first.ps1 click --session <name> --target <target> [--target <target> ...] [button] [--settle-ms <ms>] [--modifiers <keys>]",
        "[pw-auto] notes:",
        "[pw-auto]   order targets as stable selectors first and snapshot refs last",
        "[pw-auto]   fill and click stop on the first successful target",
        "[pw-auto]   --settle-ms must be a non-negative integer and runs wrapper settle logic via eval after success"
    ) | ForEach-Object { Write-Output $_ }
    exit 0
}

if (-not $Arguments -or $Arguments.Length -eq 0 -or $Arguments[0] -in @("help", "--help", "-h")) {
    Show-Help
}

$command = $Arguments[0]
$tokens = @()
if ($Arguments.Length -gt 1) {
    $tokens = $Arguments[1..($Arguments.Length - 1)]
}

$session = Get-OptionValue -Tokens $tokens -Name "--session"
if (-not $session) {
    Fail "missing required --session <name>."
}

$targets = Get-OptionValues -Tokens $tokens -Name "--target"
if (-not $targets -or $targets.Length -eq 0) {
    Fail "missing required --target <target>."
}

$settleMs = Get-OptionValue -Tokens $tokens -Name "--settle-ms"
if ((Has-OptionToken -Tokens $tokens -Name "--settle-ms") -and ((-not $settleMs) -or $settleMs.StartsWith("--"))) {
    Fail "missing value for --settle-ms."
}
if ($settleMs -and $settleMs -notmatch '^[0-9]+$') {
    Fail "--settle-ms must be a non-negative integer number of milliseconds."
}

switch ($command) {
    "fill" {
        $text = Get-OptionValue -Tokens $tokens -Name "--text"
        if (-not $text) {
            Fail "fill requires --text <value>."
        }

        $submit = Has-Flag -Tokens $tokens -Flag "--submit"
        $lastFailure = ""
        $selectorNotUniqueTarget = ""
        foreach ($target in $targets) {
            $wrapperArgs = @("run", "fill", $target, $text, "--session", $session)
            if ($submit) {
                $wrapperArgs += "--submit"
            }
            $result = Invoke-WrapperCapture -WrapperArguments $wrapperArgs
            if ($result.ExitCode -eq 0) {
                if ($result.Output) {
                    Write-Output $result.Output
                }
                Write-Output "[pw-auto] resolved-target=$target"
                if ($settleMs) {
                    & (Join-Path $PSScriptRoot "playwright-automation.ps1") run eval "() => new Promise((resolve) => setTimeout(resolve, $settleMs))" --session $session
                    exit $LASTEXITCODE
                }
                exit 0
            }
            $lastFailure = $result.Output
            if (-not $selectorNotUniqueTarget -and (Test-SelectorNotUnique -Output $lastFailure)) {
                $selectorNotUniqueTarget = $target
            }
        }

        Write-Output "[pw-auto] target-first fill failed. None of the provided targets worked for session '$session'."
        if ($selectorNotUniqueTarget) {
            Show-SelectorNotUniqueDiagnostic -Target $selectorNotUniqueTarget
        }
        if ($lastFailure) {
            Write-Output $lastFailure
        }
        exit 1
    }
    "click" {
        $button = ""
        $modifiers = Get-OptionValue -Tokens $tokens -Name "--modifiers"
        for ($i = 0; $i -lt $tokens.Length; $i++) {
            $token = $tokens[$i]
            if ($token.StartsWith("--")) {
                if ($token -in @("--session", "--target", "--modifiers", "--settle-ms")) {
                    $i += 1
                }
                continue
            }
            if ($token -in $targets -or $token -eq $session) {
                continue
            }
            $button = $token
            break
        }

        $lastFailure = ""
        $selectorNotUniqueTarget = ""
        foreach ($target in $targets) {
            $wrapperArgs = @("run", "click", $target, "--session", $session)
            if ($button) {
                $wrapperArgs = @("run", "click", $target, $button, "--session", $session)
            }
            if ($modifiers) {
                $wrapperArgs += @("--modifiers", $modifiers)
            }
            $result = Invoke-WrapperCapture -WrapperArguments $wrapperArgs
            if ($result.ExitCode -eq 0) {
                if ($result.Output) {
                    Write-Output $result.Output
                }
                Write-Output "[pw-auto] resolved-target=$target"
                if ($settleMs) {
                    & (Join-Path $PSScriptRoot "playwright-automation.ps1") run eval "() => new Promise((resolve) => setTimeout(resolve, $settleMs))" --session $session
                    exit $LASTEXITCODE
                }
                exit 0
            }
            $lastFailure = $result.Output
            if (-not $selectorNotUniqueTarget -and (Test-SelectorNotUnique -Output $lastFailure)) {
                $selectorNotUniqueTarget = $target
            }
        }

        Write-Output "[pw-auto] target-first click failed. None of the provided targets worked for session '$session'."
        if ($selectorNotUniqueTarget) {
            Show-SelectorNotUniqueDiagnostic -Target $selectorNotUniqueTarget
        }
        if ($lastFailure) {
            Write-Output $lastFailure
        }
        exit 1
    }
    default {
        Fail "unknown command '$command'. Use fill or click."
    }
}
