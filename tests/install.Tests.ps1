# Tests for install/install.ps1, without Pester. Run from anywhere:
#   pwsh -NoProfile -File tests/install.Tests.ps1
# Exit code 0 when everything passes. Windows paths are simulated with temporary
# folders and an injected environment; nothing is downloaded.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$env:SOSC_INSTALL_TEST = '1'
$env:SOSC_LANG = 'en'
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$InstallScript = [System.IO.Path]::Combine($RepoRoot, 'install', 'install.ps1')
. $InstallScript
$script:SoscQuiet = $true

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

# Prepares fake uosc/thumbfast downloads with matching hashes; returns artifacts.
function New-FakeArtifacts {
    param([string]$Dir)
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $zip = New-FakeUoscZip $Dir
    $thumb = P @($Dir, 'thumbfast-src.lua')
    Set-TestFile $thumb '-- fake thumbfast'
    $script:UoscSha256 = Get-SoscFileSha256 $zip
    $script:ThumbfastSha256 = Get-SoscFileSha256 $thumb
    $script:FakeDownloads = @{}
    $script:FakeDownloads[$script:UoscUrl] = $zip
    $script:FakeDownloads[$script:ThumbfastUrl] = $thumb
    $work = P @($Dir, 'work')
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    return (Get-SoscArtifacts -TempDir $work)
}

$OriginalUoscSha = $script:UoscSha256
$OriginalThumbSha = $script:ThumbfastSha256
$Source = Get-SoscSource -TempDir $TestRoot

# ---------------------------------------------------------------------------
# Script hygiene
# ---------------------------------------------------------------------------

Test-Case 'install.ps1 is pure ASCII (Windows PowerShell 5.1 reads it as ANSI)' {
    $bytes = Get-TestBytes $InstallScript
    $bad = @($bytes | Where-Object { $_ -gt 127 })
    Assert-Equal $bad.Count 0 'non-ASCII bytes'
}

Test-Case 'install.ps1 avoids PowerShell 7-only syntax' {
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
        Assert-True ((T 'release_unpublished').Contains('install\install.ps1')) 'single backslash'
        foreach ($k in $script:SoscStringsEn.Keys) { Assert-True ($script:SoscStringsEs.ContainsKey($k)) ('es key ' + $k) }
        foreach ($k in $script:SoscStringsEs.Keys) { Assert-True ($script:SoscStringsEn.ContainsKey($k)) ('en key ' + $k) }
    }
    finally { Set-SoscLanguage 'en' }
    Assert-True ((T 'release_unpublished').Contains('install\install.ps1')) 'en single backslash'
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
    Assert-Equal ([string]::Join('|', $b.Lines)) 'osc=no|osd-bar=no|include="~~/sosc-palette.conf"|include="~~/sosc-subs.conf"' 'lines'
    Assert-True (-not ($b.Lines -contains 'border=no')) 'no border=no'
    $b = Get-SoscMpvConfBlock "vo=gpu`n[anime]`nprofile-cond=1`n"
    Assert-Equal $b.Lines[0] '[default]' 'default section'
    $b = Get-SoscMpvConfBlock "[anime]`nx=1`n[default]`ny=2`n"
    Assert-True (-not ($b.Lines -contains '[default]')) 'already back at [default]'
    $b = Get-SoscMpvConfBlock ("a=1`n" + $BlockB + "`nosc=no`n" + $BlockE + "`n[after]`nz=1`n")
    Assert-True (-not ($b.Lines -contains '[default]')) 'profile after the block does not count'
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

Test-Case 'backup is a sibling folder without cache and watch_later' {
    $d = New-TestDir 'backup'
    $cfg = P @($d, 'portable config')
    Set-TestFile (P @($cfg, 'mpv.conf')) 'x=1'
    Set-TestFile (P @($cfg, 'shaders', 'a.glsl')) 'shader'
    Set-TestFile (P @($cfg, 'cache', 'big.bin')) 'cache'
    Set-TestFile (P @($cfg, 'watch_later', 'ABC')) 'pos'
    Set-TestFile (P @($cfg, '.hidden')) 'h'
    $b = New-SoscBackup -ConfigDir $cfg -Stamp '20260101-000000'
    Assert-Equal $b ((Get-SoscFullPath $cfg) + '-respaldo-sosc-20260101-000000') 'name'
    Assert-Equal (Get-TestText (P @($b, 'mpv.conf'))) 'x=1' 'file copied'
    Assert-True (Test-Path -LiteralPath (P @($b, 'shaders', 'a.glsl'))) 'subfolder copied'
    Assert-True (Test-Path -LiteralPath (P @($b, '.hidden'))) 'hidden copied'
    Assert-True (-not (Test-Path -LiteralPath (P @($b, 'cache')))) 'no cache'
    Assert-True (-not (Test-Path -LiteralPath (P @($b, 'watch_later')))) 'no watch_later'
    $b2 = New-SoscBackup -ConfigDir $cfg -Stamp '20260101-000000'
    Assert-Equal $b2 ($b + '-2') 'same second: new name'
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
    }
    finally { $script:SoscScriptRoot = $saved }
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
    Assert-True ($mpvAfter.EndsWith('include="~~/sosc-subs.conf"' + "`r`n" + $BlockE + "`r`n")) 'block at the end, CRLF'
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
    function Read-SoscLine { param([string]$Prompt) if ($Prompt -like '*palette and subtitle*') { return 'y' } return '' }
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
    foreach ($a in @('9', '1', '2', $cfg)) { $script:Answers.Enqueue($a) }
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
        foreach ($a in @('1', '1')) { $script:Answers.Enqueue($a) }
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

Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
