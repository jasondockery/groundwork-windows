#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Install,
    [switch]$SetDefaultBrowser,
    [switch]$ApplyBrowserPolicy,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$packages = @(
    @{ Name = 'Tailscale'; Id = 'Tailscale.Tailscale'; Source = 'winget' },
    @{ Name = 'Cursor'; Id = 'Anysphere.Cursor'; Source = 'winget' },
    @{ Name = 'Claude'; Id = 'Anthropic.Claude'; Source = 'winget' },
    @{ Name = 'ChatGPT'; Id = '9NT1R1C2HH7J'; Source = 'msstore' },
    @{ Name = 'FreeTube'; Id = 'FreeTube.FreeTube'; Source = 'winget' },
    @{ Name = 'Brave'; Id = 'Brave.Brave'; Source = 'winget' }
)
$script:BravePolicyKey = 'HKLM:\Software\Policies\BraveSoftware\Brave'
$script:BitwardenPasswordManagerWhen = 'Bitwarden is the password manager.'
$script:UrlAssociationSource = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

namespace GroundworkHostApps {
    public static class UrlAssociation {
        [DllImport("Shlwapi.dll", CharSet = CharSet.Unicode)]
        private static extern int AssocQueryString(int flags, int kind, string assoc, string extra, StringBuilder output, ref int size);

        public static string Lookup(string protocol, int kind) {
            var output = new StringBuilder(1024);
            int size = output.Capacity;
            int hr = AssocQueryString(0, kind, protocol, null, output, ref size);
            if (hr != 0) {
                throw new InvalidOperationException("Association lookup failed.");
            }
            return output.ToString();
        }
    }
}
'@

function Test-HostAppsElevated {
    if ($env:WSL_DISTRO_NAME -or $env:WSL_INTEROP) { return $false }
    if (-not $IsWindows) { return $false }
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-GroundworkBraveSpec {
    param([string]$RepoRoot = $PSScriptRoot)
    $path = Join-Path $RepoRoot 'core/browser/brave.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Missing core/browser/brave.json. Run: git submodule update --init'
    }
    $spec = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($spec.schemaVersion -ne 1) {
        throw "core/browser/brave.json schemaVersion '$($spec.schemaVersion)' is not 1. No Brave policies were written."
    }
    return $spec
}

function ConvertTo-BraveRegistryValue {
    param($Value)
    if ($Value -is [bool]) {
        $data = [int][bool]$Value
        return [pscustomobject]@{ Type = 'DWord'; Data = $data; Label = "DWORD $data" }
    }
    if ($Value -is [string]) {
        if ($Value -match '[\u0000-\u001F]') {
            throw 'A Brave policy string contains a control character. No Brave policies were written.'
        }
        return [pscustomobject]@{ Type = 'String'; Data = $Value; Label = "String $Value" }
    }
    throw "Unsupported Brave policy value type $($Value.GetType().FullName). No Brave policies were written."
}

function Get-ApplicableBravePolicies {
    param($Spec)
    # A when condition is skipped unless this installer can show it is true.
    # Unknown conditions fail closed so a new row is not written by guesswork.
    $applicable = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($policy in @($Spec.policies)) {
        $name = [string]$policy.name
        if ($name -notmatch '^[A-Za-z][A-Za-z0-9]{0,127}$') {
            throw "Brave policy name '$name' is not a registry value name. No Brave policies were written."
        }
        if ($seen.ContainsKey($name)) {
            throw "Brave policy '$name' is listed more than once. No Brave policies were written."
        }
        $seen[$name] = $true
        $null = ConvertTo-BraveRegistryValue $policy.value
        $when = $null
        if ($policy.PSObject.Properties.Name -contains 'when') { $when = [string]$policy.when }
        if (-not [string]::IsNullOrWhiteSpace($when)) {
            if ($when -ne $script:BitwardenPasswordManagerWhen) {
                throw "Brave policy '$name' has a when condition this installer does not evaluate. No Brave policies were written."
            }
            $offered = @($Spec.extensions | Where-Object { $_.name -eq 'Bitwarden' -and $_.install -eq 'offer' })
            if ($offered.Count -ne 1) { continue }
        }
        $applicable.Add($policy)
    }
    return @($applicable.ToArray())
}

function Set-BravePolicyValue {
    param([string]$Name, $Converted)
    if (-not $IsWindows) { throw 'Run this script on the Windows host. No Brave policies were written.' }
    if (-not (Test-Path -LiteralPath $script:BravePolicyKey)) {
        New-Item -Path $script:BravePolicyKey -Force | Out-Null
    }
    $propertyType = if ($Converted.Type -eq 'DWord') { 'DWord' } elseif ($Converted.Type -eq 'String') { 'String' } else {
        throw "Unsupported registry type $($Converted.Type). No further Brave policies were written."
    }
    New-ItemProperty -LiteralPath $script:BravePolicyKey -Name $Name -PropertyType $propertyType -Value $Converted.Data -Force | Out-Null
}

function Invoke-GroundworkBravePolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $WhatIfPreference) {
        if (-not (Test-HostAppsElevated)) {
            throw 'Open 64-bit PowerShell 7 as Administrator on the Windows host, then rerun with -ApplyBrowserPolicy. No Brave policies were written.'
        }
        if (-not [Environment]::Is64BitProcess) {
            throw 'Open 64-bit PowerShell 7 as Administrator. A 32-bit session would write the Brave policy key in the wrong registry view. No Brave policies were written.'
        }
    }
    $spec = Read-GroundworkBraveSpec
    foreach ($policy in @(Get-ApplicableBravePolicies $spec)) {
        $converted = ConvertTo-BraveRegistryValue $policy.value
        $operation = "Set $($policy.name)=$($converted.Label)"
        Write-Output $operation
        if ($PSCmdlet.ShouldProcess($script:BravePolicyKey, $operation)) {
            Set-BravePolicyValue -Name $policy.name -Converted $converted
        }
    }
}

function Test-BraveReleaseCapabilityPath {
    param([string]$Data)
    $normalized = ($Data -replace '/', '\').Trim().TrimEnd('\')
    if ($normalized -match '(?i)Brave-Browser-(Beta|Dev|Nightly)') { return $false }
    return $normalized -match '(?i)^Software\\(Clients\\StartMenuInternet\\Brave|BraveSoftware\\Brave-Browser)\\Capabilities$'
}

function Select-BraveRegisteredApplication {
    param($Entries)
    $found = @(foreach ($entry in @($Entries)) { if (Test-BraveReleaseCapabilityPath $entry.Data) { $entry } })
    if ($found.Count -eq 0) {
        throw 'Brave has no RegisteredApplications entry. Install Brave, open it once, then rerun: pwsh -File ./install-host-apps.ps1 -SetDefaultBrowser'
    }
    $users = @($found | Where-Object { $_.Scope -eq 'User' })
    $chosen = if ($users.Count -gt 0) { $users } else { @($found | Where-Object { $_.Scope -eq 'Machine' }) }
    if ($chosen.Count -ne 1) {
        $names = @($chosen | ForEach-Object { $_.Name }) -join ', '
        throw "More than one Brave registration is present ($names). No Settings page was opened."
    }
    return $chosen[0]
}

function ConvertTo-BraveDefaultAppsUri {
    param($Entry)
    if ([string]::IsNullOrWhiteSpace([string]$Entry.Name)) { throw 'Brave registration has no value name. No Settings page was opened.' }
    $parameter = switch ($Entry.Scope) {
        'User' { 'registeredAppUser' }
        'Machine' { 'registeredAppMachine' }
        default { throw "Brave registration scope '$($Entry.Scope)' is not User or Machine. No Settings page was opened." }
    }
    $name = [uri]::EscapeDataString([string]$Entry.Name)
    return "ms-settings:defaultapps?$parameter=$name"
}

function Get-BraveRegisteredApplicationEntries {
    if (-not $IsWindows) { return @() }
    $hives = @(
        @{ Scope = 'User'; Path = 'HKCU:\Software\RegisteredApplications' },
        @{ Scope = 'Machine'; Path = 'HKLM:\Software\RegisteredApplications' }
    )
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($hive in $hives) {
        if (-not (Test-Path -LiteralPath $hive.Path)) { continue }
        $key = Get-Item -LiteralPath $hive.Path
        foreach ($name in @($key.GetValueNames())) {
            if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
            $data = $key.GetValue($name)
            if ($data -is [Array]) { $data = $data | Select-Object -First 1 }
            $entries.Add([pscustomobject]@{ Name = [string]$name; Scope = $hive.Scope; Data = [string]$data })
        }
    }
    return @($entries.ToArray())
}

function Open-BraveDefaultAppsSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param($Entries)
    if (-not $IsWindows) { throw 'Run this script on the Windows host, not inside WSL, macOS, or Linux.' }
    if (-not $Entries) { $Entries = @(Get-BraveRegisteredApplicationEntries) }
    $selected = Select-BraveRegisteredApplication $Entries
    $uri = ConvertTo-BraveDefaultAppsUri $selected
    Write-Output $uri
    Write-Output 'In Windows Settings, set Brave as the default browser and confirm. Windows does not let an installer set this.'
    if ($PSCmdlet.ShouldProcess($uri, 'Open Windows Settings on the Brave default-apps page')) {
        Start-Process -FilePath $uri
    }
}

function Test-ShouldOfferBraveImport {
    param([string[]]$Association, [bool]$ChromeInstalled)
    if ($ChromeInstalled) { return $true }
    foreach ($value in @($Association)) {
        if ($value -in @('ChromeHTML', 'MSEdgeHTM', 'AppXq0fevzme2pys62n3e0fbqa7peapykr8v', 'Google Chrome', 'Microsoft Edge')) {
            return $true
        }
    }
    return $false
}

function Get-BraveImportNotice {
    param([string[]]$Association, [bool]$ChromeInstalled)
    if (-not (Test-ShouldOfferBraveImport -Association $Association -ChromeInstalled $ChromeInstalled)) { return $null }
    return 'Brave can import bookmarks, passwords, and history at brave://settings/importData. Nothing was uninstalled.'
}

function Test-GoogleChromeInstalled {
    if (-not $IsWindows) { return $false }
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $roots) {
        foreach ($item in @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
            if ($item.DisplayName -eq 'Google Chrome') { return $true }
        }
    }
    return $false
}

function Get-WindowsUrlAssociation {
    param([string]$Protocol)
    if (-not ('GroundworkHostApps.UrlAssociation' -as [type])) {
        Add-Type -TypeDefinition $script:UrlAssociationSource
    }
    $values = [System.Collections.Generic.List[string]]::new()
    foreach ($kind in @(20, 4)) {
        $values.Add([GroundworkHostApps.UrlAssociation]::Lookup($Protocol, $kind))
    }
    return @($values.ToArray())
}

function Get-BraveImportNoticeFromHost {
    if (-not $IsWindows) { return $null }
    try {
        $associations = [System.Collections.Generic.List[string]]::new()
        foreach ($protocol in @('http', 'https')) {
            foreach ($value in @(Get-WindowsUrlAssociation $protocol)) { $associations.Add($value) }
        }
        return Get-BraveImportNotice -Association $associations.ToArray() -ChromeInstalled (Test-GoogleChromeInstalled)
    } catch {
        return $null
    }
}

function Get-BraveExtensionNotice {
    param([string]$RepoRoot = $PSScriptRoot)
    $path = Join-Path $RepoRoot 'core/browser/brave.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return 'Brave policies and the extension offer need core/browser/brave.json. Run: git submodule update --init'
    }
    $spec = Read-GroundworkBraveSpec -RepoRoot $RepoRoot
    $offers = @($spec.extensions)
    if ($offers.Count -eq 0) { return $null }
    $urls = [System.Collections.Generic.List[string]]::new()
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($offer in $offers) {
        if ($offer.PSObject.Properties.Name -contains 'forceInstall') {
            throw "Extension '$($offer.name)' asks for a force install. No extension was installed."
        }
        if ($offer.install -ne 'offer') {
            throw "Extension '$($offer.name)' is not an offer. No extension was installed."
        }
        $id = [string]$offer.id
        if ($id -notmatch '^[a-p]{32}$') {
            throw "Extension '$($offer.name)' does not have a Chrome Web Store id. No extension was installed."
        }
        $names.Add([string]$offer.name)
        $urls.Add("https://chromewebstore.google.com/detail/$id")
    }
    $listed = $names -join ', '
    $pages = $urls -join ' '
    return "$listed is offered, not installed. Open $pages in Brave."
}

function Write-BraveHostOffers {
    $import = Get-BraveImportNoticeFromHost
    if ($import) { Write-Output $import }
    $extension = Get-BraveExtensionNotice
    if ($extension) { Write-Output $extension }
}

if ($Help) {
    Write-Output 'Usage: pwsh -File ./install-host-apps.ps1 [-Install [-WhatIf]] [-SetDefaultBrowser [-WhatIf]] [-ApplyBrowserPolicy [-WhatIf]]'
    Write-Output 'Default: show the package plan. -Install requests the newest available official packages and accepts their source/package agreements.'
    Write-Output 'The Brave package id is Brave.Brave from winget. -SetDefaultBrowser opens Windows Settings so you can confirm Brave as the default. Windows does not let a program set that default.'
    Write-Output '-ApplyBrowserPolicy writes the shared policies from core/browser/brave.json. It needs 64-bit Administrator PowerShell and leaves other values under that key alone.'
    Write-Output 'Run on the Windows host with PowerShell 7 and App Installer (winget). Sign-in and device approval remain local.'
    return
}
if (-not $Install -and -not $SetDefaultBrowser -and -not $ApplyBrowserPolicy) {
    $packages | ForEach-Object { Write-Output ("{0}: {1} ({2})" -f $_.Name, $_.Id, $_.Source) }
    Write-Output 'Plan only. Use -Install after reviewing the packages; -Install -WhatIf previews without running winget.'
    Write-BraveHostOffers
    return
}
$failed = $false
if ($Install) {
    if (-not $IsWindows -and -not $WhatIfPreference) {
        throw 'Run this script on the Windows host, not inside WSL, macOS, or Linux.'
    }
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
                $check = if ($package.Name -eq 'FreeTube') {
                    'its version (FreeTube has no account)'
                } elseif ($package.Name -eq 'Brave') {
                    'its version (Brave has no account)'
                } else {
                    'its version and sign-in'
                }
                Write-Output ("{0}: package command completed. Open the app and verify {1}." -f $package.Name, $check)
                if ($package.Name -eq 'Brave' -and -not $SetDefaultBrowser) {
                    Write-Output 'To confirm Brave as the default browser, run: pwsh -File ./install-host-apps.ps1 -SetDefaultBrowser'
                }
            }
        } finally {
            if (-not $process.HasExited) {
                $process.Kill($true)
                if (-not $process.WaitForExit(10000)) { throw 'The owned installer could not be confirmed stopped.' }
            }
            $process.Dispose()
        }
    }
    Write-BraveHostOffers
}
if ($SetDefaultBrowser) { Open-BraveDefaultAppsSettings }
if ($ApplyBrowserPolicy) { Invoke-GroundworkBravePolicy }
if ($failed) { throw 'One or more requested native apps could not be verified. Successful installations remain installed; repair the reported package and rerun.' }
