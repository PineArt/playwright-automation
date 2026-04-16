param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)
& (Join-Path $PSScriptRoot "playwright-automation.ps1") @("recover") @Arguments
exit $LASTEXITCODE

