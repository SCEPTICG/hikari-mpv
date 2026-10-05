<#
.SYNOPSIS
    sosc installer for Windows: mpv, mpv.net and AnimeJaNai.

.DESCRIPTION
    Installs, updates or removes sosc (https://github.com/SCEPTICG/sosc), together
    with uosc and thumbfast, in one or more mpv config folders.

    Run it from a copy of the repository:
        powershell -ExecutionPolicy Bypass -File install\install.ps1

    No administrator rights, no registry, no PATH changes. Before touching a
    folder it copies what it may change (mpv.conf, input.conf, scripts,
    script-opts, fonts and its own files) to a sibling folder named
    <config>-respaldo-sosc-<date>.

    Works with Windows PowerShell 5.1 and PowerShell 7. This file is pure ASCII on
    purpose: Windows PowerShell 5.1 reads BOM-less scripts as ANSI, so the Spanish
    messages are written with \uXXXX escapes and decoded at start-up.

.PARAMETER Action
    install or uninstall. Without it a menu is shown.

.PARAMETER Target
    mpv config folder(s) to work on (the folder that holds mpv.conf, e.g.
    ...\mpv-AnimeJaNai\portable_config or %APPDATA%\mpv). Several folders go
    separated by ';' (with -File, PowerShell does not split "a,b" into a list).
    Without it the detected players are listed.

.PARAMETER Yes
    Do not ask: take the default answer to every question. Needs -Action, and
    -Target when more than one folder is found.

.NOTES
    Exit codes: 0 done (or cancelled by the user), 1 at least one folder failed,
    2 wrong usage or nothing to work on.
#>
[CmdletBinding()]
param(
    [ValidateSet('', 'install', 'uninstall')]
    [string]$Action = '',
    [string[]]$Target = @(),
    [switch]$Yes
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$script:SoscVersion = 'dev'

# Release zip of sosc for the "run on its own" mode (irm .../install.ps1 | iex).
# Empty until the publication phase: with no URL the installer explains that it
# has to be run from a copy of the repository.
$script:SoscReleaseUrl = ''
$script:SoscReleaseSha256 = ''

# uosc: fixed release, verified by SHA256 before it is extracted.
$script:UoscVersion = '5.13.0'
$script:UoscUrl = 'https://github.com/tomasklaen/uosc/releases/download/5.13.0/uosc.zip'
$script:UoscSha256 = '4be9da3289285300fa374496c3f1bfd7bb20ac08e890d25bd5a06b28eebe4882'
# What uosc's own installer puts in the config folder (installers/windows.ps1),
# minus its uosc.conf: sosc ships its own.
$script:UoscFonts = @('uosc_icons.otf', 'uosc_textures.ttf')

# thumbfast: fixed commit, verified by SHA256.
$script:ThumbfastCommit = '0f711de3138c9bd6718209d819ac54022c23ded2'
$script:ThumbfastUrl = 'https://raw.githubusercontent.com/po5/thumbfast/0f711de3138c9bd6718209d819ac54022c23ded2/thumbfast.lua'
$script:ThumbfastSha256 = 'a3d08e71eae8b892f6cd39f9593ea219768e709312d176bca883841b156448bf'

# Downloads are only allowed over HTTPS from these hosts.
$script:AllowedHosts = @('github.com', 'raw.githubusercontent.com')

$script:BlockBegin = '# >>> sosc (managed block, do not edit) >>>'
$script:BlockEnd = '# <<< sosc <<<'

$script:MpvConfLines = @(
    'osc=no',
    'osd-bar=no',
    'include="~~/sosc-palette.conf"',
    'include="~~/sosc-subs.conf"'
)

$script:InputBindings = @(
    @{ Key = 'Alt+p'; Command = 'script-binding sosc_palettes/open-menu' },
    @{ Key = 'Alt+s'; Command = 'script-binding sosc_skip/skip' },
    @{ Key = 'Alt+t'; Command = 'script-binding sosc_subs/open-menu' }
)

# Files of sosc that only get copied when missing: they hold the user's choices.
$script:UserChoiceFiles = @('sosc-palette.conf', 'sosc-subs.conf')

# script-opts that are not named sosc-*: removed on uninstall only if sosc put them there.
$script:SharedConfs = @('uosc.conf', 'thumbfast.conf')

$script:RecordName = 'sosc-installed.txt'
$script:DisabledDir = 'scripts-desactivados'
$script:OriginalsDir = 'sosc-originales'

# What the backup copies: only what the installer can change. shaders, cache,
# watch_later and anything else in the folder are never touched, so not copied.
$script:BackupItems = @(
    'mpv.conf', 'input.conf', 'scripts', 'script-opts', 'fonts',
    'sosc-palette.conf', 'sosc-subs.conf', 'sosc-installed.txt',
    'scripts-desactivados', 'sosc-originales'
)

# Signs that a folder belongs to mpv (any of them is enough).
$script:MpvConfigFiles = @('mpv.conf', 'input.conf', 'sosc-installed.txt', 'sosc-palette.conf', 'sosc-subs.conf')
$script:MpvConfigDirs = @('scripts', 'script-opts')
$script:PlayerExes = @('mpvnet.exe', 'mpv.exe')

# Scripts that replace mpv's on-screen controller and clash with uosc. Matched
# against file names in scripts/ (wildcards, case-insensitive). Kept short on
# purpose: only well-known OSC replacements.
$script:ConflictPatterns = @(
    'osc.lua', 'osc_*.lua', 'osc-*.lua', 'oscc.lua', 'oscc_*.lua', 'oscc-*.lua',
    'modernx*.lua', 'modernz*.lua', 'mordenx*.lua', 'mpv-osc-*.lua',
    'mfpbar.lua', 'mpv_thumbnail_script_client_osc*.lua'
)
# Fonts that clearly belong to one of them (fonts/).
$script:ConflictFontPatterns = @('modernx*', 'modernz*', 'mordenx*')
# Leftovers of uosc 4, which would load next to scripts/uosc.
$script:UoscLegacy = @('uosc.lua', 'uosc_shared')

$script:SoscScriptRoot = $PSScriptRoot
$script:SoscQuiet = $false
$script:NonInteractive = $false
# Set when running as administrator: deleting or moving then refuses paths that
# go through a link (junction or symbolic link) inside the config folder.
$script:SoscElevated = $false
$script:SoscWarnings = New-Object System.Collections.Generic.List[string]

# Download function, replaceable in tests: param($Url, $OutFile).
$script:SoscDownloader = {
    param([string]$Url, [string]$OutFile)
    $oldProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    }
    finally {
        $ProgressPreference = $oldProgress
    }
}

# ---------------------------------------------------------------------------
# Messages (English and Spanish). Spanish strings use \uXXXX escapes.
# ---------------------------------------------------------------------------

$script:SoscStringsEn = @{
    title                 = 'sosc installer'
    menu                  = "1) Install or update`n2) Uninstall`n0) Exit"
    menu_prompt           = 'Choose an option'
    invalid               = 'Invalid option.'
    detecting             = 'Looking for mpv players...'
    found_header          = 'Players and config folders found:'
    found_header_uninst   = 'Folders with sosc:'
    cand_exe              = '     Player: {0}'
    cand_config           = '     Config: {0}'
    kind_folder           = 'config folder'
    tag_installed         = '[sosc {0} installed]'
    tag_manual            = '[sosc files present, no installer record]'
    tag_readonly          = '[no write permission]'
    tag_new               = '[will be created]'
    opt_other             = 'O) Other folder'
    opt_quit              = '0) Exit'
    select_prompt         = 'Choose one or more, separated by commas (e.g. 1,3)'
    ask_folder            = 'Full path of the mpv config folder (where mpv.conf is or should go)'
    folder_missing        = 'The folder {0} does not exist and neither does its parent.'
    readonly_warn         = 'Cannot write to {0}.'
    readonly_offer        = 'Use {0} instead?'
    readonly_portable     = 'Careful: while {0} exists, this player only reads that folder and will not see sosc in {1}.'
    readonly_skip         = 'Skipping {0}.'
    none_found            = 'No mpv player was found (mpv, mpv.net or AnimeJaNai).'
    none_opt_winget       = '1) Install mpv.net with winget (winget install --id mpv.net -e)'
    none_opt_folder       = '2) Type the config folder myself'
    none_opt_prepare      = '3) Prepare the config in {0} for an mpv installed later'
    none_link             = 'Ways to get mpv: https://mpv.io/installation/'
    none_nowinget         = '   (winget is not available on this computer)'
    winget_confirm        = 'Run "winget install --id mpv.net -e" now? (it accepts the winget source and package agreements)'
    winget_failed         = 'winget finished with code {0}.'
    winget_error          = 'Could not run winget: {0}'
    yes_no_default_yes    = ' [Y/n] '
    yes_no_default_no     = ' [y/N] '
    backup_done           = 'Backup: {0}'
    backup_size           = 'Backing up {0} ({1} MB)...'
    backup_failed         = 'Could not back up {0}: {1}. Nothing was changed in that folder.'
    conflicts_found       = 'These scripts replace the mpv controls and clash with uosc:'
    conflicts_confirm     = 'Move them to {0}? Nothing is deleted.'
    conflicts_kept        = 'Left in place: uosc and that interface will both draw controls.'
    moved                 = 'Moved {0} -> {1}'
    downloading           = 'Downloading {0}...'
    hash_bad              = 'The download of {0} does not match its expected SHA256 (expected {1}, got {2}). Nothing was installed from it.'
    url_bad               = 'Refusing to download {0}: only HTTPS from GitHub is allowed.'
    release_unpublished   = 'sosc has no published release yet, so this installer cannot run on its own. Download the repository and run install\install.ps1 from that copy.'
    source_missing        = 'sosc files not found in {0}.'
    installing_to         = 'Installing sosc into {0}'
    uosc_done             = 'uosc {0} installed.'
    thumbfast_done        = 'thumbfast installed.'
    sosc_files_done       = 'sosc files copied ({0}).'
    kept_user_file        = '{0} already exists: kept (it holds your choice).'
    removed_stale         = 'Removed old sosc file {0}.'
    mpvpath_set           = 'thumbfast.conf: mpv_path={0}'
    block_updated         = '{0}: sosc block written.'
    default_section       = '{0} ends inside a [profile]: the sosc block starts with [default] so its options apply to every file.'
    key_taken             = '{0} is already bound in input.conf ({1}). sosc leaves it alone; bind another key to "{2}" if you want.'
    key_same              = '{0} already runs "{1}" in your input.conf: left as it is.'
    install_ok            = 'sosc installed in {0}.'
    target_failed         = '{0}: {1}'
    restore_hint          = 'Your previous config is in {0}.'
    summary               = 'Done: {0} of {1} folders.'
    restart               = 'Restart the player to see the changes.'
    uninstalling_from     = 'Removing sosc from {0}'
    ask_remove_uosc       = 'Remove uosc too?'
    ask_remove_thumbfast  = 'Remove thumbfast too?'
    ask_restore           = 'Move back the interfaces sosc set aside ({0})?'
    ask_delete_choices    = 'Delete your saved palette and subtitle choices (sosc-palette.conf, sosc-subs.conf)?'
    restore_skipped       = '{0} not moved back: {1} already exists.'
    conf_restored         = '{0}: your version from before sosc was put back.'
    conf_left             = '{0} was there before sosc and is left as it is now. Your earlier version is in {1}.'
    conf_unknown          = '{0} left in place (no installer record says who put it there).'
    includes_outside      = 'mpv.conf still includes {0} outside the sosc block: remove that line, or mpv will log an error at start-up.'
    uninstall_ok          = 'sosc removed from {0}.'
    nothing_to_uninstall  = 'sosc does not seem to be installed in any detected folder.'
    usage_yes_action      = '-Yes needs -Action install or -Action uninstall.'
    usage_many            = 'Several folders found; with -Yes, choose with -Target:'
    usage_none            = 'Nothing to work on.'
    error_generic         = 'Error: {0}'
    malformed_block       = '{0} has an incomplete or repeated sosc block (a start or end marker is missing). Fix it by hand and run the installer again.'
    outside_target        = 'Refusing to delete {0}: it is outside {1}.'
    old_ps                = 'Windows PowerShell 5.1 or newer is needed.'
    cancelled             = 'Cancelled.'
    link_skipped          = 'Not copied to the backup: {0} is a link (junction or symbolic link).'
    path_bad              = '{0} is not a valid folder path.'
    target_root           = 'Refusing {0}: a drive root or your user folder is not an mpv config folder.'
    not_mpv_folder        = '{0} does not look like an mpv config folder: no mpv.conf, input.conf, scripts or script-opts in it, and no mpv next to it.'
    not_mpv_confirm       = 'Use it anyway?'
    not_mpv_yes           = 'With -Yes such a folder is refused: run without -Yes to confirm it.'
    exe_folder            = '{0} is the folder of {1}, not its config folder.'
    exe_portable          = 'Using {0}, the portable_config next to it.'
    exe_offer             = 'Use {0}, the config folder that player reads?'
    mpv_home_note         = 'MPV_HOME is set: mpv reads its config from {0}, not from {1}.'
    admin_warn            = 'The installer is running as administrator. It does not need it, and what it creates may end up belonging to the administrator.'
    admin_confirm         = 'Continue as administrator?'
    admin_refused         = 'As administrator with -Yes, only folders under Program Files or ProgramData are allowed: {0}. Run it without administrator rights.'
    link_in_path          = 'Refusing to delete or move {0}: {1} is a link (junction or symbolic link) and the installer is running as administrator.'
    record_bad            = 'Ignored an invalid entry in sosc-installed.txt: {0}'
}

$script:SoscStringsEs = @{
    title                 = 'Instalador de sosc'
    menu                  = '1) Instalar o actualizar\n2) Desinstalar\n0) Salir'
    menu_prompt           = 'Elige una opci\u00f3n'
    invalid               = 'Opci\u00f3n no v\u00e1lida.'
    detecting             = 'Buscando reproductores de mpv...'
    found_header          = 'Reproductores y carpetas de configuraci\u00f3n encontrados:'
    found_header_uninst   = 'Carpetas con sosc:'
    cand_exe              = '     Reproductor: {0}'
    cand_config           = '     Configuraci\u00f3n: {0}'
    kind_folder           = 'carpeta de configuraci\u00f3n'
    tag_installed         = '[sosc {0} instalado]'
    tag_manual            = '[hay ficheros de sosc, sin registro del instalador]'
    tag_readonly          = '[sin permiso de escritura]'
    tag_new               = '[se crear\u00e1]'
    opt_other             = 'O) Otra carpeta'
    opt_quit              = '0) Salir'
    select_prompt         = 'Elige uno o varios separados por comas (p. ej. 1,3)'
    ask_folder            = 'Ruta completa de la carpeta de configuraci\u00f3n de mpv (donde est\u00e1 o ir\u00e1 mpv.conf)'
    folder_missing        = 'No existe la carpeta {0} ni la que la contiene.'
    readonly_warn         = 'No se puede escribir en {0}.'
    readonly_offer        = '\u00bfUsar {0} en su lugar?'
    readonly_portable     = 'Ojo: mientras exista {0}, este reproductor solo lee esa carpeta y no ver\u00e1 sosc en {1}.'
    readonly_skip         = 'Se omite {0}.'
    none_found            = 'No se ha encontrado ning\u00fan reproductor de mpv (mpv, mpv.net o AnimeJaNai).'
    none_opt_winget       = '1) Instalar mpv.net con winget (winget install --id mpv.net -e)'
    none_opt_folder       = '2) Escribir yo la carpeta de configuraci\u00f3n'
    none_opt_prepare      = '3) Dejar la configuraci\u00f3n preparada en {0} para un mpv que instale despu\u00e9s'
    none_link             = 'Formas de conseguir mpv: https://mpv.io/installation/'
    none_nowinget         = '   (winget no est\u00e1 disponible en este equipo)'
    winget_confirm        = '\u00bfEjecutar ahora "winget install --id mpv.net -e"? (acepta los acuerdos del origen y del paquete de winget)'
    winget_failed         = 'winget ha terminado con el c\u00f3digo {0}.'
    winget_error          = 'No se ha podido ejecutar winget: {0}'
    yes_no_default_yes    = ' [S/n] '
    yes_no_default_no     = ' [s/N] '
    backup_done           = 'Copia de seguridad: {0}'
    backup_size           = 'Copiando {0} ({1} MB)...'
    backup_failed         = 'No se ha podido hacer la copia de seguridad de {0}: {1}. No se ha cambiado nada en esa carpeta.'
    conflicts_found       = 'Estos scripts sustituyen los controles de mpv y chocan con uosc:'
    conflicts_confirm     = '\u00bfMoverlos a {0}? No se borra nada.'
    conflicts_kept        = 'Se quedan donde est\u00e1n: uosc y esa interfaz dibujar\u00e1n controles a la vez.'
    moved                 = 'Movido {0} -> {1}'
    downloading           = 'Descargando {0}...'
    hash_bad              = 'La descarga de {0} no coincide con su SHA256 esperado (esperado {1}, obtenido {2}). No se ha instalado nada de ella.'
    url_bad               = 'No se descarga {0}: solo se admite HTTPS desde GitHub.'
    release_unpublished   = 'sosc a\u00fan no tiene ninguna versi\u00f3n publicada, as\u00ed que este instalador no puede funcionar suelto. Descarga el repositorio y ejecuta install\\install.ps1 desde esa copia.'
    source_missing        = 'No se encuentran los ficheros de sosc en {0}.'
    installing_to         = 'Instalando sosc en {0}'
    uosc_done             = 'uosc {0} instalado.'
    thumbfast_done        = 'thumbfast instalado.'
    sosc_files_done       = 'Ficheros de sosc copiados ({0}).'
    kept_user_file        = '{0} ya existe: se conserva (guarda tu elecci\u00f3n).'
    removed_stale         = 'Borrado el fichero antiguo de sosc {0}.'
    mpvpath_set           = 'thumbfast.conf: mpv_path={0}'
    block_updated         = '{0}: bloque de sosc escrito.'
    default_section       = '{0} termina dentro de un [perfil]: el bloque de sosc empieza con [default] para que sus opciones valgan siempre.'
    key_taken             = '{0} ya est\u00e1 asignada en input.conf ({1}). sosc no la toca; si quieres, asigna otra tecla a "{2}".'
    key_same              = '{0} ya ejecuta "{1}" en tu input.conf: se deja como est\u00e1.'
    install_ok            = 'sosc instalado en {0}.'
    target_failed         = '{0}: {1}'
    restore_hint          = 'Tu configuraci\u00f3n anterior est\u00e1 en {0}.'
    summary               = 'Hecho: {0} de {1} carpetas.'
    restart               = 'Reinicia el reproductor para ver los cambios.'
    uninstalling_from     = 'Quitando sosc de {0}'
    ask_remove_uosc       = '\u00bfQuitar tambi\u00e9n uosc?'
    ask_remove_thumbfast  = '\u00bfQuitar tambi\u00e9n thumbfast?'
    ask_restore           = '\u00bfDevolver a su sitio las interfaces que sosc apart\u00f3 ({0})?'
    ask_delete_choices    = '\u00bfBorrar tus elecciones guardadas de paleta y subt\u00edtulos (sosc-palette.conf, sosc-subs.conf)?'
    restore_skipped       = '{0} no se devuelve: ya existe {1}.'
    conf_restored         = '{0}: se ha devuelto tu versi\u00f3n de antes de sosc.'
    conf_left             = '{0} ya exist\u00eda antes de sosc y se deja como est\u00e1 ahora. Tu versi\u00f3n anterior est\u00e1 en {1}.'
    conf_unknown          = '{0} se deja en su sitio (no hay registro del instalador que diga qui\u00e9n lo puso).'
    includes_outside      = 'mpv.conf sigue incluyendo {0} fuera del bloque de sosc: quita esa l\u00ednea o mpv dar\u00e1 un error al arrancar.'
    uninstall_ok          = 'sosc quitado de {0}.'
    nothing_to_uninstall  = 'No parece que sosc est\u00e9 instalado en ninguna de las carpetas encontradas.'
    usage_yes_action      = '-Yes necesita -Action install o -Action uninstall.'
    usage_many            = 'Hay varias carpetas; con -Yes, elige con -Target:'
    usage_none            = 'No hay nada sobre lo que trabajar.'
    error_generic         = 'Error: {0}'
    malformed_block       = '{0} tiene un bloque de sosc incompleto o repetido (falta una marca de inicio o de fin). Arr\u00e9glalo a mano y vuelve a ejecutar el instalador.'
    outside_target        = 'No se borra {0}: est\u00e1 fuera de {1}.'
    old_ps                = 'Hace falta Windows PowerShell 5.1 o posterior.'
    cancelled             = 'Cancelado.'
    link_skipped          = 'No se copia a la copia de seguridad: {0} es un enlace (uni\u00f3n o enlace simb\u00f3lico).'
    path_bad              = '{0} no es una ruta de carpeta v\u00e1lida.'
    target_root           = 'No se usa {0}: la ra\u00edz de una unidad o tu carpeta de usuario no son una carpeta de configuraci\u00f3n de mpv.'
    not_mpv_folder        = '{0} no parece una carpeta de configuraci\u00f3n de mpv: no tiene mpv.conf, input.conf, scripts ni script-opts, ni hay un mpv al lado.'
    not_mpv_confirm       = '\u00bfUsarla de todos modos?'
    not_mpv_yes           = 'Con -Yes se rechaza una carpeta as\u00ed: ejecuta sin -Yes para confirmarla.'
    exe_folder            = '{0} es la carpeta de {1}, no su carpeta de configuraci\u00f3n.'
    exe_portable          = 'Se usa {0}, la portable_config que tiene al lado.'
    exe_offer             = '\u00bfUsar {0}, la carpeta de configuraci\u00f3n que lee ese reproductor?'
    mpv_home_note         = 'MPV_HOME est\u00e1 definida: mpv lee su configuraci\u00f3n de {0}, no de {1}.'
    admin_warn            = 'El instalador se est\u00e1 ejecutando como administrador. No le hace falta, y lo que cree puede acabar perteneciendo al administrador.'
    admin_confirm         = '\u00bfSeguir como administrador?'
    admin_refused         = 'Como administrador y con -Yes solo se admiten carpetas dentro de Program Files o ProgramData: {0}. Ejec\u00fatalo sin permisos de administrador.'
    link_in_path          = 'No se borra ni se mueve {0}: {1} es un enlace (uni\u00f3n o enlace simb\u00f3lico) y el instalador se est\u00e1 ejecutando como administrador.'
    record_bad            = 'Se ignora una entrada no v\u00e1lida de sosc-installed.txt: {0}'
}

function Get-SoscLanguage {
    if ($env:SOSC_LANG -eq 'es' -or $env:SOSC_LANG -eq 'en') { return $env:SOSC_LANG }
    try {
        if ((Get-Culture).TwoLetterISOLanguageName -eq 'es') { return 'es' }
    }
    catch { }
    return 'en'
}

function Set-SoscLanguage {
    param([string]$Language)
    $script:SoscLang = $Language
    $script:SoscStrings = @{}
    if ($Language -eq 'es') {
        foreach ($key in $script:SoscStringsEs.Keys) {
            $script:SoscStrings[$key] = [regex]::Unescape($script:SoscStringsEs[$key])
        }
    }
    else {
        foreach ($key in $script:SoscStringsEn.Keys) {
            $script:SoscStrings[$key] = $script:SoscStringsEn[$key]
        }
    }
}

function T {
    param([string]$Key, [object[]]$FormatArgs = @())
    $text = $script:SoscStrings[$Key]
    if ($null -eq $text) { $text = $Key }
    if (@($FormatArgs).Count -gt 0) { return ($text -f $FormatArgs) }
    return $text
}

Set-SoscLanguage (Get-SoscLanguage)

# ---------------------------------------------------------------------------
# Output and input (replaceable in tests)
# ---------------------------------------------------------------------------

function Write-SoscInfo {
    param([string]$Message)
    if (-not $script:SoscQuiet) { Write-Host $Message }
}

function Write-SoscOk {
    param([string]$Message)
    if (-not $script:SoscQuiet) { Write-Host $Message -ForegroundColor Green }
}

function Write-SoscWarn {
    param([string]$Message)
    $script:SoscWarnings.Add($Message)
    if (-not $script:SoscQuiet) { Write-Host $Message -ForegroundColor Yellow }
}

function Write-SoscError {
    param([string]$Message)
    if (-not $script:SoscQuiet) { Write-Host $Message -ForegroundColor Red }
}

function Read-SoscLine {
    param([string]$Prompt)
    return (Read-Host -Prompt $Prompt)
}

function Confirm-Sosc {
    param([string]$Question, [bool]$Default)
    if ($script:NonInteractive) { return $Default }
    $suffix = T 'yes_no_default_no'
    if ($Default) { $suffix = T 'yes_no_default_yes' }
    while ($true) {
        $answer = Read-SoscLine ($Question + $suffix)
        if ($null -eq $answer) { return $Default }
        $answer = $answer.Trim().ToLowerInvariant()
        if ($answer -eq '') { return $Default }
        if (@('s', 'si', 'y', 'yes') -contains $answer -or $answer -eq ('s' + [char]0x00ED)) { return $true }
        if (@('n', 'no') -contains $answer) { return $false }
        Write-SoscWarn (T 'invalid')
    }
}

# ---------------------------------------------------------------------------
# Paths and files
# ---------------------------------------------------------------------------

function Join-SoscPath {
    param([string]$Base, [string[]]$Child)
    $result = $Base
    foreach ($part in $Child) { $result = [System.IO.Path]::Combine($result, $part) }
    return $result
}

function Get-SoscFullPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $trim = $full.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    if ($trim -eq '' -or $trim -match '^[A-Za-z]:$') { return $full }
    return $trim
}

function Test-SoscSamePath {
    param([string]$A, [string]$B)
    return [string]::Equals((Get-SoscFullPath $A), (Get-SoscFullPath $B), [System.StringComparison]::OrdinalIgnoreCase)
}

# True when $Path is strictly inside $Root (never $Root itself).
function Test-SoscInside {
    param([string]$Path, [string]$Root)
    if ([string]::IsNullOrEmpty($Path) -or [string]::IsNullOrEmpty($Root)) { return $false }
    $full = Get-SoscFullPath $Path
    $rootFull = (Get-SoscFullPath $Root).TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if ($full.Length -le $prefix.Length) { return $false }
    return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-SoscInside {
    param([string]$Path, [string]$Root)
    if (-not (Test-SoscInside -Path $Path -Root $Root)) {
        throw (T 'outside_target' @($Path, $Root))
    }
}

# True for junctions, symbolic links and other reparse points.
function Test-SoscLink {
    param($Item)
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

# Running as administrator, a link inside the config folder (scripts\ -> C:\Windows,
# say) would let a delete or move land outside it with full rights. So, only when
# elevated, every folder between $Root (excluded) and $Path (excluded: a link
# there is deleted or moved as a link) must be a real folder.
function Assert-SoscNoLink {
    param([string]$Path, [string]$Root)
    if (-not $script:SoscElevated) { return }
    $rootFull = Get-SoscFullPath $Root
    $p = Split-Path -Path (Get-SoscFullPath $Path) -Parent
    while ($p -and (Test-SoscInside -Path $p -Root $rootFull)) {
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and (Test-SoscLink $item)) { throw (T 'link_in_path' @($Path, $p)) }
        $p = Split-Path -Path $p -Parent
    }
}

# Deletes a file or folder inside $Root. Links (junctions, symlinks) are removed
# as links: their target is never followed.
function Remove-SoscItem {
    param([string]$Path, [string]$Root)
    Assert-SoscInside -Path $Path -Root $Root
    Assert-SoscNoLink -Path $Path -Root $Root
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $isLink = Test-SoscLink $item
    if ($item.PSIsContainer) {
        if ($isLink) {
            [System.IO.Directory]::Delete($item.FullName, $false)
            return
        }
        foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force)) {
            Remove-SoscItem -Path $child.FullName -Root $Root
        }
        $item.Attributes = [System.IO.FileAttributes]::Directory
        [System.IO.Directory]::Delete($item.FullName, $false)
    }
    else {
        if (-not $isLink) { $item.Attributes = [System.IO.FileAttributes]::Normal }
        [System.IO.File]::Delete($item.FullName)
    }
}

# Copies a folder tree. Links inside it are skipped (with a warning), never
# followed: a junction could point anywhere, even back up the tree.
function Copy-SoscTree {
    param([string]$From, [string]$To)
    if (-not (Test-Path -LiteralPath $To -PathType Container)) {
        New-Item -ItemType Directory -Path $To -Force | Out-Null
    }
    foreach ($child in @(Get-ChildItem -LiteralPath $From -Force)) {
        if (Test-SoscLink $child) { Write-SoscWarn (T 'link_skipped' @($child.FullName)); continue }
        $dest = Join-SoscPath $To $child.Name
        if ($child.PSIsContainer) {
            Copy-SoscTree -From $child.FullName -To $dest
        }
        else {
            Copy-Item -LiteralPath $child.FullName -Destination $dest -Force
        }
    }
}

# Size in bytes of a file or folder tree, without following links.
function Get-SoscTreeSize {
    param($Item)
    if (Test-SoscLink $Item) { return 0 }
    if (-not $Item.PSIsContainer) { return [long]$Item.Length }
    $total = [long]0
    foreach ($child in @(Get-ChildItem -LiteralPath $Item.FullName -Force -ErrorAction SilentlyContinue)) {
        $total += (Get-SoscTreeSize $child)
    }
    return $total
}

# A path typed by the user (or given with -Target): quotes stripped, %VARS%
# expanded and a relative path resolved against PowerShell's current folder (not
# the process one, which can differ). Throws when it is not a file system path.
function ConvertTo-SoscTypedPath {
    param([string]$Path)
    if ($null -eq $Path) { $Path = '' }
    $p = $Path.Trim().Trim('"').Trim("'").Trim()
    if ($p -eq '') { throw (T 'path_bad' @($Path)) }
    $p = [Environment]::ExpandEnvironmentVariables($p)
    $provider = $null
    $drive = $null
    try { $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p, [ref]$provider, [ref]$drive) }
    catch { throw (T 'path_bad' @($Path)) }
    if ($null -eq $provider -or $provider.Name -ne 'FileSystem') { throw (T 'path_bad' @($Path)) }
    return (Get-SoscFullPath $resolved)
}

function New-SoscDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Reads a text file keeping what is needed to write it back unchanged: UTF-8 (with
# or without BOM) or, when the bytes are not valid UTF-8, Latin-1, which maps
# every byte to one character and back, so nothing of the user's file is lost.
function Read-SoscText {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $offset = 0
    if ($bom) { $offset = 3 }
    $encoding = 'utf8'
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        $text = $strict.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        $encoding = 'latin1'
        $text = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes, $offset, $bytes.Length - $offset)
    }
    return [pscustomobject]@{ Text = $text; Encoding = $encoding; Bom = $bom }
}

# Writes text without BOM unless $Bom is set (only to keep a BOM the file already had).
function Write-SoscText {
    param([string]$Path, [string]$Text, [string]$Encoding = 'utf8', [bool]$Bom = $false)
    if ($Encoding -eq 'latin1') {
        $enc = [System.Text.Encoding]::GetEncoding(28591)
        $body = $enc.GetBytes($Text)
        if ($Bom) {
            $all = New-Object byte[] ($body.Length + 3)
            $all[0] = 0xEF; $all[1] = 0xBB; $all[2] = 0xBF
            [Array]::Copy($body, 0, $all, 3, $body.Length)
            $body = $all
        }
        [System.IO.File]::WriteAllBytes($Path, $body)
    }
    else {
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($Bom)))
    }
}

function Test-SoscDirWritable {
    param([string]$Path)
    $probe = $Path
    while ($probe -and -not (Test-Path -LiteralPath $probe -PathType Container)) {
        $parent = Split-Path -Path $probe -Parent
        if ($parent -eq $probe) { break }
        $probe = $parent
    }
    if (-not $probe -or -not (Test-Path -LiteralPath $probe -PathType Container)) { return $false }
    $file = Join-SoscPath $probe ('.sosc-write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($file, 'sosc')
        [System.IO.File]::Delete($file)
        return $true
    }
    catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

function Test-SoscAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
        return [bool]$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

# Everything detection needs from the machine, so tests can fake a Windows box.
function New-SoscEnvironment {
    return @{
        IsAdmin         = (Test-SoscAdmin)
        LocalAppData    = $env:LOCALAPPDATA
        AppData         = $env:APPDATA
        UserProfile     = $env:USERPROFILE
        ProgramFiles    = $env:ProgramFiles
        ProgramFilesX86 = ${env:ProgramFiles(x86)}
        ProgramData     = $env:ProgramData
        MpvHome         = $env:MPV_HOME
        FindCommand     = {
            param([string]$Name)
            $cmd = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmd) { return $cmd.Path }
            return $null
        }
        TestWritable    = { param([string]$Path) Test-SoscDirWritable $Path }
    }
}

function Get-SoscUserConfigDir {
    param([hashtable]$Env, [string]$Kind)
    if ($Kind -eq 'mpv') {
        if ($Env.MpvHome) { return $Env.MpvHome }
        if (-not $Env.AppData) { return $null }
        return (Join-SoscPath $Env.AppData 'mpv')
    }
    if (-not $Env.AppData) { return $null }
    return (Join-SoscPath $Env.AppData 'mpv.net')
}

function Get-SoscPlayerKind {
    param([string]$Exe)
    $name = [System.IO.Path]::GetFileName($Exe)
    if ($name -ieq 'mpvnet.exe') {
        if ($Exe -match '(?i)animejanai') { return 'AnimeJaNai' }
        return 'mpv.net'
    }
    return 'mpv'
}

# Scoop puts a small launcher in PATH (shims\mpv.exe) with a mpv.shim text file
# next to it that says where the real exe is.
function Resolve-SoscShim {
    param([string]$Exe)
    $shim = [System.IO.Path]::ChangeExtension($Exe, '.shim')
    if (Test-Path -LiteralPath $shim -PathType Leaf) {
        foreach ($line in [System.IO.File]::ReadAllLines($shim)) {
            if ($line -match '^\s*path\s*=\s*"?([^"]+?)"?\s*$') { return $Matches[1] }
        }
    }
    if ($Exe -match '(?i)[\\/]chocolatey[\\/]bin[\\/]') { return $null }
    return $Exe
}

function Get-SoscInstallState {
    param([string]$ConfigDir)
    $state = [pscustomobject]@{ Installed = $false; Version = ''; Manual = $false }
    if (-not $ConfigDir -or -not (Test-Path -LiteralPath $ConfigDir -PathType Container)) { return $state }
    $record = Read-SoscRecord $ConfigDir -NoWarn
    if ($null -ne $record) {
        $state.Installed = $true
        $state.Version = [string]$record.Values['sosc_version']
        return $state
    }
    $scripts = Join-SoscPath $ConfigDir 'scripts'
    if ((Test-Path -LiteralPath $scripts -PathType Container) -and
        @(Get-ChildItem -LiteralPath $scripts -Filter 'sosc-*.lua' -File -Force).Count -gt 0) {
        $state.Installed = $true
        $state.Manual = $true
    }
    return $state
}

function New-SoscCandidate {
    param([hashtable]$Env, [string]$Kind, [string]$Exe, [string]$ConfigDir, [bool]$Portable)
    $state = Get-SoscInstallState $ConfigDir
    $fallback = $null
    if ($Portable) { $fallback = Get-SoscUserConfigDir -Env $Env -Kind $Kind }
    return [pscustomobject]@{
        Kind             = $Kind
        Exe              = $Exe
        ConfigDir        = $ConfigDir
        Portable         = $Portable
        Exists           = (Test-Path -LiteralPath $ConfigDir -PathType Container)
        Writable         = [bool](& $Env.TestWritable $ConfigDir)
        Installed        = $state.Installed
        InstalledVersion = $state.Version
        Manual           = $state.Manual
        UserConfigDir    = $fallback
    }
}

# Finds mpv, mpv.net and AnimeJaNai, plus mpv config folders that exist without
# a player. Pure apart from the file system: everything else comes from $Env.
function Find-SoscPlayers {
    param([Parameter(Mandatory = $true)][hashtable]$Env)

    $exePaths = New-Object System.Collections.Generic.List[string]
    $addExe = {
        param([string]$Path)
        if ([string]::IsNullOrEmpty($Path)) { return }
        $exePaths.Add($Path)
    }

    if ($Env.LocalAppData) {
        & $addExe (Join-SoscPath $Env.LocalAppData @('Programs', 'mpv-AnimeJaNai', 'mpvnet.exe'))
        & $addExe (Join-SoscPath $Env.LocalAppData @('Programs', 'mpv.net', 'mpvnet.exe'))
    }
    foreach ($pf in @($Env.ProgramFiles, $Env.ProgramFilesX86)) {
        if ($pf) {
            & $addExe (Join-SoscPath $pf @('mpv.net', 'mpvnet.exe'))
        }
    }
    if ($Env.UserProfile) {
        & $addExe (Join-SoscPath $Env.UserProfile @('scoop', 'apps', 'mpv.net', 'current', 'mpvnet.exe'))
    }
    $found = & $Env.FindCommand 'mpvnet.exe'
    if ($found) { & $addExe (Resolve-SoscShim $found) }

    $found = & $Env.FindCommand 'mpv.exe'
    if ($found) { & $addExe (Resolve-SoscShim $found) }
    if ($Env.UserProfile) {
        & $addExe (Join-SoscPath $Env.UserProfile @('scoop', 'apps', 'mpv', 'current', 'mpv.exe'))
        & $addExe (Join-SoscPath $Env.UserProfile @('scoop', 'apps', 'mpv-git', 'current', 'mpv.exe'))
    }
    foreach ($pf in @($Env.ProgramFiles, $Env.ProgramFilesX86)) {
        if ($pf) {
            & $addExe (Join-SoscPath $pf @('mpv', 'mpv.exe'))
            & $addExe (Join-SoscPath $pf @('MPV Player', 'mpv.exe'))
        }
    }
    if ($Env.ProgramData) {
        $chocoLib = Join-SoscPath $Env.ProgramData @('chocolatey', 'lib')
        if (Test-Path -LiteralPath $chocoLib -PathType Container) {
            foreach ($pkg in @(Get-ChildItem -LiteralPath $chocoLib -Directory -Filter 'mpv*' -Force)) {
                foreach ($exe in @(Get-ChildItem -LiteralPath $pkg.FullName -Recurse -Depth 3 -File -Filter 'mpv.exe' -Force -ErrorAction SilentlyContinue)) {
                    & $addExe $exe.FullName
                }
            }
        }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    $seenExe = New-Object System.Collections.Generic.List[string]
    $seenConfig = New-Object System.Collections.Generic.List[string]
    $isSeen = {
        param($List, [string]$Path)
        foreach ($p in $List) { if (Test-SoscSamePath $p $Path) { return $true } }
        return $false
    }

    foreach ($exe in $exePaths) {
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
        $exeFull = Get-SoscFullPath $exe
        if (& $isSeen $seenExe $exeFull) { continue }
        $seenExe.Add($exeFull)
        $kind = Get-SoscPlayerKind $exeFull
        $portableDir = Join-SoscPath (Split-Path -Path $exeFull -Parent) 'portable_config'
        # mpv itself gives MPV_HOME priority over portable_config. mpv.net (and
        # AnimeJaNai) set their own config-dir, which beats both, so for them
        # MPV_HOME does not matter.
        $portable = (Test-Path -LiteralPath $portableDir -PathType Container) -and -not ($kind -eq 'mpv' -and $Env.MpvHome)
        if ($portable) { $config = $portableDir } else { $config = Get-SoscUserConfigDir -Env $Env -Kind $kind }
        if (-not $config) { continue }
        $config = Get-SoscFullPath $config
        if (& $isSeen $seenConfig $config) { continue }
        $seenConfig.Add($config)
        $candidates.Add((New-SoscCandidate -Env $Env -Kind $kind -Exe $exeFull -ConfigDir $config -Portable $portable))
    }

    foreach ($kind in @('mpv', 'mpv.net')) {
        $config = Get-SoscUserConfigDir -Env $Env -Kind $kind
        if (-not $config -or -not (Test-Path -LiteralPath $config -PathType Container)) { continue }
        $config = Get-SoscFullPath $config
        if (& $isSeen $seenConfig $config) { continue }
        $seenConfig.Add($config)
        $candidates.Add((New-SoscCandidate -Env $Env -Kind 'folder' -Exe '' -ConfigDir $config -Portable $false))
    }

    return $candidates.ToArray()
}

# A folder typed by the user (or given with -Target): reuse the detected entry
# when it is one, otherwise guess the player from an exe next to it. A folder
# that holds the player itself is not a config folder: its portable_config is
# used, or the user folder that player reads is offered. Returns $null when the
# user turns that down.
function Resolve-SoscManualTarget {
    param([hashtable]$Env, [string]$Path, [object[]]$Candidates)
    $full = ConvertTo-SoscTypedPath $Path
    foreach ($c in $Candidates) {
        if (Test-SoscSamePath $c.ConfigDir $full) { return $c }
    }

    foreach ($name in $script:PlayerExes) {
        $probe = Join-SoscPath $full $name
        if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { continue }
        $kind = Get-SoscPlayerKind $probe
        Write-SoscWarn (T 'exe_folder' @($full, $name))
        $portableDir = Join-SoscPath $full 'portable_config'
        if ((Test-Path -LiteralPath $portableDir -PathType Container) -and -not ($kind -eq 'mpv' -and $Env.MpvHome)) {
            Write-SoscInfo (T 'exe_portable' @($portableDir))
            return (Resolve-SoscManualTarget -Env $Env -Path $portableDir -Candidates $Candidates)
        }
        $user = Get-SoscUserConfigDir -Env $Env -Kind $kind
        if (-not $user) { return $null }
        $user = Get-SoscFullPath $user
        if (-not (Confirm-Sosc -Question (T 'exe_offer' @($user)) -Default $true)) { return $null }
        foreach ($c in $Candidates) {
            if (Test-SoscSamePath $c.ConfigDir $user) { return $c }
        }
        return (New-SoscCandidate -Env $Env -Kind $kind -Exe $probe -ConfigDir $user -Portable $false)
    }

    $kind = 'folder'
    $exe = ''
    $portable = $false
    if ((Split-Path -Path $full -Leaf) -ieq 'portable_config') {
        $parent = Split-Path -Path $full -Parent
        foreach ($name in $script:PlayerExes) {
            $probe = Join-SoscPath $parent $name
            if (Test-Path -LiteralPath $probe -PathType Leaf) {
                $exe = $probe
                $kind = Get-SoscPlayerKind $probe
                $portable = $true
                if ($kind -eq 'mpv' -and $Env.MpvHome) { Write-SoscWarn (T 'mpv_home_note' @($Env.MpvHome, $full)) }
                break
            }
        }
    }
    return (New-SoscCandidate -Env $Env -Kind $kind -Exe $exe -ConfigDir $full -Portable $portable)
}

# A drive root (C:\, \\server\share, /) or the bare user profile is never a
# config folder: backing it up or writing scripts\ there makes no sense.
function Test-SoscForbiddenTarget {
    param([hashtable]$Env, [string]$Path)
    $full = Get-SoscFullPath $Path
    $seps = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($null -eq $root -or $full.TrimEnd($seps) -eq $root.TrimEnd($seps)) { return $true }
    if ($Env.UserProfile -and (Test-SoscSamePath $full $Env.UserProfile)) { return $true }
    return $false
}

# False only for a folder that exists, is not empty and shows no sign of mpv.
function Test-SoscLooksLikeMpvConfig {
    param([hashtable]$Env, $Candidate)
    $dir = Get-SoscFullPath $Candidate.ConfigDir
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $true }
    if (@(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) { return $true }
    if ($Candidate.Exe) { return $true }
    foreach ($n in $script:MpvConfigFiles) { if (Test-Path -LiteralPath (Join-SoscPath $dir $n) -PathType Leaf) { return $true } }
    foreach ($n in $script:MpvConfigDirs) { if (Test-Path -LiteralPath (Join-SoscPath $dir $n) -PathType Container) { return $true } }
    foreach ($kind in @('mpv', 'mpv.net')) {
        $user = Get-SoscUserConfigDir -Env $Env -Kind $kind
        if ($user -and (Test-SoscSamePath $user $dir)) { return $true }
    }
    $parent = Split-Path -Path $dir -Parent
    foreach ($d in @($dir, $parent)) {
        if (-not $d) { continue }
        foreach ($n in $script:PlayerExes) { if (Test-Path -LiteralPath (Join-SoscPath $d $n) -PathType Leaf) { return $true } }
    }
    return $false
}

# "1,3" / "o" / "0" -> what the user picked. Returns $null when the text is not valid.
function ConvertFrom-SoscSelection {
    param([string]$Text, [int]$Count)
    $result = [pscustomobject]@{ Indexes = @(); Other = $false; Quit = $false }
    if ($null -eq $Text) { return $null }
    $parts = @($Text -split '[,;\s]+' | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) { return $null }
    $indexes = New-Object System.Collections.Generic.List[int]
    foreach ($part in $parts) {
        $p = $part.ToLowerInvariant()
        if ($p -eq '0' -or $p -eq 'q' -or $p -eq 'x') { $result.Quit = $true; continue }
        if ($p -eq 'o') { $result.Other = $true; continue }
        $n = 0
        if (-not [int]::TryParse($p, [ref]$n)) { return $null }
        if ($n -lt 1 -or $n -gt $Count) { return $null }
        if (-not $indexes.Contains($n - 1)) { $indexes.Add($n - 1) }
    }
    $result.Indexes = $indexes.ToArray()
    return $result
}

# ---------------------------------------------------------------------------
# Managed blocks in mpv.conf / input.conf
# ---------------------------------------------------------------------------

# Splits text into lines, keeping each line's own terminator and offset.
function Split-SoscLines {
    param([string]$Text)
    $lines = New-Object System.Collections.Generic.List[object]
    $pos = 0
    $length = $Text.Length
    while ($pos -lt $length) {
        $nl = $Text.IndexOf("`n", $pos)
        if ($nl -lt 0) {
            $lines.Add([pscustomobject]@{ Start = $pos; Content = $Text.Substring($pos); Eol = '' })
            break
        }
        $end = $nl
        $eol = "`n"
        if ($nl -gt $pos -and $Text[$nl - 1] -eq "`r") { $end = $nl - 1; $eol = "`r`n" }
        $lines.Add([pscustomobject]@{ Start = $pos; Content = $Text.Substring($pos, $end - $pos); Eol = $eol })
        $pos = $nl + 1
    }
    return $lines.ToArray()
}

function Get-SoscEol {
    param([string]$Text)
    if ($Text.Contains("`r`n")) { return "`r`n" }
    if ($Text.Contains("`n")) { return "`n" }
    return "`r`n"
}

# Returns $null when there is no block, or the index of its first and last line.
# Throws when the markers do not pair up.
function Find-SoscBlock {
    param([object[]]$Lines, [string]$Name = 'file')
    $begin = -1
    $end = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $content = $Lines[$i].Content.Trim()
        if ($content -eq $script:BlockBegin) {
            if ($begin -ge 0) { throw (T 'malformed_block' @($Name)) }
            $begin = $i
        }
        elseif ($content -eq $script:BlockEnd) {
            if ($begin -lt 0 -or $end -ge 0) { throw (T 'malformed_block' @($Name)) }
            $end = $i
        }
    }
    if ($begin -ge 0 -and $end -lt 0) { throw (T 'malformed_block' @($Name)) }
    if ($begin -lt 0) { return $null }
    return [pscustomobject]@{ Begin = $begin; End = $end }
}

# Puts the block (marker lines added here) in place of the old one, or at the end.
function Set-SoscBlockText {
    param([string]$Text, [string[]]$BlockLines, [string]$Name = 'file', [string]$Eol = '')
    if ($null -eq $Text) { $Text = '' }
    $eol = $Eol
    if (-not $eol) { $eol = Get-SoscEol $Text }
    $all = @($script:BlockBegin) + @($BlockLines) + @($script:BlockEnd)
    $body = [string]::Join($eol, $all)
    $lines = @(Split-SoscLines $Text)
    $block = Find-SoscBlock -Lines $lines -Name $Name
    if ($null -ne $block) {
        $first = $lines[$block.Begin]
        $last = $lines[$block.End]
        $after = $last.Start + $last.Content.Length
        return $Text.Substring(0, $first.Start) + $body + $Text.Substring($after)
    }
    $prefix = $Text
    if ($prefix.Length -gt 0 -and -not $prefix.EndsWith("`n")) { $prefix += $eol }
    return $prefix + $body + $eol
}

function Remove-SoscBlockText {
    param([string]$Text, [string]$Name = 'file')
    if ($null -eq $Text) { return '' }
    $lines = @(Split-SoscLines $Text)
    $block = Find-SoscBlock -Lines $lines -Name $Name
    if ($null -eq $block) { return $Text }
    $first = $lines[$block.Begin]
    $last = $lines[$block.End]
    $after = $last.Start + $last.Content.Length + $last.Eol.Length
    return $Text.Substring(0, $first.Start) + $Text.Substring($after)
}

# Lines of the file that are not part of the sosc block.
function Get-SoscOutsideLines {
    param([string]$Text, [string]$Name = 'file')
    $lines = @(Split-SoscLines $Text)
    $block = Find-SoscBlock -Lines $lines -Name $Name
    $out = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($null -ne $block -and $i -ge $block.Begin -and $i -le $block.End) { continue }
        $out.Add([pscustomobject]@{ Index = $i; Content = $lines[$i].Content; BeforeBlock = ($null -eq $block -or $i -lt $block.Begin) })
    }
    return $out.ToArray()
}

# Profile name of an mpv.conf line, or $null when the line is not a profile
# header. Same rules as mpv's parser: leading blanks skipped, the name is what
# lies between '[' and the first ']' (not trimmed), and after it only blanks
# and a '#' comment may follow.
function Get-SoscProfileHeader {
    param([string]$Line)
    $m = [regex]::Match($Line.TrimStart(), '^\[([^\]]*)\]\s*(#.*)?$')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}

# Block for mpv.conf, which always goes at the end of the file (so its include of
# sosc-subs.conf comes after the user's own sub-* lines). If the file ends inside
# a [profile], the block opens with [default] so its options are top-level: mpv
# applies whatever follows a [name] header to that profile only. mpv compares
# names exactly: [DEFAULT] is another profile, and an empty [] means default.
function Get-SoscMpvConfBlock {
    param([string]$Text)
    $lastHeader = $null
    foreach ($line in @(Get-SoscOutsideLines -Text $Text -Name 'mpv.conf')) {
        $h = Get-SoscProfileHeader $line.Content
        if ($null -ne $h) { $lastHeader = $h }
    }
    $needsDefault = ($null -ne $lastHeader -and $lastHeader -cne 'default' -and $lastHeader -ne '')
    $lines = @()
    if ($needsDefault) { $lines += '[default]' }
    $lines += $script:MpvConfLines
    return [pscustomobject]@{ Lines = $lines; NeedsDefault = $needsDefault }
}

function ConvertTo-SoscKeyName {
    param([string]$Key)
    $parts = @($Key -split '\+')
    if ($Key.EndsWith('++')) { $parts = @($Key.Substring(0, $Key.Length - 2) -split '\+') + @('+') }
    $parts = @($parts | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) { return $Key }
    $last = $parts[$parts.Count - 1]
    if ($last.Length -gt 1) { $last = $last.ToLowerInvariant() }
    $mods = @()
    if ($parts.Count -gt 1) { $mods = @($parts[0..($parts.Count - 2)] | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object) }
    return [string]::Join('+', @($mods + @($last)))
}

# Decides which sosc bindings go in the block. A key the user already bound
# outside the block is left alone (and reported); same key and same command is
# simply not repeated.
function Get-SoscInputBlock {
    param([string]$Text)
    # Case-sensitive: in mpv, Alt+p and Alt+P (with Shift) are different keys.
    $bound = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
    foreach ($line in @(Get-SoscOutsideLines -Text $Text -Name 'input.conf')) {
        $c = $line.Content.Trim()
        if ($c -eq '' -or $c.StartsWith('#')) { continue }
        $m = [regex]::Match($c, '^(\S+)\s*(.*)$')
        if (-not $m.Success) { continue }
        $key = ConvertTo-SoscKeyName $m.Groups[1].Value
        $command = ($m.Groups[2].Value -replace '\s+', ' ').Trim()
        $bound[$key] = $command
    }
    $lines = @()
    $taken = @()
    $same = @()
    foreach ($b in $script:InputBindings) {
        $norm = ConvertTo-SoscKeyName $b.Key
        if ($bound.ContainsKey($norm)) {
            $existing = $bound[$norm]
            if ($existing -eq $b.Command -or $existing.StartsWith($b.Command + ' ') -or $existing.StartsWith($b.Command + '#')) {
                $same += [pscustomobject]@{ Key = $b.Key; Command = $b.Command; Existing = $existing }
            }
            else {
                $taken += [pscustomobject]@{ Key = $b.Key; Command = $b.Command; Existing = $existing }
            }
            continue
        }
        $lines += ($b.Key + '  ' + $b.Command)
    }
    return [pscustomobject]@{ Lines = $lines; Taken = $taken; Same = $same }
}

# Writes the block into a file (created when missing), keeping its encoding,
# BOM and line endings. Returns whether the file existed.
function Update-SoscManagedFile {
    param([string]$Path, [string]$Kind)
    $existed = Test-Path -LiteralPath $Path -PathType Leaf
    $name = [System.IO.Path]::GetFileName($Path)
    if ($existed) { $file = Read-SoscText $Path }
    else { $file = [pscustomobject]@{ Text = ''; Encoding = 'utf8'; Bom = $false } }

    if ($Kind -eq 'mpv') {
        # The block is taken out of wherever it is and added again at the end.
        $without = Remove-SoscBlockText -Text $file.Text -Name $name
        $block = Get-SoscMpvConfBlock $without
        if ($block.NeedsDefault) { Write-SoscInfo (T 'default_section' @($name)) }
        $newText = Set-SoscBlockText -Text $without -BlockLines $block.Lines -Name $name -Eol (Get-SoscEol $file.Text)
    }
    else {
        # input.conf: the block stays where it is (order does not matter there).
        $block = Get-SoscInputBlock $file.Text
        foreach ($t in $block.Taken) { Write-SoscWarn (T 'key_taken' @($t.Key, $t.Existing, $t.Command)) }
        foreach ($s in $block.Same) { Write-SoscInfo (T 'key_same' @($s.Key, $s.Command)) }
        $newText = Set-SoscBlockText -Text $file.Text -BlockLines $block.Lines -Name $name
    }
    if (-not $existed -or $newText -ne $file.Text) {
        Write-SoscText -Path $Path -Text $newText -Encoding $file.Encoding -Bom $file.Bom
    }
    Write-SoscInfo (T 'block_updated' @($name))
    return $existed
}

# Removes the block. A file that only held the block and was created by sosc is deleted.
function Remove-SoscManagedFile {
    param([string]$Path, [string]$Root, [bool]$CreatedBySosc)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $name = [System.IO.Path]::GetFileName($Path)
    $file = Read-SoscText $Path
    $newText = Remove-SoscBlockText -Text $file.Text -Name $name
    if ($newText -eq $file.Text) { return }
    if ($CreatedBySosc -and $newText.Trim() -eq '') {
        Remove-SoscItem -Path $Path -Root $Root
        return
    }
    Write-SoscText -Path $Path -Text $newText -Encoding $file.Encoding -Bom $file.Bom
}

# Sets key=value in a script-opts file, replacing an existing line for that key.
function Set-SoscConfOption {
    param([string]$Path, [string]$Key, [string]$Value, [string]$Comment = '')
    if (Test-Path -LiteralPath $Path -PathType Leaf) { $file = Read-SoscText $Path }
    else { $file = [pscustomobject]@{ Text = ''; Encoding = 'utf8'; Bom = $false } }
    $text = $file.Text
    $eol = Get-SoscEol $text
    $lines = @(Split-SoscLines $text)
    $newLine = $Key + '=' + $Value
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i].Content -match $pattern) {
            $l = $lines[$i]
            $text = $text.Substring(0, $l.Start) + $newLine + $text.Substring($l.Start + $l.Content.Length)
            Write-SoscText -Path $Path -Text $text -Encoding $file.Encoding -Bom $file.Bom
            return
        }
    }
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += $eol }
    if ($Comment) {
        if ($text.Length -gt 0) { $text += $eol }
        $text += '# ' + $Comment + $eol
    }
    $text += $newLine + $eol
    Write-SoscText -Path $Path -Text $text -Encoding $file.Encoding -Bom $file.Bom
}

# ---------------------------------------------------------------------------
# Installer record (sosc-installed.txt)
# ---------------------------------------------------------------------------

# The record can be edited by anyone, so its paths are checked before use: they
# must be relative, '/'-separated, with no '..', '.', empty segment, drive,
# backslash or characters Windows does not allow, and no segment ending in a dot
# or a space (Windows drops those, so "..." could act as "..").
function Test-SoscRecordPath {
    param([string]$Rel)
    if ([string]::IsNullOrEmpty($Rel)) { return $false }
    if ($Rel -match '[\\:*?"<>|\x00-\x1f]') { return $false }
    foreach ($seg in ($Rel -split '/')) {
        if ($seg -eq '' -or $seg -match '^\.+$' -or $seg -match '[. ]$') { return $false }
    }
    return $true
}

function Read-SoscRecord {
    param([string]$ConfigDir, [switch]$NoWarn)
    $path = Join-SoscPath $ConfigDir $script:RecordName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $values = @{}
    $files = New-Object System.Collections.Generic.List[string]
    $disabled = New-Object System.Collections.Generic.List[string]
    foreach ($line in ((Read-SoscText $path).Text -split "`r?`n")) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $idx = $line.IndexOf('=')
        $key = $line.Substring(0, $idx).Trim()
        $value = $line.Substring($idx + 1).Trim()
        if ($key -eq 'file') {
            if (Test-SoscRecordPath $value) { $files.Add($value) }
            elseif (-not $NoWarn) { Write-SoscWarn (T 'record_bad' @($line)) }
        }
        elseif ($key -eq 'disabled') {
            $pair = $value -split '\|'
            if ($pair.Count -eq 2 -and (Test-SoscRecordPath $pair[0]) -and (Test-SoscRecordPath $pair[1])) { $disabled.Add($value) }
            elseif (-not $NoWarn) { Write-SoscWarn (T 'record_bad' @($line)) }
        }
        else { $values[$key] = $value }
    }
    return [pscustomobject]@{ Values = $values; Files = $files.ToArray(); Disabled = $disabled.ToArray() }
}

function Write-SoscRecord {
    param([string]$ConfigDir, [System.Collections.Specialized.OrderedDictionary]$Values, [string[]]$Files, [string[]]$Disabled)
    $eol = "`r`n"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('# Written by the sosc installer (install/install.ps1). Used to update and uninstall; do not edit.' + $eol)
    foreach ($key in $Values.Keys) { [void]$sb.Append($key + '=' + $Values[$key] + $eol) }
    foreach ($d in $Disabled) { [void]$sb.Append('disabled=' + $d + $eol) }
    foreach ($f in $Files) { [void]$sb.Append('file=' + $f + $eol) }
    Write-SoscText -Path (Join-SoscPath $ConfigDir $script:RecordName) -Text $sb.ToString()
}

function ConvertTo-SoscYesNo { param([bool]$Value) if ($Value) { return 'yes' } return 'no' }

# ---------------------------------------------------------------------------
# Sources and downloads
# ---------------------------------------------------------------------------

function Get-SoscRepoCommit {
    param([string]$RepoRoot)
    try {
        $gitDir = Join-SoscPath $RepoRoot '.git'
        $head = Join-SoscPath $gitDir 'HEAD'
        if (-not (Test-Path -LiteralPath $head -PathType Leaf)) { return '' }
        $ref = ([System.IO.File]::ReadAllText($head)).Trim()
        if ($ref -notmatch '^ref:\s*(.+)$') { return $ref }
        $refName = $Matches[1].Trim()
        $refFile = Join-SoscPath $gitDir ($refName -split '/')
        if (Test-Path -LiteralPath $refFile -PathType Leaf) { return ([System.IO.File]::ReadAllText($refFile)).Trim() }
        $packed = Join-SoscPath $gitDir 'packed-refs'
        if (Test-Path -LiteralPath $packed -PathType Leaf) {
            foreach ($line in [System.IO.File]::ReadAllLines($packed)) {
                if ($line -match ('^([0-9a-f]{40}) ' + [regex]::Escape($refName) + '$')) { return $Matches[1] }
            }
        }
    }
    catch { }
    return ''
}

function Assert-SoscDownloadUrl {
    param([string]$Url)
    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or $script:AllowedHosts -notcontains $uri.Host.ToLowerInvariant()) {
        throw (T 'url_bad' @($Url))
    }
}

function Get-SoscFileSha256 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $hash = $sha.ComputeHash($stream)
    }
    finally {
        $stream.Dispose()
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

# Downloads $Url to $OutFile and checks its SHA256. On mismatch the file is
# deleted and an error is thrown, so nothing unverified is ever used.
function Invoke-SoscVerifiedDownload {
    param([string]$Url, [string]$Sha256, [string]$OutFile)
    Assert-SoscDownloadUrl $Url
    if ([string]::IsNullOrEmpty($Sha256)) { throw (T 'hash_bad' @($Url, '?', '?')) }
    Write-SoscInfo (T 'downloading' @($Url))
    # Anything the downloader prints must not end up in the caller's return value.
    & $script:SoscDownloader $Url $OutFile | Out-Null
    if (-not (Test-Path -LiteralPath $OutFile -PathType Leaf)) { throw (T 'hash_bad' @($Url, $Sha256, '-')) }
    $actual = Get-SoscFileSha256 $OutFile
    if ($actual -ne $Sha256.ToLowerInvariant()) {
        [System.IO.File]::Delete($OutFile)
        throw (T 'hash_bad' @($Url, $Sha256.ToLowerInvariant(), $actual))
    }
}

function Expand-SoscZip {
    param([string]$Zip, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-SoscDirectory $Destination
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Destination)
}

function New-SoscTempDir {
    $dir = Join-SoscPath ([System.IO.Path]::GetTempPath()) ('sosc-install-' + [guid]::NewGuid().ToString('N'))
    New-SoscDirectory $dir
    return $dir
}

# Where the sosc files come from: the portable_config of the repository copy the
# script sits in, or (once published) a verified release zip.
function Get-SoscSource {
    param([string]$TempDir)
    if ($script:SoscScriptRoot) {
        $repo = Split-Path -Path $script:SoscScriptRoot -Parent
        $config = Join-SoscPath $repo 'portable_config'
        if (Test-Path -LiteralPath (Join-SoscPath $config @('scripts', 'sosc-palettes.lua')) -PathType Leaf) {
            $commit = Get-SoscRepoCommit $repo
            return [pscustomobject]@{ ConfigDir = $config; Version = $script:SoscVersion; Commit = $commit }
        }
    }
    return (Get-SoscReleaseSource -TempDir $TempDir)
}

function Get-SoscReleaseSource {
    param([string]$TempDir)
    if ([string]::IsNullOrEmpty($script:SoscReleaseUrl)) { throw (T 'release_unpublished') }
    $zip = Join-SoscPath $TempDir 'sosc.zip'
    Invoke-SoscVerifiedDownload -Url $script:SoscReleaseUrl -Sha256 $script:SoscReleaseSha256 -OutFile $zip
    $dest = Join-SoscPath $TempDir 'sosc'
    Expand-SoscZip -Zip $zip -Destination $dest
    foreach ($dir in @($dest) + @(Get-ChildItem -LiteralPath $dest -Directory -Force | ForEach-Object { $_.FullName })) {
        $config = Join-SoscPath $dir 'portable_config'
        if (Test-Path -LiteralPath (Join-SoscPath $config @('scripts', 'sosc-palettes.lua')) -PathType Leaf) {
            return [pscustomobject]@{ ConfigDir = $config; Version = $script:SoscVersion; Commit = '' }
        }
    }
    throw (T 'source_missing' @($dest))
}

# Downloads and verifies uosc and thumbfast once for every target.
function Get-SoscArtifacts {
    param([string]$TempDir)
    $zip = Join-SoscPath $TempDir 'uosc.zip'
    Invoke-SoscVerifiedDownload -Url $script:UoscUrl -Sha256 $script:UoscSha256 -OutFile $zip
    $uoscDir = Join-SoscPath $TempDir 'uosc'
    Expand-SoscZip -Zip $zip -Destination $uoscDir
    if (-not (Test-Path -LiteralPath (Join-SoscPath $uoscDir @('scripts', 'uosc', 'main.lua')) -PathType Leaf)) {
        throw (T 'source_missing' @($script:UoscUrl))
    }
    $thumb = Join-SoscPath $TempDir 'thumbfast.lua'
    Invoke-SoscVerifiedDownload -Url $script:ThumbfastUrl -Sha256 $script:ThumbfastSha256 -OutFile $thumb
    return [pscustomobject]@{ UoscDir = $uoscDir; ThumbfastFile = $thumb }
}

# ---------------------------------------------------------------------------
# Install steps
# ---------------------------------------------------------------------------

# Copies what the installer may change ($script:BackupItems) to
# <config>-respaldo-sosc-<stamp>, next to it. Links are skipped, not followed.
# Returns '' when there is nothing to copy. A copy that fails half-way is deleted.
function New-SoscBackup {
    param([string]$ConfigDir, [string]$Stamp = '')
    if (-not $Stamp) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }
    $full = Get-SoscFullPath $ConfigDir
    $parent = Split-Path -Path $full -Parent
    if (-not $parent) { throw (T 'target_root' @($full)) }
    $items = @()
    foreach ($name in $script:BackupItems) {
        $p = Join-SoscPath $full $name
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        if (Test-SoscLink $item) { Write-SoscWarn (T 'link_skipped' @($item.FullName)); continue }
        $items += $item
    }
    if ($items.Count -eq 0) { return '' }

    $base = $full + '-respaldo-sosc-' + $Stamp
    $backup = $base
    $n = 2
    while (Test-Path -LiteralPath $backup) { $backup = $base + '-' + $n; $n++ }
    $bytes = [long]0
    foreach ($item in $items) { $bytes += (Get-SoscTreeSize $item) }
    Write-SoscInfo (T 'backup_size' @($full, [math]::Round($bytes / 1MB, 1)))
    New-SoscDirectory $backup
    try {
        foreach ($item in $items) {
            $dest = Join-SoscPath $backup $item.Name
            if ($item.PSIsContainer) { Copy-SoscTree -From $item.FullName -To $dest }
            else { Copy-Item -LiteralPath $item.FullName -Destination $dest -Force }
        }
    }
    catch {
        $failure = $_
        try { Remove-SoscItem -Path $backup -Root $parent } catch { }
        throw $failure
    }
    return $backup
}

function Get-SoscRelativePath {
    param([string]$Path, [string]$Root)
    $full = Get-SoscFullPath $Path
    $rootFull = Get-SoscFullPath $Root
    return $full.Substring($rootFull.Length).TrimStart([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)).Replace('\', '/')
}

function Find-SoscConflicts {
    param([string]$ConfigDir)
    $found = New-Object System.Collections.Generic.List[string]
    $scripts = Join-SoscPath $ConfigDir 'scripts'
    if (-not (Test-Path -LiteralPath $scripts -PathType Container)) { return $found.ToArray() }
    foreach ($item in @(Get-ChildItem -LiteralPath $scripts -File -Force)) {
        foreach ($pattern in $script:ConflictPatterns) {
            if ($item.Name -like $pattern) { $found.Add($item.FullName); break }
        }
    }
    $names = @($found | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) })
    $opts = Join-SoscPath $ConfigDir 'script-opts'
    foreach ($n in $names) {
        $conf = Join-SoscPath $opts ($n + '.conf')
        if (Test-Path -LiteralPath $conf -PathType Leaf) { $found.Add($conf) }
    }
    $fonts = Join-SoscPath $ConfigDir 'fonts'
    if ($names.Count -gt 0 -and (Test-Path -LiteralPath $fonts -PathType Container)) {
        foreach ($item in @(Get-ChildItem -LiteralPath $fonts -File -Force)) {
            foreach ($pattern in $script:ConflictFontPatterns) {
                $prefix = $pattern.TrimEnd('*')
                $owned = @($names | Where-Object { $_ -like $pattern -or $_ -like ($prefix + '*') })
                if ($item.Name -like $pattern -and $owned.Count -gt 0) { $found.Add($item.FullName); break }
            }
        }
    }
    return $found.ToArray()
}

# Moves a file or folder of the config into scripts-desactivados, keeping its
# sub-folder (scripts/, script-opts/, fonts/). Returns "moved|original" (relative).
function Move-SoscToDisabled {
    param([string]$Path, [string]$ConfigDir, [string]$Stamp)
    Assert-SoscInside -Path $Path -Root $ConfigDir
    $rel = Get-SoscRelativePath -Path $Path -Root $ConfigDir
    $sub = Split-Path -Path $rel -Parent
    $destDir = Join-SoscPath $ConfigDir $script:DisabledDir
    if ($sub -and $sub -ne 'scripts') { $destDir = Join-SoscPath $destDir ($sub -split '[\\/]') }
    New-SoscDirectory $destDir
    $name = Split-Path -Path $Path -Leaf
    $dest = Join-SoscPath $destDir $name
    if (Test-Path -LiteralPath $dest) {
        $ext = [System.IO.Path]::GetExtension($name)
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)
        if ((Get-Item -LiteralPath $Path -Force).PSIsContainer) { $ext = ''; $stem = $name }
        $dest = Join-SoscPath $destDir ($stem + '-' + $Stamp + $ext)
    }
    Assert-SoscInside -Path $dest -Root $ConfigDir
    Assert-SoscNoLink -Path $Path -Root $ConfigDir
    Assert-SoscNoLink -Path $dest -Root $ConfigDir
    Move-Item -LiteralPath $Path -Destination $dest
    $destRel = Get-SoscRelativePath -Path $dest -Root $ConfigDir
    Write-SoscInfo (T 'moved' @($rel, $destRel))
    return ($destRel + '|' + $rel)
}

function Install-SoscUosc {
    param([string]$ConfigDir, [string]$UoscDir, [string]$Stamp)
    $scripts = Join-SoscPath $ConfigDir 'scripts'
    New-SoscDirectory $scripts
    $moved = @()
    foreach ($legacy in $script:UoscLegacy) {
        $p = Join-SoscPath $scripts $legacy
        if (Test-Path -LiteralPath $p) { $moved += Move-SoscToDisabled -Path $p -ConfigDir $ConfigDir -Stamp $Stamp }
    }
    $dest = Join-SoscPath $scripts 'uosc'
    Remove-SoscItem -Path $dest -Root $ConfigDir
    Copy-SoscTree -From (Join-SoscPath $UoscDir @('scripts', 'uosc')) -To $dest
    $fonts = Join-SoscPath $ConfigDir 'fonts'
    New-SoscDirectory $fonts
    foreach ($font in $script:UoscFonts) {
        $src = Join-SoscPath $UoscDir @('fonts', $font)
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Copy-Item -LiteralPath $src -Destination (Join-SoscPath $fonts $font) -Force
        }
    }
    return $moved
}

function Test-SoscUoscPresent {
    param([string]$ConfigDir)
    return ((Test-Path -LiteralPath (Join-SoscPath $ConfigDir @('scripts', 'uosc')) -PathType Container) -or
        (Test-Path -LiteralPath (Join-SoscPath $ConfigDir @('scripts', 'uosc.lua')) -PathType Leaf))
}

function Install-SoscTarget {
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)]$Artifacts,
        [string]$Stamp = ''
    )
    if (-not $Stamp) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }
    $config = Get-SoscFullPath $Candidate.ConfigDir
    Write-SoscInfo ''
    Write-SoscInfo (T 'installing_to' @($config))

    # a. Backup (only when there is something to back up).
    $backup = ''
    if (Test-Path -LiteralPath $config -PathType Container) {
        try { $backup = New-SoscBackup -ConfigDir $config -Stamp $Stamp }
        catch { throw (T 'backup_failed' @($config, $_.Exception.Message)) }
        if ($backup) { Write-SoscInfo (T 'backup_done' @($backup)) }
    }
    else {
        New-SoscDirectory $config
    }

    try {
        $old = Read-SoscRecord $config
        $oldValues = @{}
        $oldDisabled = @()
        $oldFiles = @()
        if ($null -ne $old) { $oldValues = $old.Values; $oldDisabled = @($old.Disabled); $oldFiles = @($old.Files) }
        $first = ($null -eq $old)
        $prev = {
            param([string]$Key, [bool]$Now)
            if (-not $first -and $oldValues.ContainsKey($Key)) { return ($oldValues[$Key] -eq 'yes') }
            return $Now
        }

        $scripts = Join-SoscPath $config 'scripts'
        $opts = Join-SoscPath $config 'script-opts'
        $uoscBefore = & $prev 'uosc_preexisting' (Test-SoscUoscPresent $config)
        $thumbBefore = & $prev 'thumbfast_preexisting' (Test-Path -LiteralPath (Join-SoscPath $scripts 'thumbfast.lua') -PathType Leaf)
        $mpvConfBefore = & $prev 'mpv_conf_preexisting' (Test-Path -LiteralPath (Join-SoscPath $config 'mpv.conf') -PathType Leaf)
        $inputConfBefore = & $prev 'input_conf_preexisting' (Test-Path -LiteralPath (Join-SoscPath $config 'input.conf') -PathType Leaf)
        $confBefore = @{}
        foreach ($c in $script:SharedConfs) {
            $key = ($c -replace '\.conf$', '') + '_conf_preexisting'
            $confBefore[$c] = & $prev $key (Test-Path -LiteralPath (Join-SoscPath $opts $c) -PathType Leaf)
        }

        # b. Interfaces that clash with uosc.
        $disabled = New-Object System.Collections.Generic.List[string]
        foreach ($d in $oldDisabled) { $disabled.Add($d) }
        $conflicts = @(Find-SoscConflicts $config)
        if ($conflicts.Count -gt 0) {
            Write-SoscWarn (T 'conflicts_found')
            foreach ($c in $conflicts) { Write-SoscWarn ('  - ' + (Get-SoscRelativePath -Path $c -Root $config)) }
            if (Confirm-Sosc -Question (T 'conflicts_confirm' @($script:DisabledDir)) -Default $true) {
                foreach ($c in $conflicts) { $disabled.Add((Move-SoscToDisabled -Path $c -ConfigDir $config -Stamp $Stamp)) }
            }
            else {
                Write-SoscWarn (T 'conflicts_kept')
            }
        }

        # c. uosc.
        foreach ($m in (Install-SoscUosc -ConfigDir $config -UoscDir $Artifacts.UoscDir -Stamp $Stamp)) { $disabled.Add($m) }
        Write-SoscOk (T 'uosc_done' @($script:UoscVersion))

        # d. thumbfast.
        New-SoscDirectory $scripts
        Copy-Item -LiteralPath $Artifacts.ThumbfastFile -Destination (Join-SoscPath $scripts 'thumbfast.lua') -Force
        Write-SoscOk (T 'thumbfast_done')

        # e. sosc files.
        $installed = New-Object System.Collections.Generic.List[string]
        $srcScripts = Join-SoscPath $Source.ConfigDir 'scripts'
        foreach ($f in @(Get-ChildItem -LiteralPath $srcScripts -File -Filter 'sosc-*.lua' -Force)) {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-SoscPath $scripts $f.Name) -Force
            $installed.Add('scripts/' + $f.Name)
        }
        New-SoscDirectory $opts
        $origDir = Join-SoscPath $config @($script:OriginalsDir, 'script-opts')
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-SoscPath $Source.ConfigDir 'script-opts') -File -Filter '*.conf' -Force)) {
            $dest = Join-SoscPath $opts $f.Name
            if ($first -and $script:SharedConfs -contains $f.Name -and (Test-Path -LiteralPath $dest -PathType Leaf)) {
                New-SoscDirectory $origDir
                Copy-Item -LiteralPath $dest -Destination (Join-SoscPath $origDir $f.Name) -Force
            }
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            $installed.Add('script-opts/' + $f.Name)
        }
        foreach ($name in $script:UserChoiceFiles) {
            $dest = Join-SoscPath $config $name
            if (Test-Path -LiteralPath $dest -PathType Leaf) {
                Write-SoscInfo (T 'kept_user_file' @($name))
            }
            else {
                Copy-Item -LiteralPath (Join-SoscPath $Source.ConfigDir $name) -Destination $dest
            }
        }
        foreach ($oldFile in $oldFiles) {
            if ($installed -contains $oldFile -or $oldFile -notmatch '^scripts/sosc-[^/\\]+\.lua$|^script-opts/sosc-[^/\\]+\.conf$') { continue }
            if (-not (Test-SoscRecordPath $oldFile)) { continue }
            $p = Join-SoscPath $config ($oldFile -split '/')
            if (Test-Path -LiteralPath $p -PathType Leaf) {
                Remove-SoscItem -Path $p -Root $config
                Write-SoscInfo (T 'removed_stale' @($oldFile))
            }
        }
        Write-SoscOk (T 'sosc_files_done' @($installed.Count))

        # g. mpv.net does not always tell thumbfast where it is.
        if (($Candidate.Kind -eq 'mpv.net' -or $Candidate.Kind -eq 'AnimeJaNai') -and $Candidate.Exe) {
            Set-SoscConfOption -Path (Join-SoscPath $opts 'thumbfast.conf') -Key 'mpv_path' -Value $Candidate.Exe `
                -Comment 'Added by the sosc installer: mpv.net does not always tell thumbfast where it is.'
            Write-SoscInfo (T 'mpvpath_set' @($Candidate.Exe))
        }

        # f. Managed blocks.
        [void](Update-SoscManagedFile -Path (Join-SoscPath $config 'mpv.conf') -Kind 'mpv')
        [void](Update-SoscManagedFile -Path (Join-SoscPath $config 'input.conf') -Kind 'input')

        # h. Record.
        $firstBackup = $backup
        if (-not $first -and $oldValues.ContainsKey('first_backup')) { $firstBackup = $oldValues['first_backup'] }
        $values = [ordered]@{}
        $values['sosc_version'] = $Source.Version
        $values['sosc_commit'] = $Source.Commit
        $values['uosc_version'] = $script:UoscVersion
        $values['thumbfast_commit'] = $script:ThumbfastCommit
        $values['installed_at'] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        $values['player'] = $Candidate.Kind
        $values['player_exe'] = $Candidate.Exe
        $values['uosc_preexisting'] = ConvertTo-SoscYesNo $uoscBefore
        $values['thumbfast_preexisting'] = ConvertTo-SoscYesNo $thumbBefore
        $values['uosc_conf_preexisting'] = ConvertTo-SoscYesNo $confBefore['uosc.conf']
        $values['thumbfast_conf_preexisting'] = ConvertTo-SoscYesNo $confBefore['thumbfast.conf']
        $values['mpv_conf_preexisting'] = ConvertTo-SoscYesNo $mpvConfBefore
        $values['input_conf_preexisting'] = ConvertTo-SoscYesNo $inputConfBefore
        $values['first_backup'] = $firstBackup
        $values['last_backup'] = $backup
        Write-SoscRecord -ConfigDir $config -Values $values -Files $installed.ToArray() -Disabled $disabled.ToArray()
    }
    catch {
        $message = $_.Exception.Message
        if ($backup) { $message += ' ' + (T 'restore_hint' @($backup)) }
        throw $message
    }
    Write-SoscOk (T 'install_ok' @($config))
    return $backup
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

function Uninstall-SoscTarget {
    param([Parameter(Mandatory = $true)]$Candidate, [string]$Stamp = '')
    if (-not $Stamp) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }
    $config = Get-SoscFullPath $Candidate.ConfigDir
    Write-SoscInfo ''
    Write-SoscInfo (T 'uninstalling_from' @($config))
    try { $backup = New-SoscBackup -ConfigDir $config -Stamp $Stamp }
    catch { throw (T 'backup_failed' @($config, $_.Exception.Message)) }
    if ($backup) { Write-SoscInfo (T 'backup_done' @($backup)) }

    try {
        $record = Read-SoscRecord $config
        $values = @{}
        $disabled = @()
        if ($null -ne $record) { $values = $record.Values; $disabled = @($record.Disabled) }
        $wasThere = {
            param([string]$Key)
            if ($null -eq $record -or -not $values.ContainsKey($Key)) { return $null }
            return ($values[$Key] -eq 'yes')
        }
        $scripts = Join-SoscPath $config 'scripts'
        $opts = Join-SoscPath $config 'script-opts'

        if (Test-Path -LiteralPath $scripts -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $scripts -File -Filter 'sosc-*.lua' -Force)) { Remove-SoscItem -Path $f.FullName -Root $config }
        }
        if (Test-Path -LiteralPath $opts -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $opts -File -Filter 'sosc-*.conf' -Force)) { Remove-SoscItem -Path $f.FullName -Root $config }
        }

        $originals = Join-SoscPath $config @($script:OriginalsDir, 'script-opts')
        foreach ($c in $script:SharedConfs) {
            $p = Join-SoscPath $opts $c
            $before = & $wasThere (($c -replace '\.conf$', '') + '_conf_preexisting')
            $orig = Join-SoscPath $originals $c
            if ($before -eq $true -and (Test-Path -LiteralPath $orig -PathType Leaf)) {
                Copy-Item -LiteralPath $orig -Destination $p -Force
                Write-SoscInfo (T 'conf_restored' @(('script-opts/' + $c)))
            }
            elseif ($before -eq $false) {
                Remove-SoscItem -Path $p -Root $config
            }
            elseif ($before -eq $true) {
                $firstBackup = ''
                if ($values.ContainsKey('first_backup')) { $firstBackup = [string]$values['first_backup'] }
                Write-SoscInfo (T 'conf_left' @(('script-opts/' + $c), $firstBackup))
            }
            elseif (Test-Path -LiteralPath $p -PathType Leaf) {
                Write-SoscInfo (T 'conf_unknown' @(('script-opts/' + $c)))
            }
        }

        Remove-SoscManagedFile -Path (Join-SoscPath $config 'mpv.conf') -Root $config -CreatedBySosc ((& $wasThere 'mpv_conf_preexisting') -eq $false)
        Remove-SoscManagedFile -Path (Join-SoscPath $config 'input.conf') -Root $config -CreatedBySosc ((& $wasThere 'input_conf_preexisting') -eq $false)

        $uoscBefore = & $wasThere 'uosc_preexisting'
        $removeUosc = $false
        if (Test-SoscUoscPresent $config) {
            $removeUosc = Confirm-Sosc -Question (T 'ask_remove_uosc') -Default ($uoscBefore -eq $false)
            if ($removeUosc) {
                Remove-SoscItem -Path (Join-SoscPath $scripts 'uosc') -Root $config
                foreach ($font in $script:UoscFonts) { Remove-SoscItem -Path (Join-SoscPath $config @('fonts', $font)) -Root $config }
            }
        }
        $thumb = Join-SoscPath $scripts 'thumbfast.lua'
        if (Test-Path -LiteralPath $thumb -PathType Leaf) {
            if (Confirm-Sosc -Question (T 'ask_remove_thumbfast') -Default ((& $wasThere 'thumbfast_preexisting') -eq $false)) {
                Remove-SoscItem -Path $thumb -Root $config
            }
        }

        $pending = @($disabled | Where-Object { $_ -match '\|' })
        if ($pending.Count -gt 0) {
            $names = [string]::Join(', ', @($pending | ForEach-Object { ($_ -split '\|')[1] }))
            if (Confirm-Sosc -Question (T 'ask_restore' @($names)) -Default $removeUosc) {
                foreach ($entry in $pending) {
                    $pair = $entry -split '\|'
                    # Already checked when the record was read; checked again here
                    # because an entry pointing outside must never be acted on.
                    if ($pair.Count -ne 2 -or -not (Test-SoscRecordPath $pair[0]) -or -not (Test-SoscRecordPath $pair[1])) {
                        Write-SoscWarn (T 'record_bad' @($entry)); continue
                    }
                    $from = Join-SoscPath $config ($pair[0] -split '/')
                    $to = Join-SoscPath $config ($pair[1] -split '/')
                    if (-not (Test-SoscInside -Path $from -Root $config)) { Write-SoscWarn (T 'outside_target' @($from, $config)); continue }
                    if (-not (Test-SoscInside -Path $to -Root $config)) { Write-SoscWarn (T 'outside_target' @($to, $config)); continue }
                    if (-not (Test-Path -LiteralPath $from)) { continue }
                    if (Test-Path -LiteralPath $to) { Write-SoscWarn (T 'restore_skipped' @($pair[0], $pair[1])); continue }
                    Assert-SoscNoLink -Path $from -Root $config
                    Assert-SoscNoLink -Path $to -Root $config
                    New-SoscDirectory (Split-Path -Path $to -Parent)
                    Move-Item -LiteralPath $from -Destination $to
                    Write-SoscInfo (T 'moved' @($pair[0], $pair[1]))
                }
            }
        }

        $deleteChoices = $false
        if (@($script:UserChoiceFiles | Where-Object { Test-Path -LiteralPath (Join-SoscPath $config $_) -PathType Leaf }).Count -gt 0) {
            $deleteChoices = Confirm-Sosc -Question (T 'ask_delete_choices') -Default $false
            if ($deleteChoices) {
                foreach ($name in $script:UserChoiceFiles) { Remove-SoscItem -Path (Join-SoscPath $config $name) -Root $config }
            }
        }
        $mpvConf = Join-SoscPath $config 'mpv.conf'
        if ($deleteChoices -and (Test-Path -LiteralPath $mpvConf -PathType Leaf)) {
            $text = (Read-SoscText $mpvConf).Text
            foreach ($name in $script:UserChoiceFiles) {
                if ($text -match ('(?im)^\s*include\s*=.*' + [regex]::Escape($name))) { Write-SoscWarn (T 'includes_outside' @($name)) }
            }
        }

        # Folders left empty (sosc may have created them) go too.
        foreach ($dirName in @('fonts', 'script-opts', 'scripts')) {
            $dir = Join-SoscPath $config $dirName
            $item = Get-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
            if ($null -ne $item -and $item.PSIsContainer -and -not (Test-SoscLink $item) -and
                @(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) {
                Remove-SoscItem -Path $dir -Root $config
            }
        }
        Remove-SoscItem -Path (Join-SoscPath $config $script:OriginalsDir) -Root $config
        Remove-SoscItem -Path (Join-SoscPath $config $script:RecordName) -Root $config
        $disabledDir = Join-SoscPath $config $script:DisabledDir
        if ((Test-Path -LiteralPath $disabledDir -PathType Container) -and
            @(Get-ChildItem -LiteralPath $disabledDir -Recurse -File -Force).Count -eq 0) {
            Remove-SoscItem -Path $disabledDir -Root $config
        }
    }
    catch {
        $message = $_.Exception.Message
        if ($backup) { $message += ' ' + (T 'restore_hint' @($backup)) }
        throw $message
    }
    Write-SoscOk (T 'uninstall_ok' @($config))
    return $backup
}

# ---------------------------------------------------------------------------
# Interactive flow
# ---------------------------------------------------------------------------

function Get-SoscKindLabel {
    param([string]$Kind)
    if ($Kind -eq 'folder') { return (T 'kind_folder') }
    return $Kind
}

function Show-SoscCandidates {
    param([object[]]$Candidates)
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $c = $Candidates[$i]
        $tags = @()
        if ($c.Installed -and $c.Manual) { $tags += (T 'tag_manual') }
        elseif ($c.Installed) { $tags += (T 'tag_installed' @($c.InstalledVersion)) }
        if (-not $c.Writable) { $tags += (T 'tag_readonly') }
        if (-not $c.Exists) { $tags += (T 'tag_new') }
        Write-SoscInfo (' {0}) {1}  {2}' -f ($i + 1), (Get-SoscKindLabel $c.Kind), [string]::Join(' ', $tags))
        if ($c.Exe) { Write-SoscInfo (T 'cand_exe' @($c.Exe)) }
        Write-SoscInfo (T 'cand_config' @($c.ConfigDir))
    }
}

function Read-SoscFolder {
    param([hashtable]$Env, [object[]]$Candidates)
    while ($true) {
        $answer = Read-SoscLine (T 'ask_folder')
        if ($null -eq $answer -or $answer.Trim() -eq '' -or $answer.Trim() -eq '0') { return $null }
        try { $path = ConvertTo-SoscTypedPath $answer }
        catch { Write-SoscWarn $_.Exception.Message; continue }
        $parent = Split-Path -Path $path -Parent
        if ((Test-Path -LiteralPath $path -PathType Container) -or ($parent -and (Test-Path -LiteralPath $parent -PathType Container))) {
            $c = Resolve-SoscManualTarget -Env $Env -Path $path -Candidates $Candidates
            if ($null -ne $c) { return $c }
            continue
        }
        Write-SoscWarn (T 'folder_missing' @($path))
    }
}

# Runs winget. Its output goes to the screen, never into the caller's return
# value. Returns winget's exit code (-1 when it could not be started).
function Invoke-SoscWinget {
    param([string]$Exe)
    $wingetArgs = @('install', '--id', 'mpv.net', '-e', '--accept-source-agreements', '--accept-package-agreements')
    try {
        & $Exe @wingetArgs | ForEach-Object { Write-SoscInfo ([string]$_) }
        return [int]$LASTEXITCODE
    }
    catch {
        Write-SoscWarn (T 'winget_error' @($_.Exception.Message))
        return -1
    }
}

# Checks write access and offers the user folder when a portable one is read-only.
function Resolve-SoscWritable {
    param([hashtable]$Env, $Candidate)
    if ($Candidate.Writable) { return $Candidate }
    Write-SoscWarn (T 'readonly_warn' @($Candidate.ConfigDir))
    if ($Candidate.UserConfigDir) {
        if ($Candidate.Portable) { Write-SoscWarn (T 'readonly_portable' @($Candidate.ConfigDir, $Candidate.UserConfigDir)) }
        if (-not $script:NonInteractive -and (Confirm-Sosc -Question (T 'readonly_offer' @($Candidate.UserConfigDir)) -Default $false)) {
            $alt = New-SoscCandidate -Env $Env -Kind $Candidate.Kind -Exe $Candidate.Exe -ConfigDir (Get-SoscFullPath $Candidate.UserConfigDir) -Portable $false
            if ($alt.Writable) { return $alt }
            Write-SoscWarn (T 'readonly_warn' @($alt.ConfigDir))
        }
    }
    Write-SoscWarn (T 'readonly_skip' @($Candidate.ConfigDir))
    return $null
}

# Nothing detected: offer winget, a typed folder or %APPDATA%\mpv.
function Invoke-SoscNoPlayerMenu {
    param([hashtable]$Env)
    Write-SoscWarn (T 'none_found')
    $winget = & $Env.FindCommand 'winget'
    $hasWinget = -not [string]::IsNullOrEmpty($winget)
    $appMpv = Get-SoscUserConfigDir -Env $Env -Kind 'mpv'
    while ($true) {
        Write-SoscInfo (T 'none_opt_winget')
        if (-not $hasWinget) { Write-SoscInfo (T 'none_nowinget') }
        Write-SoscInfo (T 'none_opt_folder')
        Write-SoscInfo (T 'none_opt_prepare' @($appMpv))
        Write-SoscInfo (T 'opt_quit')
        Write-SoscInfo (T 'none_link')
        $answer = Read-SoscLine (T 'menu_prompt')
        if ($null -eq $answer) { return @() }
        switch ($answer.Trim()) {
            '0' { return @() }
            '1' {
                if (-not $hasWinget) { Write-SoscWarn (T 'invalid'); continue }
                if (Confirm-Sosc -Question (T 'winget_confirm') -Default $true) {
                    $code = Invoke-SoscWinget -Exe $winget
                    if ($code -ne 0) { Write-SoscWarn (T 'winget_failed' @($code)) }
                    $found = @(Find-SoscPlayers -Env $Env)
                    if ($found.Count -gt 0) { return $found }
                    Write-SoscWarn (T 'none_found')
                }
            }
            '2' {
                $c = Read-SoscFolder -Env $Env -Candidates @()
                if ($null -ne $c) { return @($c) }
            }
            '3' {
                if (-not $appMpv) { Write-SoscWarn (T 'invalid'); continue }
                $c = Resolve-SoscManualTarget -Env $Env -Path $appMpv -Candidates @()
                if ($null -ne $c) { return @($c) }
            }
            default { Write-SoscWarn (T 'invalid') }
        }
    }
}

# Returns Ok (false: wrong usage with -Yes) and the targets (empty: cancelled).
function Select-SoscTargets {
    param([hashtable]$Env, [string]$Mode, [string[]]$Paths)
    Write-SoscInfo (T 'detecting')
    $all = @(Find-SoscPlayers -Env $Env)
    $chosen = New-Object System.Collections.Generic.List[object]

    $refused = $false
    if (@($Paths).Count -gt 0) {
        foreach ($p in $Paths) {
            $c = $null
            try { $c = Resolve-SoscManualTarget -Env $Env -Path $p -Candidates $all }
            catch { Write-SoscError $_.Exception.Message }
            if ($null -ne $c) { $chosen.Add($c) } else { $refused = $true }
        }
    }
    else {
        $list = $all
        if ($Mode -eq 'uninstall') { $list = @($all | Where-Object { $_.Installed }) }
        if ($script:NonInteractive) {
            if ($list.Count -eq 1) { $chosen.Add($list[0]) }
            elseif ($list.Count -eq 0) {
                if ($Mode -eq 'uninstall') { Write-SoscError (T 'nothing_to_uninstall') } else { Write-SoscError (T 'none_found') }
                return [pscustomobject]@{ Ok = $false; Targets = @() }
            }
            else {
                Write-SoscError (T 'usage_many')
                Show-SoscCandidates $list
                return [pscustomobject]@{ Ok = $false; Targets = @() }
            }
        }
        elseif ($list.Count -eq 0 -and $Mode -eq 'install') {
            foreach ($c in @(Invoke-SoscNoPlayerMenu -Env $Env)) { $chosen.Add($c) }
        }
        else {
            if ($list.Count -eq 0) { Write-SoscWarn (T 'nothing_to_uninstall') }
            while ($true) {
                if ($list.Count -gt 0) {
                    if ($Mode -eq 'uninstall') { Write-SoscInfo (T 'found_header_uninst') } else { Write-SoscInfo (T 'found_header') }
                    Show-SoscCandidates $list
                }
                Write-SoscInfo (' ' + (T 'opt_other'))
                Write-SoscInfo (' ' + (T 'opt_quit'))
                $text = Read-SoscLine (T 'select_prompt')
                # No more input (stdin closed or redirected): same as choosing Exit.
                if ($null -eq $text) { break }
                $sel = ConvertFrom-SoscSelection -Text $text -Count $list.Count
                if ($null -eq $sel) { Write-SoscWarn (T 'invalid'); continue }
                if ($sel.Quit) { break }
                foreach ($i in $sel.Indexes) { $chosen.Add($list[$i]) }
                if ($sel.Other) {
                    $c = Read-SoscFolder -Env $Env -Candidates $all
                    if ($null -ne $c) { $chosen.Add($c) }
                }
                break
            }
        }
    }

    # Folders that must never be used, and folders that do not look like mpv's.
    $safe = New-Object System.Collections.Generic.List[object]
    foreach ($c in $chosen) {
        if (Test-SoscForbiddenTarget -Env $Env -Path $c.ConfigDir) {
            Write-SoscError (T 'target_root' @($c.ConfigDir))
            $refused = $true
            continue
        }
        if (-not (Test-SoscLooksLikeMpvConfig -Env $Env -Candidate $c)) {
            Write-SoscWarn (T 'not_mpv_folder' @($c.ConfigDir))
            if ($script:NonInteractive) {
                Write-SoscError (T 'not_mpv_yes')
                $refused = $true
                continue
            }
            if (-not (Confirm-Sosc -Question (T 'not_mpv_confirm') -Default $false)) {
                Write-SoscWarn (T 'readonly_skip' @($c.ConfigDir))
                continue
            }
        }
        $safe.Add($c)
    }
    if ($refused -and $script:NonInteractive) { return [pscustomobject]@{ Ok = $false; Targets = @() } }

    if ($Mode -eq 'uninstall') { return [pscustomobject]@{ Ok = $true; Targets = $safe.ToArray() } }
    $writable = New-Object System.Collections.Generic.List[object]
    foreach ($c in $safe) {
        $w = Resolve-SoscWritable -Env $Env -Candidate $c
        if ($null -ne $w) { $writable.Add($w) }
    }
    return [pscustomobject]@{ Ok = $true; Targets = $writable.ToArray() }
}

function Test-SoscUnderSystemDirs {
    param([hashtable]$Env, [string]$Path)
    foreach ($root in @($Env.ProgramFiles, $Env.ProgramFilesX86, $Env.ProgramData)) {
        if ($root -and (Test-SoscInside -Path $Path -Root $root)) { return $true }
    }
    return $false
}

# Running as administrator is not needed and risky: warn and ask; with -Yes,
# only allow folders under Program Files or ProgramData (the only ones that may
# really need it).
function Confirm-SoscElevation {
    param([hashtable]$Env, [object[]]$Targets)
    if (-not $Env.IsAdmin) { return $true }
    Write-SoscWarn (T 'admin_warn')
    if ($script:NonInteractive) {
        $bad = @($Targets | Where-Object { -not (Test-SoscUnderSystemDirs -Env $Env -Path $_.ConfigDir) } | ForEach-Object { $_.ConfigDir })
        if ($bad.Count -gt 0) {
            Write-SoscError (T 'admin_refused' @(([string]::Join('; ', $bad))))
            return $false
        }
        return $true
    }
    return (Confirm-Sosc -Question (T 'admin_confirm') -Default $false)
}

function Invoke-SoscMain {
    param([string]$Action, [string[]]$Target, [bool]$Yes)
    $script:NonInteractive = $Yes
    if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        Write-SoscError (T 'old_ps')
        return 2
    }
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 } catch { }
    }

    Write-SoscInfo (T 'title')
    if (-not $Action) {
        if ($Yes) { Write-SoscError (T 'usage_yes_action'); return 2 }
        while (-not $Action) {
            Write-SoscInfo (T 'menu')
            $answer = Read-SoscLine (T 'menu_prompt')
            if ($null -eq $answer) { return 0 }
            switch ($answer.Trim()) {
                '1' { $Action = 'install' }
                '2' { $Action = 'uninstall' }
                '0' { Write-SoscInfo (T 'cancelled'); return 0 }
                default { Write-SoscWarn (T 'invalid') }
            }
        }
    }

    # powershell -File passes "-Target a,b" as one string: ';' separates folders.
    $paths = @($Target | ForEach-Object { $_ -split ';' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    $environment = New-SoscEnvironment
    $script:SoscElevated = [bool]$environment.IsAdmin
    $selection = Select-SoscTargets -Env $environment -Mode $Action -Paths $paths
    if (-not $selection.Ok) { return 2 }
    $targets = @($selection.Targets)
    if (@($targets).Count -eq 0) {
        if ($Yes) { Write-SoscError (T 'usage_none'); return 2 }
        Write-SoscInfo (T 'cancelled')
        return 0
    }
    if (-not (Confirm-SoscElevation -Env $environment -Targets $targets)) {
        if ($Yes) { return 2 }
        Write-SoscInfo (T 'cancelled')
        return 0
    }

    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $ok = 0
    $temp = $null
    try {
        if ($Action -eq 'install') {
            $temp = New-SoscTempDir
            try {
                $source = Get-SoscSource -TempDir $temp
                $artifacts = Get-SoscArtifacts -TempDir $temp
            }
            catch {
                Write-SoscError (T 'error_generic' @($_.Exception.Message))
                return 1
            }
        }
        foreach ($t in $targets) {
            try {
                if ($Action -eq 'install') {
                    [void](Install-SoscTarget -Candidate $t -Source $source -Artifacts $artifacts -Stamp $stamp)
                }
                else {
                    [void](Uninstall-SoscTarget -Candidate $t -Stamp $stamp)
                }
                $ok++
            }
            catch {
                Write-SoscError (T 'target_failed' @($t.ConfigDir, $_.Exception.Message))
            }
        }
    }
    finally {
        if ($temp -and (Test-Path -LiteralPath $temp)) {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-SoscInfo ''
    Write-SoscInfo (T 'summary' @($ok, @($targets).Count))
    if ($ok -gt 0) { Write-SoscInfo (T 'restart') }
    if ($ok -lt @($targets).Count) { return 1 }
    return 0
}

# Tests load the functions above without running the installer.
if ($env:SOSC_INSTALL_TEST) { return }

$code = Invoke-SoscMain -Action $Action -Target $Target -Yes ([bool]$Yes)
if ($PSCommandPath) { exit $code }
$global:LASTEXITCODE = $code
