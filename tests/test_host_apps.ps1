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
$desktop = Join-Path $PSScriptRoot '../setup-remote-desktop.ps1'
$null = [System.Management.Automation.Language.Parser]::ParseFile($desktop, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw ($errors | Out-String) }
foreach ($case in @(@{ Args = @('-Help') }, @{ Args = @() }, @{ Args = @('-Enable', '-WhatIf') })) {
    $arguments = $case.Args
    $output = & $pwsh -NoProfile -File $desktop @arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw $output }
    if ($output -notmatch 'RDP') { throw 'The native RDP plan omitted its service.' }
}
. $desktop -Help
if (-not (Test-DesktopPort @('3000-4000') 3389)) { throw 'RDP range rule was missed.' }
if (-not (Test-DesktopPort @('Any') 3389)) { throw 'A broad port rule was missed.' }
if (Test-DesktopPort @('22', '80', '443') 3389) { throw 'Unrelated ports were treated as RDP.' }
Write-Output 'Remote desktop parser, no-mutation plans and firewall port classification passed.'
& (Join-Path $PSScriptRoot 'test_remote_desktop.ps1')
exit 0
