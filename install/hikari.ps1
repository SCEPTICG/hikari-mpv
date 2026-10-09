<#
.SYNOPSIS
    hikari installer for Windows: mpv, mpv.net and AnimeJaNai.

.DESCRIPTION
    Installs, updates or removes hikari (https://github.com/SCEPTICG/hikari-mpv), together
    with uosc and thumbfast, in one or more mpv config folders.

    From a published release (the release's hikari.ps1 downloads that release's
    hikari.zip and checks its SHA256 before using it):
        irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1 | iex
    With options (iex cannot pass them):
        & ([scriptblock]::Create((irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1))) -Action uninstall
    From a copy of the repository, or a downloaded hikari.ps1:
        powershell -ExecutionPolicy Bypass -File install\hikari.ps1

    No administrator rights, no registry, no PATH changes. Before touching a
    folder it copies what it may change (mpv.conf, input.conf, scripts,
    script-opts, fonts and its own files) to a sibling folder named
    <config>-respaldo-hikari-<date>.

    Works with Windows PowerShell 5.1 and PowerShell 7. This file is pure ASCII on
    purpose: Windows PowerShell 5.1 reads BOM-less scripts as ANSI, so the Spanish
    messages are written with \uXXXX escapes and decoded at start-up.

    Everything runs inside one script block, invoked in a scope of its own (a
    throw-away dynamic module), so that run through iex it leaves nothing behind
    in the session: no variables, functions, StrictMode or ErrorActionPreference
    changes. It only calls exit when it runs from a file (-File, or .\hikari.ps1);
    through iex it returns and leaves its exit code in $LASTEXITCODE.

.PARAMETER HikariAction
    Use it as -Action (alias). install or uninstall. Without it a menu is
    shown.

.PARAMETER HikariTarget
    Use it as -Target (alias). mpv config folder(s) to work on (the folder that
    holds mpv.conf, e.g. ...\mpv-AnimeJaNai\portable_config or %APPDATA%\mpv).
    Several folders go separated by ';' (with -File, PowerShell does not split
    "a,b" into a list). Without it the detected players are listed.

.PARAMETER HikariYes
    Use it as -Yes (alias). Do not ask: take the default answer to every
    question. Needs -Action, and -Target when more than one folder is found.

.PARAMETER HikariNoMenu
    Use it as -NoMenu (alias). Ask with numbers and typed answers instead of
    the keyboard menus (arrows, Space, Enter, Esc). Numbers are also used on
    their own when there is no interactive console (input or output
    redirected, -NonInteractive, ISE...).

.PARAMETER HikariAnime4K
    Use it as -Anime4K (alias). yes or no: answers the Anime4K questions
    (install it; take over an Anime4K installed by hand) instead of asking.
    Without it, -Yes installs Anime4K where there is none and leaves one
    installed by hand alone. Never used for AnimeJaNai.

.NOTES
    Exit codes: 0 done (or cancelled by the user), 1 at least one folder failed,
    2 wrong usage or nothing to work on.
#>
# The parameters are named Hikari* on purpose: run through iex, a param block
# creates its variables in the caller's session, so they get names nobody else
# uses and are removed again at the end (see the finally below). The aliases
# keep the public names: -Action, -Target, -Yes, -NoMenu, -Anime4K.
[CmdletBinding()]
param(
    [Alias('Action')]
    [ValidateSet('', 'install', 'uninstall')]
    [string]$HikariAction = '',
    [Alias('Target')]
    [string[]]$HikariTarget = @(),
    [Alias('Yes')]
    [switch]$HikariYes,
    [Alias('NoMenu')]
    [switch]$HikariNoMenu,
    [Alias('Anime4K')]
    [ValidateSet('', 'yes', 'no')]
    [string]$HikariAnime4K = ''
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
# whole and exactly once each, with the tag, the URL of that release's hikari.zip
# and its SHA256. Keep them exactly as they are. In the repository they stay
# empty: the hikari files then come from the repository copy the script sits in,
# and run on its own (irm | iex) it explains that there is no release yet.
# With a URL, the hikari files always come from that zip, checked against the hash.
$script:HikariVersion = 'dev'
$script:HikariReleaseUrl = ''
$script:HikariReleaseSha256 = ''

# uosc: fixed release, verified by SHA256 before it is extracted.
$script:UoscVersion = '5.13.0'
$script:UoscUrl = 'https://github.com/tomasklaen/uosc/releases/download/5.13.0/uosc.zip'
$script:UoscSha256 = '4be9da3289285300fa374496c3f1bfd7bb20ac08e890d25bd5a06b28eebe4882'
# What uosc's own installer puts in the config folder (installers/windows.ps1),
# minus its uosc.conf: hikari ships its own.
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
$script:Anime4KPattern = '^Anime4K_[A-Za-z0-9_]+\.glsl\z'
# The shaders hikari-upscale.lua uses (its required_shaders(); the Lua tests
# compare both lists). The zip must have all of them.
$script:Anime4KRequired = @(
    'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_M.glsl', 'Anime4K_Restore_CNN_S.glsl', 'Anime4K_Restore_CNN_Soft_M.glsl',
    'Anime4K_Restore_CNN_Soft_S.glsl', 'Anime4K_Restore_CNN_Soft_VL.glsl', 'Anime4K_Restore_CNN_VL.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl', 'Anime4K_Upscale_CNN_x2_S.glsl', 'Anime4K_Upscale_CNN_x2_VL.glsl',
    'Anime4K_Upscale_Denoise_CNN_x2_M.glsl', 'Anime4K_Upscale_Denoise_CNN_x2_VL.glsl'
)
# Keys of Anime4K's official mpv templates, here driving hikari-upscale.lua.
# Only added to input.conf when hikari installed (and manages) Anime4K.
$script:Anime4KBindings = @(
    @{ Key = 'Ctrl+1'; Command = 'script-message-to hikari_upscale set-mode a' },
    @{ Key = 'Ctrl+2'; Command = 'script-message-to hikari_upscale set-mode b' },
    @{ Key = 'Ctrl+3'; Command = 'script-message-to hikari_upscale set-mode c' },
    @{ Key = 'Ctrl+4'; Command = 'script-message-to hikari_upscale set-mode aa' },
    @{ Key = 'Ctrl+5'; Command = 'script-message-to hikari_upscale set-mode bb' },
    @{ Key = 'Ctrl+6'; Command = 'script-message-to hikari_upscale set-mode ca' },
    @{ Key = 'Ctrl+7'; Command = 'script-message-to hikari_upscale set-mode auto' },
    @{ Key = 'Ctrl+0'; Command = 'script-message-to hikari_upscale set-mode off' }
)
$script:ShadersDir = 'shaders'
$script:ShadersDisabledDir = 'shaders-desactivados'
$script:UpscaleConf = 'hikari-upscale.conf'
$script:LanguageConf = 'hikari-language.conf'
# The languages of hikari in mpv: those of uosc 5.13 (script-modules/hikari-i18n.lua).
$script:MpvLanguages = @('en', 'es', 'de', 'fr', 'it', 'pl', 'pt', 'ro', 'ru', 'tr', 'uk', 'zh-HK', 'zh-hans')
# What hikari puts in front of a line of the user's it turns off (never deleted).
$script:CommentPrefix = '# hikari: '
# mpv.conf lines (outside the hikari block) of an Anime4K installed by hand that
# turn it on at start-up, as Anime4K's official templates do.
$script:Anime4KConfPattern = '^\s*glsl-shaders(-append|-set|-add)?\s*=.*Anime4K_'
# File inside the backup made before hikari's first install: that backup is never
# deleted by the rotation, even when no record names it any more.
$script:BackupOriginalMark = 'hikari-backup-original.txt'
# Backups of one folder that are kept (plus the one from before the first install).
$script:BackupKeep = 3
# -Anime4K: '' (ask; -Yes takes the default answers), 'yes' or 'no'.
$script:HikariAnime4KChoice = ''

# Downloads are only allowed over HTTPS from these hosts.
$script:AllowedHosts = @('github.com', 'raw.githubusercontent.com')

$script:BlockBegin = '# >>> hikari (managed block, do not edit) >>>'
$script:BlockEnd = '# <<< hikari <<<'

$script:MpvConfLines = @(
    'osc=no',
    'osd-bar=no',
    'include="~~/hikari-palette.conf"',
    'include="~~/hikari-subs.conf"',
    'include="~~/hikari-upscale.conf"',
    'include="~~/hikari-language.conf"'
)

$script:InputBindings = @(
    @{ Key = 'Alt+p'; Command = 'script-binding hikari_palettes/open-menu' },
    @{ Key = 'Alt+s'; Command = 'script-binding hikari_skip/skip' },
    @{ Key = 'Alt+t'; Command = 'script-binding hikari_subs/open-menu' },
    @{ Key = 'Alt+u'; Command = 'script-binding hikari_update/open-menu' },
    @{ Key = 'Alt+l'; Command = 'script-binding hikari_language/open-menu' }
)

# Files of hikari that only get copied when missing: they hold the user's choices.
# hikari-upscale.conf (with the quality that suits the graphics card) and
# hikari-language.conf (with the system language) are written by the installer
# itself, the others are copied from the hikari files.
$script:UserChoiceFiles = @('hikari-palette.conf', 'hikari-subs.conf', 'hikari-upscale.conf', 'hikari-language.conf')

# script-opts that are not named hikari-*: removed on uninstall only if hikari put them there.
$script:SharedConfs = @('uosc.conf', 'thumbfast.conf')

$script:RecordName = 'hikari-installed.txt'
# What hikari-update.lua saves (last check, latest version, dismissed one):
# state, not a choice. Kept on update, removed on uninstall like the record.
$script:UpdateState = 'hikari-update.txt'
$script:DisabledDir = 'scripts-desactivados'
$script:OriginalsDir = 'hikari-originales'

# hikari was called sosc until v0.3.0. These names are only used to recognise an
# installation of sosc and carry it over to hikari (Invoke-HikariSoscMigration).
$script:SoscRecordName = 'sosc-installed.txt'
$script:SoscBlockBegin = '# >>> sosc (managed block, do not edit) >>>'
$script:SoscBlockEnd = '# <<< sosc <<<'
$script:SoscCommentPrefix = '# sosc: '
$script:SoscOriginalsDir = 'sosc-originales'
$script:SoscUpdateState = 'sosc-update.txt'
# The part after sosc- of its choice files (sosc-<name>.conf).
$script:SoscChoices = @('palette', 'subs', 'upscale')
# Names of its scripts (sosc_<name> in input.conf, sosc-<name> in options).
$script:SoscScripts = @('palettes', 'palette', 'skip', 'subs', 'speed', 'upscale', 'update', 'title')
# What sosc 0.3.0 installed: scripts\sosc-<name>.lua and script-opts\sosc-<name>.conf.
# Only these are recognised and removed (a sosc-other.lua of someone else stays).
$script:SoscLuaFiles = @('palettes', 'skip', 'speed', 'subs', 'title', 'update', 'upscale')
$script:SoscConfFiles = @('skip', 'title', 'update')

# What the backup copies: only what the installer can change (and the files of
# sosc, which a migration changes). cache,
# watch_later and anything else in the folder are never touched, so not copied.
# shaders is not copied either: hikari only adds and removes its own Anime4K
# files there, and moves (never deletes) an Anime4K installed by hand to
# shaders-desactivados, which is copied.
$script:BackupItems = @(
    'mpv.conf', 'input.conf', 'scripts', 'script-opts', 'script-modules', 'fonts',
    'hikari-palette.conf', 'hikari-subs.conf', 'hikari-upscale.conf', 'hikari-language.conf', 'hikari-installed.txt',
    'scripts-desactivados', 'hikari-originales', 'shaders-desactivados',
    'sosc-palette.conf', 'sosc-subs.conf', 'sosc-upscale.conf', 'sosc-installed.txt', 'sosc-originales', 'sosc-update.txt'
)

# Signs that a folder belongs to mpv (any of them is enough).
$script:MpvConfigFiles = @('mpv.conf', 'input.conf', 'hikari-installed.txt', 'hikari-palette.conf', 'hikari-subs.conf', 'hikari-upscale.conf', 'hikari-language.conf')
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
$script:HikariScriptRoot = $PSScriptRoot
$script:HikariQuiet = $false
$script:NonInteractive = $false
# Set when running as administrator: deleting or moving then refuses paths that
# go through a link (junction or symbolic link) inside the config folder.
$script:HikariElevated = $false
$script:HikariWarnings = New-Object System.Collections.Generic.List[string]

# Names of the graphics cards, replaceable in tests (returns a list of names).
$script:HikariGpuProbe = { Get-HikariGpuNames }

# The Windows display language (de-DE, zh-Hant-TW...), replaceable in tests.
# The regional format (Get-Culture) only when the display language is unknown.
$script:HikariUiCultureProbe = {
    $name = ''
    try { $name = (Get-UICulture).Name } catch { }
    if (-not $name) { try { $name = (Get-Culture).Name } catch { } }
    return [string]$name
}

# Download function, replaceable in tests: param($Url, $OutFile).
$script:HikariDownloader = {
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

$script:HikariStringsEn = @{
    title                 = 'hikari installer'
    menu                  = "1) Install or update`n2) Uninstall`n0) Exit"
    menu_prompt           = 'Choose an option'
    invalid               = 'Invalid option.'
    detecting             = 'Looking for mpv players...'
    found_header          = 'Players and config folders found:'
    found_header_uninst   = 'Folders with hikari:'
    cand_exe              = '     Player: {0}'
    cand_config           = '     Config: {0}'
    kind_folder           = 'config folder'
    tag_installed         = '[hikari {0} installed]'
    tag_manual            = '[hikari files present, no installer record]'
    tag_readonly          = '[no write permission]'
    tag_new               = '[will be created]'
    opt_other             = 'O) Other folder'
    opt_quit              = '0) Exit'
    select_prompt         = 'Choose one or more, separated by commas (e.g. 1,3)'
    ask_folder            = 'Full path of the mpv config folder (where mpv.conf is or should go)'
    folder_missing        = 'The folder {0} does not exist and neither does its parent.'
    readonly_warn         = 'Cannot write to {0}.'
    readonly_offer        = 'Use {0} instead?'
    readonly_portable     = 'Careful: while {0} exists, this player only reads that folder and will not see hikari in {1}.'
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
    backup_size           = 'Backing up the files hikari touches ({0} MB)...'
    backup_failed         = 'Could not back up {0}: {1}. Nothing was changed in that folder.'
    conflicts_found       = 'These scripts replace the mpv controls and clash with uosc:'
    conflicts_confirm     = 'Move them to {0}? Nothing is deleted.'
    conflicts_kept        = 'Left in place: uosc and that interface will both draw controls.'
    moved                 = 'Moved {0} -> {1}'
    downloading           = 'Downloading {0}...'
    hash_bad              = 'The download of {0} does not match its expected SHA256 (expected {1}, got {2}). Nothing was installed from it.'
    url_bad               = 'Refusing to download {0}: only HTTPS from GitHub is allowed.'
    release_unpublished   = 'hikari has no published release yet, so this installer cannot run on its own. Download the repository and run install\hikari.ps1 from that copy.'
    source_missing        = 'hikari files not found in {0}.'
    installing_to         = 'Installing hikari into {0}'
    uosc_done             = 'uosc {0} installed.'
    thumbfast_done        = 'thumbfast installed.'
    hikari_files_done     = 'hikari files copied ({0}).'
    kept_user_file        = '{0} already exists: kept (it holds your choice).'
    language_set          = 'hikari language in mpv: {0} (the system''s; change it in mpv with Alt+l).'
    removed_stale         = 'Removed old hikari file {0}.'
    mpvpath_set           = 'thumbfast.conf: mpv_path={0}'
    block_updated         = '{0}: hikari block written.'
    default_section       = '{0} ends inside a [profile]: the hikari block starts with [default] so its options apply to every file.'
    key_taken             = '{0} is already bound in input.conf ({1}). hikari leaves it alone; bind another key to "{2}" if you want.'
    key_same              = '{0} already runs "{1}" in your input.conf: left as it is.'
    install_ok            = 'hikari installed in {0}.'
    target_failed         = '{0}: {1}'
    restore_hint          = 'Your previous config is in {0}.'
    summary               = 'Done: {0} of {1} folders.'
    restart               = 'Restart the player to see the changes.'
    uninstalling_from     = 'Removing hikari from {0}'
    ask_remove_uosc       = 'Remove uosc too?'
    ask_remove_thumbfast  = 'Remove thumbfast too?'
    ask_restore           = 'Move back the interfaces hikari set aside ({0})?'
    ask_delete_choices    = 'Delete your saved palette, subtitle, upscaling and language choices (hikari-palette.conf, hikari-subs.conf, hikari-upscale.conf, hikari-language.conf)?'
    restore_skipped       = '{0} not moved back: {1} already exists.'
    conf_restored         = '{0}: your version from before hikari was put back.'
    conf_left             = '{0} was there before hikari and is left as it is now. Your earlier version is in {1}.'
    conf_unknown          = '{0} left in place (no installer record says who put it there).'
    includes_outside      = 'mpv.conf still includes {0} outside the hikari block: remove that line, or mpv will log an error at start-up.'
    uninstall_ok          = 'hikari removed from {0}.'
    nothing_to_uninstall  = 'hikari does not seem to be installed in any detected folder.'
    usage_yes_action      = '-Yes needs -Action install or -Action uninstall.'
    usage_many            = 'Several folders found; with -Yes, choose with -Target:'
    usage_none            = 'Nothing to work on.'
    error_generic         = 'Error: {0}'
    malformed_block       = '{0} has an incomplete or repeated hikari block (a start or end marker is missing). Fix it by hand and run the installer again.'
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
    record_bad            = 'Ignored an invalid entry in hikari-installed.txt: {0}'
    menu_help             = '\u2191/\u2193 to move \u00b7 Enter to choose \u00b7 Esc to exit'
    multi_help            = '\u2191/\u2193 to move \u00b7 Space to tick or untick \u00b7 Esc to exit'
    multi_help2           = 'Enter to confirm (with nothing ticked, the highlighted one is chosen)'
    yesno_help            = '\u2190/\u2192 to change \u00b7 Enter to confirm \u00b7 Y/N \u00b7 Esc = No'
    menu_help_short       = '\u2191/\u2193 \u00b7 Enter \u00b7 Esc'
    multi_help_short      = '\u2191/\u2193 \u00b7 Space \u00b7 Enter \u00b7 Esc'
    answer_yes            = 'Yes'
    answer_no             = 'No'
    anime4k_intro         = 'Anime4K sharpens and upscales anime on the graphics card. It starts in Autom\u00e1tico mode, which picks a mode from the resolution of each video; change it in the Escalado menu or with Ctrl+1 to Ctrl+7 (Ctrl+0 turns it off).'
    anime4k_confirm       = 'Install Anime4K (anime upscaling on the graphics card)?'
    anime4k_done          = 'Anime4K {0} installed ({1} shaders in {2}).'
    anime4k_animejanai    = 'AnimeJaNai already upscales with AI (Ctrl+1 to Ctrl+9): Anime4K is not installed here.'
    anime4k_declined      = 'Anime4K not installed. Run the installer again to install it.'
    anime4k_kept          = 'Anime4K left as it is (-Anime4K no).'
    anime4k_manual        = 'There is already an Anime4K installed by hand in {0} (files: {1}).'
    anime4k_manage        = 'Let hikari take care of it? Your files go to {0} (nothing is deleted, they come back on uninstall) and hikari installs its own copy, with the Escalado menu and the Ctrl+0 to Ctrl+7 keys.'
    anime4k_manual_kept   = 'Your Anime4K is left as it is, with its own keys. The hikari Escalado menu changes the same shaders and does not know what those keys turned on.'
    anime4k_keys_found    = 'input.conf binds these Anime4K keys outside the hikari block:'
    anime4k_comment       = 'Turn those lines off by putting "# hikari: " in front of them, so the hikari keys can use them? They are turned back on when you uninstall.'
    anime4k_commented     = 'input.conf: lines turned off with "# hikari: ": {0}.'
    anime4k_bad_zip       = 'The Anime4K download does not have the shaders hikari needs ({0}).'
    anime4k_conf_found    = 'mpv.conf turns Anime4K on at start-up outside the hikari block:'
    anime4k_conf_comment  = 'Turn those lines off by putting "# hikari: " in front of them? Otherwise Anime4K would always be on, even with Apagado. They are turned back on when you uninstall.'
    anime4k_conf_commented = 'mpv.conf: lines turned off with "# hikari: ": {0}.'
    anime4k_failed        = 'Could not get Anime4K: {0} The rest of hikari is installed; run the installer again to install Anime4K.'
    anime4k_uptodate      = 'Anime4K {0} is already installed, with every shader hikari needs.'
    ask_uncomment_conf    = 'Turn your Anime4K lines in mpv.conf back on?'
    uncommented_conf      = 'mpv.conf: lines turned back on: {0}.'
    backup_original_note  = 'This backup holds the mpv configuration from before hikari was first installed here. The hikari installer never deletes it.'
    gpu_line              = 'Graphics card: {0} \u2192 quality {1}'
    gpu_unknown           = 'unknown'
    quality_hq            = 'High'
    quality_fast          = 'Fast'
    backup_pruned         = 'Old backup deleted: {0}'
    backup_prune_failed   = 'Could not delete the old backup {0}: {1}'
    ask_restore_anime4k   = 'Move your earlier Anime4K back from {0}?'
    ask_uncomment         = 'Turn your Anime4K keys in input.conf back on?'
    uncommented           = 'input.conf: lines turned back on: {0}.'
    osc_orphan            = 'mpv.conf has "{0}" outside the hikari block: without uosc the player would have no on-screen controls.'
    ask_restore_osc       = 'Move back the interfaces hikari set aside ({0}), so there are controls?'
    ask_comment_osc       = 'Turn that line off by putting "# hikari: " in front of it, so mpv shows its own controls?'
    osc_commented         = 'mpv.conf: "{0}" turned off with "# hikari: ".'
    osc_left              = 'Left as it is: remove that line or install an on-screen controller to get controls back.'
    broken_found          = 'These files in scripts are not scripts but the error page of a failed download (mpv logs an error for each one):'
    broken_confirm        = 'Move them to {0}? Nothing is deleted, and they come back when you uninstall.'
    broken_kept           = 'Left in place: mpv keeps logging an error for each one at start-up.'
    ask_restore_broken    = 'Move back the broken scripts hikari set aside ({0})?'
    tag_sosc              = '[sosc installed: it becomes hikari]'
    sosc_found            = 'sosc is installed here (the name of hikari until v0.3.0): it becomes hikari, with your choices.'
    sosc_line_changed     = '{0}: line of yours changed from sosc to hikari: {1}'
    sosc_choice_moved     = '{0} -> {1} (your choice is kept).'
    sosc_done             = 'sosc removed: hikari takes its place. Uninstalling hikari puts everything back as it was before sosc.'
    sosc_old_backups      = 'There are {0} old sosc backups ({1}-respaldo-sosc-*). They are not deleted: delete them yourself when you no longer need them.'
    sosc_link_left        = 'Left as it is: {0} is a link (junction or symbolic link), nothing is written or moved through it.'
}

$script:HikariStringsEs = @{
    title                 = 'Instalador de hikari'
    menu                  = '1) Instalar o actualizar\n2) Desinstalar\n0) Salir'
    menu_prompt           = 'Elige una opci\u00f3n'
    invalid               = 'Opci\u00f3n no v\u00e1lida.'
    detecting             = 'Buscando reproductores de mpv...'
    found_header          = 'Reproductores y carpetas de configuraci\u00f3n encontrados:'
    found_header_uninst   = 'Carpetas con hikari:'
    cand_exe              = '     Reproductor: {0}'
    cand_config           = '     Configuraci\u00f3n: {0}'
    kind_folder           = 'carpeta de configuraci\u00f3n'
    tag_installed         = '[hikari {0} instalado]'
    tag_manual            = '[hay ficheros de hikari, sin registro del instalador]'
    tag_readonly          = '[sin permiso de escritura]'
    tag_new               = '[se crear\u00e1]'
    opt_other             = 'O) Otra carpeta'
    opt_quit              = '0) Salir'
    select_prompt         = 'Elige uno o varios separados por comas (p. ej. 1,3)'
    ask_folder            = 'Ruta completa de la carpeta de configuraci\u00f3n de mpv (donde est\u00e1 o ir\u00e1 mpv.conf)'
    folder_missing        = 'No existe la carpeta {0} ni la que la contiene.'
    readonly_warn         = 'No se puede escribir en {0}.'
    readonly_offer        = '\u00bfUsar {0} en su lugar?'
    readonly_portable     = 'Ojo: mientras exista {0}, este reproductor solo lee esa carpeta y no ver\u00e1 hikari en {1}.'
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
    backup_size           = 'Copia de seguridad de los ficheros que toca hikari ({0} MB)...'
    backup_failed         = 'No se ha podido hacer la copia de seguridad de {0}: {1}. No se ha cambiado nada en esa carpeta.'
    conflicts_found       = 'Estos scripts sustituyen los controles de mpv y chocan con uosc:'
    conflicts_confirm     = '\u00bfMoverlos a {0}? No se borra nada.'
    conflicts_kept        = 'Se quedan donde est\u00e1n: uosc y esa interfaz dibujar\u00e1n controles a la vez.'
    moved                 = 'Movido {0} -> {1}'
    downloading           = 'Descargando {0}...'
    hash_bad              = 'La descarga de {0} no coincide con su SHA256 esperado (esperado {1}, obtenido {2}). No se ha instalado nada de ella.'
    url_bad               = 'No se descarga {0}: solo se admite HTTPS desde GitHub.'
    release_unpublished   = 'hikari a\u00fan no tiene ninguna versi\u00f3n publicada, as\u00ed que este instalador no puede funcionar suelto. Descarga el repositorio y ejecuta install\\hikari.ps1 desde esa copia.'
    source_missing        = 'No se encuentran los ficheros de hikari en {0}.'
    installing_to         = 'Instalando hikari en {0}'
    uosc_done             = 'uosc {0} instalado.'
    thumbfast_done        = 'thumbfast instalado.'
    hikari_files_done     = 'Ficheros de hikari copiados ({0}).'
    kept_user_file        = '{0} ya existe: se conserva (guarda tu elecci\u00f3n).'
    language_set          = 'Idioma de hikari en mpv: {0} (el del sistema; c\u00e1mbialo en mpv con Alt+l).'
    removed_stale         = 'Borrado el fichero antiguo de hikari {0}.'
    mpvpath_set           = 'thumbfast.conf: mpv_path={0}'
    block_updated         = '{0}: bloque de hikari escrito.'
    default_section       = '{0} termina dentro de un [perfil]: el bloque de hikari empieza con [default] para que sus opciones valgan siempre.'
    key_taken             = '{0} ya est\u00e1 asignada en input.conf ({1}). hikari no la toca; si quieres, asigna otra tecla a "{2}".'
    key_same              = '{0} ya ejecuta "{1}" en tu input.conf: se deja como est\u00e1.'
    install_ok            = 'hikari instalado en {0}.'
    target_failed         = '{0}: {1}'
    restore_hint          = 'Tu configuraci\u00f3n anterior est\u00e1 en {0}.'
    summary               = 'Hecho: {0} de {1} carpetas.'
    restart               = 'Reinicia el reproductor para ver los cambios.'
    uninstalling_from     = 'Quitando hikari de {0}'
    ask_remove_uosc       = '\u00bfQuitar tambi\u00e9n uosc?'
    ask_remove_thumbfast  = '\u00bfQuitar tambi\u00e9n thumbfast?'
    ask_restore           = '\u00bfDevolver a su sitio las interfaces que hikari apart\u00f3 ({0})?'
    ask_delete_choices    = '\u00bfBorrar tus elecciones guardadas de paleta, subt\u00edtulos, escalado e idioma (hikari-palette.conf, hikari-subs.conf, hikari-upscale.conf, hikari-language.conf)?'
    restore_skipped       = '{0} no se devuelve: ya existe {1}.'
    conf_restored         = '{0}: se ha devuelto tu versi\u00f3n de antes de hikari.'
    conf_left             = '{0} ya exist\u00eda antes de hikari y se deja como est\u00e1 ahora. Tu versi\u00f3n anterior est\u00e1 en {1}.'
    conf_unknown          = '{0} se deja en su sitio (no hay registro del instalador que diga qui\u00e9n lo puso).'
    includes_outside      = 'mpv.conf sigue incluyendo {0} fuera del bloque de hikari: quita esa l\u00ednea o mpv dar\u00e1 un error al arrancar.'
    uninstall_ok          = 'hikari quitado de {0}.'
    nothing_to_uninstall  = 'No parece que hikari est\u00e9 instalado en ninguna de las carpetas encontradas.'
    usage_yes_action      = '-Yes necesita -Action install o -Action uninstall.'
    usage_many            = 'Hay varias carpetas; con -Yes, elige con -Target:'
    usage_none            = 'No hay nada sobre lo que trabajar.'
    error_generic         = 'Error: {0}'
    malformed_block       = '{0} tiene un bloque de hikari incompleto o repetido (falta una marca de inicio o de fin). Arr\u00e9glalo a mano y vuelve a ejecutar el instalador.'
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
    record_bad            = 'Se ignora una entrada no v\u00e1lida de hikari-installed.txt: {0}'
    menu_help             = '\u2191/\u2193 para moverte \u00b7 Intro para elegir \u00b7 Esc para salir'
    multi_help            = '\u2191/\u2193 para moverte \u00b7 Espacio para marcar o desmarcar \u00b7 Esc para salir'
    multi_help2           = 'Intro para confirmar (si no marcas ninguna, se elige la resaltada)'
    yesno_help            = '\u2190/\u2192 para cambiar \u00b7 Intro para confirmar \u00b7 S/N \u00b7 Esc = No'
    menu_help_short       = '\u2191/\u2193 \u00b7 Intro \u00b7 Esc'
    multi_help_short      = '\u2191/\u2193 \u00b7 Espacio \u00b7 Intro \u00b7 Esc'
    answer_yes            = 'S\u00ed'
    answer_no             = 'No'
    anime4k_intro         = 'Anime4K mejora y reescala el anime en la tarjeta gr\u00e1fica. Empieza en modo Autom\u00e1tico, que elige el modo seg\u00fan la resoluci\u00f3n de cada v\u00eddeo; c\u00e1mbialo en el men\u00fa Escalado o con Ctrl+1 a Ctrl+7 (Ctrl+0 lo apaga).'
    anime4k_confirm       = '\u00bfInstalar Anime4K (reescalado de anime en la gr\u00e1fica)?'
    anime4k_done          = 'Anime4K {0} instalado ({1} shaders en {2}).'
    anime4k_animejanai    = 'AnimeJaNai ya reescala con IA (Ctrl+1 a Ctrl+9): aqu\u00ed no se instala Anime4K.'
    anime4k_declined      = 'Anime4K no se instala. Vuelve a ejecutar el instalador para instalarlo.'
    anime4k_kept          = 'Anime4K se deja como est\u00e1 (-Anime4K no).'
    anime4k_manual        = 'Ya hay un Anime4K instalado a mano en {0} (ficheros: {1}).'
    anime4k_manage        = '\u00bfQuieres que lo gestione hikari? Tus ficheros van a {0} (no se borra nada y vuelven al desinstalar) y hikari instala su propia copia, con el men\u00fa Escalado y los atajos Ctrl+0 a Ctrl+7.'
    anime4k_manual_kept   = 'Tu Anime4K se queda como est\u00e1, con sus atajos. El men\u00fa Escalado de hikari cambia los mismos shaders y no sabe lo que hayan activado esos atajos.'
    anime4k_keys_found    = 'input.conf tiene estos atajos de Anime4K fuera del bloque de hikari:'
    anime4k_comment       = '\u00bfDesactivar esas l\u00edneas poni\u00e9ndoles delante "# hikari: ", para que los atajos de hikari puedan usar esas teclas? Se vuelven a activar al desinstalar.'
    anime4k_commented     = 'input.conf: l\u00edneas desactivadas con "# hikari: ": {0}.'
    anime4k_bad_zip       = 'La descarga de Anime4K no tiene los shaders que necesita hikari ({0}).'
    anime4k_conf_found    = 'mpv.conf enciende Anime4K al arrancar fuera del bloque de hikari:'
    anime4k_conf_comment  = '\u00bfDesactivar esas l\u00edneas poni\u00e9ndoles delante "# hikari: "? Si no, Anime4K estar\u00eda siempre encendido, incluso con Apagado. Se vuelven a activar al desinstalar.'
    anime4k_conf_commented = 'mpv.conf: l\u00edneas desactivadas con "# hikari: ": {0}.'
    anime4k_failed        = 'No se ha podido obtener Anime4K: {0} El resto de hikari se instala; vuelve a ejecutar el instalador para instalar Anime4K.'
    anime4k_uptodate      = 'Anime4K {0} ya est\u00e1 instalado, con todos los shaders que necesita hikari.'
    ask_uncomment_conf    = '\u00bfVolver a activar tus l\u00edneas de Anime4K de mpv.conf?'
    uncommented_conf      = 'mpv.conf: l\u00edneas activadas de nuevo: {0}.'
    backup_original_note  = 'Esta copia guarda la configuraci\u00f3n de mpv de antes de la primera instalaci\u00f3n de hikari en esta carpeta. El instalador de hikari nunca la borra.'
    gpu_line              = 'Gr\u00e1fica: {0} \u2192 calidad {1}'
    gpu_unknown           = 'desconocida'
    quality_hq            = 'Alta'
    quality_fast          = 'R\u00e1pida'
    backup_pruned         = 'Borrada la copia de seguridad antigua {0}'
    backup_prune_failed   = 'No se ha podido borrar la copia de seguridad antigua {0}: {1}'
    ask_restore_anime4k   = '\u00bfDevolver a su sitio tu Anime4K anterior, que est\u00e1 en {0}?'
    ask_uncomment         = '\u00bfVolver a activar tus atajos de Anime4K de input.conf?'
    uncommented           = 'input.conf: l\u00edneas activadas de nuevo: {0}.'
    osc_orphan            = 'mpv.conf tiene "{0}" fuera del bloque de hikari: sin uosc, el reproductor se quedar\u00eda sin controles en pantalla.'
    ask_restore_osc       = '\u00bfDevolver a su sitio las interfaces que hikari apart\u00f3 ({0}), para tener controles?'
    ask_comment_osc       = '\u00bfDesactivar esa l\u00ednea poni\u00e9ndole delante "# hikari: ", para que mpv muestre sus propios controles?'
    osc_commented         = 'mpv.conf: "{0}" desactivada con "# hikari: ".'
    osc_left              = 'Se deja como est\u00e1: quita esa l\u00ednea o instala otra interfaz para recuperar los controles.'
    broken_found          = 'Estos ficheros de scripts no son scripts sino la p\u00e1gina de error de una descarga fallida (mpv da un error por cada uno):'
    broken_confirm        = '\u00bfMoverlos a {0}? No se borra nada y vuelven a su sitio al desinstalar.'
    broken_kept           = 'Se quedan donde est\u00e1n: mpv sigue dando un error por cada uno al arrancar.'
    ask_restore_broken    = '\u00bfDevolver a su sitio los scripts rotos que hikari apart\u00f3 ({0})?'
    tag_sosc              = '[sosc instalado: pasa a ser hikari]'
    sosc_found            = 'Aqu\u00ed est\u00e1 instalado sosc (el nombre de hikari hasta la v0.3.0): pasa a ser hikari, con tus elecciones.'
    sosc_line_changed     = '{0}: l\u00ednea tuya cambiada de sosc a hikari: {1}'
    sosc_choice_moved     = '{0} -> {1} (se conserva tu elecci\u00f3n).'
    sosc_done             = 'sosc quitado: hikari ocupa su lugar. Al desinstalar hikari todo vuelve a como estaba antes de sosc.'
    sosc_old_backups      = 'Hay {0} copias de seguridad antiguas de sosc ({1}-respaldo-sosc-*). No se borran: b\u00f3rralas t\u00fa cuando ya no te hagan falta.'
    sosc_link_left        = 'Se deja como est\u00e1: {0} es un enlace (uni\u00f3n o enlace simb\u00f3lico), no se escribe ni se mueve nada a trav\u00e9s de \u00e9l.'
}

function Get-HikariLanguage {
    if ($env:HIKARI_LANG -eq 'es' -or $env:HIKARI_LANG -eq 'en') { return $env:HIKARI_LANG }
    try {
        if ((Get-Culture).TwoLetterISOLanguageName -eq 'es') { return 'es' }
    }
    catch { }
    return 'en'
}

function Set-HikariLanguage {
    param([string]$Language)
    $script:HikariLang = $Language
    $script:HikariStrings = @{}
    if ($Language -eq 'es') {
        foreach ($key in $script:HikariStringsEs.Keys) {
            $script:HikariStrings[$key] = [regex]::Unescape($script:HikariStringsEs[$key])
        }
    }
    else {
        # Only \uXXXX is decoded here: English strings hold real backslashes
        # (install\hikari.ps1) that [regex]::Unescape would reject.
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) }
        foreach ($key in $script:HikariStringsEn.Keys) {
            $script:HikariStrings[$key] = [regex]::Replace($script:HikariStringsEn[$key], '\\u([0-9A-Fa-f]{4})', $evaluator)
        }
    }
}

function T {
    param([string]$Key, [object[]]$FormatArgs = @())
    $text = $script:HikariStrings[$Key]
    if ($null -eq $text) { $text = $Key }
    if (@($FormatArgs).Count -gt 0) { return ($text -f $FormatArgs) }
    return $text
}

Set-HikariLanguage (Get-HikariLanguage)

# ---------------------------------------------------------------------------
# Output and input (replaceable in tests)
# ---------------------------------------------------------------------------

function Write-HikariInfo {
    param([string]$Message)
    if (-not $script:HikariQuiet) { Write-Host $Message }
}

function Write-HikariOk {
    param([string]$Message)
    if (-not $script:HikariQuiet) { Write-Host $Message -ForegroundColor Green }
}

function Write-HikariWarn {
    param([string]$Message)
    $script:HikariWarnings.Add($Message)
    if (-not $script:HikariQuiet) { Write-Host $Message -ForegroundColor Yellow }
}

function Write-HikariError {
    param([string]$Message)
    if (-not $script:HikariQuiet) { Write-Host $Message -ForegroundColor Red }
}

function Read-HikariLine {
    param([string]$Prompt)
    return (Read-Host -Prompt $Prompt)
}

function Confirm-Hikari {
    param([string]$Question, [bool]$Default)
    if ($script:NonInteractive) { return $Default }
    $r = Invoke-HikariMenuOrNumbers { Read-HikariYesNoMenu -Question $Question -Default $Default }
    if (-not (Test-HikariUseNumbers $r)) { return [bool]$r }
    $suffix = T 'yes_no_default_no'
    if ($Default) { $suffix = T 'yes_no_default_yes' }
    while ($true) {
        $answer = Read-HikariLine ($Question + $suffix)
        if ($null -eq $answer) { return $Default }
        $answer = $answer.Trim().ToLowerInvariant()
        if ($answer -eq '') { return $Default }
        if (@('s', 'si', 'y', 'yes') -contains $answer -or $answer -eq ('s' + [char]0x00ED)) { return $true }
        if (@('n', 'no') -contains $answer) { return $false }
        Write-HikariWarn (T 'invalid')
    }
}

# ---------------------------------------------------------------------------
# Keyboard menus: arrows, Space, Enter and Esc. When the console cannot do them
# (input or output redirected, -NonInteractive, ISE, ReadKey failing) or with
# -NoMenu, the questions are asked with numbers and typed answers instead.
# ---------------------------------------------------------------------------

# Set by Invoke-HikariMain: $true while keyboard menus can be used.
$script:HikariMenu = $false
# Error message meaning "no keys can be read here": the caller switches to numbers.
$script:HikariNoConsole = 'HIKARI_NO_INTERACTIVE_CONSOLE'
# Returned by Invoke-HikariMenuOrNumbers when the question has to be asked with numbers.
$script:HikariUseNumbers = New-Object psobject
# Menu width in columns; 0 means the console's own width.
$script:HikariMenuWidth = 0
# Window height in lines; 0 means the console's own height (replaceable in tests).
$script:HikariMenuHeight = 0
$script:GlyphPointer = [string][char]0x203A
$script:GlyphEllipsis = [string][char]0x2026

# Replaceable in tests: can this console do keyboard menus?
$script:HikariConsoleProbe = { Test-HikariInteractiveConsole }
# Replaceable in tests: reads one key, without echo. Returns a ConsoleKeyInfo or,
# in tests, a key name: 'UpArrow', 'Spacebar', 'Enter', 'Escape', 'S', 'Ctrl+C'...
$script:HikariKeyReader = { [Console]::ReadKey($true) }
# Replaceable in tests: draws a frame (a list of lines, each a list of
# @{Text; Color} pieces) over the previous one, which took $Previous lines.
# Returns how many lines the new frame takes.
$script:HikariMenuRenderer = { param([object[]]$Lines, [int]$Previous) Write-HikariMenuFrame -Lines $Lines -Previous $Previous }
# Replaceable in tests: hide the cursor and take Ctrl+C as a key, and undo it.
$script:HikariConsoleEnter = { Enter-HikariMenuConsole }
$script:HikariConsoleExit = { param($State) Exit-HikariMenuConsole -State $State }
# Replaceable in tests: throws away keys pressed before a menu opened (during a
# download, say), so they never answer its question.
$script:HikariKeyFlush = { Clear-HikariPendingKeys }

function Test-HikariInteractiveConsole {
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

function Test-HikariUseNumbers {
    param($Value)
    return [object]::ReferenceEquals($Value, $script:HikariUseNumbers)
}

# Runs a keyboard menu and returns its answer, or $script:HikariUseNumbers when
# menus are off or the console turns out not to be able to read keys (then they
# stay off for the rest of the run).
function Invoke-HikariMenuOrNumbers {
    param([scriptblock]$Body)
    if (-not $script:HikariMenu -or $script:NonInteractive) { return $script:HikariUseNumbers }
    try {
        return (& $Body)
    }
    catch {
        if ($_.Exception.Message -ne $script:HikariNoConsole) { throw }
        $script:HikariMenu = $false
        return $script:HikariUseNumbers
    }
}

function Get-HikariMenuWidth {
    if ($script:HikariMenuWidth -gt 0) { return $script:HikariMenuWidth }
    $w = 80
    try { $w = [Console]::WindowWidth } catch { }
    if ($w -lt 20) { $w = 80 }
    return $w
}

# Window height in lines, or 0 when it cannot be known (then it is not checked).
function Get-HikariMenuHeight {
    if ($script:HikariMenuHeight -gt 0) { return $script:HikariMenuHeight }
    try { $h = [Console]::WindowHeight } catch { $h = 0 }
    if ($null -eq $h) { $h = 0 }
    return [int]$h
}

# A frame of $Count lines fits when it leaves one line free below it: redrawing
# goes back up exactly that many lines, which only works while the whole frame
# is inside the window. Taller, every key would leave a copy of the menu above.
function Test-HikariFrameFits {
    param([int]$Count)
    if ($Count -le 0) { return $true }
    $h = Get-HikariMenuHeight
    return ($h -le 0 -or $Count -lt $h - 1)
}

# Splits a help text into lines of at most $Max characters instead of cutting
# it: first between its ' . ' separated parts, then between words.
function Split-HikariHelp {
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
        $text = Format-HikariFit -Text $t[1] -Max $Max
        if ($line -eq '') { $line = $text }
        elseif ($line.Length + $t[0].Length + $text.Length -le $Max) { $line += $t[0] + $text }
        else { $out.Add($line); $line = $text }
    }
    if ($line -ne '') { $out.Add($line) }
    return , $out.ToArray()
}

# Help lines for a frame, indented by two spaces and wrapped to the width.
function Add-HikariHelpLines {
    param($Lines, [string[]]$Texts)
    $max = (Get-HikariMenuWidth) - 3
    foreach ($h in $Texts) {
        foreach ($part in (Split-HikariHelp -Text $h -Max $max)) { $Lines.Add([object[]]@(New-HikariSeg ('  ' + $part) 'DarkGray')) }
    }
}

# Shortens a text to $Max characters with an ellipsis, at the end or (paths,
# where the last folders matter most) in the middle.
function Format-HikariFit {
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
function Get-HikariPlainLabel {
    param([string]$Text)
    return ($Text.Trim() -replace '^[0-9A-Za-z]\)\s*', '')
}

function New-HikariSeg {
    param([string]$Text, [string]$Color = '')
    return @{ Text = $Text; Color = $Color }
}

# Draws the frame over the previous one: back up $Previous lines, write every
# line padded to the width (so nothing of the old frame is left) and clear the
# old lines that are no longer needed. Lines never reach the last column, so
# the console never wraps them and going back up stays exact. A frame taller
# than the window is refused before anything is written (Invoke-HikariRender then
# switches to numbers): redrawing it would leave copies of it on screen.
function Write-HikariMenuFrame {
    param([object[]]$Lines, [int]$Previous)
    if (-not (Test-HikariFrameFits @($Lines).Count)) { throw 'The menu does not fit in the window.' }
    $max = (Get-HikariMenuWidth) - 1
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
                $text = Format-HikariFit -Text ([string]$seg.Text) -Max $room
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

function Invoke-HikariRender {
    param([object[]]$Lines, [int]$Previous)
    try { return [int](& $script:HikariMenuRenderer $Lines $Previous) }
    catch { throw $script:HikariNoConsole }
}

# Hides the cursor and takes Ctrl+C as a key while a menu is open (so it acts
# as Esc and the console is always put back). Returns what has to be restored.
function Enter-HikariMenuConsole {
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

function Exit-HikariMenuConsole {
    param($State)
    if ($null -eq $State) { return }
    if ($null -ne $State.CtrlC) { try { [Console]::TreatControlCAsInput = [bool]$State.CtrlC } catch { } }
    try { [Console]::CursorVisible = [bool]$State.Cursor } catch { }
}

# Throws away the keys already waiting (a bounded number: a key held down keeps
# them coming). Nothing to do when there is no console to ask.
function Clear-HikariPendingKeys {
    try {
        for ($i = 0; $i -lt 256 -and [Console]::KeyAvailable; $i++) { [void][Console]::ReadKey($true) }
    }
    catch { }
}

# One key as Key (ConsoleKey name), Char, Ctrl and Alt. A reader that fails
# means there is no console to read from.
function Read-HikariKey {
    try { $k = & $script:HikariKeyReader }
    catch { throw $script:HikariNoConsole }
    if ($null -eq $k) { throw $script:HikariNoConsole }
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
function Test-HikariPlainKey {
    param($Key)
    return (-not $Key.Ctrl -and -not $Key.Alt)
}

# Esc, and Ctrl+C while a menu is open: always the safe way out.
function Test-HikariCancelKey {
    param($Key)
    return ($Key.Key -eq 'Escape' -or ($Key.Ctrl -and $Key.Key -eq 'C') -or $Key.Char -eq [char]3)
}

# An entry of a list menu. Action: in a multiple choice menu, an entry that is
# chosen with Enter instead of ticked ("Other folder...", "Exit"). Quit: the
# entry that leaves. Summary: what the line left after choosing says. Hotkey:
# in a single choice menu, the digit that chooses it at once (the number it had
# in the old numbered menus).
function New-HikariMenuItem {
    param([string]$Label, [string[]]$Details = @(), [bool]$Action = $false, [bool]$Disabled = $false, [string]$Summary = '', [bool]$Quit = $false, [string]$Hotkey = '')
    if (-not $Summary) { $Summary = $Label }
    return [pscustomobject]@{ Label = $Label; Details = @($Details); Action = $Action; Disabled = $Disabled; Summary = $Summary; Quit = $Quit; Hotkey = $Hotkey }
}

# Next entry that is not disabled, wrapping around at both ends.
function Get-HikariNextItem {
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
function Get-HikariListFrame {
    param([object[]]$Items, [int]$Current, [bool[]]$Checked, [bool]$Multi)
    foreach ($compact in @($false, $true)) {
        $frame = New-HikariListFrame -Items $Items -Current $Current -Checked $Checked -Multi $Multi -Compact $compact
        if (Test-HikariFrameFits @($frame).Count) { return , $frame }
    }
    throw $script:HikariNoConsole
}

function New-HikariListFrame {
    param([object[]]$Items, [int]$Current, [bool[]]$Checked, [bool]$Multi, [bool]$Compact)
    $width = Get-HikariMenuWidth
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
        $segs = @(New-HikariSeg $head $color)
        if ($Compact) {
            # No folder line, but entries that look alike must still be told
            # apart: the folder goes, shortened, on the same line when it fits.
            $room = $width - 1 - $head.Length - 2
            if (@($it.Details).Count -gt 0 -and $room -ge 12) {
                $segs += New-HikariSeg ('  ' + (Format-HikariFit -Text $it.Details[0] -Max $room -Middle)) $detailColor
            }
            $lines.Add([object[]]$segs)
            continue
        }
        $lines.Add([object[]]$segs)
        $indent = ' ' * (2 + $box.Length)
        foreach ($d in $it.Details) {
            $lines.Add([object[]]@(New-HikariSeg ($indent + (Format-HikariFit -Text $d -Max ($width - 1 - $indent.Length) -Middle)) $detailColor))
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
    Add-HikariHelpLines -Lines $lines -Texts $help
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
function Invoke-HikariListMenu {
    param([object[]]$Items, [switch]$Multi, [int]$Start = 0, [string[]]$Header = @())
    $n = $Items.Count
    $checked = New-Object 'bool[]' $n
    $cur = Get-HikariNextItem -Items $Items -From ($Start - 1) -Step 1
    $result = $null
    $drawn = 0
    # Too tall even when compact: this throws before anything is written, so
    # the numbered question that replaces it starts on a clean screen.
    [void](Get-HikariListFrame -Items $Items -Current $cur -Checked $checked -Multi ([bool]$Multi))
    foreach ($h in $Header) { Write-HikariInfo $h }
    $console = & $script:HikariConsoleEnter
    try {
        & $script:HikariKeyFlush
        while ($null -eq $result) {
            $drawn = Invoke-HikariRender -Lines (Get-HikariListFrame -Items $Items -Current $cur -Checked $checked -Multi ([bool]$Multi)) -Previous $drawn
            $key = Read-HikariKey
            if (Test-HikariCancelKey $key) {
                $result = [pscustomobject]@{ Cancelled = $true; Index = -1; Checked = @() }
                continue
            }
            $digit = [string]$key.Char
            if (-not $Multi -and $digit -match '^[0-9]$') {
                if (Test-HikariPlainKey $key) {
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
                'UpArrow' { $cur = Get-HikariNextItem -Items $Items -From $cur -Step -1 }
                'DownArrow' { $cur = Get-HikariNextItem -Items $Items -From $cur -Step 1 }
                'Home' { $cur = Get-HikariNextItem -Items $Items -From -1 -Step 1 }
                'End' { $cur = Get-HikariNextItem -Items $Items -From $n -Step -1 }
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
            $final = , ([object[]]@(New-HikariSeg ($script:GlyphPointer + ' ' + [string]::Join(', ', $parts)) 'Cyan'))
        }
        try { [void](& $script:HikariMenuRenderer $final $drawn) } catch { }
        & $script:HikariConsoleExit $console
    }
    return $result
}

function Get-HikariYesNoFrame {
    param([bool]$Yes)
    $answers = @(@((T 'answer_yes'), $true), @((T 'answer_no'), $false))
    $segs = @(New-HikariSeg '  ')
    foreach ($a in $answers) {
        if ($a[1] -eq $Yes) { $segs += New-HikariSeg ($script:GlyphPointer + ' ' + $a[0]) 'Cyan' }
        else { $segs += New-HikariSeg ('  ' + $a[0]) }
        $segs += New-HikariSeg '    '
    }
    # Full: answers and help. Compact (a very low window): only the answers.
    $lines = New-Object System.Collections.Generic.List[object]
    $lines.Add([object[]]$segs)
    Add-HikariHelpLines -Lines $lines -Texts @(T 'yesno_help')
    if (Test-HikariFrameFits $lines.Count) { return , $lines.ToArray() }
    if (Test-HikariFrameFits 1) { return , @(, [object[]]$segs) }
    throw $script:HikariNoConsole
}

# Yes/No on one line. Starts on $Default; Left/Right (and Up/Down, Tab) change
# it, Enter confirms, S or Y answer yes and N no straight away. Esc (and Ctrl+C)
# always answer No: every question is asked so that No is the safe answer.
function Read-HikariYesNoMenu {
    param([string]$Question, [bool]$Default)
    $yes = $Default
    $result = $null
    $drawn = 0
    # Checked before the question is written (see Invoke-HikariListMenu).
    [void](Get-HikariYesNoFrame $yes)
    Write-HikariInfo $Question
    $console = & $script:HikariConsoleEnter
    try {
        & $script:HikariKeyFlush
        while ($null -eq $result) {
            $drawn = Invoke-HikariRender -Lines (Get-HikariYesNoFrame $yes) -Previous $drawn
            $key = Read-HikariKey
            if (Test-HikariCancelKey $key) { $result = $false; continue }
            $plain = Test-HikariPlainKey $key
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
            $final = , ([object[]]@(New-HikariSeg ('  ' + $script:GlyphPointer + ' ' + $label) 'Cyan'))
        }
        try { [void](& $script:HikariMenuRenderer $final $drawn) } catch { }
        & $script:HikariConsoleExit $console
    }
    return $result
}

# ---------------------------------------------------------------------------
# Paths and files
# ---------------------------------------------------------------------------

function Join-HikariPath {
    param([string]$Base, [string[]]$Child)
    $result = $Base
    foreach ($part in $Child) { $result = [System.IO.Path]::Combine($result, $part) }
    return $result
}

function Get-HikariFullPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $trim = $full.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    if ($trim -eq '' -or $trim -match '^[A-Za-z]:$') { return $full }
    return $trim
}

function Test-HikariSamePath {
    param([string]$A, [string]$B)
    return [string]::Equals((Get-HikariFullPath $A), (Get-HikariFullPath $B), [System.StringComparison]::OrdinalIgnoreCase)
}

# True when $Path is strictly inside $Root (never $Root itself).
function Test-HikariInside {
    param([string]$Path, [string]$Root)
    if ([string]::IsNullOrEmpty($Path) -or [string]::IsNullOrEmpty($Root)) { return $false }
    $full = Get-HikariFullPath $Path
    $rootFull = (Get-HikariFullPath $Root).TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if ($full.Length -le $prefix.Length) { return $false }
    return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-HikariInside {
    param([string]$Path, [string]$Root)
    if (-not (Test-HikariInside -Path $Path -Root $Root)) {
        throw (T 'outside_target' @($Path, $Root))
    }
}

# True for junctions, symbolic links and other reparse points.
function Test-HikariLink {
    param($Item)
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

# Running as administrator, a link inside the config folder (scripts\ -> C:\Windows,
# say) would let a delete or move land outside it with full rights. So, only when
# elevated, every folder between $Root (excluded) and $Path (excluded: a link
# there is deleted or moved as a link) must be a real folder.
function Assert-HikariNoLink {
    param([string]$Path, [string]$Root)
    if (-not $script:HikariElevated) { return }
    $rootFull = Get-HikariFullPath $Root
    $p = Split-Path -Path (Get-HikariFullPath $Path) -Parent
    while ($p -and (Test-HikariInside -Path $p -Root $rootFull)) {
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and (Test-HikariLink $item)) { throw (T 'link_in_path' @($Path, $p)) }
        $p = Split-Path -Path $p -Parent
    }
}

# Deletes a file or folder inside $Root. Links (junctions, symlinks) are removed
# as links: their target is never followed.
function Remove-HikariItem {
    param([string]$Path, [string]$Root)
    Assert-HikariInside -Path $Path -Root $Root
    Assert-HikariNoLink -Path $Path -Root $Root
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $isLink = Test-HikariLink $item
    if ($item.PSIsContainer) {
        if ($isLink) {
            [System.IO.Directory]::Delete($item.FullName, $false)
            return
        }
        foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force)) {
            Remove-HikariItem -Path $child.FullName -Root $Root
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
function Copy-HikariTree {
    param([string]$From, [string]$To)
    if (-not (Test-Path -LiteralPath $To -PathType Container)) {
        New-Item -ItemType Directory -Path $To -Force | Out-Null
    }
    foreach ($child in @(Get-ChildItem -LiteralPath $From -Force)) {
        if (Test-HikariLink $child) { Write-HikariWarn (T 'link_skipped' @($child.FullName)); continue }
        $dest = Join-HikariPath $To $child.Name
        if ($child.PSIsContainer) {
            Copy-HikariTree -From $child.FullName -To $dest
        }
        else {
            Copy-Item -LiteralPath $child.FullName -Destination $dest -Force
        }
    }
}

# Size in bytes of a file or folder tree, without following links.
function Get-HikariTreeSize {
    param($Item)
    if (Test-HikariLink $Item) { return 0 }
    if (-not $Item.PSIsContainer) { return [long]$Item.Length }
    $total = [long]0
    foreach ($child in @(Get-ChildItem -LiteralPath $Item.FullName -Force -ErrorAction SilentlyContinue)) {
        $total += (Get-HikariTreeSize $child)
    }
    return $total
}

# A path typed by the user (or given with -Target): quotes stripped, %VARS%
# expanded and a relative path resolved against PowerShell's current folder (not
# the process one, which can differ). Throws when it is not a file system path.
function ConvertTo-HikariTypedPath {
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
    return (Get-HikariFullPath $resolved)
}

function New-HikariDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Reads a text file keeping what is needed to write it back unchanged: UTF-8 (with
# or without BOM) or, when the bytes are not valid UTF-8, Latin-1, which maps
# every byte to one character and back, so nothing of the user's file is lost.
function Read-HikariText {
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
function Write-HikariText {
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

function Test-HikariDirWritable {
    param([string]$Path)
    $probe = $Path
    while ($probe -and -not (Test-Path -LiteralPath $probe -PathType Container)) {
        $parent = Split-Path -Path $probe -Parent
        if ($parent -eq $probe) { break }
        $probe = $parent
    }
    if (-not $probe -or -not (Test-Path -LiteralPath $probe -PathType Container)) { return $false }
    $file = Join-HikariPath $probe ('.hikari-write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($file, 'hikari')
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

function Test-HikariAdmin {
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
function New-HikariEnvironment {
    return @{
        IsAdmin         = (Test-HikariAdmin)
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
        TestWritable    = { param([string]$Path) Test-HikariDirWritable $Path }
    }
}

function Get-HikariUserConfigDir {
    param([hashtable]$Env, [string]$Kind)
    if ($Kind -eq 'mpv') {
        if ($Env.MpvHome) { return $Env.MpvHome }
        if (-not $Env.AppData) { return $null }
        return (Join-HikariPath $Env.AppData 'mpv')
    }
    if (-not $Env.AppData) { return $null }
    return (Join-HikariPath $Env.AppData 'mpv.net')
}

function Get-HikariPlayerKind {
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
function Resolve-HikariShim {
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

function Get-HikariInstallState {
    param([string]$ConfigDir)
    $state = [pscustomobject]@{ Installed = $false; Version = ''; Manual = $false; Sosc = $false }
    if (-not $ConfigDir -or -not (Test-Path -LiteralPath $ConfigDir -PathType Container)) { return $state }
    $record = Read-HikariRecord $ConfigDir -NoWarn
    if ($null -ne $record) {
        $state.Installed = $true
        $state.Version = [string]$record.Values['hikari_version']
        return $state
    }
    $scripts = Join-HikariPath $ConfigDir 'scripts'
    if ((Test-Path -LiteralPath $scripts -PathType Container) -and
        @(Get-ChildItem -LiteralPath $scripts -Filter 'hikari-*.lua' -File -Force).Count -gt 0) {
        $state.Installed = $true
        $state.Manual = $true
    }
    elseif (Test-HikariSoscPresent $ConfigDir) {
        $state.Installed = $true
        $state.Sosc = $true
    }
    return $state
}

function New-HikariCandidate {
    param([hashtable]$Env, [string]$Kind, [string]$Exe, [string]$ConfigDir, [bool]$Portable)
    $state = Get-HikariInstallState $ConfigDir
    $fallback = $null
    if ($Portable) { $fallback = Get-HikariUserConfigDir -Env $Env -Kind $Kind }
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
        Sosc             = $state.Sosc
        UserConfigDir    = $fallback
    }
}

# Finds mpv, mpv.net and AnimeJaNai, plus mpv config folders that exist without
# a player. Pure apart from the file system: everything else comes from $Env.
function Find-HikariPlayers {
    param([Parameter(Mandatory = $true)][hashtable]$Env)

    $exePaths = New-Object System.Collections.Generic.List[string]
    $addExe = {
        param([string]$Path)
        if ([string]::IsNullOrEmpty($Path)) { return }
        $exePaths.Add($Path)
    }

    if ($Env.LocalAppData) {
        & $addExe (Join-HikariPath $Env.LocalAppData @('Programs', 'mpv-AnimeJaNai', 'mpvnet.exe'))
        & $addExe (Join-HikariPath $Env.LocalAppData @('Programs', 'mpv.net', 'mpvnet.exe'))
    }
    foreach ($pf in @($Env.ProgramFiles, $Env.ProgramFilesX86)) {
        if ($pf) {
            & $addExe (Join-HikariPath $pf @('mpv.net', 'mpvnet.exe'))
        }
    }
    if ($Env.UserProfile) {
        & $addExe (Join-HikariPath $Env.UserProfile @('scoop', 'apps', 'mpv.net', 'current', 'mpvnet.exe'))
    }
    $found = & $Env.FindCommand 'mpvnet.exe'
    if ($found) { & $addExe (Resolve-HikariShim $found) }

    $found = & $Env.FindCommand 'mpv.exe'
    if ($found) { & $addExe (Resolve-HikariShim $found) }
    if ($Env.UserProfile) {
        & $addExe (Join-HikariPath $Env.UserProfile @('scoop', 'apps', 'mpv', 'current', 'mpv.exe'))
        & $addExe (Join-HikariPath $Env.UserProfile @('scoop', 'apps', 'mpv-git', 'current', 'mpv.exe'))
    }
    foreach ($pf in @($Env.ProgramFiles, $Env.ProgramFilesX86)) {
        if ($pf) {
            & $addExe (Join-HikariPath $pf @('mpv', 'mpv.exe'))
            & $addExe (Join-HikariPath $pf @('MPV Player', 'mpv.exe'))
        }
    }
    if ($Env.ProgramData) {
        $chocoLib = Join-HikariPath $Env.ProgramData @('chocolatey', 'lib')
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
        foreach ($p in $List) { if (Test-HikariSamePath $p $Path) { return $true } }
        return $false
    }

    foreach ($exe in $exePaths) {
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
        $exeFull = Get-HikariFullPath $exe
        if (& $isSeen $seenExe $exeFull) { continue }
        $seenExe.Add($exeFull)
        $kind = Get-HikariPlayerKind $exeFull
        $portableDir = Join-HikariPath (Split-Path -Path $exeFull -Parent) 'portable_config'
        # mpv itself gives MPV_HOME priority over portable_config. mpv.net (and
        # AnimeJaNai) set their own config-dir, which beats both, so for them
        # MPV_HOME does not matter.
        $portable = (Test-Path -LiteralPath $portableDir -PathType Container) -and -not ($kind -eq 'mpv' -and $Env.MpvHome)
        if ($portable) { $config = $portableDir } else { $config = Get-HikariUserConfigDir -Env $Env -Kind $kind }
        if (-not $config) { continue }
        $config = Get-HikariFullPath $config
        if (& $isSeen $seenConfig $config) { continue }
        $seenConfig.Add($config)
        $candidates.Add((New-HikariCandidate -Env $Env -Kind $kind -Exe $exeFull -ConfigDir $config -Portable $portable))
    }

    foreach ($kind in @('mpv', 'mpv.net')) {
        $config = Get-HikariUserConfigDir -Env $Env -Kind $kind
        if (-not $config -or -not (Test-Path -LiteralPath $config -PathType Container)) { continue }
        $config = Get-HikariFullPath $config
        if (& $isSeen $seenConfig $config) { continue }
        $seenConfig.Add($config)
        $candidates.Add((New-HikariCandidate -Env $Env -Kind 'folder' -Exe '' -ConfigDir $config -Portable $false))
    }

    return $candidates.ToArray()
}

# A folder typed by the user (or given with -Target): reuse the detected entry
# when it is one, otherwise guess the player from an exe next to it. A folder
# that holds the player itself is not a config folder: its portable_config is
# used, or the user folder that player reads is offered. Returns $null when the
# user turns that down.
function Resolve-HikariManualTarget {
    param([hashtable]$Env, [string]$Path, [object[]]$Candidates)
    $full = ConvertTo-HikariTypedPath $Path
    foreach ($c in $Candidates) {
        if (Test-HikariSamePath $c.ConfigDir $full) { return $c }
    }

    foreach ($name in $script:PlayerExes) {
        $probe = Join-HikariPath $full $name
        if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { continue }
        $kind = Get-HikariPlayerKind $probe
        Write-HikariWarn (T 'exe_folder' @($full, $name))
        $portableDir = Join-HikariPath $full 'portable_config'
        if ((Test-Path -LiteralPath $portableDir -PathType Container) -and -not ($kind -eq 'mpv' -and $Env.MpvHome)) {
            Write-HikariInfo (T 'exe_portable' @($portableDir))
            return (Resolve-HikariManualTarget -Env $Env -Path $portableDir -Candidates $Candidates)
        }
        $user = Get-HikariUserConfigDir -Env $Env -Kind $kind
        if (-not $user) { return $null }
        $user = Get-HikariFullPath $user
        if (-not (Confirm-Hikari -Question (T 'exe_offer' @($user)) -Default $true)) { return $null }
        foreach ($c in $Candidates) {
            if (Test-HikariSamePath $c.ConfigDir $user) { return $c }
        }
        return (New-HikariCandidate -Env $Env -Kind $kind -Exe $probe -ConfigDir $user -Portable $false)
    }

    $kind = 'folder'
    $exe = ''
    $portable = $false
    if ((Split-Path -Path $full -Leaf) -ieq 'portable_config') {
        $parent = Split-Path -Path $full -Parent
        foreach ($name in $script:PlayerExes) {
            $probe = Join-HikariPath $parent $name
            if (Test-Path -LiteralPath $probe -PathType Leaf) {
                $exe = $probe
                $kind = Get-HikariPlayerKind $probe
                $portable = $true
                if ($kind -eq 'mpv' -and $Env.MpvHome) { Write-HikariWarn (T 'mpv_home_note' @($Env.MpvHome, $full)) }
                break
            }
        }
    }
    return (New-HikariCandidate -Env $Env -Kind $kind -Exe $exe -ConfigDir $full -Portable $portable)
}

# A drive root (C:\, \\server\share, /) or the bare user profile is never a
# config folder: backing it up or writing scripts\ there makes no sense.
function Test-HikariForbiddenTarget {
    param([hashtable]$Env, [string]$Path)
    $full = Get-HikariFullPath $Path
    $seps = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($null -eq $root -or $full.TrimEnd($seps) -eq $root.TrimEnd($seps)) { return $true }
    if ($Env.UserProfile -and (Test-HikariSamePath $full $Env.UserProfile)) { return $true }
    return $false
}

# False only for a folder that exists, is not empty and shows no sign of mpv.
function Test-HikariLooksLikeMpvConfig {
    param([hashtable]$Env, $Candidate)
    $dir = Get-HikariFullPath $Candidate.ConfigDir
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $true }
    if (@(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) { return $true }
    if ($Candidate.Exe) { return $true }
    foreach ($n in $script:MpvConfigFiles) { if (Test-Path -LiteralPath (Join-HikariPath $dir $n) -PathType Leaf) { return $true } }
    foreach ($n in $script:MpvConfigDirs) { if (Test-Path -LiteralPath (Join-HikariPath $dir $n) -PathType Container) { return $true } }
    foreach ($kind in @('mpv', 'mpv.net')) {
        $user = Get-HikariUserConfigDir -Env $Env -Kind $kind
        if ($user -and (Test-HikariSamePath $user $dir)) { return $true }
    }
    $parent = Split-Path -Path $dir -Parent
    foreach ($d in @($dir, $parent)) {
        if (-not $d) { continue }
        foreach ($n in $script:PlayerExes) { if (Test-Path -LiteralPath (Join-HikariPath $d $n) -PathType Leaf) { return $true } }
    }
    return $false
}

# "1,3" / "o" / "0" -> what the user picked. Returns $null when the text is not valid.
function ConvertFrom-HikariSelection {
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
function Split-HikariLines {
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

function Get-HikariEol {
    param([string]$Text)
    if ($Text.Contains("`r`n")) { return "`r`n" }
    if ($Text.Contains("`n")) { return "`n" }
    return "`r`n"
}

# Returns $null when there is no block, or the index of its first and last line.
# Throws when the markers do not pair up.
# $BeginMarker and $EndMarker: other markers (sosc's).
function Find-HikariBlock {
    param([object[]]$Lines, [string]$Name = 'file', [string]$BeginMarker = $script:BlockBegin, [string]$EndMarker = $script:BlockEnd)
    $begin = -1
    $end = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $content = $Lines[$i].Content.Trim()
        if ($content -eq $BeginMarker) {
            if ($begin -ge 0) { throw (T 'malformed_block' @($Name)) }
            $begin = $i
        }
        elseif ($content -eq $EndMarker) {
            if ($begin -lt 0 -or $end -ge 0) { throw (T 'malformed_block' @($Name)) }
            $end = $i
        }
    }
    if ($begin -ge 0 -and $end -lt 0) { throw (T 'malformed_block' @($Name)) }
    if ($begin -lt 0) { return $null }
    return [pscustomobject]@{ Begin = $begin; End = $end }
}

# Puts the block (marker lines added here) in place of the old one, or at the end.
function Set-HikariBlockText {
    param([string]$Text, [string[]]$BlockLines, [string]$Name = 'file', [string]$Eol = '')
    if ($null -eq $Text) { $Text = '' }
    $eol = $Eol
    if (-not $eol) { $eol = Get-HikariEol $Text }
    $all = @($script:BlockBegin) + @($BlockLines) + @($script:BlockEnd)
    $body = [string]::Join($eol, $all)
    $lines = @(Split-HikariLines $Text)
    $block = Find-HikariBlock -Lines $lines -Name $Name
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

# $NoFinalEol: the file had no line break at its end before hikari added the
# block (Set-HikariBlockText then adds one); when the block is still the last
# thing in the file, that line break goes too.
function Remove-HikariBlockText {
    param([string]$Text, [string]$Name = 'file', [switch]$NoFinalEol, [string]$BeginMarker = $script:BlockBegin,
        [string]$EndMarker = $script:BlockEnd)
    if ($null -eq $Text) { return '' }
    $lines = @(Split-HikariLines $Text)
    $block = Find-HikariBlock -Lines $lines -Name $Name -BeginMarker $BeginMarker -EndMarker $EndMarker
    if ($null -eq $block) { return $Text }
    $first = $lines[$block.Begin]
    $last = $lines[$block.End]
    $after = $last.Start + $last.Content.Length + $last.Eol.Length
    $before = $Text.Substring(0, $first.Start)
    if ($NoFinalEol -and $after -ge $Text.Length) {
        if ($before.EndsWith("`r`n")) { $before = $before.Substring(0, $before.Length - 2) }
        elseif ($before.EndsWith("`n")) { $before = $before.Substring(0, $before.Length - 1) }
    }
    return $before + $Text.Substring($after)
}

# 'no' when the file exists, is not empty and does not end with a line break.
function Get-HikariFinalEolState {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'yes' }
    $text = (Read-HikariText $Path).Text
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { return 'no' }
    return 'yes'
}

# Lines of the file that are not part of the hikari block.
function Get-HikariOutsideLines {
    param([string]$Text, [string]$Name = 'file')
    $lines = @(Split-HikariLines $Text)
    $block = Find-HikariBlock -Lines $lines -Name $Name
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
function Get-HikariProfileHeader {
    param([string]$Line)
    $m = [regex]::Match($Line.TrimStart(), '^\[([^\]]*)\]\s*(#.*)?$')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}

# Block for mpv.conf, which always goes at the end of the file (so its include of
# hikari-subs.conf comes after the user's own sub-* lines). If the file ends inside
# a [profile], the block opens with [default] so its options are top-level: mpv
# applies whatever follows a [name] header to that profile only. mpv compares
# names exactly: [DEFAULT] is another profile, and an empty [] means default.
function Get-HikariMpvConfBlock {
    param([string]$Text)
    $lastHeader = $null
    foreach ($line in @(Get-HikariOutsideLines -Text $Text -Name 'mpv.conf')) {
        $h = Get-HikariProfileHeader $line.Content
        if ($null -ne $h) { $lastHeader = $h }
    }
    $needsDefault = ($null -ne $lastHeader -and $lastHeader -cne 'default' -and $lastHeader -ne '')
    $lines = @()
    if ($needsDefault) { $lines += '[default]' }
    $lines += $script:MpvConfLines
    return [pscustomobject]@{ Lines = $lines; NeedsDefault = $needsDefault }
}

function ConvertTo-HikariKeyName {
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

# Decides which hikari bindings go in the block. A key the user already bound
# outside the block is left alone (and reported); same key and same command is
# simply not repeated.
function Get-HikariInputBlock {
    param([string]$Text, [object[]]$Extra = @())
    # Case-sensitive: in mpv, Alt+p and Alt+P (with Shift) are different keys.
    $bound = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
    foreach ($line in @(Get-HikariOutsideLines -Text $Text -Name 'input.conf')) {
        $c = $line.Content.Trim()
        if ($c -eq '' -or $c.StartsWith('#')) { continue }
        $m = [regex]::Match($c, '^(\S+)\s*(.*)$')
        if (-not $m.Success) { continue }
        $key = ConvertTo-HikariKeyName $m.Groups[1].Value
        $command = ($m.Groups[2].Value -replace '\s+', ' ').Trim()
        $bound[$key] = $command
    }
    $lines = @()
    $taken = @()
    $same = @()
    foreach ($b in (@($script:InputBindings) + @($Extra))) {
        $norm = ConvertTo-HikariKeyName $b.Key
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
function Update-HikariManagedFile {
    param([string]$Path, [string]$Kind, [object[]]$ExtraBindings = @())
    $existed = Test-Path -LiteralPath $Path -PathType Leaf
    $name = [System.IO.Path]::GetFileName($Path)
    if ($existed) { $file = Read-HikariText $Path }
    else { $file = [pscustomobject]@{ Text = ''; Encoding = 'utf8'; Bom = $false } }

    if ($Kind -eq 'mpv') {
        # The block is taken out of wherever it is and added again at the end.
        $without = Remove-HikariBlockText -Text $file.Text -Name $name
        $block = Get-HikariMpvConfBlock $without
        if ($block.NeedsDefault) { Write-HikariInfo (T 'default_section' @($name)) }
        $newText = Set-HikariBlockText -Text $without -BlockLines $block.Lines -Name $name -Eol (Get-HikariEol $file.Text)
    }
    else {
        # input.conf: the block stays where it is (order does not matter there).
        $block = Get-HikariInputBlock -Text $file.Text -Extra $ExtraBindings
        foreach ($t in $block.Taken) { Write-HikariWarn (T 'key_taken' @($t.Key, $t.Existing, $t.Command)) }
        foreach ($s in $block.Same) { Write-HikariInfo (T 'key_same' @($s.Key, $s.Command)) }
        $newText = Set-HikariBlockText -Text $file.Text -BlockLines $block.Lines -Name $name
    }
    if (-not $existed -or $newText -ne $file.Text) {
        Write-HikariText -Path $Path -Text $newText -Encoding $file.Encoding -Bom $file.Bom
    }
    Write-HikariInfo (T 'block_updated' @($name))
    return $existed
}

# Removes the block. A file that only held the block and was created by hikari is deleted.
function Remove-HikariManagedFile {
    param([string]$Path, [string]$Root, [bool]$CreatedByHikari, [bool]$NoFinalEol = $false)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $name = [System.IO.Path]::GetFileName($Path)
    $file = Read-HikariText $Path
    $newText = Remove-HikariBlockText -Text $file.Text -Name $name -NoFinalEol:$NoFinalEol
    if ($newText -eq $file.Text) { return }
    if ($CreatedByHikari -and $newText.Trim() -eq '') {
        Remove-HikariItem -Path $Path -Root $Root
        return
    }
    Write-HikariText -Path $Path -Text $newText -Encoding $file.Encoding -Bom $file.Bom
}

# Sets key=value in a script-opts file, replacing an existing line for that key.
function Set-HikariConfOption {
    param([string]$Path, [string]$Key, [string]$Value, [string]$Comment = '')
    if (Test-Path -LiteralPath $Path -PathType Leaf) { $file = Read-HikariText $Path }
    else { $file = [pscustomobject]@{ Text = ''; Encoding = 'utf8'; Bom = $false } }
    $text = $file.Text
    $eol = Get-HikariEol $text
    $lines = @(Split-HikariLines $text)
    $newLine = $Key + '=' + $Value
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i].Content -match $pattern) {
            $l = $lines[$i]
            $text = $text.Substring(0, $l.Start) + $newLine + $text.Substring($l.Start + $l.Content.Length)
            Write-HikariText -Path $Path -Text $text -Encoding $file.Encoding -Bom $file.Bom
            return
        }
    }
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += $eol }
    if ($Comment) {
        if ($text.Length -gt 0) { $text += $eol }
        $text += '# ' + $Comment + $eol
    }
    $text += $newLine + $eol
    Write-HikariText -Path $Path -Text $text -Encoding $file.Encoding -Bom $file.Bom
}

# ---------------------------------------------------------------------------
# Installer record (hikari-installed.txt)
# ---------------------------------------------------------------------------

# The record can be edited by anyone, so its paths are checked before use: they
# must be relative, '/'-separated, with no '..', '.', empty segment, drive,
# backslash or characters Windows does not allow, and no segment ending in a dot
# or a space (Windows drops those, so "..." could act as "..").
function Test-HikariRecordPath {
    param([string]$Rel)
    if ([string]::IsNullOrEmpty($Rel)) { return $false }
    if ($Rel -match '[\\:*?"<>|\x00-\x1f]') { return $false }
    foreach ($seg in ($Rel -split '/')) {
        if ($seg -eq '' -or $seg -match '^\.+\z' -or $seg -match '[. ]\z') { return $false }
    }
    return $true
}

# $Name: another record (sosc's), read with the same checks.
function Read-HikariRecord {
    param([string]$ConfigDir, [switch]$NoWarn, [string]$Name = $script:RecordName)
    $path = Join-HikariPath $ConfigDir $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $values = @{}
    $files = New-Object System.Collections.Generic.List[string]
    $disabled = New-Object System.Collections.Generic.List[string]
    $broken = New-Object System.Collections.Generic.List[string]
    $moved = New-Object System.Collections.Generic.List[string]
    $commented = New-Object System.Collections.Generic.List[string]
    $commentedMpv = New-Object System.Collections.Generic.List[string]
    foreach ($line in ((Read-HikariText $path).Text -split "`r?`n")) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $idx = $line.IndexOf('=')
        $key = $line.Substring(0, $idx).Trim()
        $value = $line.Substring($idx + 1).Trim()
        if ($key -eq 'file') {
            if (Test-HikariRecordPath $value) { $files.Add($value) }
            elseif (-not $NoWarn) { Write-HikariWarn (T 'record_bad' @($line)) }
        }
        elseif ($key -eq 'disabled' -or $key -eq 'broken') {
            $pair = $value -split '\|'
            if ($pair.Count -eq 2 -and (Test-HikariRecordPath $pair[0]) -and (Test-HikariRecordPath $pair[1])) {
                if ($key -eq 'disabled') { $disabled.Add($value) } else { $broken.Add($value) }
            }
            elseif (-not $NoWarn) { Write-HikariWarn (T 'record_bad' @($line)) }
        }
        elseif ($key -eq 'a4k_moved') {
            # shaders-desactivados/<file>|shaders/<file>: never anything else.
            $pair = $value -split '\|'
            if ($pair.Count -eq 2 -and (Test-HikariRecordPath $pair[0]) -and (Test-HikariRecordPath $pair[1]) -and
                $pair[0].StartsWith($script:ShadersDisabledDir + '/') -and $pair[1].StartsWith($script:ShadersDir + '/')) { $moved.Add($value) }
            elseif (-not $NoWarn) { Write-HikariWarn (T 'record_bad' @($line)) }
        }
        elseif ($key -eq 'a4k_commented' -or $key -eq 'a4k_commented_mpv') {
            # Only used to recognise lines hikari turned off (input.conf, mpv.conf);
            # checked again before use.
            if (Test-HikariRecordableLine $value) {
                if ($key -eq 'a4k_commented') { $commented.Add($value) } else { $commentedMpv.Add($value) }
            }
            elseif (-not $NoWarn) { Write-HikariWarn (T 'record_bad' @($line)) }
        }
        else { $values[$key] = $value }
    }
    return [pscustomobject]@{ Values = $values; Files = $files.ToArray(); Disabled = $disabled.ToArray(); Moved = $moved.ToArray()
        Commented = $commented.ToArray(); CommentedMpv = $commentedMpv.ToArray(); Broken = $broken.ToArray() }
}

function Write-HikariRecord {
    param([string]$ConfigDir, [System.Collections.Specialized.OrderedDictionary]$Values, [string[]]$Files, [string[]]$Disabled,
        [string[]]$Moved = @(), [string[]]$Commented = @(), [string[]]$CommentedMpv = @(), [string[]]$Broken = @())
    $eol = "`r`n"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('# Written by the hikari installer (install/hikari.ps1). Used to update and uninstall; do not edit.' + $eol)
    foreach ($key in $Values.Keys) { [void]$sb.Append($key + '=' + $Values[$key] + $eol) }
    foreach ($d in $Disabled) { [void]$sb.Append('disabled=' + $d + $eol) }
    foreach ($b in $Broken) { [void]$sb.Append('broken=' + $b + $eol) }
    foreach ($m in $Moved) { [void]$sb.Append('a4k_moved=' + $m + $eol) }
    foreach ($c in $Commented) { [void]$sb.Append('a4k_commented=' + $c + $eol) }
    foreach ($c in $CommentedMpv) { [void]$sb.Append('a4k_commented_mpv=' + $c + $eol) }
    foreach ($f in $Files) { [void]$sb.Append('file=' + $f + $eol) }
    Write-HikariText -Path (Join-HikariPath $ConfigDir $script:RecordName) -Text $sb.ToString()
}

# A line of the user's that can be kept in the record (to turn it back on
# later): not empty, not too long, no control characters but tabs.
function Test-HikariRecordableLine {
    param([string]$Line)
    return ($Line -ne '' -and $Line.Length -le 4000 -and $Line -notmatch '[\x00-\x08\x0a-\x1f]')
}

# Adds entries ("key=value") to the record just before the change they
# describe is made, so a failure later in the run (or a closed window) never
# leaves a moved shader or a turned-off line unrecorded (an entry for a change
# that did not happen is harmless: it is checked again before use). The full record written at the
# end of the install replaces it. Starts a record when there is none.
function Add-HikariRecordEntries {
    param([string]$ConfigDir, [string[]]$Entries)
    if (@($Entries).Count -eq 0) { return }
    $path = Join-HikariPath $ConfigDir $script:RecordName
    $eol = "`r`n"
    $text = ''
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $text = (Read-HikariText $path).Text
        if ($text -ne '' -and -not $text.EndsWith("`n")) { $text += $eol }
    }
    else {
        $text = '# Written by the hikari installer (install/hikari.ps1). Used to update and uninstall; do not edit.' + $eol
    }
    foreach ($e in $Entries) { $text += $e + $eol }
    Write-HikariText -Path $path -Text $text
}

function ConvertTo-HikariYesNo { param([bool]$Value) if ($Value) { return 'yes' } return 'no' }

# ---------------------------------------------------------------------------
# Sources and downloads
# ---------------------------------------------------------------------------

function Get-HikariRepoCommit {
    param([string]$RepoRoot)
    try {
        $gitDir = Join-HikariPath $RepoRoot '.git'
        $head = Join-HikariPath $gitDir 'HEAD'
        if (-not (Test-Path -LiteralPath $head -PathType Leaf)) { return '' }
        $ref = ([System.IO.File]::ReadAllText($head)).Trim()
        if ($ref -notmatch '^ref:\s*(.+)$') { return $ref }
        $refName = $Matches[1].Trim()
        $refFile = Join-HikariPath $gitDir ($refName -split '/')
        if (Test-Path -LiteralPath $refFile -PathType Leaf) { return ([System.IO.File]::ReadAllText($refFile)).Trim() }
        $packed = Join-HikariPath $gitDir 'packed-refs'
        if (Test-Path -LiteralPath $packed -PathType Leaf) {
            foreach ($line in [System.IO.File]::ReadAllLines($packed)) {
                if ($line -match ('^([0-9a-f]{40}) ' + [regex]::Escape($refName) + '$')) { return $Matches[1] }
            }
        }
    }
    catch { }
    return ''
}

function Assert-HikariDownloadUrl {
    param([string]$Url)
    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or $script:AllowedHosts -notcontains $uri.Host.ToLowerInvariant()) {
        throw (T 'url_bad' @($Url))
    }
}

function Get-HikariFileSha256 {
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
function Invoke-HikariVerifiedDownload {
    param([string]$Url, [string]$Sha256, [string]$OutFile)
    Assert-HikariDownloadUrl $Url
    if ([string]::IsNullOrEmpty($Sha256)) { throw (T 'hash_bad' @($Url, '?', '?')) }
    Write-HikariInfo (T 'downloading' @($Url))
    # Anything the downloader prints must not end up in the caller's return value.
    & $script:HikariDownloader $Url $OutFile | Out-Null
    if (-not (Test-Path -LiteralPath $OutFile -PathType Leaf)) { throw (T 'hash_bad' @($Url, $Sha256, '-')) }
    $actual = Get-HikariFileSha256 $OutFile
    if ($actual -ne $Sha256.ToLowerInvariant()) {
        [System.IO.File]::Delete($OutFile)
        throw (T 'hash_bad' @($Url, $Sha256.ToLowerInvariant(), $actual))
    }
}

function Expand-HikariZip {
    param([string]$Zip, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-HikariDirectory $Destination
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Destination)
}

function New-HikariTempDir {
    $dir = Join-HikariPath ([System.IO.Path]::GetTempPath()) ('hikari-install-' + [guid]::NewGuid().ToString('N'))
    New-HikariDirectory $dir
    return $dir
}

# Where the hikari files come from. A release build (the markers filled in by
# tools/make-release.sh) always uses its own hikari.zip, downloaded and checked
# against its SHA256, wherever the script is: a stray portable_config next to a
# downloaded hikari.ps1 is never picked up. The repository version uses the
# portable_config of the repository copy it sits in; run on its own (iex, no
# file) it has nothing to install from and says so.
function Get-HikariSource {
    param([string]$TempDir)
    if (-not [string]::IsNullOrEmpty($script:HikariReleaseUrl)) { return (Get-HikariReleaseSource -TempDir $TempDir) }
    if ($script:HikariScriptRoot) {
        $repo = Split-Path -Path $script:HikariScriptRoot -Parent
        $config = Join-HikariPath $repo 'portable_config'
        if (Test-Path -LiteralPath (Join-HikariPath $config @('scripts', 'hikari-palettes.lua')) -PathType Leaf) {
            $commit = Get-HikariRepoCommit $repo
            return [pscustomobject]@{ ConfigDir = $config; Version = $script:HikariVersion; Commit = $commit }
        }
    }
    throw (T 'release_unpublished')
}

# Downloads the release zip into $TempDir (a fresh folder of this run, deleted by
# Invoke-HikariMain when it ends, also on failure), checks its SHA256 before
# opening it and extracts it there.
function Get-HikariReleaseSource {
    param([string]$TempDir)
    if ([string]::IsNullOrEmpty($script:HikariReleaseUrl)) { throw (T 'release_unpublished') }
    $zip = Join-HikariPath $TempDir 'hikari.zip'
    Invoke-HikariVerifiedDownload -Url $script:HikariReleaseUrl -Sha256 $script:HikariReleaseSha256 -OutFile $zip
    $dest = Join-HikariPath $TempDir 'hikari'
    Expand-HikariZip -Zip $zip -Destination $dest
    foreach ($dir in @($dest) + @(Get-ChildItem -LiteralPath $dest -Directory -Force | ForEach-Object { $_.FullName })) {
        $config = Join-HikariPath $dir 'portable_config'
        if (Test-Path -LiteralPath (Join-HikariPath $config @('scripts', 'hikari-palettes.lua')) -PathType Leaf) {
            return [pscustomobject]@{ ConfigDir = $config; Version = $script:HikariVersion; Commit = '' }
        }
    }
    throw (T 'source_missing' @($dest))
}

# Downloads and verifies uosc and thumbfast once for every target.
function Get-HikariArtifacts {
    param([string]$TempDir)
    $zip = Join-HikariPath $TempDir 'uosc.zip'
    Invoke-HikariVerifiedDownload -Url $script:UoscUrl -Sha256 $script:UoscSha256 -OutFile $zip
    $uoscDir = Join-HikariPath $TempDir 'uosc'
    Expand-HikariZip -Zip $zip -Destination $uoscDir
    if (-not (Test-Path -LiteralPath (Join-HikariPath $uoscDir @('scripts', 'uosc', 'main.lua')) -PathType Leaf)) {
        throw (T 'source_missing' @($script:UoscUrl))
    }
    $thumb = Join-HikariPath $TempDir 'thumbfast.lua'
    Invoke-HikariVerifiedDownload -Url $script:ThumbfastUrl -Sha256 $script:ThumbfastSha256 -OutFile $thumb
    # Anime4K is only downloaded when a folder needs it (Get-HikariAnime4KSource).
    return [pscustomobject]@{ UoscDir = $uoscDir; ThumbfastFile = $thumb; TempDir = $TempDir; Anime4KDir = '' }
}

# ---------------------------------------------------------------------------
# Anime4K and the graphics card
# ---------------------------------------------------------------------------

# Names of the graphics cards (Windows). Empty when they cannot be read (the
# card is then "unknown"); a WMI that hangs is given up after 10 seconds.
function Get-HikariGpuNames {
    try {
        return @(Get-CimInstance -ClassName Win32_VideoController -OperationTimeoutSec 10 -ErrorAction Stop |
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
function Get-HikariGpuQuality {
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
function Get-HikariGpuTier {
    param([string[]]$Names)
    $list = @($Names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    foreach ($n in $list) {
        if ((Get-HikariGpuQuality $n) -eq 'hq') { return [pscustomobject]@{ Name = $n; Quality = 'hq' } }
    }
    $real = @($list | Where-Object { $_ -notmatch '(?i)basic|virtual|remote|parsec|mirage|displaylink|citrix|vmware|hyper-v|spacedesk|indirect' })
    $name = ''
    if ($real.Count -gt 0) { $name = $real[0] } elseif ($list.Count -gt 0) { $name = $list[0] }
    return [pscustomobject]@{ Name = $name; Quality = 'fast' }
}

# hikari-upscale.conf for "Apagado" (off) or "Automatico" (auto) and the given
# quality, byte for byte what hikari-upscale.lua writes for that choice (the
# tests compare both). Neither mode has glsl-shaders lines.
function Get-HikariUpscaleConfText {
    param([string]$Quality, [string]$Mode = 'off')
    if (@('hq', 'fast') -notcontains $Quality) { $Quality = 'fast' }
    if (@('off', 'auto') -notcontains $Mode) { $Mode = 'off' }
    $lines = @(
        ('# Generated by hikari-upscale.lua. Mode: ' + $Mode + ', quality: ' + $Quality),
        ('script-opts-append=hikari_upscale-mode=' + $Mode),
        ('script-opts-append=hikari_upscale-quality=' + $Quality)
    )
    return ([string]::Join("`n", $lines) + "`n")
}

# Writes hikari-upscale.conf with $Mode and the quality that suits the graphics
# card when it is missing, or always with $Overwrite (hikari has just installed
# Anime4K here for the first time: it starts in "Automatico"). Otherwise an
# existing one holds the user's choice and is kept.
function Initialize-HikariUpscaleConf {
    param([string]$ConfigDir, [bool]$Announce, [string]$Mode = 'off', [bool]$Overwrite = $false)
    $path = Join-HikariPath $ConfigDir $script:UpscaleConf
    if (-not $Overwrite -and (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-HikariInfo (T 'kept_user_file' @($script:UpscaleConf))
        return
    }
    $gpu = Get-HikariGpuTier -Names @(& $script:HikariGpuProbe)
    Write-HikariText -Path $path -Text (Get-HikariUpscaleConfText -Quality $gpu.Quality -Mode $Mode)
    if ($Announce) {
        $name = $gpu.Name
        if (-not $name) { $name = T 'gpu_unknown' }
        Write-HikariInfo (T 'gpu_line' @($name, (T ('quality_' + $gpu.Quality))))
    }
}

# The hikari language for mpv (one of $script:MpvLanguages) of a culture name or
# a locale, the same rules as normalize() in script-modules/hikari-i18n.lua and
# mpv_language_code in hikari.sh: es-ES -> es, pt-BR -> pt, de_DE@euro -> de,
# zh-CN / zh-SG / zh-Hans -> zh-hans, zh-TW / zh-HK / zh-Hant -> zh-HK. $null for
# C, POSIX and any other language.
function ConvertTo-HikariMpvLanguage {
    param([string]$Tag)
    if ($null -eq $Tag) { return $null }
    $t = $Tag.ToLowerInvariant().Replace('_', '-').TrimStart()
    $m = [regex]::Match($t, '^[a-z0-9-]*')
    $t = $m.Value
    if ($t -eq '' -or $t -eq 'c' -or $t -eq 'posix') { return $null }
    $lang = [regex]::Match($t, '^[a-z]+').Value
    if ($lang -eq 'zh') {
        $sub = '-' + $t + '-'
        if ($sub.Contains('-hans-')) { return 'zh-hans' }
        if ($sub.Contains('-hant-') -or $sub.Contains('-tw-') -or $sub.Contains('-hk-') -or $sub.Contains('-mo-')) { return 'zh-HK' }
        return 'zh-hans'
    }
    if (@('en', 'es', 'de', 'fr', 'it', 'pl', 'pt', 'ro', 'ru', 'tr', 'uk') -contains $lang) { return $lang }
    return $null
}

# The language hikari speaks in mpv after a first install: HIKARI_MPV_LANG when
# set (tests, or whoever wants another one), else the Windows display language.
# English when it is none of $script:MpvLanguages.
function Get-HikariMpvLanguage {
    $name = $env:HIKARI_MPV_LANG
    if (-not $name) { $name = & $script:HikariUiCultureProbe }
    $code = ConvertTo-HikariMpvLanguage $name
    if ($null -eq $code) { return 'en' }
    return $code
}

# hikari-language.conf for a language code, byte for byte what
# hikari-language.lua writes for it (the tests compare both). uosc gets the same
# language; zh-HK also by the path of its file (uosc looks for it in lower case,
# which a case-sensitive file system does not find).
function Get-HikariLanguageConfText {
    param([string]$Code)
    if ($script:MpvLanguages -cnotcontains $Code) { $Code = 'en' }
    $uosc = $Code + ',en'
    if ($Code -eq 'en') { $uosc = 'en' }
    elseif ($Code -ceq 'zh-HK') { $uosc = '~~/scripts/uosc/intl/zh-HK.json,zh-HK,en' }
    $lines = @(
        ('# Generated by hikari-language.lua. Language: ' + $Code),
        ('script-opts-append=hikari-language=' + $Code),
        ('script-opts-append=uosc-languages=' + $uosc)
    )
    return ([string]::Join("`n", $lines) + "`n")
}

# Writes hikari-language.conf with the system language when it holds no choice
# yet: missing, or the copy that comes with the hikari files (only comments).
# One with a hikari-language= line is the user's and is kept.
function Initialize-HikariLanguageConf {
    param([string]$ConfigDir)
    $path = Join-HikariPath $ConfigDir $script:LanguageConf
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $text = (Read-HikariText $path).Text
        if ($text -cmatch '(?m)^script-opts-append=hikari-language=') {
            Write-HikariInfo (T 'kept_user_file' @($script:LanguageConf))
            return
        }
    }
    $code = Get-HikariMpvLanguage
    Write-HikariText -Path $path -Text (Get-HikariLanguageConfText -Code $code)
    Write-HikariInfo (T 'language_set' @($code))
}

# AnimeJaNai brings its own AI upscaling (and uses Ctrl+1..9 for it).
function Test-HikariAnimeJaNai {
    param($Candidate, [string]$ConfigDir)
    if ($Candidate.Kind -eq 'AnimeJaNai') { return $true }
    $scripts = Join-HikariPath $ConfigDir 'scripts'
    if (Test-Path -LiteralPath $scripts -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $scripts -File -Force -Filter 'animejanai*.lua').Count -gt 0) { return $true }
    }
    return $false
}

function Test-HikariOwnShaderPath {
    param([string]$Rel)
    return ((Test-HikariRecordPath $Rel) -and $Rel -cmatch '^shaders/Anime4K_[A-Za-z0-9_]+\.glsl\z')
}

# Anime4K_*.glsl files in shaders/ that hikari did not put there.
function Find-HikariManualAnime4K {
    param([string]$ConfigDir, [string[]]$Own = @())
    $dir = Join-HikariPath $ConfigDir $script:ShadersDir
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
function Expand-HikariAnime4K {
    param([string]$Zip, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-HikariDirectory $Destination
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -cnotmatch $script:Anime4KPattern) { continue }
            $out = Join-HikariPath $Destination $entry.FullName
            Assert-HikariInside -Path $out -Root $Destination
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $out, $true)
        }
    }
    finally {
        $archive.Dispose()
    }
    $missing = @($script:Anime4KRequired | Where-Object { -not (Test-Path -LiteralPath (Join-HikariPath $Destination $_) -PathType Leaf) })
    if ($missing.Count -gt 0) { throw (T 'anime4k_bad_zip' @([string]::Join(', ', $missing))) }
}

# Downloads, checks and extracts Anime4K the first time a folder needs it; the
# other folders of the same run reuse it.
function Get-HikariAnime4KSource {
    param($Artifacts)
    $cached = $Artifacts.PSObject.Properties['Anime4KDir']
    if ($null -ne $cached -and $cached.Value) { return [string]$cached.Value }
    # A download that already failed in this run is not tried again for each folder.
    $failed = $Artifacts.PSObject.Properties['Anime4KError']
    if ($null -ne $failed -and $failed.Value) { throw [string]$failed.Value }
    try {
        $temp = $Artifacts.PSObject.Properties['TempDir']
        if ($null -eq $temp -or -not $temp.Value) { throw (T 'source_missing' @($script:Anime4KUrl)) }
        $zip = Join-HikariPath $temp.Value 'anime4k.zip'
        Invoke-HikariVerifiedDownload -Url $script:Anime4KUrl -Sha256 $script:Anime4KSha256 -OutFile $zip
        $dest = Join-HikariPath $temp.Value 'anime4k'
        Expand-HikariAnime4K -Zip $zip -Destination $dest
    }
    catch {
        $Artifacts | Add-Member -NotePropertyName 'Anime4KError' -NotePropertyValue $_.Exception.Message -Force
        throw
    }
    $Artifacts | Add-Member -NotePropertyName 'Anime4KDir' -NotePropertyValue $dest -Force
    return $dest
}

# True when hikari's Anime4K of this version is in place: the record says this
# version and every shader hikari-upscale.lua needs is there, recorded as hikari's.
function Test-HikariAnime4KComplete {
    param([string]$ConfigDir, [string[]]$Own, [string]$Version)
    if ($Version -ne $script:Anime4KVersion) { return $false }
    foreach ($name in $script:Anime4KRequired) {
        $rel = $script:ShadersDir + '/' + $name
        if (@($Own) -cnotcontains $rel) { return $false }
        if (-not (Test-Path -LiteralPath (Join-HikariPath $ConfigDir @($script:ShadersDir, $name)) -PathType Leaf)) { return $false }
    }
    return $true
}

# Copies the extracted shaders into <config>/shaders. Returns their record
# paths; the ones not yet recorded ($Own) are added to the record first.
function Install-HikariAnime4KFiles {
    param([string]$ConfigDir, [string]$SourceDir, [string[]]$Own = @())
    $dir = Join-HikariPath $ConfigDir $script:ShadersDir
    New-HikariDirectory $dir
    $sources = @(Get-ChildItem -LiteralPath $SourceDir -File -Force | Where-Object { $_.Name -cmatch $script:Anime4KPattern } | Sort-Object Name)
    $rels = @($sources | ForEach-Object { $script:ShadersDir + '/' + $_.Name })
    Add-HikariRecordEntries -ConfigDir $ConfigDir -Entries @($rels | Where-Object { @($Own) -cnotcontains $_ } | ForEach-Object { 'file=' + $_ })
    foreach ($f in $sources) {
        $dest = Join-HikariPath $dir $f.Name
        Assert-HikariInside -Path $dest -Root $ConfigDir
        Assert-HikariNoLink -Path $dest -Root $ConfigDir
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    }
    return $rels
}

# Moves a shader installed by hand into shaders-desactivados. Returns
# "moved|original" (relative), like Move-HikariToDisabled.
function Move-HikariShaderAside {
    param([string]$Path, [string]$ConfigDir, [string]$Stamp, [switch]$Record)
    Assert-HikariInside -Path $Path -Root $ConfigDir
    $rel = Get-HikariRelativePath -Path $Path -Root $ConfigDir
    $destDir = Join-HikariPath $ConfigDir $script:ShadersDisabledDir
    New-HikariDirectory $destDir
    $name = Split-Path -Path $Path -Leaf
    $dest = Join-HikariPath $destDir $name
    if (Test-Path -LiteralPath $dest) {
        $dest = Join-HikariPath $destDir ([System.IO.Path]::GetFileNameWithoutExtension($name) + '-' + $Stamp + [System.IO.Path]::GetExtension($name))
    }
    Assert-HikariInside -Path $dest -Root $ConfigDir
    Assert-HikariNoLink -Path $Path -Root $ConfigDir
    Assert-HikariNoLink -Path $dest -Root $ConfigDir
    $destRel = Get-HikariRelativePath -Path $dest -Root $ConfigDir
    if ($Record) { Add-HikariRecordEntries -ConfigDir $ConfigDir -Entries @('a4k_moved=' + $destRel + '|' + $rel) }
    Move-Item -LiteralPath $Path -Destination $dest
    Write-HikariInfo (T 'moved' @($rel, $destRel))
    return ($destRel + '|' + $rel)
}

# An input.conf line (without the hikari prefix) that binds Ctrl+0..Ctrl+6 to
# something that changes glsl-shaders, as Anime4K's templates do.
function Test-HikariAnime4KKeyLine {
    param([string]$Line)
    $c = $Line.Trim()
    if ($c -eq '' -or $c.StartsWith('#')) { return $false }
    $m = [regex]::Match($c, '^(\S+)\s+(.*)$')
    if (-not $m.Success) { return $false }
    $key = ConvertTo-HikariKeyName $m.Groups[1].Value
    if (@('ctrl+0', 'ctrl+1', 'ctrl+2', 'ctrl+3', 'ctrl+4', 'ctrl+5', 'ctrl+6') -cnotcontains $key) { return $false }
    return ($m.Groups[2].Value -match 'glsl-shaders')
}

# Those lines of input.conf, outside the hikari block: Index and Content.
function Find-HikariAnime4KKeyLines {
    param([string]$Text)
    return @(Get-HikariOutsideLines -Text $Text -Name 'input.conf' | Where-Object { Test-HikariAnime4KKeyLine $_.Content })
}

# mpv.conf lines outside the hikari block that turn Anime4K on at start-up
# ($script:Anime4KConfPattern), as Anime4K's templates do.
function Test-HikariAnime4KConfLine {
    param([string]$Line)
    return ($Line -match $script:Anime4KConfPattern)
}

function Find-HikariAnime4KConfLines {
    param([string]$Text)
    return @(Get-HikariOutsideLines -Text $Text -Name 'mpv.conf' | Where-Object { Test-HikariAnime4KConfLine $_.Content })
}

# mpv.conf lines outside the hikari block that turn mpv's own controller off.
function Find-HikariOscOffLines {
    param([string]$Text)
    return @(Get-HikariOutsideLines -Text $Text -Name 'mpv.conf' | Where-Object {
            $_.Content -match '^\s*(osc\s*=\s*"?(no|false)"?|no-osc)\s*(#.*)?$' })
}

# Rewrites some lines of a file ($Map: line index -> new content), keeping its
# encoding, BOM and every line ending.
function Update-HikariLines {
    param([string]$Path, [hashtable]$Map)
    $file = Read-HikariText $Path
    $sb = New-Object System.Text.StringBuilder
    $lines = @(Split-HikariLines $file.Text)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $content = $lines[$i].Content
        if ($Map.ContainsKey($i)) { $content = [string]$Map[$i] }
        [void]$sb.Append($content + $lines[$i].Eol)
    }
    Write-HikariText -Path $Path -Text $sb.ToString() -Encoding $file.Encoding -Bom $file.Bom
}

# Turns lines off by putting $script:CommentPrefix in front of them (never deleted).
function Set-HikariLinesCommented {
    param([string]$Path, [object[]]$Lines)
    $map = @{}
    foreach ($l in $Lines) { $map[[int]$l.Index] = $script:CommentPrefix + $l.Content }
    if ($map.Count -gt 0) { Update-HikariLines -Path $Path -Map $map }
}

# Turns lines off like Set-HikariLinesCommented, adding them to the record
# ("$Key=<trimmed line>") first. Lines that could not be read back from the
# record (see Test-HikariRecordableLine) are left on. Returns $Previous plus the
# new entries.
function Set-HikariLinesOffRecorded {
    param([string]$Path, [string]$ConfigDir, [object[]]$Lines, [string]$Key, [string[]]$Previous = @())
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($p in $Previous) { $list.Add($p) }
    $ok = @($Lines | Where-Object { Test-HikariRecordableLine $_.Content.Trim() })
    $new = New-Object System.Collections.Generic.List[string]
    foreach ($l in $ok) {
        $t = $l.Content.Trim()
        if (-not $list.Contains($t)) { $list.Add($t); $new.Add($t) }
    }
    Add-HikariRecordEntries -ConfigDir $ConfigDir -Entries @($new | ForEach-Object { $Key + '=' + $_ })
    Set-HikariLinesCommented -Path $Path -Lines $ok
    return $list.ToArray()
}

# Lines hikari turned off outside the hikari block of a file and recorded
# ($Recorded: their trimmed text) that are still there and still pass $Test:
# Index and the original Content to put back.
function Find-HikariCommentedLines {
    param([string]$Text, [string]$Name, [string[]]$Recorded, [scriptblock]$Test)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($l in @(Get-HikariOutsideLines -Text $Text -Name $Name)) {
        if (-not $l.Content.StartsWith($script:CommentPrefix)) { continue }
        $rest = $l.Content.Substring($script:CommentPrefix.Length)
        if (@($Recorded) -ccontains $rest.Trim() -and (& $Test $rest)) {
            $out.Add([pscustomobject]@{ Index = $l.Index; Content = $rest })
        }
    }
    return $out.ToArray()
}

# input.conf: Anime4K keys hikari turned off.
function Find-HikariCommentedKeyLines {
    param([string]$Text, [string[]]$Recorded)
    return @(Find-HikariCommentedLines -Text $Text -Name 'input.conf' -Recorded $Recorded -Test { param($l) Test-HikariAnime4KKeyLine $l })
}

# mpv.conf: Anime4K glsl-shaders lines hikari turned off.
function Find-HikariCommentedConfLines {
    param([string]$Text, [string[]]$Recorded)
    return @(Find-HikariCommentedLines -Text $Text -Name 'mpv.conf' -Recorded $Recorded -Test { param($l) Test-HikariAnime4KConfLine $l })
}

# Decides what to do with Anime4K in one folder and does it. Returns State
# (hikari: installed and managed by hikari; declined; failed: the download or its
# check failed, asked again next time; manual: one installed by hand is left
# alone; animejanai), Files (record paths of hikari's shaders), Moved
# ("moved|original" of the hand-installed ones set aside), Commented and
# CommentedMpv (input.conf and mpv.conf lines turned off), Version and Fresh
# (hikari installed Anime4K in this run and it was not hikari's before: a new
# install, or one installed by hand taken over).
# Anime4K is downloaded and checked before anything in the folder is moved or
# changed, and every change is added to the record before it is made.
function Invoke-HikariAnime4KStep {
    param($Candidate, [string]$ConfigDir, $Artifacts, [string]$Stamp,
        [hashtable]$OldValues, [string[]]$OldFiles = @(), [string[]]$OldMoved = @(), [string[]]$OldCommented = @(),
        [string[]]$OldCommentedMpv = @())
    $choice = $script:HikariAnime4KChoice
    $prevState = ''
    if ($OldValues.ContainsKey('anime4k')) { $prevState = [string]$OldValues['anime4k'] }
    $own = @($OldFiles | Where-Object { Test-HikariOwnShaderPath $_ })
    $result = [pscustomobject]@{ State = ''; Files = $own; Moved = @($OldMoved); Commented = @($OldCommented)
        CommentedMpv = @($OldCommentedMpv); Version = ''; Fresh = $false }
    if ($OldValues.ContainsKey('anime4k_version')) { $result.Version = [string]$OldValues['anime4k_version'] }

    if (Test-HikariAnimeJaNai -Candidate $Candidate -ConfigDir $ConfigDir) {
        Write-HikariInfo (T 'anime4k_animejanai')
        $result.State = 'animejanai'
        return $result
    }

    $manual = @(Find-HikariManualAnime4K -ConfigDir $ConfigDir -Own $own)
    $takeOver = $false
    $update = $false
    if ($manual.Count -gt 0) {
        Write-HikariWarn (T 'anime4k_manual' @($script:ShadersDir, $manual.Count))
        $manage = $false
        if ($choice -eq 'yes') { $manage = $true }
        elseif ($choice -ne 'no' -and $prevState -ne 'manual') {
            $manage = Confirm-Hikari -Question (T 'anime4k_manage' @($script:ShadersDisabledDir)) -Default $false
        }
        if (-not $manage) {
            Write-HikariWarn (T 'anime4k_manual_kept')
            $result.State = 'manual'
            return $result
        }
        $takeOver = $true
    }
    elseif ($prevState -eq 'hikari' -and $own.Count -gt 0) {
        $update = $true
        if ($choice -eq 'no') {
            Write-HikariInfo (T 'anime4k_kept')
            $result.State = 'hikari'
            return $result
        }
        if (Test-HikariAnime4KComplete -ConfigDir $ConfigDir -Own $own -Version $result.Version) {
            Write-HikariInfo (T 'anime4k_uptodate' @($script:Anime4KVersion))
            $result.State = 'hikari'
            return $result
        }
    }
    else {
        $install = ($choice -eq 'yes')
        if ($choice -eq '') {
            Write-HikariInfo (T 'anime4k_intro')
            $install = Confirm-Hikari -Question (T 'anime4k_confirm') -Default ($prevState -ne 'declined')
        }
        if (-not $install) {
            Write-HikariInfo (T 'anime4k_declined')
            $result.State = 'declined'
            return $result
        }
    }

    # Download and check Anime4K before touching anything. If that fails, the
    # rest of hikari is still installed: an earlier copy of hikari's stays, and
    # otherwise Anime4K is left out and offered again (yes by default).
    try { $src = Get-HikariAnime4KSource -Artifacts $Artifacts }
    catch {
        Write-HikariWarn (T 'anime4k_failed' @($_.Exception.Message))
        if ($update) { $result.State = 'hikari' } else { $result.State = 'failed' }
        return $result
    }

    if ($takeOver) {
        $moved = New-Object System.Collections.Generic.List[string]
        foreach ($m in $result.Moved) { $moved.Add($m) }
        foreach ($p in $manual) { $moved.Add((Move-HikariShaderAside -Path $p -ConfigDir $ConfigDir -Stamp $Stamp -Record)) }
        $result.Moved = $moved.ToArray()

        $inputPath = Join-HikariPath $ConfigDir 'input.conf'
        if (Test-Path -LiteralPath $inputPath -PathType Leaf) {
            $keys = @(Find-HikariAnime4KKeyLines (Read-HikariText $inputPath).Text)
            if ($keys.Count -gt 0) {
                Write-HikariWarn (T 'anime4k_keys_found')
                foreach ($k in $keys) { Write-HikariWarn ('  ' + $k.Content.Trim()) }
                $comment = ($choice -eq 'yes')
                if (-not $comment) { $comment = Confirm-Hikari -Question (T 'anime4k_comment') -Default $true }
                if ($comment) {
                    $result.Commented = @(Set-HikariLinesOffRecorded -Path $inputPath -ConfigDir $ConfigDir -Lines $keys `
                            -Key 'a4k_commented' -Previous $result.Commented)
                    Write-HikariInfo (T 'anime4k_commented' @($keys.Count))
                }
            }
        }
    }

    # An Anime4K line of the user's in mpv.conf (Anime4K's templates have one)
    # would keep a mode on from start-up, even with "Apagado", now that the
    # shaders are there. Asked when hikari starts managing Anime4K, not on updates.
    $mpvPath = Join-HikariPath $ConfigDir 'mpv.conf'
    if (-not $update -and (Test-Path -LiteralPath $mpvPath -PathType Leaf)) {
        $confLines = @(Find-HikariAnime4KConfLines (Read-HikariText $mpvPath).Text)
        if ($confLines.Count -gt 0) {
            Write-HikariWarn (T 'anime4k_conf_found')
            foreach ($l in $confLines) { Write-HikariWarn ('  ' + $l.Content.Trim()) }
            $comment = ($choice -eq 'yes')
            if (-not $comment) { $comment = Confirm-Hikari -Question (T 'anime4k_conf_comment') -Default $true }
            if ($comment) {
                $result.CommentedMpv = @(Set-HikariLinesOffRecorded -Path $mpvPath -ConfigDir $ConfigDir -Lines $confLines `
                        -Key 'a4k_commented_mpv' -Previous $result.CommentedMpv)
                Write-HikariInfo (T 'anime4k_conf_commented' @($confLines.Count))
            }
        }
    }

    $files = @(Install-HikariAnime4KFiles -ConfigDir $ConfigDir -SourceDir $src -Own $own)
    # Files of an earlier Anime4K install by hikari that this one no longer has.
    foreach ($f in $own) {
        if ($files -contains $f) { continue }
        $p = Join-HikariPath $ConfigDir ($f -split '/')
        if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-HikariItem -Path $p -Root $ConfigDir }
    }
    Write-HikariOk (T 'anime4k_done' @($script:Anime4KVersion, $files.Count, $script:ShadersDir))
    $result.State = 'hikari'
    $result.Files = $files
    $result.Version = $script:Anime4KVersion
    $result.Fresh = (-not $update)
    return $result
}

# ---------------------------------------------------------------------------
# Migration from sosc (the name of hikari until v0.3.0)
# ---------------------------------------------------------------------------

# Is there anything of sosc in the folder? Its record, scripts, options, choice
# files or managed blocks.
function Test-HikariSoscPresent {
    param([string]$ConfigDir)
    if (-not $ConfigDir -or -not (Test-Path -LiteralPath $ConfigDir -PathType Container)) { return $false }
    if (Test-Path -LiteralPath (Join-HikariPath $ConfigDir $script:SoscRecordName)) { return $true }
    foreach ($p in @(Get-HikariSoscFiles $ConfigDir)) {
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $true }
    }
    foreach ($n in $script:SoscChoices) {
        if (Test-Path -LiteralPath (Join-HikariPath $ConfigDir ('sosc-' + $n + '.conf')) -PathType Leaf) { return $true }
    }
    foreach ($name in @('mpv.conf', 'input.conf')) {
        $p = Join-HikariPath $ConfigDir $name
        if ((Test-Path -LiteralPath $p -PathType Leaf) -and (Read-HikariText $p).Text.Contains($script:SoscBlockBegin)) { return $true }
    }
    return $false
}

# The paths in the folder of the scripts and options sosc 0.3.0 installed
# (whether they are there or not).
function Get-HikariSoscFiles {
    param([string]$ConfigDir)
    $paths = @()
    foreach ($n in $script:SoscLuaFiles) { $paths += (Join-HikariPath $ConfigDir @('scripts', ('sosc-' + $n + '.lua'))) }
    foreach ($n in $script:SoscConfFiles) { $paths += (Join-HikariPath $ConfigDir @('script-opts', ('sosc-' + $n + '.conf'))) }
    return $paths
}

# The text with the names of sosc's scripts, options and files changed to
# hikari's (sosc_palettes/open-menu, script-message-to sosc_upscale,
# sosc-subs.conf, sosc-update-enabled=...). Only whole names: at the start of a
# line or after a character that is not a letter, digit, _ or - (so
# mysosc_skipper stays as it is).
function ConvertFrom-HikariSoscText {
    param([string]$Text)
    $names = [string]::Join('|', @($script:SoscScripts | ForEach-Object { [regex]::Escape($_) }))
    return [regex]::Replace($Text, '(?<![A-Za-z0-9_-])sosc(?=[_-](?:' + $names + '))', 'hikari', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
}

# mpv.conf or input.conf: the sosc block becomes the hikari block, in the same
# place (or goes, when there is a hikari block already); the lines sosc turned
# off and recorded ($Recorded) get the hikari prefix, so uninstalling hikari
# turns them back on; and lines of the user's own that use sosc's names are
# changed to hikari's, with one warning each. Encoding, BOM and line ends kept.
function Update-HikariSoscFile {
    param([string]$ConfigDir, [string]$Name, [string[]]$Recorded = @())
    $path = Join-HikariPath $ConfigDir $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $file = Read-HikariText $path
    $text = $file.Text
    $lines = @(Split-HikariLines $text)
    $hikariBlock = Find-HikariBlock -Lines $lines -Name $Name
    $soscBlock = Find-HikariBlock -Lines $lines -Name ($Name + ' (sosc)') -BeginMarker $script:SoscBlockBegin -EndMarker $script:SoscBlockEnd
    $map = @{}
    $skip = @{}
    if ($null -ne $soscBlock) {
        if ($null -ne $hikariBlock) {
            $text = Remove-HikariBlockText -Text $text -Name ($Name + ' (sosc)') -BeginMarker $script:SoscBlockBegin -EndMarker $script:SoscBlockEnd
            $lines = @(Split-HikariLines $text)
        }
        else {
            $map[$soscBlock.Begin] = $script:BlockBegin
            $map[$soscBlock.End] = $script:BlockEnd
            for ($i = $soscBlock.Begin; $i -le $soscBlock.End; $i++) { $skip[$i] = $true }
        }
    }
    foreach ($l in @(Get-HikariOutsideLines -Text $text -Name $Name)) {
        if ($skip.ContainsKey($l.Index)) { continue }
        if ($l.Content.StartsWith($script:SoscCommentPrefix)) {
            $rest = $l.Content.Substring($script:SoscCommentPrefix.Length)
            if (@($Recorded) -ccontains $rest.Trim()) { $map[$l.Index] = $script:CommentPrefix + $rest }
            continue
        }
        $t = $l.Content.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $converted = ConvertFrom-HikariSoscText $l.Content
        if ($converted -cne $l.Content) {
            $map[$l.Index] = $converted
            # Control characters of the line are not sent to the terminal.
            Write-HikariWarn (T 'sosc_line_changed' @($Name, ($converted.Trim() -replace '\p{Cc}', '')))
        }
    }
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $content = $lines[$i].Content
        if ($map.ContainsKey($i)) { $content = [string]$map[$i] }
        [void]$sb.Append($content + $lines[$i].Eol)
    }
    $newText = $sb.ToString()
    if ($newText -cne $file.Text) { Write-HikariText -Path $path -Text $newText -Encoding $file.Encoding -Bom $file.Bom }
}

# Carries an installation of sosc over to hikari, after the backup and before
# anything else. The record of sosc becomes the record of hikari (what sosc set
# aside, turned off or found there before it), so uninstalling hikari puts
# everything back as it was before sosc; sosc's choices are kept under hikari's
# names; then everything of sosc goes. Each step can run again: a migration cut
# short is finished by the next run. Old sosc backups are left alone (hikari's
# rotation only counts its own).
function Invoke-HikariSoscMigration {
    param([string]$ConfigDir)
    if (-not (Test-HikariSoscPresent $ConfigDir)) { return }
    Write-HikariInfo (T 'sosc_found')
    # A broken block stops everything before any change.
    foreach ($name in @('mpv.conf', 'input.conf')) {
        $p = Join-HikariPath $ConfigDir $name
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        $lines = @(Split-HikariLines (Read-HikariText $p).Text)
        [void](Find-HikariBlock -Lines $lines -Name $name)
        [void](Find-HikariBlock -Lines $lines -Name ($name + ' (sosc)') -BeginMarker $script:SoscBlockBegin -EndMarker $script:SoscBlockEnd)
    }

    $old = Read-HikariRecord $ConfigDir -NoWarn -Name $script:SoscRecordName
    $commented = @()
    $commentedMpv = @()
    if ($null -ne $old) { $commented = @($old.Commented); $commentedMpv = @($old.CommentedMpv) }
    Update-HikariSoscFile -ConfigDir $ConfigDir -Name 'mpv.conf' -Recorded $commentedMpv
    Update-HikariSoscFile -ConfigDir $ConfigDir -Name 'input.conf' -Recorded $commented

    # The user's choices, with their keys under hikari's names.
    foreach ($n in $script:SoscChoices) {
        $from = Join-HikariPath $ConfigDir ('sosc-' + $n + '.conf')
        $to = Join-HikariPath $ConfigDir ('hikari-' + $n + '.conf')
        if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { continue }
        # Never written through a link (broken or not).
        $toItem = Get-Item -LiteralPath $to -Force -ErrorAction SilentlyContinue
        if ($null -ne $toItem -and (Test-HikariLink $toItem)) { Write-HikariWarn (T 'sosc_link_left' @($to)) }
        elseif (-not (Test-Path -LiteralPath $to)) {
            $file = Read-HikariText $from
            Write-HikariText -Path $to -Text (ConvertFrom-HikariSoscText $file.Text) -Encoding $file.Encoding -Bom $file.Bom
            Write-HikariInfo (T 'sosc_choice_moved' @(('sosc-' + $n + '.conf'), ('hikari-' + $n + '.conf')))
        }
        Remove-HikariItem -Path $from -Root $ConfigDir
    }

    # The user's uosc.conf and thumbfast.conf from before sosc.
    $soscOrig = Join-HikariPath $ConfigDir $script:SoscOriginalsDir
    $item = Get-Item -LiteralPath $soscOrig -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and $item.PSIsContainer -and -not (Test-HikariLink $item)) {
        $fromOpts = Join-HikariPath $soscOrig 'script-opts'
        $toOpts = Join-HikariPath $ConfigDir @($script:OriginalsDir, 'script-opts')
        if (Test-Path -LiteralPath $fromOpts -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $fromOpts -File -Force)) {
                $dest = Join-HikariPath $toOpts $f.Name
                if (Test-Path -LiteralPath $dest) { continue }
                Assert-HikariNoLink -Path $f.FullName -Root $ConfigDir
                Assert-HikariNoLink -Path $dest -Root $ConfigDir
                New-HikariDirectory $toOpts
                Move-Item -LiteralPath $f.FullName -Destination $dest
            }
        }
        Remove-HikariItem -Path $soscOrig -Root $ConfigDir
    }

    # The record. When hikari has one already (a migration cut short after
    # writing it), that one has everything.
    $recPath = Join-HikariPath $ConfigDir $script:RecordName
    $recItem = Get-Item -LiteralPath $recPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $old -and $null -ne $recItem -and (Test-HikariLink $recItem)) { Write-HikariWarn (T 'sosc_link_left' @($recPath)) }
    elseif ($null -ne $old -and -not (Test-Path -LiteralPath $recPath)) {
        $values = [ordered]@{}
        foreach ($key in @($old.Values.Keys | Sort-Object)) {
            $k = [string]$key
            $v = [string]$old.Values[$key]
            if ($k -ceq 'sosc_version') { $k = 'hikari_version' }
            elseif ($k -ceq 'sosc_commit') { $k = 'hikari_commit' }
            elseif ($k -ceq 'anime4k' -and $v -ceq 'sosc') { $v = 'hikari' }
            $values[$k] = $v
        }
        $files = @($old.Files | Where-Object { $_ -cnotmatch '^(scripts|script-opts)/sosc-' })
        Write-HikariRecord -ConfigDir $ConfigDir -Values $values -Files $files -Disabled @($old.Disabled) -Moved @($old.Moved) `
            -Commented @($old.Commented) -CommentedMpv @($old.CommentedMpv) -Broken @($old.Broken)
    }

    # Everything else of sosc goes (it is all in the backup).
    foreach ($p in @(Get-HikariSoscFiles $ConfigDir)) {
        if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-HikariItem -Path $p -Root $ConfigDir }
    }
    foreach ($name in @($script:SoscUpdateState, ($script:SoscUpdateState + '.tmp'), $script:SoscRecordName)) {
        $p = Join-HikariPath $ConfigDir $name
        if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-HikariItem -Path $p -Root $ConfigDir }
    }
    Write-HikariOk (T 'sosc_done')

    $full = Get-HikariFullPath $ConfigDir
    $parent = Split-Path -Path $full -Parent
    $prefix = (Split-Path -Path $full -Leaf) + '-respaldo-sosc-'
    $count = 0
    if ($parent -and (Test-Path -LiteralPath $parent -PathType Container)) {
        try {
            foreach ($d in @(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction Stop)) {
                if ($d.Name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -and -not (Test-HikariLink $d)) { $count++ }
            }
        }
        catch { }
    }
    if ($count -gt 0) { Write-HikariInfo (T 'sosc_old_backups' @($count, $full)) }
}

# ---------------------------------------------------------------------------
# Install steps
# ---------------------------------------------------------------------------

# Copies what the installer may change ($script:BackupItems) to
# <config>-respaldo-hikari-<stamp>, next to it. Links are skipped, not followed.
# Returns '' when there is nothing to copy. A copy that fails half-way is deleted.
function New-HikariBackup {
    param([string]$ConfigDir, [string]$Stamp = '')
    if (-not $Stamp) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }
    $full = Get-HikariFullPath $ConfigDir
    $parent = Split-Path -Path $full -Parent
    if (-not $parent) { throw (T 'target_root' @($full)) }
    $items = @()
    foreach ($name in $script:BackupItems) {
        $p = Join-HikariPath $full $name
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        if (Test-HikariLink $item) { Write-HikariWarn (T 'link_skipped' @($item.FullName)); continue }
        $items += $item
    }
    if ($items.Count -eq 0) { return '' }

    $base = $full + '-respaldo-hikari-' + $Stamp
    $backup = $base
    $n = 2
    while (Test-Path -LiteralPath $backup) { $backup = $base + '-' + $n; $n++ }
    $bytes = [long]0
    foreach ($item in $items) { $bytes += (Get-HikariTreeSize $item) }
    Write-HikariInfo (T 'backup_size' @([math]::Round($bytes / 1MB, 1)))
    New-HikariDirectory $backup
    try {
        foreach ($item in $items) {
            $dest = Join-HikariPath $backup $item.Name
            if ($item.PSIsContainer) { Copy-HikariTree -From $item.FullName -To $dest }
            else { Copy-Item -LiteralPath $item.FullName -Destination $dest -Force }
        }
    }
    catch {
        $failure = $_
        try { Remove-HikariItem -Path $backup -Root $parent } catch { }
        throw $failure
    }
    return $backup
}

# Keeps the newest $Keep backups of this folder (<config>-respaldo-hikari-<stamp>,
# siblings of it) and deletes the older ones. Only folders whose name is
# exactly that pattern for this folder are considered; links are never touched.
# The backup from before hikari's first install is never deleted: the one that
# holds $script:BackupOriginalMark, and $Protect (the record's first_backup).
function Remove-HikariOldBackups {
    param([string]$ConfigDir, [int]$Keep = $script:BackupKeep, [string[]]$Protect = @())
    $full = Get-HikariFullPath $ConfigDir
    $parent = Split-Path -Path $full -Parent
    if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { return }
    $re = '^' + [regex]::Escape((Split-Path -Path $full -Leaf)) + '-respaldo-hikari-(\d{8}-\d{6})(?:-(\d+))?\z'
    $found = New-Object System.Collections.Generic.List[object]
    $dirs = @()
    try { $dirs = @(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction Stop) }
    catch { Write-HikariWarn (T 'backup_prune_failed' @($parent, $_.Exception.Message)); return }
    foreach ($d in $dirs) {
        $m = [regex]::Match($d.Name, $re, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $m.Success -or (Test-HikariLink $d)) { continue }
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
            try { if ($p -and (Test-HikariSamePath $p $old)) { $keepIt = $true } } catch { }
        }
        if (Test-HikariOriginalBackup $old) { $keepIt = $true }
        if ($keepIt) { continue }
        try {
            Assert-HikariInside -Path $old -Root $parent
            Remove-HikariItem -Path $old -Root $parent
            Write-HikariInfo (T 'backup_pruned' @($old))
        }
        catch {
            Write-HikariWarn (T 'backup_prune_failed' @($old, $_.Exception.Message))
        }
    }
}

# A backup made before hikari's first install (it holds the mark file).
function Test-HikariOriginalBackup {
    param([string]$Path)
    return (Test-Path -LiteralPath (Join-HikariPath $Path $script:BackupOriginalMark) -PathType Leaf)
}

# Backups of this folder (<config>-respaldo-hikari-*, siblings, not links) that
# hold the mark of the backup from before hikari's first install.
function Find-HikariOriginalBackups {
    param([string]$ConfigDir)
    $full = Get-HikariFullPath $ConfigDir
    $parent = Split-Path -Path $full -Parent
    if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { return @() }
    $prefix = (Split-Path -Path $full -Leaf) + '-respaldo-hikari-'
    $found = @()
    try {
        foreach ($d in @(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction Stop)) {
            if ($d.Name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -and -not (Test-HikariLink $d) -and
                (Test-HikariOriginalBackup $d.FullName)) { $found += $d.FullName }
        }
    }
    catch { }
    return $found
}

function Get-HikariRelativePath {
    param([string]$Path, [string]$Root)
    $full = Get-HikariFullPath $Path
    $rootFull = Get-HikariFullPath $Root
    return $full.Substring($rootFull.Length).TrimStart([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)).Replace('\', '/')
}

function Find-HikariConflicts {
    param([string]$ConfigDir)
    $found = New-Object System.Collections.Generic.List[string]
    $scripts = Join-HikariPath $ConfigDir 'scripts'
    if (-not (Test-Path -LiteralPath $scripts -PathType Container)) { return $found.ToArray() }
    foreach ($item in @(Get-ChildItem -LiteralPath $scripts -File -Force)) {
        foreach ($pattern in $script:ConflictPatterns) {
            if ($item.Name -like $pattern) { $found.Add($item.FullName); break }
        }
    }
    $names = @($found | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) })
    $opts = Join-HikariPath $ConfigDir 'script-opts'
    foreach ($n in $names) {
        $conf = Join-HikariPath $opts ($n + '.conf')
        if (Test-Path -LiteralPath $conf -PathType Leaf) { $found.Add($conf) }
    }
    $fonts = Join-HikariPath $ConfigDir 'fonts'
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

# A file in scripts/ named *.lua whose first line shows it is the page a failed
# download saved instead of the script: "404: Not Found" (GitHub raw), "Not
# Found", or an HTML page. mpv logs an error for each one at start-up.
function Test-HikariBrokenScript {
    param([string]$Path)
    $first = $null
    try {
        $reader = New-Object System.IO.StreamReader($Path, $true)
        try { $first = $reader.ReadLine() } finally { $reader.Dispose() }
    }
    catch { return $false }
    if ($null -eq $first) { return $false }
    $first = $first.Trim([char[]]@([char]0xFEFF, ' ', "`t", "`r"))
    return ($first -match '(?i)^(404:?\s*)?Not Found\s*$' -or $first -match '(?i)^<!DOCTYPE|^<html')
}

# Those files in scripts/ (only at its top level, where mpv loads them).
function Find-HikariBrokenScripts {
    param([string]$ConfigDir)
    $scripts = Join-HikariPath $ConfigDir 'scripts'
    if (-not (Test-Path -LiteralPath $scripts -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $scripts -File -Force -Filter '*.lua' |
            Where-Object { -not (Test-HikariLink $_) -and (Test-HikariBrokenScript $_.FullName) } | ForEach-Object { $_.FullName })
}

# Moves a file or folder of the config into scripts-desactivados, keeping its
# sub-folder (scripts/, script-opts/, fonts/). Returns "moved|original" (relative).
function Move-HikariToDisabled {
    param([string]$Path, [string]$ConfigDir, [string]$Stamp)
    Assert-HikariInside -Path $Path -Root $ConfigDir
    $rel = Get-HikariRelativePath -Path $Path -Root $ConfigDir
    $sub = Split-Path -Path $rel -Parent
    $destDir = Join-HikariPath $ConfigDir $script:DisabledDir
    if ($sub -and $sub -ne 'scripts') { $destDir = Join-HikariPath $destDir ($sub -split '[\\/]') }
    New-HikariDirectory $destDir
    $name = Split-Path -Path $Path -Leaf
    $dest = Join-HikariPath $destDir $name
    if (Test-Path -LiteralPath $dest) {
        $ext = [System.IO.Path]::GetExtension($name)
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)
        if ((Get-Item -LiteralPath $Path -Force).PSIsContainer) { $ext = ''; $stem = $name }
        $dest = Join-HikariPath $destDir ($stem + '-' + $Stamp + $ext)
    }
    Assert-HikariInside -Path $dest -Root $ConfigDir
    Assert-HikariNoLink -Path $Path -Root $ConfigDir
    Assert-HikariNoLink -Path $dest -Root $ConfigDir
    Move-Item -LiteralPath $Path -Destination $dest
    $destRel = Get-HikariRelativePath -Path $dest -Root $ConfigDir
    Write-HikariInfo (T 'moved' @($rel, $destRel))
    return ($destRel + '|' + $rel)
}

function Install-HikariUosc {
    param([string]$ConfigDir, [string]$UoscDir, [string]$Stamp)
    $scripts = Join-HikariPath $ConfigDir 'scripts'
    New-HikariDirectory $scripts
    $moved = @()
    foreach ($legacy in $script:UoscLegacy) {
        $p = Join-HikariPath $scripts $legacy
        if (Test-Path -LiteralPath $p) { $moved += Move-HikariToDisabled -Path $p -ConfigDir $ConfigDir -Stamp $Stamp }
    }
    $dest = Join-HikariPath $scripts 'uosc'
    Remove-HikariItem -Path $dest -Root $ConfigDir
    Copy-HikariTree -From (Join-HikariPath $UoscDir @('scripts', 'uosc')) -To $dest
    $fonts = Join-HikariPath $ConfigDir 'fonts'
    New-HikariDirectory $fonts
    foreach ($font in $script:UoscFonts) {
        $src = Join-HikariPath $UoscDir @('fonts', $font)
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Copy-Item -LiteralPath $src -Destination (Join-HikariPath $fonts $font) -Force
        }
    }
    return $moved
}

function Test-HikariUoscPresent {
    param([string]$ConfigDir)
    return ((Test-Path -LiteralPath (Join-HikariPath $ConfigDir @('scripts', 'uosc')) -PathType Container) -or
        (Test-Path -LiteralPath (Join-HikariPath $ConfigDir @('scripts', 'uosc.lua')) -PathType Leaf))
}

function Install-HikariTarget {
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)]$Artifacts,
        [string]$Stamp = ''
    )
    if (-not $Stamp) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }
    $config = Get-HikariFullPath $Candidate.ConfigDir
    Write-HikariInfo ''
    Write-HikariInfo (T 'installing_to' @($config))

    # a. Backup (only when there is something to back up). The one made when
    # hikari was never installed here (no record, no earlier backup marked as
    # the original) is marked, so the rotation keeps it for good.
    $backup = ''
    if (Test-Path -LiteralPath $config -PathType Container) {
        # A record of sosc counts too: its first backup, from before sosc, is the original.
        $hadRecord = (Test-Path -LiteralPath (Join-HikariPath $config $script:RecordName)) -or
            (Test-Path -LiteralPath (Join-HikariPath $config $script:SoscRecordName))
        try { $backup = New-HikariBackup -ConfigDir $config -Stamp $Stamp }
        catch { throw (T 'backup_failed' @($config, $_.Exception.Message)) }
        if ($backup) {
            Write-HikariInfo (T 'backup_done' @($backup))
            if (-not $hadRecord -and @(Find-HikariOriginalBackups $config | Where-Object { -not (Test-HikariSamePath $_ $backup) }).Count -eq 0) {
                try { Write-HikariText -Path (Join-HikariPath $backup $script:BackupOriginalMark) -Text ((T 'backup_original_note') + "`r`n") }
                catch { Write-HikariWarn $_.Exception.Message }
            }
        }
    }
    else {
        New-HikariDirectory $config
    }

    try {
        Invoke-HikariSoscMigration $config
        $old = Read-HikariRecord $config
        $oldValues = @{}
        $oldDisabled = @()
        $oldFiles = @()
        $oldMoved = @()
        $oldCommented = @()
        $oldCommentedMpv = @()
        $oldBroken = @()
        if ($null -ne $old) {
            $oldValues = $old.Values; $oldDisabled = @($old.Disabled); $oldFiles = @($old.Files)
            $oldMoved = @($old.Moved); $oldCommented = @($old.Commented); $oldCommentedMpv = @($old.CommentedMpv)
            $oldBroken = @($old.Broken)
        }
        $first = ($null -eq $old)
        if ($backup) {
            $protect = @()
            if ($oldValues.ContainsKey('first_backup')) { $protect = @([string]$oldValues['first_backup']) }
            Remove-HikariOldBackups -ConfigDir $config -Protect $protect
        }
        $prev = {
            param([string]$Key, [bool]$Now)
            if (-not $first -and $oldValues.ContainsKey($Key)) { return ($oldValues[$Key] -eq 'yes') }
            return $Now
        }

        $scripts = Join-HikariPath $config 'scripts'
        $opts = Join-HikariPath $config 'script-opts'
        $uoscBefore = & $prev 'uosc_preexisting' (Test-HikariUoscPresent $config)
        $thumbBefore = & $prev 'thumbfast_preexisting' (Test-Path -LiteralPath (Join-HikariPath $scripts 'thumbfast.lua') -PathType Leaf)
        $mpvConfBefore = & $prev 'mpv_conf_preexisting' (Test-Path -LiteralPath (Join-HikariPath $config 'mpv.conf') -PathType Leaf)
        $inputConfBefore = & $prev 'input_conf_preexisting' (Test-Path -LiteralPath (Join-HikariPath $config 'input.conf') -PathType Leaf)
        $finalEol = @{}
        foreach ($n in @('mpv_conf', 'input_conf')) {
            $key = $n + '_final_eol'
            if (-not $first -and $oldValues.ContainsKey($key)) { $finalEol[$n] = [string]$oldValues[$key] }
            else { $finalEol[$n] = Get-HikariFinalEolState (Join-HikariPath $config ($n -replace '_', '.')) }
        }
        $shadersBefore = & $prev 'shaders_preexisting' (Test-Path -LiteralPath (Join-HikariPath $config $script:ShadersDir) -PathType Container)
        $confBefore = @{}
        foreach ($c in $script:SharedConfs) {
            $key = ($c -replace '\.conf$', '') + '_conf_preexisting'
            $confBefore[$c] = & $prev $key (Test-Path -LiteralPath (Join-HikariPath $opts $c) -PathType Leaf)
        }

        # b. Interfaces that clash with uosc.
        $disabled = New-Object System.Collections.Generic.List[string]
        foreach ($d in $oldDisabled) { $disabled.Add($d) }
        $conflicts = @(Find-HikariConflicts $config)
        if ($conflicts.Count -gt 0) {
            Write-HikariWarn (T 'conflicts_found')
            foreach ($c in $conflicts) { Write-HikariWarn ('  - ' + (Get-HikariRelativePath -Path $c -Root $config)) }
            if (Confirm-Hikari -Question (T 'conflicts_confirm' @($script:DisabledDir)) -Default $true) {
                foreach ($c in $conflicts) { $disabled.Add((Move-HikariToDisabled -Path $c -ConfigDir $config -Stamp $Stamp)) }
            }
            else {
                Write-HikariWarn (T 'conflicts_kept')
            }
        }

        # b2. Scripts that are the error page of a failed download: set aside
        # (never deleted), and moved back on uninstall.
        $broken = New-Object System.Collections.Generic.List[string]
        foreach ($b in $oldBroken) { $broken.Add($b) }
        $bad = @(Find-HikariBrokenScripts $config)
        if ($bad.Count -gt 0) {
            Write-HikariWarn (T 'broken_found')
            foreach ($b in $bad) { Write-HikariWarn ('  - ' + (Get-HikariRelativePath -Path $b -Root $config)) }
            if (Confirm-Hikari -Question (T 'broken_confirm' @($script:DisabledDir)) -Default $true) {
                foreach ($b in $bad) { $broken.Add((Move-HikariToDisabled -Path $b -ConfigDir $config -Stamp $Stamp)) }
            }
            else {
                Write-HikariWarn (T 'broken_kept')
            }
        }

        # c. uosc.
        foreach ($m in (Install-HikariUosc -ConfigDir $config -UoscDir $Artifacts.UoscDir -Stamp $Stamp)) { $disabled.Add($m) }
        Write-HikariOk (T 'uosc_done' @($script:UoscVersion))

        # d. thumbfast.
        New-HikariDirectory $scripts
        Copy-Item -LiteralPath $Artifacts.ThumbfastFile -Destination (Join-HikariPath $scripts 'thumbfast.lua') -Force
        Write-HikariOk (T 'thumbfast_done')

        # e. hikari files.
        $installed = New-Object System.Collections.Generic.List[string]
        $srcScripts = Join-HikariPath $Source.ConfigDir 'scripts'
        foreach ($f in @(Get-ChildItem -LiteralPath $srcScripts -File -Filter 'hikari-*.lua' -Force)) {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-HikariPath $scripts $f.Name) -Force
            $installed.Add('scripts/' + $f.Name)
        }
        # The texts module the scripts share (not a script: mpv would run any .lua in scripts\).
        $modules = Join-HikariPath $config 'script-modules'
        New-HikariDirectory $modules
        $srcModules = Join-HikariPath $Source.ConfigDir 'script-modules'
        if (Test-Path -LiteralPath $srcModules -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $srcModules -File -Filter 'hikari-*.lua' -Force)) {
                Copy-Item -LiteralPath $f.FullName -Destination (Join-HikariPath $modules $f.Name) -Force
                $installed.Add('script-modules/' + $f.Name)
            }
        }
        New-HikariDirectory $opts
        $origDir = Join-HikariPath $config @($script:OriginalsDir, 'script-opts')
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-HikariPath $Source.ConfigDir 'script-opts') -File -Filter '*.conf' -Force)) {
            $dest = Join-HikariPath $opts $f.Name
            if ($first -and $script:SharedConfs -contains $f.Name -and (Test-Path -LiteralPath $dest -PathType Leaf)) {
                New-HikariDirectory $origDir
                Copy-Item -LiteralPath $dest -Destination (Join-HikariPath $origDir $f.Name) -Force
            }
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            $installed.Add('script-opts/' + $f.Name)
        }
        foreach ($name in $script:UserChoiceFiles) {
            if ($name -eq $script:UpscaleConf -or $name -eq $script:LanguageConf) { continue }
            $dest = Join-HikariPath $config $name
            if (Test-Path -LiteralPath $dest -PathType Leaf) {
                Write-HikariInfo (T 'kept_user_file' @($name))
            }
            else {
                Copy-Item -LiteralPath (Join-HikariPath $Source.ConfigDir $name) -Destination $dest
            }
        }
        Initialize-HikariLanguageConf -ConfigDir $config
        foreach ($oldFile in $oldFiles) {
            if ($installed -contains $oldFile -or
                $oldFile -notmatch '^scripts/hikari-[^/\\]+\.lua\z|^script-opts/hikari-[^/\\]+\.conf\z|^script-modules/hikari-[^/\\]+\.lua\z') { continue }
            if (-not (Test-HikariRecordPath $oldFile)) { continue }
            $p = Join-HikariPath $config ($oldFile -split '/')
            if (Test-Path -LiteralPath $p -PathType Leaf) {
                Remove-HikariItem -Path $p -Root $config
                Write-HikariInfo (T 'removed_stale' @($oldFile))
            }
        }
        Write-HikariOk (T 'hikari_files_done' @($installed.Count))

        # e2. Anime4K, and the upscale choice file (with the quality for this
        # graphics card when it is new).
        $a4k = Invoke-HikariAnime4KStep -Candidate $Candidate -ConfigDir $config -Artifacts $Artifacts -Stamp $Stamp `
            -OldValues $oldValues -OldFiles $oldFiles -OldMoved $oldMoved -OldCommented $oldCommented -OldCommentedMpv $oldCommentedMpv
        # Anime4K installed by hikari starts in "Automatico" the first time; on
        # updates the mode the user chose is kept.
        $upscaleMode = 'off'
        if ($a4k.State -eq 'hikari') { $upscaleMode = 'auto' }
        Initialize-HikariUpscaleConf -ConfigDir $config -Announce (@('hikari', 'manual') -contains $a4k.State) -Mode $upscaleMode `
            -Overwrite ([bool]$a4k.Fresh)
        $a4kBindings = @()
        if ($a4k.State -eq 'hikari') { $a4kBindings = $script:Anime4KBindings }

        # g. mpv.net does not always tell thumbfast where it is.
        if (($Candidate.Kind -eq 'mpv.net' -or $Candidate.Kind -eq 'AnimeJaNai') -and $Candidate.Exe) {
            Set-HikariConfOption -Path (Join-HikariPath $opts 'thumbfast.conf') -Key 'mpv_path' -Value $Candidate.Exe `
                -Comment 'Added by the hikari installer: mpv.net does not always tell thumbfast where it is.'
            Write-HikariInfo (T 'mpvpath_set' @($Candidate.Exe))
        }

        # f. Managed blocks.
        [void](Update-HikariManagedFile -Path (Join-HikariPath $config 'mpv.conf') -Kind 'mpv')
        [void](Update-HikariManagedFile -Path (Join-HikariPath $config 'input.conf') -Kind 'input' -ExtraBindings $a4kBindings)

        # h. Record.
        $firstBackup = $backup
        if (-not $first -and $oldValues.ContainsKey('first_backup')) { $firstBackup = $oldValues['first_backup'] }
        $values = [ordered]@{}
        $values['hikari_version'] = $Source.Version
        $values['hikari_commit'] = $Source.Commit
        $values['uosc_version'] = $script:UoscVersion
        $values['thumbfast_commit'] = $script:ThumbfastCommit
        $values['installed_at'] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        $values['player'] = $Candidate.Kind
        $values['player_exe'] = $Candidate.Exe
        $values['uosc_preexisting'] = ConvertTo-HikariYesNo $uoscBefore
        $values['thumbfast_preexisting'] = ConvertTo-HikariYesNo $thumbBefore
        $values['uosc_conf_preexisting'] = ConvertTo-HikariYesNo $confBefore['uosc.conf']
        $values['thumbfast_conf_preexisting'] = ConvertTo-HikariYesNo $confBefore['thumbfast.conf']
        $values['mpv_conf_preexisting'] = ConvertTo-HikariYesNo $mpvConfBefore
        $values['input_conf_preexisting'] = ConvertTo-HikariYesNo $inputConfBefore
        $values['mpv_conf_final_eol'] = $finalEol['mpv_conf']
        $values['input_conf_final_eol'] = $finalEol['input_conf']
        $values['shaders_preexisting'] = ConvertTo-HikariYesNo $shadersBefore
        $values['anime4k'] = $a4k.State
        $values['anime4k_version'] = $a4k.Version
        $values['first_backup'] = $firstBackup
        $values['last_backup'] = $backup
        $allFiles = @($installed.ToArray()) + @($a4k.Files)
        Write-HikariRecord -ConfigDir $config -Values $values -Files $allFiles -Disabled $disabled.ToArray() -Moved @($a4k.Moved) `
            -Commented @($a4k.Commented) -CommentedMpv @($a4k.CommentedMpv) -Broken $broken.ToArray()
    }
    catch {
        $message = $_.Exception.Message
        if ($backup) { $message += ' ' + (T 'restore_hint' @($backup)) }
        throw $message
    }
    Write-HikariOk (T 'install_ok' @($config))
    return $backup
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

# Moves set-aside items back ("moved|original" record entries, relative to the
# folder). Entries are checked again (they come from the record, which is not
# trusted): both ends must be clean paths inside the folder, nothing is
# overwritten and links are not followed when running as administrator.
function Restore-HikariPairs {
    param([string]$ConfigDir, [string[]]$Pairs)
    foreach ($entry in $Pairs) {
        $pair = $entry -split '\|'
        if ($pair.Count -ne 2 -or -not (Test-HikariRecordPath $pair[0]) -or -not (Test-HikariRecordPath $pair[1])) {
            Write-HikariWarn (T 'record_bad' @($entry)); continue
        }
        $from = Join-HikariPath $ConfigDir ($pair[0] -split '/')
        $to = Join-HikariPath $ConfigDir ($pair[1] -split '/')
        if (-not (Test-HikariInside -Path $from -Root $ConfigDir)) { Write-HikariWarn (T 'outside_target' @($from, $ConfigDir)); continue }
        if (-not (Test-HikariInside -Path $to -Root $ConfigDir)) { Write-HikariWarn (T 'outside_target' @($to, $ConfigDir)); continue }
        if (-not (Test-Path -LiteralPath $from)) { continue }
        if (Test-Path -LiteralPath $to) { Write-HikariWarn (T 'restore_skipped' @($pair[0], $pair[1])); continue }
        Assert-HikariNoLink -Path $from -Root $ConfigDir
        Assert-HikariNoLink -Path $to -Root $ConfigDir
        New-HikariDirectory (Split-Path -Path $to -Parent)
        Move-Item -LiteralPath $from -Destination $to
        Write-HikariInfo (T 'moved' @($pair[0], $pair[1]))
    }
}

function Uninstall-HikariTarget {
    param([Parameter(Mandatory = $true)]$Candidate, [string]$Stamp = '')
    if (-not $Stamp) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }
    $config = Get-HikariFullPath $Candidate.ConfigDir
    Write-HikariInfo ''
    Write-HikariInfo (T 'uninstalling_from' @($config))
    try { $backup = New-HikariBackup -ConfigDir $config -Stamp $Stamp }
    catch { throw (T 'backup_failed' @($config, $_.Exception.Message)) }
    if ($backup) { Write-HikariInfo (T 'backup_done' @($backup)) }

    try {
        Invoke-HikariSoscMigration $config
        $record = Read-HikariRecord $config
        $values = @{}
        $disabled = @()
        $recordFiles = @()
        $movedA4k = @()
        $commentedA4k = @()
        $commentedMpvA4k = @()
        $brokenPairs = @()
        if ($null -ne $record) {
            $values = $record.Values; $disabled = @($record.Disabled); $recordFiles = @($record.Files)
            $movedA4k = @($record.Moved); $commentedA4k = @($record.Commented); $commentedMpvA4k = @($record.CommentedMpv)
            $brokenPairs = @($record.Broken)
        }
        if ($backup) {
            $protect = @()
            if ($values.ContainsKey('first_backup')) { $protect = @([string]$values['first_backup']) }
            Remove-HikariOldBackups -ConfigDir $config -Protect $protect
        }
        $wasThere = {
            param([string]$Key)
            if ($null -eq $record -or -not $values.ContainsKey($Key)) { return $null }
            return ($values[$Key] -eq 'yes')
        }
        $scripts = Join-HikariPath $config 'scripts'
        $opts = Join-HikariPath $config 'script-opts'

        if (Test-Path -LiteralPath $scripts -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $scripts -File -Filter 'hikari-*.lua' -Force)) { Remove-HikariItem -Path $f.FullName -Root $config }
        }
        if (Test-Path -LiteralPath $opts -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $opts -File -Filter 'hikari-*.conf' -Force)) { Remove-HikariItem -Path $f.FullName -Root $config }
        }
        $modules = Join-HikariPath $config 'script-modules'
        if (Test-Path -LiteralPath $modules -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $modules -File -Filter 'hikari-*.lua' -Force)) { Remove-HikariItem -Path $f.FullName -Root $config }
        }
        # Anime4K shaders: only the ones the record says hikari installed.
        foreach ($rel in @($recordFiles | Where-Object { Test-HikariOwnShaderPath $_ })) {
            $p = Join-HikariPath $config ($rel -split '/')
            if ((Test-HikariInside -Path $p -Root $config) -and (Test-Path -LiteralPath $p -PathType Leaf)) { Remove-HikariItem -Path $p -Root $config }
        }

        $originals = Join-HikariPath $config @($script:OriginalsDir, 'script-opts')
        foreach ($c in $script:SharedConfs) {
            $p = Join-HikariPath $opts $c
            $before = & $wasThere (($c -replace '\.conf$', '') + '_conf_preexisting')
            $orig = Join-HikariPath $originals $c
            if ($before -eq $true -and (Test-Path -LiteralPath $orig -PathType Leaf)) {
                Copy-Item -LiteralPath $orig -Destination $p -Force
                Write-HikariInfo (T 'conf_restored' @(('script-opts/' + $c)))
            }
            elseif ($before -eq $false) {
                Remove-HikariItem -Path $p -Root $config
            }
            elseif ($before -eq $true) {
                $firstBackup = ''
                if ($values.ContainsKey('first_backup')) { $firstBackup = [string]$values['first_backup'] }
                Write-HikariInfo (T 'conf_left' @(('script-opts/' + $c), $firstBackup))
            }
            elseif (Test-Path -LiteralPath $p -PathType Leaf) {
                Write-HikariInfo (T 'conf_unknown' @(('script-opts/' + $c)))
            }
        }

        Remove-HikariManagedFile -Path (Join-HikariPath $config 'mpv.conf') -Root $config -CreatedByHikari ((& $wasThere 'mpv_conf_preexisting') -eq $false) `
            -NoFinalEol ((& $wasThere 'mpv_conf_final_eol') -eq $false)
        Remove-HikariManagedFile -Path (Join-HikariPath $config 'input.conf') -Root $config -CreatedByHikari ((& $wasThere 'input_conf_preexisting') -eq $false) `
            -NoFinalEol ((& $wasThere 'input_conf_final_eol') -eq $false)

        $uoscBefore = & $wasThere 'uosc_preexisting'
        $removeUosc = $false
        if (Test-HikariUoscPresent $config) {
            $removeUosc = Confirm-Hikari -Question (T 'ask_remove_uosc') -Default ($uoscBefore -eq $false)
            if ($removeUosc) {
                Remove-HikariItem -Path (Join-HikariPath $scripts 'uosc') -Root $config
                foreach ($font in $script:UoscFonts) { Remove-HikariItem -Path (Join-HikariPath $config @('fonts', $font)) -Root $config }
            }
        }
        $thumb = Join-HikariPath $scripts 'thumbfast.lua'
        if (Test-Path -LiteralPath $thumb -PathType Leaf) {
            if (Confirm-Hikari -Question (T 'ask_remove_thumbfast') -Default ((& $wasThere 'thumbfast_preexisting') -eq $false)) {
                Remove-HikariItem -Path $thumb -Root $config
            }
        }

        $pending = @($disabled | Where-Object { $_ -match '\|' })
        if ($pending.Count -gt 0) {
            $names = [string]::Join(', ', @($pending | ForEach-Object { ($_ -split '\|')[1] }))
            if (Confirm-Hikari -Question (T 'ask_restore' @($names)) -Default $removeUosc) {
                Restore-HikariPairs -ConfigDir $config -Pairs $pending
            }
        }
        if ($brokenPairs.Count -gt 0) {
            $names = [string]::Join(', ', @($brokenPairs | ForEach-Object { ($_ -split '\|')[1] }))
            if (Confirm-Hikari -Question (T 'ask_restore_broken' @($names)) -Default $true) {
                Restore-HikariPairs -ConfigDir $config -Pairs $brokenPairs
            }
        }

        # Without uosc, an osc=no of the user's own leaves the player without
        # controls: offer to put back an interface, or to turn that line off.
        # With -Yes it only warns.
        $mpvConf = Join-HikariPath $config 'mpv.conf'
        if ($removeUosc -and (Test-Path -LiteralPath $mpvConf -PathType Leaf)) {
            $oscOff = @(Find-HikariOscOffLines (Read-HikariText $mpvConf).Text)
            if ($oscOff.Count -gt 0 -and @(Find-HikariConflicts $config).Count -eq 0) {
                Write-HikariWarn (T 'osc_orphan' @($oscOff[0].Content.Trim()))
                $still = @($pending | Where-Object { Test-Path -LiteralPath (Join-HikariPath $config (($_ -split '\|')[0] -split '/')) })
                if ($still.Count -gt 0) {
                    $names = [string]::Join(', ', @($still | ForEach-Object { ($_ -split '\|')[1] }))
                    if (Confirm-Hikari -Question (T 'ask_restore_osc' @($names)) -Default (-not $script:NonInteractive)) {
                        Restore-HikariPairs -ConfigDir $config -Pairs $still
                    }
                }
                if (@(Find-HikariConflicts $config).Count -eq 0) {
                    if (Confirm-Hikari -Question (T 'ask_comment_osc') -Default (-not $script:NonInteractive)) {
                        Set-HikariLinesCommented -Path $mpvConf -Lines $oscOff
                        foreach ($l in $oscOff) { Write-HikariInfo (T 'osc_commented' @($l.Content.Trim())) }
                    }
                    else { Write-HikariWarn (T 'osc_left') }
                }
            }
        }

        # Anime4K installed by hand that hikari set aside, and the input.conf
        # lines it turned off.
        if ($movedA4k.Count -gt 0) {
            if (Confirm-Hikari -Question (T 'ask_restore_anime4k' @($script:ShadersDisabledDir)) -Default $true) {
                Restore-HikariPairs -ConfigDir $config -Pairs $movedA4k
            }
        }
        $inputConf = Join-HikariPath $config 'input.conf'
        if ($commentedA4k.Count -gt 0 -and (Test-Path -LiteralPath $inputConf -PathType Leaf)) {
            $off = @(Find-HikariCommentedKeyLines -Text (Read-HikariText $inputConf).Text -Recorded $commentedA4k)
            if ($off.Count -gt 0 -and (Confirm-Hikari -Question (T 'ask_uncomment') -Default $true)) {
                $map = @{}
                foreach ($l in $off) { $map[[int]$l.Index] = $l.Content }
                Update-HikariLines -Path $inputConf -Map $map
                Write-HikariInfo (T 'uncommented' @($off.Count))
            }
        }
        # And its glsl-shaders lines in mpv.conf, with the same checks: only
        # recorded lines, still there with the prefix, outside the block.
        if ($commentedMpvA4k.Count -gt 0 -and (Test-Path -LiteralPath $mpvConf -PathType Leaf)) {
            $off = @(Find-HikariCommentedConfLines -Text (Read-HikariText $mpvConf).Text -Recorded $commentedMpvA4k)
            if ($off.Count -gt 0 -and (Confirm-Hikari -Question (T 'ask_uncomment_conf') -Default $true)) {
                $map = @{}
                foreach ($l in $off) { $map[[int]$l.Index] = $l.Content }
                Update-HikariLines -Path $mpvConf -Map $map
                Write-HikariInfo (T 'uncommented_conf' @($off.Count))
            }
        }

        $deleteChoices = $false
        if (@($script:UserChoiceFiles | Where-Object { Test-Path -LiteralPath (Join-HikariPath $config $_) -PathType Leaf }).Count -gt 0) {
            $deleteChoices = Confirm-Hikari -Question (T 'ask_delete_choices') -Default $false
            if ($deleteChoices) {
                foreach ($name in $script:UserChoiceFiles) { Remove-HikariItem -Path (Join-HikariPath $config $name) -Root $config }
            }
        }
        if ($deleteChoices -and (Test-Path -LiteralPath $mpvConf -PathType Leaf)) {
            $text = (Read-HikariText $mpvConf).Text
            foreach ($name in $script:UserChoiceFiles) {
                if ($text -match ('(?im)^\s*include\s*=.*' + [regex]::Escape($name))) { Write-HikariWarn (T 'includes_outside' @($name)) }
            }
        }

        # Folders left empty (hikari may have created them) go too; shaders only
        # when the record says hikari created it.
        $emptyDirs = @('fonts', 'script-opts', 'scripts', 'script-modules')
        if ((& $wasThere 'shaders_preexisting') -eq $false) { $emptyDirs += $script:ShadersDir }
        foreach ($dirName in $emptyDirs) {
            $dir = Join-HikariPath $config $dirName
            $item = Get-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
            if ($null -ne $item -and $item.PSIsContainer -and -not (Test-HikariLink $item) -and
                @(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) {
                Remove-HikariItem -Path $dir -Root $config
            }
        }
        Remove-HikariItem -Path (Join-HikariPath $config $script:OriginalsDir) -Root $config
        Remove-HikariItem -Path (Join-HikariPath $config $script:RecordName) -Root $config
        foreach ($name in @($script:UpdateState, ($script:UpdateState + '.tmp'))) {
            $statePath = Join-HikariPath $config $name
            if (Test-Path -LiteralPath $statePath -PathType Leaf) { Remove-HikariItem -Path $statePath -Root $config }
        }
        foreach ($dirName in @($script:DisabledDir, $script:ShadersDisabledDir)) {
            $dir = Join-HikariPath $config $dirName
            if ((Test-Path -LiteralPath $dir -PathType Container) -and
                @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force).Count -eq 0) {
                Remove-HikariItem -Path $dir -Root $config
            }
        }
    }
    catch {
        $message = $_.Exception.Message
        if ($backup) { $message += ' ' + (T 'restore_hint' @($backup)) }
        throw $message
    }
    Write-HikariOk (T 'uninstall_ok' @($config))
    return $backup
}

# ---------------------------------------------------------------------------
# Interactive flow
# ---------------------------------------------------------------------------

function Get-HikariKindLabel {
    param([string]$Kind)
    if ($Kind -eq 'folder') { return (T 'kind_folder') }
    return $Kind
}

function Get-HikariCandidateTags {
    param($Candidate)
    $tags = @()
    $sosc = $Candidate.PSObject.Properties['Sosc']
    if ($null -ne $sosc -and $sosc.Value) { $tags += (T 'tag_sosc') }
    elseif ($Candidate.Installed -and $Candidate.Manual) { $tags += (T 'tag_manual') }
    elseif ($Candidate.Installed) { $tags += (T 'tag_installed' @($Candidate.InstalledVersion)) }
    if (-not $Candidate.Writable) { $tags += (T 'tag_readonly') }
    if (-not $Candidate.Exists) { $tags += (T 'tag_new') }
    return [string]::Join(' ', $tags)
}

function Show-HikariCandidates {
    param([object[]]$Candidates)
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $c = $Candidates[$i]
        Write-HikariInfo (' {0}) {1}  {2}' -f ($i + 1), (Get-HikariKindLabel $c.Kind), (Get-HikariCandidateTags $c))
        if ($c.Exe) { Write-HikariInfo (T 'cand_exe' @($c.Exe)) }
        Write-HikariInfo (T 'cand_config' @($c.ConfigDir))
    }
}

# The line above the list of folders ('' with no folders).
function Get-HikariTargetHeader {
    param([object[]]$List, [string]$Mode)
    if (@($List).Count -eq 0) { return '' }
    if ($Mode -eq 'uninstall') { return (T 'found_header_uninst') }
    return (T 'found_header')
}

function Write-HikariTargetHeader {
    param([object[]]$List, [string]$Mode)
    $h = Get-HikariTargetHeader -List $List -Mode $Mode
    if ($h) { Write-HikariInfo $h }
}

# Menu entry for a detected folder: player and tags, then its config folder.
function New-HikariCandidateItem {
    param($Candidate)
    $kind = Get-HikariKindLabel $Candidate.Kind
    $label = $kind
    $tags = Get-HikariCandidateTags $Candidate
    if ($tags) { $label += '  ' + $tags }
    $summary = $kind + ' (' + (Format-HikariFit -Text $Candidate.ConfigDir -Max 40 -Middle) + ')'
    return (New-HikariMenuItem -Label $label -Details @($Candidate.ConfigDir) -Summary $summary)
}

# Which folders to work on: Indexes (into $List), Other (type a folder) and
# Quit, as ConvertFrom-HikariSelection returns them. $null when the input ends.
function Read-HikariTargetChoice {
    param([object[]]$List, [string]$Mode)
    $r = Invoke-HikariMenuOrNumbers {
        $header = @(Get-HikariTargetHeader -List $List -Mode $Mode | Where-Object { $_ })
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($c in $List) { $items.Add((New-HikariCandidateItem $c)) }
        $otherIndex = $items.Count
        $items.Add((New-HikariMenuItem -Label ((Get-HikariPlainLabel (T 'opt_other')) + $script:GlyphEllipsis) -Action $true))
        $items.Add((New-HikariMenuItem -Label (Get-HikariPlainLabel (T 'opt_quit')) -Action $true -Quit $true))
        $m = Invoke-HikariListMenu -Items $items.ToArray() -Multi -Header $header
        $sel = [pscustomobject]@{ Indexes = @(); Other = $false; Quit = $false }
        if ($m.Cancelled -or ($m.Index -ge 0 -and $items[$m.Index].Quit)) { $sel.Quit = $true; return $sel }
        $sel.Indexes = @($m.Checked)
        $sel.Other = ($m.Index -eq $otherIndex)
        return $sel
    }
    if (-not (Test-HikariUseNumbers $r)) { return $r }
    while ($true) {
        Write-HikariTargetHeader -List $List -Mode $Mode
        if (@($List).Count -gt 0) { Show-HikariCandidates $List }
        Write-HikariInfo (' ' + (T 'opt_other'))
        Write-HikariInfo (' ' + (T 'opt_quit'))
        $text = Read-HikariLine (T 'select_prompt')
        if ($null -eq $text) { return $null }
        $sel = ConvertFrom-HikariSelection -Text $text -Count @($List).Count
        if ($null -ne $sel) { return $sel }
        Write-HikariWarn (T 'invalid')
    }
}

# Main menu: '1' install, '2' uninstall, '0' exit, $null when the input ends;
# anything else typed in number mode is returned as it is (invalid).
function Read-HikariMainChoice {
    $r = Invoke-HikariMenuOrNumbers {
        $labels = @((T 'menu') -split "`r?`n" | ForEach-Object { Get-HikariPlainLabel $_ })
        $items = @(
            (New-HikariMenuItem -Label $labels[0] -Hotkey '1'),
            (New-HikariMenuItem -Label $labels[1] -Hotkey '2'),
            (New-HikariMenuItem -Label $labels[2] -Quit $true -Hotkey '0')
        )
        $m = Invoke-HikariListMenu -Items $items
        if ($m.Cancelled) { return '0' }
        return @('1', '2', '0')[$m.Index]
    }
    if (-not (Test-HikariUseNumbers $r)) { return $r }
    Write-HikariInfo (T 'menu')
    return (Read-HikariLine (T 'menu_prompt'))
}

# No player found: '1' winget, '2' type a folder, '3' prepare %APPDATA%\mpv,
# '0' exit, $null when the input ends.
function Read-HikariNoPlayerChoice {
    param([bool]$HasWinget, [string]$AppMpv)
    $r = Invoke-HikariMenuOrNumbers {
        $wingetLabel = Get-HikariPlainLabel (T 'none_opt_winget')
        if (-not $HasWinget) { $wingetLabel += ' ' + (T 'none_nowinget').Trim() }
        $items = @(
            (New-HikariMenuItem -Label $wingetLabel -Disabled (-not $HasWinget) -Hotkey '1'),
            (New-HikariMenuItem -Label (Get-HikariPlainLabel (T 'none_opt_folder')) -Hotkey '2'),
            (New-HikariMenuItem -Label (Get-HikariPlainLabel (T 'none_opt_prepare' @($AppMpv))) -Disabled (-not $AppMpv) -Hotkey '3'),
            (New-HikariMenuItem -Label (Get-HikariPlainLabel (T 'opt_quit')) -Quit $true -Hotkey '0')
        )
        $m = Invoke-HikariListMenu -Items $items -Header @(T 'none_link')
        if ($m.Cancelled) { return '0' }
        return @('1', '2', '3', '0')[$m.Index]
    }
    if (-not (Test-HikariUseNumbers $r)) { return $r }
    Write-HikariInfo (T 'none_opt_winget')
    if (-not $HasWinget) { Write-HikariInfo (T 'none_nowinget') }
    Write-HikariInfo (T 'none_opt_folder')
    Write-HikariInfo (T 'none_opt_prepare' @($AppMpv))
    Write-HikariInfo (T 'opt_quit')
    Write-HikariInfo (T 'none_link')
    return (Read-HikariLine (T 'menu_prompt'))
}

function Read-HikariFolder {
    param([hashtable]$Env, [object[]]$Candidates)
    while ($true) {
        $answer = Read-HikariLine (T 'ask_folder')
        if ($null -eq $answer -or $answer.Trim() -eq '' -or $answer.Trim() -eq '0') { return $null }
        try { $path = ConvertTo-HikariTypedPath $answer }
        catch { Write-HikariWarn $_.Exception.Message; continue }
        $parent = Split-Path -Path $path -Parent
        if ((Test-Path -LiteralPath $path -PathType Container) -or ($parent -and (Test-Path -LiteralPath $parent -PathType Container))) {
            $c = Resolve-HikariManualTarget -Env $Env -Path $path -Candidates $Candidates
            if ($null -ne $c) { return $c }
            continue
        }
        Write-HikariWarn (T 'folder_missing' @($path))
    }
}

# Runs winget. Its output goes to the screen, never into the caller's return
# value. Returns winget's exit code (-1 when it could not be started).
function Invoke-HikariWinget {
    param([string]$Exe)
    $wingetArgs = @('install', '--id', 'mpv.net', '-e', '--accept-source-agreements', '--accept-package-agreements')
    try {
        & $Exe @wingetArgs | ForEach-Object { Write-HikariInfo ([string]$_) }
        return [int]$LASTEXITCODE
    }
    catch {
        Write-HikariWarn (T 'winget_error' @($_.Exception.Message))
        return -1
    }
}

# Checks write access and offers the user folder when a portable one is read-only.
function Resolve-HikariWritable {
    param([hashtable]$Env, $Candidate)
    if ($Candidate.Writable) { return $Candidate }
    Write-HikariWarn (T 'readonly_warn' @($Candidate.ConfigDir))
    if ($Candidate.UserConfigDir) {
        if ($Candidate.Portable) { Write-HikariWarn (T 'readonly_portable' @($Candidate.ConfigDir, $Candidate.UserConfigDir)) }
        if (-not $script:NonInteractive -and (Confirm-Hikari -Question (T 'readonly_offer' @($Candidate.UserConfigDir)) -Default $false)) {
            $alt = New-HikariCandidate -Env $Env -Kind $Candidate.Kind -Exe $Candidate.Exe -ConfigDir (Get-HikariFullPath $Candidate.UserConfigDir) -Portable $false
            if ($alt.Writable) { return $alt }
            Write-HikariWarn (T 'readonly_warn' @($alt.ConfigDir))
        }
    }
    Write-HikariWarn (T 'readonly_skip' @($Candidate.ConfigDir))
    return $null
}

# Nothing detected: offer winget, a typed folder or %APPDATA%\mpv.
function Invoke-HikariNoPlayerMenu {
    param([hashtable]$Env)
    Write-HikariWarn (T 'none_found')
    $winget = & $Env.FindCommand 'winget'
    $hasWinget = -not [string]::IsNullOrEmpty($winget)
    $appMpv = Get-HikariUserConfigDir -Env $Env -Kind 'mpv'
    while ($true) {
        $answer = Read-HikariNoPlayerChoice -HasWinget $hasWinget -AppMpv $appMpv
        if ($null -eq $answer) { return @() }
        switch ($answer.Trim()) {
            '0' { return @() }
            '1' {
                if (-not $hasWinget) { Write-HikariWarn (T 'invalid'); continue }
                if (Confirm-Hikari -Question (T 'winget_confirm') -Default $true) {
                    $code = Invoke-HikariWinget -Exe $winget
                    if ($code -ne 0) { Write-HikariWarn (T 'winget_failed' @($code)) }
                    $found = @(Find-HikariPlayers -Env $Env)
                    if ($found.Count -gt 0) { return $found }
                    Write-HikariWarn (T 'none_found')
                }
            }
            '2' {
                $c = Read-HikariFolder -Env $Env -Candidates @()
                if ($null -ne $c) { return @($c) }
            }
            '3' {
                if (-not $appMpv) { Write-HikariWarn (T 'invalid'); continue }
                $c = Resolve-HikariManualTarget -Env $Env -Path $appMpv -Candidates @()
                if ($null -ne $c) { return @($c) }
            }
            default { Write-HikariWarn (T 'invalid') }
        }
    }
}

# Returns Ok (false: wrong usage with -Yes) and the targets (empty: cancelled).
function Select-HikariTargets {
    param([hashtable]$Env, [string]$Mode, [string[]]$Paths)
    Write-HikariInfo (T 'detecting')
    $all = @(Find-HikariPlayers -Env $Env)
    $chosen = New-Object System.Collections.Generic.List[object]

    $refused = $false
    if (@($Paths).Count -gt 0) {
        foreach ($p in $Paths) {
            $c = $null
            try { $c = Resolve-HikariManualTarget -Env $Env -Path $p -Candidates $all }
            catch { Write-HikariError $_.Exception.Message }
            if ($null -ne $c) { $chosen.Add($c) } else { $refused = $true }
        }
    }
    else {
        $list = $all
        if ($Mode -eq 'uninstall') { $list = @($all | Where-Object { $_.Installed }) }
        if ($script:NonInteractive) {
            if ($list.Count -eq 1) { $chosen.Add($list[0]) }
            elseif ($list.Count -eq 0) {
                if ($Mode -eq 'uninstall') { Write-HikariError (T 'nothing_to_uninstall') } else { Write-HikariError (T 'none_found') }
                return [pscustomobject]@{ Ok = $false; Targets = @() }
            }
            else {
                Write-HikariError (T 'usage_many')
                Show-HikariCandidates $list
                return [pscustomobject]@{ Ok = $false; Targets = @() }
            }
        }
        elseif ($list.Count -eq 0 -and $Mode -eq 'install') {
            foreach ($c in @(Invoke-HikariNoPlayerMenu -Env $Env)) { $chosen.Add($c) }
        }
        else {
            if ($list.Count -eq 0) { Write-HikariWarn (T 'nothing_to_uninstall') }
            $sel = Read-HikariTargetChoice -List $list -Mode $Mode
            # $null: no more input (stdin closed or redirected), same as choosing Exit.
            if ($null -ne $sel -and -not $sel.Quit) {
                foreach ($i in $sel.Indexes) { $chosen.Add($list[$i]) }
                if ($sel.Other) {
                    $c = Read-HikariFolder -Env $Env -Candidates $all
                    if ($null -ne $c) { $chosen.Add($c) }
                }
            }
        }
    }

    # Folders that must never be used, and folders that do not look like mpv's.
    $safe = New-Object System.Collections.Generic.List[object]
    foreach ($c in $chosen) {
        if (Test-HikariForbiddenTarget -Env $Env -Path $c.ConfigDir) {
            Write-HikariError (T 'target_root' @($c.ConfigDir))
            $refused = $true
            continue
        }
        if (-not (Test-HikariLooksLikeMpvConfig -Env $Env -Candidate $c)) {
            Write-HikariWarn (T 'not_mpv_folder' @($c.ConfigDir))
            if ($script:NonInteractive) {
                Write-HikariError (T 'not_mpv_yes')
                $refused = $true
                continue
            }
            if (-not (Confirm-Hikari -Question (T 'not_mpv_confirm') -Default $false)) {
                Write-HikariWarn (T 'readonly_skip' @($c.ConfigDir))
                continue
            }
        }
        $safe.Add($c)
    }
    if ($refused -and $script:NonInteractive) { return [pscustomobject]@{ Ok = $false; Targets = @() } }

    if ($Mode -eq 'uninstall') { return [pscustomobject]@{ Ok = $true; Targets = $safe.ToArray() } }
    $writable = New-Object System.Collections.Generic.List[object]
    foreach ($c in $safe) {
        $w = Resolve-HikariWritable -Env $Env -Candidate $c
        if ($null -ne $w) { $writable.Add($w) }
    }
    return [pscustomobject]@{ Ok = $true; Targets = $writable.ToArray() }
}

function Test-HikariUnderSystemDirs {
    param([hashtable]$Env, [string]$Path)
    foreach ($root in @($Env.ProgramFiles, $Env.ProgramFilesX86, $Env.ProgramData)) {
        if ($root -and (Test-HikariInside -Path $Path -Root $root)) { return $true }
    }
    return $false
}

# Running as administrator is not needed and risky: warn and ask; with -Yes,
# only allow folders under Program Files or ProgramData (the only ones that may
# really need it).
function Confirm-HikariElevation {
    param([hashtable]$Env, [object[]]$Targets)
    if (-not $Env.IsAdmin) { return $true }
    Write-HikariWarn (T 'admin_warn')
    if ($script:NonInteractive) {
        $bad = @($Targets | Where-Object { -not (Test-HikariUnderSystemDirs -Env $Env -Path $_.ConfigDir) } | ForEach-Object { $_.ConfigDir })
        if ($bad.Count -gt 0) {
            Write-HikariError (T 'admin_refused' @(([string]::Join('; ', $bad))))
            return $false
        }
        return $true
    }
    return (Confirm-Hikari -Question (T 'admin_confirm') -Default $false)
}

function Invoke-HikariMain {
    param([string]$Action, [string[]]$Target, [bool]$Yes, [bool]$NoMenu = $false, [string]$Anime4K = '')
    $script:NonInteractive = $Yes
    $script:HikariAnime4KChoice = $Anime4K
    # Keyboard menus only on a real interactive console; numbers otherwise.
    $script:HikariMenu = $false
    if (-not $Yes -and -not $NoMenu) { $script:HikariMenu = [bool](& $script:HikariConsoleProbe) }
    if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        Write-HikariError (T 'old_ps')
        return 2
    }
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 } catch { }
    }

    Write-HikariInfo (T 'title')
    if (-not $Action) {
        if ($Yes) { Write-HikariError (T 'usage_yes_action'); return 2 }
        while (-not $Action) {
            $answer = Read-HikariMainChoice
            if ($null -eq $answer) { return 0 }
            switch ($answer.Trim()) {
                '1' { $Action = 'install' }
                '2' { $Action = 'uninstall' }
                '0' { Write-HikariInfo (T 'cancelled'); return 0 }
                default { Write-HikariWarn (T 'invalid') }
            }
        }
    }

    # powershell -File passes "-Target a,b" as one string: ';' separates folders.
    $paths = @($Target | ForEach-Object { $_ -split ';' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    $environment = New-HikariEnvironment
    $script:HikariElevated = [bool]$environment.IsAdmin
    $selection = Select-HikariTargets -Env $environment -Mode $Action -Paths $paths
    if (-not $selection.Ok) { return 2 }
    $targets = @($selection.Targets)
    if (@($targets).Count -eq 0) {
        if ($Yes) { Write-HikariError (T 'usage_none'); return 2 }
        Write-HikariInfo (T 'cancelled')
        return 0
    }
    if (-not (Confirm-HikariElevation -Env $environment -Targets $targets)) {
        if ($Yes) { return 2 }
        Write-HikariInfo (T 'cancelled')
        return 0
    }

    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $ok = 0
    $temp = $null
    try {
        if ($Action -eq 'install') {
            $temp = New-HikariTempDir
            try {
                $source = Get-HikariSource -TempDir $temp
                $artifacts = Get-HikariArtifacts -TempDir $temp
            }
            catch {
                Write-HikariError (T 'error_generic' @($_.Exception.Message))
                return 1
            }
        }
        foreach ($t in $targets) {
            try {
                if ($Action -eq 'install') {
                    [void](Install-HikariTarget -Candidate $t -Source $source -Artifacts $artifacts -Stamp $stamp)
                }
                else {
                    [void](Uninstall-HikariTarget -Candidate $t -Stamp $stamp)
                }
                $ok++
            }
            catch {
                Write-HikariError (T 'target_failed' @($t.ConfigDir, $_.Exception.Message))
            }
        }
    }
    finally {
        if ($temp -and (Test-Path -LiteralPath $temp)) {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-HikariInfo ''
    Write-HikariInfo (T 'summary' @($ok, @($targets).Count))
    if ($ok -gt 0) { Write-HikariInfo (T 'restart') }
    if ($ok -lt @($targets).Count) { return 1 }
    return 0
}

# Tests load the functions above without running the installer.
if ($env:HIKARI_INSTALL_TEST) { return }

# Windows PowerShell 5.1 may need TLS 1.2 switched on for GitHub (see
# Invoke-HikariMain); that setting is process-wide, so it is put back afterwards.
$savedTls = $null
try { $savedTls = [System.Net.ServicePointManager]::SecurityProtocol } catch { }
try {
    $code = Invoke-HikariMain -Action $Action -Target $Target -Yes ([bool]$Yes) -NoMenu ([bool]$NoMenu) -Anime4K $Anime4K
}
finally {
    if ($null -ne $savedTls) { try { [System.Net.ServicePointManager]::SecurityProtocol = $savedTls } catch { } }
}
# { }.File is the file this script block was read from: set with -File or
# .\hikari.ps1, empty through iex or [scriptblock]::Create. Only a file run may
# exit: through iex, exit would close the user's PowerShell window.
if ({ }.File) { exit $code }
$global:LASTEXITCODE = $code
} -Action $HikariAction -Target $HikariTarget -Yes:$HikariYes -NoMenu:$HikariNoMenu -Anime4K $HikariAnime4K
}
catch {
    # An unexpected error that got this far. Same rule as above: exit only when
    # running from a file. No new variables here: this runs in the caller's scope.
    Write-Host ('hikari: ' + $_.Exception.Message) -ForegroundColor Red
    if ({ }.File) { exit 1 }
    $global:LASTEXITCODE = 1
}
finally {
    # Through iex the parameters above are variables of the caller's session.
    if (-not { }.File) { Remove-Variable -Name HikariAction, HikariTarget, HikariYes, HikariNoMenu, HikariAnime4K -Scope 0 -ErrorAction SilentlyContinue }
}
