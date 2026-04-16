param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)
& (Join-Path $PSScriptRoot "playwright-automation.ps1") @("cleanup") @Arguments
exit $LASTEXITCODE

