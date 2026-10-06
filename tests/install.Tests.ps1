# Tests for install/sosc.ps1, without Pester. Run from anywhere:
#   pwsh -NoProfile -File tests/install.Tests.ps1
# Exit code 0 when everything passes. Windows paths are simulated with temporary
# folders and an injected environment; nothing is downloaded.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$env:SOSC_INSTALL_TEST = '1'
$env:SOSC_LANG = 'en'
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$InstallScript = [System.IO.Path]::Combine($RepoRoot, 'install', 'sosc.ps1')
$IexHarness = [System.IO.Path]::Combine($PSScriptRoot, 'iex-harness.ps1')

# The installer keeps everything inside one script block run in a scope of its
# own (so that iex leaves nothing behind). The tests need its functions and
# $script: variables here, so they take that script block from the file and
# dot-source it; with SOSC_INSTALL_TEST set it stops before running anything.
function Get-InstallerBody {
    param([string]$Path)
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw ('parse errors in ' + $Path) }
    $found = $ast.Find({
            param($n)
            $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and
            $n.Parent -is [System.Management.Automation.Language.CommandAst] -and
            $n.Parent.CommandElements.Count -ge 2 -and
            $n.Parent.CommandElements[0] -is [System.Management.Automation.Language.ParenExpressionAst] -and
            [object]::ReferenceEquals($n.Parent.CommandElements[1], $n)
        }, $true)
    if ($null -eq $found) { throw ('installer body not found in ' + $Path) }
    return $found.ScriptBlock.GetScriptBlock()
}
. (Get-InstallerBody $InstallScript)
$script:SoscQuiet = $true
# The tests that drive the old number questions run as if there were no
# interactive console; the keyboard menu tests below switch it on themselves.
$script:SoscConsoleProbe = { $false }

$script:Passed = 0
$script:Failed = 0
$TestRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'sosc-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TestRoot | Out-Null

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    $script:SoscWarnings.Clear()
    $script:NonInteractive = $true
    try {
        & $Body
        $script:Passed++
        Write-Host ('ok   ' + $Name)
    }
    catch {
        $script:Failed++
        Write-Host ('FAIL ' + $Name) -ForegroundColor Red
        Write-Host ('     ' + $_.Exception.Message + ' (line ' + $_.InvocationInfo.ScriptLineNumber + ')') -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$What = 'value')
    if (-not [object]::Equals($Actual, $Expected)) {
        throw ("{0}: expected [{1}], got [{2}]" -f $What, $Expected, $Actual)
    }
}

function Assert-True {
    param($Condition, [string]$What)
    if (-not $Condition) { throw ('expected true: ' + $What) }
}

function Assert-Throws {
    param([scriptblock]$Body, [string]$Like = '*', [string]$What = 'call')
    $threw = $false
    try { & $Body } catch {
        $threw = $true
        if ($_.Exception.Message -notlike $Like) { throw ("{0} threw [{1}], expected like [{2}]" -f $What, $_.Exception.Message, $Like) }
    }
    if (-not $threw) { throw ($What + ' did not throw') }
}

function P {
    param([string[]]$Parts)
    $r = $Parts[0]
    for ($i = 1; $i -lt $Parts.Count; $i++) { $r = [System.IO.Path]::Combine($r, $Parts[$i]) }
    return $r
}

function New-TestDir {
    param([string]$Name)
    $d = P @($TestRoot, $Name)
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

function Set-TestFile {
    param([string]$Path, [string]$Content = 'x')
    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-TestText {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path)
}

function Get-TestBytes {
    param([string]$Path)
    return [System.IO.File]::ReadAllBytes($Path)
}

function Test-HasBom {
    param([string]$Path)
    $b = Get-TestBytes $Path
    return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

# Fake Windows environment rooted in a temp folder.
$script:FakeCommands = @{}
$script:FakeReadOnly = @()
function New-FakeEnv {
    param([string]$Base)
    return @{
        LocalAppData    = (P @($Base, 'Local'))
        AppData         = (P @($Base, 'Roaming'))
        UserProfile     = (P @($Base, 'User'))
        ProgramFiles    = (P @($Base, 'Program Files'))
        ProgramFilesX86 = $null
        ProgramData     = (P @($Base, 'ProgramData'))
        MpvHome         = $null
        IsAdmin         = $false
        FindCommand     = { param([string]$Name) if ($script:FakeCommands.ContainsKey($Name)) { return $script:FakeCommands[$Name] } return $null }
        TestWritable    = {
            param([string]$Path)
            foreach ($r in $script:FakeReadOnly) { if (Test-SoscSamePath $r $Path) { return $false } }
            return $true
        }
    }
}

function Reset-Fake {
    $script:FakeCommands = @{}
    $script:FakeReadOnly = @()
}

# Fake downloads: URL -> local file.
$script:FakeDownloads = @{}
$script:SoscDownloader = {
    param([string]$Url, [string]$OutFile)
    if (-not $script:FakeDownloads.ContainsKey($Url)) { throw ('unexpected download ' + $Url) }
    Copy-Item -LiteralPath $script:FakeDownloads[$Url] -Destination $OutFile -Force
}

function New-FakeUoscZip {
    param([string]$Dir)
    $src = P @($Dir, 'uosc-src')
    Set-TestFile (P @($src, 'scripts', 'uosc', 'main.lua')) '-- fake uosc main'
    Set-TestFile (P @($src, 'scripts', 'uosc', 'lib', 'utils.lua')) '-- fake uosc lib'
    Set-TestFile (P @($src, 'fonts', 'uosc_icons.otf')) 'icons'
    Set-TestFile (P @($src, 'fonts', 'uosc_textures.ttf')) 'textures'
    $zip = P @($Dir, 'uosc.zip')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $zip)
    return $zip
}

# A zip like Anime4K's release: flat, every shader sosc needs and a few more.
# -Hostile adds entries that must never be extracted (other names, folders,
# paths going up); -Missing leaves one required shader out.
function New-FakeAnime4KZip {
    param([string]$Dir, [switch]$Hostile, [string]$Missing = '')
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $zip = P @($Dir, 'Anime4K_v4.0.zip')
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
    try {
        $names = @($script:Anime4KRequired) + @('Anime4K_Thin_HQ.glsl', 'Anime4K_Darken_Fast.glsl')
        if ($Hostile) { $names += @('evil.lua', 'sub/Anime4K_Nested.glsl', '../Anime4K_Up.glsl', 'Anime4K_x.glsl.lua', 'README.md') }
        foreach ($n in $names) {
            if ($n -eq $Missing) { continue }
            $entry = $archive.CreateEntry($n)
            $w = New-Object System.IO.StreamWriter($entry.Open())
            try { $w.Write('// fake ' + $n) } finally { $w.Dispose() }
        }
    }
    finally { $archive.Dispose() }
    return $zip
}

# Prepares fake uosc/thumbfast/Anime4K downloads with matching hashes; returns artifacts.
function New-FakeArtifacts {
    param([string]$Dir)
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $zip = New-FakeUoscZip $Dir
    $thumb = P @($Dir, 'thumbfast-src.lua')
    Set-TestFile $thumb '-- fake thumbfast'
    $a4k = New-FakeAnime4KZip (P @($Dir, 'a4k'))
    $script:UoscSha256 = Get-SoscFileSha256 $zip
    $script:ThumbfastSha256 = Get-SoscFileSha256 $thumb
    $script:Anime4KSha256 = Get-SoscFileSha256 $a4k
    $script:FakeDownloads = @{}
    $script:FakeDownloads[$script:UoscUrl] = $zip
    $script:FakeDownloads[$script:ThumbfastUrl] = $thumb
    $script:FakeDownloads[$script:Anime4KUrl] = $a4k
    $work = P @($Dir, 'work')
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    return (Get-SoscArtifacts -TempDir $work)
}

$OriginalUoscSha = $script:UoscSha256
$OriginalThumbSha = $script:ThumbfastSha256
$OriginalAnime4KSha = $script:Anime4KSha256
# The graphics card the tests see unless they say otherwise.
$script:SoscGpuProbe = { @('Intel(R) UHD Graphics 620') }
$Source = Get-SoscSource -TempDir $TestRoot

# ---------------------------------------------------------------------------
# Script hygiene
# ---------------------------------------------------------------------------

Test-Case 'sosc.ps1 is pure ASCII (Windows PowerShell 5.1 reads it as ANSI)' {
    $bytes = Get-TestBytes $InstallScript
    $bad = @($bytes | Where-Object { $_ -gt 127 })
    Assert-Equal $bad.Count 0 'non-ASCII bytes'
}

Test-Case 'sosc.ps1 avoids PowerShell 7-only syntax' {
    $text = Get-TestText $InstallScript
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    Assert-Equal @($errors).Count 0 'parse errors'
    $kinds = @($tokens | ForEach-Object { $_.Kind.ToString() })
    foreach ($k in @('QuestionQuestion', 'QuestionQuestionEquals', 'QuestionDot', 'QuestionLBracket', 'AndAnd', 'OrOr')) {
        Assert-True (-not ($kinds -contains $k)) ('token ' + $k)
    }
    $ternary = @($tokens | Where-Object { $_.Kind.ToString() -eq 'QuestionMark' })
    Assert-Equal $ternary.Count 0 'ternary operator'
    Assert-True ($text -notmatch 'Invoke-Expression|\biex\b.*\(') 'no Invoke-Expression'
}

Test-Case 'repository sosc files have no BOM' {
    foreach ($f in @(Get-ChildItem -LiteralPath (P @($RepoRoot, 'portable_config')) -Recurse -File)) {
        Assert-True (-not (Test-HasBom $f.FullName)) ('BOM in ' + $f.Name)
    }
}

Test-Case 'Spanish messages decode their \u escapes' {
    Set-SoscLanguage 'es'
    try {
        Assert-Equal (T 'invalid') ('Opci' + [char]0x00F3 + 'n no v' + [char]0x00E1 + 'lida.') 'es invalid'
        Assert-True ((T 'menu').Contains("`n")) 'menu has line breaks'
        Assert-True ((T 'release_unpublished').Contains('install\sosc.ps1')) 'single backslash'
        foreach ($k in $script:SoscStringsEn.Keys) { Assert-True ($script:SoscStringsEs.ContainsKey($k)) ('es key ' + $k) }
        foreach ($k in $script:SoscStringsEs.Keys) { Assert-True ($script:SoscStringsEn.ContainsKey($k)) ('en key ' + $k) }
    }
    finally { Set-SoscLanguage 'en' }
    Assert-True ((T 'release_unpublished').Contains('install\sosc.ps1')) 'en single backslash'
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

Test-Case 'detects AnimeJaNai with portable_config' {
    Reset-Fake
    $base = New-TestDir 'det-aj'
    $e = New-FakeEnv $base
    $exe = P @($base, 'Local', 'Programs', 'mpv-AnimeJaNai', 'mpvnet.exe')
    Set-TestFile $exe
    New-Item -ItemType Directory -Path (P @($base, 'Local', 'Programs', 'mpv-AnimeJaNai', 'portable_config')) | Out-Null
    $found = @(Find-SoscPlayers -Env $e)
    Assert-Equal $found.Count 1 'candidates'
    Assert-Equal $found[0].Kind 'AnimeJaNai' 'kind'
    Assert-Equal $found[0].Exe (Get-SoscFullPath $exe) 'exe'
    Assert-Equal $found[0].ConfigDir (Get-SoscFullPath (P @($base, 'Local', 'Programs', 'mpv-AnimeJaNai', 'portable_config'))) 'config'
    Assert-True $found[0].Portable 'portable'
    Assert-True $found[0].Writable 'writable'
    Assert-Equal $found[0].UserConfigDir (P @($base, 'Roaming', 'mpv.net')) 'fallback'
}

Test-Case 'mpv.net without portable_config uses %APPDATA%\mpv.net' {
    Reset-Fake
    $base = New-TestDir 'det-net'
    $e = New-FakeEnv $base
    $exe = P @($base, 'Local', 'Programs', 'mpv.net', 'mpvnet.exe')
    Set-TestFile $exe
    $found = @(Find-SoscPlayers -Env $e)
    Assert-Equal $found.Count 1 'candidates'
    Assert-Equal $found[0].Kind 'mpv.net' 'kind'
    Assert-Equal $found[0].ConfigDir (Get-SoscFullPath (P @($base, 'Roaming', 'mpv.net'))) 'config'
    Assert-True (-not $found[0].Portable) 'not portable'
    Assert-True (-not $found[0].Exists) 'folder not there yet'
}

Test-Case 'mpv.net with portable_config (Program Files) uses it' {
    Reset-Fake
    $base = New-TestDir 'det-net-portable'
    $e = New-FakeEnv $base
    $exe = P @($base, 'Program Files', 'mpv.net', 'mpvnet.exe')
    Set-TestFile $exe
    New-Item -ItemType Directory -Path (P @($base, 'Program Files', 'mpv.net', 'portable_config')) | Out-Null
    $found = @(Find-SoscPlayers -Env $e)
    Assert-Equal $found.Count 1 'candidates'
    Assert-Equal $found[0].ConfigDir (Get-SoscFullPath (P @($base, 'Program Files', 'mpv.net', 'portable_config'))) 'config'
}

Test-Case 'mpv in PATH, scoop shim and %APPDATA%\mpv' {
    Reset-Fake
    $base = New-TestDir 'det-mpv'
    $e = New-FakeEnv $base
    $real = P @($base, 'User', 'scoop', 'apps', 'mpv', '1.0', 'mpv.exe')
    Set-TestFile $real
    New-Item -ItemType Directory -Path (P @($base, 'User', 'scoop', 'apps', 'mpv', '1.0', 'portable_config')) | Out-Null
    $shim = P @($base, 'User', 'scoop', 'shims', 'mpv.exe')
    Set-TestFile $shim
    Set-TestFile (P @($base, 'User', 'scoop', 'shims', 'mpv.shim')) ('path = "' + $real + '"' + "`r`n")
    $script:FakeCommands['mpv.exe'] = $shim
    $plain = P @($base, 'Program Files', 'mpv', 'mpv.exe')
    Set-TestFile $plain
    $found = @(Find-SoscPlayers -Env $e)
    Assert-Equal $found.Count 2 'candidates'
    Assert-Equal $found[0].Exe (Get-SoscFullPath $real) 'shim resolved'
    Assert-Equal $found[0].ConfigDir (Get-SoscFullPath (P @($base, 'User', 'scoop', 'apps', 'mpv', '1.0', 'portable_config'))) 'scoop portable'
    Assert-Equal $found[1].Kind 'mpv' 'kind'
    Assert-Equal $found[1].ConfigDir (Get-SoscFullPath (P @($base, 'Roaming', 'mpv'))) 'user config'
}

Test-Case 'config folders without a player are listed' {
    Reset-Fake
    $base = New-TestDir 'det-folders'
    $e = New-FakeEnv $base
    New-Item -ItemType Directory -Path (P @($base, 'Roaming', 'mpv')) -Force | Out-Null
    New-Item -ItemType Directory -Path (P @($base, 'Roaming', 'mpv.net')) -Force | Out-Null
    $found = @(Find-SoscPlayers -Env $e)
    Assert-Equal $found.Count 2 'candidates'
    Assert-Equal $found[0].Kind 'folder' 'kind 0'
    Assert-Equal $found[1].Kind 'folder' 'kind 1'
    Assert-Equal $found[0].Exe '' 'no exe'
}

Test-Case 'deduplicates by config folder' {
    Reset-Fake
    $base = New-TestDir 'det-dedup'
    $e = New-FakeEnv $base
    $exe = P @($base, 'Program Files', 'mpv', 'mpv.exe')
    Set-TestFile $exe
    $other = P @($base, 'Tools', 'mpv', 'mpv.exe')
    Set-TestFile $other
    $script:FakeCommands['mpv.exe'] = $other
    New-Item -ItemType Directory -Path (P @($base, 'Roaming', 'mpv')) -Force | Out-Null
    $found = @(Find-SoscPlayers -Env $e)
    Assert-Equal $found.Count 1 'one entry for %APPDATA%\mpv'
    Assert-Equal $found[0].Kind 'mpv' 'player wins over bare folder'
    Assert-Equal $found[0].Exe (Get-SoscFullPath $other) 'first exe found (PATH) kept'
}

Test-Case 'marks folders without write permission and offers the user folder' {
    Reset-Fake
    $base = New-TestDir 'det-ro'
    $e = New-FakeEnv $base
    Set-TestFile (P @($base, 'Program Files', 'mpv', 'mpv.exe'))
    $portable = P @($base, 'Program Files', 'mpv', 'portable_config')
    New-Item -ItemType Directory -Path $portable | Out-Null
    $script:FakeReadOnly = @($portable)
    $found = @(Find-SoscPlayers -Env $e)
    Assert-Equal $found.Count 1 'candidates'
    Assert-True (-not $found[0].Writable) 'not writable'
    Assert-Equal $found[0].UserConfigDir (P @($base, 'Roaming', 'mpv')) 'fallback'
    $script:NonInteractive = $true
    $r = Resolve-SoscWritable -Env $e -Candidate $found[0]
    Assert-Equal $r $null 'skipped with -Yes'
    $script:NonInteractive = $false
    function Read-SoscLine { param([string]$Prompt) return 'y' }
    try {
        $r = Resolve-SoscWritable -Env $e -Candidate $found[0]
        Assert-Equal $r.ConfigDir (Get-SoscFullPath (P @($base, 'Roaming', 'mpv'))) 'fallback chosen'
        Assert-True ($script:SoscWarnings.Count -ge 2) 'warned (read-only + portable note)'
    }
    finally {
        Remove-Item Function:\Read-SoscLine
        $script:NonInteractive = $true
    }
}

Test-Case 'default write test really writes (and cleans up)' {
    $d = New-TestDir 'writable'
    Assert-True (Test-SoscDirWritable $d) 'writable dir'
    Assert-True (Test-SoscDirWritable (P @($d, 'not', 'yet'))) 'missing dir: tests nearest parent'
    Assert-Equal @(Get-ChildItem -LiteralPath $d -Force).Count 0 'probe removed'
}

Test-Case 'MPV_HOME replaces %APPDATA%\mpv for mpv' {
    Reset-Fake
    $base = New-TestDir 'det-home'
    $e = New-FakeEnv $base
    $e.MpvHome = P @($base, 'MyMpv')
    Set-TestFile (P @($base, 'Program Files', 'mpv', 'mpv.exe'))
    $found = @(Find-SoscPlayers -Env $e)
    Assert-Equal $found[0].ConfigDir (Get-SoscFullPath (P @($base, 'MyMpv'))) 'config'
}

Test-Case 'reports sosc already installed (record or by hand)' {
    Reset-Fake
    $base = New-TestDir 'det-installed'
    $e = New-FakeEnv $base
    $mpv = P @($base, 'Roaming', 'mpv')
    Set-TestFile (P @($mpv, 'sosc-installed.txt')) "# x`r`nsosc_version=1.2.3`r`n"
    $net = P @($base, 'Roaming', 'mpv.net')
    Set-TestFile (P @($net, 'scripts', 'sosc-palettes.lua')) '--'
    $found = @(Find-SoscPlayers -Env $e)
    Assert-True $found[0].Installed 'record'
    Assert-Equal $found[0].InstalledVersion '1.2.3' 'version'
    Assert-True (-not $found[0].Manual) 'not manual'
    Assert-True $found[1].Installed 'manual'
    Assert-True $found[1].Manual 'manual flag'
}

Test-Case 'a typed portable_config next to mpvnet.exe is recognised' {
    Reset-Fake
    $base = New-TestDir 'manual-target'
    $e = New-FakeEnv $base
    $exe = P @($base, 'Apps', 'Mi reproductor', 'mpvnet.exe')
    Set-TestFile $exe
    $cfg = P @($base, 'Apps', 'Mi reproductor', 'portable_config')
    $c = Resolve-SoscManualTarget -Env $e -Path ('"' + $cfg + '"') -Candidates @()
    Assert-Equal $c.Kind 'mpv.net' 'kind'
    Assert-Equal $c.Exe $exe 'exe'
    $c2 = Resolve-SoscManualTarget -Env $e -Path (P @($base, 'Elsewhere')) -Candidates @()
    Assert-Equal $c2.Kind 'folder' 'plain folder'
}

Test-Case 'selection parsing' {
    $s = ConvertFrom-SoscSelection -Text '1,3' -Count 3
    Assert-Equal ([string]::Join(',', $s.Indexes)) '0,2' 'indexes'
    $s = ConvertFrom-SoscSelection -Text ' 2 , o ' -Count 2
    Assert-True $s.Other 'other'
    Assert-Equal ([string]::Join(',', $s.Indexes)) '1' 'index with other'
    Assert-True (ConvertFrom-SoscSelection -Text '0' -Count 2).Quit 'quit'
    Assert-Equal (ConvertFrom-SoscSelection -Text '4' -Count 3) $null 'out of range'
    Assert-Equal (ConvertFrom-SoscSelection -Text 'abc' -Count 3) $null 'garbage'
    Assert-Equal (ConvertFrom-SoscSelection -Text '' -Count 3) $null 'empty'
}

# ---------------------------------------------------------------------------
# Managed blocks
# ---------------------------------------------------------------------------

$BlockB = $script:BlockBegin
$BlockE = $script:BlockEnd

Test-Case 'block appended to an LF file, idempotent, removable' {
    $orig = "a=1`nb=2`n"
    $t1 = Set-SoscBlockText -Text $orig -BlockLines @('x', 'y')
    Assert-Equal $t1 ("a=1`nb=2`n" + $BlockB + "`nx`ny`n" + $BlockE + "`n") 'appended'
    $t2 = Set-SoscBlockText -Text $t1 -BlockLines @('x', 'y')
    Assert-Equal $t2 $t1 'idempotent'
    Assert-Equal (Remove-SoscBlockText -Text $t1) $orig 'removed'
}

Test-Case 'block keeps CRLF and replaces in place' {
    $orig = "a=1`r`n" + $BlockB + "`r`nold`r`n" + $BlockE + "`r`nz=9`r`n"
    $t = Set-SoscBlockText -Text $orig -BlockLines @('new1', 'new2')
    Assert-Equal $t ("a=1`r`n" + $BlockB + "`r`nnew1`r`nnew2`r`n" + $BlockE + "`r`nz=9`r`n") 'replaced in place'
    Assert-Equal (Remove-SoscBlockText -Text $t) "a=1`r`nz=9`r`n" 'removed in place'
}

Test-Case 'block on a file without final newline and on an empty file' {
    $t = Set-SoscBlockText -Text 'a=1' -BlockLines @('x')
    Assert-Equal $t ("a=1`r`n" + $BlockB + "`r`nx`r`n" + $BlockE + "`r`n") 'no final newline (no line ending known: CRLF)'
    $t = Set-SoscBlockText -Text "a=1`nb" -BlockLines @('x')
    Assert-Equal $t ("a=1`nb`n" + $BlockB + "`nx`n" + $BlockE + "`n") 'LF detected'
    $t = Set-SoscBlockText -Text '' -BlockLines @('x')
    Assert-Equal $t ($BlockB + "`r`nx`r`n" + $BlockE + "`r`n") 'empty'
    Assert-Equal (Remove-SoscBlockText -Text $t) '' 'back to empty'
}

Test-Case 'incomplete or repeated block is refused' {
    Assert-Throws { Set-SoscBlockText -Text ($BlockB + "`nx`n") -BlockLines @('y') } '*incomplete*' 'begin only'
    Assert-Throws { Remove-SoscBlockText -Text ("x`n" + $BlockE + "`n") } '*incomplete*' 'end only'
    Assert-Throws { Remove-SoscBlockText -Text ($BlockB + "`n" + $BlockE + "`n" + $BlockB + "`n" + $BlockE + "`n") } '*incomplete*' 'twice'
}

Test-Case 'mpv.conf block: options, includes last, [default] after a profile' {
    $b = Get-SoscMpvConfBlock "sub-font=Arial`n"
    Assert-Equal ([string]::Join('|', $b.Lines)) 'osc=no|osd-bar=no|include="~~/sosc-palette.conf"|include="~~/sosc-subs.conf"|include="~~/sosc-upscale.conf"' 'lines'
    Assert-True (-not ($b.Lines -contains 'border=no')) 'no border=no'
    $b = Get-SoscMpvConfBlock "vo=gpu`n[anime]`nprofile-cond=1`n"
    Assert-Equal $b.Lines[0] '[default]' 'default section'
    $b = Get-SoscMpvConfBlock "[anime]`nx=1`n[default]`ny=2`n"
    Assert-True (-not ($b.Lines -contains '[default]')) 'already back at [default]'
    $b = Get-SoscMpvConfBlock ("a=1`n" + $BlockB + "`nosc=no`n" + $BlockE + "`n[after]`nz=1`n")
    Assert-Equal $b.Lines[0] '[default]' 'the block moves to the end, so a profile after the old block counts'
}

Test-Case 'mpv.conf profile headers follow mpv rules' {
    Assert-Equal (Get-SoscProfileHeader '[anime] # my profile') 'anime' 'comment after header'
    Assert-Equal (Get-SoscProfileHeader '  [anime]  ') 'anime' 'blanks around'
    Assert-Equal (Get-SoscProfileHeader '[ anime ]') ' anime ' 'name not trimmed (as mpv)'
    Assert-Equal (Get-SoscProfileHeader '[]') '' 'empty header'
    Assert-Equal (Get-SoscProfileHeader '[anime]x') $null 'extra characters: not a header'
    Assert-Equal (Get-SoscProfileHeader '[anime') $null 'no closing bracket'
    Assert-Equal (Get-SoscProfileHeader '# [anime]') $null 'commented out'
    Assert-Equal (Get-SoscProfileHeader 'sub-font=[x]') $null 'option line'
    Assert-True (Get-SoscMpvConfBlock "[anime] # c`nx=1`n").NeedsDefault 'header with comment needs [default]'
    Assert-True (Get-SoscMpvConfBlock "[anime]`n[DEFAULT]`n").NeedsDefault '[DEFAULT] is another profile'
    Assert-True (-not (Get-SoscMpvConfBlock "[anime]`n[]`nx=1`n").NeedsDefault) '[] is the default profile'
    Assert-True (-not (Get-SoscMpvConfBlock "[anime]`n  [default]  # back`n").NeedsDefault) '[default] with blanks and comment'
    Assert-True (Get-SoscMpvConfBlock "[anime]`n[ default ]`n").NeedsDefault '[ default ] is another profile'
    Assert-True (-not (Get-SoscMpvConfBlock "[anime]x`n").NeedsDefault) 'malformed header ignored'
}

Test-Case 'mpv.conf: on update the block moves to the end, after the user lines' {
    $d = New-TestDir 'block-move'
    $p = P @($d, 'mpv.conf')
    $old = "a=1`n" + $BlockB + "`nosc=no`n" + $BlockE + "`nsub-font-size=50`n"
    Set-TestFile $p $old
    [void](Update-SoscManagedFile -Path $p -Kind 'mpv')
    $t = Get-TestText $p
    Assert-True ($t.StartsWith("a=1`nsub-font-size=50`n" + $BlockB + "`n")) ('user lines first, block after: ' + $t)
    Assert-True ($t.EndsWith('include="~~/sosc-upscale.conf"' + "`n" + $BlockE + "`n")) 'block last, LF kept'
    Assert-Equal @([regex]::Matches($t, [regex]::Escape($BlockB))).Count 1 'one block'
    [void](Update-SoscManagedFile -Path $p -Kind 'mpv')
    Assert-Equal (Get-TestText $p) $t 'idempotent once at the end'
    Set-TestFile $p ($t + "[anime]`nprofile-cond=1`n")
    [void](Update-SoscManagedFile -Path $p -Kind 'mpv')
    $t2 = Get-TestText $p
    Assert-True ($t2.StartsWith("a=1`nsub-font-size=50`n[anime]`nprofile-cond=1`n" + $BlockB + "`n[default]`nosc=no`n")) ('moved after the profile with [default]: ' + $t2)
    Remove-SoscManagedFile -Path $p -Root $d -CreatedBySosc $false
    Assert-Equal (Get-TestText $p) "a=1`nsub-font-size=50`n[anime]`nprofile-cond=1`n" 'removal leaves the user lines'
    # A file holding only an LF block keeps LF when the block is rewritten.
    $q = P @($d, 'only.conf')
    Set-TestFile $q ($BlockB + "`nosc=no`n" + $BlockE + "`n")
    [void](Update-SoscManagedFile -Path $q -Kind 'mpv')
    Assert-True (-not (Get-TestText $q).Contains("`r")) 'LF kept'
    # input.conf: the block stays where it is.
    $i = P @($d, 'input.conf')
    Set-TestFile $i ("a cycle pause`n" + $BlockB + "`nold`n" + $BlockE + "`nb cycle mute`n")
    [void](Update-SoscManagedFile -Path $i -Kind 'input')
    Assert-True ((Get-TestText $i).EndsWith($BlockE + "`nb cycle mute`n")) 'input.conf block left in place'
}

Test-Case 'input.conf: taken keys are reported and left alone' {
    $text = "Alt+p cycle pause`nALT+s script-binding sosc_skip/skip  # mine`n# Alt+t commented`n"
    $b = Get-SoscInputBlock $text
    Assert-Equal ([string]::Join('|', $b.Lines)) 'Alt+t  script-binding sosc_subs/open-menu' 'only Alt+t added'
    Assert-Equal @($b.Taken).Count 1 'taken'
    Assert-Equal $b.Taken[0].Key 'Alt+p' 'taken key'
    Assert-Equal @($b.Same).Count 1 'same'
    $b = Get-SoscInputBlock "Alt+P cycle pause`n"
    Assert-Equal @($b.Taken).Count 0 'Alt+P (shift) is another key'
}

Test-Case 'Update-SoscManagedFile: new file, no BOM, CRLF; warning for taken key' {
    $d = New-TestDir 'managed'
    $p = P @($d, 'input.conf')
    [void](Update-SoscManagedFile -Path $p -Kind 'input')
    Assert-True (-not (Test-HasBom $p)) 'no BOM'
    Assert-True ((Get-TestText $p).Contains("`r`n")) 'CRLF'
    $q = P @($d, 'input2.conf')
    Set-TestFile $q "Alt+t cycle sub`n"
    [void](Update-SoscManagedFile -Path $q -Kind 'input')
    Assert-True (@($script:SoscWarnings | Where-Object { $_ -like '*Alt+t*' }).Count -eq 1) 'warned about Alt+t'
    Assert-True ((Get-TestText $q).StartsWith("Alt+t cycle sub`n")) 'user line untouched'
}

Test-Case 'Update-SoscManagedFile keeps an existing BOM and non-UTF-8 bytes' {
    $d = New-TestDir 'managed-enc'
    $p = P @($d, 'mpv.conf')
    $latin = [byte[]](0x23, 0x20, 0x63, 0x61, 0x6E, 0x63, 0x69, 0xF3, 0x6E, 0x0A)   # "# canci\xF3n\n" in Latin-1
    [System.IO.File]::WriteAllBytes($p, $latin)
    [void](Update-SoscManagedFile -Path $p -Kind 'mpv')
    $after = Get-TestBytes $p
    for ($i = 0; $i -lt $latin.Length; $i++) { Assert-Equal $after[$i] $latin[$i] ('byte ' + $i) }
    Remove-SoscManagedFile -Path $p -Root $d -CreatedBySosc $false
    Assert-Equal ([Convert]::ToBase64String((Get-TestBytes $p))) ([Convert]::ToBase64String($latin)) 'restored bytes'
    $q = P @($d, 'bom.conf')
    [System.IO.File]::WriteAllText($q, "x=1`n", (New-Object System.Text.UTF8Encoding($true)))
    [void](Update-SoscManagedFile -Path $q -Kind 'mpv')
    Assert-True (Test-HasBom $q) 'BOM kept'
    Assert-Equal @([System.Text.RegularExpressions.Regex]::Matches((Get-TestText $q), [char]0xFEFF)).Count 0 'BOM not duplicated'
}

Test-Case 'thumbfast.conf mpv_path is added once and updated' {
    $d = New-TestDir 'thumbconf'
    $p = P @($d, 'thumbfast.conf')
    Set-TestFile $p "network=yes`nhwdec=yes`n"
    Set-SoscConfOption -Path $p -Key 'mpv_path' -Value 'C:\Users\Jos\u00e9\mpv net\mpvnet.exe' -Comment 'c'
    Set-SoscConfOption -Path $p -Key 'mpv_path' -Value 'C:\Users\Ana\mpvnet.exe' -Comment 'c'
    $t = Get-TestText $p
    Assert-Equal @([regex]::Matches($t, 'mpv_path=')).Count 1 'one mpv_path'
    Assert-True ($t.Contains('mpv_path=C:\Users\Ana\mpvnet.exe')) 'updated value'
    Assert-True ($t.StartsWith("network=yes`nhwdec=yes`n")) 'rest kept'
}

# ---------------------------------------------------------------------------
# Safety helpers
# ---------------------------------------------------------------------------

Test-Case 'inside-target check before deleting' {
    $d = New-TestDir 'inside'
    $cfg = P @($d, 'portable_config')
    Set-TestFile (P @($cfg, 'scripts', 'a.lua'))
    Set-TestFile (P @($d, 'portable_config-other', 'keep.txt'))
    Assert-True (Test-SoscInside (P @($cfg, 'scripts')) $cfg) 'child'
    Assert-True (-not (Test-SoscInside $cfg $cfg)) 'root itself'
    Assert-True (-not (Test-SoscInside (P @($d, 'portable_config-other')) $cfg)) 'sibling with same prefix'
    Assert-True (-not (Test-SoscInside (P @($cfg, '..', 'portable_config-other')) $cfg)) 'dot-dot escape'
    Assert-Throws { Remove-SoscItem -Path (P @($d, 'portable_config-other')) -Root $cfg } '*outside*' 'sibling delete'
    Assert-Throws { Remove-SoscItem -Path $cfg -Root $cfg } '*outside*' 'root delete'
    Assert-True (Test-Path -LiteralPath (P @($d, 'portable_config-other', 'keep.txt'))) 'sibling kept'
    Remove-SoscItem -Path (P @($cfg, 'scripts')) -Root $cfg
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts')))) 'inside deleted'
}

Test-Case 'deleting a linked folder removes the link, not its target' {
    $d = New-TestDir 'links'
    $cfg = P @($d, 'cfg')
    $outside = P @($d, 'outside')
    Set-TestFile (P @($outside, 'precious.txt'))
    New-Item -ItemType Directory -Path (P @($cfg, 'scripts')) -Force | Out-Null
    $link = P @($cfg, 'scripts', 'uosc')
    try { New-Item -ItemType SymbolicLink -Path $link -Target $outside | Out-Null } catch { Write-Host '     (symlinks not available, skipped)'; return }
    Remove-SoscItem -Path $link -Root $cfg
    Assert-True (-not (Test-Path -LiteralPath $link)) 'link gone'
    Assert-True (Test-Path -LiteralPath (P @($outside, 'precious.txt'))) 'target intact'
}

Test-Case 'backup copies only what the installer can change' {
    $d = New-TestDir 'backup'
    $cfg = P @($d, 'portable config')
    Set-TestFile (P @($cfg, 'mpv.conf')) 'x=1'
    Set-TestFile (P @($cfg, 'input.conf')) 'a b'
    Set-TestFile (P @($cfg, 'scripts', 'a.lua')) '--'
    Set-TestFile (P @($cfg, 'scripts', 'uosc', 'main.lua')) '--'
    Set-TestFile (P @($cfg, 'script-opts', 'a.conf')) 'k=v'
    Set-TestFile (P @($cfg, 'fonts', 'f.ttf')) 'f'
    Set-TestFile (P @($cfg, 'sosc-palette.conf')) 'p'
    Set-TestFile (P @($cfg, 'sosc-installed.txt')) 'sosc_version=dev'
    Set-TestFile (P @($cfg, 'scripts-desactivados', 'm.lua')) 'm'
    Set-TestFile (P @($cfg, 'sosc-originales', 'script-opts', 'uosc.conf')) 'u'
    Set-TestFile (P @($cfg, 'shaders', 'a.glsl')) 'shader'
    Set-TestFile (P @($cfg, 'cache', 'big.bin')) 'cache'
    Set-TestFile (P @($cfg, 'watch_later', 'ABC')) 'pos'
    Set-TestFile (P @($cfg, '.hidden')) 'h'
    Set-TestFile (P @($cfg, 'mpv-animejanai.conf')) 'aj'
    $script:InfoLog = New-Object System.Collections.Generic.List[string]
    function Write-SoscInfo { param([string]$Message) $script:InfoLog.Add($Message) }
    try { $b = New-SoscBackup -ConfigDir $cfg -Stamp '20260101-000000' }
    finally { Remove-Item Function:\Write-SoscInfo }
    Assert-Equal $b ((Get-SoscFullPath $cfg) + '-respaldo-sosc-20260101-000000') 'name'
    Assert-True (@($script:InfoLog | Where-Object { $_ -like '*MB*' }).Count -eq 1) 'size shown'
    Assert-True (@($script:InfoLog | Where-Object { $_ -like 'Backing up the files sosc touches (*MB)...' }).Count -eq 1) 'says only some files are copied'
    foreach ($rel in @(@('mpv.conf'), @('input.conf'), @('scripts', 'a.lua'), @('scripts', 'uosc', 'main.lua'), @('script-opts', 'a.conf'),
            @('fonts', 'f.ttf'), @('sosc-palette.conf'), @('sosc-installed.txt'), @('scripts-desactivados', 'm.lua'),
            @('sosc-originales', 'script-opts', 'uosc.conf'))) {
        Assert-True (Test-Path -LiteralPath (P (@($b) + $rel))) ('copied ' + [string]::Join('/', $rel))
    }
    Assert-Equal (Get-TestText (P @($b, 'mpv.conf'))) 'x=1' 'file content'
    foreach ($name in @('shaders', 'cache', 'watch_later', '.hidden', 'mpv-animejanai.conf')) {
        Assert-True (-not (Test-Path -LiteralPath (P @($b, $name)))) ('not copied ' + $name)
    }
    $b2 = New-SoscBackup -ConfigDir $cfg -Stamp '20260101-000000'
    Assert-Equal $b2 ($b + '-2') 'same second: new name'
    $empty = P @($d, 'only-shaders')
    Set-TestFile (P @($empty, 'shaders', 'a.glsl')) 's'
    Assert-Equal (New-SoscBackup -ConfigDir $empty -Stamp '20260101-000000') '' 'nothing to back up: no backup'
    Assert-True (-not (Test-Path -LiteralPath ($empty + '-respaldo-sosc-20260101-000000'))) 'no empty backup folder'
}

Test-Case 'backup skips links and deletes a copy that fails half-way' {
    $d = New-TestDir 'backup-links'
    $cfg = P @($d, 'cfg')
    $outside = P @($d, 'outside')
    Set-TestFile (P @($outside, 'huge.bin')) 'big'
    Set-TestFile (P @($cfg, 'mpv.conf')) 'x=1'
    Set-TestFile (P @($cfg, 'scripts', 'a.lua')) '--'
    $linked = $true
    try {
        New-Item -ItemType SymbolicLink -Path (P @($cfg, 'scripts', 'loop')) -Target $cfg | Out-Null
        New-Item -ItemType SymbolicLink -Path (P @($cfg, 'fonts')) -Target $outside | Out-Null
    }
    catch { $linked = $false; Write-Host '     (symlinks not available, link part skipped)' }
    if ($linked) {
        $b = New-SoscBackup -ConfigDir $cfg -Stamp '20260101-000000'
        Assert-True (Test-Path -LiteralPath (P @($b, 'scripts', 'a.lua'))) 'real file copied'
        Assert-True (-not (Test-Path -LiteralPath (P @($b, 'scripts', 'loop')))) 'link inside scripts skipped'
        Assert-True (-not (Test-Path -LiteralPath (P @($b, 'fonts')))) 'linked fonts folder skipped'
        Assert-True (@($script:SoscWarnings | Where-Object { $_ -like '*link*' }).Count -eq 2) 'two warnings'
    }
    function Copy-SoscTree { param([string]$From, [string]$To) New-Item -ItemType Directory -Path $To -Force | Out-Null; throw 'disk full' }
    try { Assert-Throws { New-SoscBackup -ConfigDir $cfg -Stamp '20260202-000000' } '*disk full*' 'failing copy' }
    finally { Remove-Item Function:\Copy-SoscTree }
    Assert-True (-not (Test-Path -LiteralPath ((Get-SoscFullPath $cfg) + '-respaldo-sosc-20260202-000000'))) 'partial copy deleted'
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    function Copy-Item { throw 'disk full' }
    try { Assert-Throws { Install-SoscTarget -Candidate $cand -Source $Source -Artifacts ([pscustomobject]@{ UoscDir = ''; ThumbfastFile = '' }) -Stamp '20260303-000000' } '*Could not back up*' 'install stops' }
    finally { Remove-Item Function:\Copy-Item }
    Assert-True (-not (Test-Path -LiteralPath ((Get-SoscFullPath $cfg) + '-respaldo-sosc-20260303-000000'))) 'no partial backup left by install'
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) 'x=1' 'folder untouched'
}

Test-Case 'conflicting interfaces are found with their conf and fonts' {
    $d = New-TestDir 'conflicts'
    $cfg = P @($d, 'cfg')
    foreach ($n in @('modernz.lua', 'osc.lua', 'mpv-osc-tethys.lua', 'sosc-skip.lua', 'thumbfast.lua', 'autoload.lua', 'oscillator.lua')) {
        Set-TestFile (P @($cfg, 'scripts', $n))
    }
    Set-TestFile (P @($cfg, 'script-opts', 'modernz.conf'))
    Set-TestFile (P @($cfg, 'script-opts', 'uosc.conf'))
    Set-TestFile (P @($cfg, 'fonts', 'modernz-icons.ttf'))
    Set-TestFile (P @($cfg, 'fonts', 'other.ttf'))
    $found = @(Find-SoscConflicts $cfg | ForEach-Object { Get-SoscRelativePath -Path $_ -Root $cfg } | Sort-Object)
    Assert-Equal ([string]::Join(',', $found)) 'fonts/modernz-icons.ttf,script-opts/modernz.conf,scripts/modernz.lua,scripts/mpv-osc-tethys.lua,scripts/osc.lua' 'found'
}

# ---------------------------------------------------------------------------
# Downloads
# ---------------------------------------------------------------------------

Test-Case 'download URLs: HTTPS and GitHub only' {
    Assert-SoscDownloadUrl $script:UoscUrl
    Assert-SoscDownloadUrl $script:ThumbfastUrl
    Assert-Throws { Assert-SoscDownloadUrl 'http://github.com/x.zip' } '*HTTPS*' 'http'
    Assert-Throws { Assert-SoscDownloadUrl 'https://example.com/x.zip' } '*HTTPS*' 'other host'
    Assert-Throws { Assert-SoscDownloadUrl 'https://github.com.evil.example/x.zip' } '*HTTPS*' 'look-alike host'
}

Test-Case 'pinned versions and hashes' {
    Assert-Equal $OriginalUoscSha '4be9da3289285300fa374496c3f1bfd7bb20ac08e890d25bd5a06b28eebe4882' 'uosc sha'
    Assert-Equal $OriginalThumbSha 'a3d08e71eae8b892f6cd39f9593ea219768e709312d176bca883841b156448bf' 'thumbfast sha'
    Assert-Equal $OriginalAnime4KSha '139cd282086457c5adc79caf7b75b8b825091d71c9b54958c18745fea62d7ed7' 'Anime4K sha'
    Assert-Equal $script:Anime4KUrl 'https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip' 'Anime4K url'
    Assert-True ($script:Anime4KUrl.Contains('/v' + $script:Anime4KVersion + '/')) 'Anime4K url has version'
    Assert-SoscDownloadUrl $script:Anime4KUrl
    Assert-True ($script:UoscUrl.Contains('/' + $script:UoscVersion + '/')) 'uosc url has version'
    Assert-True ($script:ThumbfastUrl.Contains($script:ThumbfastCommit)) 'thumbfast url has commit'
}

Test-Case 'SHA256 verification accepts the right file and rejects a tampered one' {
    $d = New-TestDir 'sha'
    $good = P @($d, 'good.lua')
    Set-TestFile $good 'print(1)'
    $hash = Get-SoscFileSha256 $good
    $script:FakeDownloads = @{ 'https://github.com/a/b.lua' = $good }
    $out = P @($d, 'out.lua')
    Invoke-SoscVerifiedDownload -Url 'https://github.com/a/b.lua' -Sha256 $hash.ToUpperInvariant() -OutFile $out
    Assert-True (Test-Path -LiteralPath $out) 'accepted'
    $out2 = P @($d, 'out2.lua')
    Assert-Throws { Invoke-SoscVerifiedDownload -Url 'https://github.com/a/b.lua' -Sha256 ('0' * 64) -OutFile $out2 } '*SHA256*' 'rejected'
    Assert-True (-not (Test-Path -LiteralPath $out2)) 'rejected file deleted'
    Assert-Throws { Invoke-SoscVerifiedDownload -Url 'https://github.com/a/b.lua' -Sha256 '' -OutFile $out2 } '*SHA256*' 'empty hash'
}

Test-Case 'uosc zip with a wrong hash is never extracted' {
    $d = New-TestDir 'sha-uosc'
    [void](New-FakeArtifacts (P @($d, 'a')))
    $script:UoscSha256 = 'f' * 64
    $work = P @($d, 'work2')
    New-Item -ItemType Directory -Path $work | Out-Null
    Assert-Throws { Get-SoscArtifacts -TempDir $work } '*SHA256*' 'uosc'
    Assert-True (-not (Test-Path -LiteralPath (P @($work, 'uosc')))) 'not extracted'
}

Test-Case 'run on its own without a published release: clear message' {
    Assert-Throws { Get-SoscReleaseSource -TempDir $TestRoot } '*no published release*' 'release'
    $saved = $script:SoscScriptRoot
    try {
        $script:SoscScriptRoot = ''
        Assert-Throws { Get-SoscSource -TempDir $TestRoot } '*no published release*' 'iex mode'
        # A script root with no repository around it: same message.
        $script:SoscScriptRoot = New-TestDir 'lonely-script'
        Assert-Throws { Get-SoscSource -TempDir $TestRoot } '*no published release*' 'downloaded file'
    }
    finally { $script:SoscScriptRoot = $saved }
}

# A sosc.zip like the one tools/make-release.sh builds: portable_config, LICENSE
# and README.md at its root.
function New-TestReleaseZip {
    param([string]$Dir, [switch]$NoConfig)
    $src = P @($Dir, 'zip-src')
    New-Item -ItemType Directory -Path $src -Force | Out-Null
    if (-not $NoConfig) { Copy-Item -LiteralPath (P @($RepoRoot, 'portable_config')) -Destination (P @($src, 'portable_config')) -Recurse }
    Copy-Item -LiteralPath (P @($RepoRoot, 'LICENSE')) -Destination (P @($src, 'LICENSE'))
    Copy-Item -LiteralPath (P @($RepoRoot, 'README.md')) -Destination (P @($src, 'README.md'))
    $zip = P @($Dir, 'sosc.zip')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $zip)
    return $zip
}

$TestReleaseUrl = 'https://github.com/SCEPTICG/sosc/releases/download/v9.9.9/sosc.zip'

Test-Case 'release build: sosc files come from its zip, checked by SHA256, never from a copy next to it' {
    $d = New-TestDir 'release-src'
    $zip = New-TestReleaseZip $d
    $saved = @($script:SoscReleaseUrl, $script:SoscReleaseSha256, $script:SoscVersion)
    try {
        $script:SoscReleaseUrl = $TestReleaseUrl
        $script:SoscReleaseSha256 = (Get-SoscFileSha256 $zip).ToUpperInvariant()
        $script:SoscVersion = '9.9.9'
        $script:FakeDownloads = @{ $TestReleaseUrl = $zip }
        # The script root still points at this repository, which has a
        # portable_config: a release build must not use it.
        $work = New-TestDir 'release-src-work'
        $src = Get-SoscSource -TempDir $work
        Assert-True (Test-SoscInside -Path $src.ConfigDir -Root $work) ('from the zip: ' + $src.ConfigDir)
        Assert-Equal $src.Version '9.9.9' 'version'
        Assert-Equal $src.Commit '' 'no commit'
        foreach ($f in @(Get-ChildItem -LiteralPath (P @($RepoRoot, 'portable_config', 'scripts')) -File)) {
            Assert-Equal (Get-TestText (P @($src.ConfigDir, 'scripts', $f.Name))) (Get-TestText $f.FullName) $f.Name
        }

        $script:SoscReleaseSha256 = 'a' * 64
        $bad = New-TestDir 'release-src-bad'
        Assert-Throws { Get-SoscSource -TempDir $bad } '*SHA256*' 'wrong hash'
        Assert-True (-not (Test-Path -LiteralPath (P @($bad, 'sosc')))) 'not extracted'
        Assert-True (-not (Test-Path -LiteralPath (P @($bad, 'sosc.zip')))) 'download deleted'

        $script:SoscReleaseSha256 = ''
        Assert-Throws { Get-SoscSource -TempDir (New-TestDir 'release-src-nohash') } '*SHA256*' 'no hash, no use'

        $empty = New-TestReleaseZip (New-TestDir 'release-src-noconfig') -NoConfig
        $script:FakeDownloads = @{ $TestReleaseUrl = $empty }
        $script:SoscReleaseSha256 = Get-SoscFileSha256 $empty
        Assert-Throws { Get-SoscSource -TempDir (New-TestDir 'release-src-noconfig-work') } '*sosc files not found*' 'zip without portable_config'

        foreach ($u in @('http://github.com/SCEPTICG/sosc/releases/download/v9.9.9/sosc.zip', 'https://example.com/sosc.zip', 'https://github.com.evil.example/sosc.zip')) {
            $script:SoscReleaseUrl = $u
            Assert-Throws { Get-SoscSource -TempDir (New-TestDir 'release-src-url') } '*only HTTPS from GitHub*' $u
        }
    }
    finally {
        $script:SoscReleaseUrl = $saved[0]
        $script:SoscReleaseSha256 = $saved[1]
        $script:SoscVersion = $saved[2]
    }
}

Test-Case 'release markers: each line is there exactly once, empty in the repository' {
    $lines = [System.IO.File]::ReadAllLines($InstallScript)
    foreach ($m in @("`$script:SoscVersion = 'dev'", "`$script:SoscReleaseUrl = ''", "`$script:SoscReleaseSha256 = ''")) {
        Assert-Equal @($lines | Where-Object { $_ -ceq $m }).Count 1 $m
    }
    Assert-Equal $script:SoscReleaseUrl '' 'no URL in the repository'
}

Test-Case 'the installer does not need the repository mpv.conf or input.conf' {
    $d = New-TestDir 'no-repo-conf'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $srcDir = P @($d, 'src', 'portable_config')
    Copy-Item -LiteralPath (P @($RepoRoot, 'portable_config')) -Destination $srcDir -Recurse
    Remove-Item -LiteralPath (P @($srcDir, 'mpv.conf'))
    Remove-Item -LiteralPath (P @($srcDir, 'input.conf'))
    $src = [pscustomobject]@{ ConfigDir = $srcDir; Version = 'x'; Commit = '' }
    $cfg = P @($d, 'mpv')
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    [void](Install-SoscTarget -Candidate $cand -Source $src -Artifacts $art -Stamp '20261005-160000')
    $conf = Get-TestText (P @($cfg, 'mpv.conf'))
    Assert-Equal $conf ([string]::Join("`r`n", @($BlockB) + $script:MpvConfLines + @($BlockE)) + "`r`n") 'only the sosc block'
    Assert-True ((Get-TestText (P @($cfg, 'input.conf'))).Contains('Alt+t  script-binding sosc_subs/open-menu')) 'input.conf block'
}

Test-Case 'repository source is found next to the script' {
    Assert-Equal $Source.ConfigDir (P @($RepoRoot, 'portable_config')) 'source dir'
    Assert-True ($Source.Commit -match '^[0-9a-f]{40}$') ('commit ' + $Source.Commit)
}

# ---------------------------------------------------------------------------
# Install / update / uninstall end to end
# ---------------------------------------------------------------------------

Test-Case 'install, update and uninstall on an AnimeJaNai-like folder' {
    $d = New-TestDir 'e2e'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $player = P @($d, 'Programs', 'mpv-AnimeJaNai')
    $exe = P @($player, 'mpvnet.exe')
    Set-TestFile $exe
    $cfg = P @($player, 'portable_config')
    $mpvConf = "# mine`r`nprofile=gpu-hq`r`nsub-font-size=40`r`ninclude=`"~~/mpv-animejanai.conf`"`r`n"
    $inputConf = "Alt+p cycle pause`nCtrl+1 script-binding animejanai/x`n"
    Set-TestFile (P @($cfg, 'mpv.conf')) $mpvConf
    Set-TestFile (P @($cfg, 'input.conf')) $inputConf
    Set-TestFile (P @($cfg, 'sosc-palette.conf')) "# my palette`n"
    Set-TestFile (P @($cfg, 'scripts', 'modernz.lua')) '-- modernz'
    Set-TestFile (P @($cfg, 'scripts', 'animejanai_v2.lua')) '-- aj'
    Set-TestFile (P @($cfg, 'script-opts', 'modernz.conf')) 'x=1'
    Set-TestFile (P @($cfg, 'fonts', 'modernz-icons.ttf')) 'font'
    Set-TestFile (P @($cfg, 'cache', 'c.bin')) 'c'
    Set-TestFile (P @($cfg, 'watch_later', 'W')) 'w'

    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'AnimeJaNai' -Exe $exe -ConfigDir $cfg -Portable $true
    $backup = Install-SoscTarget -Candidate $cand -Source $Source -Artifacts $art -Stamp '20261005-120000'

    Assert-True (Test-Path -LiteralPath (P @($backup, 'scripts', 'modernz.lua'))) 'backup holds the old state'
    Assert-True (-not (Test-Path -LiteralPath (P @($backup, 'cache')))) 'backup without cache'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts-desactivados', 'modernz.lua'))) 'modernz set aside'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts-desactivados', 'script-opts', 'modernz.conf'))) 'modernz.conf set aside'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts-desactivados', 'fonts', 'modernz-icons.ttf'))) 'modernz font set aside'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'modernz.lua')))) 'modernz gone from scripts'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'animejanai_v2.lua'))) 'other scripts untouched'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'uosc', 'main.lua'))) 'uosc'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'uosc', 'lib', 'utils.lua'))) 'uosc lib'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'fonts', 'uosc_icons.otf'))) 'uosc font'
    Assert-Equal (Get-TestText (P @($cfg, 'scripts', 'thumbfast.lua'))) '-- fake thumbfast' 'thumbfast'
    foreach ($f in @(Get-ChildItem -LiteralPath (P @($RepoRoot, 'portable_config', 'scripts')) -Filter 'sosc-*.lua')) {
        Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', $f.Name))) $f.Name
    }
    Assert-Equal (Get-TestText (P @($cfg, 'script-opts', 'uosc.conf'))) (Get-TestText (P @($RepoRoot, 'portable_config', 'script-opts', 'uosc.conf'))) 'uosc.conf from sosc'
    Assert-Equal (Get-TestText (P @($cfg, 'sosc-palette.conf'))) "# my palette`n" 'palette choice kept'
    Assert-Equal (Get-TestText (P @($cfg, 'sosc-subs.conf'))) (Get-TestText (P @($RepoRoot, 'portable_config', 'sosc-subs.conf'))) 'subs default copied'
    $thumbConf = Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))
    Assert-True ($thumbConf.Contains('network=yes')) 'thumbfast.conf from sosc'
    Assert-True ($thumbConf.Contains('mpv_path=' + $exe)) 'mpv_path'
    $mpvAfter = Get-TestText (P @($cfg, 'mpv.conf'))
    Assert-True ($mpvAfter.StartsWith($mpvConf)) 'user mpv.conf lines untouched'
    Assert-True ($mpvAfter.EndsWith('include="~~/sosc-upscale.conf"' + "`r`n" + $BlockE + "`r`n")) 'block at the end, CRLF'
    Assert-True (-not $mpvAfter.Contains('border=no')) 'no border=no'
    Assert-True (-not $mpvAfter.Contains('alang')) 'no personal language lines'
    $inputAfter = Get-TestText (P @($cfg, 'input.conf'))
    Assert-True ($inputAfter.StartsWith($inputConf)) 'user input.conf untouched'
    Assert-True (-not $inputAfter.Contains('Alt+p  script-binding')) 'Alt+p left to the user'
    Assert-True ($inputAfter.Contains("Alt+s  script-binding sosc_skip/skip`n")) 'Alt+s, LF kept'
    Assert-True (-not (Test-HasBom (P @($cfg, 'mpv.conf')))) 'no BOM mpv.conf'
    Assert-True (-not (Test-HasBom (P @($cfg, 'script-opts', 'thumbfast.conf')))) 'no BOM thumbfast.conf'
    $rec = Read-SoscRecord $cfg
    Assert-Equal $rec.Values['uosc_version'] $script:UoscVersion 'record uosc'
    Assert-Equal $rec.Values['uosc_preexisting'] 'no' 'record uosc before'
    Assert-Equal $rec.Values['player_exe'] $exe 'record exe'
    Assert-Equal $rec.Values['sosc_commit'] $Source.Commit 'record commit'
    Assert-True (@($rec.Files) -contains 'scripts/sosc-skip.lua') 'record files'
    Assert-Equal @($rec.Disabled).Count 3 'record disabled'
    Assert-True ((Get-SoscInstallState $cfg).Installed) 'detected as installed'

    # Update: same result, record keeps what existed before the first install.
    Set-TestFile (P @($cfg, 'scripts', 'sosc-removed-feature.lua')) '--'
    $rec2Text = (Get-TestText (P @($cfg, 'sosc-installed.txt'))) + "file=scripts/sosc-removed-feature.lua`r`n"
    Set-TestFile (P @($cfg, 'sosc-installed.txt')) $rec2Text
    Set-TestFile (P @($cfg, 'scripts', 'uosc', 'stale.lua')) '--'
    [void](Install-SoscTarget -Candidate $cand -Source $Source -Artifacts $art -Stamp '20261005-120100')
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) $mpvAfter 'mpv.conf idempotent'
    Assert-Equal (Get-TestText (P @($cfg, 'input.conf'))) $inputAfter 'input.conf idempotent'
    Assert-Equal @([regex]::Matches((Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))), 'mpv_path=')).Count 1 'one mpv_path'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'uosc', 'stale.lua')))) 'uosc replaced clean'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'sosc-removed-feature.lua')))) 'stale sosc file removed'
    $rec = Read-SoscRecord $cfg
    Assert-Equal $rec.Values['uosc_preexisting'] 'no' 'still not preexisting'
    Assert-Equal $rec.Values['first_backup'] $backup 'first backup kept'
    Assert-Equal @($rec.Disabled).Count 3 'disabled list kept'

    # Uninstall with default answers.
    [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261005-120200')
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) $mpvConf 'mpv.conf as before'
    Assert-Equal (Get-TestText (P @($cfg, 'input.conf'))) $inputConf 'input.conf as before'
    Assert-Equal @(Get-ChildItem -LiteralPath (P @($cfg, 'scripts')) -Filter 'sosc-*').Count 0 'sosc scripts gone'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'script-opts', 'sosc-skip.conf')))) 'sosc conf gone'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'script-opts', 'uosc.conf')))) 'uosc.conf gone (sosc put it)'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'uosc')))) 'uosc removed (was not there before)'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'fonts', 'uosc_icons.otf')))) 'uosc font removed'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'thumbfast.lua')))) 'thumbfast removed'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'modernz.lua'))) 'modernz back'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'script-opts', 'modernz.conf'))) 'modernz.conf back'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'fonts', 'modernz-icons.ttf'))) 'modernz font back'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts-desactivados')))) 'empty scripts-desactivados removed'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'sosc-palette.conf'))) 'choices kept by default'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'sosc-installed.txt')))) 'record gone'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'cache', 'c.bin'))) 'cache untouched'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'animejanai_v2.lua'))) 'other scripts untouched'
}

Test-Case 'existing uosc, thumbfast and uosc.conf survive uninstall' {
    $d = New-TestDir 'e2e-pre'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'scripts', 'uosc', 'main.lua')) '-- old uosc'
    Set-TestFile (P @($cfg, 'scripts', 'thumbfast.lua')) '-- old thumbfast'
    Set-TestFile (P @($cfg, 'script-opts', 'uosc.conf')) "timeline_style=line`n"
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    [void](Install-SoscTarget -Candidate $cand -Source $Source -Artifacts $art -Stamp '20261005-130000')
    Assert-True (-not (Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))).Contains('mpv_path')) 'no mpv_path for plain mpv'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'mpv.conf'))) 'mpv.conf created'
    [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261005-130100')
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'uosc', 'main.lua'))) 'uosc kept'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'thumbfast.lua'))) 'thumbfast kept'
    Assert-Equal (Get-TestText (P @($cfg, 'script-opts', 'uosc.conf'))) "timeline_style=line`n" 'user uosc.conf restored'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'script-opts', 'thumbfast.conf')))) 'thumbfast.conf (from sosc) removed'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'mpv.conf')))) 'mpv.conf created by sosc removed'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'input.conf')))) 'input.conf created by sosc removed'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'sosc-originales')))) 'originals cleaned'
}

Test-Case 'uninstall answers can remove the saved choices and warn about includes' {
    $d = New-TestDir 'e2e-choices'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'mpv.conf')) "include=`"~~/sosc-palette.conf`"`n"
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'folder' -Exe '' -ConfigDir $cfg -Portable $false
    [void](Install-SoscTarget -Candidate $cand -Source $Source -Artifacts $art -Stamp '20261005-140000')
    $script:NonInteractive = $false
    function Read-SoscLine { param([string]$Prompt) if ($Prompt -like '*palette, subtitle and upscaling*') { return 'y' } return '' }
    try { [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261005-140100') }
    finally { Remove-Item Function:\Read-SoscLine; $script:NonInteractive = $true }
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'sosc-palette.conf')))) 'palette deleted'
    Assert-True (@($script:SoscWarnings | Where-Object { $_ -like '*sosc-palette.conf*' }).Count -ge 1) 'include warning'
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) "include=`"~~/sosc-palette.conf`"`n" 'user line untouched'
}

Test-Case 'a failing target keeps its backup and reports it' {
    $d = New-TestDir 'e2e-fail'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'mpv.conf')) ($BlockB + "`nosc=no`n")
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    Assert-Throws { Install-SoscTarget -Candidate $cand -Source $Source -Artifacts $art -Stamp '20261005-150000' } '*incomplete*respaldo-sosc*' 'malformed mpv.conf'
    Assert-True (Test-Path -LiteralPath ((Get-SoscFullPath $cfg) + '-respaldo-sosc-20261005-150000')) 'backup there'
}

Test-Case 'Invoke-SoscMain: usage errors and a non-interactive install' {
    Assert-Equal (Invoke-SoscMain -Action '' -Target @() -Yes $true) 2 '-Yes without -Action'
    $d = New-TestDir 'main'
    [void](New-FakeArtifacts (P @($d, 'dl')))
    $cfg = P @($d, 'Configuraci' + [char]0x00F3 + 'n de Jos' + [char]0x00E9, 'mpv')
    $code = Invoke-SoscMain -Action 'install' -Target @($cfg) -Yes $true
    Assert-Equal $code 0 'install exit code'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'sosc-palettes.lua'))) 'installed into a non-ASCII path'
    $cfg2 = P @($d, 'second')
    $code = Invoke-SoscMain -Action 'install' -Target @($cfg2 + ';') -Yes $true
    Assert-Equal $code 0 'second folder'
    $code = Invoke-SoscMain -Action 'uninstall' -Target @($cfg + ';' + $cfg2) -Yes $true
    Assert-Equal $code 0 'uninstall exit code'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg2, 'scripts', 'sosc-palettes.lua')))) 'both folders uninstalled'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'sosc-palettes.lua')))) 'uninstalled'
    $script:UoscSha256 = '0' * 64
    $code = Invoke-SoscMain -Action 'install' -Target @($cfg) -Yes $true
    Assert-Equal $code 1 'bad hash: exit 1'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'uosc')))) 'nothing installed on bad hash'
}

Test-Case 'interactive: menu, no player found, typed folder, then uninstall from the list' {
    Reset-Fake
    $d = New-TestDir 'interactive'
    [void](New-FakeArtifacts (P @($d, 'dl')))
    $script:FakeEnvBase = P @($d, 'machine')
    $cfg = P @($d, 'Mis cosas', 'mpv config')
    New-Item -ItemType Directory -Path (P @($d, 'Mis cosas')) | Out-Null
    $script:Answers = New-Object System.Collections.Generic.Queue[string]
    # The last answer takes the default for Anime4K (install it).
    foreach ($a in @('9', '1', '2', $cfg, '')) { $script:Answers.Enqueue($a) }
    function New-SoscEnvironment { return (New-FakeEnv $script:FakeEnvBase) }
    function Read-SoscLine { param([string]$Prompt) return $script:Answers.Dequeue() }
    $script:NonInteractive = $false
    try {
        $code = Invoke-SoscMain -Action '' -Target @() -Yes $false
        Assert-Equal $code 0 'install exit code'
        Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'sosc-skip.lua'))) 'installed in typed folder'
        Assert-Equal $script:Answers.Count 0 'all answers used'
        # Uninstall: the folder is not detected (no player), so pick "other folder".
        foreach ($a in @('2', 'o', $cfg, '', '', '')) { $script:Answers.Enqueue($a) }
        $code = Invoke-SoscMain -Action '' -Target @() -Yes $false
        Assert-Equal $code 0 'uninstall exit code'
        Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'sosc-skip.lua')))) 'uninstalled'
        Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'uosc')))) 'uosc removed by default'
        # Detected player: pick it by number, then exit from the menu.
        Set-TestFile (P @($script:FakeEnvBase, 'Local', 'Programs', 'mpv.net', 'mpvnet.exe'))
        foreach ($a in @('1', '1', '')) { $script:Answers.Enqueue($a) }
        $code = Invoke-SoscMain -Action '' -Target @() -Yes $false
        Assert-Equal $code 0 'install by number'
        $net = P @($script:FakeEnvBase, 'Roaming', 'mpv.net')
        Assert-True ((Get-TestText (P @($net, 'script-opts', 'thumbfast.conf'))).Contains('mpv_path=')) 'mpv.net gets mpv_path'
        foreach ($a in @('0')) { $script:Answers.Enqueue($a) }
        Assert-Equal (Invoke-SoscMain -Action '' -Target @() -Yes $false) 0 'exit from menu'
    }
    finally {
        Remove-Item Function:\New-SoscEnvironment
        Remove-Item Function:\Read-SoscLine
        $script:NonInteractive = $true
    }
}

# ---------------------------------------------------------------------------
# Review fixes
# ---------------------------------------------------------------------------

$IsWin = ([System.IO.Path]::DirectorySeparatorChar -eq '\')

# Fake winget: prints to stdout like the real one, records its arguments and,
# when $Install, drops a mpvnet.exe where mpv.net would be.
function New-FakeWinget {
    param([string]$Dir, [string]$ExeDir, [int]$Code, [bool]$Install)
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $argsFile = P @($Dir, 'args.txt')
    if ($IsWin) {
        $path = P @($Dir, 'winget.cmd')
        $body = "@echo off`r`necho Found mpv.net [mpv.net]`r`necho Successfully installed`r`necho %* > `"$argsFile`"`r`n"
        if ($Install) { $body += "mkdir `"$ExeDir`" 2>nul`r`ntype nul > `"$ExeDir\mpvnet.exe`"`r`n" }
        $body += "exit /b $Code`r`n"
    }
    else {
        $path = P @($Dir, 'winget')
        $body = "#!/bin/sh`necho 'Found mpv.net [mpv.net]'`necho 'Successfully installed'`necho `"`$*`" > '$argsFile'`n"
        if ($Install) { $body += "mkdir -p '$ExeDir'`n: > '$ExeDir/mpvnet.exe'`n" }
        $body += "exit $Code`n"
    }
    [System.IO.File]::WriteAllText($path, $body)
    if (-not $IsWin) { & chmod +x $path }
    return $path
}

Test-Case 'winget output never ends up as a target (it used to crash with StrictMode)' {
    Reset-Fake
    $d = New-TestDir 'winget'
    $base = P @($d, 'machine')
    $e = New-FakeEnv $base
    $exeDir = P @($base, 'Local', 'Programs', 'mpv.net')
    $script:FakeCommands['winget'] = New-FakeWinget -Dir (P @($d, 'bin')) -ExeDir $exeDir -Code 0 -Install $true
    $script:Answers = New-Object System.Collections.Generic.Queue[string]
    foreach ($a in @('1', '')) { $script:Answers.Enqueue($a) }
    function Read-SoscLine { param([string]$Prompt) return $script:Answers.Dequeue() }
    $script:FakeEnvBase = $base
    function New-SoscEnvironment { return (New-FakeEnv $script:FakeEnvBase) }
    $script:NonInteractive = $false
    try {
        $r = @(Invoke-SoscNoPlayerMenu -Env $e)
        Assert-Equal $r.Count 1 'only the detected player comes back'
        Assert-Equal $r[0].Kind 'mpv.net' 'kind'
        Assert-True ($null -ne $r[0].PSObject.Properties['Writable']) 'a real candidate'
        $argsSeen = (Get-TestText (P @($d, 'bin', 'args.txt'))).Trim()
        Assert-True ($argsSeen.Contains('--id mpv.net -e --accept-source-agreements --accept-package-agreements')) ('winget args: ' + $argsSeen)
        # Whole flow: menu -> install -> winget -> install into %APPDATA%\mpv.net.
        Remove-Item -LiteralPath $exeDir -Recurse -Force
        [void](New-FakeArtifacts (P @($d, 'dl')))
        foreach ($a in @('1', '1', '', '')) { $script:Answers.Enqueue($a) }
        $code = Invoke-SoscMain -Action '' -Target @() -Yes $false
        Assert-Equal $code 0 'exit code'
        Assert-True (Test-Path -LiteralPath (P @($base, 'Roaming', 'mpv.net', 'scripts', 'sosc-skip.lua'))) 'installed for mpv.net'
        # winget failing: reported, then back to the menu.
        Remove-Item -LiteralPath $exeDir -Recurse -Force
        Remove-Item -LiteralPath (P @($base, 'Roaming')) -Recurse -Force
        $script:FakeCommands['winget'] = New-FakeWinget -Dir (P @($d, 'bin2')) -ExeDir $exeDir -Code 3 -Install $false
        $script:SoscWarnings.Clear()
        foreach ($a in @('1', '', '0')) { $script:Answers.Enqueue($a) }
        $r = @(Invoke-SoscNoPlayerMenu -Env $e)
        Assert-Equal $r.Count 0 'nothing chosen'
        Assert-True (@($script:SoscWarnings | Where-Object { $_ -like '*code 3*' }).Count -eq 1) 'exit code reported'
        Assert-Equal $script:Answers.Count 0 'all answers used'
    }
    finally {
        Remove-Item Function:\Read-SoscLine
        Remove-Item Function:\New-SoscEnvironment
        $script:NonInteractive = $true
        Reset-Fake
    }
}

Test-Case 'uninstall finishes when sosc-originales was deleted by hand' {
    $d = New-TestDir 'no-originals'
    [void](New-FakeArtifacts (P @($d, 'dl')))
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'script-opts', 'uosc.conf')) "timeline_style=line`n"
    Set-TestFile (P @($cfg, 'mpv.conf')) "volume=50`n"
    Assert-Equal (Invoke-SoscMain -Action 'install' -Target @($cfg) -Yes $true) 0 'install'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'sosc-originales', 'script-opts', 'uosc.conf'))) 'original kept on install'
    Remove-Item -LiteralPath (P @($cfg, 'sosc-originales')) -Recurse -Force
    Assert-Equal (Invoke-SoscMain -Action 'uninstall' -Target @($cfg) -Yes $true) 0 'uninstall exit code'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'sosc-installed.txt')))) 'record gone'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts')))) 'scripts (created by sosc, now empty) gone'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'fonts')))) 'fonts (created by sosc, now empty) gone'
    Assert-Equal @(Get-ChildItem -LiteralPath (P @($cfg, 'script-opts')) -Filter 'sosc-*').Count 0 'sosc options gone'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'script-opts', 'uosc.conf'))) 'uosc.conf left (the earlier one is in the backup)'
    $left = @(Get-ChildItem -LiteralPath $cfg -Recurse -Force -File | ForEach-Object { Get-SoscRelativePath -Path $_.FullName -Root $cfg } | Sort-Object)
    Assert-Equal ([string]::Join(',', $left)) 'mpv.conf,script-opts/uosc.conf,sosc-palette.conf,sosc-subs.conf,sosc-upscale.conf' 'only the user files and the saved choices are left'
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) "volume=50`n" 'mpv.conf as before'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'input.conf')))) 'input.conf created by sosc removed'
}

Test-Case 'end of input (stdin closed) is taken as Exit, never as a loop' {
    Reset-Fake
    $d = New-TestDir 'eof'
    $script:FakeEnvBase = P @($d, 'machine')
    Set-TestFile (P @($script:FakeEnvBase, 'Local', 'Programs', 'mpv.net', 'mpvnet.exe'))
    $script:ReadCalls = 0
    function New-SoscEnvironment { return (New-FakeEnv $script:FakeEnvBase) }
    function Read-SoscLine { param([string]$Prompt) $script:ReadCalls++; if ($script:ReadCalls -gt 20) { throw 'endless loop' } return $null }
    $script:NonInteractive = $false
    try {
        Assert-Equal (Invoke-SoscMain -Action '' -Target @() -Yes $false) 0 'main menu'
        Assert-Equal (Invoke-SoscMain -Action 'install' -Target @() -Yes $false) 0 'target list'
        Assert-Equal (Invoke-SoscMain -Action 'uninstall' -Target @() -Yes $false) 0 'uninstall list (nothing installed)'
        Remove-Item -LiteralPath (P @($script:FakeEnvBase, 'Local')) -Recurse -Force
        Assert-Equal (Invoke-SoscMain -Action 'install' -Target @() -Yes $false) 0 'no-player menu'
        Assert-True ($script:ReadCalls -le 4) ('reads: ' + $script:ReadCalls)
        Assert-True (-not (Test-Path -LiteralPath (P @($script:FakeEnvBase, 'Roaming', 'mpv.net')))) 'nothing installed'
    }
    finally {
        Remove-Item Function:\New-SoscEnvironment
        Remove-Item Function:\Read-SoscLine
        $script:NonInteractive = $true
    }
}

Test-Case 'typed paths: %VARS%, quotes and relative paths from the PowerShell location' {
    $d = New-TestDir 'typed'
    $env:SOSC_TEST_DIR = $d
    $sep = [string][System.IO.Path]::DirectorySeparatorChar
    try {
        Assert-Equal (ConvertTo-SoscTypedPath ('%SOSC_TEST_DIR%' + $sep + 'mpv')) (P @($d, 'mpv')) 'env var expanded'
        Assert-Equal (ConvertTo-SoscTypedPath ('  "' + $d + $sep + 'a b' + $sep + '"  ')) (P @($d, 'a b')) 'quotes and trailing separator'
        $sub = New-TestDir (P @('typed', 'here'))
        Push-Location -LiteralPath $sub
        try {
            Assert-Equal (ConvertTo-SoscTypedPath 'mpv') (P @($sub, 'mpv')) 'relative to the PowerShell location'
            Assert-Equal (ConvertTo-SoscTypedPath ('..' + $sep + 'other')) (P @($d, 'other')) 'dot-dot'
            Assert-True ([System.IO.Directory]::GetCurrentDirectory() -ne $sub) 'process folder differs (the case that matters)'
        }
        finally { Pop-Location }
        Assert-Throws { ConvertTo-SoscTypedPath '   ' } '*not a valid*' 'empty'
        Assert-Throws { ConvertTo-SoscTypedPath 'Env:\PATH' } '*not a valid*' 'other provider'
    }
    finally { Remove-Item Env:\SOSC_TEST_DIR }
}

Test-Case 'typed folder holding the player: its portable_config, or the user folder it reads' {
    Reset-Fake
    $base = New-TestDir 'typed-exe'
    $e = New-FakeEnv $base
    $aj = P @($base, 'Apps', 'mpv-AnimeJaNai')
    Set-TestFile (P @($aj, 'mpvnet.exe'))
    New-Item -ItemType Directory -Path (P @($aj, 'portable_config')) | Out-Null
    $c = Resolve-SoscManualTarget -Env $e -Path $aj -Candidates @()
    Assert-Equal $c.ConfigDir (P @($aj, 'portable_config')) 'portable_config used'
    Assert-Equal $c.Kind 'AnimeJaNai' 'kind'
    Assert-Equal $c.Exe (P @($aj, 'mpvnet.exe')) 'exe kept for mpv_path'
    Assert-True (@($script:SoscWarnings | Where-Object { $_ -like '*not its config folder*' }).Count -eq 1) 'warned'
    $mpvDir = P @($base, 'Apps', 'mpv')
    Set-TestFile (P @($mpvDir, 'mpv.exe'))
    $c = Resolve-SoscManualTarget -Env $e -Path $mpvDir -Candidates @()
    Assert-Equal $c.ConfigDir (Get-SoscFullPath (P @($base, 'Roaming', 'mpv'))) 'user folder offered (yes by default)'
    Assert-Equal $c.Kind 'mpv' 'mpv kind'
    $script:NonInteractive = $false
    function Read-SoscLine { param([string]$Prompt) return 'n' }
    try { Assert-Equal (Resolve-SoscManualTarget -Env $e -Path $mpvDir -Candidates @()) $null 'declined: nothing' }
    finally { Remove-Item Function:\Read-SoscLine; $script:NonInteractive = $true }
}

Test-Case 'MPV_HOME wins over portable_config for mpv, not for mpv.net' {
    Reset-Fake
    $base = New-TestDir 'mpv-home'
    $e = New-FakeEnv $base
    $e.MpvHome = P @($base, 'Home')
    Set-TestFile (P @($base, 'Program Files', 'mpv', 'mpv.exe'))
    New-Item -ItemType Directory -Path (P @($base, 'Program Files', 'mpv', 'portable_config')) | Out-Null
    Set-TestFile (P @($base, 'Local', 'Programs', 'mpv.net', 'mpvnet.exe'))
    New-Item -ItemType Directory -Path (P @($base, 'Local', 'Programs', 'mpv.net', 'portable_config')) | Out-Null
    $found = @(Find-SoscPlayers -Env $e)
    $mpv = @($found | Where-Object { $_.Kind -eq 'mpv' })[0]
    $net = @($found | Where-Object { $_.Kind -eq 'mpv.net' })[0]
    Assert-Equal $mpv.ConfigDir (Get-SoscFullPath $e.MpvHome) 'mpv reads MPV_HOME'
    Assert-True (-not $mpv.Portable) 'not portable'
    Assert-Equal $net.ConfigDir (Get-SoscFullPath (P @($base, 'Local', 'Programs', 'mpv.net', 'portable_config'))) 'mpv.net keeps portable_config'
    $c = Resolve-SoscManualTarget -Env $e -Path (P @($base, 'Program Files', 'mpv', 'portable_config')) -Candidates @()
    Assert-True (@($script:SoscWarnings | Where-Object { $_ -like '*MPV_HOME*' }).Count -eq 1) 'typed portable_config: MPV_HOME note'
}

Test-Case 'refused targets: drive root, user profile, and folders that are not mpv' {
    Reset-Fake
    $d = New-TestDir 'refused'
    $e = New-FakeEnv $d
    $root = [System.IO.Path]::GetPathRoot($d)
    Assert-True (Test-SoscForbiddenTarget -Env $e -Path $root) 'drive root'
    Assert-True (Test-SoscForbiddenTarget -Env $e -Path ($e.UserProfile + [System.IO.Path]::DirectorySeparatorChar)) 'user profile'
    Assert-True (-not (Test-SoscForbiddenTarget -Env $e -Path (P @($e.UserProfile, 'mpv')))) 'folder inside the profile'
    $docs = P @($d, 'Documents')
    Set-TestFile (P @($docs, 'tax.pdf')) 'pdf'
    $cand = New-SoscCandidate -Env $e -Kind 'folder' -Exe '' -ConfigDir $docs -Portable $false
    Assert-True (-not (Test-SoscLooksLikeMpvConfig -Env $e -Candidate $cand)) 'no sign of mpv'
    $c2 = New-SoscCandidate -Env $e -Kind 'folder' -Exe '' -ConfigDir (P @($d, 'new')) -Portable $false
    Assert-True (Test-SoscLooksLikeMpvConfig -Env $e -Candidate $c2) 'missing folder is fine'
    $withConf = P @($d, 'withconf')
    Set-TestFile (P @($withConf, 'mpv.conf')) 'x'
    Assert-True (Test-SoscLooksLikeMpvConfig -Env $e -Candidate (New-SoscCandidate -Env $e -Kind 'folder' -Exe '' -ConfigDir $withConf -Portable $false)) 'mpv.conf'
    $beside = P @($d, 'player', 'cfg')
    Set-TestFile (P @($beside, 'notes.txt'))
    Set-TestFile (P @($d, 'player', 'mpv.exe'))
    Assert-True (Test-SoscLooksLikeMpvConfig -Env $e -Candidate (New-SoscCandidate -Env $e -Kind 'folder' -Exe '' -ConfigDir $beside -Portable $false)) 'mpv.exe next to it'

    [void](New-FakeArtifacts (P @($d, 'dl')))
    $script:FakeEnvBase = $d
    function New-SoscEnvironment { return (New-FakeEnv $script:FakeEnvBase) }
    function Read-SoscLine { param([string]$Prompt) return $script:Reply }
    try {
        Assert-Equal (Invoke-SoscMain -Action 'install' -Target @($docs) -Yes $true) 2 '-Yes refuses a non-mpv folder'
        Assert-Equal (Invoke-SoscMain -Action 'install' -Target @($e.UserProfile) -Yes $true) 2 '-Yes refuses the profile'
        Assert-Equal (Invoke-SoscMain -Action 'uninstall' -Target @($root) -Yes $true) 2 '-Yes refuses a drive root'
        Assert-Equal @(Get-ChildItem -LiteralPath $docs -Force).Count 1 'nothing written'
        Assert-Equal @(Get-ChildItem -LiteralPath $d -Filter 'Documents-respaldo*').Count 0 'no backup made'
        $script:NonInteractive = $false
        $script:Reply = 'n'
        Assert-Equal (Invoke-SoscMain -Action 'install' -Target @($docs) -Yes $false) 0 'interactive no: cancelled'
        Assert-True (-not (Test-Path -LiteralPath (P @($docs, 'scripts')))) 'still nothing written'
        $script:Reply = 'y'
        Assert-Equal (Invoke-SoscMain -Action 'install' -Target @($docs) -Yes $false) 0 'interactive yes: installed'
        Assert-True (Test-Path -LiteralPath (P @($docs, 'scripts', 'sosc-skip.lua'))) 'installed after confirming'
    }
    finally {
        Remove-Item Function:\New-SoscEnvironment
        Remove-Item Function:\Read-SoscLine
        $script:NonInteractive = $true
    }
}

Test-Case 'administrator: warned and asked; with -Yes only Program Files or ProgramData' {
    $d = New-TestDir 'admin'
    $e = New-FakeEnv $d
    $user = [pscustomobject]@{ ConfigDir = (P @($d, 'Roaming', 'mpv')) }
    $pf = [pscustomobject]@{ ConfigDir = (P @($d, 'Program Files', 'mpv', 'portable_config')) }
    Assert-True (Confirm-SoscElevation -Env $e -Targets @($user)) 'not admin: go on'
    Assert-Equal $script:SoscWarnings.Count 0 'no warning'
    $e.IsAdmin = $true
    Assert-True (-not (Confirm-SoscElevation -Env $e -Targets @($user))) '-Yes refuses a user folder'
    Assert-True (-not (Confirm-SoscElevation -Env $e -Targets @($pf, $user))) '-Yes refuses a mix'
    Assert-True (Confirm-SoscElevation -Env $e -Targets @($pf)) '-Yes allows Program Files'
    $script:NonInteractive = $false
    $script:Reply = ''
    function Read-SoscLine { param([string]$Prompt) return $script:Reply }
    try {
        Assert-True (-not (Confirm-SoscElevation -Env $e -Targets @($user))) 'interactive: no by default'
        $script:Reply = 's'
        Assert-True (Confirm-SoscElevation -Env $e -Targets @($user)) 'interactive: yes'
    }
    finally { Remove-Item Function:\Read-SoscLine; $script:NonInteractive = $true }
    [void](New-FakeArtifacts (P @($d, 'dl')))
    $script:FakeEnvBase = $d
    function New-SoscEnvironment { $x = New-FakeEnv $script:FakeEnvBase; $x.IsAdmin = $true; return $x }
    try {
        Assert-Equal (Invoke-SoscMain -Action 'install' -Target @($user.ConfigDir) -Yes $true) 2 'main: refused'
        Assert-True (-not (Test-Path -LiteralPath $user.ConfigDir)) 'nothing created'
    }
    finally { Remove-Item Function:\New-SoscEnvironment; $script:SoscElevated = $false }
}

Test-Case 'administrator: no delete or move through a link inside the config folder' {
    $d = New-TestDir 'admin-links'
    $cfg = P @($d, 'cfg')
    $outside = P @($d, 'outside')
    Set-TestFile (P @($outside, 'uosc', 'main.lua')) 'precious'
    Set-TestFile (P @($outside, 'modernz.lua')) 'precious'
    New-Item -ItemType Directory -Path $cfg | Out-Null
    try { New-Item -ItemType SymbolicLink -Path (P @($cfg, 'scripts')) -Target $outside | Out-Null }
    catch { Write-Host '     (symlinks not available, skipped)'; return }
    $script:SoscElevated = $true
    try {
        Assert-Throws { Remove-SoscItem -Path (P @($cfg, 'scripts', 'uosc')) -Root $cfg } '*is a link*' 'delete through link'
        Assert-Throws { Move-SoscToDisabled -Path (P @($cfg, 'scripts', 'modernz.lua')) -ConfigDir $cfg -Stamp 's' } '*is a link*' 'move through link'
        Assert-True (Test-Path -LiteralPath (P @($outside, 'uosc', 'main.lua'))) 'target intact'
        Assert-True (Test-Path -LiteralPath (P @($outside, 'modernz.lua'))) 'file not moved'
        Remove-SoscItem -Path (P @($cfg, 'scripts')) -Root $cfg
        Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts')))) 'the link itself can go'
        Assert-True (Test-Path -LiteralPath (P @($outside, 'uosc', 'main.lua'))) 'its target stays'
    }
    finally { $script:SoscElevated = $false }
}

Test-Case 'record paths: only clean relative paths are accepted' {
    foreach ($ok in @('scripts/modernz.lua', 'scripts-desactivados/script-opts/modernz.conf', 'fonts/modernz-icons.ttf', 'scripts/sosc-skip.lua')) {
        Assert-True (Test-SoscRecordPath $ok) ('accepted ' + $ok)
    }
    foreach ($bad in @('', '../x', '../../x', 'scripts/../../x', 'C:/Windows/x', 'C:\Windows\x', 'scripts/sosc-..\..\..\x.lua',
            '/etc/passwd', '//server/share/x', 'scripts//x', './x', 'scripts/./x', '...', 'scripts/.../x', 'scripts/x.', 'scripts/x ',
            'a|b', 'scripts/x:stream', "scripts/x`ty")) {
        Assert-True (-not (Test-SoscRecordPath $bad)) ('rejected ' + $bad)
    }
}

Test-Case 'hostile sosc-installed.txt never touches anything outside the folder' {
    $d = New-TestDir 'hostile'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $top = P @($d, 'top')
    $cfg = P @($top, 'mid', 'cfg')
    New-Item -ItemType Directory -Path $cfg -Force | Out-Null
    $sentinels = @((P @($top, 'x')), (P @($top, 'evil')), (P @($top, 'x.lua')), (P @($top, 'mid', 'x')), (P @($top, 'mid', 'x.lua')), (P @($top, 'mid', 'outside.lua')))
    foreach ($s in $sentinels) { Set-TestFile $s 'keep' }
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    [void](Install-SoscTarget -Candidate $cand -Source $Source -Artifacts $art -Stamp '20261005-160000')
    Set-TestFile (P @($cfg, 'scripts-desactivados', 'a.lua')) '-- set aside'
    $hostile = @(
        'disabled=../../x|scripts/a.lua',
        'disabled=scripts-desactivados/a.lua|../../evil',
        'disabled=scripts-desactivados/a.lua|../../../dropped.lua',
        'disabled=C:/Windows/x|scripts/b.lua',
        'disabled=C:\Windows\x|scripts/b.lua',
        'disabled=/etc/hostname|scripts/c.lua',
        'disabled=scripts-desactivados/a.lua|..\..\evil2',
        'disabled=.../x|scripts/d.lua',
        'disabled=scripts-desactivados/a.lua',
        'disabled=a|b|c',
        'file=scripts/sosc-..\..\..\x.lua',
        'file=scripts/sosc-../../../x.lua',
        'file=../outside.lua',
        'file=script-opts/sosc-..\..\x.conf'
    )
    $recPath = P @($cfg, 'sosc-installed.txt')
    Set-TestFile $recPath ((Get-TestText $recPath) + [string]::Join("`r`n", $hostile) + "`r`n")
    $rec = Read-SoscRecord $cfg
    Assert-Equal @($rec.Disabled).Count 0 'no hostile disabled entry kept'
    foreach ($f in $rec.Files) { Assert-True (Test-SoscRecordPath $f) ('file entry ' + $f) }
    Assert-Equal @($script:SoscWarnings | Where-Object { $_ -like '*invalid entry*' }).Count $hostile.Count 'each one reported'
    $before = @(Get-ChildItem -LiteralPath $top -Recurse -Force | Where-Object { $_.FullName -notlike ((Get-SoscFullPath $cfg) + '*') } | ForEach-Object { $_.FullName } | Sort-Object)

    # Update and uninstall with that record.
    [void](Install-SoscTarget -Candidate $cand -Source $Source -Artifacts $art -Stamp '20261005-160100')
    Set-TestFile $recPath ((Get-TestText $recPath) + [string]::Join("`r`n", $hostile) + "`r`n")
    [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261005-160200')

    foreach ($s in $sentinels) { Assert-Equal (Get-TestText $s) 'keep' ('sentinel ' + $s) }
    $after = @(Get-ChildItem -LiteralPath $top -Recurse -Force | Where-Object { $_.FullName -notlike ((Get-SoscFullPath $cfg) + '*') } | ForEach-Object { $_.FullName } | Sort-Object)
    Assert-Equal ([string]::Join('|', $after)) ([string]::Join('|', $before)) 'nothing created or removed outside the folder (backups aside)'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts-desactivados', 'a.lua'))) 'set-aside file stays inside'
    Assert-True (-not (Test-Path -LiteralPath $recPath)) 'uninstall finished'

    # The same entries through the restore loop directly (as if the reader had
    # let them through): every one is refused.
    $script:SoscWarnings.Clear()
    $pairs = @('../../x|scripts/a.lua', 'scripts-desactivados/a.lua|../../evil', 'C:/Windows/x|scripts/b.lua', 'scripts-desactivados/a.lua|..\..\evil2')
    foreach ($entry in $pairs) {
        $pair = $entry -split '\|'
        Assert-True (-not ((Test-SoscRecordPath $pair[0]) -and (Test-SoscRecordPath $pair[1]))) ('refused ' + $entry)
    }
}

# ---------------------------------------------------------------------------
# Keyboard menus
# ---------------------------------------------------------------------------

$Ptr = [string][char]0x203A
$script:Keys = New-Object System.Collections.Generic.Queue[string]
$script:Frames = New-Object System.Collections.Generic.List[string]
$script:ConsoleLog = New-Object System.Collections.Generic.List[string]
# Keys pressed before a menu opened: read first, unless the menu throws them away.
$script:Pending = New-Object System.Collections.Generic.Queue[string]
$RealKeyFlush = $script:SoscKeyFlush
$RealKeyReader = $script:SoscKeyReader
$RealRenderer = $script:SoscMenuRenderer
$RealConsoleEnter = $script:SoscConsoleEnter
$RealConsoleExit = $script:SoscConsoleExit

function ConvertTo-FrameText {
    param([object[]]$Lines)
    $out = @()
    foreach ($line in $Lines) { $out += [string]::Join('', @(@($line) | ForEach-Object { $_.Text })) }
    return [string]::Join("`n", $out)
}

# Keys come from a queue, frames are kept as text, the console is not touched.
function Use-FakeConsole {
    param([string[]]$Keys = @())
    $script:Keys.Clear()
    foreach ($k in $Keys) { $script:Keys.Enqueue($k) }
    $script:Frames.Clear()
    $script:ConsoleLog.Clear()
    $script:Pending.Clear()
    $script:SoscKeyReader = {
        if ($script:Pending.Count -gt 0) { return $script:Pending.Dequeue() }
        if ($script:Keys.Count -eq 0) { throw 'no more keys' }
        return $script:Keys.Dequeue()
    }
    $script:SoscKeyFlush = { $script:Pending.Clear() }
    $script:SoscMenuRenderer = { param([object[]]$Lines, [int]$Previous) $script:Frames.Add((ConvertTo-FrameText $Lines)); return @($Lines).Count }
    $script:SoscConsoleEnter = { $script:ConsoleLog.Add('enter'); return @{ Fake = $true } }
    $script:SoscConsoleExit = { param($State) $script:ConsoleLog.Add('exit') }
    $script:SoscMenu = $true
    $script:SoscMenuWidth = 80
    $script:SoscMenuHeight = 50
    $script:NonInteractive = $false
}

function Reset-FakeConsole {
    $script:SoscKeyReader = $RealKeyReader
    $script:SoscKeyFlush = $RealKeyFlush
    $script:SoscMenuRenderer = $RealRenderer
    $script:SoscConsoleEnter = $RealConsoleEnter
    $script:SoscConsoleExit = $RealConsoleExit
    $script:SoscConsoleProbe = { $false }
    $script:SoscMenu = $false
    $script:SoscMenuWidth = 0
    $script:SoscMenuHeight = 0
    $script:NonInteractive = $true
}

function Get-LastFrame { return $script:Frames[$script:Frames.Count - 1] }

function New-TestItems {
    param([string[]]$Labels)
    return @($Labels | ForEach-Object { New-SoscMenuItem -Label $_ })
}

Test-Case 'menu: single choice moves, wraps around at both ends and chooses with Enter' {
    Use-FakeConsole @('DownArrow', 'DownArrow', 'DownArrow', 'UpArrow', 'Enter')
    try {
        $m = Invoke-SoscListMenu -Items (New-TestItems @('Alpha', 'Beta', 'Gamma'))
        Assert-True (-not $m.Cancelled) 'not cancelled'
        Assert-Equal $m.Index 2 'Down x3 wraps to Alpha, Up wraps to Gamma'
        Assert-True ($script:Frames[0].StartsWith($Ptr + ' Alpha' + "`n" + '  Beta')) ('first frame: ' + $script:Frames[0])
        Assert-True ($script:Frames[0].Contains('Enter to choose')) 'help line'
        Assert-True ($script:Frames[3].Contains($Ptr + ' Alpha')) 'wrapped to the first entry'
        Assert-Equal (Get-LastFrame) ($Ptr + ' Gamma') 'only the choice is left on screen'
        Assert-Equal ([string]::Join(',', $script:ConsoleLog)) 'enter,exit' 'console set up and restored'
        Assert-Equal $script:Keys.Count 0 'all keys used'
    }
    finally { Reset-FakeConsole }
}

Test-Case 'menu: disabled entries are skipped, Home/End, Esc and Ctrl+C cancel and clear the menu' {
    $items = @((New-SoscMenuItem -Label 'Alpha' -Disabled $true), (New-SoscMenuItem -Label 'Beta'), (New-SoscMenuItem -Label 'Gamma' -Disabled $true), (New-SoscMenuItem -Label 'Delta'))
    Use-FakeConsole @('DownArrow', 'Enter')
    try {
        Assert-Equal (Invoke-SoscListMenu -Items $items).Index 3 'starts on Beta, Gamma skipped'
        Use-FakeConsole @('End', 'Home', 'UpArrow', 'Enter')
        Assert-Equal (Invoke-SoscListMenu -Items $items).Index 3 'End, Home, Up wraps to Delta'
        Use-FakeConsole @('DownArrow', 'Escape')
        $m = Invoke-SoscListMenu -Items $items
        Assert-True $m.Cancelled 'Esc cancels'
        Assert-Equal (Get-LastFrame) '' 'nothing left on screen'
        Assert-Equal ([string]::Join(',', $script:ConsoleLog)) 'enter,exit' 'console restored'
        Use-FakeConsole @('Ctrl+C')
        Assert-True (Invoke-SoscListMenu -Items $items).Cancelled 'Ctrl+C cancels like Esc'
    }
    finally { Reset-FakeConsole }
}

Test-Case 'menu: multiple choice ticks, unticks and confirms; actions are not ticked' {
    $items = @((New-TestItems @('One', 'Two', 'Three')) + @((New-SoscMenuItem -Label 'Other' -Action $true), (New-SoscMenuItem -Label 'Exit' -Action $true -Quit $true)))
    Use-FakeConsole @('Spacebar', 'DownArrow', 'Spacebar', 'DownArrow', 'Spacebar', 'Spacebar', 'Enter')
    try {
        $m = Invoke-SoscListMenu -Items $items -Multi
        Assert-Equal ([string]::Join(',', $m.Checked)) '0,1' 'One and Two ticked, Three ticked and unticked'
        Assert-Equal $m.Index (-1) 'Enter on a tickable entry'
        Assert-True ($script:Frames[1].Contains('[x] One')) ('ticked box drawn: ' + $script:Frames[1])
        Assert-True ($script:Frames[1].Contains('[ ] Two')) 'empty box drawn'
        Assert-True ($script:Frames[1].Contains("`n  Other")) 'action drawn without a box'
        Assert-True ($script:Frames[1].Contains('Space to tick')) 'help line'
        Assert-Equal (Get-LastFrame) ($Ptr + ' One, Two') 'choice left on screen'
        # Nothing ticked: Enter takes the highlighted entry. Space on an action does nothing.
        Use-FakeConsole @('DownArrow', 'Enter')
        Assert-Equal ([string]::Join(',', (Invoke-SoscListMenu -Items $items -Multi).Checked)) '1' 'highlighted one'
        Use-FakeConsole @('UpArrow', 'UpArrow', 'Spacebar', 'Enter')
        $m = Invoke-SoscListMenu -Items $items -Multi
        Assert-Equal $m.Index 3 'Enter on Other'
        Assert-Equal @($m.Checked).Count 0 'Space on an action ticks nothing'
        # Ticked entries plus "Other": both come back.
        Use-FakeConsole @('Spacebar', 'DownArrow', 'DownArrow', 'DownArrow', 'Enter')
        $m = Invoke-SoscListMenu -Items $items -Multi
        Assert-Equal $m.Index 3 'Other'
        Assert-Equal ([string]::Join(',', $m.Checked)) '0' 'with One'
        Assert-Equal (Get-LastFrame) ($Ptr + ' One, Other') 'summary'
        # Exit drops the ticks.
        Use-FakeConsole @('Spacebar', 'UpArrow', 'Enter')
        $m = Invoke-SoscListMenu -Items $items -Multi
        Assert-True $items[$m.Index].Quit 'Exit chosen'
        Assert-Equal (Get-LastFrame) ($Ptr + ' Exit') 'summary only says Exit'
    }
    finally { Reset-FakeConsole }
}

Test-Case 'menu: target list maps ticks, Other and Esc; long paths are shortened' {
    $base = New-TestDir 'menu-targets'
    $e = New-FakeEnv $base
    $long = P @($base, ('very long folder name ' * 4).Trim(), 'mpv-AnimeJaNai', 'portable_config')
    $list = @(
        (New-SoscCandidate -Env $e -Kind 'AnimeJaNai' -Exe '' -ConfigDir $long -Portable $true),
        (New-SoscCandidate -Env $e -Kind 'mpv' -Exe '' -ConfigDir (P @($base, 'Roaming', 'mpv')) -Portable $false)
    )
    function Read-SoscLine { param([string]$Prompt) throw 'a number question was asked' }
    try {
        Use-FakeConsole @('DownArrow', 'Spacebar', 'UpArrow', 'Spacebar', 'Enter')
        $sel = Read-SoscTargetChoice -List $list -Mode 'install'
        Assert-Equal ([string]::Join(',', $sel.Indexes)) '0,1' 'both'
        Assert-True (-not $sel.Other -and -not $sel.Quit) 'nothing else'
        $first = $script:Frames[0] -split "`n"
        Assert-True ($first[0] -like ($Ptr + ' `[ `] AnimeJaNai*')) ('player line: ' + $first[0])
        Assert-True ($first[1].Contains([char]0x2026)) ('long path shortened: ' + $first[1])
        Assert-True ($first[1].EndsWith('portable_config')) 'the end of the path is kept'
        Assert-True ($first[1].Length -le 79) ('fits the width: ' + $first[1].Length)
        Assert-True ($script:Frames[0].Contains('Other folder' + [char]0x2026)) 'Other folder entry'
        Use-FakeConsole @('UpArrow', 'UpArrow', 'Enter')
        $sel = Read-SoscTargetChoice -List $list -Mode 'install'
        Assert-True $sel.Other 'Other folder'
        Assert-Equal @($sel.Indexes).Count 0 'no folder ticked'
        Use-FakeConsole @('Spacebar', 'Escape')
        Assert-True (Read-SoscTargetChoice -List $list -Mode 'install').Quit 'Esc leaves'
        Use-FakeConsole @('Enter')
        Assert-True (Read-SoscTargetChoice -List @() -Mode 'uninstall').Other 'empty list: Other folder first'
    }
    finally { Remove-Item Function:\Read-SoscLine; Reset-FakeConsole }
}

Test-Case 'yes/no: starts on the default, arrows change it, S/Y/N answer, Esc is always No' {
    function Read-SoscLine { param([string]$Prompt) throw 'a number question was asked' }
    try {
        $cases = @(
            @(@('Enter'), $true, $true, 'Enter keeps the default (yes)'),
            @(@('Enter'), $false, $false, 'Enter keeps the default (no)'),
            @(@('LeftArrow', 'Enter'), $false, $true, 'Left is Yes'),
            @(@('RightArrow', 'Enter'), $true, $false, 'Right is No'),
            @(@('DownArrow', 'Enter'), $false, $true, 'Down toggles'),
            @(@('UpArrow', 'UpArrow', 'Enter'), $true, $true, 'Up twice: back'),
            @(@('S'), $false, $true, 'S answers yes at once'),
            @(@('y'), $false, $true, 'Y answers yes at once'),
            @(@('N'), $true, $false, 'N answers no at once'),
            @(@('X', 'Enter'), $true, $true, 'other keys are ignored'),
            @(@('Escape'), $true, $false, 'Esc is No even when the default is yes'),
            @(@('LeftArrow', 'Escape'), $false, $false, 'Esc is No even when Yes is highlighted'),
            @(@('Ctrl+C'), $true, $false, 'Ctrl+C is No')
        )
        foreach ($c in $cases) {
            Use-FakeConsole $c[0]
            Assert-Equal (Confirm-Sosc -Question 'Q?' -Default $c[1]) $c[2] $c[3]
            Assert-Equal $script:Keys.Count 0 ('keys used: ' + $c[3])
            Assert-Equal ([string]::Join(',', $script:ConsoleLog)) 'enter,exit' ('console restored: ' + $c[3])
        }
        Use-FakeConsole @('RightArrow', 'Enter')
        [void](Confirm-Sosc -Question 'Q?' -Default $true)
        Assert-True ($script:Frames[0].StartsWith('  ' + $Ptr + ' Yes      No')) ('first frame: ' + $script:Frames[0])
        Assert-True ($script:Frames[1].StartsWith('    Yes    ' + $Ptr + ' No')) ('second frame: ' + $script:Frames[1])
        Assert-True ($script:Frames[0].Contains('Esc = No')) 'help line'
        Assert-Equal (Get-LastFrame) ('  ' + $Ptr + ' No') 'answer left on screen'
        # With -Yes nothing is read, menus or not.
        Use-FakeConsole @()
        $script:NonInteractive = $true
        Assert-True (Confirm-Sosc -Question 'Q?' -Default $true) 'default with -Yes'
        Assert-Equal $script:ConsoleLog.Count 0 'no menu with -Yes'
    }
    finally { Remove-Item Function:\Read-SoscLine; Reset-FakeConsole }
}

Test-Case 'Spanish menus: S answers yes, labels and help decoded' {
    Set-SoscLanguage 'es'
    try {
        Use-FakeConsole @('S')
        Assert-True (Confirm-Sosc -Question 'P?' -Default $false) 'S = Si'
        Assert-True ($script:Frames[0].Contains('S' + [char]0x00ED)) ('Si drawn: ' + $script:Frames[0])
        Use-FakeConsole @('Escape')
        [void](Read-SoscMainChoice)
        Assert-True ($script:Frames[0].Contains('Instalar o actualizar')) 'label without its number'
        Assert-True ($script:Frames[0].Contains([char]0x2191 + '/' + [char]0x2193 + ' para moverte')) 'arrows in the help'
    }
    finally { Set-SoscLanguage 'en'; Reset-FakeConsole }
    Assert-True ((T 'menu_help').StartsWith([string][char]0x2191)) 'English help decodes \u too'
}

Test-Case 'plan B: a console that cannot read keys falls back to numbers and is restored' {
    $script:Lines = New-Object System.Collections.Generic.Queue[string]
    function Read-SoscLine { param([string]$Prompt) return $script:Lines.Dequeue() }
    try {
        Use-FakeConsole @()
        $script:SoscKeyReader = { throw (New-Object System.InvalidOperationException 'Cannot read keys when either application does not have a console or when console input has been redirected.') }
        $script:Lines.Enqueue('y')
        Assert-True (Confirm-Sosc -Question 'Q?' -Default $false) 'answered with a typed y'
        Assert-True (-not $script:SoscMenu) 'menus off for the rest of the run'
        Assert-Equal ([string]::Join(',', $script:ConsoleLog)) 'enter,exit' 'console restored'
        Assert-Equal (Get-LastFrame) '' 'menu cleared'
        $script:Lines.Enqueue('2')
        Assert-Equal (Read-SoscMainChoice) '2' 'main menu with numbers'
        Assert-Equal $script:ConsoleLog.Count 2 'no other menu tried'
        # A renderer that fails mid-menu: same.
        Use-FakeConsole @('DownArrow', 'Enter')
        $script:SoscMenuRenderer = { param([object[]]$Lines, [int]$Previous) if ($script:Frames.Count -ge 1) { throw 'cannot move the cursor' } $script:Frames.Add('x'); return 1 }
        $script:Lines.Enqueue('0')
        Assert-Equal (Read-SoscMainChoice) '0' 'numbers after the renderer failed'
        Assert-Equal ([string]::Join(',', $script:ConsoleLog)) 'enter,exit' 'console restored'
        Assert-Equal $script:Lines.Count 0 'all typed answers used'
    }
    finally { Remove-Item Function:\Read-SoscLine; Reset-FakeConsole }
}

Test-Case 'plan B: detection decides; -NoMenu and -Yes never open a menu' {
    Reset-Fake
    $d = New-TestDir 'menu-detect'
    $script:FakeEnvBase = P @($d, 'machine')
    function New-SoscEnvironment { return (New-FakeEnv $script:FakeEnvBase) }
    $script:Lines = New-Object System.Collections.Generic.Queue[string]
    function Read-SoscLine { param([string]$Prompt) if ($script:Lines.Count -eq 0) { return $null } return $script:Lines.Dequeue() }
    try {
        # Not an interactive console: numbers, the keys are never read.
        Use-FakeConsole @('Enter')
        $script:SoscConsoleProbe = { $false }
        $script:Lines.Enqueue('0')
        Assert-Equal (Invoke-SoscMain -Action '' -Target @() -Yes $false) 0 'exit by number'
        Assert-Equal $script:Keys.Count 1 'no key read'
        Assert-Equal $script:Lines.Count 0 'typed answer used'
        # Interactive console: the menu.
        $script:SoscConsoleProbe = { $true }
        Use-FakeConsole @('Escape')
        Assert-Equal (Invoke-SoscMain -Action '' -Target @() -Yes $false) 0 'Esc in the main menu'
        Assert-Equal $script:Keys.Count 0 'key read'
        Assert-True ($script:Frames[0].Contains('Install or update')) 'main menu drawn'
        # -NoMenu: numbers even on an interactive console.
        Use-FakeConsole @('Enter')
        $script:SoscConsoleProbe = { $true }
        $script:Lines.Enqueue('0')
        Assert-Equal (Invoke-SoscMain -Action '' -Target @() -Yes $false -NoMenu $true) 0 'exit by number'
        Assert-Equal $script:Keys.Count 1 'no key read with -NoMenu'
        # -Yes: the probe is not even asked.
        Use-FakeConsole @()
        $script:SoscConsoleProbe = { throw 'probe called' }
        Assert-Equal (Invoke-SoscMain -Action '' -Target @() -Yes $true) 2 '-Yes without -Action'
        Assert-Equal $script:ConsoleLog.Count 0 'no menu with -Yes'
    }
    finally {
        Remove-Item Function:\New-SoscEnvironment
        Remove-Item Function:\Read-SoscLine
        Reset-FakeConsole
    }
    # A real process with its output redirected is not an interactive console.
    $exe = (Get-Process -Id $PID).Path
    $cmd = 'function Get-InstallerBody {' + ${function:Get-InstallerBody}.ToString() + '}; . (Get-InstallerBody ''' + $InstallScript.Replace("'", "''") + '''); Test-SoscInteractiveConsole'
    $out = & $exe -NoProfile -NonInteractive -Command $cmd
    Assert-Equal ([string]::Join('', @($out)).Trim()) 'False' 'redirected child process'
}

Test-Case 'menus end to end: install from the list, then uninstall answering with keys' {
    Reset-Fake
    $d = New-TestDir 'menu-e2e'
    [void](New-FakeArtifacts (P @($d, 'dl')))
    $script:FakeEnvBase = P @($d, 'machine')
    $aj = P @($script:FakeEnvBase, 'Local', 'Programs', 'mpv-AnimeJaNai')
    Set-TestFile (P @($aj, 'mpvnet.exe'))
    $cfg = P @($aj, 'portable_config')
    Set-TestFile (P @($cfg, 'scripts', 'modernz.lua')) '-- modernz'
    function New-SoscEnvironment { return (New-FakeEnv $script:FakeEnvBase) }
    function Read-SoscLine { param([string]$Prompt) throw 'a number question was asked' }
    try {
        # Install (first entry), the only player (Enter with nothing ticked), then
        # "move the clashing interface?" with its default (yes).
        Use-FakeConsole @('Enter', 'Enter', 'Enter')
        $script:SoscConsoleProbe = { $true }
        Assert-Equal (Invoke-SoscMain -Action '' -Target @() -Yes $false) 0 'install exit code'
        Assert-Equal $script:Keys.Count 0 'all keys used'
        Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'sosc-skip.lua'))) 'installed'
        Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts-desactivados', 'modernz.lua'))) 'modernz set aside (default yes)'
        # Uninstall: keep uosc (Right = No), remove thumbfast (Enter, yes by
        # default), bring modernz back (S), keep the choices (Esc = No).
        Use-FakeConsole @('DownArrow', 'Enter', 'Enter', 'RightArrow', 'Enter', 'Enter', 'S', 'Escape')
        $script:SoscConsoleProbe = { $true }
        Assert-Equal (Invoke-SoscMain -Action '' -Target @() -Yes $false) 0 'uninstall exit code'
        Assert-Equal $script:Keys.Count 0 'all keys used'
        Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'sosc-skip.lua')))) 'uninstalled'
        Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'uosc', 'main.lua'))) 'uosc kept (No)'
        Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'thumbfast.lua')))) 'thumbfast removed (Yes)'
        Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'modernz.lua'))) 'modernz back (S)'
        Assert-True (Test-Path -LiteralPath (P @($cfg, 'sosc-palette.conf'))) 'choices kept (Esc)'
        # No player at all: winget missing is skipped, so Enter is "type a folder".
        Remove-Item -LiteralPath (P @($script:FakeEnvBase, 'Local')) -Recurse -Force
        Use-FakeConsole @('Enter')
        Assert-Equal (Read-SoscNoPlayerChoice -HasWinget $false -AppMpv 'C:\x') '2' 'winget entry skipped'
        Assert-True ($script:Frames[0].Contains('winget is not available')) 'and says why'
        Use-FakeConsole @('UpArrow', 'UpArrow', 'Enter')
        Assert-Equal (Read-SoscNoPlayerChoice -HasWinget $true -AppMpv 'C:\x') '3' 'wraps from winget to Exit, then prepare'
    }
    finally {
        Remove-Item Function:\New-SoscEnvironment
        Remove-Item Function:\Read-SoscLine
        Reset-FakeConsole
    }
}

# Two detected folders, as in the low-window report (tmux 61x6).
function New-TwoFolderList {
    param([string]$Name)
    $base = New-TestDir $Name
    $e = New-FakeEnv $base
    return @(
        (New-SoscCandidate -Env $e -Kind 'mpv' -Exe '' -ConfigDir (P @($base, 'one', 'mpv')) -Portable $false),
        (New-SoscCandidate -Env $e -Kind 'mpv.net' -Exe '' -ConfigDir (P @($base, 'two', 'mpv.net')) -Portable $false)
    )
}

Test-Case 'low window: compact menu first, then numbers; never taller than the window' {
    $list = New-TwoFolderList 'menu-low'
    $script:Lines = New-Object System.Collections.Generic.Queue[string]
    function Read-SoscLine { param([string]$Prompt) return $script:Lines.Dequeue() }
    $script:Headers = New-Object System.Collections.Generic.List[string]
    function Write-SoscInfo { param([string]$Message) $script:Headers.Add($Message) }
    try {
        # Tall enough: the full menu, with the folder lines.
        Use-FakeConsole @('Enter')
        $script:SoscMenuWidth = 61
        [void](Read-SoscTargetChoice -List $list -Mode 'install')
        $full = @($script:Frames[0] -split "`n")
        Assert-True ($script:Frames[0].Contains((P @('one', 'mpv')))) 'full frame shows the folders'
        Assert-True ($full.Count -lt 49) ('fits in 50 lines: ' + $full.Count)
        # Lower: the compact menu (entries and one short help line), every frame
        # of the same height, so redrawing never leaves copies behind.
        Use-FakeConsole @('DownArrow', 'Spacebar', 'Enter')
        $script:SoscMenuWidth = 61
        $script:SoscMenuHeight = $full.Count
        $sel = Read-SoscTargetChoice -List $list -Mode 'install'
        Assert-Equal ([string]::Join(',', $sel.Indexes)) '1' 'compact menu still works'
        foreach ($f in @($script:Frames | Select-Object -First 3)) {
            $rows = @($f -split "`n")
            Assert-Equal $rows.Count 5 ('compact frame: ' + $f)
            Assert-True ($rows.Count -lt $script:SoscMenuHeight - 1) 'leaves a free line'
            Assert-True ($rows[0].EndsWith((P @('one', 'mpv')))) ('folder on the entry line, shortened: ' + $rows[0])
            Assert-True ($rows[0].Contains([char]0x2026) -and $rows[0].Length -le 60) 'shortened to the width'
            Assert-True ($rows[1].EndsWith((P @('two', 'mpv.net')))) 'second folder told apart'
            Assert-True ($rows[4].Contains('Space') -and -not $rows[4].Contains('tick')) ('short help: ' + $rows[4])
        }
        Assert-Equal ([string]::Join(',', $script:ConsoleLog)) 'enter,exit' 'console restored'
        # 61x6 (the report): not even compact fits, so numbers, with nothing drawn
        # and the header written once (by the numbered question).
        Use-FakeConsole @('Enter')
        $script:SoscMenuWidth = 61
        $script:SoscMenuHeight = 6
        $script:Headers.Clear()
        $script:Lines.Enqueue('2')
        $sel = Read-SoscTargetChoice -List $list -Mode 'install'
        Assert-Equal ([string]::Join(',', $sel.Indexes)) '1' 'answered with a number'
        Assert-Equal $script:Frames.Count 0 'no menu drawn'
        Assert-Equal $script:ConsoleLog.Count 0 'console never switched to menu mode'
        Assert-Equal $script:Keys.Count 1 'no key read'
        Assert-True (-not $script:SoscMenu) 'numbers from now on'
        Assert-Equal @($script:Headers | Where-Object { $_ -eq (T 'found_header') }).Count 1 'header written once'
        # Yes/No: two lines, one (no help) in a very low window, numbers below that.
        Use-FakeConsole @('Enter')
        $script:SoscMenuHeight = 3
        Assert-True (Confirm-Sosc -Question 'Q?' -Default $true) 'compact yes/no'
        Assert-Equal $script:Frames[0] ('  ' + $Ptr + ' Yes      No    ') 'answers only'
        Use-FakeConsole @('Enter')
        $script:SoscMenuHeight = 2
        $script:Lines.Enqueue('n')
        Assert-True (-not (Confirm-Sosc -Question 'Q?' -Default $true)) 'typed answer'
        Assert-Equal $script:Frames.Count 0 'no yes/no drawn'
    }
    finally { Remove-Item Function:\Read-SoscLine; Remove-Item Function:\Write-SoscInfo; Reset-FakeConsole }
    # The real renderer refuses a frame taller than the window before writing,
    # and Invoke-SoscRender turns that into the switch to numbers.
    $script:SoscMenuHeight = 4
    try {
        $tall = @(1..3 | ForEach-Object { , [object[]]@(New-SoscSeg ('line ' + $_)) })
        Assert-Throws { Write-SoscMenuFrame -Lines $tall -Previous 0 } '*does not fit*' 'renderer'
        $script:SoscMenuRenderer = $RealRenderer
        Assert-Throws { Invoke-SoscRender -Lines $tall -Previous 0 } $script:SoscNoConsole 'render'
        Assert-True (Test-SoscFrameFits 2) 'two lines fit in four'
        Assert-True (Test-SoscFrameFits 0) 'clearing always fits'
    }
    finally { $script:SoscMenuHeight = 0 }
}

Test-Case 'narrow window: help texts are wrapped, not cut' {
    Set-SoscLanguage 'es'
    try {
        $list = New-TwoFolderList 'menu-narrow'
        Use-FakeConsole @('Enter')
        $script:SoscMenuWidth = 61
        [void](Read-SoscTargetChoice -List $list -Mode 'install')
        $f = $script:Frames[0]
        Assert-True (($f -replace "`n\s*", ' ').Contains('se elige la resaltada)')) ('multi_help2 complete: ' + $f)
        Assert-True ($f.Contains('Esc para salir')) 'multi_help complete'
        $help = $false
        foreach ($row in @($f -split "`n")) {
            Assert-True ($row.Length -le 60) ('fits in 61 columns: ' + $row)
            if ($row -eq '') { $help = $true }
            if ($help) { Assert-True (-not $row.Contains([char]0x2026)) ('help not cut: ' + $row) }
        }
        Assert-True $help 'help lines found'
        $wrapped = Split-SoscHelp -Text 'aaa bbb ccc' -Max 7
        Assert-Equal ([string]::Join('|', $wrapped)) 'aaa bbb|ccc' 'words'
        $dot = ' ' + [char]0x00B7 + ' '
        $wrapped = Split-SoscHelp -Text ('one two' + $dot + 'three' + $dot + 'four') -Max 15
        Assert-Equal ([string]::Join('|', $wrapped)) ('one two' + $dot + 'three|four') 'breaks between parts, without the dot'
    }
    finally { Set-SoscLanguage 'en'; Reset-FakeConsole }
}

Test-Case 'shortcuts: Ctrl/Alt letters do not answer, digits choose in single menus' {
    function Read-SoscLine { param([string]$Prompt) throw 'a number question was asked' }
    try {
        Use-FakeConsole @('Ctrl+S', 'Ctrl+Y', 'Alt+S', 'Enter')
        Assert-True (-not (Confirm-Sosc -Question 'Q?' -Default $false)) 'Ctrl+S, Ctrl+Y and Alt+S ignored'
        Assert-Equal $script:Keys.Count 0 'keys used'
        Use-FakeConsole @('Alt+N', 'Ctrl+N', 'Enter')
        Assert-True (Confirm-Sosc -Question 'Q?' -Default $true) 'Alt+N, Ctrl+N ignored'
        Use-FakeConsole @('Ctrl+C')
        Assert-True (-not (Confirm-Sosc -Question 'Q?' -Default $true)) 'Ctrl+C is still No'
        # Digits, as in the numbered menus.
        Use-FakeConsole @('2')
        Assert-Equal (Read-SoscMainChoice) '2' 'main menu: 2'
        Assert-Equal (Get-LastFrame) ($Ptr + ' Uninstall') 'choice left on screen'
        Use-FakeConsole @('0')
        Assert-Equal (Read-SoscMainChoice) '0' 'main menu: 0 exits'
        Use-FakeConsole @('7', 'Ctrl+2', 'Alt+1', '1')
        Assert-Equal (Read-SoscMainChoice) '1' 'unknown digit and Ctrl/Alt digits ignored'
        Use-FakeConsole @('1', '3', '2')
        Assert-Equal (Read-SoscNoPlayerChoice -HasWinget $false -AppMpv '') '2' 'disabled entries (1, 3) do not answer'
        Use-FakeConsole @('3')
        Assert-Equal (Read-SoscNoPlayerChoice -HasWinget $true -AppMpv 'C:\x') '3' 'no player: 3'
        # Multiple choice: digits do nothing (Enter takes the highlighted one).
        $list = New-TwoFolderList 'menu-digits'
        Use-FakeConsole @('2', 'Enter')
        Assert-Equal ([string]::Join(',', (Read-SoscTargetChoice -List $list -Mode 'install').Indexes)) '0' 'digits ignored in the folder list'
    }
    finally { Remove-Item Function:\Read-SoscLine; Reset-FakeConsole }
}

Test-Case 'keys pressed before a menu opens are thrown away' {
    function Read-SoscLine { param([string]$Prompt) throw 'a number question was asked' }
    try {
        Use-FakeConsole @('Enter')
        $script:Pending.Enqueue('S')
        Assert-True (-not (Confirm-Sosc -Question 'Q?' -Default $false)) 'an S typed during a download does not answer Yes'
        Assert-Equal $script:Pending.Count 0 'flushed'
        Use-FakeConsole @('Enter')
        foreach ($k in @('DownArrow', 'Enter')) { $script:Pending.Enqueue($k) }
        Assert-Equal (Read-SoscMainChoice) '1' 'list menu: earlier keys do not move or choose'
        # The real flush never fails, with or without a console.
        $script:SoscKeyFlush = $RealKeyFlush
        & $script:SoscKeyFlush
    }
    finally { Remove-Item Function:\Read-SoscLine; Reset-FakeConsole }
}

Test-Case 'text fitting: middle ellipsis for paths, end ellipsis otherwise' {
    $e = [string][char]0x2026
    Assert-Equal (Format-SoscFit -Text 'short' -Max 10) 'short' 'fits'
    Assert-Equal (Format-SoscFit -Text 'abcdefghij' -Max 5) ('abcd' + $e) 'end'
    Assert-Equal (Format-SoscFit -Text 'C:\Users\Ana\portable_config' -Max 16 -Middle) ('C:\Us' + $e + 'ble_config') 'middle'
    Assert-Equal (Format-SoscFit -Text 'abc' -Max 1) $e 'one column'
    Assert-Equal (Format-SoscFit -Text 'abc' -Max 0) '' 'no room'
    Assert-Equal (Get-SoscPlainLabel ' O) Other folder') 'Other folder' 'prefix removed'
}

# ---------------------------------------------------------------------------
# v0.1.1: Anime4K, graphics card, backup rotation, osc=no left behind
# ---------------------------------------------------------------------------

# Installs into $Cfg with -Yes semantics and the given -Anime4K choice.
function Invoke-TestInstall {
    param($Cand, $Art, [string]$Stamp, [string]$Choice = '')
    $saved = $script:SoscAnime4KChoice
    $script:SoscAnime4KChoice = $Choice
    try { return (Install-SoscTarget -Candidate $Cand -Source $Source -Artifacts $Art -Stamp $Stamp) }
    finally { $script:SoscAnime4KChoice = $saved }
}

function Get-TestShaders {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return '' }
    return [string]::Join(',', @(Get-ChildItem -LiteralPath $Dir -File -Force | ForEach-Object { $_.Name } | Sort-Object))
}

$OfficialA4kKeys = "CTRL+1 no-osd change-list glsl-shaders set `"~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_M.glsl`"; show-text `"Anime4K: Mode A (Fast)`"`r`n" +
    "CTRL+2 no-osd change-list glsl-shaders set `"~~/shaders/Anime4K_Restore_CNN_Soft_M.glsl`"; show-text `"Anime4K: Mode B (Fast)`"`r`n" +
    "CTRL+0 no-osd change-list glsl-shaders clr `"`"; show-text `"GLSL shaders cleared`"`r`n"

Test-Case 'repository input.conf and mpv.conf carry the same keys and includes as the installer' {
    $in = Get-TestText (P @($RepoRoot, 'portable_config', 'input.conf'))
    foreach ($b in @($script:InputBindings) + @($script:Anime4KBindings)) {
        Assert-True ($in -match ('(?m)^' + [regex]::Escape($b.Key) + '\s+' + [regex]::Escape($b.Command) + '\s*$')) ($b.Key + ' in input.conf')
    }
    $conf = Get-TestText (P @($RepoRoot, 'portable_config', 'mpv.conf'))
    foreach ($l in $script:MpvConfLines) { Assert-True ($conf -match ('(?m)^' + [regex]::Escape($l) + '\s*$')) ($l + ' in mpv.conf') }
}

Test-Case 'graphics card: Alta from GTX 1080 / RTX 2070 / RX 590 up (Anime4K guide), Rapida for the rest' {
    $hq = @('NVIDIA GeForce GTX 1080', 'NVIDIA GeForce GTX 1080 Ti', 'NVIDIA TITAN Xp', 'NVIDIA TITAN RTX',
        'NVIDIA GeForce RTX 2070', 'NVIDIA GeForce RTX 2070 SUPER', 'NVIDIA GeForce RTX 2080 Ti', 'NVIDIA GeForce RTX 3060',
        'NVIDIA GeForce RTX 3060 Laptop GPU', 'NVIDIA GeForce RTX 3070', 'NVIDIA GeForce RTX 4060', 'NVIDIA GeForce RTX 4070 Laptop GPU',
        'NVIDIA GeForce RTX 4090', 'NVIDIA GeForce RTX 5060 Ti', 'NVIDIA GeForce RTX 5090', 'Quadro RTX 4000', 'NVIDIA RTX A4000',
        'NVIDIA RTX 4000 Ada Generation', 'NVIDIA RTX PRO 6000 Blackwell Workstation Edition',
        'Radeon RX 590 Series', 'AMD Radeon RX 590 GME', 'AMD Radeon RX 5600 XT', 'AMD Radeon RX 5700 XT', 'AMD Radeon RX 6600',
        'AMD Radeon RX 6600M', 'AMD Radeon RX 6650 XT', 'AMD Radeon RX 7600', 'AMD Radeon RX 7900 XTX', 'AMD Radeon RX 9060 XT',
        'AMD Radeon RX 9070 XT', 'Radeon RX Vega', 'Radeon RX Vega 56', 'AMD Radeon VII',
        'Intel(R) Arc(TM) A580 Graphics', 'Intel(R) Arc(TM) A750 Graphics', 'Intel(R) Arc(TM) A770 Graphics',
        'Intel(R) Arc(TM) A770M Graphics', 'Intel(R) Arc(TM) B570 Graphics', 'Intel(R) Arc(TM) B580 Graphics',
        'Apple M1 Pro', 'Apple M2 Max', 'Apple M3 Ultra', 'Apple M4 Pro')
    $fast = @('NVIDIA GeForce GTX 1070', 'NVIDIA GeForce GTX 1070 Ti', 'NVIDIA GeForce GTX 1060 6GB', 'NVIDIA GeForce GTX 1660 SUPER',
        'NVIDIA GeForce GTX 1650', 'NVIDIA GeForce GTX 1050 Ti', 'NVIDIA GeForce GTX 980', 'NVIDIA GeForce GTX 960M',
        'NVIDIA GeForce GTX TITAN X', 'NVIDIA GeForce RTX 2050', 'NVIDIA GeForce RTX 2060', 'NVIDIA GeForce RTX 2060 SUPER',
        'NVIDIA GeForce RTX 3050', 'NVIDIA GeForce RTX 3050 Ti Laptop GPU', 'NVIDIA GeForce RTX 4050 Laptop GPU',
        'NVIDIA GeForce RTX 5050', 'NVIDIA RTX A2000 12GB', 'NVIDIA RTX A500 Laptop GPU', 'NVIDIA RTX 2000 Ada Generation',
        'NVIDIA Quadro P4000', 'NVIDIA GeForce MX450', 'NVIDIA GeForce GT 1030',
        'AMD Radeon RX 580 Series', 'AMD Radeon RX 570', 'AMD Radeon RX 550X', 'AMD Radeon RX 460', 'AMD Radeon RX 5500 XT',
        'AMD Radeon RX 6400', 'AMD Radeon RX 6500 XT', 'AMD Radeon RX 7400', 'AMD Radeon(TM) Graphics',
        'AMD Radeon(TM) RX Vega 10 Graphics', 'AMD Radeon 780M Graphics', 'AMD Radeon Pro 5500M',
        'Intel(R) Arc(TM) Graphics', 'Intel(R) Arc(TM) 140V GPU (16GB)', 'Intel(R) Arc(TM) A380 Graphics',
        'Intel(R) Arc(TM) A370M Graphics', 'Intel(R) Arc(TM) A730M Graphics', 'Intel(R) Iris(R) Xe Graphics',
        'Intel(R) UHD Graphics 630', 'Intel(R) UHD Graphics 620', 'Intel(R) HD Graphics 4600', 'Intel Iris Plus Graphics 655',
        'Apple M1', 'Apple M3', 'Apple M4', 'Microsoft Basic Display Adapter', 'Some Unknown GPU', '')
    foreach ($n in $hq) { Assert-Equal (Get-SoscGpuQuality $n) 'hq' $n }
    foreach ($n in $fast) { Assert-Equal (Get-SoscGpuQuality $n) 'fast' $n }
}

Test-Case 'graphics card: the most capable one decides; virtual adapters only as a last resort' {
    $t = Get-SoscGpuTier @('Intel(R) UHD Graphics 630', 'NVIDIA GeForce RTX 4070 Laptop GPU')
    Assert-Equal $t.Name 'NVIDIA GeForce RTX 4070 Laptop GPU' 'dedicated wins'
    Assert-Equal $t.Quality 'hq' 'quality'
    $t = Get-SoscGpuTier @('Intel(R) Arc(TM) Graphics', 'NVIDIA GeForce GTX 1060 6GB', 'AMD Radeon RX 6600')
    Assert-Equal $t.Name 'AMD Radeon RX 6600' 'the capable one decides, whatever the order'
    Assert-Equal $t.Quality 'hq' 'quality of the best'
    $t = Get-SoscGpuTier @('Intel(R) UHD Graphics 630', 'NVIDIA GeForce RTX 3050 Laptop GPU')
    Assert-Equal $t.Quality 'fast' 'no capable card: fast'
    $t = Get-SoscGpuTier @('Parsec Virtual Display Adapter', 'Intel(R) UHD Graphics 630')
    Assert-Equal $t.Name 'Intel(R) UHD Graphics 630' 'real card named'
    Assert-Equal $t.Quality 'fast' 'fast'
    $t = Get-SoscGpuTier @()
    Assert-Equal $t.Name '' 'no name'
    Assert-Equal $t.Quality 'fast' 'unknown is fast'
    Assert-Equal @(Get-SoscGpuNames).Count @(Get-SoscGpuNames).Count 'reading the cards never throws'
}

Test-Case 'sosc-upscale.conf: same bytes as the script, quality from the card, never overwritten' {
    Assert-Equal (Get-SoscUpscaleConfText 'fast') (Get-TestText (P @($RepoRoot, 'portable_config', 'sosc-upscale.conf'))) 'fast = shipped default'
    Assert-Equal (Get-SoscUpscaleConfText 'hq') ((Get-TestText (P @($RepoRoot, 'portable_config', 'sosc-upscale.conf'))) -replace 'fast', 'hq') 'hq'
    Assert-Equal (Get-SoscUpscaleConfText 'x;rm') (Get-SoscUpscaleConfText 'fast') 'unknown quality'
    $d = New-TestDir 'upscale-conf'
    $saved = $script:SoscGpuProbe
    $script:InfoLog = New-Object System.Collections.Generic.List[string]
    function Write-SoscInfo { param([string]$Message) $script:InfoLog.Add($Message) }
    try {
        $script:SoscGpuProbe = { @('Intel(R) UHD Graphics 620', 'NVIDIA GeForce RTX 3070') }
        Initialize-SoscUpscaleConf -ConfigDir $d -Announce $true
        Assert-Equal (Get-TestText (P @($d, 'sosc-upscale.conf'))) (Get-SoscUpscaleConfText 'hq') 'hq written'
        Assert-Equal @($script:InfoLog | Where-Object { $_ -eq ('Graphics card: NVIDIA GeForce RTX 3070 ' + [char]0x2192 + ' quality High') }).Count 1 'one line about the card'
        Set-TestFile (P @($d, 'sosc-upscale.conf')) "# mine`n"
        $script:SoscGpuProbe = { @('Intel(R) UHD Graphics 620') }
        Initialize-SoscUpscaleConf -ConfigDir $d -Announce $true
        Assert-Equal (Get-TestText (P @($d, 'sosc-upscale.conf'))) "# mine`n" 'user choice kept'
        $e = New-TestDir 'upscale-conf-quiet'
        $script:InfoLog.Clear()
        Initialize-SoscUpscaleConf -ConfigDir $e -Announce $false
        Assert-Equal (Get-TestText (P @($e, 'sosc-upscale.conf'))) (Get-SoscUpscaleConfText 'fast') 'fast written'
        Assert-Equal @($script:InfoLog | Where-Object { $_ -like 'Graphics card*' }).Count 0 'no card line without Anime4K'
    }
    finally { $script:SoscGpuProbe = $saved; Remove-Item Function:\Write-SoscInfo }
    Set-SoscLanguage 'es'
    try { Assert-Equal (T 'gpu_line' @('X', (T 'quality_fast'))) ('Gr' + [char]0x00E1 + 'fica: X ' + [char]0x2192 + ' calidad R' + [char]0x00E1 + 'pida') 'Spanish line' }
    finally { Set-SoscLanguage 'en' }
}

Test-Case 'Anime4K: installed with -Yes, update refreshes it, uninstall removes only its shaders' {
    $d = New-TestDir 'a4k-e2e'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'shaders', 'FSRCNNX_x2_8-0-4-1.glsl')) '// user shader'
    Set-TestFile (P @($cfg, 'mpv.conf')) "glsl-shaders=`"~~/shaders/FSRCNNX_x2_8-0-4-1.glsl`"`n"
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    $script:FakeLog = New-Object System.Collections.Generic.List[string]
    $savedDl = $script:SoscDownloader
    $script:SoscDownloader = { param([string]$Url, [string]$OutFile) $script:FakeLog.Add($Url); & $savedDl $Url $OutFile }
    try {
        [void](Invoke-TestInstall $cand $art '20261006-100000')
        $expected = [string]::Join(',', @(@($script:Anime4KRequired) + @('Anime4K_Darken_Fast.glsl', 'Anime4K_Thin_HQ.glsl', 'FSRCNNX_x2_8-0-4-1.glsl') | Sort-Object))
        Assert-Equal (Get-TestShaders (P @($cfg, 'shaders'))) $expected 'Anime4K next to the user shader'
        $rec = Read-SoscRecord $cfg
        Assert-Equal $rec.Values['anime4k'] 'sosc' 'state'
        Assert-Equal $rec.Values['anime4k_version'] '4.0.1' 'version'
        Assert-Equal $rec.Values['shaders_preexisting'] 'yes' 'shaders existed'
        Assert-Equal @($rec.Files | Where-Object { $_ -like 'shaders/*' }).Count 16 'shaders in the record'
        Assert-True (-not (@($rec.Files) -contains 'shaders/FSRCNNX_x2_8-0-4-1.glsl')) 'user shader not recorded'
        $input = Get-TestText (P @($cfg, 'input.conf'))
        Assert-True ($input.Contains('Ctrl+1  script-message-to sosc_upscale set-mode a')) 'Ctrl+1'
        Assert-True ($input.Contains('Ctrl+0  script-message-to sosc_upscale set-mode off')) 'Ctrl+0'
        Assert-True ((Get-TestText (P @($cfg, 'mpv.conf'))).Contains('include="~~/sosc-upscale.conf"')) 'include'
        Assert-Equal (Get-TestText (P @($cfg, 'sosc-upscale.conf'))) (Get-SoscUpscaleConfText 'fast') 'conf for an Intel UHD'
        Assert-Equal @($script:FakeLog | Where-Object { $_ -eq $script:Anime4KUrl }).Count 1 'downloaded once'

        # Update: no question, refreshed, downloaded once per run (artifacts reused).
        Set-TestFile (P @($cfg, 'shaders', 'Anime4K_Thin_HQ.glsl')) 'changed'
        Set-TestFile (P @($cfg, 'sosc-upscale.conf')) "# my choice`n"
        [void](Invoke-TestInstall $cand $art '20261006-100100')
        Assert-Equal (Get-TestText (P @($cfg, 'shaders', 'Anime4K_Thin_HQ.glsl'))) '// fake Anime4K_Thin_HQ.glsl' 'refreshed'
        Assert-Equal (Get-TestText (P @($cfg, 'sosc-upscale.conf'))) "# my choice`n" 'choice kept on update'
        Assert-Equal @($script:FakeLog | Where-Object { $_ -eq $script:Anime4KUrl }).Count 1 'reused, not downloaded again'
        Assert-Equal @([regex]::Matches((Get-TestText (P @($cfg, 'input.conf'))), 'Ctrl\+1')).Count 1 'one Ctrl+1'

        # -Anime4K no on an update: left as it is, still recorded.
        [void](Invoke-TestInstall $cand $art '20261006-100200' 'no')
        Assert-Equal (Read-SoscRecord $cfg).Values['anime4k'] 'sosc' 'still managed'
        Assert-True (Test-Path -LiteralPath (P @($cfg, 'shaders', 'Anime4K_Clamp_Highlights.glsl'))) 'still there'

        [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261006-100300')
        Assert-Equal (Get-TestShaders (P @($cfg, 'shaders'))) 'FSRCNNX_x2_8-0-4-1.glsl' 'only the user shader is left'
        Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) "glsl-shaders=`"~~/shaders/FSRCNNX_x2_8-0-4-1.glsl`"`n" 'mpv.conf as before'
        Assert-True (Test-Path -LiteralPath (P @($cfg, 'sosc-upscale.conf'))) 'choice kept by default'
    }
    finally { $script:SoscDownloader = $savedDl }

    # A folder without shaders: sosc creates it and removes it again.
    $cfg2 = P @($d, 'mpv2')
    $cand2 = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg2 -Portable $false
    [void](Invoke-TestInstall $cand2 $art '20261006-100400')
    Assert-Equal (Read-SoscRecord $cfg2).Values['shaders_preexisting'] 'no' 'shaders created by sosc'
    [void](Uninstall-SoscTarget -Candidate $cand2 -Stamp '20261006-100500')
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg2, 'shaders')))) 'empty shaders folder removed'
}

Test-Case 'Anime4K: -Anime4K no, declined answers, -Anime4K yes and AnimeJaNai' {
    $d = New-TestDir 'a4k-choice'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $script:FakeDownloads.Remove($script:Anime4KUrl)
    $cfg = P @($d, 'mpv')
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    [void](Invoke-TestInstall $cand $art '20261006-110000' 'no')
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'shaders')))) 'nothing installed, nothing downloaded'
    Assert-Equal (Read-SoscRecord $cfg).Values['anime4k'] 'declined' 'declined'
    Assert-True (-not (Get-TestText (P @($cfg, 'input.conf'))).Contains('Ctrl+1')) 'no Anime4K keys'
    Assert-Equal (Get-TestText (P @($cfg, 'sosc-upscale.conf'))) (Get-SoscUpscaleConfText 'fast') 'conf still written (mpv.conf includes it)'
    # -Yes after a "no": the default is now no.
    [void](Invoke-TestInstall $cand $art '20261006-110100')
    Assert-Equal (Read-SoscRecord $cfg).Values['anime4k'] 'declined' 'still declined with -Yes'
    # Interactive: asked again (default no); answering yes installs it.
    $script:FakeDownloads[$script:Anime4KUrl] = (New-FakeAnime4KZip (P @($d, 'a4k2')))
    $script:Anime4KSha256 = Get-SoscFileSha256 $script:FakeDownloads[$script:Anime4KUrl]
    $script:Prompts = New-Object System.Collections.Generic.List[string]
    function Read-SoscLine { param([string]$Prompt) $script:Prompts.Add($Prompt); if ($Prompt -like 'Install Anime4K*') { return 'y' } return '' }
    $script:NonInteractive = $false
    try { [void](Invoke-TestInstall $cand $art '20261006-110200') }
    finally { Remove-Item Function:\Read-SoscLine; $script:NonInteractive = $true }
    Assert-True (@($script:Prompts | Where-Object { $_ -like 'Install Anime4K*`[y/N`]*' }).Count -eq 1) ('asked with default no: ' + [string]::Join(' | ', $script:Prompts))
    Assert-Equal (Read-SoscRecord $cfg).Values['anime4k'] 'sosc' 'installed after yes'
    # -Anime4K yes on a fresh folder, no question.
    $cfg3 = P @($d, 'mpv3')
    $cand3 = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'folder' -Exe '' -ConfigDir $cfg3 -Portable $false
    [void](Invoke-TestInstall $cand3 $art '20261006-110300' 'yes')
    Assert-Equal (Read-SoscRecord $cfg3).Values['anime4k'] 'sosc' 'forced yes'
    # AnimeJaNai: never, not even with -Anime4K yes; also recognised by its scripts.
    $script:FakeDownloads.Remove($script:Anime4KUrl)
    $art2 = [pscustomobject]@{ UoscDir = $art.UoscDir; ThumbfastFile = $art.ThumbfastFile; TempDir = (New-TestDir 'a4k-choice-tmp'); Anime4KDir = '' }
    $aj = P @($d, 'aj', 'portable_config')
    $candAj = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'AnimeJaNai' -Exe '' -ConfigDir $aj -Portable $true
    [void](Invoke-TestInstall $candAj $art2 '20261006-110400' 'yes')
    Assert-Equal (Read-SoscRecord $aj).Values['anime4k'] 'animejanai' 'AnimeJaNai skipped'
    Assert-True (-not (Test-Path -LiteralPath (P @($aj, 'shaders')))) 'no shaders for AnimeJaNai'
    Assert-True (-not (Get-TestText (P @($aj, 'input.conf'))).Contains('Ctrl+1')) 'Ctrl+1 left to AnimeJaNai'
    $ajLike = P @($d, 'aj-like')
    Set-TestFile (P @($ajLike, 'scripts', 'animejanai_v2.lua')) '--'
    $candLike = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'folder' -Exe '' -ConfigDir $ajLike -Portable $false
    [void](Invoke-TestInstall $candLike $art2 '20261006-110500')
    Assert-Equal (Read-SoscRecord $ajLike).Values['anime4k'] 'animejanai' 'AnimeJaNai scripts recognised'
}

Test-Case 'Anime4K installed by hand: left alone with -Yes, taken over with -Anime4K yes and given back on uninstall' {
    $d = New-TestDir 'a4k-manual'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'shaders', 'Anime4K_Restore_CNN_M.glsl')) '// mine'
    Set-TestFile (P @($cfg, 'shaders', 'Anime4K_Upscale_CNN_x2_M.glsl')) '// mine too'
    Set-TestFile (P @($cfg, 'shaders', 'other.glsl')) '// other'
    $inputConf = "# my keys`r`n" + $OfficialA4kKeys + "Ctrl+3 cycle sub`r`n"
    Set-TestFile (P @($cfg, 'input.conf')) $inputConf
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false

    [void](Invoke-TestInstall $cand $art '20261006-120000')
    Assert-Equal (Get-TestShaders (P @($cfg, 'shaders'))) 'Anime4K_Restore_CNN_M.glsl,Anime4K_Upscale_CNN_x2_M.glsl,other.glsl' 'nothing added or moved'
    Assert-Equal (Read-SoscRecord $cfg).Values['anime4k'] 'manual' 'state manual'
    Assert-True (@($script:SoscWarnings | Where-Object { $_ -like '*installed by hand*' }).Count -ge 1) 'warned'
    Assert-True (@($script:SoscWarnings | Where-Object { $_ -like '*does not know what those keys*' }).Count -eq 1) 'key clash explained'
    Assert-True ((Get-TestText (P @($cfg, 'input.conf'))).StartsWith($inputConf)) 'input.conf untouched'
    Assert-True (-not (Get-TestText (P @($cfg, 'input.conf'))).Contains('set-mode')) 'no sosc Anime4K keys'
    Assert-Equal (Get-TestText (P @($cfg, 'sosc-upscale.conf'))) (Get-SoscUpscaleConfText 'fast') 'conf written'

    # Interactive update: not asked again (the user already said no).
    $script:Prompts = New-Object System.Collections.Generic.List[string]
    function Read-SoscLine { param([string]$Prompt) $script:Prompts.Add($Prompt); return 'y' }
    $script:NonInteractive = $false
    try { [void](Invoke-TestInstall $cand $art '20261006-120100') }
    finally { Remove-Item Function:\Read-SoscLine; $script:NonInteractive = $true }
    Assert-Equal @($script:Prompts | Where-Object { $_ -like '*take care of it*' }).Count 0 'not asked again'

    [void](Invoke-TestInstall $cand $art '20261006-120200' 'yes')
    $shaders = Get-TestShaders (P @($cfg, 'shaders'))
    Assert-True ($shaders.Contains('other.glsl') -and $shaders.Contains('Anime4K_Clamp_Highlights.glsl')) 'sosc copy installed, other shader kept'
    Assert-Equal (Get-TestText (P @($cfg, 'shaders', 'Anime4K_Restore_CNN_M.glsl'))) '// fake Anime4K_Restore_CNN_M.glsl' 'sosc copy in place'
    Assert-Equal (Get-TestText (P @($cfg, 'shaders-desactivados', 'Anime4K_Restore_CNN_M.glsl'))) '// mine' 'user copy set aside'
    Assert-Equal (Get-TestText (P @($cfg, 'shaders-desactivados', 'Anime4K_Upscale_CNN_x2_M.glsl'))) '// mine too' 'both set aside'
    $rec = Read-SoscRecord $cfg
    Assert-Equal $rec.Values['anime4k'] 'sosc' 'managed now'
    Assert-Equal @($rec.Moved).Count 2 'moves recorded'
    Assert-Equal @($rec.Commented).Count 3 'commented lines recorded'
    $in = Get-TestText (P @($cfg, 'input.conf'))
    Assert-True ($in.Contains("`r`n# sosc: CTRL+1 no-osd change-list glsl-shaders set")) 'Ctrl+1 line turned off'
    Assert-True ($in.Contains("`r`n# sosc: CTRL+0 no-osd change-list glsl-shaders clr")) 'Ctrl+0 line turned off'
    Assert-True ($in.Contains("`r`nCtrl+3 cycle sub`r`n")) 'other Ctrl+3 binding untouched'
    Assert-True ($in.Contains('Ctrl+1  script-message-to sosc_upscale set-mode a')) 'sosc Ctrl+1'
    Assert-True ($in -notmatch 'set-mode c\r?\n') 'Ctrl+3 is the user''s: left alone'
    Assert-True (@($script:SoscWarnings | Where-Object { $_ -like 'Ctrl+3 is already bound*' }).Count -eq 1) 'Ctrl+3 reported'

    # Backup has the set-aside copies; update keeps the record.
    [void](Invoke-TestInstall $cand $art '20261006-120300')
    $rec = Read-SoscRecord $cfg
    Assert-Equal @($rec.Moved).Count 2 'moves kept on update'
    Assert-Equal @($rec.Commented).Count 3 'comments kept on update'
    Assert-Equal @([regex]::Matches((Get-TestText (P @($cfg, 'input.conf'))), '# sosc: ')).Count 3 'not commented twice'

    [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261006-120400')
    Assert-Equal (Get-TestShaders (P @($cfg, 'shaders'))) 'Anime4K_Restore_CNN_M.glsl,Anime4K_Upscale_CNN_x2_M.glsl,other.glsl' 'user shaders back, sosc ones gone'
    Assert-Equal (Get-TestText (P @($cfg, 'shaders', 'Anime4K_Restore_CNN_M.glsl'))) '// mine' 'the user''s own copy'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'shaders-desactivados')))) 'empty shaders-desactivados removed'
    Assert-Equal (Get-TestText (P @($cfg, 'input.conf'))) $inputConf 'input.conf exactly as before'
}

Test-Case 'Anime4K installed by hand, interactive: take it over, keep the keys commented choice' {
    $d = New-TestDir 'a4k-manual-int'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'shaders', 'Anime4K_Clamp_Highlights.glsl')) '// mine'
    Set-TestFile (P @($cfg, 'input.conf')) $OfficialA4kKeys
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    $script:Prompts = New-Object System.Collections.Generic.List[string]
    function Read-SoscLine {
        param([string]$Prompt)
        $script:Prompts.Add($Prompt)
        if ($Prompt -like '*take care of it*') { return 'y' }
        if ($Prompt -like 'Turn those lines off*') { return 'n' }
        return ''
    }
    $script:NonInteractive = $false
    try { [void](Invoke-TestInstall $cand $art '20261006-130000') }
    finally { Remove-Item Function:\Read-SoscLine; $script:NonInteractive = $true }
    Assert-True (@($script:Prompts | Where-Object { $_ -like '*take care of it*`[y/N`]*' }).Count -eq 1) 'asked, default no'
    Assert-True (@($script:Prompts | Where-Object { $_ -like 'Turn those lines off*`[Y/n`]*' }).Count -eq 1) 'asked about the keys, default yes'
    Assert-Equal (Get-TestText (P @($cfg, 'shaders-desactivados', 'Anime4K_Clamp_Highlights.glsl'))) '// mine' 'set aside'
    $in = Get-TestText (P @($cfg, 'input.conf'))
    Assert-True ($in.StartsWith($OfficialA4kKeys)) 'keys left on (answered no)'
    Assert-True (-not $in.Contains('Ctrl+1  script-message-to')) 'so sosc does not bind them'
    Assert-True ($in.Contains('Ctrl+4  script-message-to sosc_upscale set-mode aa')) 'free keys are bound'
    Assert-Equal @((Read-SoscRecord $cfg).Commented).Count 0 'nothing recorded as commented'
}

Test-Case 'Anime4K zip: only Anime4K_*.glsl at its root is taken; a zip without the needed shaders is refused' {
    $d = New-TestDir 'a4k-zip'
    $zip = New-FakeAnime4KZip (P @($d, 'z')) -Hostile
    $dest = P @($d, 'out', 'anime4k')
    Expand-SoscAnime4K -Zip $zip -Destination $dest
    $names = @(Get-ChildItem -LiteralPath (P @($d, 'out')) -Recurse -Force | ForEach-Object { $_.Name })
    Assert-True (-not ($names -contains 'evil.lua')) 'no other files'
    Assert-True (-not ($names -contains 'Anime4K_Nested.glsl')) 'nothing from folders'
    Assert-True (-not ($names -contains 'Anime4K_Up.glsl')) 'nothing from ../'
    Assert-True (-not ($names -contains 'Anime4K_x.glsl.lua')) 'exact extension'
    Assert-True (-not (Test-Path -LiteralPath (P @($d, 'out', 'sub')))) 'no folder created'
    Assert-Equal @(Get-ChildItem -LiteralPath $dest -File).Count ($script:Anime4KRequired.Count + 2) 'only the shaders'
    $bad = New-FakeAnime4KZip (P @($d, 'z2')) -Missing 'Anime4K_Restore_CNN_VL.glsl'
    Assert-Throws { Expand-SoscAnime4K -Zip $bad -Destination (P @($d, 'out2')) } '*Anime4K_Restore_CNN_VL.glsl*' 'missing shader'
    # A wrong hash: never extracted, nothing installed.
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $script:Anime4KSha256 = 'c' * 64
    $cfg = P @($d, 'mpv')
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    Assert-Throws { Invoke-TestInstall $cand $art '20261006-140000' } '*SHA256*' 'wrong hash'
    Assert-True (-not (Test-Path -LiteralPath (P @($art.TempDir, 'anime4k')))) 'not extracted'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'shaders')))) 'no shaders'
}

Test-Case 'hostile record entries for Anime4K are ignored' {
    $d = New-TestDir 'a4k-hostile'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $top = P @($d, 'top')
    $cfg = P @($top, 'cfg')
    Set-TestFile (P @($top, 'Anime4K_Evil.glsl')) 'keep'
    Set-TestFile (P @($cfg, 'shaders', 'mine.glsl')) 'keep'
    Set-TestFile (P @($cfg, 'shaders-desactivados', 'Anime4K_X.glsl')) 'aside'
    Set-TestFile (P @($cfg, 'input.conf')) "# sosc: Ctrl+9 cycle pause`n# sosc: Ctrl+1 cycle pause`n"
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    [void](Invoke-TestInstall $cand $art '20261006-150000' 'no')
    $hostile = @(
        'file=shaders/../../Anime4K_Evil.glsl', 'file=shaders/mine.glsl', 'file=../Anime4K_Evil.glsl',
        'a4k_moved=shaders-desactivados/Anime4K_X.glsl|scripts/x.lua', 'a4k_moved=shaders-desactivados/Anime4K_X.glsl|../Anime4K_X.glsl',
        'a4k_moved=scripts/a.lua|shaders/a.glsl', 'a4k_moved=a|b|c'
    )
    $recPath = P @($cfg, 'sosc-installed.txt')
    Set-TestFile $recPath ((Get-TestText $recPath) + [string]::Join("`r`n", $hostile) + "`r`na4k_commented=Ctrl+9 cycle pause`r`na4k_commented=Ctrl+1 cycle pause`r`n")
    $rec = Read-SoscRecord $cfg
    Assert-Equal @($rec.Moved).Count 0 'no hostile move kept'
    Assert-Equal @($rec.Commented).Count 2 'comment entries read (checked again before use)'
    [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261006-150100')
    Assert-Equal (Get-TestText (P @($top, 'Anime4K_Evil.glsl'))) 'keep' 'outside file kept'
    Assert-Equal (Get-TestText (P @($cfg, 'shaders', 'mine.glsl'))) 'keep' 'user shader kept'
    Assert-Equal (Get-TestText (P @($cfg, 'shaders-desactivados', 'Anime4K_X.glsl'))) 'aside' 'nothing moved'
    Assert-Equal (Get-TestText (P @($cfg, 'input.conf'))) "# sosc: Ctrl+9 cycle pause`n# sosc: Ctrl+1 cycle pause`n" 'lines that are not Anime4K keys stay commented'
}

Test-Case 'backups: only the 3 newest of this folder are kept, plus the first one; nothing else is touched' {
    $d = New-TestDir 'rotate'
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'mpv.conf')) 'x=1'
    $mk = { param([string]$Name) Set-TestFile (P @($d, $Name, 'mpv.conf')) 'old' }
    foreach ($n in @('mpv-respaldo-sosc-20250101-000000', 'mpv-respaldo-sosc-20250201-000000', 'mpv-respaldo-sosc-20250301-000000',
            'mpv-respaldo-sosc-20250301-000000-2', 'mpv-respaldo-sosc-20250301-000000-10',
            'mpvnet-respaldo-sosc-20240101-000000', 'mpv-respaldo-sosc-2025', 'mpv-respaldo-sosc-20240101-000000-copia', 'otra')) { & $mk $n }
    Set-TestFile (P @($d, 'mpv-respaldo-sosc-20230101-000000')) 'a file, not a folder'
    $b = New-SoscBackup -ConfigDir $cfg -Stamp '20261006-160000'
    Remove-SoscOldBackups -ConfigDir $cfg -Protect @((P @($d, 'mpv-respaldo-sosc-20250101-000000')), '::bad path::')
    $left = @(Get-ChildItem -LiteralPath $d -Force | ForEach-Object { $_.Name } | Sort-Object)
    $want = @('mpv', 'mpv-respaldo-sosc-20230101-000000', 'mpv-respaldo-sosc-20250101-000000', 'mpv-respaldo-sosc-20250301-000000-10',
        'mpv-respaldo-sosc-20250301-000000-2', 'mpv-respaldo-sosc-2025', 'mpv-respaldo-sosc-20240101-000000-copia',
        'mpv-respaldo-sosc-20261006-160000', 'mpvnet-respaldo-sosc-20240101-000000', 'otra') | Sort-Object
    Assert-Equal ([string]::Join(',', $left)) ([string]::Join(',', $want)) 'kept'
    Assert-True (@($script:SoscWarnings).Count -eq 0) 'no warnings'
    # Through an install: the record's first backup survives every update.
    $d2 = New-TestDir 'rotate-install'
    $art = New-FakeArtifacts (P @($d2, 'dl'))
    $cfg2 = P @($d2, 'mpv')
    Set-TestFile (P @($cfg2, 'mpv.conf')) "volume=50`n"
    $cand = New-SoscCandidate -Env (New-FakeEnv $d2) -Kind 'mpv' -Exe '' -ConfigDir $cfg2 -Portable $false
    $first = Invoke-TestInstall $cand $art '20261006-170000' 'no'
    foreach ($i in 1..5) { [void](Invoke-TestInstall $cand $art ('20261006-17000' + $i) 'no') }
    $backups = @(Get-ChildItem -LiteralPath $d2 -Directory | Where-Object { $_.Name -like 'mpv-respaldo-sosc-*' } | ForEach-Object { $_.Name } | Sort-Object)
    Assert-Equal ([string]::Join(',', $backups)) 'mpv-respaldo-sosc-20261006-170000,mpv-respaldo-sosc-20261006-170003,mpv-respaldo-sosc-20261006-170004,mpv-respaldo-sosc-20261006-170005' 'first + 3 newest'
    Assert-Equal (Get-TestText (P @($first, 'mpv.conf'))) "volume=50`n" 'first backup has the config from before sosc'
    $linked = $true
    try { New-Item -ItemType SymbolicLink -Path (P @($d2, 'mpv-respaldo-sosc-20000101-000000')) -Target (P @($d2, 'dl')) | Out-Null }
    catch { $linked = $false }
    if ($linked) {
        Remove-SoscOldBackups -ConfigDir $cfg2 -Keep 1
        Assert-True (Test-Path -LiteralPath (P @($d2, 'dl', 'thumbfast-src.lua'))) 'a link is never followed or removed'
        Assert-True (Test-Path -LiteralPath (P @($d2, 'mpv-respaldo-sosc-20000101-000000'))) 'link left'
    }
}

Test-Case 'uninstall without uosc: an osc=no of the user is reported; -Yes only warns' {
    $d = New-TestDir 'osc-orphan'
    $art = New-FakeArtifacts (P @($d, 'dl'))
    $cfg = P @($d, 'mpv')
    $conf = "osc=no # mine`nvolume=50`n"
    Set-TestFile (P @($cfg, 'mpv.conf')) $conf
    $cand = New-SoscCandidate -Env (New-FakeEnv $d) -Kind 'mpv' -Exe '' -ConfigDir $cfg -Portable $false
    [void](Invoke-TestInstall $cand $art '20261006-180000' 'no')
    [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261006-180100')
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts', 'uosc')))) 'uosc removed (default)'
    Assert-True (@($script:SoscWarnings | Where-Object { $_ -like '*"osc=no # mine"*no on-screen controls*' }).Count -eq 1) 'warned'
    Assert-True (@($script:SoscWarnings | Where-Object { $_ -like 'Left as it is*' }).Count -eq 1) 'and left as it is'
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) $conf 'line untouched with -Yes'

    # Interactive: turn it off.
    [void](Invoke-TestInstall $cand $art '20261006-180200' 'no')
    function Read-SoscLine { param([string]$Prompt) if ($Prompt -like 'Turn that line off*`[Y/n`]*') { return '' } return '' }
    $script:NonInteractive = $false
    try { [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261006-180300') }
    finally { Remove-Item Function:\Read-SoscLine; $script:NonInteractive = $true }
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) "# sosc: osc=no # mine`nvolume=50`n" 'turned off'

    # An interface set aside and not given back: offered again first.
    Set-TestFile (P @($cfg, 'mpv.conf')) "osc=false`n"
    Set-TestFile (P @($cfg, 'scripts', 'modernz.lua')) '-- modernz'
    [void](Invoke-TestInstall $cand $art '20261006-180400' 'no')
    $script:Prompts = New-Object System.Collections.Generic.List[string]
    function Read-SoscLine {
        param([string]$Prompt)
        $script:Prompts.Add($Prompt)
        if ($Prompt -like 'Move back the interfaces*so there are controls*') { return 'y' }
        if ($Prompt -like 'Move back the interfaces*') { return 'n' }
        return ''
    }
    $script:NonInteractive = $false
    try { [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261006-180500') }
    finally { Remove-Item Function:\Read-SoscLine; $script:NonInteractive = $true }
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'modernz.lua'))) 'interface back'
    Assert-Equal @($script:Prompts | Where-Object { $_ -like 'Turn that line off*' }).Count 0 'no need to turn osc=no off'
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) "osc=false`n" 'osc=false kept for modernz'

    # uosc kept: nothing to say.
    Set-TestFile (P @($cfg, 'mpv.conf')) "no-osc`n"
    Remove-Item -LiteralPath (P @($cfg, 'scripts', 'modernz.lua'))
    Set-TestFile (P @($cfg, 'scripts', 'uosc', 'main.lua')) '-- mine'
    [void](Invoke-TestInstall $cand $art '20261006-180600' 'no')
    $script:SoscWarnings.Clear()
    [void](Uninstall-SoscTarget -Candidate $cand -Stamp '20261006-180700')
    Assert-Equal @($script:SoscWarnings | Where-Object { $_ -like '*on-screen controls*' }).Count 0 'uosc there before: kept, no warning'
}

# ---------------------------------------------------------------------------
# Run without a file: irm | iex, and [scriptblock]::Create for options. Each of
# these starts a real pwsh and dot-sources tests/iex-harness.ps1 from -Command,
# so the installer runs in the global scope of a fresh session, as at a prompt.
# ---------------------------------------------------------------------------

$script:Pwsh = (Get-Process -Id $PID).Path

# A copy of the installer with some marker lines replaced, the way
# tools/make-release.sh does it: whole lines, each exactly once.
function New-ReleaseScript {
    param([string]$Path, [System.Collections.Specialized.OrderedDictionary]$Replace)
    $lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllText($InstallScript) -split "`n")
    foreach ($old in $Replace.Keys) {
        $at = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -ceq $old) { $i } })
        if ($at.Count -ne 1) { throw ('marker found ' + $at.Count + ' times: ' + $old) }
        $lines[$at[0]] = $Replace[$old]
    }
    [System.IO.File]::WriteAllText($Path, [string]::Join("`n", $lines), (New-Object System.Text.UTF8Encoding($false)))
}

# Release copy pointing at $Zip, plus fake uosc and thumbfast with their hashes.
# Returns the script path and the URL -> file map for the fake downloader.
function New-TestRelease {
    param([string]$Dir, [string]$Zip, [string]$ZipSha256 = '')
    if (-not $ZipSha256) { $ZipSha256 = Get-SoscFileSha256 $Zip }
    $uosc = New-FakeUoscZip $Dir
    $thumb = P @($Dir, 'thumbfast-src.lua')
    Set-TestFile $thumb '-- fake thumbfast'
    $a4k = New-FakeAnime4KZip (P @($Dir, 'a4k'))
    $scriptPath = P @($Dir, 'sosc.ps1')
    $replace = [ordered]@{}
    $replace["`$script:SoscVersion = 'dev'"] = "`$script:SoscVersion = '9.9.9'"
    $replace["`$script:SoscReleaseUrl = ''"] = "`$script:SoscReleaseUrl = '" + $TestReleaseUrl + "'"
    $replace["`$script:SoscReleaseSha256 = ''"] = "`$script:SoscReleaseSha256 = '" + $ZipSha256 + "'"
    $replace["`$script:UoscSha256 = '" + $OriginalUoscSha + "'"] = "`$script:UoscSha256 = '" + (Get-SoscFileSha256 $uosc) + "'"
    $replace["`$script:ThumbfastSha256 = '" + $OriginalThumbSha + "'"] = "`$script:ThumbfastSha256 = '" + (Get-SoscFileSha256 $thumb) + "'"
    $replace["`$script:Anime4KSha256 = '" + $OriginalAnime4KSha + "'"] = "`$script:Anime4KSha256 = '" + (Get-SoscFileSha256 $a4k) + "'"
    New-ReleaseScript -Path $scriptPath -Replace $replace
    $map = @{}
    $map[$TestReleaseUrl] = $Zip
    $map[$script:UoscUrl] = $uosc
    $map[$script:ThumbfastUrl] = $thumb
    $map[$script:Anime4KUrl] = $a4k
    return [pscustomobject]@{ Script = $scriptPath; Downloads = $map }
}

# Runs the harness in a new pwsh. $Stdin: the typed answers. $TempDir: the
# temporary folder of that process (TMPDIR, TEMP, TMP), to check it is left
# clean. Returns the report (null when the process ended without writing it,
# e.g. because the installer called exit) and everything the process printed.
function Invoke-IexHarness {
    param([string]$Script, [hashtable]$Downloads = @{}, [string]$Mode = 'iex', [string[]]$Stdin = @(),
        [string]$Action = '', [string]$Target = '', [string]$YesValue = '', [switch]$StrictLatest, [string]$TempDir = '')
    $id = [guid]::NewGuid().ToString('N')
    $report = P @($TestRoot, ('harness-' + $id + '.json'))
    $dl = P @($TestRoot, ('harness-' + $id + '-downloads.json'))
    [System.IO.File]::WriteAllText($dl, ($Downloads | ConvertTo-Json))
    $q = { param([string]$v) "'" + $v.Replace("'", "''") + "'" }
    $cmd = '. ' + (& $q $IexHarness) + ' -Script ' + (& $q $Script) + ' -Report ' + (& $q $report) + ' -Downloads ' + (& $q $dl) + ' -Mode ' + $Mode
    if ($Action) { $cmd += ' -Action ' + (& $q $Action) }
    if ($Target) { $cmd += ' -Target ' + (& $q $Target) }
    if ($YesValue) { $cmd += ' -YesValue ' + $YesValue }
    if ($StrictLatest) { $cmd += ' -StrictLatest' }
    $saved = @($env:TMPDIR, $env:TEMP, $env:TMP)
    if ($TempDir) { $env:TMPDIR = $TempDir; $env:TEMP = $TempDir; $env:TMP = $TempDir }
    try {
        $stdinLines = @($Stdin) + @('')
        $out = @($stdinLines | & $script:Pwsh -NoProfile -Command $cmd 2>&1 | ForEach-Object { [string]$_ })
    }
    finally { $env:TMPDIR = $saved[0]; $env:TEMP = $saved[1]; $env:TMP = $saved[2] }
    $r = $null
    if (Test-Path -LiteralPath $report) { $r = Get-Content -Raw -LiteralPath $report | ConvertFrom-Json }
    return [pscustomobject]@{ Report = $r; Text = [string]::Join("`n", $out) }
}

function Assert-SessionClean {
    param($Run, [int]$ExitCode)
    $r = $Run.Report
    Assert-True ($null -ne $r) ('the session survived (no exit); output: ' + $Run.Text)
    Assert-True $r.Alive 'alive'
    Assert-Equal ([int]$r.ExitCode) $ExitCode ('$LASTEXITCODE; output: ' + $Run.Text)
    Assert-Equal @($r.NewVariables).Count 0 ('variables left: ' + [string]::Join(',', @($r.NewVariables)))
    Assert-Equal @($r.NewFunctions).Count 0 ('functions left: ' + [string]::Join(',', @($r.NewFunctions)))
    Assert-Equal @($r.NewModules).Count 0 ('modules left: ' + [string]::Join(',', @($r.NewModules)))
    Assert-Equal @($r.Output).Count 0 ('pipeline output: ' + [string]::Join(',', @($r.Output)))
    Assert-True $r.TlsSame 'SecurityProtocol put back'
    Assert-True $r.CtrlCSame 'TreatControlCAsInput untouched'
}

function Get-SoscTempLeftovers {
    param([string]$Dir)
    return @(Get-ChildItem -LiteralPath $Dir -Force -Filter 'sosc-install-*')
}

Test-Case 'iex at a prompt, no options: no exit, nothing left in the session' {
    $run = Invoke-IexHarness -Script $InstallScript -Stdin @('0')
    Assert-SessionClean $run 0
    Assert-Equal $run.Report.Eap 'Continue' 'ErrorActionPreference kept'
    Assert-Equal $run.Report.Strict 'off' 'StrictMode stays off'
    Assert-True ($run.Text.Contains('Cancelled.')) 'menu answered'
}

Test-Case 'iex in a session with StrictMode Latest and ErrorActionPreference Stop: runs, both kept' {
    $run = Invoke-IexHarness -Script $InstallScript -Stdin @('0') -StrictLatest
    Assert-SessionClean $run 0
    Assert-Equal $run.Report.Eap 'Stop' 'ErrorActionPreference kept'
    Assert-Equal $run.Report.Strict 'on' 'StrictMode Latest kept'
}

Test-Case 'iex of the repository version: no release yet, nothing downloaded' {
    $d = New-TestDir 'iex-dev'
    $tmp = New-TestDir 'iex-dev-tmp'
    # Install, "type the folder myself" (no player on this machine), the folder.
    $run = Invoke-IexHarness -Script $InstallScript -Stdin @('1', '2', (P @($d, 'mpv'))) -TempDir $tmp
    Assert-SessionClean $run 1
    Assert-True ($run.Text.Contains('no published release')) ('message; output: ' + $run.Text)
    Assert-Equal @($run.Report.Downloads).Count 0 'no download'
    Assert-Equal @(Get-SoscTempLeftovers $tmp).Count 0 'temp folder removed'
    Assert-True (-not (Test-Path -LiteralPath (P @($d, 'mpv', 'scripts')))) 'nothing installed'
}

Test-Case 'release through iex: its zip comes from the downloader, is checked and installed; temp removed' {
    $d = New-TestDir 'iex-release'
    $tmp = New-TestDir 'iex-release-tmp'
    $rel = New-TestRelease -Dir $d -Zip (New-TestReleaseZip $d)
    $cfg = P @($d, 'mpv')
    $run = Invoke-IexHarness -Script $rel.Script -Downloads $rel.Downloads -Stdin @('1', '2', $cfg) -TempDir $tmp
    Assert-SessionClean $run 0
    Assert-True $run.Report.TlsTouched 'the downloader changed SecurityProtocol, so putting it back was tested'
    Assert-Equal ([string]::Join(' ', @($run.Report.Downloads))) ([string]::Join(' ', @($TestReleaseUrl, $script:UoscUrl, $script:ThumbfastUrl, $script:Anime4KUrl))) 'downloads, release zip first, Anime4K when the folder needs it'
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'shaders', 'Anime4K_Clamp_Highlights.glsl'))) 'Anime4K installed (default answer)'
    foreach ($f in @(Get-ChildItem -LiteralPath (P @($RepoRoot, 'portable_config', 'scripts')) -File)) {
        Assert-Equal (Get-TestText (P @($cfg, 'scripts', $f.Name))) (Get-TestText $f.FullName) $f.Name
    }
    Assert-True (Test-Path -LiteralPath (P @($cfg, 'scripts', 'uosc', 'main.lua'))) 'uosc'
    $rec = Read-SoscRecord $cfg
    Assert-Equal $rec.Values['sosc_version'] '9.9.9' 'record version'
    Assert-Equal @(Get-SoscTempLeftovers $tmp).Count 0 'temp folder removed'

    # Options through [scriptblock]::Create: uninstall without questions.
    $run = Invoke-IexHarness -Script $rel.Script -Downloads $rel.Downloads -Mode create -Action 'uninstall' -Target $cfg -YesValue 'true' -TempDir $tmp
    Assert-SessionClean $run 0
    Assert-Equal @($run.Report.Downloads).Count 0 'uninstall downloads nothing'
    Assert-Equal @(Get-ChildItem -LiteralPath $cfg -Recurse -Filter 'sosc-*.lua').Count 0 'uninstalled'
}

Test-Case 'release with a wrong hash: zip refused, nothing installed, temp removed' {
    $d = New-TestDir 'iex-badhash'
    $tmp = New-TestDir 'iex-badhash-tmp'
    $rel = New-TestRelease -Dir $d -Zip (New-TestReleaseZip $d) -ZipSha256 ('b' * 64)
    $cfg = P @($d, 'mpv')
    $run = Invoke-IexHarness -Script $rel.Script -Downloads $rel.Downloads -Mode create -Action 'install' -Target $cfg -YesValue 'true' -TempDir $tmp
    Assert-SessionClean $run 1
    Assert-True $run.Report.TlsTouched 'the downloader changed SecurityProtocol, so putting it back was tested'
    Assert-True ($run.Text.Contains('does not match its expected SHA256')) ('message; output: ' + $run.Text)
    Assert-Equal ([string]::Join(' ', @($run.Report.Downloads))) $TestReleaseUrl 'only the zip was fetched'
    Assert-True (-not (Test-Path -LiteralPath (P @($cfg, 'scripts')))) 'nothing installed'
    Assert-Equal @(Get-SoscTempLeftovers $tmp).Count 0 'temp folder removed'
}

Test-Case 'options through [scriptblock]::Create: -Yes:$false is not -Yes' {
    # -Yes without -Action is a usage error (2); -Yes:$false shows the menu (0 on Exit).
    $run = Invoke-IexHarness -Script $InstallScript -Mode create -YesValue 'true'
    Assert-SessionClean $run 2
    $run = Invoke-IexHarness -Script $InstallScript -Mode create -YesValue 'false' -Stdin @('0')
    Assert-SessionClean $run 0
}

Test-Case '-File: the exit code reaches the caller' {
    $saved = $env:SOSC_INSTALL_TEST
    $env:SOSC_INSTALL_TEST = ''
    try {
        $out = & $script:Pwsh -NoProfile -NonInteractive -File $InstallScript -Yes 2>&1
        Assert-Equal $LASTEXITCODE 2 ('-Yes without -Action: ' + [string]::Join(' ', @($out)))
        $out = & $script:Pwsh -NoProfile -NonInteractive -File $InstallScript -Action nonsense 2>&1
        Assert-True ($LASTEXITCODE -ne 0) 'invalid -Action fails'
        $out = '0' | & $script:Pwsh -NoProfile -File $InstallScript -NoMenu 2>&1
        Assert-Equal $LASTEXITCODE 0 ('exit from the menu: ' + [string]::Join(' ', @($out)))
    }
    finally { $env:SOSC_INSTALL_TEST = $saved }
}

# ---------------------------------------------------------------------------

Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
