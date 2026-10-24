#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Install, [switch]$Help)

$ErrorActionPreference = 'Stop'
$packages = @(
    @{ Name = 'Tailscale'; Id = 'Tailscale.Tailscale'; Source = 'winget' },
    @{ Name = 'Cursor'; Id = 'Anysphere.Cursor'; Source = 'winget' },
    @{ Name = 'Claude'; Id = 'Anthropic.Claude'; Source = 'winget' },
    @{ Name = 'ChatGPT'; Id = '9NT1R1C2HH7J'; Source = 'msstore' },
    @{ Name = 'FreeTube'; Id = 'FreeTube.FreeTube'; Source = 'winget' }
)
if ($Help) {
    Write-Output 'Usage: pwsh -File ./install-host-apps.ps1 [-Install [-WhatIf]]'
    Write-Output 'Default: show the package plan. -Install requests the newest available official packages and accepts their source/package agreements.'
    Write-Output 'Run on the Windows host with PowerShell 7 and App Installer (winget). Sign-in and device approval remain local.'
    return
}
if (-not $Install) {
    $packages | ForEach-Object { Write-Output ("{0}: {1} ({2})" -f $_.Name, $_.Id, $_.Source) }
    Write-Output 'Plan only. Use -Install after reviewing the packages; -Install -WhatIf previews without running winget.'
    return
}
if (-not $IsWindows -and -not $WhatIfPreference) {
    throw 'Run this script on the Windows host, not inside WSL, macOS, or Linux.'
}
$failed = $false
foreach ($package in $packages) {
    if (-not $PSCmdlet.ShouldProcess($package.Name, 'Install or upgrade from its official package source')) { continue }
    $winget = Get-Command winget.exe -CommandType Application -ErrorAction Stop
    $arguments = @('install', '--id', $package.Id, '--exact', '--source', $package.Source,
                   '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    Write-Output ("Requesting {0}; deadline 10 minutes. Ctrl+C cancels the owned installer process tree." -f $package.Name)
    $process = Start-Process -FilePath $winget.Source -ArgumentList $arguments -PassThru -NoNewWindow
    try {
        if (-not $process.WaitForExit(600000)) {
            throw ("{0} exceeded its 10-minute deadline; installation was not verified." -f $package.Name)
        }
        if ($process.ExitCode -ne 0) {
            Write-Warning ("{0}: winget exited {1}. Check package availability, pinning, Store access, and device policy; this is not verified success." -f $package.Name, $process.ExitCode)
            $failed = $true
        } else {
            Write-Output ("{0}: package command completed. Open the app and verify its version and sign-in." -f $package.Name)
        }
    } finally {
        if (-not $process.HasExited) {
            $process.Kill($true)
            if (-not $process.WaitForExit(10000)) { throw 'The owned installer could not be confirmed stopped.' }
        }
        $process.Dispose()
    }
}
if ($failed) { throw 'One or more requested native apps could not be verified. Successful installations remain installed; repair the reported package and rerun.' }
