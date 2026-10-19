#Requires -Version 7.0
# Native cmdlets are replaced at their execution boundary. No test starts a
# service, edits the registry, or changes the runner's network/firewall.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../setup-remote-desktop.ps1') -Help
$script:changes = [System.Collections.Generic.List[object]]::new()
$script:fixtureCase = 'success'
function Assert-WindowsAdministrator { }
function Read-TailscaleStatus {
    $state = if ($script:fixtureCase -eq 'offline') { 'NeedsLogin' } else { 'Running' }
    return [pscustomobject]@{ BackendState = $state; Self = [pscustomobject]@{ Online = $true; TailscaleIPs = @('100.64.0.2') } }
}
function Get-ItemProperty {
    param($Path, $ErrorAction)
    if ($Path -like '*Policies*') {
        if ($script:fixtureCase -eq 'policy') { return [pscustomobject]@{ UserAuthentication = 0 } }
        return $null
    }
    return [pscustomobject]@{ EditionID = 'Professional'; PortNumber = 3389 }
}
function Get-CimInstance { param($ClassName) return [pscustomobject]@{ ProductType = 1 } }
function Get-NetIPAddress { param($AddressFamily) return [pscustomobject]@{ IPAddress = '100.64.0.2'; InterfaceIndex = 42 } }
function Get-NetAdapter { param($InterfaceIndex) return [pscustomobject]@{ Name = 'Tailscale'; InterfaceDescription = 'Tailscale Tunnel' } }
function Get-NetFirewallProfile {
    param($PolicyStore)
    return [pscustomobject]@{ Enabled = ($script:fixtureCase -ne 'firewall-off'); DefaultInboundAction = 'Block' }
}
function Get-NetFirewallRule {
    param($Name, $PolicyStore, $Enabled, $Direction, $Action, $ErrorAction)
    if ($Name -eq 'Groundwork-RDP-Tailscale') { return $null }
    if ($Name -eq 'RemoteDesktop-*') { return [pscustomobject]@{ Name = 'RemoteDesktop-UserMode-In-TCP' } }
    if ($script:fixtureCase -eq 'broad-rule') { return [pscustomobject]@{ Name = 'OwnerBroadRule' } }
    return [pscustomobject]@{ Name = 'UnrelatedSSH' }
}
function Get-NetFirewallPortFilter {
    param([Parameter(ValueFromPipeline)]$Rule)
    process { return [pscustomobject]@{ Protocol = 'TCP'; LocalPort = $(if ($Rule.Name -eq 'OwnerBroadRule') { 'Any' } else { '22' }) } }
}
function Get-NetFirewallApplicationFilter { param([Parameter(ValueFromPipeline)]$Rule) process { return [pscustomobject]@{ Program = 'Any' } } }
function Get-NetFirewallServiceFilter { param([Parameter(ValueFromPipeline)]$Rule) process { return [pscustomobject]@{ Service = 'Any' } } }
function New-NetFirewallRule {
    param($Name, $DisplayName, $Direction, $Action, $Enabled, $Profile, $InterfaceAlias, $LocalAddress, $RemoteAddress, $Protocol, $LocalPort, $EdgeTraversalPolicy)
    $script:changes.Add([pscustomobject]@{ Operation = 'allow'; Interface = $InterfaceAlias; Local = $LocalAddress; Remote = $RemoteAddress; Protocol = $Protocol; Port = $LocalPort })
}
function Remove-NetFirewallRule { param([Parameter(ValueFromPipeline)]$Rule) process { $script:changes.Add([pscustomobject]@{ Operation = 'remove' }) } }
function Disable-NetFirewallRule { param([Parameter(ValueFromPipeline)]$Rule) process { $script:changes.Add([pscustomobject]@{ Operation = 'disable'; Name = $Rule.Name }) } }
function Set-ItemProperty { param($Path, $Name, $Value) $script:changes.Add([pscustomobject]@{ Operation = 'registry'; Name = $Name; Value = $Value }) }
function Set-Service { param($Name, $StartupType) $script:changes.Add([pscustomobject]@{ Operation = 'startup'; Startup = $StartupType }) }
function Start-Service { param($Name) $script:changes.Add([pscustomobject]@{ Operation = 'start' }) }
function Get-Service { param($Name) return [pscustomobject]@{ Status = 'Running' } }

foreach ($case in @('offline', 'policy', 'firewall-off', 'broad-rule')) {
    $script:fixtureCase = $case
    $script:changes.Clear()
    $failed = $false
    try { Enable-GroundworkRemoteDesktop } catch { $failed = $true }
    if (-not $failed) { throw "Unsafe precondition '$case' was accepted." }
    if ($script:changes.Count -ne 0) { throw "Unsafe precondition '$case' mutated host settings." }
}
$script:fixtureCase = 'success'
$script:changes.Clear()
Enable-GroundworkRemoteDesktop
$allow = @($script:changes | Where-Object Operation -eq 'allow')
if ($allow.Count -ne 1 -or $allow[0].Interface -ne 'Tailscale' -or $allow[0].Local -ne '100.64.0.2' -or $allow[0].Remote -ne '100.64.0.0/10' -or $allow[0].Protocol -ne 'TCP' -or $allow[0].Port -ne 3389) { throw 'RDP firewall scope widened.' }
if (-not @($script:changes | Where-Object { $_.Operation -eq 'registry' -and $_.Name -eq 'UserAuthentication' -and $_.Value -eq 1 }).Count) { throw 'NLA was not required.' }
if (-not @($script:changes | Where-Object { $_.Operation -eq 'registry' -and $_.Name -eq 'SecurityLayer' -and $_.Value -eq 2 }).Count) { throw 'TLS was not required.' }
if (-not @($script:changes | Where-Object { $_.Operation -eq 'startup' -and $_.Startup -eq 'Automatic' }).Count) { throw 'RDP was not configured for automatic startup.' }
if ($script:changes[0].Operation -ne 'allow') { throw 'The service changed before its scoped firewall rule.' }
Write-Output 'RDP offline/policy/firewall rejection, authenticated scope, and automatic startup contracts passed with mocked native commands.'
