<#
.SYNOPSIS
    sosc installer for Windows: mpv, mpv.net and AnimeJaNai.

.DESCRIPTION
    Installs, updates or removes sosc (https://github.com/SCEPTICG/sosc), together
    with uosc and thumbfast, in one or more mpv config folders.

    From a published release (the release's sosc.ps1 downloads that release's
    sosc.zip and checks its SHA256 before using it):
        irm https://github.com/SCEPTICG/sosc/releases/latest/download/sosc.ps1 | iex
    With options (iex cannot pass them):
        & ([scriptblock]::Create((irm https://github.com/SCEPTICG/sosc/releases/latest/download/sosc.ps1))) -Action uninstall
    From a copy of the repository, or a downloaded sosc.ps1:
        powershell -ExecutionPolicy Bypass -File install\sosc.ps1

    No administrator rights, no registry, no PATH changes. Before touching a
    folder it copies what it may change (mpv.conf, input.conf, scripts,
    script-opts, fonts and its own files) to a sibling folder named
    <config>-respaldo-sosc-<date>.

    Works with Windows PowerShell 5.1 and PowerShell 7. This file is pure ASCII on
    purpose: Windows PowerShell 5.1 reads BOM-less scripts as ANSI, so the Spanish
    messages are written with \uXXXX escapes and decoded at start-up.

    Everything runs inside one script block, invoked in a scope of its own (a
    throw-away dynamic module), so that run through iex it leaves nothing behind
    in the session: no variables, functions, StrictMode or ErrorActionPreference
    changes. It only calls exit when it runs from a file (-File, or .\sosc.ps1);
    through iex it returns and leaves its exit code in $LASTEXITCODE.

.PARAMETER SoscAction
    Use it as -Action (alias). install or uninstall. Without it a menu is
    shown.

.PARAMETER SoscTarget
    Use it as -Target (alias). mpv config folder(s) to work on (the folder that
    holds mpv.conf, e.g. ...\mpv-AnimeJaNai\portable_config or %APPDATA%\mpv).
    Several folders go separated by ';' (with -File, PowerShell does not split
    "a,b" into a list). Without it the detected players are listed.

.PARAMETER SoscYes
    Use it as -Yes (alias). Do not ask: take the default answer to every
    question. Needs -Action, and -Target when more than one folder is found.

.PARAMETER SoscNoMenu
    Use it as -NoMenu (alias). Ask with numbers and typed answers instead of
    the keyboard menus (arrows, Space, Enter, Esc). Numbers are also used on
    their own when there is no interactive console (input or output
    redirected, -NonInteractive, ISE...).

.PARAMETER SoscAnime4K
    Use it as -Anime4K (alias). yes or no: answers the Anime4K questions
    (install it; take over an Anime4K installed by hand) instead of asking.
    Without it, -Yes installs Anime4K where there is none and leaves one
    installed by hand alone. Never used for AnimeJaNai.

.NOTES
    Exit codes: 0 done (or cancelled by the user), 1 at least one folder failed,
    2 wrong usage or nothing to work on.
#>
# The parameters are named Sosc* on purpose: run through iex, a param block
# creates its variables in the caller's session, so they get names nobody else
# uses and are removed again at the end (see the finally below). The aliases
# keep the public names: -Action, -Target, -Yes, -NoMenu, -Anime4K.
[CmdletBinding()]
param(
    [Alias('Action')]
    [ValidateSet('', 'install', 'uninstall')]
    [string]$SoscAction = '',
    [Alias('Target')]
    [string[]]$SoscTarget = @(),
    [Alias('Yes')]
    [switch]$SoscYes,
    [Alias('NoMenu')]
    [switch]$SoscNoMenu,
    [Alias('Anime4K')]
    [ValidateSet('', 'yes', 'no')]
    [string]$SoscAnime4K = ''
)

try {
# A dynamic module gives the script block its own script: scope, so the many
# $script: variables below never land in the caller's session. New-Module with
# an empty body exports nothing and is not added to the session's module list.
# The parameters are passed by name (not with @args, which turns -Yes:$false
# into -Yes).
& (New-Module -ScriptBlock { }) {
param(
    [string]$Action = '',
    [string[]]$Target = @(),
    [switch]$Yes,
    [switch]$NoMenu,
    [string]$Anime4K = ''
)

# Both are local to this script block: the caller's session keeps its own.
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Release markers. tools/make-release.sh replaces these three lines, matched
# whole and exactly once each, with the tag, the URL of that release's sosc.zip
# and its SHA256. Keep them exactly as they are. In the repository they stay
# empty: the sosc files then come from the repository copy the script sits in,
# and run on its own (irm | iex) it explains that there is no release yet.
# With a URL, the sosc files always come from that zip, checked against the hash.
$script:SoscVersion = 'dev'
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

# Anime4K (https://github.com/bloc97/Anime4K, MIT): fixed release, verified by
# SHA256. The zip is flat: 39 Anime4K_*.glsl files and nothing else. Only files
# with that name pattern are ever taken out of it, into <config>/shaders.
$script:Anime4KVersion = '4.0.1'
$script:Anime4KUrl = 'https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip'
$script:Anime4KSha256 = '139cd282086457c5adc79caf7b75b8b825091d71c9b54958c18745fea62d7ed7'
$script:Anime4KPattern = '^Anime4K_[A-Za-z0-9_]+\.glsl$'
# The shaders sosc-upscale.lua uses (its required_shaders(); the Lua tests
# compare both lists). The zip must have all of them.
$script:Anime4KRequired = @(
    'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_M.glsl', 'Anime4K_Restore_CNN_S.glsl', 'Anime4K_Restore_CNN_Soft_M.glsl',
    'Anime4K_Restore_CNN_Soft_S.glsl', 'Anime4K_Restore_CNN_Soft_VL.glsl', 'Anime4K_Restore_CNN_VL.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl', 'Anime4K_Upscale_CNN_x2_S.glsl', 'Anime4K_Upscale_CNN_x2_VL.glsl',
    'Anime4K_Upscale_Denoise_CNN_x2_M.glsl', 'Anime4K_Upscale_Denoise_CNN_x2_VL.glsl'
)
# Keys of Anime4K's official mpv templates, here driving sosc-upscale.lua.
# Only added to input.conf when sosc installed (and manages) Anime4K.
$script:Anime4KBindings = @(
    @{ Key = 'Ctrl+1'; Command = 'script-message-to sosc_upscale set-mode a' },
    @{ Key = 'Ctrl+2'; Command = 'script-message-to sosc_upscale set-mode b' },
    @{ Key = 'Ctrl+3'; Command = 'script-message-to sosc_upscale set-mode c' },
    @{ Key = 'Ctrl+4'; Command = 'script-message-to sosc_upscale set-mode aa' },
    @{ Key = 'Ctrl+5'; Command = 'script-message-to sosc_upscale set-mode bb' },
    @{ Key = 'Ctrl+6'; Command = 'script-message-to sosc_upscale set-mode ca' },
    @{ Key = 'Ctrl+0'; Command = 'script-message-to sosc_upscale set-mode off' }
)
$script:ShadersDir = 'shaders'
$script:ShadersDisabledDir = 'shaders-desactivados'
$script:UpscaleConf = 'sosc-upscale.conf'
# What sosc puts in front of a line of the user's it turns off (never deleted).
$script:CommentPrefix = '# sosc: '
# Backups of one folder that are kept (plus the one from before the first install).
$script:BackupKeep = 3
# -Anime4K: '' (ask; -Yes takes the default answers), 'yes' or 'no'.
$script:SoscAnime4KChoice = ''

# Downloads are only allowed over HTTPS from these hosts.
$script:AllowedHosts = @('github.com', 'raw.githubusercontent.com')

$script:BlockBegin = '# >>> sosc (managed block, do not edit) >>>'
$script:BlockEnd = '# <<< sosc <<<'

$script:MpvConfLines = @(
    'osc=no',
    'osd-bar=no',
    'include="~~/sosc-palette.conf"',
    'include="~~/sosc-subs.conf"',
    'include="~~/sosc-upscale.conf"'
)

$script:InputBindings = @(
    @{ Key = 'Alt+p'; Command = 'script-binding sosc_palettes/open-menu' },
    @{ Key = 'Alt+s'; Command = 'script-binding sosc_skip/skip' },
    @{ Key = 'Alt+t'; Command = 'script-binding sosc_subs/open-menu' }
)

# Files of sosc that only get copied when missing: they hold the user's choices.
# sosc-upscale.conf is written by the installer itself (with the quality that
# suits the graphics card), the others are copied from the sosc files.
$script:UserChoiceFiles = @('sosc-palette.conf', 'sosc-subs.conf', 'sosc-upscale.conf')

# script-opts that are not named sosc-*: removed on uninstall only if sosc put them there.
$script:SharedConfs = @('uosc.conf', 'thumbfast.conf')

$script:RecordName = 'sosc-installed.txt'
$script:DisabledDir = 'scripts-desactivados'
$script:OriginalsDir = 'sosc-originales'

# What the backup copies: only what the installer can change. cache,
# watch_later and anything else in the folder are never touched, so not copied.
# shaders is not copied either: sosc only adds and removes its own Anime4K
# files there, and moves (never deletes) an Anime4K installed by hand to
# shaders-desactivados, which is copied.
$script:BackupItems = @(
    'mpv.conf', 'input.conf', 'scripts', 'script-opts', 'fonts',
    'sosc-palette.conf', 'sosc-subs.conf', 'sosc-upscale.conf', 'sosc-installed.txt',
    'scripts-desactivados', 'sosc-originales', 'shaders-desactivados'
)

# Signs that a folder belongs to mpv (any of them is enough).
$script:MpvConfigFiles = @('mpv.conf', 'input.conf', 'sosc-installed.txt', 'sosc-palette.conf', 'sosc-subs.conf', 'sosc-upscale.conf')
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

# Folder of this file; empty when run through iex or [scriptblock]::Create.
$script:SoscScriptRoot = $PSScriptRoot
$script:SoscQuiet = $false
$script:NonInteractive = $false
# Set when running as administrator: deleting or moving then refuses paths that
# go through a link (junction or symbolic link) inside the config folder.
$script:SoscElevated = $false
$script:SoscWarnings = New-Object System.Collections.Generic.List[string]

# Names of the graphics cards, replaceable in tests (returns a list of names).
$script:SoscGpuProbe = { Get-SoscGpuNames }

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
    backup_size           = 'Backing up the files sosc touches ({0} MB)...'
    backup_failed         = 'Could not back up {0}: {1}. Nothing was changed in that folder.'
    conflicts_found       = 'These scripts replace the mpv controls and clash with uosc:'
    conflicts_confirm     = 'Move them to {0}? Nothing is deleted.'
    conflicts_kept        = 'Left in place: uosc and that interface will both draw controls.'
    moved                 = 'Moved {0} -> {1}'
    downloading           = 'Downloading {0}...'
    hash_bad              = 'The download of {0} does not match its expected SHA256 (expected {1}, got {2}). Nothing was installed from it.'
    url_bad               = 'Refusing to download {0}: only HTTPS from GitHub is allowed.'
    release_unpublished   = 'sosc has no published release yet, so this installer cannot run on its own. Download the repository and run install\sosc.ps1 from that copy.'
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
    ask_delete_choices    = 'Delete your saved palette, subtitle and upscaling choices (sosc-palette.conf, sosc-subs.conf, sosc-upscale.conf)?'
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
    menu_help             = '\u2191/\u2193 to move \u00b7 Enter to choose \u00b7 Esc to exit'
    multi_help            = '\u2191/\u2193 to move \u00b7 Space to tick or untick \u00b7 Esc to exit'
    multi_help2           = 'Enter to confirm (with nothing ticked, the highlighted one is chosen)'
    yesno_help            = '\u2190/\u2192 to change \u00b7 Enter to confirm \u00b7 Y/N \u00b7 Esc = No'
    menu_help_short       = '\u2191/\u2193 \u00b7 Enter \u00b7 Esc'
    multi_help_short      = '\u2191/\u2193 \u00b7 Space \u00b7 Enter \u00b7 Esc'
    answer_yes            = 'Yes'
    answer_no             = 'No'
    anime4k_intro         = 'Anime4K sharpens and upscales anime on the graphics card. It stays off until you pick a mode in the Escalado menu or press Ctrl+1 to Ctrl+6 (Ctrl+0 turns it off).'
    anime4k_confirm       = 'Install Anime4K (anime upscaling on the graphics card)?'
    anime4k_done          = 'Anime4K {0} installed ({1} shaders in {2}).'
    anime4k_animejanai    = 'AnimeJaNai already upscales with AI (Ctrl+1 to Ctrl+9): Anime4K is not installed here.'
    anime4k_declined      = 'Anime4K not installed. Run the installer again to install it.'
    anime4k_kept          = 'Anime4K left as it is (-Anime4K no).'
    anime4k_manual        = 'There is already an Anime4K installed by hand in {0} (files: {1}).'
    anime4k_manage        = 'Let sosc take care of it? Your files go to {0} (nothing is deleted, they come back on uninstall) and sosc installs its own copy, with the Escalado menu and the Ctrl+0 to Ctrl+6 keys.'
    anime4k_manual_kept   = 'Your Anime4K is left as it is, with its own keys. The sosc Escalado menu changes the same shaders and does not know what those keys turned on.'
    anime4k_keys_found    = 'input.conf binds these Anime4K keys outside the sosc block:'
    anime4k_comment       = 'Turn those lines off by putting "# sosc: " in front of them, so the sosc keys can use them? They are turned back on when you uninstall.'
    anime4k_commented     = 'input.conf: lines turned off with "# sosc: ": {0}.'
    anime4k_bad_zip       = 'The Anime4K download does not have the shaders sosc needs ({0}).'
    gpu_line              = 'Graphics card: {0} \u2192 quality {1}'
    gpu_unknown           = 'unknown'
    quality_hq            = 'High'
    quality_fast          = 'Fast'
    backup_pruned         = 'Old backup deleted: {0}'
    backup_prune_failed   = 'Could not delete the old backup {0}: {1}'
    ask_restore_anime4k   = 'Move your earlier Anime4K back from {0}?'
    ask_uncomment         = 'Turn your Anime4K keys in input.conf back on?'
    uncommented           = 'input.conf: lines turned back on: {0}.'
    osc_orphan            = 'mpv.conf has "{0}" outside the sosc block: without uosc the player would have no on-screen controls.'
    ask_restore_osc       = 'Move back the interfaces sosc set aside ({0}), so there are controls?'
    ask_comment_osc       = 'Turn that line off by putting "# sosc: " in front of it, so mpv shows its own controls?'
    osc_commented         = 'mpv.conf: "{0}" turned off with "# sosc: ".'
    osc_left              = 'Left as it is: remove that line or install an on-screen controller to get controls back.'
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
    backup_size           = 'Copia de seguridad de los ficheros que toca sosc ({0} MB)...'
    backup_failed         = 'No se ha podido hacer la copia de seguridad de {0}: {1}. No se ha cambiado nada en esa carpeta.'
    conflicts_found       = 'Estos scripts sustituyen los controles de mpv y chocan con uosc:'
    conflicts_confirm     = '\u00bfMoverlos a {0}? No se borra nada.'
    conflicts_kept        = 'Se quedan donde est\u00e1n: uosc y esa interfaz dibujar\u00e1n controles a la vez.'
    moved                 = 'Movido {0} -> {1}'
    downloading           = 'Descargando {0}...'
    hash_bad              = 'La descarga de {0} no coincide con su SHA256 esperado (esperado {1}, obtenido {2}). No se ha instalado nada de ella.'
    url_bad               = 'No se descarga {0}: solo se admite HTTPS desde GitHub.'
    release_unpublished   = 'sosc a\u00fan no tiene ninguna versi\u00f3n publicada, as\u00ed que este instalador no puede funcionar suelto. Descarga el repositorio y ejecuta install\\sosc.ps1 desde esa copia.'
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
    ask_delete_choices    = '\u00bfBorrar tus elecciones guardadas de paleta, subt\u00edtulos y escalado (sosc-palette.conf, sosc-subs.conf, sosc-upscale.conf)?'
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
    menu_help             = '\u2191/\u2193 para moverte \u00b7 Intro para elegir \u00b7 Esc para salir'
    multi_help            = '\u2191/\u2193 para moverte \u00b7 Espacio para marcar o desmarcar \u00b7 Esc para salir'
    multi_help2           = 'Intro para confirmar (si no marcas ninguna, se elige la resaltada)'
    yesno_help            = '\u2190/\u2192 para cambiar \u00b7 Intro para confirmar \u00b7 S/N \u00b7 Esc = No'
    menu_help_short       = '\u2191/\u2193 \u00b7 Intro \u00b7 Esc'
    multi_help_short      = '\u2191/\u2193 \u00b7 Espacio \u00b7 Intro \u00b7 Esc'
    answer_yes            = 'S\u00ed'
    answer_no             = 'No'
    anime4k_intro         = 'Anime4K mejora y reescala el anime en la tarjeta gr\u00e1fica. Est\u00e1 apagado hasta que eliges un modo en el men\u00fa Escalado o pulsas Ctrl+1 a Ctrl+6 (Ctrl+0 lo apaga).'
    anime4k_confirm       = '\u00bfInstalar Anime4K (reescalado de anime en la gr\u00e1fica)?'
    anime4k_done          = 'Anime4K {0} instalado ({1} shaders en {2}).'
    anime4k_animejanai    = 'AnimeJaNai ya reescala con IA (Ctrl+1 a Ctrl+9): aqu\u00ed no se instala Anime4K.'
    anime4k_declined      = 'Anime4K no se instala. Vuelve a ejecutar el instalador para instalarlo.'
    anime4k_kept          = 'Anime4K se deja como est\u00e1 (-Anime4K no).'
    anime4k_manual        = 'Ya hay un Anime4K instalado a mano en {0} (ficheros: {1}).'
    anime4k_manage        = '\u00bfQuieres que lo gestione sosc? Tus ficheros van a {0} (no se borra nada y vuelven al desinstalar) y sosc instala su propia copia, con el men\u00fa Escalado y los atajos Ctrl+0 a Ctrl+6.'
    anime4k_manual_kept   = 'Tu Anime4K se queda como est\u00e1, con sus atajos. El men\u00fa Escalado de sosc cambia los mismos shaders y no sabe lo que hayan activado esos atajos.'
    anime4k_keys_found    = 'input.conf tiene estos atajos de Anime4K fuera del bloque de sosc:'
    anime4k_comment       = '\u00bfDesactivar esas l\u00edneas poni\u00e9ndoles delante "# sosc: ", para que los atajos de sosc puedan usar esas teclas? Se vuelven a activar al desinstalar.'
    anime4k_commented     = 'input.conf: l\u00edneas desactivadas con "# sosc: ": {0}.'
    anime4k_bad_zip       = 'La descarga de Anime4K no tiene los shaders que necesita sosc ({0}).'
    gpu_line              = 'Gr\u00e1fica: {0} \u2192 calidad {1}'
    gpu_unknown           = 'desconocida'
    quality_hq            = 'Alta'
    quality_fast          = 'R\u00e1pida'
    backup_pruned         = 'Borrada la copia de seguridad antigua {0}'
    backup_prune_failed   = 'No se ha podido borrar la copia de seguridad antigua {0}: {1}'
    ask_restore_anime4k   = '\u00bfDevolver a su sitio tu Anime4K anterior, que est\u00e1 en {0}?'
    ask_uncomment         = '\u00bfVolver a activar tus atajos de Anime4K de input.conf?'
    uncommented           = 'input.conf: l\u00edneas activadas de nuevo: {0}.'
    osc_orphan            = 'mpv.conf tiene "{0}" fuera del bloque de sosc: sin uosc, el reproductor se quedar\u00eda sin controles en pantalla.'
    ask_restore_osc       = '\u00bfDevolver a su sitio las interfaces que sosc apart\u00f3 ({0}), para tener controles?'
    ask_comment_osc       = '\u00bfDesactivar esa l\u00ednea poni\u00e9ndole delante "# sosc: ", para que mpv muestre sus propios controles?'
    osc_commented         = 'mpv.conf: "{0}" desactivada con "# sosc: ".'
    osc_left              = 'Se deja como est\u00e1: quita esa l\u00ednea o instala otra interfaz para recuperar los controles.'
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
        # Only \uXXXX is decoded here: English strings hold real backslashes
        # (install\sosc.ps1) that [regex]::Unescape would reject.
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) }
        foreach ($key in $script:SoscStringsEn.Keys) {
            $script:SoscStrings[$key] = [regex]::Replace($script:SoscStringsEn[$key], '\\u([0-9A-Fa-f]{4})', $evaluator)
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
    $r = Invoke-SoscMenuOrNumbers { Read-SoscYesNoMenu -Question $Question -Default $Default }
    if (-not (Test-SoscUseNumbers $r)) { return [bool]$r }
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
# Keyboard menus: arrows, Space, Enter and Esc. When the console cannot do them
# (input or output redirected, -NonInteractive, ISE, ReadKey failing) or with
# -NoMenu, the questions are asked with numbers and typed answers instead.
# ---------------------------------------------------------------------------

# Set by Invoke-SoscMain: $true while keyboard menus can be used.
$script:SoscMenu = $false
# Error message meaning "no keys can be read here": the caller switches to numbers.
$script:SoscNoConsole = 'SOSC_NO_INTERACTIVE_CONSOLE'
# Returned by Invoke-SoscMenuOrNumbers when the question has to be asked with numbers.
$script:SoscUseNumbers = New-Object psobject
# Menu width in columns; 0 means the console's own width.
$script:SoscMenuWidth = 0
# Window height in lines; 0 means the console's own height (replaceable in tests).
$script:SoscMenuHeight = 0
$script:GlyphPointer = [string][char]0x203A
$script:GlyphEllipsis = [string][char]0x2026

# Replaceable in tests: can this console do keyboard menus?
$script:SoscConsoleProbe = { Test-SoscInteractiveConsole }
# Replaceable in tests: reads one key, without echo. Returns a ConsoleKeyInfo or,
# in tests, a key name: 'UpArrow', 'Spacebar', 'Enter', 'Escape', 'S', 'Ctrl+C'...
$script:SoscKeyReader = { [Console]::ReadKey($true) }
# Replaceable in tests: draws a frame (a list of lines, each a list of
# @{Text; Color} pieces) over the previous one, which took $Previous lines.
# Returns how many lines the new frame takes.
$script:SoscMenuRenderer = { param([object[]]$Lines, [int]$Previous) Write-SoscMenuFrame -Lines $Lines -Previous $Previous }
# Replaceable in tests: hide the cursor and take Ctrl+C as a key, and undo it.
$script:SoscConsoleEnter = { Enter-SoscMenuConsole }
$script:SoscConsoleExit = { param($State) Exit-SoscMenuConsole -State $State }
# Replaceable in tests: throws away keys pressed before a menu opened (during a
# download, say), so they never answer its question.
$script:SoscKeyFlush = { Clear-SoscPendingKeys }

function Test-SoscInteractiveConsole {
    try {
        if ($Host.Name -ne 'ConsoleHost') { return $false }
        if (-not [Environment]::UserInteractive) { return $false }
        if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return $false }
        # powershell -NonInteractive (or -noni): only the arguments before the script's own.
        foreach ($a in @([Environment]::GetCommandLineArgs() | Select-Object -Skip 1)) {
            if ($a -match '^[-/](f|file|c|command|ec|encodedcommand)$') { break }
            if ($a -match '^[-/]noni') { return $false }
        }
        [void][Console]::KeyAvailable
        if ([Console]::WindowWidth -lt 20) { return $false }
        return $true
    }
    catch {
        return $false
    }
}

function Test-SoscUseNumbers {
    param($Value)
    return [object]::ReferenceEquals($Value, $script:SoscUseNumbers)
}

# Runs a keyboard menu and returns its answer, or $script:SoscUseNumbers when
# menus are off or the console turns out not to be able to read keys (then they
# stay off for the rest of the run).
function Invoke-SoscMenuOrNumbers {
    param([scriptblock]$Body)
    if (-not $script:SoscMenu -or $script:NonInteractive) { return $script:SoscUseNumbers }
    try {
        return (& $Body)
    }
    catch {
        if ($_.Exception.Message -ne $script:SoscNoConsole) { throw }
        $script:SoscMenu = $false
        return $script:SoscUseNumbers
    }
}

function Get-SoscMenuWidth {
    if ($script:SoscMenuWidth -gt 0) { return $script:SoscMenuWidth }
    $w = 80
    try { $w = [Console]::WindowWidth } catch { }
    if ($w -lt 20) { $w = 80 }
    return $w
}

# Window height in lines, or 0 when it cannot be known (then it is not checked).
function Get-SoscMenuHeight {
    if ($script:SoscMenuHeight -gt 0) { return $script:SoscMenuHeight }
    try { $h = [Console]::WindowHeight } catch { $h = 0 }
    if ($null -eq $h) { $h = 0 }
    return [int]$h
}

# A frame of $Count lines fits when it leaves one line free below it: redrawing
# goes back up exactly that many lines, which only works while the whole frame
# is inside the window. Taller, every key would leave a copy of the menu above.
function Test-SoscFrameFits {
    param([int]$Count)
    if ($Count -le 0) { return $true }
    $h = Get-SoscMenuHeight
    return ($h -le 0 -or $Count -lt $h - 1)
}

# Splits a help text into lines of at most $Max characters instead of cutting
# it: first between its ' . ' separated parts, then between words.
function Split-SoscHelp {
    param([string]$Text, [int]$Max)
    $out = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrEmpty($Text) -or $Max -lt 1) { return , $out.ToArray() }
    $sep = ' ' + [string][char]0x00B7 + ' '
    $tokens = New-Object System.Collections.Generic.List[object]
    $first = $true
    foreach ($part in ($Text -split [regex]::Escape($sep))) {
        $join = $sep
        if ($first) { $join = '' }
        $first = $false
        if ($part.Length -le $Max) { $tokens.Add(@($join, $part)); continue }
        foreach ($word in @($part -split ' ' | Where-Object { $_ -ne '' })) {
            $tokens.Add(@($join, $word))
            $join = ' '
        }
    }
    $line = ''
    foreach ($t in $tokens) {
        $text = Format-SoscFit -Text $t[1] -Max $Max
        if ($line -eq '') { $line = $text }
        elseif ($line.Length + $t[0].Length + $text.Length -le $Max) { $line += $t[0] + $text }
        else { $out.Add($line); $line = $text }
    }
    if ($line -ne '') { $out.Add($line) }
    return , $out.ToArray()
}

# Help lines for a frame, indented by two spaces and wrapped to the width.
function Add-SoscHelpLines {
    param($Lines, [string[]]$Texts)
    $max = (Get-SoscMenuWidth) - 3
    foreach ($h in $Texts) {
        foreach ($part in (Split-SoscHelp -Text $h -Max $max)) { $Lines.Add([object[]]@(New-SoscSeg ('  ' + $part) 'DarkGray')) }
    }
}

# Shortens a text to $Max characters with an ellipsis, at the end or (paths,
# where the last folders matter most) in the middle.
function Format-SoscFit {
    param([string]$Text, [int]$Max, [switch]$Middle)
    if ($null -eq $Text -or $Max -lt 1) { return '' }
    if ($Text.Length -le $Max) { return $Text }
    if ($Max -eq 1) { return $script:GlyphEllipsis }
    if ($Middle) {
        $head = [int][Math]::Floor(($Max - 1) / 3)
        $tail = $Max - 1 - $head
        return $Text.Substring(0, $head) + $script:GlyphEllipsis + $Text.Substring($Text.Length - $tail)
    }
    return $Text.Substring(0, $Max - 1) + $script:GlyphEllipsis
}

# "1) Install or update" -> "Install or update".
function Get-SoscPlainLabel {
    param([string]$Text)
    return ($Text.Trim() -replace '^[0-9A-Za-z]\)\s*', '')
}

function New-SoscSeg {
    param([string]$Text, [string]$Color = '')
    return @{ Text = $Text; Color = $Color }
}

# Draws the frame over the previous one: back up $Previous lines, write every
# line padded to the width (so nothing of the old frame is left) and clear the
# old lines that are no longer needed. Lines never reach the last column, so
# the console never wraps them and going back up stays exact. A frame taller
# than the window is refused before anything is written (Invoke-SoscRender then
# switches to numbers): redrawing it would leave copies of it on screen.
function Write-SoscMenuFrame {
    param([object[]]$Lines, [int]$Previous)
    if (-not (Test-SoscFrameFits @($Lines).Count)) { throw 'The menu does not fit in the window.' }
    $max = (Get-SoscMenuWidth) - 1
    if ($Previous -gt 0) {
        $top = [Console]::CursorTop - $Previous
        if ($top -lt 0) { $top = 0 }
        [Console]::SetCursorPosition(0, $top)
    }
    $count = @($Lines).Count
    $total = [Math]::Max($count, $Previous)
    for ($i = 0; $i -lt $total; $i++) {
        $used = 0
        if ($i -lt $count) {
            foreach ($seg in @($Lines[$i])) {
                $room = $max - $used
                if ($room -le 0) { break }
                $text = Format-SoscFit -Text ([string]$seg.Text) -Max $room
                if ($text.Length -eq 0) { continue }
                if ($seg.Color) { Write-Host $text -NoNewline -ForegroundColor $seg.Color }
                else { Write-Host $text -NoNewline }
                $used += $text.Length
            }
        }
        Write-Host (' ' * [Math]::Max(0, $max - $used))
    }
    if ($total -gt $count) {
        $top = [Console]::CursorTop - ($total - $count)
        if ($top -lt 0) { $top = 0 }
        [Console]::SetCursorPosition(0, $top)
    }
    return $count
}

function Invoke-SoscRender {
    param([object[]]$Lines, [int]$Previous)
    try { return [int](& $script:SoscMenuRenderer $Lines $Previous) }
    catch { throw $script:SoscNoConsole }
}

# Hides the cursor and takes Ctrl+C as a key while a menu is open (so it acts
# as Esc and the console is always put back). Returns what has to be restored.
function Enter-SoscMenuConsole {
    $state = @{ Cursor = $true; CtrlC = $null }
    try { $state.Cursor = [Console]::CursorVisible } catch { }
    try { [Console]::CursorVisible = $false } catch { }
    try {
        $old = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true
        $state.CtrlC = $old
    }
    catch { }
    return $state
}

function Exit-SoscMenuConsole {
    param($State)
    if ($null -eq $State) { return }
    if ($null -ne $State.CtrlC) { try { [Console]::TreatControlCAsInput = [bool]$State.CtrlC } catch { } }
    try { [Console]::CursorVisible = [bool]$State.Cursor } catch { }
}

# Throws away the keys already waiting (a bounded number: a key held down keeps
# them coming). Nothing to do when there is no console to ask.
function Clear-SoscPendingKeys {
    try {
        for ($i = 0; $i -lt 256 -and [Console]::KeyAvailable; $i++) { [void][Console]::ReadKey($true) }
    }
    catch { }
}

# One key as Key (ConsoleKey name), Char, Ctrl and Alt. A reader that fails
# means there is no console to read from.
function Read-SoscKey {
    try { $k = & $script:SoscKeyReader }
    catch { throw $script:SoscNoConsole }
    if ($null -eq $k) { throw $script:SoscNoConsole }
    if ($k -is [string]) {
        $name = $k
        $ctrl = $false
        $alt = $false
        while ($true) {
            if ($name -like 'Ctrl+?*') { $ctrl = $true; $name = $name.Substring(5); continue }
            if ($name -like 'Alt+?*') { $alt = $true; $name = $name.Substring(4); continue }
            break
        }
        $char = [char]0
        if ($name.Length -eq 1) { $char = $name[0]; $name = $name.ToUpperInvariant() }
        return [pscustomobject]@{ Key = $name; Char = $char; Ctrl = $ctrl; Alt = $alt }
    }
    return [pscustomobject]@{
        Key  = [string]$k.Key
        Char = $k.KeyChar
        Ctrl = (($k.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
        Alt  = (($k.Modifiers -band [ConsoleModifiers]::Alt) -ne 0)
    }
}

# Letter and number shortcuts only count when typed on their own: Ctrl+S or
# Alt+Y must not answer Yes.
function Test-SoscPlainKey {
    param($Key)
    return (-not $Key.Ctrl -and -not $Key.Alt)
}

# Esc, and Ctrl+C while a menu is open: always the safe way out.
function Test-SoscCancelKey {
    param($Key)
    return ($Key.Key -eq 'Escape' -or ($Key.Ctrl -and $Key.Key -eq 'C') -or $Key.Char -eq [char]3)
}

# An entry of a list menu. Action: in a multiple choice menu, an entry that is
# chosen with Enter instead of ticked ("Other folder...", "Exit"). Quit: the
# entry that leaves. Summary: what the line left after choosing says. Hotkey:
# in a single choice menu, the digit that chooses it at once (the number it had
# in the old numbered menus).
function New-SoscMenuItem {
    param([string]$Label, [string[]]$Details = @(), [bool]$Action = $false, [bool]$Disabled = $false, [string]$Summary = '', [bool]$Quit = $false, [string]$Hotkey = '')
    if (-not $Summary) { $Summary = $Label }
    return [pscustomobject]@{ Label = $Label; Details = @($Details); Action = $Action; Disabled = $Disabled; Summary = $Summary; Quit = $Quit; Hotkey = $Hotkey }
}

# Next entry that is not disabled, wrapping around at both ends.
function Get-SoscNextItem {
    param([object[]]$Items, [int]$From, [int]$Step)
    $n = @($Items).Count
    $i = $From
    for ($k = 0; $k -lt $n; $k++) {
        $i = (($i + $Step) % $n + $n) % $n
        if (-not $Items[$i].Disabled) { return $i }
    }
    return $From
}

# The list menu as it is drawn: the full version when it fits in the window,
# otherwise a compact one (no folder lines, short help). When not even that
# fits, the question is asked with numbers.
function Get-SoscListFrame {
    param([object[]]$Items, [int]$Current, [bool[]]$Checked, [bool]$Multi)
    foreach ($compact in @($false, $true)) {
        $frame = New-SoscListFrame -Items $Items -Current $Current -Checked $Checked -Multi $Multi -Compact $compact
        if (Test-SoscFrameFits @($frame).Count) { return , $frame }
    }
    throw $script:SoscNoConsole
}

function New-SoscListFrame {
    param([object[]]$Items, [int]$Current, [bool[]]$Checked, [bool]$Multi, [bool]$Compact)
    $width = Get-SoscMenuWidth
    $lines = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $it = $Items[$i]
        $on = ($i -eq $Current)
        $color = ''
        $detailColor = 'DarkGray'
        if ($on) { $color = 'Cyan'; $detailColor = 'Cyan' }
        elseif ($it.Disabled) { $color = 'DarkGray' }
        $pointer = '  '
        if ($on) { $pointer = $script:GlyphPointer + ' ' }
        $box = ''
        if ($Multi -and -not $it.Action) {
            if ($Checked[$i]) { $box = '[x] ' } else { $box = '[ ] ' }
        }
        $head = $pointer + $box + $it.Label
        $segs = @(New-SoscSeg $head $color)
        if ($Compact) {
            # No folder line, but entries that look alike must still be told
            # apart: the folder goes, shortened, on the same line when it fits.
            $room = $width - 1 - $head.Length - 2
            if (@($it.Details).Count -gt 0 -and $room -ge 12) {
                $segs += New-SoscSeg ('  ' + (Format-SoscFit -Text $it.Details[0] -Max $room -Middle)) $detailColor
            }
            $lines.Add([object[]]$segs)
            continue
        }
        $lines.Add([object[]]$segs)
        $indent = ' ' * (2 + $box.Length)
        foreach ($d in $it.Details) {
            $lines.Add([object[]]@(New-SoscSeg ($indent + (Format-SoscFit -Text $d -Max ($width - 1 - $indent.Length) -Middle)) $detailColor))
        }
    }
    if ($Compact) {
        $help = @(T 'menu_help_short')
        if ($Multi) { $help = @(T 'multi_help_short') }
    }
    else {
        $lines.Add([object[]]@())
        $help = @(T 'menu_help')
        if ($Multi) { $help = @((T 'multi_help'), (T 'multi_help2')) }
    }
    Add-SoscHelpLines -Lines $lines -Texts $help
    return , $lines.ToArray()
}

# List menu. Single choice: Up/Down (wrapping around), Home/End, Enter chooses,
# Esc leaves. Multiple choice (-Multi): Space ticks or unticks, Enter confirms
# the ticked entries or, with none ticked, the highlighted one; Enter on an
# action entry chooses it (together with what is ticked).
# Single choice: a digit chooses the entry with that Hotkey (not when disabled).
# $Header: lines written above the menu, only once it is sure the menu fits.
# Returns Cancelled, Index (entry Enter was pressed on; -1 for ticked ones) and
# Checked (indexes of the chosen entries that are not actions).
function Invoke-SoscListMenu {
    param([object[]]$Items, [switch]$Multi, [int]$Start = 0, [string[]]$Header = @())
    $n = $Items.Count
    $checked = New-Object 'bool[]' $n
    $cur = Get-SoscNextItem -Items $Items -From ($Start - 1) -Step 1
    $result = $null
    $drawn = 0
    # Too tall even when compact: this throws before anything is written, so
    # the numbered question that replaces it starts on a clean screen.
    [void](Get-SoscListFrame -Items $Items -Current $cur -Checked $checked -Multi ([bool]$Multi))
    foreach ($h in $Header) { Write-SoscInfo $h }
    $console = & $script:SoscConsoleEnter
    try {
        & $script:SoscKeyFlush
        while ($null -eq $result) {
            $drawn = Invoke-SoscRender -Lines (Get-SoscListFrame -Items $Items -Current $cur -Checked $checked -Multi ([bool]$Multi)) -Previous $drawn
            $key = Read-SoscKey
            if (Test-SoscCancelKey $key) {
                $result = [pscustomobject]@{ Cancelled = $true; Index = -1; Checked = @() }
                continue
            }
            $digit = [string]$key.Char
            if (-not $Multi -and $digit -match '^[0-9]$') {
                if (Test-SoscPlainKey $key) {
                    for ($i = 0; $i -lt $n; $i++) {
                        if ($Items[$i].Hotkey -eq $digit -and -not $Items[$i].Disabled) {
                            $cur = $i
                            $result = [pscustomobject]@{ Cancelled = $false; Index = $i; Checked = @() }
                            break
                        }
                    }
                }
                continue
            }
            switch ($key.Key) {
                'UpArrow' { $cur = Get-SoscNextItem -Items $Items -From $cur -Step -1 }
                'DownArrow' { $cur = Get-SoscNextItem -Items $Items -From $cur -Step 1 }
                'Home' { $cur = Get-SoscNextItem -Items $Items -From -1 -Step 1 }
                'End' { $cur = Get-SoscNextItem -Items $Items -From $n -Step -1 }
                'Spacebar' {
                    if ($Multi -and -not $Items[$cur].Action) { $checked[$cur] = -not $checked[$cur] }
                }
                'Enter' {
                    $ticked = @(for ($i = 0; $i -lt $n; $i++) { if ($checked[$i]) { $i } })
                    if ($Multi -and -not $Items[$cur].Action) {
                        if ($ticked.Count -eq 0) { $ticked = @($cur) }
                        $result = [pscustomobject]@{ Cancelled = $false; Index = -1; Checked = $ticked }
                    }
                    else {
                        $result = [pscustomobject]@{ Cancelled = $false; Index = $cur; Checked = $ticked }
                    }
                }
            }
        }
    }
    finally {
        # The menu is replaced by one line with the choice (nothing when cancelled).
        $final = @()
        if ($null -ne $result -and -not $result.Cancelled) {
            $parts = @($result.Checked | ForEach-Object { $Items[$_].Summary })
            if ($result.Index -ge 0) {
                if ($Items[$result.Index].Quit) { $parts = @() }
                $parts += $Items[$result.Index].Summary
            }
            $final = , ([object[]]@(New-SoscSeg ($script:GlyphPointer + ' ' + [string]::Join(', ', $parts)) 'Cyan'))
        }
        try { [void](& $script:SoscMenuRenderer $final $drawn) } catch { }
        & $script:SoscConsoleExit $console
    }
    return $result
}

function Get-SoscYesNoFrame {
    param([bool]$Yes)
    $answers = @(@((T 'answer_yes'), $true), @((T 'answer_no'), $false))
    $segs = @(New-SoscSeg '  ')
    foreach ($a in $answers) {
        if ($a[1] -eq $Yes) { $segs += New-SoscSeg ($script:GlyphPointer + ' ' + $a[0]) 'Cyan' }
        else { $segs += New-SoscSeg ('  ' + $a[0]) }
        $segs += New-SoscSeg '    '
    }
    # Full: answers and help. Compact (a very low window): only the answers.
    $lines = New-Object System.Collections.Generic.List[object]
    $lines.Add([object[]]$segs)
    Add-SoscHelpLines -Lines $lines -Texts @(T 'yesno_help')
    if (Test-SoscFrameFits $lines.Count) { return , $lines.ToArray() }
    if (Test-SoscFrameFits 1) { return , @(, [object[]]$segs) }
    throw $script:SoscNoConsole
}

# Yes/No on one line. Starts on $Default; Left/Right (and Up/Down, Tab) change
# it, Enter confirms, S or Y answer yes and N no straight away. Esc (and Ctrl+C)
# always answer No: every question is asked so that No is the safe answer.
function Read-SoscYesNoMenu {
    param([string]$Question, [bool]$Default)
    $yes = $Default
    $result = $null
    $drawn = 0
    # Checked before the question is written (see Invoke-SoscListMenu).
    [void](Get-SoscYesNoFrame $yes)
    Write-SoscInfo $Question
    $console = & $script:SoscConsoleEnter
    try {
        & $script:SoscKeyFlush
        while ($null -eq $result) {
            $drawn = Invoke-SoscRender -Lines (Get-SoscYesNoFrame $yes) -Previous $drawn
            $key = Read-SoscKey
            if (Test-SoscCancelKey $key) { $result = $false; continue }
            $plain = Test-SoscPlainKey $key
            switch ($key.Key) {
                'LeftArrow' { $yes = $true }
                'RightArrow' { $yes = $false }
                'UpArrow' { $yes = -not $yes }
                'DownArrow' { $yes = -not $yes }
                'Tab' { $yes = -not $yes }
                'Enter' { $result = $yes }
                'S' { if ($plain) { $result = $true } }
                'Y' { if ($plain) { $result = $true } }
                'N' { if ($plain) { $result = $false } }
            }
        }
    }
    finally {
        $final = @()
        if ($null -ne $result) {
            $label = T 'answer_no'
            if ($result) { $label = T 'answer_yes' }
            $final = , ([object[]]@(New-SoscSeg ('  ' + $script:GlyphPointer + ' ' + $label) 'Cyan'))
        }
        try { [void](& $script:SoscMenuRenderer $final $drawn) } catch { }
        & $script:SoscConsoleExit $console
    }
    return $result
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
    param([string]$Text, [object[]]$Extra = @())
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
    foreach ($b in (@($script:InputBindings) + @($Extra))) {
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
    param([string]$Path, [string]$Kind, [object[]]$ExtraBindings = @())
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
        $block = Get-SoscInputBlock -Text $file.Text -Extra $ExtraBindings
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
    $moved = New-Object System.Collections.Generic.List[string]
    $commented = New-Object System.Collections.Generic.List[string]
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
        elseif ($key -eq 'a4k_moved') {
            # shaders-desactivados/<file>|shaders/<file>: never anything else.
            $pair = $value -split '\|'
            if ($pair.Count -eq 2 -and (Test-SoscRecordPath $pair[0]) -and (Test-SoscRecordPath $pair[1]) -and
                $pair[0].StartsWith($script:ShadersDisabledDir + '/') -and $pair[1].StartsWith($script:ShadersDir + '/')) { $moved.Add($value) }
            elseif (-not $NoWarn) { Write-SoscWarn (T 'record_bad' @($line)) }
        }
        elseif ($key -eq 'a4k_commented') {
            # Only used to recognise lines sosc turned off; checked again before use.
            if ($value -ne '' -and $value.Length -le 2000 -and $value -notmatch '[\x00-\x1f]') { $commented.Add($value) }
            elseif (-not $NoWarn) { Write-SoscWarn (T 'record_bad' @($line)) }
        }
        else { $values[$key] = $value }
    }
    return [pscustomobject]@{ Values = $values; Files = $files.ToArray(); Disabled = $disabled.ToArray(); Moved = $moved.ToArray(); Commented = $commented.ToArray() }
}

function Write-SoscRecord {
    param([string]$ConfigDir, [System.Collections.Specialized.OrderedDictionary]$Values, [string[]]$Files, [string[]]$Disabled,
        [string[]]$Moved = @(), [string[]]$Commented = @())
    $eol = "`r`n"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('# Written by the sosc installer (install/sosc.ps1). Used to update and uninstall; do not edit.' + $eol)
    foreach ($key in $Values.Keys) { [void]$sb.Append($key + '=' + $Values[$key] + $eol) }
    foreach ($d in $Disabled) { [void]$sb.Append('disabled=' + $d + $eol) }
    foreach ($m in $Moved) { [void]$sb.Append('a4k_moved=' + $m + $eol) }
    foreach ($c in $Commented) { [void]$sb.Append('a4k_commented=' + $c + $eol) }
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

# Where the sosc files come from. A release build (the markers filled in by
# tools/make-release.sh) always uses its own sosc.zip, downloaded and checked
# against its SHA256, wherever the script is: a stray portable_config next to a
# downloaded sosc.ps1 is never picked up. The repository version uses the
# portable_config of the repository copy it sits in; run on its own (iex, no
# file) it has nothing to install from and says so.
function Get-SoscSource {
    param([string]$TempDir)
    if (-not [string]::IsNullOrEmpty($script:SoscReleaseUrl)) { return (Get-SoscReleaseSource -TempDir $TempDir) }
    if ($script:SoscScriptRoot) {
        $repo = Split-Path -Path $script:SoscScriptRoot -Parent
        $config = Join-SoscPath $repo 'portable_config'
        if (Test-Path -LiteralPath (Join-SoscPath $config @('scripts', 'sosc-palettes.lua')) -PathType Leaf) {
            $commit = Get-SoscRepoCommit $repo
            return [pscustomobject]@{ ConfigDir = $config; Version = $script:SoscVersion; Commit = $commit }
        }
    }
    throw (T 'release_unpublished')
}

# Downloads the release zip into $TempDir (a fresh folder of this run, deleted by
# Invoke-SoscMain when it ends, also on failure), checks its SHA256 before
# opening it and extracts it there.
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
    # Anime4K is only downloaded when a folder needs it (Get-SoscAnime4KSource).
    return [pscustomobject]@{ UoscDir = $uoscDir; ThumbfastFile = $thumb; TempDir = $TempDir; Anime4KDir = '' }
}

# ---------------------------------------------------------------------------
# Anime4K and the graphics card
# ---------------------------------------------------------------------------

# Names of the graphics cards (Windows). Empty when they cannot be read.
function Get-SoscGpuNames {
    try {
        return @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
                ForEach-Object { [string]$_.Name } | Where-Object { $_ })
    }
    catch {
        return @()
    }
}

# Anime4K quality for one graphics card name: 'hq' (Alta) or 'fast' (Rapida).
# Pure, so the same rules can serve the macOS installer. The line comes from
# Anime4K's own mpv guide (md/GLSL_Instructions_Windows_MPV.md): its "higher-end"
# examples are GTX 1080, RTX 2070, RTX 3060, RX 590, Vega 56, 5700 XT and
# 6600 XT; its "lower-end" ones GTX 980, GTX 1060 and RX 570. When a card is not
# clearly at the level of an RTX 2070, it gets 'fast' (the user can change it).
#   hq   - NVIDIA: GTX 1080 / 1080 Ti, TITAN Xp / V / RTX / X (Pascal); RTX
#          2070 and up in the 20 series, RTX x060 and up from the 30 series on
#          (3060, 4060, 5060...); professional RTX numbered 4000 and up (Quadro
#          RTX 4000+, RTX A4000+, RTX 4000 Ada...).
#          AMD (dedicated: never "... Graphics", the name of its integrated
#          graphics): RX 590; RX 5600 and up in the 5000, 6000 and 7000 series
#          (x600+); RX 9060 and up; RX Vega 56/64 and Radeon VII.
#          Intel Arc dedicated cards with a model number of 570 and up (A580,
#          A750, A770, B570, B580); laptop ones (A...M) only from A770M.
#          Apple M Pro, Max and Ultra.
#   fast - everything else: GTX 1070, GTX 16xx, GTX 1060 and older, RTX 2060
#          (Super too), RTX x050 (3050, 4050, 5050), RTX A2000 and smaller,
#          NVIDIA MX/GT; RX 580/570 and older, RX 5500, RX 6400/6500, RX 7400;
#          AMD and Intel integrated graphics (UHD/Iris/HD, "Intel(R) Arc(TM)
#          Graphics" with no number, Arc 140V, Arc A380); Apple M base chips,
#          Intel Macs and unknown names.
function Get-SoscGpuQuality {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return 'fast' }
    if ($Name -match '(?i)\bApple\s+M\d+\s+(Pro|Max|Ultra)\b') { return 'hq' }
    if ($Name -match '(?i)NVIDIA|GeForce|Quadro|\bRTX\b|\bGTX\b|\bTITAN\b') {
        $m = [regex]::Match($Name, '(?i)\bRTX\s*(PRO\s*)?(A)?\s*(\d{3,4})(?!\d)')
        if ($m.Success) {
            $num = [int]$m.Groups[3].Value
            $pro = $m.Groups[1].Success -or $m.Groups[2].Success -or $Name -match '(?i)Quadro' -or ($num % 100) -eq 0
            if ($pro) { if ($num -ge 4000) { return 'hq' } else { return 'fast' } }
            if ($num -lt 1000) { return 'fast' }
            $series = [int][math]::Floor($num / 100)
            $tier = $num % 100
            if ($series -eq 20 -and $tier -ge 70) { return 'hq' }
            if ($series -ge 30 -and $tier -ge 60) { return 'hq' }
            return 'fast'
        }
        if ($Name -match '(?i)\bGTX\s*1080(?!\d)') { return 'hq' }
        if ($Name -match '(?i)\bTITAN\s+(Xp|V|RTX|X\s*\(Pascal\))(?![\w])') { return 'hq' }
        return 'fast'
    }
    if ($Name -match '(?i)\bIntel\b|\bArc\b') {
        $m = [regex]::Match($Name, '(?i)\bArc\b.*?\b[AB](\d{3})(M?)\b')
        if ($m.Success) {
            $num = [int]$m.Groups[1].Value
            $min = 570
            if ($m.Groups[2].Value) { $min = 770 }
            if ($num -ge $min) { return 'hq' }
        }
        return 'fast'
    }
    if ($Name -match '(?i)Radeon') {
        if ($Name -match '(?i)\bGraphics\b') { return 'fast' }
        $m = [regex]::Match($Name, '(?i)\bRX\s*(\d{3,4})(?!\d)')
        if ($m.Success) {
            $num = [int]$m.Groups[1].Value
            if ($num -lt 1000) { if ($num -ge 590 -and $num -lt 600) { return 'hq' } else { return 'fast' } }
            $series = [int][math]::Floor($num / 1000)
            if ($series -ge 5 -and $series -le 8) { $tier = [int][math]::Floor(($num % 1000) / 10) } else { $tier = $num % 100 }
            if ($tier -ge 60) { return 'hq' }
            return 'fast'
        }
        if ($Name -match '(?i)\bRX\s+Vega(\s+(56|64))?\s*$|\bVega\s+(56|64)\b|\bRadeon\s+VII\b') { return 'hq' }
        return 'fast'
    }
    return 'fast'
}

# The card that decides (the most capable one when there are several) and its
# quality. Virtual adapters (remote desktop, basic display...) are only used
# when there is nothing else.
function Get-SoscGpuTier {
    param([string[]]$Names)
    $list = @($Names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    foreach ($n in $list) {
        if ((Get-SoscGpuQuality $n) -eq 'hq') { return [pscustomobject]@{ Name = $n; Quality = 'hq' } }
    }
    $real = @($list | Where-Object { $_ -notmatch '(?i)basic|virtual|remote|parsec|mirage|displaylink|citrix|vmware|hyper-v|spacedesk|indirect' })
    $name = ''
    if ($real.Count -gt 0) { $name = $real[0] } elseif ($list.Count -gt 0) { $name = $list[0] }
    return [pscustomobject]@{ Name = $name; Quality = 'fast' }
}

# sosc-upscale.conf for "Apagado" and the given quality, byte for byte what
# sosc-upscale.lua writes for that choice (the tests compare both).
function Get-SoscUpscaleConfText {
    param([string]$Quality)
    if (@('hq', 'fast') -notcontains $Quality) { $Quality = 'fast' }
    $lines = @(
        ('# Generated by sosc-upscale.lua. Mode: off, quality: ' + $Quality),
        'script-opts-append=sosc_upscale-mode=off',
        ('script-opts-append=sosc_upscale-quality=' + $Quality)
    )
    return ([string]::Join("`n", $lines) + "`n")
}

# Writes sosc-upscale.conf when it is missing, with the quality that suits the
# graphics card; an existing one holds the user's choice and is kept.
function Initialize-SoscUpscaleConf {
    param([string]$ConfigDir, [bool]$Announce)
    $path = Join-SoscPath $ConfigDir $script:UpscaleConf
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Write-SoscInfo (T 'kept_user_file' @($script:UpscaleConf))
        return
    }
    $gpu = Get-SoscGpuTier -Names @(& $script:SoscGpuProbe)
    Write-SoscText -Path $path -Text (Get-SoscUpscaleConfText -Quality $gpu.Quality)
    if ($Announce) {
        $name = $gpu.Name
        if (-not $name) { $name = T 'gpu_unknown' }
        Write-SoscInfo (T 'gpu_line' @($name, (T ('quality_' + $gpu.Quality))))
    }
}

# AnimeJaNai brings its own AI upscaling (and uses Ctrl+1..9 for it).
function Test-SoscAnimeJaNai {
    param($Candidate, [string]$ConfigDir)
    if ($Candidate.Kind -eq 'AnimeJaNai') { return $true }
    $scripts = Join-SoscPath $ConfigDir 'scripts'
    if (Test-Path -LiteralPath $scripts -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $scripts -File -Force -Filter 'animejanai*.lua').Count -gt 0) { return $true }
    }
    return $false
}

function Test-SoscOwnShaderPath {
    param([string]$Rel)
    return ((Test-SoscRecordPath $Rel) -and $Rel -cmatch '^shaders/Anime4K_[A-Za-z0-9_]+\.glsl$')
}

# Anime4K_*.glsl files in shaders/ that sosc did not put there.
function Find-SoscManualAnime4K {
    param([string]$ConfigDir, [string[]]$Own = @())
    $dir = Join-SoscPath $ConfigDir $script:ShadersDir
    $found = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $found.ToArray() }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Force)) {
        if ($f.Name -notmatch $script:Anime4KPattern) { continue }
        if (@($Own) -contains ('shaders/' + $f.Name)) { continue }
        $found.Add($f.FullName)
    }
    return $found.ToArray()
}

# Takes the Anime4K shaders out of the verified zip into $Destination: only
# entries named like Anime4K_*.glsl at the root of the zip, nothing else.
function Expand-SoscAnime4K {
    param([string]$Zip, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-SoscDirectory $Destination
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -cnotmatch $script:Anime4KPattern) { continue }
            $out = Join-SoscPath $Destination $entry.FullName
            Assert-SoscInside -Path $out -Root $Destination
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $out, $true)
        }
    }
    finally {
        $archive.Dispose()
    }
    $missing = @($script:Anime4KRequired | Where-Object { -not (Test-Path -LiteralPath (Join-SoscPath $Destination $_) -PathType Leaf) })
    if ($missing.Count -gt 0) { throw (T 'anime4k_bad_zip' @([string]::Join(', ', $missing))) }
}

# Downloads, checks and extracts Anime4K the first time a folder needs it; the
# other folders of the same run reuse it.
function Get-SoscAnime4KSource {
    param($Artifacts)
    $cached = $Artifacts.PSObject.Properties['Anime4KDir']
    if ($null -ne $cached -and $cached.Value) { return [string]$cached.Value }
    $temp = $Artifacts.PSObject.Properties['TempDir']
    if ($null -eq $temp -or -not $temp.Value) { throw (T 'source_missing' @($script:Anime4KUrl)) }
    $zip = Join-SoscPath $temp.Value 'anime4k.zip'
    Invoke-SoscVerifiedDownload -Url $script:Anime4KUrl -Sha256 $script:Anime4KSha256 -OutFile $zip
    $dest = Join-SoscPath $temp.Value 'anime4k'
    Expand-SoscAnime4K -Zip $zip -Destination $dest
    $Artifacts | Add-Member -NotePropertyName 'Anime4KDir' -NotePropertyValue $dest -Force
    return $dest
}

# Copies the extracted shaders into <config>/shaders. Returns their record paths.
function Install-SoscAnime4KFiles {
    param([string]$ConfigDir, [string]$SourceDir)
    $dir = Join-SoscPath $ConfigDir $script:ShadersDir
    New-SoscDirectory $dir
    $rels = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -LiteralPath $SourceDir -File -Force | Sort-Object Name)) {
        if ($f.Name -cnotmatch $script:Anime4KPattern) { continue }
        $dest = Join-SoscPath $dir $f.Name
        Assert-SoscInside -Path $dest -Root $ConfigDir
        Assert-SoscNoLink -Path $dest -Root $ConfigDir
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        $rels.Add('shaders/' + $f.Name)
    }
    return $rels.ToArray()
}

# Moves a shader installed by hand into shaders-desactivados. Returns
# "moved|original" (relative), like Move-SoscToDisabled.
function Move-SoscShaderAside {
    param([string]$Path, [string]$ConfigDir, [string]$Stamp)
    Assert-SoscInside -Path $Path -Root $ConfigDir
    $rel = Get-SoscRelativePath -Path $Path -Root $ConfigDir
    $destDir = Join-SoscPath $ConfigDir $script:ShadersDisabledDir
    New-SoscDirectory $destDir
    $name = Split-Path -Path $Path -Leaf
    $dest = Join-SoscPath $destDir $name
    if (Test-Path -LiteralPath $dest) {
        $dest = Join-SoscPath $destDir ([System.IO.Path]::GetFileNameWithoutExtension($name) + '-' + $Stamp + [System.IO.Path]::GetExtension($name))
    }
    Assert-SoscInside -Path $dest -Root $ConfigDir
    Assert-SoscNoLink -Path $Path -Root $ConfigDir
    Assert-SoscNoLink -Path $dest -Root $ConfigDir
    Move-Item -LiteralPath $Path -Destination $dest
    $destRel = Get-SoscRelativePath -Path $dest -Root $ConfigDir
    Write-SoscInfo (T 'moved' @($rel, $destRel))
    return ($destRel + '|' + $rel)
}

# An input.conf line (without the sosc prefix) that binds Ctrl+0..Ctrl+6 to
# something that changes glsl-shaders, as Anime4K's templates do.
function Test-SoscAnime4KKeyLine {
    param([string]$Line)
    $c = $Line.Trim()
    if ($c -eq '' -or $c.StartsWith('#')) { return $false }
    $m = [regex]::Match($c, '^(\S+)\s+(.*)$')
    if (-not $m.Success) { return $false }
    $key = ConvertTo-SoscKeyName $m.Groups[1].Value
    if (@('ctrl+0', 'ctrl+1', 'ctrl+2', 'ctrl+3', 'ctrl+4', 'ctrl+5', 'ctrl+6') -cnotcontains $key) { return $false }
    return ($m.Groups[2].Value -match 'glsl-shaders')
}

# Those lines of input.conf, outside the sosc block: Index and Content.
function Find-SoscAnime4KKeyLines {
    param([string]$Text)
    return @(Get-SoscOutsideLines -Text $Text -Name 'input.conf' | Where-Object { Test-SoscAnime4KKeyLine $_.Content })
}

# mpv.conf lines outside the sosc block that turn mpv's own controller off.
function Find-SoscOscOffLines {
    param([string]$Text)
    return @(Get-SoscOutsideLines -Text $Text -Name 'mpv.conf' | Where-Object {
            $_.Content -match '^\s*(osc\s*=\s*"?(no|false)"?|no-osc)\s*(#.*)?$' })
}

# Rewrites some lines of a file ($Map: line index -> new content), keeping its
# encoding, BOM and every line ending.
function Update-SoscLines {
    param([string]$Path, [hashtable]$Map)
    $file = Read-SoscText $Path
    $sb = New-Object System.Text.StringBuilder
    $lines = @(Split-SoscLines $file.Text)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $content = $lines[$i].Content
        if ($Map.ContainsKey($i)) { $content = [string]$Map[$i] }
        [void]$sb.Append($content + $lines[$i].Eol)
    }
    Write-SoscText -Path $Path -Text $sb.ToString() -Encoding $file.Encoding -Bom $file.Bom
}

# Turns lines off by putting $script:CommentPrefix in front of them (never deleted).
function Set-SoscLinesCommented {
    param([string]$Path, [object[]]$Lines)
    $map = @{}
    foreach ($l in $Lines) { $map[[int]$l.Index] = $script:CommentPrefix + $l.Content }
    if ($map.Count -gt 0) { Update-SoscLines -Path $Path -Map $map }
}

# Lines sosc turned off in input.conf and recorded ($Recorded: their trimmed
# text) that are still there: Index and the original Content to put back.
function Find-SoscCommentedKeyLines {
    param([string]$Text, [string[]]$Recorded)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($l in @(Get-SoscOutsideLines -Text $Text -Name 'input.conf')) {
        if (-not $l.Content.StartsWith($script:CommentPrefix)) { continue }
        $rest = $l.Content.Substring($script:CommentPrefix.Length)
        if (@($Recorded) -ccontains $rest.Trim() -and (Test-SoscAnime4KKeyLine $rest)) {
            $out.Add([pscustomobject]@{ Index = $l.Index; Content = $rest })
        }
    }
    return $out.ToArray()
}

# Decides what to do with Anime4K in one folder and does it. Returns State
# (sosc: installed and managed by sosc; declined; manual: one installed by hand
# is left alone; animejanai), Files (record paths of sosc's shaders), Moved
# ("moved|original" of the hand-installed ones set aside), Commented (input.conf
# lines turned off) and Version.
function Invoke-SoscAnime4KStep {
    param($Candidate, [string]$ConfigDir, $Artifacts, [string]$Stamp,
        [hashtable]$OldValues, [string[]]$OldFiles = @(), [string[]]$OldMoved = @(), [string[]]$OldCommented = @())
    $choice = $script:SoscAnime4KChoice
    $prevState = ''
    if ($OldValues.ContainsKey('anime4k')) { $prevState = [string]$OldValues['anime4k'] }
    $own = @($OldFiles | Where-Object { Test-SoscOwnShaderPath $_ })
    $result = [pscustomobject]@{ State = ''; Files = $own; Moved = @($OldMoved); Commented = @($OldCommented); Version = '' }
    if ($OldValues.ContainsKey('anime4k_version')) { $result.Version = [string]$OldValues['anime4k_version'] }

    if (Test-SoscAnimeJaNai -Candidate $Candidate -ConfigDir $ConfigDir) {
        Write-SoscInfo (T 'anime4k_animejanai')
        $result.State = 'animejanai'
        return $result
    }

    $manual = @(Find-SoscManualAnime4K -ConfigDir $ConfigDir -Own $own)
    if ($manual.Count -gt 0) {
        Write-SoscWarn (T 'anime4k_manual' @($script:ShadersDir, $manual.Count))
        $manage = $false
        if ($choice -eq 'yes') { $manage = $true }
        elseif ($choice -ne 'no' -and $prevState -ne 'manual') {
            $manage = Confirm-Sosc -Question (T 'anime4k_manage' @($script:ShadersDisabledDir)) -Default $false
        }
        if (-not $manage) {
            Write-SoscWarn (T 'anime4k_manual_kept')
            $result.State = 'manual'
            return $result
        }
        $moved = New-Object System.Collections.Generic.List[string]
        foreach ($m in $result.Moved) { $moved.Add($m) }
        foreach ($p in $manual) { $moved.Add((Move-SoscShaderAside -Path $p -ConfigDir $ConfigDir -Stamp $Stamp)) }
        $result.Moved = $moved.ToArray()

        $inputPath = Join-SoscPath $ConfigDir 'input.conf'
        if (Test-Path -LiteralPath $inputPath -PathType Leaf) {
            $keys = @(Find-SoscAnime4KKeyLines (Read-SoscText $inputPath).Text)
            if ($keys.Count -gt 0) {
                Write-SoscWarn (T 'anime4k_keys_found')
                foreach ($k in $keys) { Write-SoscWarn ('  ' + $k.Content.Trim()) }
                $comment = ($choice -eq 'yes')
                if (-not $comment) { $comment = Confirm-Sosc -Question (T 'anime4k_comment') -Default $true }
                if ($comment) {
                    Set-SoscLinesCommented -Path $inputPath -Lines $keys
                    $commented = New-Object System.Collections.Generic.List[string]
                    foreach ($c in $result.Commented) { $commented.Add($c) }
                    foreach ($k in $keys) { $commented.Add($k.Content.Trim()) }
                    $result.Commented = $commented.ToArray()
                    Write-SoscInfo (T 'anime4k_commented' @($keys.Count))
                }
            }
        }
    }
    elseif ($prevState -eq 'sosc' -and $own.Count -gt 0) {
        if ($choice -eq 'no') {
            Write-SoscInfo (T 'anime4k_kept')
            $result.State = 'sosc'
            return $result
        }
    }
    else {
        $install = ($choice -eq 'yes')
        if ($choice -eq '') {
            Write-SoscInfo (T 'anime4k_intro')
            $install = Confirm-Sosc -Question (T 'anime4k_confirm') -Default ($prevState -ne 'declined')
        }
        if (-not $install) {
            Write-SoscInfo (T 'anime4k_declined')
            $result.State = 'declined'
            return $result
        }
    }

    $src = Get-SoscAnime4KSource -Artifacts $Artifacts
    $files = @(Install-SoscAnime4KFiles -ConfigDir $ConfigDir -SourceDir $src)
    # Files of an earlier Anime4K install by sosc that this one no longer has.
    foreach ($f in $own) {
        if ($files -contains $f) { continue }
        $p = Join-SoscPath $ConfigDir ($f -split '/')
        if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-SoscItem -Path $p -Root $ConfigDir }
    }
    Write-SoscOk (T 'anime4k_done' @($script:Anime4KVersion, $files.Count, $script:ShadersDir))
    $result.State = 'sosc'
    $result.Files = $files
    $result.Version = $script:Anime4KVersion
    return $result
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
    Write-SoscInfo (T 'backup_size' @([math]::Round($bytes / 1MB, 1)))
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

# Keeps the newest $Keep backups of this folder (<config>-respaldo-sosc-<stamp>,
# siblings of it) and deletes the older ones. Only folders whose name is
# exactly that pattern for this folder are considered; links are never touched.
# $Protect (the backup from before sosc's first install) is never deleted.
function Remove-SoscOldBackups {
    param([string]$ConfigDir, [int]$Keep = $script:BackupKeep, [string[]]$Protect = @())
    $full = Get-SoscFullPath $ConfigDir
    $parent = Split-Path -Path $full -Parent
    if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { return }
    $re = '^' + [regex]::Escape((Split-Path -Path $full -Leaf)) + '-respaldo-sosc-(\d{8}-\d{6})(?:-(\d+))?$'
    $found = New-Object System.Collections.Generic.List[object]
    $dirs = @()
    try { $dirs = @(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction Stop) }
    catch { Write-SoscWarn (T 'backup_prune_failed' @($parent, $_.Exception.Message)); return }
    foreach ($d in $dirs) {
        $m = [regex]::Match($d.Name, $re, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $m.Success -or (Test-SoscLink $d)) { continue }
        $n = 1
        if ($m.Groups[2].Success) { $n = [int]$m.Groups[2].Value }
        $found.Add([pscustomobject]@{ Path = $d.FullName; Stamp = $m.Groups[1].Value; N = $n })
    }
    $sorted = @($found | Sort-Object -Property @{ Expression = 'Stamp'; Descending = $true }, @{ Expression = 'N'; Descending = $true })
    for ($i = $Keep; $i -lt $sorted.Count; $i++) {
        $old = $sorted[$i].Path
        $keepIt = $false
        foreach ($p in $Protect) {
            # $Protect comes from the record, which is not trusted: a bad path just protects nothing.
            try { if ($p -and (Test-SoscSamePath $p $old)) { $keepIt = $true } } catch { }
        }
        if ($keepIt) { continue }
        try {
            Assert-SoscInside -Path $old -Root $parent
            Remove-SoscItem -Path $old -Root $parent
            Write-SoscInfo (T 'backup_pruned' @($old))
        }
        catch {
            Write-SoscWarn (T 'backup_prune_failed' @($old, $_.Exception.Message))
        }
    }
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
        $oldMoved = @()
        $oldCommented = @()
        if ($null -ne $old) {
            $oldValues = $old.Values; $oldDisabled = @($old.Disabled); $oldFiles = @($old.Files)
            $oldMoved = @($old.Moved); $oldCommented = @($old.Commented)
        }
        $first = ($null -eq $old)
        if ($backup) {
            $protect = @()
            if ($oldValues.ContainsKey('first_backup')) { $protect = @([string]$oldValues['first_backup']) }
            Remove-SoscOldBackups -ConfigDir $config -Protect $protect
        }
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
        $shadersBefore = & $prev 'shaders_preexisting' (Test-Path -LiteralPath (Join-SoscPath $config $script:ShadersDir) -PathType Container)
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
            if ($name -eq $script:UpscaleConf) { continue }
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

        # e2. Anime4K, and the upscale choice file (with the quality for this
        # graphics card when it is new).
        $a4k = Invoke-SoscAnime4KStep -Candidate $Candidate -ConfigDir $config -Artifacts $Artifacts -Stamp $Stamp `
            -OldValues $oldValues -OldFiles $oldFiles -OldMoved $oldMoved -OldCommented $oldCommented
        Initialize-SoscUpscaleConf -ConfigDir $config -Announce (@('sosc', 'manual') -contains $a4k.State)
        $a4kBindings = @()
        if ($a4k.State -eq 'sosc') { $a4kBindings = $script:Anime4KBindings }

        # g. mpv.net does not always tell thumbfast where it is.
        if (($Candidate.Kind -eq 'mpv.net' -or $Candidate.Kind -eq 'AnimeJaNai') -and $Candidate.Exe) {
            Set-SoscConfOption -Path (Join-SoscPath $opts 'thumbfast.conf') -Key 'mpv_path' -Value $Candidate.Exe `
                -Comment 'Added by the sosc installer: mpv.net does not always tell thumbfast where it is.'
            Write-SoscInfo (T 'mpvpath_set' @($Candidate.Exe))
        }

        # f. Managed blocks.
        [void](Update-SoscManagedFile -Path (Join-SoscPath $config 'mpv.conf') -Kind 'mpv')
        [void](Update-SoscManagedFile -Path (Join-SoscPath $config 'input.conf') -Kind 'input' -ExtraBindings $a4kBindings)

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
        $values['shaders_preexisting'] = ConvertTo-SoscYesNo $shadersBefore
        $values['anime4k'] = $a4k.State
        $values['anime4k_version'] = $a4k.Version
        $values['first_backup'] = $firstBackup
        $values['last_backup'] = $backup
        $allFiles = @($installed.ToArray()) + @($a4k.Files)
        Write-SoscRecord -ConfigDir $config -Values $values -Files $allFiles -Disabled $disabled.ToArray() -Moved @($a4k.Moved) -Commented @($a4k.Commented)
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

# Moves set-aside items back ("moved|original" record entries, relative to the
# folder). Entries are checked again (they come from the record, which is not
# trusted): both ends must be clean paths inside the folder, nothing is
# overwritten and links are not followed when running as administrator.
function Restore-SoscPairs {
    param([string]$ConfigDir, [string[]]$Pairs)
    foreach ($entry in $Pairs) {
        $pair = $entry -split '\|'
        if ($pair.Count -ne 2 -or -not (Test-SoscRecordPath $pair[0]) -or -not (Test-SoscRecordPath $pair[1])) {
            Write-SoscWarn (T 'record_bad' @($entry)); continue
        }
        $from = Join-SoscPath $ConfigDir ($pair[0] -split '/')
        $to = Join-SoscPath $ConfigDir ($pair[1] -split '/')
        if (-not (Test-SoscInside -Path $from -Root $ConfigDir)) { Write-SoscWarn (T 'outside_target' @($from, $ConfigDir)); continue }
        if (-not (Test-SoscInside -Path $to -Root $ConfigDir)) { Write-SoscWarn (T 'outside_target' @($to, $ConfigDir)); continue }
        if (-not (Test-Path -LiteralPath $from)) { continue }
        if (Test-Path -LiteralPath $to) { Write-SoscWarn (T 'restore_skipped' @($pair[0], $pair[1])); continue }
        Assert-SoscNoLink -Path $from -Root $ConfigDir
        Assert-SoscNoLink -Path $to -Root $ConfigDir
        New-SoscDirectory (Split-Path -Path $to -Parent)
        Move-Item -LiteralPath $from -Destination $to
        Write-SoscInfo (T 'moved' @($pair[0], $pair[1]))
    }
}

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
        $recordFiles = @()
        $movedA4k = @()
        $commentedA4k = @()
        if ($null -ne $record) {
            $values = $record.Values; $disabled = @($record.Disabled); $recordFiles = @($record.Files)
            $movedA4k = @($record.Moved); $commentedA4k = @($record.Commented)
        }
        if ($backup) {
            $protect = @()
            if ($values.ContainsKey('first_backup')) { $protect = @([string]$values['first_backup']) }
            Remove-SoscOldBackups -ConfigDir $config -Protect $protect
        }
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
        # Anime4K shaders: only the ones the record says sosc installed.
        foreach ($rel in @($recordFiles | Where-Object { Test-SoscOwnShaderPath $_ })) {
            $p = Join-SoscPath $config ($rel -split '/')
            if ((Test-SoscInside -Path $p -Root $config) -and (Test-Path -LiteralPath $p -PathType Leaf)) { Remove-SoscItem -Path $p -Root $config }
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
                Restore-SoscPairs -ConfigDir $config -Pairs $pending
            }
        }

        # Without uosc, an osc=no of the user's own leaves the player without
        # controls: offer to put back an interface, or to turn that line off.
        # With -Yes it only warns.
        $mpvConf = Join-SoscPath $config 'mpv.conf'
        if ($removeUosc -and (Test-Path -LiteralPath $mpvConf -PathType Leaf)) {
            $oscOff = @(Find-SoscOscOffLines (Read-SoscText $mpvConf).Text)
            if ($oscOff.Count -gt 0 -and @(Find-SoscConflicts $config).Count -eq 0) {
                Write-SoscWarn (T 'osc_orphan' @($oscOff[0].Content.Trim()))
                $still = @($pending | Where-Object { Test-Path -LiteralPath (Join-SoscPath $config (($_ -split '\|')[0] -split '/')) })
                if ($still.Count -gt 0) {
                    $names = [string]::Join(', ', @($still | ForEach-Object { ($_ -split '\|')[1] }))
                    if (Confirm-Sosc -Question (T 'ask_restore_osc' @($names)) -Default (-not $script:NonInteractive)) {
                        Restore-SoscPairs -ConfigDir $config -Pairs $still
                    }
                }
                if (@(Find-SoscConflicts $config).Count -eq 0) {
                    if (Confirm-Sosc -Question (T 'ask_comment_osc') -Default (-not $script:NonInteractive)) {
                        Set-SoscLinesCommented -Path $mpvConf -Lines $oscOff
                        foreach ($l in $oscOff) { Write-SoscInfo (T 'osc_commented' @($l.Content.Trim())) }
                    }
                    else { Write-SoscWarn (T 'osc_left') }
                }
            }
        }

        # Anime4K installed by hand that sosc set aside, and the input.conf
        # lines it turned off.
        if ($movedA4k.Count -gt 0) {
            if (Confirm-Sosc -Question (T 'ask_restore_anime4k' @($script:ShadersDisabledDir)) -Default $true) {
                Restore-SoscPairs -ConfigDir $config -Pairs $movedA4k
            }
        }
        $inputConf = Join-SoscPath $config 'input.conf'
        if ($commentedA4k.Count -gt 0 -and (Test-Path -LiteralPath $inputConf -PathType Leaf)) {
            $off = @(Find-SoscCommentedKeyLines -Text (Read-SoscText $inputConf).Text -Recorded $commentedA4k)
            if ($off.Count -gt 0 -and (Confirm-Sosc -Question (T 'ask_uncomment') -Default $true)) {
                $map = @{}
                foreach ($l in $off) { $map[[int]$l.Index] = $l.Content }
                Update-SoscLines -Path $inputConf -Map $map
                Write-SoscInfo (T 'uncommented' @($off.Count))
            }
        }

        $deleteChoices = $false
        if (@($script:UserChoiceFiles | Where-Object { Test-Path -LiteralPath (Join-SoscPath $config $_) -PathType Leaf }).Count -gt 0) {
            $deleteChoices = Confirm-Sosc -Question (T 'ask_delete_choices') -Default $false
            if ($deleteChoices) {
                foreach ($name in $script:UserChoiceFiles) { Remove-SoscItem -Path (Join-SoscPath $config $name) -Root $config }
            }
        }
        if ($deleteChoices -and (Test-Path -LiteralPath $mpvConf -PathType Leaf)) {
            $text = (Read-SoscText $mpvConf).Text
            foreach ($name in $script:UserChoiceFiles) {
                if ($text -match ('(?im)^\s*include\s*=.*' + [regex]::Escape($name))) { Write-SoscWarn (T 'includes_outside' @($name)) }
            }
        }

        # Folders left empty (sosc may have created them) go too; shaders only
        # when the record says sosc created it.
        $emptyDirs = @('fonts', 'script-opts', 'scripts')
        if ((& $wasThere 'shaders_preexisting') -eq $false) { $emptyDirs += $script:ShadersDir }
        foreach ($dirName in $emptyDirs) {
            $dir = Join-SoscPath $config $dirName
            $item = Get-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
            if ($null -ne $item -and $item.PSIsContainer -and -not (Test-SoscLink $item) -and
                @(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) {
                Remove-SoscItem -Path $dir -Root $config
            }
        }
        Remove-SoscItem -Path (Join-SoscPath $config $script:OriginalsDir) -Root $config
        Remove-SoscItem -Path (Join-SoscPath $config $script:RecordName) -Root $config
        foreach ($dirName in @($script:DisabledDir, $script:ShadersDisabledDir)) {
            $dir = Join-SoscPath $config $dirName
            if ((Test-Path -LiteralPath $dir -PathType Container) -and
                @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force).Count -eq 0) {
                Remove-SoscItem -Path $dir -Root $config
            }
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

function Get-SoscCandidateTags {
    param($Candidate)
    $tags = @()
    if ($Candidate.Installed -and $Candidate.Manual) { $tags += (T 'tag_manual') }
    elseif ($Candidate.Installed) { $tags += (T 'tag_installed' @($Candidate.InstalledVersion)) }
    if (-not $Candidate.Writable) { $tags += (T 'tag_readonly') }
    if (-not $Candidate.Exists) { $tags += (T 'tag_new') }
    return [string]::Join(' ', $tags)
}

function Show-SoscCandidates {
    param([object[]]$Candidates)
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $c = $Candidates[$i]
        Write-SoscInfo (' {0}) {1}  {2}' -f ($i + 1), (Get-SoscKindLabel $c.Kind), (Get-SoscCandidateTags $c))
        if ($c.Exe) { Write-SoscInfo (T 'cand_exe' @($c.Exe)) }
        Write-SoscInfo (T 'cand_config' @($c.ConfigDir))
    }
}

# The line above the list of folders ('' with no folders).
function Get-SoscTargetHeader {
    param([object[]]$List, [string]$Mode)
    if (@($List).Count -eq 0) { return '' }
    if ($Mode -eq 'uninstall') { return (T 'found_header_uninst') }
    return (T 'found_header')
}

function Write-SoscTargetHeader {
    param([object[]]$List, [string]$Mode)
    $h = Get-SoscTargetHeader -List $List -Mode $Mode
    if ($h) { Write-SoscInfo $h }
}

# Menu entry for a detected folder: player and tags, then its config folder.
function New-SoscCandidateItem {
    param($Candidate)
    $kind = Get-SoscKindLabel $Candidate.Kind
    $label = $kind
    $tags = Get-SoscCandidateTags $Candidate
    if ($tags) { $label += '  ' + $tags }
    $summary = $kind + ' (' + (Format-SoscFit -Text $Candidate.ConfigDir -Max 40 -Middle) + ')'
    return (New-SoscMenuItem -Label $label -Details @($Candidate.ConfigDir) -Summary $summary)
}

# Which folders to work on: Indexes (into $List), Other (type a folder) and
# Quit, as ConvertFrom-SoscSelection returns them. $null when the input ends.
function Read-SoscTargetChoice {
    param([object[]]$List, [string]$Mode)
    $r = Invoke-SoscMenuOrNumbers {
        $header = @(Get-SoscTargetHeader -List $List -Mode $Mode | Where-Object { $_ })
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($c in $List) { $items.Add((New-SoscCandidateItem $c)) }
        $otherIndex = $items.Count
        $items.Add((New-SoscMenuItem -Label ((Get-SoscPlainLabel (T 'opt_other')) + $script:GlyphEllipsis) -Action $true))
        $items.Add((New-SoscMenuItem -Label (Get-SoscPlainLabel (T 'opt_quit')) -Action $true -Quit $true))
        $m = Invoke-SoscListMenu -Items $items.ToArray() -Multi -Header $header
        $sel = [pscustomobject]@{ Indexes = @(); Other = $false; Quit = $false }
        if ($m.Cancelled -or ($m.Index -ge 0 -and $items[$m.Index].Quit)) { $sel.Quit = $true; return $sel }
        $sel.Indexes = @($m.Checked)
        $sel.Other = ($m.Index -eq $otherIndex)
        return $sel
    }
    if (-not (Test-SoscUseNumbers $r)) { return $r }
    while ($true) {
        Write-SoscTargetHeader -List $List -Mode $Mode
        if (@($List).Count -gt 0) { Show-SoscCandidates $List }
        Write-SoscInfo (' ' + (T 'opt_other'))
        Write-SoscInfo (' ' + (T 'opt_quit'))
        $text = Read-SoscLine (T 'select_prompt')
        if ($null -eq $text) { return $null }
        $sel = ConvertFrom-SoscSelection -Text $text -Count @($List).Count
        if ($null -ne $sel) { return $sel }
        Write-SoscWarn (T 'invalid')
    }
}

# Main menu: '1' install, '2' uninstall, '0' exit, $null when the input ends;
# anything else typed in number mode is returned as it is (invalid).
function Read-SoscMainChoice {
    $r = Invoke-SoscMenuOrNumbers {
        $labels = @((T 'menu') -split "`r?`n" | ForEach-Object { Get-SoscPlainLabel $_ })
        $items = @(
            (New-SoscMenuItem -Label $labels[0] -Hotkey '1'),
            (New-SoscMenuItem -Label $labels[1] -Hotkey '2'),
            (New-SoscMenuItem -Label $labels[2] -Quit $true -Hotkey '0')
        )
        $m = Invoke-SoscListMenu -Items $items
        if ($m.Cancelled) { return '0' }
        return @('1', '2', '0')[$m.Index]
    }
    if (-not (Test-SoscUseNumbers $r)) { return $r }
    Write-SoscInfo (T 'menu')
    return (Read-SoscLine (T 'menu_prompt'))
}

# No player found: '1' winget, '2' type a folder, '3' prepare %APPDATA%\mpv,
# '0' exit, $null when the input ends.
function Read-SoscNoPlayerChoice {
    param([bool]$HasWinget, [string]$AppMpv)
    $r = Invoke-SoscMenuOrNumbers {
        $wingetLabel = Get-SoscPlainLabel (T 'none_opt_winget')
        if (-not $HasWinget) { $wingetLabel += ' ' + (T 'none_nowinget').Trim() }
        $items = @(
            (New-SoscMenuItem -Label $wingetLabel -Disabled (-not $HasWinget) -Hotkey '1'),
            (New-SoscMenuItem -Label (Get-SoscPlainLabel (T 'none_opt_folder')) -Hotkey '2'),
            (New-SoscMenuItem -Label (Get-SoscPlainLabel (T 'none_opt_prepare' @($AppMpv))) -Disabled (-not $AppMpv) -Hotkey '3'),
            (New-SoscMenuItem -Label (Get-SoscPlainLabel (T 'opt_quit')) -Quit $true -Hotkey '0')
        )
        $m = Invoke-SoscListMenu -Items $items -Header @(T 'none_link')
        if ($m.Cancelled) { return '0' }
        return @('1', '2', '3', '0')[$m.Index]
    }
    if (-not (Test-SoscUseNumbers $r)) { return $r }
    Write-SoscInfo (T 'none_opt_winget')
    if (-not $HasWinget) { Write-SoscInfo (T 'none_nowinget') }
    Write-SoscInfo (T 'none_opt_folder')
    Write-SoscInfo (T 'none_opt_prepare' @($AppMpv))
    Write-SoscInfo (T 'opt_quit')
    Write-SoscInfo (T 'none_link')
    return (Read-SoscLine (T 'menu_prompt'))
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
        $answer = Read-SoscNoPlayerChoice -HasWinget $hasWinget -AppMpv $appMpv
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
            $sel = Read-SoscTargetChoice -List $list -Mode $Mode
            # $null: no more input (stdin closed or redirected), same as choosing Exit.
            if ($null -ne $sel -and -not $sel.Quit) {
                foreach ($i in $sel.Indexes) { $chosen.Add($list[$i]) }
                if ($sel.Other) {
                    $c = Read-SoscFolder -Env $Env -Candidates $all
                    if ($null -ne $c) { $chosen.Add($c) }
                }
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
    param([string]$Action, [string[]]$Target, [bool]$Yes, [bool]$NoMenu = $false, [string]$Anime4K = '')
    $script:NonInteractive = $Yes
    $script:SoscAnime4KChoice = $Anime4K
    # Keyboard menus only on a real interactive console; numbers otherwise.
    $script:SoscMenu = $false
    if (-not $Yes -and -not $NoMenu) { $script:SoscMenu = [bool](& $script:SoscConsoleProbe) }
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
            $answer = Read-SoscMainChoice
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

# Windows PowerShell 5.1 may need TLS 1.2 switched on for GitHub (see
# Invoke-SoscMain); that setting is process-wide, so it is put back afterwards.
$savedTls = $null
try { $savedTls = [System.Net.ServicePointManager]::SecurityProtocol } catch { }
try {
    $code = Invoke-SoscMain -Action $Action -Target $Target -Yes ([bool]$Yes) -NoMenu ([bool]$NoMenu) -Anime4K $Anime4K
}
finally {
    if ($null -ne $savedTls) { try { [System.Net.ServicePointManager]::SecurityProtocol = $savedTls } catch { } }
}
# { }.File is the file this script block was read from: set with -File or
# .\sosc.ps1, empty through iex or [scriptblock]::Create. Only a file run may
# exit: through iex, exit would close the user's PowerShell window.
if ({ }.File) { exit $code }
$global:LASTEXITCODE = $code
} -Action $SoscAction -Target $SoscTarget -Yes:$SoscYes -NoMenu:$SoscNoMenu -Anime4K $SoscAnime4K
}
catch {
    # An unexpected error that got this far. Same rule as above: exit only when
    # running from a file. No new variables here: this runs in the caller's scope.
    Write-Host ('sosc: ' + $_.Exception.Message) -ForegroundColor Red
    if ({ }.File) { exit 1 }
    $global:LASTEXITCODE = 1
}
finally {
    # Through iex the parameters above are variables of the caller's session.
    if (-not { }.File) { Remove-Variable -Name SoscAction, SoscTarget, SoscYes, SoscNoMenu, SoscAnime4K -Scope 0 -ErrorAction SilentlyContinue }
}
