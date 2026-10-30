#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '../install-host-apps.ps1'
$tokens = $null; $errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw ($errors | Out-String) }
$source = Get-Content -LiteralPath $script -Raw
if ($source -match 'UserChoice') { throw 'install-host-apps.ps1 references UserChoice.' }
if ($source -match 'ExtensionInstallForcelist|Chrome\\Extensions') { throw 'install-host-apps.ps1 writes a Chromium extension force-install key.' }
$pwsh = (Get-Process -Id $PID).Path
$spec = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../core/browser/brave.json') -Raw | ConvertFrom-Json
foreach ($policy in @($spec.policies)) {
    $name = [string]$policy.name
    if ($source.Contains($name)) { throw "$name is copied into install-host-apps.ps1 instead of core/browser/brave.json." }
}
foreach ($extension in @($spec.extensions)) {
    $id = [string]$extension.id
    if ($source.Contains($id)) { throw "$id is copied into install-host-apps.ps1 instead of core/browser/brave.json." }
}
$extensionId = [string]$spec.extensions[0].id
foreach ($case in @(@{ Args = @('-Help') }, @{ Args = @() }, @{ Args = @('-Install', '-WhatIf') })) {
    $arguments = $case.Args
    $output = & $pwsh -NoProfile -File $script @arguments *>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw $output }
    if ($arguments -notcontains '-Help' -and $output -notmatch 'Tailscale') { throw 'The package plan omitted Tailscale.' }
    if ($arguments.Count -eq 0 -and -not $output.Contains('FreeTube: FreeTube.FreeTube (winget)')) { throw 'The package plan omitted the FreeTube.FreeTube winget id.' }
    if ($arguments.Count -eq 0 -and -not $output.Contains('Brave: Brave.Brave (winget)')) { throw 'The package plan omitted the Brave.Brave winget id.' }
    if ($arguments.Count -eq 0 -and $output -notlike "*https://chromewebstore.google.com/detail/$extensionId*") { throw 'The plan omitted the extension offer from brave.json.' }
    if (-not $IsWindows -and $arguments.Count -eq 0 -and $output -match 'importData') { throw 'The Linux plan offered a Windows browser import.' }
    if ($arguments -contains '-Help' -and $output -notmatch '-SetDefaultBrowser') { throw 'Help omitted -SetDefaultBrowser.' }
    if ($arguments -contains '-Help' -and $output -notmatch '-ApplyBrowserPolicy') { throw 'Help omitted -ApplyBrowserPolicy.' }
    if ($arguments -contains '-WhatIf' -and -not $output.Contains('target "FreeTube"')) { throw 'The WhatIf preview omitted FreeTube.' }
    if ($arguments -contains '-WhatIf' -and -not $output.Contains('target "Brave"')) { throw 'The WhatIf preview omitted Brave.' }
    if ($arguments -contains '-WhatIf' -and $output -match 'Requesting ') { throw 'WhatIf ran winget.' }
}
$output = & $pwsh -NoProfile -File $script -UnknownArgument *>&1 | Out-String
if ($LASTEXITCODE -eq 0) { throw 'An invalid argument was accepted.' }
$helpWithPolicy = & $pwsh -NoProfile -File $script -Help -ApplyBrowserPolicy *>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw $helpWithPolicy }
if ($helpWithPolicy -notmatch '-ApplyBrowserPolicy') { throw 'Help combined with -ApplyBrowserPolicy did not print usage.' }

. $script -Help | Out-Null
$settingsBitnessSentence = 'Open 64-bit PowerShell 7, then rerun: pwsh -File ./install-host-apps.ps1 -SetDefaultBrowser. No Settings page was opened.'
if (${function:Open-BraveDefaultAppsSettings}.ToString() -notmatch [regex]::Escape($settingsBitnessSentence)) {
    throw 'Open-BraveDefaultAppsSettings does not refuse a 32-bit process.'
}
$policyBitnessSentence = 'Open 64-bit PowerShell 7 as Administrator. No Brave policies were written.'
if (${function:Open-BraveDefaultAppsSettings}.ToString() -match [regex]::Escape($policyBitnessSentence)) {
    throw 'Open-BraveDefaultAppsSettings uses the policy bitness message.'
}
if ($source -match 'wrong registry view') { throw 'A bitness refusal still claims the wrong registry view.' }
if (${function:Invoke-GroundworkBravePolicy}.ToString() -notmatch [regex]::Escape($policyBitnessSentence)) {
    throw 'Policy apply does not refuse a 32-bit process.'
}
if (${function:Invoke-GroundworkBravePolicy}.ToString() -match [regex]::Escape($settingsBitnessSentence)) {
    throw 'Policy apply uses the Settings bitness message.'
}
$elevatedDefinition = ${function:Test-HostAppsElevated}.ToString()
if ($elevatedDefinition -notmatch 'WindowsBuiltInRole' -or $elevatedDefinition -notmatch 'Administrator') {
    throw 'Elevation check does not require the Administrator role.'
}
if ($IsWindows) {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $role = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ((Test-HostAppsElevated) -ne $role) { throw 'Elevation check disagreed with WindowsPrincipal.' }
} elseif (Test-HostAppsElevated) {
    throw 'Linux was treated as an elevated Windows session.'
}

$userEntry = [pscustomobject]@{ Name = 'Brave HTML'; Scope = 'User'; Data = 'Software\BraveSoftware\Brave-Browser\Capabilities' }
$machineEntry = [pscustomobject]@{ Name = 'Brave'; Scope = 'Machine'; Data = 'Software\Clients\StartMenuInternet\Brave\Capabilities' }
$betaEntry = [pscustomobject]@{ Name = 'Brave Beta'; Scope = 'User'; Data = 'Software\BraveSoftware\Brave-Browser-Beta\Capabilities' }
$edgeEntry = [pscustomobject]@{ Name = 'Microsoft Edge'; Scope = 'Machine'; Data = 'Software\Clients\StartMenuInternet\Microsoft Edge\Capabilities' }
$selected = Select-BraveRegisteredApplication @($edgeEntry, $machineEntry, $betaEntry, $userEntry)
$uri = ConvertTo-BraveDefaultAppsUri $selected
if ($uri -ne 'ms-settings:defaultapps?registeredAppUser=Brave%20HTML') { throw "User deep link was '$uri'." }
$machineUri = ConvertTo-BraveDefaultAppsUri (Select-BraveRegisteredApplication @($edgeEntry, $machineEntry, $betaEntry))
if ($machineUri -ne 'ms-settings:defaultapps?registeredAppMachine=Brave') { throw "Machine deep link was '$machineUri'." }
$sidSuffix = '234567ABCDEFGHIJKLMNOPQRST'
if ($sidSuffix.Length -ne 26 -or $sidSuffix -notmatch '^[A-Z2-7]{26}$') { throw 'The base32 fixture is not 26 characters.' }
$sidName = "Brave.$sidSuffix"
$sidEntry = [pscustomobject]@{ Name = $sidName; Scope = 'User'; Data = "Software\Clients\StartMenuInternet\$sidName\Capabilities" }
$sidUri = ConvertTo-BraveDefaultAppsUri (Select-BraveRegisteredApplication @($edgeEntry, $machineEntry, $betaEntry, $sidEntry))
if ($sidUri -ne "ms-settings:defaultapps?registeredAppUser=$sidName") { throw "SID deep link was '$sidUri'." }
$userName = 'Brave.SomeUser'
$userNamed = [pscustomobject]@{ Name = $userName; Scope = 'User'; Data = "Software\Clients\StartMenuInternet\$userName\Capabilities" }
$userNamedUri = ConvertTo-BraveDefaultAppsUri (Select-BraveRegisteredApplication @($edgeEntry, $betaEntry, $userNamed))
if ($userNamedUri -ne "ms-settings:defaultapps?registeredAppUser=$userName") { throw "Username deep link was '$userNamedUri'." }
if (Test-BraveReleaseCapabilityPath 'Software\BraveSoftware\Brave-Browser-Beta\Capabilities') { throw 'Brave Beta was accepted.' }
if (Test-BraveReleaseCapabilityPath 'Software\BraveSoftware\Brave-Browser-Dev\Capabilities') { throw 'Brave Dev was accepted.' }
if (Test-BraveReleaseCapabilityPath 'Software\BraveSoftware\Brave-Browser-Nightly\Capabilities') { throw 'Brave Nightly was accepted.' }
$rejected = $false
try { Select-BraveRegisteredApplication @($edgeEntry) } catch {
    $rejected = $true
    if ($_.Exception.Message -notmatch 'RegisteredApplications') { throw }
}
if (-not $rejected) { throw 'An unrelated registration was treated as Brave.' }

if ($source -match 'SetUserFTA|UserChoice|Hash\s*=|ProgHash') { throw 'The script touches the default-browser hash.' }
if (${function:Invoke-GroundworkBraveDefaultStep}.ToString() -match 'Set-ItemProperty|New-ItemProperty') { throw 'The default step writes the registry.' }
if ((Get-DefaultBrowserKind @()) -ne 'none') { throw 'No handler was not classified as none.' }
if ((Get-DefaultBrowserKind @('MSEdgeHTM', 'MSEdgeHTM')) -ne 'edge') { throw 'Edge was not classified.' }
if ((Get-DefaultBrowserKind @('BraveHTML', 'BraveHTML.ABC')) -ne 'brave') { throw 'Brave was not classified.' }
if ((Get-DefaultBrowserKind @('BraveHTML', 'MSEdgeHTM')) -ne 'other') { throw 'A mixed default was not classified as other.' }
if ((Get-DefaultBrowserKind @('ChromeHTML')) -ne 'other') { throw 'Chrome was not classified as other.' }
if (Get-NonInteractiveReason -UserInteractive $true -InputRedirected $false -OutputRedirected $false -Remoting $false -Ssh $false -Wsl $false) { throw 'A desktop session was called non-interactive.' }
foreach ($flags in @(@{ Ssh = $true }, @{ Remoting = $true }, @{ Wsl = $true }, @{ UserInteractive = $false }, @{ InputRedirected = $true }, @{ OutputRedirected = $true })) {
    $base = @{ UserInteractive = $true; InputRedirected = $false; OutputRedirected = $false; Remoting = $false; Ssh = $false; Wsl = $false }
    foreach ($key in $flags.Keys) { $base[$key] = $flags[$key] }
    if (-not (Get-NonInteractiveReason @base)) { throw "Session was not deferred: $($flags.Keys -join ',')" }
}
$done = [pscustomobject]@{ state = 'opened' }
$declined = [pscustomobject]@{ state = 'declined' }
$decisions = @(
    @{ State = $null; Kind = 'edge'; Check = $true; Reason = $null; Want = 'open' },
    @{ State = $null; Kind = 'none'; Check = $true; Reason = $null; Want = 'open' },
    @{ State = $null; Kind = 'edge'; Check = $true; Reason = 'SSH'; Want = 'defer' },
    @{ State = $null; Kind = 'other'; Check = $true; Reason = $null; Want = 'offer' },
    @{ State = $null; Kind = 'other'; Check = $true; Reason = 'SSH'; Want = 'offer' },
    @{ State = $null; Kind = 'brave'; Check = $true; Reason = $null; Want = 'already-brave' },
    @{ State = $null; Kind = 'edge'; Check = $false; Reason = $null; Want = 'skip-check' },
    @{ State = $done; Kind = 'edge'; Check = $true; Reason = $null; Want = 'skip-done' },
    @{ State = $declined; Kind = 'edge'; Check = $true; Reason = $null; Want = 'skip-declined' },
    @{ State = [pscustomobject]@{ state = 'unreadable' }; Kind = 'edge'; Check = $true; Reason = $null; Want = 'skip-done' }
)
foreach ($row in $decisions) {
    $got = Get-BraveDefaultDecision -State $row.State -DefaultKind $row.Kind -CheckPassed $row.Check -NonInteractiveReason $row.Reason
    if ($got -ne $row.Want) { throw "Decision for $($row.Kind)/$($row.Check)/$($row.Reason) was '$got', wanted '$($row.Want)'." }
}
$okReader = { param($Path) '130.1.71.123' }
$badReader = { param($Path) '' }
$throwReader = { param($Path) throw 'cannot run' }
if (-not (Test-BraveInstallCheck -Entries @($userEntry) -ExePath 'brave.exe' -VersionReader $okReader)) { throw 'A good Brave install failed the check.' }
if (Test-BraveInstallCheck -Entries @($edgeEntry) -ExePath 'brave.exe' -VersionReader $okReader) { throw 'Missing registration passed the check.' }
if (Test-BraveInstallCheck -Entries @($userEntry) -ExePath '' -VersionReader $okReader) { throw 'A missing exe passed the check.' }
if (Test-BraveInstallCheck -Entries @($userEntry) -ExePath 'brave.exe' -VersionReader $badReader) { throw 'A blank product version passed the check.' }
if (Test-BraveInstallCheck -Entries @($userEntry) -ExePath 'brave.exe' -VersionReader $throwReader) { throw 'A failing exe passed the check.' }
$stateDir = Join-Path ([System.IO.Path]::GetTempPath()) ("groundwork-brave-state-" + [guid]::NewGuid().ToString('n'))
try {
    $statePath = Join-Path $stateDir 'Groundwork/brave-default.json'
    if ($null -ne (Read-BraveDefaultState -Path $statePath)) { throw 'A missing state file was read as a record.' }
    Write-BraveDefaultState -Path $statePath -State 'opened' -Outcome 'not-confirmed'
    $read = Read-BraveDefaultState -Path $statePath
    if ($read.state -ne 'opened' -or $read.outcome -ne 'not-confirmed') { throw 'State did not round-trip.' }
    Write-BraveDefaultState -Path $statePath -State 'declined'
    if ((Read-BraveDefaultState -Path $statePath).state -ne 'declined') { throw 'A decline was not saved.' }
    Set-Content -LiteralPath $statePath -Value '{ not json'
    if ((Read-BraveDefaultState -Path $statePath).state -ne 'unreadable') { throw 'A corrupt state file was not fail-closed.' }
    $corruptOut = Invoke-GroundworkBraveDefaultStep -StatePath $statePath | Out-String
    if ($corruptOut -notmatch 'is unreadable' -or $corruptOut -notmatch [regex]::Escape($statePath) -or $corruptOut -notmatch 'Delete that file' -or $corruptOut -match 'Opening Windows Settings') { throw "A corrupt record was not reported or acted on.`n$corruptOut" }
    Write-BraveDefaultState -Path $statePath -State 'declined'
    $declinedOut = Invoke-GroundworkBraveDefaultStep -StatePath $statePath | Out-String
    if ($declinedOut -notmatch 'declined earlier' -or $declinedOut -match 'Opening Windows Settings') { throw "A saved decline was not respected.`n$declinedOut" }
} finally {
    if (Test-Path -LiteralPath $stateDir) { Remove-Item -LiteralPath $stateDir -Recurse -Force }
}
if (${function:Get-BraveProductVersion}.ToString() -match 'Start-Process|Process\]::Start|--version') { throw 'The version check launches Brave.' }
$bothOut = & $pwsh -NoProfile -File $script -DeclineBraveDefault -SetDefaultBrowser -WhatIf *>&1 | Out-String
if ($LASTEXITCODE -eq 0 -or $bothOut -notmatch 'contradict' -or $bothOut -match 'Recorded\.') { throw "Contradicting flags were accepted.`n$bothOut" }
$stepOut = & $pwsh -NoProfile -File $script -RunBraveDefaultStep -WhatIf *>&1 | Out-String
if ($LASTEXITCODE -ne 0 -and $IsWindows) { throw $stepOut }
$declineOut = & $pwsh -NoProfile -File $script -DeclineBraveDefault -WhatIf *>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw $declineOut }
if ($declineOut -match 'Recorded\.') { throw 'WhatIf recorded a decline.' }

if (-not (Test-ShouldOfferBraveImport -Association @('MSEdgeHTM') -ChromeInstalled $false)) { throw 'Edge as the default did not offer import.' }
if (-not (Test-ShouldOfferBraveImport -Association @('BraveHTML') -ChromeInstalled $true)) { throw 'Installed Chrome did not offer import.' }
if (Test-ShouldOfferBraveImport -Association @('BraveHTML') -ChromeInstalled $false) { throw 'Brave as the default offered an import with no other browser.' }
$importNotice = Get-BraveImportNotice -Association @('ChromeHTML') -ChromeInstalled $false
if ($importNotice -notmatch 'bookmarks and history' -or $importNotice -notmatch 'brave://settings/importData' -or $importNotice -notmatch 'Nothing was uninstalled' -or $importNotice -match 'password') { throw $importNotice }
$chromeOnly = Get-BraveImportNotice -Association @() -ChromeInstalled $true
if ($chromeOnly -notmatch 'bookmarks and history' -or $chromeOnly -notmatch 'Nothing was uninstalled' -or $chromeOnly -match 'password') { throw $chromeOnly }

if ((ConvertTo-BraveRegistryValue $true).Label -ne 'DWORD 1') { throw 'True did not render as DWORD 1.' }
if ((ConvertTo-BraveRegistryValue $false).Label -ne 'DWORD 0') { throw 'False did not render as DWORD 0.' }
if ((ConvertTo-BraveRegistryValue 'kept').Label -ne 'String kept') { throw 'A string policy did not render as String.' }
$badType = $false
try { ConvertTo-BraveRegistryValue @(1, 2) } catch { $badType = $true }
if (-not $badType) { throw 'An unsupported policy value was accepted.' }

$unknownWhen = [pscustomobject]@{
    schemaVersion = 1
    policies = @([pscustomobject]@{ name = 'ExampleEnabled'; value = $false; when = 'Something else' })
    extensions = @()
}
$unknownRejected = $false
try { Get-ApplicableBravePolicies $unknownWhen } catch {
    $unknownRejected = $true
    if ($_.Exception.Message -notmatch 'No Brave policies were written') { throw }
}
if (-not $unknownRejected) { throw 'An unknown when condition was accepted.' }
$withoutBitwarden = [pscustomobject]@{
    schemaVersion = 1
    policies = @([pscustomobject]@{ name = 'PasswordManagerEnabled'; value = $false; when = 'Bitwarden is the password manager.' })
    extensions = @()
}
if (@(Get-ApplicableBravePolicies $withoutBitwarden).Count -ne 0) { throw 'Password manager policy was applied without Bitwarden.' }

$missingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("groundwork-host-apps-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $missingRoot | Out-Null
try {
    $missingRejected = $false
    try { Read-GroundworkBraveSpec -RepoRoot $missingRoot } catch {
        $missingRejected = $true
        if ($_.Exception.Message -notmatch 'git submodule update --init') { throw }
    }
    if (-not $missingRejected) { throw 'A missing Brave spec was accepted.' }
} finally {
    Remove-Item -LiteralPath $missingRoot -Recurse -Force
}

$expected = [System.Collections.Generic.List[string]]::new()
foreach ($policy in @($spec.policies)) {
    $when = if ($policy.PSObject.Properties.Name -contains 'when') { [string]$policy.when } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($when)) {
        if ($when -ne 'Bitwarden is the password manager.') { continue }
        $offered = @($spec.extensions | Where-Object { $_.name -eq 'Bitwarden' -and $_.install -eq 'offer' })
        if ($offered.Count -ne 1) { continue }
    }
    $label = if ($policy.value -is [bool]) { "DWORD $([int][bool]$policy.value)" } elseif ($policy.value -is [string]) { "String $($policy.value)" } else { throw 'The Brave spec has a value this test does not render.' }
    $expected.Add("Set $($policy.name)=$label")
}
function Assert-PolicyWhatIfOutput {
    param([string]$Output)
    if ($Output -match 'Ads-for-crypto|upstreamDefault|Bitwarden is the password manager') { throw "Policy preview included spec metadata.`n$Output" }
    $actual = @($Output -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^Set ' })
    $diff = Compare-Object $expected $actual
    if ($diff -or $actual.Count -ne $expected.Count) { throw "Policy preview did not list the spec values.`n$Output" }
}

$policyKey = 'HKLM:\Software\Policies\BraveSoftware\Brave'
if (Test-HostAppsElevated) {
    $policyExisted = Test-Path -LiteralPath $policyKey
    $sentinel = 'GroundworkTestSentinel'
    if (-not $policyExisted) { New-Item -Path $policyKey -Force | Out-Null }
    New-ItemProperty -LiteralPath $policyKey -Name $sentinel -PropertyType String -Value 'leave-me' -Force | Out-Null
    $originalNames = @(@((Get-Item -LiteralPath $policyKey).Property) | Where-Object { $_ -ne $sentinel })
    try {
        $policyOutput = & $pwsh -NoProfile -File $script -ApplyBrowserPolicy -WhatIf *>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw $policyOutput }
        Assert-PolicyWhatIfOutput $policyOutput
        $after = Get-ItemProperty -LiteralPath $policyKey
        if ($after.$sentinel -ne 'leave-me') { throw 'WhatIf changed an unrelated policy value.' }
        $afterNames = @((Get-Item -LiteralPath $policyKey).Property)
        if (Compare-Object (@($originalNames + $sentinel) | Sort-Object) ($afterNames | Sort-Object)) { throw 'WhatIf added or removed a policy value.' }
    } finally {
        if (Test-Path -LiteralPath $policyKey) {
            foreach ($name in @((Get-Item -LiteralPath $policyKey).Property)) {
                if ($originalNames -notcontains $name) {
                    Remove-ItemProperty -LiteralPath $policyKey -Name $name -Force -ErrorAction SilentlyContinue
                }
            }
            $left = @((Get-Item -LiteralPath $policyKey).Property | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if (-not $policyExisted -and $left.Count -eq 0) {
                Remove-Item -LiteralPath $policyKey -Force
            }
        }
    }
} else {
    $policyOutput = & $pwsh -NoProfile -File $script -ApplyBrowserPolicy -WhatIf *>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw $policyOutput }
    Assert-PolicyWhatIfOutput $policyOutput
    $refused = & $pwsh -NoProfile -File $script -ApplyBrowserPolicy *>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $refused -notmatch 'No Brave policies were written') { throw $refused }
}

$originalElevated = ${function:Test-HostAppsElevated}
function Test-HostAppsElevated { return $false }
try {
    if ($IsWindows) {
        $existed = Test-Path -LiteralPath $policyKey
        $before = if ($existed) { @((Get-Item -LiteralPath $policyKey).Property) } else { @() }
    }
    $mockRefused = $false
    try { Invoke-GroundworkBravePolicy } catch {
        $mockRefused = $true
        if ($_.Exception.Message -notmatch 'Administrator' -or $_.Exception.Message -notmatch 'No Brave policies were written') { throw }
    }
    if (-not $mockRefused) { throw 'A non-admin policy apply was accepted.' }
    if ($IsWindows) {
        $existsNow = Test-Path -LiteralPath $policyKey
        if ($existsNow -ne $existed) { throw 'Non-admin apply created or removed the Brave policy key.' }
        if ($existed -and (Compare-Object ($before | Sort-Object) (@((Get-Item -LiteralPath $policyKey).Property) | Sort-Object))) {
            throw 'Non-admin apply changed Brave policy values.'
        }
    }
} finally {
    Set-Item -Path function:Test-HostAppsElevated -Value $originalElevated
}

$defaultOutput = & $pwsh -NoProfile -File $script -SetDefaultBrowser -WhatIf *>&1 | Out-String
if ($IsWindows) {
    if ($defaultOutput -notmatch 'ms-settings:defaultapps\?registeredApp(User|Machine)=' -and $defaultOutput -notmatch 'RegisteredApplications') {
        throw $defaultOutput
    }
} else {
    if ($LASTEXITCODE -eq 0 -or $defaultOutput -notmatch 'Windows host') { throw $defaultOutput }
}

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
