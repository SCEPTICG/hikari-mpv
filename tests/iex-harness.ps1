# Runs install/hikari.ps1 (or a release copy of it) the way a user does without a
# file, and reports what that run left behind in the session. Dot-source it from
# "pwsh -Command" so that it runs in the session's global scope, like a prompt:
#
#   pwsh -NoProfile -Command ". 'tests/iex-harness.ps1' -Script <ps1> -Report <json> ..."
#
# -Mode iex     : Invoke-Expression of the file text, no options; the answers to
#                 the installer's questions come from stdin.
# -Mode create  : & ([scriptblock]::Create(<text>)) with -Action/-Target and
#                 -Yes:<YesValue> (true or false), the documented way to pass options.
# -Downloads    : JSON file with an object { url: local file }. Invoke-WebRequest
#                 is replaced by a global function that serves those files (the
#                 installer finds a function before the cmdlet) and logs the URLs.
#                 It also changes [Net.ServicePointManager]::SecurityProtocol,
#                 as a download on Windows PowerShell 5.1 may need (pwsh 7 never
#                 touches it), so that the check that the installer puts it back
#                 tests something; TlsTouched in the report says it happened.
# -StrictLatest : the session runs with Set-StrictMode -Version Latest and
#                 $ErrorActionPreference = 'Stop' before the installer starts.
#
# If the installer called exit, the process would end here and no report would
# be written: the tests treat a missing report as a failure.
param(
    [string]$Script,
    [string]$Report,
    [string]$Downloads = '',
    [string]$Mode = 'iex',
    [string]$Action = '',
    [string]$Target = '',
    [string]$YesValue = '',
    [switch]$StrictLatest
)

# The parent test run loads the installer in test mode; this run must not.
Remove-Item Env:HIKARI_INSTALL_TEST -ErrorAction SilentlyContinue

$global:__hMap = @{}
if ($Downloads) {
    $__hJson = Get-Content -Raw -LiteralPath $Downloads | ConvertFrom-Json
    foreach ($__hProp in $__hJson.PSObject.Properties) { $global:__hMap[$__hProp.Name] = [string]$__hProp.Value }
}
$global:__hLog = New-Object System.Collections.Generic.List[string]
$global:__hTls = [System.Net.ServicePointManager]::SecurityProtocol
$global:__hTlsTouched = $false
function global:Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)
    $global:__hLog.Add($Uri)
    $__hOther = [System.Net.SecurityProtocolType]::Tls12
    if ($global:__hTls -eq $__hOther) { $__hOther = [System.Net.SecurityProtocolType]::Tls13 }
    [System.Net.ServicePointManager]::SecurityProtocol = $__hOther
    if ([System.Net.ServicePointManager]::SecurityProtocol -ne $global:__hTls) { $global:__hTlsTouched = $true }
    if (-not $global:__hMap.ContainsKey($Uri)) { throw ('unexpected download ' + $Uri) }
    Copy-Item -LiteralPath $global:__hMap[$Uri] -Destination $OutFile -Force
}

$__hCode = Get-Content -Raw -LiteralPath $Script
$__hCtrlC = $null
try { $__hCtrlC = [Console]::TreatControlCAsInput } catch { }

if ($StrictLatest) {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
}
else {
    Set-StrictMode -Off
    $ErrorActionPreference = 'Continue'
}

$__hVarsBefore = @(Get-Variable | ForEach-Object { $_.Name })
$__hFuncsBefore = @(Get-ChildItem Function: | ForEach-Object { $_.Name })
$__hModsBefore = @(Get-Module | ForEach-Object { $_.Name })
$global:LASTEXITCODE = 99

if ($Mode -eq 'iex') {
    $__hOut = @(Invoke-Expression $__hCode)
}
else {
    $__hParams = @{}
    if ($Action) { $__hParams['Action'] = $Action }
    if ($Target) { $__hParams['Target'] = $Target }
    if ($YesValue) { $__hParams['Yes'] = [bool]::Parse($YesValue) }
    $__hOut = @(& ([scriptblock]::Create($__hCode)) @__hParams)
}
$__hExit = $global:LASTEXITCODE

# Measured before anything else of the harness can change them.
$__hEap = [string]$ErrorActionPreference
$__hStrict = 'on'
try { $null = $__hNeverDefinedVariable; $__hStrict = 'off' } catch { }
Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$__hCtrlCAfter = $null
try { $__hCtrlCAfter = [Console]::TreatControlCAsInput } catch { }
# Harness variables (__h*) and the automatic ones any command sets are not the
# installer's doing.
$__hNoise = @('_', 'PSItem', 'LASTEXITCODE', '?', '^', '$', 'Matches', 'input')
$__hNewVars = @(Get-Variable | ForEach-Object { $_.Name } |
        Where-Object { $__hVarsBefore -notcontains $_ -and $_ -notlike '__h*' -and $__hNoise -notcontains $_ })
$__hNewFuncs = @(Get-ChildItem Function: | ForEach-Object { $_.Name } | Where-Object { $__hFuncsBefore -notcontains $_ })
# PowerShell's own modules under $PSHOME (CimCmdlets, autoloaded by the graphics
# card query on Windows) load by themselves the first time a command needs them:
# not the installer's doing either. Anything else, such as its own module, is.
$__hNewMods = @(Get-Module | Where-Object {
        $__hModsBefore -notcontains $_.Name -and -not ($_.ModuleBase -and $_.ModuleBase.StartsWith($PSHOME, [System.StringComparison]::OrdinalIgnoreCase))
    } | ForEach-Object { $_.Name })

[ordered]@{
    Alive        = $true
    ExitCode     = $__hExit
    Eap          = $__hEap
    Strict       = $__hStrict
    NewVariables = @($__hNewVars)
    NewFunctions = @($__hNewFuncs)
    NewModules   = @($__hNewMods)
    Output       = @($__hOut | ForEach-Object { [string]$_ })
    Downloads    = @($global:__hLog)
    TlsSame      = ([System.Net.ServicePointManager]::SecurityProtocol -eq $global:__hTls)
    TlsTouched   = [bool]$global:__hTlsTouched
    CtrlCSame    = ($__hCtrlCAfter -eq $__hCtrlC)
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Report -Encoding utf8
