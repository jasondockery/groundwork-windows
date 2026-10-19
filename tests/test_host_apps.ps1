#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '../install-host-apps.ps1'
$tokens = $null; $errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw ($errors | Out-String) }
$pwsh = (Get-Process -Id $PID).Path
foreach ($case in @(@{ Args = @('-Help') }, @{ Args = @() }, @{ Args = @('-Install', '-WhatIf') })) {
    $arguments = $case.Args
    $output = & $pwsh -NoProfile -File $script @arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw $output }
    if ($arguments -notcontains '-Help' -and $output -notmatch 'Tailscale') { throw 'The package plan omitted Tailscale.' }
}
$output = & $pwsh -NoProfile -File $script -UnknownArgument 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) { throw 'An invalid argument was accepted.' }
Write-Output 'Host app parser, help, plan, WhatIf, and invalid-argument contracts passed; no packages were installed.'
exit 0
