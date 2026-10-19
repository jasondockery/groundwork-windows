#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Enable, [switch]$Help)

$ErrorActionPreference = 'Stop'

function Test-DesktopPort {
    param($Ports, [int]$Port)
    foreach ($item in @($Ports)) {
        if ($item -eq 'Any' -or $item -eq "$Port") { return $true }
        if ($item -match '^(\d+)-(\d+)$' -and $Port -ge [int]$Matches[1] -and $Port -le [int]$Matches[2]) { return $true }
    }
    return $false
}

function Read-TailscaleStatus {
    $executable = Join-Path $env:ProgramFiles 'Tailscale/tailscale.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Install the official Tailscale app and sign in before enabling RDP.' }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($executable)
    $process.StartInfo.ArgumentList.Add('status')
    $process.StartInfo.ArgumentList.Add('--json')
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $started = $false
    try {
        $null = $process.Start()
        $started = $true
        $output = $process.StandardOutput.ReadToEndAsync()
        $errorOutput = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) { throw 'Tailscale status exceeded its ten-second deadline.' }
        if ($process.ExitCode -ne 0) { throw 'Tailscale status failed; diagnose the local app before enabling RDP.' }
        if (-not $output.Wait(1000) -or -not $errorOutput.Wait(1000)) { throw 'Tailscale output did not close within its deadline.' }
        return ($output.GetAwaiter().GetResult() | ConvertFrom-Json)
    } finally {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true)
            if (-not $process.WaitForExit(5000)) { throw 'The owned Tailscale status process could not be confirmed stopped.' }
        }
        $process.Dispose()
    }
}

function Assert-WindowsAdministrator {
    if ($env:WSL_DISTRO_NAME -or $env:WSL_INTEROP) { throw 'Run in native Administrator PowerShell, outside WSL.' }
    if (-not $IsWindows) { throw 'Run this native host command in Windows PowerShell 7, not inside WSL, macOS, or Linux.' }
    $identity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open PowerShell 7 as Administrator, then rerun this command.' }
}

function Enable-GroundworkRemoteDesktop {
    Assert-WindowsAdministrator
    $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    $product = (Get-CimInstance Win32_OperatingSystem).ProductType
    if ($product -eq 1 -and $edition -notmatch '^(Professional|Enterprise|Education|IoTEnterprise)') { throw 'This Windows edition cannot host supported native RDP; no settings were changed.' }
    $policy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -ErrorAction SilentlyContinue
    foreach ($setting in @(@{ Name = 'UserAuthentication'; Required = 1 }, @{ Name = 'SecurityLayer'; Required = 2 })) {
        if ($policy -and $policy.PSObject.Properties.Name -contains $setting.Name -and $policy.($setting.Name) -ne $setting.Required) { throw 'Device policy conflicts with required RDP NLA/TLS; no settings were changed.' }
    }
    if ($policy -and $policy.fDenyTSConnections -eq 1) { throw 'Device policy disables Remote Desktop; no settings were changed.' }
    $state = Read-TailscaleStatus
    $address = @($state.Self.TailscaleIPs | Where-Object { $_ -match '^100\.(\d+)\.\d+\.\d+$' -and [int]$Matches[1] -ge 64 -and [int]$Matches[1] -le 127 }) | Select-Object -First 1
    if ($state.BackendState -ne 'Running' -or -not $state.Self.Online -or -not $address) { throw 'Finish local Tailscale sign-in/device approval, then rerun; no RDP settings were changed.' }
    $interface = @(Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -eq $address)
    if ($interface.Count -ne 1) { throw 'Cannot identify one local Tailscale adapter; no RDP settings were changed.' }
    $adapter = Get-NetAdapter -InterfaceIndex $interface[0].InterfaceIndex
    if ($adapter.InterfaceDescription -notmatch 'Tailscale' -and $adapter.Name -notmatch '^Tailscale$') { throw 'The selected IP is not on a recognizable Tailscale adapter.' }
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
    if (@($profiles | Where-Object { -not $_.Enabled -or $_.DefaultInboundAction -ne 'Block' }).Count) { throw 'All active firewall profiles must be enabled with default inbound Block before this setup.' }
    $rdpKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    $port = [int](Get-ItemProperty $rdpKey).PortNumber
    if ($port -lt 1 -or $port -gt 65535) { throw 'The existing RDP port is invalid; no settings were changed.' }
    $ruleName = 'Groundwork-RDP-Tailscale'

    # Do not silently leave a custom broad rule that defeats the interface scope.
    # Keep unrelated application/service rules; fail before mutation for ambiguous
    # RDP-capable rules so their existing owner can reconcile them deliberately.
    foreach ($rule in @(Get-NetFirewallRule -PolicyStore ActiveStore -Enabled True -Direction Inbound -Action Allow)) {
        if ($rule.Name -like 'RemoteDesktop-*' -or $rule.Name -eq $ruleName) { continue }
        $ports = $rule | Get-NetFirewallPortFilter
        if ($ports.Protocol -notin @('TCP', '6', 'Any', '256') -or -not (Test-DesktopPort $ports.LocalPort $port)) { continue }
        $application = $rule | Get-NetFirewallApplicationFilter
        $service = $rule | Get-NetFirewallServiceFilter
        if (($application.Program -in @('Any', 'System') -or $application.Program -match '(^|[\\/])svchost\.exe$') -and $service.Service -in @('Any', 'TermService')) {
            throw ("Existing firewall rule '{0}' may expose RDP outside Tailscale. Reconcile it first; no settings were changed." -f $rule.Name)
        }
    }

    # Build the narrow allow before enabling the server, then retire Microsoft's
    # broad built-in RDP allows. Other service rules and account memberships stay.
    $existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($existing) { $existing | Remove-NetFirewallRule }
    $null = New-NetFirewallRule -Name $ruleName -DisplayName 'Groundwork RDP over Tailscale' -Direction Inbound -Action Allow -Enabled True -Profile Any -InterfaceAlias $adapter.Name -LocalAddress $address -RemoteAddress '100.64.0.0/10' -Protocol TCP -LocalPort $port -EdgeTraversalPolicy Block
    Get-NetFirewallRule -Name 'RemoteDesktop-*' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
    Set-ItemProperty -Path $rdpKey -Name UserAuthentication -Value 1
    Set-ItemProperty -Path $rdpKey -Name SecurityLayer -Value 2
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
    Set-Service -Name TermService -StartupType Automatic
    Start-Service -Name TermService
    if ((Get-Service TermService).Status -ne 'Running') { throw 'The RDP service did not reach Running; inspect Windows service events.' }
    Write-Output ("RDP is enabled with automatic startup on TCP {0}. Use an already allowed Windows account from Windows App/RDP over Tailscale." -f $port)
    Write-Output 'Verify the server certificate and screen/control from another approved device, including after reboot. This command did not authenticate a remote session.'
    Write-Output 'After Tailscale re-enrollment or an adapter/address change, rerun this command to reconcile its scoped firewall rule.'
}

if ($Help -or -not $Enable) {
    Write-Output 'Usage: pwsh -File ./setup-remote-desktop.ps1 -Enable [-WhatIf]'
    Write-Output 'Run once in elevated PowerShell on a supported Windows host after Tailscale sign-in. RDP then starts automatically with Windows.'
    Write-Output 'Keeps NLA/TLS and existing allowed users, scopes the firewall to the Tailscale adapter, and preserves the configured RDP port.'
    Write-Output 'Plan only. Windows Home cannot host native RDP. WSL never enables this host service.'
    return
}
if (-not $PSCmdlet.ShouldProcess('Windows Remote Desktop', 'Enable automatic native RDP with NLA/TLS and a Tailscale-scoped firewall rule')) { return }
Enable-GroundworkRemoteDesktop
