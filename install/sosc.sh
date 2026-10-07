#!/usr/bin/env bash
# shellcheck shell=bash
#
# sosc installer for macOS and Linux (mpv).
#
# Installs, updates or removes sosc (https://github.com/SCEPTICG/sosc), together
# with uosc and thumbfast (and Anime4K if wanted), in an mpv config folder. It
# does the same as install/sosc.ps1 on Windows, with the same messages.
#
# From a published release (this file then downloads that release's sosc.zip
# and checks its SHA256 before using it):
#     curl -fsSL https://github.com/SCEPTICG/sosc/releases/latest/download/sosc.sh | bash
#     curl -fsSL https://github.com/SCEPTICG/sosc/releases/latest/download/sosc.sh | bash -s -- --uninstall
# From a copy of the repository (the sosc files then come from that copy):
#     bash install/sosc.sh
#
# Options:
#     --install, --uninstall   skip the first menu
#     --target <folder>        mpv config folder to work on (repeat it for several)
#     --yes                    no questions: take the default answer to everything
#     --no-menu                ask with numbers and typed answers, not keyboard menus
#     --anime4k yes|no         answer the Anime4K questions instead of asking
#     --help
#
# Questions are read from the terminal (/dev/tty), also when this file comes
# through a pipe as above. With no terminal at all it runs as with --yes: the
# default (safe) answer to every question, and install when no action is given.
#
# Exit codes: 0 done (or cancelled), 1 at least one folder failed, 2 wrong usage
# or nothing to work on.
#
# Written for the bash 3.2 of macOS and for BSD and GNU tools alike: no
# associative arrays, no sed -i, no GNU-only options. Everything is inside
# functions and the last line calls main, so a download cut short runs nothing.
# No sudo: it only touches the config folder, the backups next to it and a
# temporary folder that it deletes when it ends (and, only if you say yes when
# mpv is missing on macOS, runs "brew install mpv").

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

sosc_defaults() {
    # Release markers. tools/make-release.sh replaces these three lines, matched
    # whole and exactly once each, with the tag, the URL of that release's
    # sosc.zip and its SHA256. Keep them exactly as they are. In the repository
    # they stay empty: the sosc files then come from the repository copy this
    # file sits in, and run on its own (curl | bash) it says there is no release.
    SOSC_VERSION='dev'
    SOSC_RELEASE_URL=''
    SOSC_RELEASE_SHA256=''

    # uosc, thumbfast and Anime4K: fixed versions, verified by SHA256 (the same
    # ones as install/sosc.ps1).
    UOSC_VERSION='5.13.0'
    UOSC_URL='https://github.com/tomasklaen/uosc/releases/download/5.13.0/uosc.zip'
    UOSC_SHA256='4be9da3289285300fa374496c3f1bfd7bb20ac08e890d25bd5a06b28eebe4882'
    UOSC_FONTS=('uosc_icons.otf' 'uosc_textures.ttf')
    THUMBFAST_COMMIT='0f711de3138c9bd6718209d819ac54022c23ded2'
    THUMBFAST_URL='https://raw.githubusercontent.com/po5/thumbfast/0f711de3138c9bd6718209d819ac54022c23ded2/thumbfast.lua'
    THUMBFAST_SHA256='a3d08e71eae8b892f6cd39f9593ea219768e709312d176bca883841b156448bf'
    ANIME4K_VERSION='4.0.1'
    ANIME4K_URL='https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip'
    ANIME4K_SHA256='139cd282086457c5adc79caf7b75b8b825091d71c9b54958c18745fea62d7ed7'
    ANIME4K_PATTERN='^Anime4K_[A-Za-z0-9_]+\.glsl$'
    # The shaders sosc-upscale.lua uses (its required_shaders()); the zip must have them all.
    ANIME4K_REQUIRED=(
        'Anime4K_AutoDownscalePre_x2.glsl' 'Anime4K_AutoDownscalePre_x4.glsl' 'Anime4K_Clamp_Highlights.glsl'
        'Anime4K_Restore_CNN_M.glsl' 'Anime4K_Restore_CNN_S.glsl' 'Anime4K_Restore_CNN_Soft_M.glsl'
        'Anime4K_Restore_CNN_Soft_S.glsl' 'Anime4K_Restore_CNN_Soft_VL.glsl' 'Anime4K_Restore_CNN_VL.glsl'
        'Anime4K_Upscale_CNN_x2_M.glsl' 'Anime4K_Upscale_CNN_x2_S.glsl' 'Anime4K_Upscale_CNN_x2_VL.glsl'
        'Anime4K_Upscale_Denoise_CNN_x2_M.glsl' 'Anime4K_Upscale_Denoise_CNN_x2_VL.glsl'
    )
    # key|command. Only added to input.conf when sosc installed (and manages) Anime4K.
    ANIME4K_BINDINGS=(
        'Ctrl+1|script-message-to sosc_upscale set-mode a'
        'Ctrl+2|script-message-to sosc_upscale set-mode b'
        'Ctrl+3|script-message-to sosc_upscale set-mode c'
        'Ctrl+4|script-message-to sosc_upscale set-mode aa'
        'Ctrl+5|script-message-to sosc_upscale set-mode bb'
        'Ctrl+6|script-message-to sosc_upscale set-mode ca'
        'Ctrl+7|script-message-to sosc_upscale set-mode auto'
        'Ctrl+0|script-message-to sosc_upscale set-mode off'
    )
    INPUT_BINDINGS=(
        'Alt+p|script-binding sosc_palettes/open-menu'
        'Alt+s|script-binding sosc_skip/skip'
        'Alt+t|script-binding sosc_subs/open-menu'
    )
    MPV_CONF_LINES=(
        'osc=no'
        'osd-bar=no'
        'include="~~/sosc-palette.conf"'
        'include="~~/sosc-subs.conf"'
        'include="~~/sosc-upscale.conf"'
    )
    SHADERS_DIR='shaders'
    SHADERS_DISABLED_DIR='shaders-desactivados'
    UPSCALE_CONF='sosc-upscale.conf'
    # What sosc puts in front of a line of the user's it turns off (never deleted).
    COMMENT_PREFIX='# sosc: '
    # mpv.conf lines (outside the sosc block, also inside profiles) of an Anime4K
    # installed by hand that turn it on, as Anime4K's templates do.
    ANIME4K_CONF_RE='^[[:space:]]*glsl-shaders(-append|-set|-add)?[[:space:]]*=.*Anime4K_'
    BACKUP_ORIGINAL_MARK='sosc-backup-original.txt'
    BACKUP_KEEP=3
    BLOCK_BEGIN='# >>> sosc (managed block, do not edit) >>>'
    BLOCK_END='# <<< sosc <<<'
    # Files of sosc that hold the user's choices: only copied when missing.
    USER_CHOICE_FILES=('sosc-palette.conf' 'sosc-subs.conf' 'sosc-upscale.conf')
    # script-opts not named sosc-*: removed on uninstall only if sosc put them there.
    SHARED_CONFS=('uosc.conf' 'thumbfast.conf')
    RECORD_NAME='sosc-installed.txt'
    DISABLED_DIR='scripts-desactivados'
    ORIGINALS_DIR='sosc-originales'
    # What the backup copies: only what the installer can change.
    BACKUP_ITEMS=(
        'mpv.conf' 'input.conf' 'scripts' 'script-opts' 'fonts'
        'sosc-palette.conf' 'sosc-subs.conf' 'sosc-upscale.conf' 'sosc-installed.txt'
        'scripts-desactivados' 'sosc-originales' 'shaders-desactivados'
    )
    MPV_CONFIG_FILES=('mpv.conf' 'input.conf' 'sosc-installed.txt' 'sosc-palette.conf' 'sosc-subs.conf' 'sosc-upscale.conf')
    MPV_CONFIG_DIRS=('scripts' 'script-opts')
    # Scripts that replace mpv's on-screen controller and clash with uosc
    # (file names in scripts/, case-insensitive), and the fonts of some of them.
    CONFLICT_PATTERNS=(
        'osc.lua' 'osc_*.lua' 'osc-*.lua' 'oscc.lua' 'oscc_*.lua' 'oscc-*.lua'
        'modernx*.lua' 'modernz*.lua' 'mordenx*.lua' 'mpv-osc-*.lua'
        'mfpbar.lua' 'mpv_thumbnail_script_client_osc*.lua'
    )
    CONFLICT_FONT_PATTERNS=('modernx*' 'modernz*' 'mordenx*')
    UOSC_LEGACY=('uosc.lua' 'uosc_shared')
    # sosc-upscale.conf as sosc-upscale.lua writes it for "Apagado" and
    # "Automático" (mode, quality, mode, quality).
    UPSCALE_CONF_FORMAT='# Generated by sosc-upscale.lua. Mode: %s, quality: %s\nscript-opts-append=sosc_upscale-mode=%s\nscript-opts-append=sosc_upscale-quality=%s\n'
    RECORD_HEADER='# Written by the sosc installer (install/sosc.sh). Used to update and uninstall; do not edit.'
    GLYPH_POINTER='›'
    GLYPH_ELLIPSIS='…'
}

# ---------------------------------------------------------------------------
# Messages (English and Spanish, the same as install/sosc.ps1). %s is replaced
# by the arguments, in order.
# ---------------------------------------------------------------------------

sosc_text_en() {
    local s=''
    case $1 in
        title) s='sosc installer' ;;
        menu) s='1) Install or update\n2) Uninstall\n0) Exit' ;;
        menu_prompt) s='Choose an option' ;;
        invalid) s='Invalid option.' ;;
        detecting) s='Looking for mpv...' ;;
        found_header) s='Config folders found:' ;;
        found_header_uninst) s='Folders with sosc:' ;;
        cand_exe) s='     Player: %s' ;;
        cand_config) s='     Config: %s' ;;
        kind_folder) s='config folder' ;;
        kind_flatpak) s='mpv (Flatpak)' ;;
        kind_snap) s='mpv (Snap)' ;;
        tag_installed) s='[sosc %s installed]' ;;
        tag_manual) s='[sosc files present, no installer record]' ;;
        tag_readonly) s='[no write permission]' ;;
        tag_new) s='[will be created]' ;;
        opt_other) s='O) Other folder' ;;
        opt_quit) s='0) Exit' ;;
        select_prompt) s='Choose one or more, separated by commas (e.g. 1,3)' ;;
        ask_folder) s='Full path of the mpv config folder (where mpv.conf is or should go)' ;;
        folder_missing) s='The folder %s does not exist and neither does its parent.' ;;
        readonly_warn) s='Cannot write to %s.' ;;
        readonly_skip) s='Skipping %s.' ;;
        none_found) s='mpv was not found.' ;;
        brew_offer) s='Install mpv with Homebrew now ("brew install mpv")?' ;;
        brew_failed) s='brew finished with code %s.' ;;
        none_mac_help) s='Install mpv first and run this installer again: with Homebrew (https://brew.sh), "brew install mpv"; or download mpv.app (https://mpv.io/installation/) into Applications.' ;;
        none_linux_help) s='Install mpv with your distribution'"'"'s package manager and run this installer again, for example:\n  Debian, Ubuntu, Mint: sudo apt install mpv\n  Fedora: sudo dnf install mpv\n  Arch, Manjaro: sudo pacman -S mpv\n  openSUSE: sudo zypper install mpv\n  Flatpak: flatpak install flathub io.mpv.Mpv' ;;
        none_link) s='Ways to get mpv: https://mpv.io/installation/' ;;
        iina_note) s='IINA is installed: it has its own settings and is not touched. sosc is for mpv.' ;;
        mpv_found) s='mpv: %s' ;;
        yes_no_default_yes) s=' [Y/n] ' ;;
        yes_no_default_no) s=' [y/N] ' ;;
        backup_done) s='Backup: %s' ;;
        backup_size) s='Backing up the files sosc touches (%s MB)...' ;;
        backup_failed) s='Could not back up %s: %s. Nothing was changed in that folder.' ;;
        conflicts_found) s='These scripts replace the mpv controls and clash with uosc:' ;;
        conflicts_confirm) s='Move them to %s? Nothing is deleted.' ;;
        conflicts_kept) s='Left in place: uosc and that interface will both draw controls.' ;;
        broken_found) s='These files in scripts are not scripts but the error page of a failed download (mpv logs an error for each one):' ;;
        broken_confirm) s='Move them to %s? Nothing is deleted, and they come back when you uninstall.' ;;
        broken_kept) s='Left in place: mpv keeps logging an error for each one at start-up.' ;;
        moved) s='Moved %s -> %s' ;;
        downloading) s='Downloading %s...' ;;
        download_failed) s='Could not download %s.' ;;
        hash_bad) s='The download of %s does not match its expected SHA256 (expected %s, got %s). Nothing was installed from it.' ;;
        url_bad) s='Refusing to download %s: only HTTPS from GitHub is allowed.' ;;
        release_unpublished) s='sosc has no published release yet, so this installer cannot run on its own. Download the repository and run install/sosc.sh from that copy.' ;;
        source_missing) s='sosc files not found in %s.' ;;
        installing_to) s='Installing sosc into %s' ;;
        uosc_done) s='uosc %s installed.' ;;
        thumbfast_done) s='thumbfast installed.' ;;
        sosc_files_done) s='sosc files copied (%s).' ;;
        kept_user_file) s='%s already exists: kept (it holds your choice).' ;;
        removed_stale) s='Removed old sosc file %s.' ;;
        mpvpath_set) s='thumbfast.conf: mpv_path=%s' ;;
        block_updated) s='%s: sosc block written.' ;;
        default_section) s='%s ends inside a [profile]: the sosc block starts with [default] so its options apply to every file.' ;;
        key_taken) s='%s is already bound in input.conf (%s). sosc leaves it alone; bind another key to "%s" if you want.' ;;
        key_same) s='%s already runs "%s" in your input.conf: left as it is.' ;;
        install_ok) s='sosc installed in %s.' ;;
        target_failed) s='%s: %s' ;;
        restore_hint) s='Your previous config is in %s.' ;;
        summary) s='Done: %s of %s folders.' ;;
        restart) s='Restart the player to see the changes.' ;;
        uninstalling_from) s='Removing sosc from %s' ;;
        ask_remove_uosc) s='Remove uosc too?' ;;
        ask_remove_thumbfast) s='Remove thumbfast too?' ;;
        ask_restore) s='Move back the interfaces sosc set aside (%s)?' ;;
        ask_restore_broken) s='Move back the broken scripts sosc set aside (%s)?' ;;
        ask_delete_choices) s='Delete your saved palette, subtitle and upscaling choices (sosc-palette.conf, sosc-subs.conf, sosc-upscale.conf)?' ;;
        restore_skipped) s='%s not moved back: %s already exists.' ;;
        conf_restored) s='%s: your version from before sosc was put back.' ;;
        conf_left) s='%s was there before sosc and is left as it is now. Your earlier version is in %s.' ;;
        conf_unknown) s='%s left in place (no installer record says who put it there).' ;;
        includes_outside) s='mpv.conf still includes %s outside the sosc block: remove that line, or mpv will log an error at start-up.' ;;
        uninstall_ok) s='sosc removed from %s.' ;;
        nothing_to_uninstall) s='sosc does not seem to be installed in any detected folder.' ;;
        usage_many) s='Several folders found; without questions, choose with --target:' ;;
        usage_none) s='Nothing to work on.' ;;
        error_generic) s='Error: %s' ;;
        malformed_block) s='%s has an incomplete or repeated sosc block (a start or end marker is missing). Fix it by hand and run the installer again.' ;;
        outside_target) s='Refusing to delete %s: it is outside %s.' ;;
        cancelled) s='Cancelled.' ;;
        link_skipped) s='Not copied to the backup: %s is a symbolic link.' ;;
        path_bad) s='%s is not a valid folder path.' ;;
        target_root) s='Refusing %s: the root folder or your home folder is not an mpv config folder.' ;;
        not_mpv_folder) s='%s does not look like an mpv config folder: no mpv.conf, input.conf, scripts or script-opts in it.' ;;
        not_mpv_confirm) s='Use it anyway?' ;;
        not_mpv_yes) s='Without questions such a folder is refused: run it in a terminal to confirm it.' ;;
        mpv_home_note) s='MPV_HOME is set: mpv reads its config from %s.' ;;
        root_warn) s='The installer is running as root (sudo). It does not need it, and what it creates would belong to root.' ;;
        root_confirm) s='Continue as root?' ;;
        root_refused) s='As root and without questions nothing is done: run it as your own user, without sudo.' ;;
        record_bad) s='Ignored an invalid entry in sosc-installed.txt: %s' ;;
        menu_help) s='↑/↓ to move · Enter to choose · Esc to exit' ;;
        multi_help) s='↑/↓ to move · Space to tick or untick · Esc to exit' ;;
        multi_help2) s='Enter to confirm (with nothing ticked, the highlighted one is chosen)' ;;
        yesno_help) s='←/→ to change · Enter to confirm · Y/N · Esc = No' ;;
        menu_help_short) s='↑/↓ · Enter · Esc' ;;
        multi_help_short) s='↑/↓ · Space · Enter · Esc' ;;
        answer_yes) s='Yes' ;;
        answer_no) s='No' ;;
        anime4k_intro) s='Anime4K sharpens and upscales anime on the graphics card. It starts in Automático mode, which picks a mode from the resolution of each video; change it in the Escalado menu or with Ctrl+1 to Ctrl+7 (Ctrl+0 turns it off).' ;;
        anime4k_confirm) s='Install Anime4K (anime upscaling on the graphics card)?' ;;
        anime4k_done) s='Anime4K %s installed (%s shaders in %s).' ;;
        anime4k_animejanai) s='AnimeJaNai already upscales with AI (Ctrl+1 to Ctrl+9): Anime4K is not installed here.' ;;
        anime4k_declined) s='Anime4K not installed. Run the installer again to install it.' ;;
        anime4k_kept) s='Anime4K left as it is (--anime4k no).' ;;
        anime4k_manual) s='There is already an Anime4K installed by hand in %s (files: %s).' ;;
        anime4k_manage) s='Let sosc take care of it? Your files go to %s (nothing is deleted, they come back on uninstall) and sosc installs its own copy, with the Escalado menu and the Ctrl+0 to Ctrl+7 keys.' ;;
        anime4k_manual_kept) s='Your Anime4K is left as it is, with its own keys. The sosc Escalado menu changes the same shaders and does not know what those keys turned on.' ;;
        anime4k_keys_found) s='input.conf binds these Anime4K keys outside the sosc block:' ;;
        anime4k_comment) s='Turn those lines off by putting "# sosc: " in front of them, so the sosc keys can use them? They are turned back on when you uninstall.' ;;
        anime4k_commented) s='input.conf: lines turned off with "# sosc: ": %s.' ;;
        anime4k_bad_zip) s='The Anime4K download does not have the shaders sosc needs (%s).' ;;
        anime4k_conf_found) s='mpv.conf turns Anime4K on at start-up outside the sosc block:' ;;
        anime4k_conf_comment) s='Turn those lines off by putting "# sosc: " in front of them? Otherwise Anime4K would always be on, even with Apagado. They are turned back on when you uninstall.' ;;
        anime4k_conf_commented) s='mpv.conf: lines turned off with "# sosc: ": %s.' ;;
        anime4k_failed) s='Could not get Anime4K: %s The rest of sosc is installed; run the installer again to install Anime4K.' ;;
        anime4k_uptodate) s='Anime4K %s is already installed, with every shader sosc needs.' ;;
        ask_uncomment_conf) s='Turn your Anime4K lines in mpv.conf back on?' ;;
        uncommented_conf) s='mpv.conf: lines turned back on: %s.' ;;
        backup_original_note) s='This backup holds the mpv configuration from before sosc was first installed here. The sosc installer never deletes it.' ;;
        gpu_line) s='Graphics card: %s → quality %s' ;;
        gpu_unknown) s='unknown' ;;
        quality_hq) s='High' ;;
        quality_fast) s='Fast' ;;
        backup_pruned) s='Old backup deleted: %s' ;;
        backup_prune_failed) s='Could not delete the old backup %s.' ;;
        ask_restore_anime4k) s='Move your earlier Anime4K back from %s?' ;;
        ask_uncomment) s='Turn your Anime4K keys in input.conf back on?' ;;
        uncommented) s='input.conf: lines turned back on: %s.' ;;
        osc_orphan) s='mpv.conf has "%s" outside the sosc block: without uosc the player would have no on-screen controls.' ;;
        ask_restore_osc) s='Move back the interfaces sosc set aside (%s), so there are controls?' ;;
        ask_comment_osc) s='Turn that line off by putting "# sosc: " in front of it, so mpv shows its own controls?' ;;
        osc_commented) s='mpv.conf: "%s" turned off with "# sosc: ".' ;;
        osc_left) s='Left as it is: remove that line or install an on-screen controller to get controls back.' ;;
        unsupported_os) s='This installer is for macOS and Linux (this system is %s). On Windows use sosc.ps1: see the README.' ;;
        missing_tool) s='%s is needed and was not found.' ;;
        bad_option) s='Unknown option: %s (see --help).' ;;
        no_input) s='No terminal to ask on: every question takes its default answer.' ;;
        usage) s='Usage: sosc.sh [--install | --uninstall] [--target <folder>]... [--yes] [--no-menu] [--anime4k yes|no]' ;;
    esac
    printf '%s' "$s"
}

sosc_text_es() {
    local s=''
    case $1 in
        title) s='Instalador de sosc' ;;
        menu) s='1) Instalar o actualizar\n2) Desinstalar\n0) Salir' ;;
        menu_prompt) s='Elige una opción' ;;
        invalid) s='Opción no válida.' ;;
        detecting) s='Buscando mpv...' ;;
        found_header) s='Carpetas de configuración encontradas:' ;;
        found_header_uninst) s='Carpetas con sosc:' ;;
        cand_exe) s='     Reproductor: %s' ;;
        cand_config) s='     Configuración: %s' ;;
        kind_folder) s='carpeta de configuración' ;;
        kind_flatpak) s='mpv (Flatpak)' ;;
        kind_snap) s='mpv (Snap)' ;;
        tag_installed) s='[sosc %s instalado]' ;;
        tag_manual) s='[hay ficheros de sosc, sin registro del instalador]' ;;
        tag_readonly) s='[sin permiso de escritura]' ;;
        tag_new) s='[se creará]' ;;
        opt_other) s='O) Otra carpeta' ;;
        opt_quit) s='0) Salir' ;;
        select_prompt) s='Elige uno o varios separados por comas (p. ej. 1,3)' ;;
        ask_folder) s='Ruta completa de la carpeta de configuración de mpv (donde está o irá mpv.conf)' ;;
        folder_missing) s='No existe la carpeta %s ni la que la contiene.' ;;
        readonly_warn) s='No se puede escribir en %s.' ;;
        readonly_skip) s='Se omite %s.' ;;
        none_found) s='No se ha encontrado mpv.' ;;
        brew_offer) s='¿Instalar ahora mpv con Homebrew ("brew install mpv")?' ;;
        brew_failed) s='brew ha terminado con el código %s.' ;;
        none_mac_help) s='Instala primero mpv y vuelve a ejecutar este instalador: con Homebrew (https://brew.sh), "brew install mpv"; o descarga mpv.app (https://mpv.io/installation/) en Aplicaciones.' ;;
        none_linux_help) s='Instala mpv con el gestor de paquetes de tu distribución y vuelve a ejecutar este instalador, por ejemplo:\n  Debian, Ubuntu, Mint: sudo apt install mpv\n  Fedora: sudo dnf install mpv\n  Arch, Manjaro: sudo pacman -S mpv\n  openSUSE: sudo zypper install mpv\n  Flatpak: flatpak install flathub io.mpv.Mpv' ;;
        none_link) s='Formas de conseguir mpv: https://mpv.io/installation/' ;;
        iina_note) s='IINA está instalado: tiene su propia configuración y no se toca. sosc es para mpv.' ;;
        mpv_found) s='mpv: %s' ;;
        yes_no_default_yes) s=' [S/n] ' ;;
        yes_no_default_no) s=' [s/N] ' ;;
        backup_done) s='Copia de seguridad: %s' ;;
        backup_size) s='Copia de seguridad de los ficheros que toca sosc (%s MB)...' ;;
        backup_failed) s='No se ha podido hacer la copia de seguridad de %s: %s. No se ha cambiado nada en esa carpeta.' ;;
        conflicts_found) s='Estos scripts sustituyen los controles de mpv y chocan con uosc:' ;;
        conflicts_confirm) s='¿Moverlos a %s? No se borra nada.' ;;
        conflicts_kept) s='Se quedan donde están: uosc y esa interfaz dibujarán controles a la vez.' ;;
        broken_found) s='Estos ficheros de scripts no son scripts sino la página de error de una descarga fallida (mpv da un error por cada uno):' ;;
        broken_confirm) s='¿Moverlos a %s? No se borra nada y vuelven a su sitio al desinstalar.' ;;
        broken_kept) s='Se quedan donde están: mpv sigue dando un error por cada uno al arrancar.' ;;
        moved) s='Movido %s -> %s' ;;
        downloading) s='Descargando %s...' ;;
        download_failed) s='No se ha podido descargar %s.' ;;
        hash_bad) s='La descarga de %s no coincide con su SHA256 esperado (esperado %s, obtenido %s). No se ha instalado nada de ella.' ;;
        url_bad) s='No se descarga %s: solo se admite HTTPS desde GitHub.' ;;
        release_unpublished) s='sosc aún no tiene ninguna versión publicada, así que este instalador no puede funcionar suelto. Descarga el repositorio y ejecuta install/sosc.sh desde esa copia.' ;;
        source_missing) s='No se encuentran los ficheros de sosc en %s.' ;;
        installing_to) s='Instalando sosc en %s' ;;
        uosc_done) s='uosc %s instalado.' ;;
        thumbfast_done) s='thumbfast instalado.' ;;
        sosc_files_done) s='Ficheros de sosc copiados (%s).' ;;
        kept_user_file) s='%s ya existe: se conserva (guarda tu elección).' ;;
        removed_stale) s='Borrado el fichero antiguo de sosc %s.' ;;
        mpvpath_set) s='thumbfast.conf: mpv_path=%s' ;;
        block_updated) s='%s: bloque de sosc escrito.' ;;
        default_section) s='%s termina dentro de un [perfil]: el bloque de sosc empieza con [default] para que sus opciones valgan siempre.' ;;
        key_taken) s='%s ya está asignada en input.conf (%s). sosc no la toca; si quieres, asigna otra tecla a "%s".' ;;
        key_same) s='%s ya ejecuta "%s" en tu input.conf: se deja como está.' ;;
        install_ok) s='sosc instalado en %s.' ;;
        target_failed) s='%s: %s' ;;
        restore_hint) s='Tu configuración anterior está en %s.' ;;
        summary) s='Hecho: %s de %s carpetas.' ;;
        restart) s='Reinicia el reproductor para ver los cambios.' ;;
        uninstalling_from) s='Quitando sosc de %s' ;;
        ask_remove_uosc) s='¿Quitar también uosc?' ;;
        ask_remove_thumbfast) s='¿Quitar también thumbfast?' ;;
        ask_restore) s='¿Devolver a su sitio las interfaces que sosc apartó (%s)?' ;;
        ask_restore_broken) s='¿Devolver a su sitio los scripts rotos que sosc apartó (%s)?' ;;
        ask_delete_choices) s='¿Borrar tus elecciones guardadas de paleta, subtítulos y escalado (sosc-palette.conf, sosc-subs.conf, sosc-upscale.conf)?' ;;
        restore_skipped) s='%s no se devuelve: ya existe %s.' ;;
        conf_restored) s='%s: se ha devuelto tu versión de antes de sosc.' ;;
        conf_left) s='%s ya existía antes de sosc y se deja como está ahora. Tu versión anterior está en %s.' ;;
        conf_unknown) s='%s se deja en su sitio (no hay registro del instalador que diga quién lo puso).' ;;
        includes_outside) s='mpv.conf sigue incluyendo %s fuera del bloque de sosc: quita esa línea o mpv dará un error al arrancar.' ;;
        uninstall_ok) s='sosc quitado de %s.' ;;
        nothing_to_uninstall) s='No parece que sosc esté instalado en ninguna de las carpetas encontradas.' ;;
        usage_many) s='Hay varias carpetas; sin preguntas, elige con --target:' ;;
        usage_none) s='No hay nada sobre lo que trabajar.' ;;
        error_generic) s='Error: %s' ;;
        malformed_block) s='%s tiene un bloque de sosc incompleto o repetido (falta una marca de inicio o de fin). Arréglalo a mano y vuelve a ejecutar el instalador.' ;;
        outside_target) s='No se borra %s: está fuera de %s.' ;;
        cancelled) s='Cancelado.' ;;
        link_skipped) s='No se copia a la copia de seguridad: %s es un enlace simbólico.' ;;
        path_bad) s='%s no es una ruta de carpeta válida.' ;;
        target_root) s='No se usa %s: la carpeta raíz o tu carpeta personal no son una carpeta de configuración de mpv.' ;;
        not_mpv_folder) s='%s no parece una carpeta de configuración de mpv: no tiene mpv.conf, input.conf, scripts ni script-opts.' ;;
        not_mpv_confirm) s='¿Usarla de todos modos?' ;;
        not_mpv_yes) s='Sin preguntas se rechaza una carpeta así: ejecútalo en un terminal para confirmarla.' ;;
        mpv_home_note) s='MPV_HOME está definida: mpv lee su configuración de %s.' ;;
        root_warn) s='El instalador se está ejecutando como root (sudo). No le hace falta, y lo que cree pertenecería a root.' ;;
        root_confirm) s='¿Seguir como root?' ;;
        root_refused) s='Como root y sin preguntas no se hace nada: ejecútalo con tu usuario, sin sudo.' ;;
        record_bad) s='Se ignora una entrada no válida de sosc-installed.txt: %s' ;;
        menu_help) s='↑/↓ para moverte · Intro para elegir · Esc para salir' ;;
        multi_help) s='↑/↓ para moverte · Espacio para marcar o desmarcar · Esc para salir' ;;
        multi_help2) s='Intro para confirmar (si no marcas ninguna, se elige la resaltada)' ;;
        yesno_help) s='←/→ para cambiar · Intro para confirmar · S/N · Esc = No' ;;
        menu_help_short) s='↑/↓ · Intro · Esc' ;;
        multi_help_short) s='↑/↓ · Espacio · Intro · Esc' ;;
        answer_yes) s='Sí' ;;
        answer_no) s='No' ;;
        anime4k_intro) s='Anime4K mejora y reescala el anime en la tarjeta gráfica. Empieza en modo Automático, que elige el modo según la resolución de cada vídeo; cámbialo en el menú Escalado o con Ctrl+1 a Ctrl+7 (Ctrl+0 lo apaga).' ;;
        anime4k_confirm) s='¿Instalar Anime4K (reescalado de anime en la gráfica)?' ;;
        anime4k_done) s='Anime4K %s instalado (%s shaders en %s).' ;;
        anime4k_animejanai) s='AnimeJaNai ya reescala con IA (Ctrl+1 a Ctrl+9): aquí no se instala Anime4K.' ;;
        anime4k_declined) s='Anime4K no se instala. Vuelve a ejecutar el instalador para instalarlo.' ;;
        anime4k_kept) s='Anime4K se deja como está (--anime4k no).' ;;
        anime4k_manual) s='Ya hay un Anime4K instalado a mano en %s (ficheros: %s).' ;;
        anime4k_manage) s='¿Quieres que lo gestione sosc? Tus ficheros van a %s (no se borra nada y vuelven al desinstalar) y sosc instala su propia copia, con el menú Escalado y los atajos Ctrl+0 a Ctrl+7.' ;;
        anime4k_manual_kept) s='Tu Anime4K se queda como está, con sus atajos. El menú Escalado de sosc cambia los mismos shaders y no sabe lo que hayan activado esos atajos.' ;;
        anime4k_keys_found) s='input.conf tiene estos atajos de Anime4K fuera del bloque de sosc:' ;;
        anime4k_comment) s='¿Desactivar esas líneas poniéndoles delante "# sosc: ", para que los atajos de sosc puedan usar esas teclas? Se vuelven a activar al desinstalar.' ;;
        anime4k_commented) s='input.conf: líneas desactivadas con "# sosc: ": %s.' ;;
        anime4k_bad_zip) s='La descarga de Anime4K no tiene los shaders que necesita sosc (%s).' ;;
        anime4k_conf_found) s='mpv.conf enciende Anime4K al arrancar fuera del bloque de sosc:' ;;
        anime4k_conf_comment) s='¿Desactivar esas líneas poniéndoles delante "# sosc: "? Si no, Anime4K estaría siempre encendido, incluso con Apagado. Se vuelven a activar al desinstalar.' ;;
        anime4k_conf_commented) s='mpv.conf: líneas desactivadas con "# sosc: ": %s.' ;;
        anime4k_failed) s='No se ha podido obtener Anime4K: %s El resto de sosc se instala; vuelve a ejecutar el instalador para instalar Anime4K.' ;;
        anime4k_uptodate) s='Anime4K %s ya está instalado, con todos los shaders que necesita sosc.' ;;
        ask_uncomment_conf) s='¿Volver a activar tus líneas de Anime4K de mpv.conf?' ;;
        uncommented_conf) s='mpv.conf: líneas activadas de nuevo: %s.' ;;
        backup_original_note) s='Esta copia guarda la configuración de mpv de antes de la primera instalación de sosc en esta carpeta. El instalador de sosc nunca la borra.' ;;
        gpu_line) s='Gráfica: %s → calidad %s' ;;
        gpu_unknown) s='desconocida' ;;
        quality_hq) s='Alta' ;;
        quality_fast) s='Rápida' ;;
        backup_pruned) s='Borrada la copia de seguridad antigua %s' ;;
        backup_prune_failed) s='No se ha podido borrar la copia de seguridad antigua %s.' ;;
        ask_restore_anime4k) s='¿Devolver a su sitio tu Anime4K anterior, que está en %s?' ;;
        ask_uncomment) s='¿Volver a activar tus atajos de Anime4K de input.conf?' ;;
        uncommented) s='input.conf: líneas activadas de nuevo: %s.' ;;
        osc_orphan) s='mpv.conf tiene "%s" fuera del bloque de sosc: sin uosc, el reproductor se quedaría sin controles en pantalla.' ;;
        ask_restore_osc) s='¿Devolver a su sitio las interfaces que sosc apartó (%s), para tener controles?' ;;
        ask_comment_osc) s='¿Desactivar esa línea poniéndole delante "# sosc: ", para que mpv muestre sus propios controles?' ;;
        osc_commented) s='mpv.conf: "%s" desactivada con "# sosc: ".' ;;
        osc_left) s='Se deja como está: quita esa línea o instala otra interfaz para recuperar los controles.' ;;
        unsupported_os) s='Este instalador es para macOS y Linux (este sistema es %s). En Windows usa sosc.ps1: mira el README.' ;;
        missing_tool) s='Hace falta %s y no se encuentra.' ;;
        bad_option) s='Opción desconocida: %s (mira --help).' ;;
        no_input) s='No hay terminal en el que preguntar: cada pregunta toma su respuesta por defecto.' ;;
        usage) s='Uso: sosc.sh [--install | --uninstall] [--target <carpeta>]... [--yes] [--no-menu] [--anime4k yes|no]' ;;
    esac
    printf '%s' "$s"
}

# T <key> [args...]: the message in the current language, with %s replaced.
T() {
    local key=$1 fmt
    shift
    if [ "$SOSC_LANG_CODE" = es ]; then fmt=$(sosc_text_es "$key"); else fmt=$(sosc_text_en "$key"); fi
    [ -n "$fmt" ] || fmt=$key
    # shellcheck disable=SC2059 # the messages above are the format strings.
    printf -- "$fmt" "$@"
}

# es when LC_ALL, LC_MESSAGES or LANG (the first one set, as the C library
# does) starts with "es"; en otherwise. SOSC_LANG=es|en wins (tests).
sosc_language() {
    case ${SOSC_LANG:-} in es | en) printf '%s' "$SOSC_LANG"; return 0 ;; esac
    local v=${LC_ALL:-}
    [ -n "$v" ] || v=${LC_MESSAGES:-}
    [ -n "$v" ] || v=${LANG:-}
    case $v in es*) printf es ;; *) printf en ;; esac
}

# ---------------------------------------------------------------------------
# Output and input
# ---------------------------------------------------------------------------

sosc_color() { # sosc_color <code> <text>: colour only on a terminal
    if [ "$COLOR" = 1 ]; then printf '\033[%sm%s\033[0m\n' "$1" "$2"; else printf '%s\n' "$2"; fi
}
info() { printf '%s\n' "$1"; }
ok() { sosc_color 32 "$1"; }
warn() { sosc_color 33 "$1"; }
error() { if [ "$COLOR" = 1 ]; then printf '\033[31m%s\033[0m\n' "$1" >&2; else printf '%s\n' "$1" >&2; fi; }

# Replaceable in tests: the terminal questions are read from.
sosc_tty_path() { printf '%s' /dev/tty; }

# Where answers come from: stdin when it is a terminal, otherwise the terminal
# itself (curl ... | bash: stdin is the script), opened as fd 3. Without one,
# every question takes its default answer.
io_setup() {
    HAVE_INPUT=0
    MENU=0
    if [ -t 0 ]; then
        exec 3<&0
        HAVE_INPUT=1
    else
        local tty
        tty=$(sosc_tty_path)
        if [ -n "$tty" ] && (: <"$tty") 2>/dev/null; then
            if { exec 3<"$tty"; } 2>/dev/null; then HAVE_INPUT=1; fi
        fi
    fi
    if [ "$HAVE_INPUT" = 1 ] && [ -t 3 ] && [ -t 1 ] && [ "$OPT_NO_MENU" != 1 ] && [ "$OPT_YES" != 1 ] &&
        [ "${TERM:-dumb}" != dumb ] && [ "$(term_cols)" -ge 20 ]; then
        MENU=1
    fi
}

# Reads a line into REPLY_LINE (fails at the end of the input).
read_line() {
    REPLY_LINE=''
    printf '%s: ' "$1"
    if [ "$HAVE_INPUT" != 1 ]; then printf '\n'; return 1; fi
    if IFS= read -r REPLY_LINE <&3; then
        [ -t 3 ] || printf '%s\n' "$REPLY_LINE"
        return 0
    fi
    printf '\n'
    [ -n "$REPLY_LINE" ]
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Sets TRIMMED to $1 without leading and trailing blanks.
trim() {
    local s=$1
    s=${s#"${s%%[![:space:]]*}"}
    s=${s%"${s##*[![:space:]]}"}
    TRIMMED=$s
}

# confirm <question> <default yes|no>: 0 for yes, 1 for no. Without questions
# (--yes or no terminal) the default answer.
confirm() {
    local question=$1 default=$2 answer
    if [ "$NONINTERACTIVE" = 1 ]; then [ "$default" = yes ]; return; fi
    if [ "$MENU" = 1 ]; then
        yesno_menu "$question" "$default"
        case $? in 0) return 0 ;; 1) return 1 ;; esac
        MENU=0
    fi
    local suffix
    if [ "$default" = yes ]; then suffix=$(T yes_no_default_yes); else suffix=$(T yes_no_default_no); fi
    while :; do
        printf '%s' "$question$suffix"
        REPLY_LINE=''
        if ! IFS= read -r REPLY_LINE <&3 && [ -z "$REPLY_LINE" ]; then
            printf '\n'
            [ "$default" = yes ]
            return
        fi
        [ -t 3 ] || printf '%s\n' "$REPLY_LINE"
        trim "$REPLY_LINE"
        answer=$(lower "$TRIMMED")
        case $answer in
            '') [ "$default" = yes ]; return ;;
            s | si | sí | y | yes) return 0 ;;
            n | no) return 1 ;;
        esac
        warn "$(T invalid)"
    done
}

# ---------------------------------------------------------------------------
# Keyboard menus (arrows, Space, Enter, Esc), drawn with ANSI codes. Used only
# on a real terminal; otherwise, or when a menu does not fit, questions are
# asked with numbers and typed answers.
# ---------------------------------------------------------------------------

term_size() {
    local size=''
    if [ "$HAVE_INPUT" = 1 ]; then size=$(stty size <&3 2>/dev/null); fi
    case $size in *[0-9]' '[0-9]*) printf '%s' "$size" ;; *) printf '24 80' ;; esac
}
term_cols() { local s; s=$(term_size); printf '%s' "${s#* }"; }
term_rows() { local s; s=$(term_size); printf '%s' "${s%% *}"; }

menu_enter() {
    STTY_SAVED=$(stty -g <&3 2>/dev/null)
    stty -icanon -echo -isig min 1 time 0 <&3 2>/dev/null
    printf '\033[?25l'
    # Keys pressed before the menu opened (during a download, say) never answer it.
    stty min 0 time 0 <&3 2>/dev/null
    dd bs=256 count=8 <&3 >/dev/null 2>&1
    stty min 1 time 0 <&3 2>/dev/null
}
menu_exit() {
    if [ -n "$STTY_SAVED" ]; then stty "$STTY_SAVED" <&3 2>/dev/null; fi
    STTY_SAVED=''
    printf '\033[?25h'
}

# One key into KEY: up, down, left, right, home, end, enter, space, tab, esc,
# cancel (Ctrl+C) or the character itself. dd, not read: bash's read -n would
# change the terminal settings the Esc timeout relies on.
read_key() {
    local c rest
    c=$(dd bs=1 count=1 <&3 2>/dev/null; printf x)
    c=${c%x}
    case $c in
        $'\033')
            stty min 0 time 1 <&3 2>/dev/null
            rest=$(dd bs=1 count=4 <&3 2>/dev/null)
            stty min 1 time 0 <&3 2>/dev/null
            case $rest in
                '[A' | 'OA') KEY=up ;;
                '[B' | 'OB') KEY=down ;;
                '[C' | 'OC') KEY=right ;;
                '[D' | 'OD') KEY=left ;;
                '[H' | 'OH' | '[1~' | '[7~') KEY=home ;;
                '[F' | 'OF' | '[4~' | '[8~') KEY=end ;;
                '') KEY=esc ;;
                *) KEY=other ;;
            esac
            ;;
        $'\n' | $'\r') KEY=enter ;;
        ' ') KEY=space ;;
        $'\t') KEY=tab ;;
        $'\003' | '') KEY=cancel ;;
        *) KEY=$c ;;
    esac
}

# Text cut to $2 characters with an ellipsis.
fit() {
    local text=$1 max=$2
    if [ "${#text}" -le "$max" ]; then printf '%s' "$text"; return; fi
    if [ "$max" -le 1 ]; then printf '%s' "$GLYPH_ELLIPSIS"; return; fi
    printf '%s%s' "${text:0:$((max - 1))}" "$GLYPH_ELLIPSIS"
}

# Path cut in the middle (the last folders matter most).
fit_middle() {
    local text=$1 max=$2 head tail
    if [ "${#text}" -le "$max" ]; then printf '%s' "$text"; return; fi
    if [ "$max" -le 1 ]; then printf '%s' "$GLYPH_ELLIPSIS"; return; fi
    head=$(((max - 1) / 3))
    tail=$((max - 1 - head))
    printf '%s%s%s' "${text:0:$head}" "$GLYPH_ELLIPSIS" "${text:$((${#text} - tail))}"
}

# Frame lines: FRAME_TEXT (plain text, already cut to the width) and FRAME_COLOR.
frame_add() {
    FRAME_TEXT[${#FRAME_TEXT[@]}]=$1
    FRAME_COLOR[${#FRAME_COLOR[@]}]=${2:-}
}

# Help lines, split between their " · " parts to fit the width.
frame_help() {
    local text=$1 max=$2 line='' part rest
    rest=$text
    while [ -n "$rest" ]; do
        case $rest in
            *' · '*) part=${rest%%' · '*}; rest=${rest#*' · '} ;;
            *) part=$rest; rest='' ;;
        esac
        if [ -z "$line" ]; then
            line=$part
        elif [ $((${#line} + 3 + ${#part})) -le "$max" ]; then
            line="$line · $part"
        else
            frame_add "  $(fit "$line" "$max")" 90
            line=$part
        fi
    done
    [ -z "$line" ] || frame_add "  $(fit "$line" "$max")" 90
}

# Draws FRAME_* over the previous frame, which took DRAWN lines.
frame_draw() {
    local i=0 n=${#FRAME_TEXT[@]}
    if [ "$DRAWN" -gt 0 ]; then printf '\033[%sA' "$DRAWN"; fi
    printf '\r\033[J'
    while [ "$i" -lt "$n" ]; do
        if [ -n "${FRAME_COLOR[i]}" ]; then
            printf '\033[%sm%s\033[0m\n' "${FRAME_COLOR[i]}" "${FRAME_TEXT[i]}"
        else
            printf '%s\n' "${FRAME_TEXT[i]}"
        fi
        i=$((i + 1))
    done
    DRAWN=$n
}

# Builds the list menu frame (full, or compact when $1 = 1).
list_frame() {
    local compact=$1 cols i n=${#M_LABEL[@]} pointer box head color dcolor room
    cols=$(term_cols)
    FRAME_TEXT=()
    FRAME_COLOR=()
    i=0
    while [ "$i" -lt "$n" ]; do
        pointer='  '
        color=''
        dcolor=90
        if [ "$i" = "$M_CUR" ]; then pointer="$GLYPH_POINTER "; color=36; dcolor=36
        elif [ "${M_DISABLED[i]}" = 1 ]; then color=90; fi
        box=''
        if [ "$M_MULTI" = 1 ] && [ "${M_ACTION[i]}" != 1 ]; then
            if [ "${M_CHECKED[i]}" = 1 ]; then box='[x] '; else box='[ ] '; fi
        fi
        head="$pointer$box${M_LABEL[i]}"
        if [ "$compact" = 1 ]; then
            room=$((cols - 1 - ${#head} - 2))
            if [ -n "${M_DETAIL[i]}" ] && [ "$room" -ge 12 ]; then
                head="$head  $(fit_middle "${M_DETAIL[i]}" "$room")"
            fi
            frame_add "$(fit "$head" $((cols - 1)))" "$color"
        else
            frame_add "$(fit "$head" $((cols - 1)))" "$color"
            if [ -n "${M_DETAIL[i]}" ]; then
                frame_add "    $(fit_middle "${M_DETAIL[i]}" $((cols - 5)))" "$dcolor"
            fi
        fi
        i=$((i + 1))
    done
    if [ "$compact" = 1 ]; then
        if [ "$M_MULTI" = 1 ]; then frame_help "$(T multi_help_short)" $((cols - 3)); else frame_help "$(T menu_help_short)" $((cols - 3)); fi
    else
        frame_add ''
        if [ "$M_MULTI" = 1 ]; then
            frame_help "$(T multi_help)" $((cols - 3))
            frame_help "$(T multi_help2)" $((cols - 3))
        else
            frame_help "$(T menu_help)" $((cols - 3))
        fi
    fi
}

# Picks the frame that fits (one line free below it); fails when none does.
list_frame_fit() {
    local rows
    rows=$(term_rows)
    list_frame 0
    [ "${#FRAME_TEXT[@]}" -lt $((rows - 1)) ] && return 0
    list_frame 1
    [ "${#FRAME_TEXT[@]}" -lt $((rows - 1)) ]
}

menu_next() { # menu_next <from> <step>: next entry that is not disabled, wrapping around
    local n=${#M_LABEL[@]} i=$1 k=0
    while [ "$k" -lt "$n" ]; do
        i=$(((i + $2 + n) % n))
        if [ "${M_DISABLED[i]}" != 1 ]; then printf '%s' "$i"; return; fi
        k=$((k + 1))
    done
    printf '%s' "$1"
}

# menu_reset: empties the entry list. menu_item <label> [detail] [action]
# [disabled] [summary] [quit] [hotkey] adds one.
menu_reset() {
    M_LABEL=(); M_DETAIL=(); M_ACTION=(); M_DISABLED=(); M_SUMMARY=(); M_QUIT=(); M_HOTKEY=(); M_CHECKED=()
}
menu_item() {
    local i=${#M_LABEL[@]}
    M_LABEL[i]=$1
    M_DETAIL[i]=${2:-}
    M_ACTION[i]=${3:-0}
    M_DISABLED[i]=${4:-0}
    M_SUMMARY[i]=${5:-$1}
    M_QUIT[i]=${6:-0}
    M_HOTKEY[i]=${7:-}
    M_CHECKED[i]=0
}

# list_menu <multi 0|1> [header lines...]: runs the menu built with menu_item.
# Sets M_CANCELLED (1/0), M_INDEX (entry Enter was pressed on, -1 for ticked
# ones) and M_PICKED (indexes of the chosen entries that are not actions).
# Returns 3, with nothing written, when the menu does not fit.
list_menu() {
    M_MULTI=$1
    shift
    local n=${#M_LABEL[@]} i done=0 summary=''
    M_CUR=$(menu_next -1 1)
    M_CANCELLED=0
    M_INDEX=-1
    M_PICKED=()
    list_frame_fit || return 3
    for i in ${1+"$@"}; do info "$i"; done
    DRAWN=0
    menu_enter
    while [ "$done" = 0 ]; do
        list_frame_fit
        frame_draw
        read_key
        case $KEY in
            esc | cancel) M_CANCELLED=1; done=1 ;;
            up) M_CUR=$(menu_next "$M_CUR" -1) ;;
            down | tab) M_CUR=$(menu_next "$M_CUR" 1) ;;
            home) M_CUR=$(menu_next -1 1) ;;
            end) M_CUR=$(menu_next "$n" -1) ;;
            space)
                if [ "$M_MULTI" = 1 ] && [ "${M_ACTION[M_CUR]}" != 1 ]; then
                    if [ "${M_CHECKED[M_CUR]}" = 1 ]; then M_CHECKED[M_CUR]=0; else M_CHECKED[M_CUR]=1; fi
                fi
                ;;
            enter)
                i=0
                while [ "$i" -lt "$n" ]; do
                    [ "${M_CHECKED[i]}" = 1 ] && M_PICKED[${#M_PICKED[@]}]=$i
                    i=$((i + 1))
                done
                if [ "$M_MULTI" = 1 ] && [ "${M_ACTION[M_CUR]}" != 1 ]; then
                    [ "${#M_PICKED[@]}" -gt 0 ] || M_PICKED=("$M_CUR")
                else
                    M_INDEX=$M_CUR
                fi
                done=1
                ;;
            [0-9])
                if [ "$M_MULTI" != 1 ]; then
                    i=0
                    while [ "$i" -lt "$n" ]; do
                        if [ "${M_HOTKEY[i]}" = "$KEY" ] && [ "${M_DISABLED[i]}" != 1 ]; then
                            M_CUR=$i; M_INDEX=$i; done=1; break
                        fi
                        i=$((i + 1))
                    done
                fi
                ;;
        esac
    done
    # The menu is replaced by one line with the choice (nothing when cancelled).
    FRAME_TEXT=()
    FRAME_COLOR=()
    if [ "$M_CANCELLED" = 0 ]; then
        for i in ${M_PICKED[@]+"${M_PICKED[@]}"}; do summary="$summary${summary:+, }${M_SUMMARY[i]}"; done
        if [ "$M_INDEX" -ge 0 ]; then
            [ "${M_QUIT[M_INDEX]}" = 1 ] && summary=''
            summary="$summary${summary:+, }${M_SUMMARY[M_INDEX]}"
        fi
        frame_add "$(fit "$GLYPH_POINTER $summary" $(($(term_cols) - 1)))" 36
    fi
    frame_draw
    menu_exit
    return 0
}

# Yes/No on one line. Returns 0 (yes), 1 (no) or 3 when it does not fit.
# Esc and Ctrl+C always answer No: every question is asked so that No is safe.
yesno_menu() {
    local question=$1 yes=0 result='' cols rows
    [ "$2" = yes ] && yes=1
    rows=$(term_rows)
    cols=$(term_cols)
    [ "$rows" -ge 3 ] || return 3
    info "$question"
    DRAWN=0
    menu_enter
    while [ -z "$result" ]; do
        FRAME_TEXT=()
        FRAME_COLOR=()
        # Only the highlighted answer in colour (the codes go in the text).
        if [ "$yes" = 1 ]; then
            frame_add "  "$'\033[36m'"$GLYPH_POINTER $(T answer_yes)"$'\033[0m'"      $(T answer_no)"
        else
            frame_add "    $(T answer_yes)    "$'\033[36m'"$GLYPH_POINTER $(T answer_no)"$'\033[0m'
        fi
        [ "$rows" -lt 4 ] || frame_help "$(T yesno_help)" $((cols - 3))
        frame_draw
        read_key
        case $KEY in
            esc | cancel) result=no ;;
            left) yes=1 ;;
            right) yes=0 ;;
            up | down | tab) yes=$((1 - yes)) ;;
            enter) if [ "$yes" = 1 ]; then result=yes; else result=no; fi ;;
            s | S | y | Y) result=yes ;;
            n | N) result=no ;;
        esac
    done
    FRAME_TEXT=()
    FRAME_COLOR=()
    if [ "$result" = yes ]; then frame_add "  $GLYPH_POINTER $(T answer_yes)" 36; else frame_add "  $GLYPH_POINTER $(T answer_no)" 36; fi
    frame_draw
    menu_exit
    [ "$result" = yes ]
}

# ---------------------------------------------------------------------------
# Paths and files
# ---------------------------------------------------------------------------

# Absolute, lexically normalised path (~ expanded, . and .. resolved, no
# trailing /). Links are not resolved. Prints nothing for an empty path.
abs_path() {
    local p=$1 out='' seg
    case $p in '') return 1 ;; \~) p=$HOME ;; \~/*) p=$HOME/${p#\~/} ;; esac
    case $p in /*) ;; *) p=$PWD/$p ;; esac
    local IFS=/
    local parts
    read -r -a parts <<<"$p"
    local stack
    stack=()
    for seg in ${parts[@]+"${parts[@]}"}; do
        case $seg in
            '' | .) ;;
            ..) [ "${#stack[@]}" -gt 0 ] && unset "stack[$((${#stack[@]} - 1))]" ;;
            *) stack[${#stack[@]}]=$seg ;;
        esac
    done
    for seg in ${stack[@]+"${stack[@]}"}; do out="$out/$seg"; done
    printf '%s' "${out:-/}"
}

# True when $1 is strictly inside $2 (never $2 itself).
is_inside() {
    local p r
    p=$(abs_path "$1") || return 1
    r=$(abs_path "$2") || return 1
    [ "$r" = / ] && r=''
    case $p in "$r"/?*) return 0 ;; esac
    return 1
}

# Deletes a file, link or folder inside $2. A link is removed as a link.
remove_item() {
    local p=$1 root=$2
    if ! is_inside "$p" "$root"; then
        SOSC_ERR=$(T outside_target "$p" "$root")
        return 1
    fi
    if [ -L "$p" ] || [ -f "$p" ]; then
        rm -f "$p" || return 1
    elif [ -d "$p" ]; then
        rm -rf "$p" || return 1
    fi
    return 0
}

# Path of $1 relative to the folder $2 ('/'-separated).
rel_path() {
    local p r
    p=$(abs_path "$1")
    r=$(abs_path "$2")
    printf '%s' "${p#"$r"/}"
}

# Can the folder (or, if missing, its nearest existing parent) be written to?
dir_writable() {
    local p=$1
    while [ ! -d "$p" ]; do
        local parent=${p%/*}
        [ -n "$parent" ] || parent=/
        [ "$parent" != "$p" ] || return 1
        p=$parent
    done
    [ -w "$p" ]
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# Writes stdin to $1 through a temporary file next to it and a rename, so a
# failure never leaves half a file. The file keeps its permissions; a link is
# written through (dotfile managers link mpv.conf), not replaced.
write_file() {
    local path=$1 tmp="$1.sosc-tmp.$$"
    if [ -f "$path" ]; then cp -p "$path" "$tmp" 2>/dev/null || :; fi
    if ! cat >"$tmp"; then rm -f "$tmp"; return 1; fi
    if [ -L "$path" ]; then
        cat "$tmp" >"$path" || { rm -f "$tmp"; return 1; }
        rm -f "$tmp"
    else
        mv -f "$tmp" "$path" || { rm -f "$tmp"; return 1; }
    fi
}

# The lines of a text file: F_LINE (content, without line break), F_EOL (crlf,
# lf, or empty for a last line without line break) and F_COUNT. Bytes are kept
# as they are, so writing it back gives the same file (NUL bytes aside, which
# no mpv config has).
load_file() {
    F_LINE=()
    F_EOL=()
    F_COUNT=0
    [ -f "$1" ] || return 0
    local line n=0
    while :; do
        if IFS= read -r line; then
            case $line in
                *$'\r') F_LINE[n]=${line%$'\r'}; F_EOL[n]=crlf ;;
                *) F_LINE[n]=$line; F_EOL[n]=lf ;;
            esac
            n=$((n + 1))
        else
            if [ -n "$line" ]; then F_LINE[n]=$line; F_EOL[n]=''; n=$((n + 1)); fi
            break
        fi
    done <"$1"
    F_COUNT=$n
}

print_lines() {
    local i=0
    while [ "$i" -lt "$F_COUNT" ]; do
        case ${F_EOL[i]} in
            crlf) printf '%s\r\n' "${F_LINE[i]}" ;;
            lf) printf '%s\n' "${F_LINE[i]}" ;;
            *) printf '%s' "${F_LINE[i]}" ;;
        esac
        i=$((i + 1))
    done
}

save_file() { print_lines | write_file "$1"; }

# Line break used for new lines: CRLF when the file has any, LF otherwise.
file_eol() {
    local i=0
    while [ "$i" -lt "$F_COUNT" ]; do
        [ "${F_EOL[i]}" = crlf ] && { printf crlf; return; }
        i=$((i + 1))
    done
    printf lf
}

# ---------------------------------------------------------------------------
# Managed blocks in mpv.conf / input.conf
# ---------------------------------------------------------------------------

# Sets BLOCK_BEGIN_AT and BLOCK_END_AT (-1 when there is no block). Fails, with
# SOSC_ERR set, when the markers do not pair up.
find_block() {
    local i=0 name=$1
    BLOCK_BEGIN_AT=-1
    BLOCK_END_AT=-1
    while [ "$i" -lt "$F_COUNT" ]; do
        trim "${F_LINE[i]}"
        if [ "$TRIMMED" = "$BLOCK_BEGIN" ]; then
            if [ "$BLOCK_BEGIN_AT" -ge 0 ]; then SOSC_ERR=$(T malformed_block "$name"); return 1; fi
            BLOCK_BEGIN_AT=$i
        elif [ "$TRIMMED" = "$BLOCK_END" ]; then
            if [ "$BLOCK_BEGIN_AT" -lt 0 ] || [ "$BLOCK_END_AT" -ge 0 ]; then SOSC_ERR=$(T malformed_block "$name"); return 1; fi
            BLOCK_END_AT=$i
        fi
        i=$((i + 1))
    done
    if [ "$BLOCK_BEGIN_AT" -ge 0 ] && [ "$BLOCK_END_AT" -lt 0 ]; then SOSC_ERR=$(T malformed_block "$name"); return 1; fi
    return 0
}

# Is line $1 outside the block found last?
outside_block() {
    [ "$BLOCK_BEGIN_AT" -lt 0 ] || [ "$1" -lt "$BLOCK_BEGIN_AT" ] || [ "$1" -gt "$BLOCK_END_AT" ]
}

# remove_block <name> <no final eol: 1|0>. When the file had no line break at
# its end before sosc added the block and the block is still last, that line
# break goes too.
remove_block() {
    find_block "$1" || return 1
    [ "$BLOCK_BEGIN_AT" -ge 0 ] || return 0
    local i=0 n=0 last=0
    local lines eols
    lines=()
    eols=()
    [ "$BLOCK_END_AT" -eq $((F_COUNT - 1)) ] && last=1
    while [ "$i" -lt "$F_COUNT" ]; do
        if outside_block "$i"; then lines[n]=${F_LINE[i]}; eols[n]=${F_EOL[i]}; n=$((n + 1)); fi
        i=$((i + 1))
    done
    if [ "$2" = 1 ] && [ "$last" = 1 ] && [ "$n" -gt 0 ] && [ "$BLOCK_BEGIN_AT" -eq "$n" ]; then
        eols[n - 1]=''
    fi
    F_LINE=(${lines[@]+"${lines[@]}"})
    F_EOL=(${eols[@]+"${eols[@]}"})
    F_COUNT=$n
}

# set_block <name> <eol> <lines...>: puts the block (markers added here) in
# place of the old one, or at the end.
set_block() {
    local name=$1 eol=$2 i=0 n=0
    shift 2
    find_block "$name" || return 1
    local lines eols new
    lines=()
    eols=()
    new=("$BLOCK_BEGIN" ${1+"$@"} "$BLOCK_END")
    if [ "$BLOCK_BEGIN_AT" -ge 0 ]; then
        local end_eol=${F_EOL[BLOCK_END_AT]} j
        while [ "$i" -lt "$F_COUNT" ]; do
            if [ "$i" -eq "$BLOCK_BEGIN_AT" ]; then
                j=0
                while [ "$j" -lt "${#new[@]}" ]; do
                    lines[n]=${new[j]}
                    if [ "$j" -eq $((${#new[@]} - 1)) ]; then eols[n]=$end_eol; else eols[n]=$eol; fi
                    n=$((n + 1)); j=$((j + 1))
                done
            elif outside_block "$i"; then
                lines[n]=${F_LINE[i]}; eols[n]=${F_EOL[i]}; n=$((n + 1))
            fi
            i=$((i + 1))
        done
        F_LINE=(${lines[@]+"${lines[@]}"})
        F_EOL=(${eols[@]+"${eols[@]}"})
        F_COUNT=$n
        return 0
    fi
    if [ "$F_COUNT" -gt 0 ] && [ -z "${F_EOL[F_COUNT - 1]}" ]; then F_EOL[F_COUNT - 1]=$eol; fi
    for i in "${new[@]}"; do
        F_LINE[F_COUNT]=$i
        F_EOL[F_COUNT]=$eol
        F_COUNT=$((F_COUNT + 1))
    done
}

# Profile name of an mpv.conf line into PROFILE_NAME; fails when the line is
# not a profile header (mpv's rules: blanks first are skipped, the name is what
# lies between '[' and the first ']', then only blanks and a comment).
profile_header() {
    local re='^[[:space:]]*\[([^]]*)\][[:space:]]*(#.*)?$'
    PROFILE_NAME=''
    [[ $1 =~ $re ]] || return 1
    PROFILE_NAME=${BASH_REMATCH[1]}
}

# Writes the sosc block at the end of mpv.conf (created when missing),
# starting with [default] when the file ends inside a [profile].
update_mpv_conf() {
    local path=$1 eol last='' found=0 i=0
    load_file "$path"
    eol=$(file_eol)
    remove_block mpv.conf 0 || return 1
    while [ "$i" -lt "$F_COUNT" ]; do
        if profile_header "${F_LINE[i]}"; then last=$PROFILE_NAME; found=1; fi
        i=$((i + 1))
    done
    local block
    block=()
    if [ "$found" = 1 ] && [ "$last" != default ] && [ -n "$last" ]; then
        block=('[default]')
        info "$(T default_section mpv.conf)"
    fi
    block=(${block[@]+"${block[@]}"} "${MPV_CONF_LINES[@]}")
    set_block mpv.conf "$eol" "${block[@]}" || return 1
    save_file "$path" || return 1
    info "$(T block_updated mpv.conf)"
}

# Normalised key name, as install/sosc.ps1 does: modifiers lower-cased and
# sorted, a named key (more than one character) lower-cased, a single
# character kept (in mpv, Alt+p and Alt+P are different keys). So CTRL+1 and
# Ctrl+1 are the same key.
norm_key() {
    local k=$1 plus=0 parts mods last i j t
    case $k in *++) k=${k%++}; plus=1 ;; esac
    local IFS=+
    read -r -a parts <<<"$k"
    IFS=' '
    local clean
    clean=()
    for t in ${parts[@]+"${parts[@]}"}; do [ -n "$t" ] && clean[${#clean[@]}]=$t; done
    [ "$plus" = 1 ] && clean[${#clean[@]}]=+
    if [ "${#clean[@]}" -eq 0 ]; then printf '%s' "$1"; return; fi
    last=${clean[${#clean[@]} - 1]}
    [ "${#last}" -gt 1 ] && last=$(lower "$last")
    mods=()
    i=0
    while [ "$i" -lt $((${#clean[@]} - 1)) ]; do mods[i]=$(lower "${clean[i]}"); i=$((i + 1)); done
    # Insertion sort of the modifiers.
    i=1
    while [ "$i" -lt "${#mods[@]}" ]; do
        t=${mods[i]}
        j=$((i - 1))
        while [ "$j" -ge 0 ] && [[ ${mods[j]} > $t ]]; do mods[j + 1]=${mods[j]}; j=$((j - 1)); done
        mods[j + 1]=$t
        i=$((i + 1))
    done
    local out=''
    for t in ${mods[@]+"${mods[@]}"}; do out="$out$t+"; done
    printf '%s' "$out$last"
}

# Collapses blanks into single spaces (SQUEEZED).
squeeze() {
    local IFS=$' \t'
    set -f
    # shellcheck disable=SC2086 # splitting on blanks is the point.
    set -- $1
    set +f
    SQUEEZED="$*"
}

# Splits an input.conf line into LINE_KEY (as written) and LINE_CMD; fails for
# blank lines and comments.
split_binding() {
    trim "$1"
    local c=$TRIMMED
    case $c in '' | '#'*) return 1 ;; esac
    LINE_KEY=${c%%[[:space:]]*}
    trim "${c#"$LINE_KEY"}"
    LINE_CMD=$TRIMMED
}

# Writes the sosc block into input.conf (created when missing). A key the user
# already bound outside the block is left alone (and reported); the same key
# with the same command is not repeated. Extra bindings ("key|command") after
# the path.
update_input_conf() {
    local path=$1 i=0 b key cmd norm j existing
    shift
    load_file "$path"
    find_block input.conf || return 1
    local bound_keys bound_cmds lines
    bound_keys=()
    bound_cmds=()
    lines=()
    while [ "$i" -lt "$F_COUNT" ]; do
        if outside_block "$i" && split_binding "${F_LINE[i]}"; then
            norm=$(norm_key "$LINE_KEY")
            squeeze "$LINE_CMD"
            j=0
            while [ "$j" -lt "${#bound_keys[@]}" ] && [ "${bound_keys[j]}" != "$norm" ]; do j=$((j + 1)); done
            bound_keys[j]=$norm
            bound_cmds[j]=$SQUEEZED
        fi
        i=$((i + 1))
    done
    for b in "${INPUT_BINDINGS[@]}" ${1+"$@"}; do
        key=${b%%|*}
        cmd=${b#*|}
        norm=$(norm_key "$key")
        j=0
        existing=''
        local hit=0
        while [ "$j" -lt "${#bound_keys[@]}" ]; do
            if [ "${bound_keys[j]}" = "$norm" ]; then hit=1; existing=${bound_cmds[j]}; break; fi
            j=$((j + 1))
        done
        if [ "$hit" = 1 ]; then
            case $existing in
                "$cmd" | "$cmd "* | "$cmd#"*) info "$(T key_same "$key" "$cmd")" ;;
                *) warn "$(T key_taken "$key" "$existing" "$cmd")" ;;
            esac
            continue
        fi
        lines[${#lines[@]}]="$key  $cmd"
    done
    set_block input.conf "$(file_eol)" ${lines[@]+"${lines[@]}"} || return 1
    save_file "$path" || return 1
    info "$(T block_updated input.conf)"
}

# remove_managed <path> <root> <created by sosc 1|0> <no final eol 1|0>:
# removes the block; a file that only held it and was created by sosc goes.
remove_managed() {
    local path=$1 name
    [ -f "$path" ] || return 0
    name=${path##*/}
    load_file "$path"
    find_block "$name" || return 1
    [ "$BLOCK_BEGIN_AT" -ge 0 ] || return 0
    remove_block "$name" "$4" || return 1
    if [ "$3" = 1 ]; then
        local i=0 empty=1
        while [ "$i" -lt "$F_COUNT" ]; do
            trim "${F_LINE[i]}"
            [ -z "$TRIMMED" ] || { empty=0; break; }
            i=$((i + 1))
        done
        if [ "$empty" = 1 ]; then remove_item "$path" "$2"; return; fi
    fi
    save_file "$path"
}

# Sets key=value in a script-opts file, replacing the last line for that key,
# or adding it (after a comment) at the end.
set_conf_option() {
    local path=$1 key=$2 value=$3 comment=${4:-} i eol
    load_file "$path"
    eol=$(file_eol)
    i=$((F_COUNT - 1))
    while [ "$i" -ge 0 ]; do
        trim "${F_LINE[i]}"
        case $TRIMMED in
            "$key"=* | "$key "*=* | "$key	"*=*)
                F_LINE[i]="$key=$value"
                save_file "$path"
                return
                ;;
        esac
        i=$((i - 1))
    done
    if [ "$F_COUNT" -gt 0 ] && [ -z "${F_EOL[F_COUNT - 1]}" ]; then F_EOL[F_COUNT - 1]=$eol; fi
    if [ -n "$comment" ]; then
        if [ "$F_COUNT" -gt 0 ]; then F_LINE[F_COUNT]=''; F_EOL[F_COUNT]=$eol; F_COUNT=$((F_COUNT + 1)); fi
        F_LINE[F_COUNT]="# $comment"; F_EOL[F_COUNT]=$eol; F_COUNT=$((F_COUNT + 1))
    fi
    F_LINE[F_COUNT]="$key=$value"; F_EOL[F_COUNT]=$eol; F_COUNT=$((F_COUNT + 1))
    save_file "$path"
}

# ---------------------------------------------------------------------------
# Installer record (sosc-installed.txt)
# ---------------------------------------------------------------------------

# The record can be edited by anyone, so its paths are checked before use:
# relative, '/'-separated, no '.', '..' or empty segment, no backslash, colon,
# wildcard or control character, no segment ending in a dot or a space.
record_path_ok() {
    local rel=$1 seg
    [ -n "$rel" ] || return 1
    case $rel in /* | *\\* | *:* | *'*'* | *'?'* | *'"'* | *'<'* | *'>'* | *'|'* | *[[:cntrl:]]*) return 1 ;; esac
    local IFS=/
    local segs
    read -r -a segs <<<"$rel"
    case $rel in */) return 1 ;; esac
    for seg in ${segs[@]+"${segs[@]}"}; do
        case $seg in '' | *. | *' ') return 1 ;; esac
    done
    return 0
}

# A line of the user's that can be kept in the record: not empty, at most 4000
# characters, no control characters but tabs.
recordable_line() {
    [ -n "$1" ] && [ "${#1}" -le 4000 ] || return 1
    local t=${1//$'\t'/}
    case $t in *[[:cntrl:]]*) return 1 ;; esac
    return 0
}

# Reads the record of folder $1 (fails when there is none): REC_KEYS/REC_VALS
# and the lists REC_FILES, REC_DISABLED, REC_BROKEN, REC_MOVED, REC_COMMENTED
# and REC_COMMENTED_MPV. $2 = quiet: no warnings for bad entries.
read_record() {
    REC_KEYS=(); REC_VALS=(); REC_FILES=(); REC_DISABLED=(); REC_BROKEN=(); REC_MOVED=(); REC_COMMENTED=(); REC_COMMENTED_MPV=()
    local path="$1/$RECORD_NAME" quiet=${2:-0} line key value i=0
    [ -f "$path" ] || return 1
    load_file "$path"
    while [ "$i" -lt "$F_COUNT" ]; do
        line=${F_LINE[i]}
        i=$((i + 1))
        trim "$line"
        case $TRIMMED in '#'* | '') continue ;; *=*) ;; *) continue ;; esac
        trim "${line%%=*}"
        key=$TRIMMED
        trim "${line#*=}"
        value=$TRIMMED
        case $key in
            file)
                if record_path_ok "$value"; then REC_FILES[${#REC_FILES[@]}]=$value
                elif [ "$quiet" != 1 ]; then warn "$(T record_bad "$line")"; fi
                ;;
            disabled | broken)
                if pair_ok "$value"; then
                    if [ "$key" = disabled ]; then REC_DISABLED[${#REC_DISABLED[@]}]=$value; else REC_BROKEN[${#REC_BROKEN[@]}]=$value; fi
                elif [ "$quiet" != 1 ]; then warn "$(T record_bad "$line")"; fi
                ;;
            a4k_moved)
                # shaders-desactivados/<file>|shaders/<file>: never anything else.
                if pair_ok "$value" && [ "${value#"$SHADERS_DISABLED_DIR"/}" != "$value" ] &&
                    [ "${value#*|"$SHADERS_DIR"/}" != "$value" ]; then
                    REC_MOVED[${#REC_MOVED[@]}]=$value
                elif [ "$quiet" != 1 ]; then warn "$(T record_bad "$line")"; fi
                ;;
            a4k_commented | a4k_commented_mpv)
                if recordable_line "$value"; then
                    if [ "$key" = a4k_commented ]; then REC_COMMENTED[${#REC_COMMENTED[@]}]=$value
                    else REC_COMMENTED_MPV[${#REC_COMMENTED_MPV[@]}]=$value; fi
                elif [ "$quiet" != 1 ]; then warn "$(T record_bad "$line")"; fi
                ;;
            *)
                REC_KEYS[${#REC_KEYS[@]}]=$key
                REC_VALS[${#REC_VALS[@]}]=$value
                ;;
        esac
    done
    return 0
}

# "moved|original", both clean record paths.
pair_ok() {
    case $1 in *'|'*'|'*) return 1 ;; *'|'*) ;; *) return 1 ;; esac
    record_path_ok "${1%%|*}" && record_path_ok "${1#*|}"
}

# rec_get <key>: REC_VALUE, and success when the record has that key.
rec_get() {
    local i=${#REC_KEYS[@]}
    REC_VALUE=''
    while [ "$i" -gt 0 ]; do
        i=$((i - 1))
        if [ "${REC_KEYS[i]}" = "$1" ]; then REC_VALUE=${REC_VALS[i]}; return 0; fi
    done
    return 1
}

# Adds "key=value" lines to the record just before the change they describe
# is made, so a failure later in the run never leaves a moved shader or a
# turned-off line unrecorded. Starts a record when there is none.
add_record_entries() {
    local dir=$1 path="$1/$RECORD_NAME" e
    shift
    [ $# -gt 0 ] || return 0
    {
        if [ -f "$path" ]; then
            cat "$path"
            [ ! -s "$path" ] || [ "$(tail -c 1 "$path" | wc -l | tr -d ' ')" != 0 ] || printf '\n'
        else
            printf '%s\n' "$RECORD_HEADER"
        fi
        for e in "$@"; do printf '%s\n' "$e"; done
    } | write_file "$path"
}

# ---------------------------------------------------------------------------
# Sources and downloads
# ---------------------------------------------------------------------------

# Replaceable in tests: downloads $1 to $2.
sosc_fetch() {
    curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 2 -o "$2" "$1"
}

# Downloads $1 to $3 and checks its SHA256 ($2). On mismatch the file is
# deleted: nothing unverified is ever used.
verified_download() {
    local url=$1 sha=$2 out=$3 actual
    case $url in
        https://github.com/* | https://raw.githubusercontent.com/*) ;;
        *) SOSC_ERR=$(T url_bad "$url"); return 1 ;;
    esac
    if [ -z "$sha" ]; then SOSC_ERR=$(T hash_bad "$url" '?' '?'); return 1; fi
    info "$(T downloading "$url")"
    rm -f "$out"
    if ! sosc_fetch "$url" "$out" || [ ! -f "$out" ]; then
        rm -f "$out"
        SOSC_ERR=$(T download_failed "$url")
        return 1
    fi
    actual=$(sha256_of "$out")
    if [ "$actual" != "$(lower "$sha")" ]; then
        rm -f "$out"
        SOSC_ERR=$(T hash_bad "$url" "$(lower "$sha")" "$actual")
        return 1
    fi
}

unzip_to() { mkdir -p "$2" && unzip -q -o "$1" -d "$2" >/dev/null; }

# Commit of the repository copy this file sits in ('' when unknown).
repo_commit() {
    local git="$1/.git" ref
    [ -f "$git/HEAD" ] || return 0
    ref=$(head -n 1 "$git/HEAD")
    case $ref in
        'ref: '*)
            ref=${ref#ref: }
            if [ -f "$git/$ref" ]; then head -n 1 "$git/$ref"
            elif [ -f "$git/packed-refs" ]; then grep " $ref\$" "$git/packed-refs" | head -n 1 | cut -d' ' -f1
            fi
            ;;
        *) printf '%s\n' "$ref" ;;
    esac
}

# Where the sosc files come from: SRC_CONFIG, SRC_VERSION, SRC_COMMIT. A
# release build always uses its own sosc.zip, downloaded and checked; the
# repository version uses the portable_config of its copy.
get_source() {
    SRC_VERSION=$SOSC_VERSION
    SRC_COMMIT=''
    if [ -n "$SOSC_RELEASE_URL" ]; then
        verified_download "$SOSC_RELEASE_URL" "$SOSC_RELEASE_SHA256" "$TEMP_DIR/sosc.zip" || return 1
        unzip_to "$TEMP_DIR/sosc.zip" "$TEMP_DIR/sosc" || { SOSC_ERR=$(T source_missing "$TEMP_DIR/sosc"); return 1; }
        local d
        for d in "$TEMP_DIR/sosc" "$TEMP_DIR"/sosc/*; do
            if [ -f "$d/portable_config/scripts/sosc-palettes.lua" ]; then SRC_CONFIG="$d/portable_config"; return 0; fi
        done
        SOSC_ERR=$(T source_missing "$TEMP_DIR/sosc")
        return 1
    fi
    if [ -n "$SCRIPT_FILE" ] && [ -f "$SCRIPT_FILE" ]; then
        local repo
        repo=$(cd "$(dirname "$SCRIPT_FILE")/.." && pwd)
        if [ -f "$repo/portable_config/scripts/sosc-palettes.lua" ]; then
            SRC_CONFIG="$repo/portable_config"
            SRC_COMMIT=$(repo_commit "$repo")
            return 0
        fi
    fi
    SOSC_ERR=$(T release_unpublished)
    return 1
}

# Downloads and verifies uosc and thumbfast (once for every folder).
get_artifacts() {
    verified_download "$UOSC_URL" "$UOSC_SHA256" "$TEMP_DIR/uosc.zip" || return 1
    unzip_to "$TEMP_DIR/uosc.zip" "$TEMP_DIR/uosc" || { SOSC_ERR=$(T source_missing "$UOSC_URL"); return 1; }
    [ -f "$TEMP_DIR/uosc/scripts/uosc/main.lua" ] || { SOSC_ERR=$(T source_missing "$UOSC_URL"); return 1; }
    verified_download "$THUMBFAST_URL" "$THUMBFAST_SHA256" "$TEMP_DIR/thumbfast.lua" || return 1
}

# Downloads, checks and extracts Anime4K into A4K_SRC: only the entries named
# like Anime4K_*.glsl at the root of the zip. Done before any folder is touched
# (unless --anime4k no), so nothing is moved before every download is checked.
# A failure is kept in A4K_ERROR: Anime4K is then left out, the rest installed.
get_anime4k() {
    A4K_SRC=''
    A4K_ERROR=''
    local zip="$TEMP_DIR/anime4k.zip" dest="$TEMP_DIR/anime4k" names name missing=''
    if ! verified_download "$ANIME4K_URL" "$ANIME4K_SHA256" "$zip"; then A4K_ERROR=$SOSC_ERR; return 1; fi
    names=()
    while IFS= read -r name; do
        [[ $name =~ $ANIME4K_PATTERN ]] && names[${#names[@]}]=$name
    done < <(unzip -Z1 "$zip" 2>/dev/null)
    mkdir -p "$dest"
    if [ "${#names[@]}" -gt 0 ]; then unzip -q -o "$zip" "${names[@]}" -d "$dest" >/dev/null 2>&1; fi
    for name in "${ANIME4K_REQUIRED[@]}"; do
        [ -f "$dest/$name" ] || missing="$missing${missing:+, }$name"
    done
    if [ -n "$missing" ]; then A4K_ERROR=$(T anime4k_bad_zip "$missing"); return 1; fi
    A4K_SRC=$dest
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

# Replaceable in tests.
sosc_uname() { uname -s; }
sosc_cpu_brand() { sysctl -n machdep.cpu.brand_string 2>/dev/null; }
sosc_lspci() { if command -v lspci >/dev/null 2>&1; then lspci 2>/dev/null; fi; }
sosc_brew() { # path of brew, or nothing
    local b
    for b in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -n "$b" ] && [ -x "$b" ] && { printf '%s' "$b"; return; }
    done
}
sosc_iina() { [ -d /Applications/IINA.app ] || [ -d "$HOME/Applications/IINA.app" ]; }
sosc_flatpak_mpv() {
    [ -d "$HOME/.var/app/io.mpv.Mpv" ] && return 0
    command -v flatpak >/dev/null 2>&1 && flatpak info io.mpv.Mpv >/dev/null 2>&1
}
sosc_snap_mpv() { [ -e /snap/bin/mpv ] || [ -d "$HOME/snap/mpv" ]; }

# Absolute path of the mpv binary (not the Flatpak or Snap one), or nothing.
# On macOS also where Homebrew, MacPorts and mpv.app put it: launched from
# Finder (or Seanime) mpv does not get the shell's PATH.
sosc_find_mpv() {
    local p
    p=$(command -v mpv 2>/dev/null)
    case $p in /snap/*) p='' ;; /*) ;; *) p='' ;; esac
    if [ -n "$p" ] && [ -x "$p" ]; then printf '%s' "$p"; return; fi
    if [ "$OS" = Darwin ]; then
        for p in /opt/homebrew/bin/mpv /usr/local/bin/mpv /opt/local/bin/mpv /Applications/mpv.app/Contents/MacOS/mpv \
            "$HOME/Applications/mpv.app/Contents/MacOS/mpv"; do
            if [ -x "$p" ]; then printf '%s' "$p"; return; fi
        done
    else
        for p in /usr/bin/mpv /usr/local/bin/mpv; do
            if [ -x "$p" ]; then printf '%s' "$p"; return; fi
        done
    fi
}

# Candidates: C_KIND (mpv, flatpak, snap, folder), C_DIR and C_EXE.
add_candidate() {
    local dir i=0
    dir=$(abs_path "$2") || return 0
    while [ "$i" -lt "${#C_DIR[@]}" ]; do
        [ "${C_DIR[i]}" = "$dir" ] && return 0
        i=$((i + 1))
    done
    C_KIND[i]=$1
    C_DIR[i]=$dir
    C_EXE[i]=$3
}

# macOS: $MPV_HOME, or ~/.config/mpv (Homebrew's mpv and mpv.app). Linux: the
# same for a native mpv (with $XDG_CONFIG_HOME), plus the Flatpak and Snap
# folders when those are installed.
find_candidates() {
    C_KIND=(); C_DIR=(); C_EXE=()
    local xdg=${XDG_CONFIG_HOME:-$HOME/.config}
    if [ "$OS" = Darwin ]; then
        if [ -n "${MPV_HOME:-}" ]; then add_candidate mpv "$MPV_HOME" "$MPV_EXE"; else add_candidate mpv "$HOME/.config/mpv" "$MPV_EXE"; fi
        return 0
    fi
    if [ -n "$MPV_EXE" ] || [ -d "$xdg/mpv" ] || [ -n "${MPV_HOME:-}" ]; then
        if [ -n "${MPV_HOME:-}" ]; then add_candidate mpv "$MPV_HOME" "$MPV_EXE"; else add_candidate mpv "$xdg/mpv" "$MPV_EXE"; fi
    fi
    if sosc_flatpak_mpv; then add_candidate flatpak "$HOME/.var/app/io.mpv.Mpv/config/mpv" ''; fi
    if sosc_snap_mpv; then add_candidate snap "$HOME/snap/mpv/current/.config/mpv" ''; fi
    return 0
}

kind_label() {
    case $1 in
        flatpak) T kind_flatpak ;;
        snap) T kind_snap ;;
        folder) T kind_folder ;;
        *) printf mpv ;;
    esac
}

# Tags of a candidate: installed (version), files without record, read-only, new.
candidate_tags() {
    local dir=${C_DIR[$1]} tags='' f
    if read_record "$dir" 1; then
        rec_get sosc_version
        tags=$(T tag_installed "$REC_VALUE")
    else
        for f in "$dir"/scripts/sosc-*.lua; do
            if [ -f "$f" ]; then tags=$(T tag_manual); break; fi
        done
    fi
    dir_writable "$dir" || tags="$tags${tags:+ }$(T tag_readonly)"
    [ -d "$dir" ] || tags="$tags${tags:+ }$(T tag_new)"
    printf '%s' "$tags"
}

candidate_installed() {
    local f
    [ -f "${C_DIR[$1]}/$RECORD_NAME" ] && return 0
    for f in "${C_DIR[$1]}"/scripts/sosc-*.lua; do [ -f "$f" ] && return 0; done
    return 1
}

# The root folder and the bare home folder are never config folders.
forbidden_target() {
    local p
    p=$(abs_path "$1")
    [ "$p" = / ] && return 0
    [ "$p" = "$(abs_path "$HOME")" ] && return 0
    return 1
}

# False only for a folder that exists, is not empty and shows no sign of mpv.
looks_like_mpv_config() {
    local d=$1 n
    [ -d "$d" ] || return 0
    [ -n "$(ls -A "$d" 2>/dev/null)" ] || return 0
    for n in "${MPV_CONFIG_FILES[@]}"; do [ -f "$d/$n" ] && return 0; done
    for n in "${MPV_CONFIG_DIRS[@]}"; do [ -d "$d/$n" ] && return 0; done
    case $(abs_path "$d") in */mpv) return 0 ;; esac
    return 1
}

# Quality for Anime4K without asking, as the official guide suggests: GPU_NAME
# and GPU_QUALITY (hq or fast). macOS: Apple M Pro, Max and Ultra -> hq; the
# base M chips and Intel Macs -> fast. Linux: a dedicated NVIDIA or AMD card
# (lspci) -> hq; Intel, others or no lspci -> fast.
gpu_detect() {
    GPU_NAME=''
    GPU_QUALITY=fast
    if [ "$OS" = Darwin ]; then
        GPU_NAME=$(sosc_cpu_brand)
        trim "$GPU_NAME"
        GPU_NAME=$TRIMMED
        local re='^Apple[[:space:]]+M[0-9]+[[:space:]]+(Pro|Max|Ultra)([[:space:]]|$)'
        [[ $GPU_NAME =~ $re ]] && GPU_QUALITY=hq
        return 0
    fi
    local line name first='' lines
    lines=$(sosc_lspci | grep -iE 'vga|3d controller|display controller')
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        name=${line#*: }
        [ -n "$first" ] || first=$name
        if printf '%s' "$name" | grep -qi 'nvidia'; then GPU_NAME=$name; GPU_QUALITY=hq; return 0; fi
        if printf '%s' "$name" | grep -qiE '(AMD|ATI).*(Navi|Radeon RX|Vega (56|64)|Radeon VII)'; then
            GPU_NAME=$name; GPU_QUALITY=hq; return 0
        fi
    done <<EOF
$lines
EOF
    GPU_NAME=$first
}

# ---------------------------------------------------------------------------
# Anime4K
# ---------------------------------------------------------------------------

is_own_shader() { record_path_ok "$1" && [[ $1 =~ ^shaders/Anime4K_[A-Za-z0-9_]+\.glsl$ ]]; }

# Anime4K_*.glsl files in shaders/ that sosc did not put there (MANUAL_A4K);
# own shaders are in OWN (record paths).
find_manual_anime4k() {
    MANUAL_A4K=()
    local f name o mine
    for f in "$1/$SHADERS_DIR"/*; do
        [ -f "$f" ] || continue
        name=${f##*/}
        [[ $name =~ $ANIME4K_PATTERN ]] || continue
        mine=0
        for o in ${OWN[@]+"${OWN[@]}"}; do [ "$o" = "shaders/$name" ] && { mine=1; break; }; done
        [ "$mine" = 1 ] || MANUAL_A4K[${#MANUAL_A4K[@]}]=$f
    done
}

anime4k_complete() { # every required shader there, recorded as sosc's, this version
    local cfg=$1 name o found
    [ "$A4K_VERSION" = "$ANIME4K_VERSION" ] || return 1
    for name in "${ANIME4K_REQUIRED[@]}"; do
        found=0
        for o in ${OWN[@]+"${OWN[@]}"}; do [ "$o" = "shaders/$name" ] && { found=1; break; }; done
        [ "$found" = 1 ] && [ -f "$cfg/$SHADERS_DIR/$name" ] || return 1
    done
}

# input.conf line binding Ctrl+0..Ctrl+6 to something that changes
# glsl-shaders, as Anime4K's templates do (CTRL+1 and Ctrl+1 alike).
anime4k_key_line() {
    split_binding "$1" || return 1
    case $(norm_key "$LINE_KEY") in ctrl+[0-6]) ;; *) return 1 ;; esac
    case $LINE_CMD in *glsl-shaders*) return 0 ;; esac
    return 1
}
anime4k_conf_line() { [[ $1 =~ $ANIME4K_CONF_RE ]]; }
osc_off_line() {
    local re='^[[:space:]]*(osc[[:space:]]*=[[:space:]]*"?(no|false)"?|no-osc)[[:space:]]*(#.*)?$'
    [[ $1 =~ $re ]]
}

# Indexes (FOUND) of the lines of the loaded file, outside the sosc block, for
# which the test function $2 is true.
find_lines() {
    local i=0
    FOUND=()
    find_block "$1" || return 1
    while [ "$i" -lt "$F_COUNT" ]; do
        if outside_block "$i" && "$2" "${F_LINE[i]}"; then FOUND[${#FOUND[@]}]=$i; fi
        i=$((i + 1))
    done
}

# comment_lines <path> <record key> <name> <test>: turns off (with the sosc
# prefix) the lines of FOUND, after adding them to the record; lines that could
# not be read back from the record are left on. Appends to COMMENTED_OUT.
comment_lines() {
    local path=$1 key=$2 i t entries c known
    entries=()
    load_file "$path"
    for i in ${FOUND[@]+"${FOUND[@]}"}; do
        trim "${F_LINE[i]}"
        t=$TRIMMED
        recordable_line "$t" || continue
        known=0
        for c in ${COMMENTED_OUT[@]+"${COMMENTED_OUT[@]}"}; do [ "$c" = "$t" ] && { known=1; break; }; done
        if [ "$known" = 0 ]; then
            COMMENTED_OUT[${#COMMENTED_OUT[@]}]=$t
            entries[${#entries[@]}]="$key=$t"
        fi
        F_LINE[i]="$COMMENT_PREFIX${F_LINE[i]}"
    done
    add_record_entries "$CFG" ${entries[@]+"${entries[@]}"} || return 1
    save_file "$path"
}

# Lines (FOUND) that sosc turned off outside the block and recorded (the list
# after $3), still there with the prefix and still passing $2.
find_commented() {
    local name=$1 test=$2 i=0 rest r
    shift 2
    FOUND=()
    find_block "$name" || return 1
    while [ "$i" -lt "$F_COUNT" ]; do
        if outside_block "$i"; then
            case ${F_LINE[i]} in
                "$COMMENT_PREFIX"*)
                    rest=${F_LINE[i]#"$COMMENT_PREFIX"}
                    trim "$rest"
                    for r in ${1+"$@"}; do
                        if [ "$r" = "$TRIMMED" ] && "$test" "$rest"; then FOUND[${#FOUND[@]}]=$i; break; fi
                    done
                    ;;
            esac
        fi
        i=$((i + 1))
    done
}

uncomment_found() { # on the loaded file
    local i
    for i in ${FOUND[@]+"${FOUND[@]}"}; do F_LINE[i]=${F_LINE[i]#"$COMMENT_PREFIX"}; done
}

# Moves an Anime4K shader installed by hand into shaders-desactivados, after
# adding it to the record. Appends "moved|original" to A4K_MOVED.
move_shader_aside() {
    local p=$1 rel name dest destrel
    rel=$(rel_path "$p" "$CFG")
    name=${p##*/}
    mkdir -p "$CFG/$SHADERS_DISABLED_DIR" || return 1
    dest="$CFG/$SHADERS_DISABLED_DIR/$name"
    [ ! -e "$dest" ] || dest="$CFG/$SHADERS_DISABLED_DIR/${name%.glsl}-$STAMP.glsl"
    destrel=$(rel_path "$dest" "$CFG")
    add_record_entries "$CFG" "a4k_moved=$destrel|$rel" || return 1
    mv "$p" "$dest" || return 1
    info "$(T moved "$rel" "$destrel")"
    A4K_MOVED[${#A4K_MOVED[@]}]="$destrel|$rel"
}

# Decides what to do with Anime4K in the folder and does it. Sets A4K_STATE
# (sosc: installed and managed by sosc; declined; failed: the download or its
# check failed, asked again next time; manual: one installed by hand left
# alone; animejanai), A4K_FILES (record paths of sosc's shaders), A4K_MOVED,
# A4K_COMMENTED, A4K_COMMENTED_MPV, A4K_VERSION and A4K_FRESH (sosc installed
# it in this run and it was not sosc's before).
anime4k_step() {
    local prev='' choice=$OPT_ANIME4K take_over=0 update=0 keep_manual install f
    A4K_FRESH=0
    rec_get anime4k && prev=$REC_VALUE
    A4K_VERSION=''
    rec_get anime4k_version && A4K_VERSION=$REC_VALUE
    OWN=()
    for f in ${OLD_FILES[@]+"${OLD_FILES[@]}"}; do is_own_shader "$f" && OWN[${#OWN[@]}]=$f; done
    A4K_FILES=(${OWN[@]+"${OWN[@]}"})
    A4K_MOVED=(${OLD_MOVED[@]+"${OLD_MOVED[@]}"})
    A4K_COMMENTED=(${OLD_COMMENTED[@]+"${OLD_COMMENTED[@]}"})
    A4K_COMMENTED_MPV=(${OLD_COMMENTED_MPV[@]+"${OLD_COMMENTED_MPV[@]}"})

    for f in "$CFG"/scripts/animejanai*.lua; do
        if [ -f "$f" ]; then info "$(T anime4k_animejanai)"; A4K_STATE=animejanai; return 0; fi
    done

    find_manual_anime4k "$CFG"
    if [ "${#MANUAL_A4K[@]}" -gt 0 ]; then
        warn "$(T anime4k_manual "$SHADERS_DIR" "${#MANUAL_A4K[@]}")"
        keep_manual=1
        if [ "$choice" = yes ]; then keep_manual=0
        elif [ "$choice" != no ] && [ "$prev" != manual ]; then
            confirm "$(T anime4k_manage "$SHADERS_DISABLED_DIR")" no && keep_manual=0
        fi
        if [ "$keep_manual" = 1 ]; then
            warn "$(T anime4k_manual_kept)"
            A4K_STATE=manual
            return 0
        fi
        take_over=1
    elif [ "$prev" = sosc ] && [ "${#OWN[@]}" -gt 0 ]; then
        update=1
        if [ "$choice" = no ]; then info "$(T anime4k_kept)"; A4K_STATE=sosc; return 0; fi
        if anime4k_complete "$CFG"; then
            info "$(T anime4k_uptodate "$ANIME4K_VERSION")"
            A4K_STATE=sosc
            return 0
        fi
    else
        install=1
        [ "$choice" = no ] && install=0
        if [ -z "$choice" ]; then
            info "$(T anime4k_intro)"
            local def=yes
            [ "$prev" = declined ] && def=no
            confirm "$(T anime4k_confirm)" "$def" || install=0
        fi
        if [ "$install" = 0 ]; then
            info "$(T anime4k_declined)"
            A4K_STATE=declined
            return 0
        fi
    fi

    # Anime4K was downloaded and checked before anything was touched. If that
    # failed, the rest of sosc is still installed: an earlier copy of sosc's
    # stays, and otherwise Anime4K is left out and offered again.
    if [ -z "$A4K_SRC" ]; then
        warn "$(T anime4k_failed "${A4K_ERROR:-?}")"
        if [ "$update" = 1 ]; then A4K_STATE=sosc; else A4K_STATE=failed; fi
        return 0
    fi

    local answer
    if [ "$take_over" = 1 ]; then
        for f in "${MANUAL_A4K[@]}"; do move_shader_aside "$f" || return 1; done
        if [ -f "$CFG/input.conf" ]; then
            load_file "$CFG/input.conf"
            find_lines input.conf anime4k_key_line || return 1
            if [ "${#FOUND[@]}" -gt 0 ]; then
                warn "$(T anime4k_keys_found)"
                for f in "${FOUND[@]}"; do trim "${F_LINE[f]}"; warn "  $TRIMMED"; done
                answer=1
                if [ "$choice" = yes ] || confirm "$(T anime4k_comment)" yes; then answer=0; fi
                if [ "$answer" = 0 ]; then
                    COMMENTED_OUT=(${A4K_COMMENTED[@]+"${A4K_COMMENTED[@]}"})
                    comment_lines "$CFG/input.conf" a4k_commented || return 1
                    A4K_COMMENTED=(${COMMENTED_OUT[@]+"${COMMENTED_OUT[@]}"})
                    info "$(T anime4k_commented "${#FOUND[@]}")"
                fi
            fi
        fi
    fi

    # An Anime4K line in mpv.conf (Anime4K's templates have one, and so do
    # profiles that pick a mode by height) would keep a mode on even with
    # "Apagado", now that the shaders are there. Asked when sosc starts
    # managing Anime4K, not on updates.
    if [ "$update" = 0 ] && [ -f "$CFG/mpv.conf" ]; then
        load_file "$CFG/mpv.conf"
        find_lines mpv.conf anime4k_conf_line || return 1
        if [ "${#FOUND[@]}" -gt 0 ]; then
            warn "$(T anime4k_conf_found)"
            for f in "${FOUND[@]}"; do trim "${F_LINE[f]}"; warn "  $TRIMMED"; done
            answer=1
            if [ "$choice" = yes ] || confirm "$(T anime4k_conf_comment)" yes; then answer=0; fi
            if [ "$answer" = 0 ]; then
                COMMENTED_OUT=(${A4K_COMMENTED_MPV[@]+"${A4K_COMMENTED_MPV[@]}"})
                comment_lines "$CFG/mpv.conf" a4k_commented_mpv || return 1
                A4K_COMMENTED_MPV=(${COMMENTED_OUT[@]+"${COMMENTED_OUT[@]}"})
                info "$(T anime4k_conf_commented "${#FOUND[@]}")"
            fi
        fi
    fi

    # Copy sosc's shaders, recording the new ones first.
    local files entries known o name
    files=()
    entries=()
    for f in "$A4K_SRC"/Anime4K_*.glsl; do
        [ -f "$f" ] || continue
        name=${f##*/}
        [[ $name =~ $ANIME4K_PATTERN ]] || continue
        files[${#files[@]}]="shaders/$name"
        known=0
        for o in ${OWN[@]+"${OWN[@]}"}; do [ "$o" = "shaders/$name" ] && { known=1; break; }; done
        [ "$known" = 1 ] || entries[${#entries[@]}]="file=shaders/$name"
    done
    mkdir -p "$CFG/$SHADERS_DIR" || return 1
    add_record_entries "$CFG" ${entries[@]+"${entries[@]}"} || return 1
    for f in "${files[@]}"; do
        rm -f "$CFG/$f"
        cp "$A4K_SRC/${f#shaders/}" "$CFG/$f" || return 1
    done
    # Files of an earlier Anime4K of sosc's that this one no longer has.
    for o in ${OWN[@]+"${OWN[@]}"}; do
        known=0
        for f in "${files[@]}"; do [ "$f" = "$o" ] && { known=1; break; }; done
        if [ "$known" = 0 ] && [ -f "$CFG/$o" ]; then remove_item "$CFG/$o" "$CFG" || return 1; fi
    done
    ok "$(T anime4k_done "$ANIME4K_VERSION" "${#files[@]}" "$SHADERS_DIR")"
    A4K_STATE=sosc
    A4K_FILES=("${files[@]}")
    A4K_VERSION=$ANIME4K_VERSION
    [ "$update" = 1 ] || A4K_FRESH=1
    return 0
}

# Writes sosc-upscale.conf with mode $1 (off or auto) and the quality of the
# graphics card when it is missing, or always when $2 = 1 (sosc has just
# installed Anime4K here: it starts in "Automático"). Otherwise an existing one
# holds the user's choice and is kept. $3 = 1: say which card was found.
init_upscale_conf() {
    local mode=$1 overwrite=$2 announce=$3 path="$CFG/$UPSCALE_CONF"
    if [ "$overwrite" != 1 ] && [ -f "$path" ]; then
        info "$(T kept_user_file "$UPSCALE_CONF")"
        return 0
    fi
    gpu_detect
    upscale_conf_text "$GPU_QUALITY" "$mode" | write_file "$path" || return 1
    if [ "$announce" = 1 ]; then
        local name=$GPU_NAME
        [ -n "$name" ] || name=$(T gpu_unknown)
        info "$(T gpu_line "$name" "$(T "quality_$GPU_QUALITY")")"
    fi
}

upscale_conf_text() { # <quality> <mode>: what sosc-upscale.lua writes for them
    local q=$1 m=$2
    case $q in hq | fast) ;; *) q=fast ;; esac
    case $m in off | auto) ;; *) m=off ;; esac
    # shellcheck disable=SC2059 # the format is the constant above.
    printf "$UPSCALE_CONF_FORMAT" "$m" "$q" "$m" "$q"
}

# ---------------------------------------------------------------------------
# Install steps
# ---------------------------------------------------------------------------

# Copies what the installer may change to <config>-respaldo-sosc-<stamp>, next
# to it (BACKUP; '' when there is nothing to copy). Symbolic links to folders
# are skipped, never followed; a linked file is copied as the file. A copy
# that fails half-way is deleted.
make_backup() {
    local cfg=$1 parent name p items kb=0 k base n
    BACKUP=''
    parent=${cfg%/*}
    [ -n "$parent" ] || { SOSC_ERR=$(T target_root "$cfg"); return 1; }
    items=()
    for name in "${BACKUP_ITEMS[@]}"; do
        p="$cfg/$name"
        [ -e "$p" ] || [ -L "$p" ] || continue
        if [ -L "$p" ] && [ -d "$p" ]; then warn "$(T link_skipped "$p")"; continue; fi
        if [ -L "$p" ] && [ ! -e "$p" ]; then warn "$(T link_skipped "$p")"; continue; fi
        items[${#items[@]}]=$name
    done
    [ "${#items[@]}" -gt 0 ] || return 0
    base="$cfg-respaldo-sosc-$STAMP"
    BACKUP=$base
    n=2
    while [ -e "$BACKUP" ] || [ -L "$BACKUP" ]; do BACKUP="$base-$n"; n=$((n + 1)); done
    for name in "${items[@]}"; do
        k=$(du -skL "$cfg/$name" 2>/dev/null | cut -f1)
        kb=$((kb + ${k:-0}))
    done
    info "$(T backup_size "$((kb / 1024)).$(((kb % 1024) * 10 / 1024))")"
    if ! mkdir "$BACKUP"; then SOSC_ERR=$BACKUP; BACKUP=''; return 1; fi
    for name in "${items[@]}"; do
        if [ -d "$cfg/$name" ]; then
            cp -pPR "$cfg/$name" "$BACKUP/$name" || { rm -rf "$BACKUP"; SOSC_ERR=$name; BACKUP=''; return 1; }
        else
            cp -p "$cfg/$name" "$BACKUP/$name" || { rm -rf "$BACKUP"; SOSC_ERR=$name; BACKUP=''; return 1; }
        fi
    done
    return 0
}

# Keeps the newest BACKUP_KEEP backups of the folder and deletes older ones.
# Only folders named exactly <config>-respaldo-sosc-<stamp>[-n] next to it
# count; links are never touched; the backup from before sosc's first install
# (it holds the mark file, or is the record's first_backup) is never deleted.
prune_backups() {
    local cfg=$1 protect=${2:-} parent leaf d name re list stamp num path kept=0
    parent=${cfg%/*}
    leaf=${cfg##*/}
    [ -d "$parent" ] || return 0
    re='^-respaldo-sosc-([0-9]{8}-[0-9]{6})(-([0-9]+))?$'
    list=''
    for d in "$parent/$leaf"-respaldo-sosc-*; do
        if [ ! -d "$d" ] || [ -L "$d" ]; then continue; fi
        name=${d##*/}
        name=${name#"$leaf"}
        [[ $name =~ $re ]] || continue
        stamp=${BASH_REMATCH[1]}
        num=${BASH_REMATCH[3]:-1}
        list="$list$stamp $num $d"$'\n'
    done
    [ -n "$list" ] || return 0
    while IFS=' ' read -r stamp num path; do
        [ -n "$path" ] || continue
        kept=$((kept + 1))
        [ "$kept" -gt "$BACKUP_KEEP" ] || continue
        [ -n "$protect" ] && [ "$(abs_path "$protect")" = "$(abs_path "$path")" ] && continue
        [ -f "$path/$BACKUP_ORIGINAL_MARK" ] && continue
        if is_inside "$path" "$parent" && rm -rf "$path"; then
            info "$(T backup_pruned "$path")"
        else
            warn "$(T backup_prune_failed "$path")"
        fi
    done <<EOF
$(printf '%s' "$list" | sort -k1,1r -k2,2nr)
EOF
}

# Is there a backup of this folder, other than $2, marked as the original?
other_original_backup() {
    local d
    for d in "$1"-respaldo-sosc-*; do
        [ -d "$d" ] && [ ! -L "$d" ] && [ "$d" != "$2" ] && [ -f "$d/$BACKUP_ORIGINAL_MARK" ] && return 0
    done
    return 1
}

# Conflicting interfaces (CONFLICTS: paths), as install/sosc.ps1.
find_conflicts() {
    local cfg=$1 f name pat stem names
    CONFLICTS=()
    names=()
    shopt -s nocasematch
    for f in "$cfg"/scripts/*; do
        [ -f "$f" ] || continue
        name=${f##*/}
        for pat in "${CONFLICT_PATTERNS[@]}"; do
            # shellcheck disable=SC2053 # $pat is a glob on purpose.
            if [[ $name == $pat ]]; then CONFLICTS[${#CONFLICTS[@]}]=$f; names[${#names[@]}]=${name%.*}; break; fi
        done
    done
    # Their options, named after the script (any case: Linux file systems care).
    for f in "$cfg"/script-opts/*.conf; do
        [ -f "$f" ] || continue
        name=${f##*/}
        for stem in ${names[@]+"${names[@]}"}; do
            if [[ $name == "$stem.conf" ]]; then CONFLICTS[${#CONFLICTS[@]}]=$f; break; fi
        done
    done
    if [ "${#names[@]}" -gt 0 ]; then
        for f in "$cfg"/fonts/*; do
            [ -f "$f" ] || continue
            name=${f##*/}
            for pat in "${CONFLICT_FONT_PATTERNS[@]}"; do
                # shellcheck disable=SC2053
                [[ $name == $pat ]] || continue
                for stem in "${names[@]}"; do
                    # shellcheck disable=SC2053
                    if [[ $stem == $pat ]]; then CONFLICTS[${#CONFLICTS[@]}]=$f; break 2; fi
                done
            done
        done
    fi
    shopt -u nocasematch
}

# A .lua in scripts/ whose first line shows it is the page a failed download
# saved instead of the script: "404: Not Found" (GitHub raw), "Not Found", or
# an HTML page. mpv logs an error for each one at start-up.
broken_script() {
    local first=''
    IFS= read -r first <"$1" || [ -n "$first" ] || return 1
    first=${first#$'\357\273\277'}
    trim "$first"
    first=$(lower "$TRIMMED")
    local re='^(404:?[[:space:]]*)?not found$'
    [[ $first =~ $re ]] && return 0
    case $first in '<!doctype'* | '<html'*) return 0 ;; esac
    return 1
}

find_broken_scripts() {
    local f
    BROKEN=()
    for f in "$1"/scripts/*.lua; do
        if [ ! -f "$f" ] || [ -L "$f" ]; then continue; fi
        broken_script "$f" && BROKEN[${#BROKEN[@]}]=$f
    done
}

# Moves a file or folder of the config into scripts-desactivados, keeping its
# sub-folder (scripts/, script-opts/, fonts/). Sets MOVED_PAIR "moved|original".
move_to_disabled() {
    local p=$1 rel sub dest_dir name dest
    is_inside "$p" "$CFG" || { SOSC_ERR=$(T outside_target "$p" "$CFG"); return 1; }
    rel=$(rel_path "$p" "$CFG")
    sub=''
    case $rel in */*) sub=${rel%/*} ;; esac
    dest_dir="$CFG/$DISABLED_DIR"
    if [ -n "$sub" ] && [ "$sub" != scripts ]; then dest_dir="$dest_dir/$sub"; fi
    mkdir -p "$dest_dir" || return 1
    name=${p##*/}
    dest="$dest_dir/$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ -d "$p" ] || [ "${name%.*}" = "$name" ]; then dest="$dest_dir/$name-$STAMP"
        else dest="$dest_dir/${name%.*}-$STAMP.${name##*.}"; fi
    fi
    mv "$p" "$dest" || return 1
    MOVED_PAIR="$(rel_path "$dest" "$CFG")|$rel"
    info "$(T moved "$rel" "${MOVED_PAIR%%|*}")"
}

uosc_present() { [ -d "$1/scripts/uosc" ] || [ -f "$1/scripts/uosc.lua" ]; }

install_uosc() {
    local legacy font
    mkdir -p "$CFG/scripts" || return 1
    for legacy in "${UOSC_LEGACY[@]}"; do
        if [ -e "$CFG/scripts/$legacy" ] || [ -L "$CFG/scripts/$legacy" ]; then
            move_to_disabled "$CFG/scripts/$legacy" || return 1
            DISABLED[${#DISABLED[@]}]=$MOVED_PAIR
        fi
    done
    remove_item "$CFG/scripts/uosc" "$CFG" || return 1
    cp -R "$TEMP_DIR/uosc/scripts/uosc" "$CFG/scripts/uosc" || return 1
    mkdir -p "$CFG/fonts" || return 1
    for font in "${UOSC_FONTS[@]}"; do
        if [ -f "$TEMP_DIR/uosc/fonts/$font" ]; then
            rm -f "$CFG/fonts/$font"
            cp "$TEMP_DIR/uosc/fonts/$font" "$CFG/fonts/$font" || return 1
        fi
    done
}

yesno() { if [ "$1" = 1 ]; then printf yes; else printf no; fi; }

# prev_flag <record key> <now 1|0>: what the first install saw (from the
# record), or what is there now on a first install.
prev_flag() {
    if [ "$FIRST" = 0 ] && rec_get "$1"; then
        [ "$REC_VALUE" = yes ] && { printf 1; return; }
        printf 0
        return
    fi
    printf '%s' "$2"
}

final_eol_state() { # no when the file exists, is not empty and lacks a final line break
    if [ -s "$1" ] && [ "$(tail -c 1 "$1" | wc -l | tr -d ' ')" = 0 ]; then printf no; else printf yes; fi
}

# Installs into the candidate $1 (index).
install_target() {
    CFG=${C_DIR[$1]}
    local kind=${C_KIND[$1]} exe=${C_EXE[$1]} had_record=0
    info ''
    info "$(T installing_to "$CFG")"
    BACKUP=''
    if [ -d "$CFG" ]; then
        [ -e "$CFG/$RECORD_NAME" ] && had_record=1
        if ! make_backup "$CFG"; then SOSC_ERR=$(T backup_failed "$CFG" "$SOSC_ERR"); return 1; fi
        if [ -n "$BACKUP" ]; then
            info "$(T backup_done "$BACKUP")"
            if [ "$had_record" = 0 ] && ! other_original_backup "$CFG" "$BACKUP"; then
                printf '%s\n' "$(T backup_original_note)" >"$BACKUP/$BACKUP_ORIGINAL_MARK" || warn "$BACKUP/$BACKUP_ORIGINAL_MARK"
            fi
        fi
    else
        mkdir -p "$CFG" || { SOSC_ERR=$CFG; return 1; }
    fi
    if ! install_steps "$kind" "$exe"; then
        [ -z "$BACKUP" ] || SOSC_ERR="$SOSC_ERR $(T restore_hint "$BACKUP")"
        return 1
    fi
    ok "$(T install_ok "$CFG")"
}

install_steps() {
    local kind=$1 exe=$2 f name c
    FIRST=1
    OLD_FILES=(); OLD_DISABLED=(); OLD_BROKEN=(); OLD_MOVED=(); OLD_COMMENTED=(); OLD_COMMENTED_MPV=()
    if read_record "$CFG"; then
        FIRST=0
        OLD_FILES=(${REC_FILES[@]+"${REC_FILES[@]}"})
        OLD_DISABLED=(${REC_DISABLED[@]+"${REC_DISABLED[@]}"})
        OLD_BROKEN=(${REC_BROKEN[@]+"${REC_BROKEN[@]}"})
        OLD_MOVED=(${REC_MOVED[@]+"${REC_MOVED[@]}"})
        OLD_COMMENTED=(${REC_COMMENTED[@]+"${REC_COMMENTED[@]}"})
        OLD_COMMENTED_MPV=(${REC_COMMENTED_MPV[@]+"${REC_COMMENTED_MPV[@]}"})
    fi
    if [ -n "$BACKUP" ]; then
        local protect=''
        rec_get first_backup && protect=$REC_VALUE
        prune_backups "$CFG" "$protect"
    fi

    local uosc_before thumb_before mpv_before input_before shaders_before uconf_before tconf_before
    local mpv_eol input_eol now
    now=0; uosc_present "$CFG" && now=1
    uosc_before=$(prev_flag uosc_preexisting "$now")
    now=0; [ -f "$CFG/scripts/thumbfast.lua" ] && now=1
    thumb_before=$(prev_flag thumbfast_preexisting "$now")
    now=0; [ -f "$CFG/mpv.conf" ] && now=1
    mpv_before=$(prev_flag mpv_conf_preexisting "$now")
    now=0; [ -f "$CFG/input.conf" ] && now=1
    input_before=$(prev_flag input_conf_preexisting "$now")
    now=0; [ -d "$CFG/$SHADERS_DIR" ] && now=1
    shaders_before=$(prev_flag shaders_preexisting "$now")
    now=0; [ -f "$CFG/script-opts/uosc.conf" ] && now=1
    uconf_before=$(prev_flag uosc_conf_preexisting "$now")
    now=0; [ -f "$CFG/script-opts/thumbfast.conf" ] && now=1
    tconf_before=$(prev_flag thumbfast_conf_preexisting "$now")
    if [ "$FIRST" = 0 ] && rec_get mpv_conf_final_eol; then mpv_eol=$REC_VALUE; else mpv_eol=$(final_eol_state "$CFG/mpv.conf"); fi
    if [ "$FIRST" = 0 ] && rec_get input_conf_final_eol; then input_eol=$REC_VALUE; else input_eol=$(final_eol_state "$CFG/input.conf"); fi

    # b. Interfaces that clash with uosc.
    DISABLED=(${OLD_DISABLED[@]+"${OLD_DISABLED[@]}"})
    find_conflicts "$CFG"
    if [ "${#CONFLICTS[@]}" -gt 0 ]; then
        warn "$(T conflicts_found)"
        for c in "${CONFLICTS[@]}"; do warn "  - $(rel_path "$c" "$CFG")"; done
        if confirm "$(T conflicts_confirm "$DISABLED_DIR")" yes; then
            for c in "${CONFLICTS[@]}"; do
                move_to_disabled "$c" || return 1
                DISABLED[${#DISABLED[@]}]=$MOVED_PAIR
            done
        else
            warn "$(T conflicts_kept)"
        fi
    fi

    # b2. Scripts that are the error page of a failed download: set aside
    # (never deleted), and moved back on uninstall.
    local broken_now
    broken_now=(${OLD_BROKEN[@]+"${OLD_BROKEN[@]}"})
    find_broken_scripts "$CFG"
    if [ "${#BROKEN[@]}" -gt 0 ]; then
        warn "$(T broken_found)"
        for c in "${BROKEN[@]}"; do warn "  - $(rel_path "$c" "$CFG")"; done
        if confirm "$(T broken_confirm "$DISABLED_DIR")" yes; then
            for c in "${BROKEN[@]}"; do
                move_to_disabled "$c" || return 1
                broken_now[${#broken_now[@]}]=$MOVED_PAIR
            done
        else
            warn "$(T broken_kept)"
        fi
    fi

    # c. uosc. d. thumbfast.
    install_uosc || return 1
    ok "$(T uosc_done "$UOSC_VERSION")"
    rm -f "$CFG/scripts/thumbfast.lua"
    cp "$TEMP_DIR/thumbfast.lua" "$CFG/scripts/thumbfast.lua" || return 1
    ok "$(T thumbfast_done)"

    # e. sosc files.
    local installed shared s
    installed=()
    for f in "$SRC_CONFIG"/scripts/sosc-*.lua; do
        [ -f "$f" ] || continue
        name=${f##*/}
        rm -f "$CFG/scripts/$name"
        cp "$f" "$CFG/scripts/$name" || return 1
        installed[${#installed[@]}]="scripts/$name"
    done
    mkdir -p "$CFG/script-opts" || return 1
    for f in "$SRC_CONFIG"/script-opts/*.conf; do
        [ -f "$f" ] || continue
        name=${f##*/}
        shared=0
        for s in "${SHARED_CONFS[@]}"; do [ "$s" = "$name" ] && shared=1; done
        if [ "$FIRST" = 1 ] && [ "$shared" = 1 ] && [ -f "$CFG/script-opts/$name" ]; then
            mkdir -p "$CFG/$ORIGINALS_DIR/script-opts" || return 1
            cp -p "$CFG/script-opts/$name" "$CFG/$ORIGINALS_DIR/script-opts/$name" || return 1
        fi
        rm -f "$CFG/script-opts/$name"
        cp "$f" "$CFG/script-opts/$name" || return 1
        installed[${#installed[@]}]="script-opts/$name"
    done
    for name in "${USER_CHOICE_FILES[@]}"; do
        [ "$name" = "$UPSCALE_CONF" ] && continue
        if [ -f "$CFG/$name" ]; then info "$(T kept_user_file "$name")"
        else cp "$SRC_CONFIG/$name" "$CFG/$name" || return 1; fi
    done
    local old keep
    for old in ${OLD_FILES[@]+"${OLD_FILES[@]}"}; do
        keep=0
        for f in "${installed[@]}"; do [ "$f" = "$old" ] && keep=1; done
        [ "$keep" = 0 ] || continue
        [[ $old =~ ^scripts/sosc-[^/]+\.lua$ || $old =~ ^script-opts/sosc-[^/]+\.conf$ ]] || continue
        record_path_ok "$old" || continue
        if [ -f "$CFG/$old" ]; then
            remove_item "$CFG/$old" "$CFG" || return 1
            info "$(T removed_stale "$old")"
        fi
    done
    ok "$(T sosc_files_done "${#installed[@]}")"

    # e2. Anime4K, and the upscale choice file: "Automático" when sosc has just
    # installed Anime4K here; on updates the user's mode is kept.
    anime4k_step || return 1
    local up_mode=off announce=0
    [ "$A4K_STATE" = sosc ] && up_mode=auto
    case $A4K_STATE in sosc | manual) announce=1 ;; esac
    init_upscale_conf "$up_mode" "$A4K_FRESH" "$announce" || return 1
    local extra
    extra=()
    [ "$A4K_STATE" = sosc ] && extra=("${ANIME4K_BINDINGS[@]}")

    # g. thumbfast starts a second mpv for the thumbnails. Started from Finder
    # (or another app), mpv does not have /opt/homebrew/bin in its PATH and
    # the thumbnails come out black: give thumbfast the full path. Not for
    # Flatpak or Snap, where "mpv" inside the sandbox is the right one.
    if [ "$kind" = mpv ] && [ -n "$exe" ]; then
        set_conf_option "$CFG/script-opts/thumbfast.conf" mpv_path "$exe" \
            'Added by the sosc installer: mpv started from Finder or another app may not find mpv in its PATH.' || return 1
        info "$(T mpvpath_set "$exe")"
    fi

    # f. Managed blocks.
    update_mpv_conf "$CFG/mpv.conf" || return 1
    update_input_conf "$CFG/input.conf" ${extra[@]+"${extra[@]}"} || return 1

    # h. Record.
    local first_backup=$BACKUP
    if [ "$FIRST" = 0 ] && rec_get first_backup; then first_backup=$REC_VALUE; fi
    {
        printf '%s\n' "$RECORD_HEADER"
        printf 'sosc_version=%s\n' "$SRC_VERSION"
        printf 'sosc_commit=%s\n' "$SRC_COMMIT"
        printf 'uosc_version=%s\n' "$UOSC_VERSION"
        printf 'thumbfast_commit=%s\n' "$THUMBFAST_COMMIT"
        printf 'installed_at=%s\n' "$(date +%Y-%m-%dT%H:%M:%S)"
        printf 'player=%s\n' "$kind"
        printf 'player_exe=%s\n' "$exe"
        printf 'uosc_preexisting=%s\n' "$(yesno "$uosc_before")"
        printf 'thumbfast_preexisting=%s\n' "$(yesno "$thumb_before")"
        printf 'uosc_conf_preexisting=%s\n' "$(yesno "$uconf_before")"
        printf 'thumbfast_conf_preexisting=%s\n' "$(yesno "$tconf_before")"
        printf 'mpv_conf_preexisting=%s\n' "$(yesno "$mpv_before")"
        printf 'input_conf_preexisting=%s\n' "$(yesno "$input_before")"
        printf 'mpv_conf_final_eol=%s\n' "$mpv_eol"
        printf 'input_conf_final_eol=%s\n' "$input_eol"
        printf 'shaders_preexisting=%s\n' "$(yesno "$shaders_before")"
        printf 'anime4k=%s\n' "$A4K_STATE"
        printf 'anime4k_version=%s\n' "$A4K_VERSION"
        printf 'first_backup=%s\n' "$first_backup"
        printf 'last_backup=%s\n' "$BACKUP"
        for f in ${DISABLED[@]+"${DISABLED[@]}"}; do printf 'disabled=%s\n' "$f"; done
        for f in ${broken_now[@]+"${broken_now[@]}"}; do printf 'broken=%s\n' "$f"; done
        for f in ${A4K_MOVED[@]+"${A4K_MOVED[@]}"}; do printf 'a4k_moved=%s\n' "$f"; done
        for f in ${A4K_COMMENTED[@]+"${A4K_COMMENTED[@]}"}; do printf 'a4k_commented=%s\n' "$f"; done
        for f in ${A4K_COMMENTED_MPV[@]+"${A4K_COMMENTED_MPV[@]}"}; do printf 'a4k_commented_mpv=%s\n' "$f"; done
        for f in "${installed[@]}" ${A4K_FILES[@]+"${A4K_FILES[@]}"}; do printf 'file=%s\n' "$f"; done
    } | write_file "$CFG/$RECORD_NAME" || return 1
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

# Moves set-aside items back ("moved|original" entries, relative to the
# folder), checked again (the record is not trusted): clean paths inside the
# folder, nothing overwritten.
restore_pairs() {
    local entry from to
    for entry in ${1+"$@"}; do
        if ! pair_ok "$entry"; then warn "$(T record_bad "$entry")"; continue; fi
        from="$CFG/${entry%%|*}"
        to="$CFG/${entry#*|}"
        if ! is_inside "$from" "$CFG" || ! is_inside "$to" "$CFG"; then warn "$(T outside_target "$from" "$CFG")"; continue; fi
        [ -e "$from" ] || [ -L "$from" ] || continue
        if [ -e "$to" ] || [ -L "$to" ]; then warn "$(T restore_skipped "${entry%%|*}" "${entry#*|}")"; continue; fi
        mkdir -p "${to%/*}" || return 1
        mv "$from" "$to" || return 1
        info "$(T moved "${entry%%|*}" "${entry#*|}")"
    done
}

pair_names() { # the originals of "moved|original" entries, comma-separated
    local e out=''
    for e in ${1+"$@"}; do out="$out${out:+, }${e#*|}"; done
    printf '%s' "$out"
}

# was_there <key>: yes, no, or '' when the record does not say.
was_there() {
    if [ "$HAS_RECORD" = 1 ] && rec_get "$1"; then
        if [ "$REC_VALUE" = yes ]; then printf yes; else printf no; fi
    fi
}

uninstall_target() {
    CFG=${C_DIR[$1]}
    info ''
    info "$(T uninstalling_from "$CFG")"
    BACKUP=''
    if ! make_backup "$CFG"; then SOSC_ERR=$(T backup_failed "$CFG" "$SOSC_ERR"); return 1; fi
    [ -z "$BACKUP" ] || info "$(T backup_done "$BACKUP")"
    if ! uninstall_steps; then
        [ -z "$BACKUP" ] || SOSC_ERR="$SOSC_ERR $(T restore_hint "$BACKUP")"
        return 1
    fi
    ok "$(T uninstall_ok "$CFG")"
}

uninstall_steps() {
    local f c before rel
    HAS_RECORD=0
    REC_KEYS=(); REC_VALS=(); REC_FILES=(); REC_DISABLED=(); REC_BROKEN=(); REC_MOVED=(); REC_COMMENTED=(); REC_COMMENTED_MPV=()
    read_record "$CFG" && HAS_RECORD=1
    local files disabled broken moved commented commented_mpv
    files=(${REC_FILES[@]+"${REC_FILES[@]}"})
    disabled=(${REC_DISABLED[@]+"${REC_DISABLED[@]}"})
    broken=(${REC_BROKEN[@]+"${REC_BROKEN[@]}"})
    moved=(${REC_MOVED[@]+"${REC_MOVED[@]}"})
    commented=(${REC_COMMENTED[@]+"${REC_COMMENTED[@]}"})
    commented_mpv=(${REC_COMMENTED_MPV[@]+"${REC_COMMENTED_MPV[@]}"})
    if [ -n "$BACKUP" ]; then
        local protect=''
        rec_get first_backup && protect=$REC_VALUE
        prune_backups "$CFG" "$protect"
    fi

    for f in "$CFG"/scripts/sosc-*.lua "$CFG"/script-opts/sosc-*.conf; do
        if [ -f "$f" ] || [ -L "$f" ]; then remove_item "$f" "$CFG" || return 1; fi
    done
    # Anime4K shaders: only the ones the record says sosc installed.
    for rel in ${files[@]+"${files[@]}"}; do
        is_own_shader "$rel" || continue
        if [ -f "$CFG/$rel" ]; then remove_item "$CFG/$rel" "$CFG" || return 1; fi
    done

    for c in "${SHARED_CONFS[@]}"; do
        before=$(was_there "${c%.conf}_conf_preexisting")
        if [ "$before" = yes ] && [ -f "$CFG/$ORIGINALS_DIR/script-opts/$c" ]; then
            rm -f "$CFG/script-opts/$c"
            cp -p "$CFG/$ORIGINALS_DIR/script-opts/$c" "$CFG/script-opts/$c" || return 1
            info "$(T conf_restored "script-opts/$c")"
        elif [ "$before" = no ]; then
            remove_item "$CFG/script-opts/$c" "$CFG" || return 1
        elif [ "$before" = yes ]; then
            rec_get first_backup
            info "$(T conf_left "script-opts/$c" "$REC_VALUE")"
        elif [ -f "$CFG/script-opts/$c" ]; then
            info "$(T conf_unknown "script-opts/$c")"
        fi
    done

    local created noeol
    created=0; [ "$(was_there mpv_conf_preexisting)" = no ] && created=1
    noeol=0; [ "$HAS_RECORD" = 1 ] && rec_get mpv_conf_final_eol && [ "$REC_VALUE" = no ] && noeol=1
    remove_managed "$CFG/mpv.conf" "$CFG" "$created" "$noeol" || return 1
    created=0; [ "$(was_there input_conf_preexisting)" = no ] && created=1
    noeol=0; [ "$HAS_RECORD" = 1 ] && rec_get input_conf_final_eol && [ "$REC_VALUE" = no ] && noeol=1
    remove_managed "$CFG/input.conf" "$CFG" "$created" "$noeol" || return 1

    local remove_uosc=0 def font
    if uosc_present "$CFG"; then
        def=no; [ "$(was_there uosc_preexisting)" = no ] && def=yes
        if confirm "$(T ask_remove_uosc)" "$def"; then
            remove_uosc=1
            remove_item "$CFG/scripts/uosc" "$CFG" || return 1
            for font in "${UOSC_FONTS[@]}"; do remove_item "$CFG/fonts/$font" "$CFG" || return 1; done
        fi
    fi
    if [ -f "$CFG/scripts/thumbfast.lua" ]; then
        def=no; [ "$(was_there thumbfast_preexisting)" = no ] && def=yes
        if confirm "$(T ask_remove_thumbfast)" "$def"; then remove_item "$CFG/scripts/thumbfast.lua" "$CFG" || return 1; fi
    fi

    local pending e
    pending=()
    for e in ${disabled[@]+"${disabled[@]}"}; do case $e in *'|'*) pending[${#pending[@]}]=$e ;; esac; done
    if [ "${#pending[@]}" -gt 0 ]; then
        def=no; [ "$remove_uosc" = 1 ] && def=yes
        if confirm "$(T ask_restore "$(pair_names "${pending[@]}")")" "$def"; then restore_pairs "${pending[@]}" || return 1; fi
    fi
    if [ "${#broken[@]}" -gt 0 ]; then
        if confirm "$(T ask_restore_broken "$(pair_names "${broken[@]}")")" yes; then restore_pairs "${broken[@]}" || return 1; fi
    fi

    # Without uosc, an osc=no of the user's own leaves the player without
    # controls: offer to put back an interface, or to turn that line off.
    # Without questions it only warns.
    if [ "$remove_uosc" = 1 ] && [ -f "$CFG/mpv.conf" ]; then
        load_file "$CFG/mpv.conf"
        find_lines mpv.conf osc_off_line || return 1
        local osc_found
        osc_found=(${FOUND[@]+"${FOUND[@]}"})
        find_conflicts "$CFG"
        if [ "${#osc_found[@]}" -gt 0 ] && [ "${#CONFLICTS[@]}" -eq 0 ]; then
            trim "${F_LINE[${osc_found[0]}]}"
            local osc_text=$TRIMMED
            warn "$(T osc_orphan "$osc_text")"
            local still
            still=()
            for e in ${pending[@]+"${pending[@]}"}; do
                if [ -e "$CFG/${e%%|*}" ]; then still[${#still[@]}]=$e; fi
            done
            def=yes; [ "$NONINTERACTIVE" = 1 ] && def=no
            if [ "${#still[@]}" -gt 0 ] && confirm "$(T ask_restore_osc "$(pair_names "${still[@]}")")" "$def"; then
                restore_pairs "${still[@]}" || return 1
            fi
            find_conflicts "$CFG"
            if [ "${#CONFLICTS[@]}" -eq 0 ]; then
                if confirm "$(T ask_comment_osc)" "$def"; then
                    load_file "$CFG/mpv.conf"
                    for e in "${osc_found[@]}"; do F_LINE[e]="$COMMENT_PREFIX${F_LINE[e]}"; done
                    save_file "$CFG/mpv.conf" || return 1
                    info "$(T osc_commented "$osc_text")"
                else
                    warn "$(T osc_left)"
                fi
            fi
        fi
    fi

    # Anime4K installed by hand that sosc set aside, and the lines it turned off.
    if [ "${#moved[@]}" -gt 0 ]; then
        if confirm "$(T ask_restore_anime4k "$SHADERS_DISABLED_DIR")" yes; then restore_pairs "${moved[@]}" || return 1; fi
    fi
    if [ "${#commented[@]}" -gt 0 ] && [ -f "$CFG/input.conf" ]; then
        load_file "$CFG/input.conf"
        find_commented input.conf anime4k_key_line "${commented[@]}" || return 1
        if [ "${#FOUND[@]}" -gt 0 ] && confirm "$(T ask_uncomment)" yes; then
            local n=${#FOUND[@]}
            uncomment_found
            save_file "$CFG/input.conf" || return 1
            info "$(T uncommented "$n")"
        fi
    fi
    if [ "${#commented_mpv[@]}" -gt 0 ] && [ -f "$CFG/mpv.conf" ]; then
        load_file "$CFG/mpv.conf"
        find_commented mpv.conf anime4k_conf_line "${commented_mpv[@]}" || return 1
        if [ "${#FOUND[@]}" -gt 0 ] && confirm "$(T ask_uncomment_conf)" yes; then
            local n=${#FOUND[@]}
            uncomment_found
            save_file "$CFG/mpv.conf" || return 1
            info "$(T uncommented_conf "$n")"
        fi
    fi

    local delete=0 name any=0
    for name in "${USER_CHOICE_FILES[@]}"; do [ -f "$CFG/$name" ] && any=1; done
    if [ "$any" = 1 ] && confirm "$(T ask_delete_choices)" no; then
        delete=1
        for name in "${USER_CHOICE_FILES[@]}"; do remove_item "$CFG/$name" "$CFG" || return 1; done
    fi
    if [ "$delete" = 1 ] && [ -f "$CFG/mpv.conf" ]; then
        for name in "${USER_CHOICE_FILES[@]}"; do
            if grep -qiE "^[[:space:]]*include[[:space:]]*=.*$name" "$CFG/mpv.conf"; then warn "$(T includes_outside "$name")"; fi
        done
    fi

    # Folders left empty (sosc may have created them) go too; shaders only when
    # the record says sosc created it.
    local d dirs
    dirs=(fonts script-opts scripts)
    [ "$(was_there shaders_preexisting)" = no ] && dirs[${#dirs[@]}]=$SHADERS_DIR
    for d in "${dirs[@]}"; do
        if [ -d "$CFG/$d" ] && [ ! -L "$CFG/$d" ] && [ -z "$(ls -A "$CFG/$d" 2>/dev/null)" ]; then rmdir "$CFG/$d" || return 1; fi
    done
    remove_item "$CFG/$ORIGINALS_DIR" "$CFG" || return 1
    remove_item "$CFG/$RECORD_NAME" "$CFG" || return 1
    for d in "$DISABLED_DIR" "$SHADERS_DISABLED_DIR"; do
        if [ -d "$CFG/$d" ] && [ ! -L "$CFG/$d" ] && [ -z "$(find "$CFG/$d" -type f -print 2>/dev/null | head -n 1)" ]; then
            remove_item "$CFG/$d" "$CFG" || return 1
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# Interactive flow
# ---------------------------------------------------------------------------

show_candidates() { # numbered list of the candidates in LIST
    local i=0 idx tags
    while [ "$i" -lt "${#LIST[@]}" ]; do
        idx=${LIST[i]}
        tags=$(candidate_tags "$idx")
        info " $((i + 1))) $(kind_label "${C_KIND[idx]}")  $tags"
        [ -z "${C_EXE[idx]}" ] || info "$(T cand_exe "${C_EXE[idx]}")"
        info "$(T cand_config "${C_DIR[idx]}")"
        i=$((i + 1))
    done
}

# Main menu: SEL = 1 install, 2 uninstall, 0 exit; fails at the end of the input.
main_choice() {
    if [ "$MENU" = 1 ]; then
        local labels l
        labels=()
        # "1) Install or update" -> "Install or update".
        while IFS= read -r l; do labels[${#labels[@]}]=${l:3}; done <<EOF
$(T menu)
EOF
        menu_reset
        menu_item "${labels[0]}" '' 0 0 '' 0 1
        menu_item "${labels[1]}" '' 0 0 '' 0 2
        menu_item "${labels[2]}" '' 0 0 '' 1 0
        if list_menu 0; then
            if [ "$M_CANCELLED" = 1 ]; then SEL=0; return 0; fi
            case $M_INDEX in 0) SEL=1 ;; 1) SEL=2 ;; *) SEL=0 ;; esac
            return 0
        fi
        MENU=0
    fi
    printf '%b\n' "$(T menu)"
    read_line "$(T menu_prompt)" || return 1
    trim "$REPLY_LINE"
    SEL=$TRIMMED
}

# Typed folder into PICKED_DIR; fails when the user gives up.
read_folder() {
    local p parent
    while :; do
        read_line "$(T ask_folder)" || return 1
        trim "$REPLY_LINE"
        p=$TRIMMED
        p=${p#\"}; p=${p%\"}; p=${p#\'}; p=${p%\'}
        case $p in '' | 0) return 1 ;; esac
        if ! p=$(abs_path "$p"); then warn "$(T path_bad "$REPLY_LINE")"; continue; fi
        parent=${p%/*}
        [ -n "$parent" ] || parent=/
        if [ -d "$p" ] || [ -d "$parent" ]; then PICKED_DIR=$p; return 0; fi
        warn "$(T folder_missing "$p")"
    done
}

# Index of the candidate for a folder (added as "folder" when it is not one).
candidate_for() {
    local dir i=0
    dir=$(abs_path "$1")
    while [ "$i" -lt "${#C_DIR[@]}" ]; do
        [ "${C_DIR[i]}" = "$dir" ] && { printf '%s' "$i"; return; }
        i=$((i + 1))
    done
    printf '%s' "$i"
}
add_folder_candidate() {
    local i
    i=$(candidate_for "$1")
    [ "$i" -lt "${#C_DIR[@]}" ] || add_candidate folder "$1" ''
    CHOSEN[${#CHOSEN[@]}]=$i
}

# Which folders: CHOSEN (candidate indexes). Fails for "exit".
choose_targets() {
    local mode=$1 i
    CHOSEN=()
    if [ "${#OPT_TARGETS[@]}" -gt 0 ]; then
        for i in "${OPT_TARGETS[@]}"; do
            if ! abs_path "$i" >/dev/null; then error "$(T path_bad "$i")"; REFUSED=1; continue; fi
            add_folder_candidate "$(abs_path "$i")"
        done
        return 0
    fi
    LIST=()
    i=0
    while [ "$i" -lt "${#C_DIR[@]}" ]; do
        if [ "$mode" = install ] || candidate_installed "$i"; then LIST[${#LIST[@]}]=$i; fi
        i=$((i + 1))
    done
    if [ "$NONINTERACTIVE" = 1 ]; then
        if [ "${#LIST[@]}" -eq 1 ]; then CHOSEN=("${LIST[0]}"); return 0; fi
        if [ "${#LIST[@]}" -eq 0 ]; then
            if [ "$mode" = uninstall ]; then error "$(T nothing_to_uninstall)"; else error "$(T usage_none)"; fi
            USAGE_ERROR=1
            return 1
        fi
        error "$(T usage_many)"
        show_candidates
        USAGE_ERROR=1
        return 1
    fi
    [ "${#LIST[@]}" -gt 0 ] || [ "$mode" != uninstall ] || warn "$(T nothing_to_uninstall)"
    if [ "$MENU" = 1 ]; then
        local header='' other idx tags label
        if [ "${#LIST[@]}" -gt 0 ]; then
            if [ "$mode" = uninstall ]; then header=$(T found_header_uninst); else header=$(T found_header); fi
        fi
        menu_reset
        for idx in ${LIST[@]+"${LIST[@]}"}; do
            label=$(kind_label "${C_KIND[idx]}")
            tags=$(candidate_tags "$idx")
            menu_item "$label${tags:+  $tags}" "${C_DIR[idx]}" 0 0 "$label ($(fit_middle "${C_DIR[idx]}" 40))"
        done
        other=${#M_LABEL[@]}
        local ol ql
        ol=$(T opt_other); ql=$(T opt_quit)
        menu_item "${ol:3}$GLYPH_ELLIPSIS" '' 1
        menu_item "${ql:3}" '' 1 0 '' 1
        if list_menu 1 ${header:+"$header"}; then
            [ "$M_CANCELLED" = 0 ] || return 1
            if [ "$M_INDEX" -ge 0 ] && [ "${M_QUIT[M_INDEX]}" = 1 ]; then return 1; fi
            for i in ${M_PICKED[@]+"${M_PICKED[@]}"}; do CHOSEN[${#CHOSEN[@]}]=${LIST[i]}; done
            if [ "$M_INDEX" = "$other" ] && read_folder; then add_folder_candidate "$PICKED_DIR"; fi
            return 0
        fi
        MENU=0
    fi
    local text part n bad quit other_pick picks
    while :; do
        if [ "${#LIST[@]}" -gt 0 ]; then
            if [ "$mode" = uninstall ]; then info "$(T found_header_uninst)"; else info "$(T found_header)"; fi
            show_candidates
        fi
        info " $(T opt_other)"
        info " $(T opt_quit)"
        read_line "$(T select_prompt)" || return 1
        text=$REPLY_LINE
        bad=0; quit=0; other_pick=0
        picks=()
        local IFS=$', ;\t'
        for part in $text; do
            case $(lower "$part") in
                0 | q | x) quit=1 ;;
                o) other_pick=1 ;;
                *[!0-9]* | '') bad=1 ;;
                *)
                    n=$((10#$part))
                    if [ "$n" -ge 1 ] && [ "$n" -le "${#LIST[@]}" ]; then picks[${#picks[@]}]=${LIST[n - 1]}; else bad=1; fi
                    ;;
            esac
        done
        IFS=$' \t\n'
        [ -n "$text" ] || bad=1
        if [ "$bad" = 1 ]; then warn "$(T invalid)"; continue; fi
        [ "$quit" = 0 ] || return 1
        CHOSEN=(${picks[@]+"${picks[@]}"})
        if [ "$other_pick" = 1 ] && read_folder; then add_folder_candidate "$PICKED_DIR"; fi
        return 0
    done
}

# Drops forbidden folders and, after asking, folders that do not look like
# mpv's; for install also folders that cannot be written. Sets TARGETS.
check_targets() {
    local mode=$1 i t dup
    TARGETS=()
    for i in ${CHOSEN[@]+"${CHOSEN[@]}"}; do
        dup=0
        for t in ${TARGETS[@]+"${TARGETS[@]}"}; do [ "$t" = "$i" ] && dup=1; done
        [ "$dup" = 0 ] || continue
        if forbidden_target "${C_DIR[i]}"; then error "$(T target_root "${C_DIR[i]}")"; REFUSED=1; continue; fi
        if ! looks_like_mpv_config "${C_DIR[i]}"; then
            warn "$(T not_mpv_folder "${C_DIR[i]}")"
            if [ "$NONINTERACTIVE" = 1 ]; then error "$(T not_mpv_yes)"; REFUSED=1; continue; fi
            if ! confirm "$(T not_mpv_confirm)" no; then warn "$(T readonly_skip "${C_DIR[i]}")"; continue; fi
        fi
        if [ "$mode" = install ] && ! dir_writable "${C_DIR[i]}"; then
            warn "$(T readonly_warn "${C_DIR[i]}")"
            warn "$(T readonly_skip "${C_DIR[i]}")"
            continue
        fi
        TARGETS[${#TARGETS[@]}]=$i
    done
}

# mpv missing: on macOS offer Homebrew, otherwise explain how to get it.
# Succeeds when mpv is there afterwards.
ensure_mpv() {
    MPV_EXE=$(sosc_find_mpv)
    if [ -n "$MPV_EXE" ]; then info "$(T mpv_found "$MPV_EXE")"; return 0; fi
    if [ "$OS" != Darwin ] && { sosc_flatpak_mpv || sosc_snap_mpv; }; then return 0; fi
    warn "$(T none_found)"
    if [ "$OS" = Darwin ]; then
        local brew code
        brew=$(sosc_brew)
        if [ -n "$brew" ] && [ "$NONINTERACTIVE" != 1 ] && confirm "$(T brew_offer)" yes; then
            "$brew" install mpv
            code=$?
            [ "$code" = 0 ] || warn "$(T brew_failed "$code")"
            MPV_EXE=$(sosc_find_mpv)
            if [ -n "$MPV_EXE" ]; then info "$(T mpv_found "$MPV_EXE")"; return 0; fi
        fi
        printf '%b\n' "$(T none_mac_help)"
    else
        printf '%b\n' "$(T none_linux_help)"
    fi
    return 1
}

sosc_cleanup() {
    [ -z "$STTY_SAVED" ] || menu_exit
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then rm -rf "$TEMP_DIR"; fi
    TEMP_DIR=''
}

usage() { T usage; printf '\n'; }

parse_args() {
    OPT_ACTION=''
    OPT_YES=0
    OPT_NO_MENU=0
    OPT_ANIME4K=''
    OPT_TARGETS=()
    while [ $# -gt 0 ]; do
        case $1 in
            --install) OPT_ACTION=install ;;
            --uninstall) OPT_ACTION=uninstall ;;
            --yes | -y) OPT_YES=1 ;;
            --no-menu) OPT_NO_MENU=1 ;;
            --anime4k)
                [ $# -ge 2 ] || { error "$(T bad_option "$1")"; return 2; }
                case $2 in yes | no) OPT_ANIME4K=$2 ;; *) error "$(T bad_option "$1 $2")"; return 2 ;; esac
                shift
                ;;
            --anime4k=*)
                case ${1#*=} in yes | no) OPT_ANIME4K=${1#*=} ;; *) error "$(T bad_option "$1")"; return 2 ;; esac
                ;;
            --target)
                if [ $# -lt 2 ] || [ -z "$2" ]; then error "$(T bad_option "$1")"; return 2; fi
                OPT_TARGETS[${#OPT_TARGETS[@]}]=$2
                shift
                ;;
            --target=*) OPT_TARGETS[${#OPT_TARGETS[@]}]=${1#*=} ;;
            -h | --help) usage; return 1 ;;
            *) error "$(T bad_option "$1")"; return 2 ;;
        esac
        shift
    done
    return 0
}

main() {
    # Unset variables are errors; every other failure is checked where it
    # happens (no set -e: its rules in functions and conditions are a trap).
    set -u
    sosc_defaults
    STTY_SAVED=''
    SOSC_LANG_CODE=$(sosc_language)
    COLOR=0
    if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then COLOR=1; fi
    SCRIPT_FILE=${BASH_SOURCE[0]:-}
    SOSC_ERR=''
    TEMP_DIR=''
    REFUSED=0
    USAGE_ERROR=0
    MPV_EXE=''
    local rc
    parse_args "$@"
    rc=$?
    case $rc in 0) ;; 1) return 0 ;; *) usage >&2; return 2 ;; esac

    trap 'sosc_cleanup' EXIT
    trap 'sosc_cleanup; trap - EXIT; exit 130' INT
    trap 'sosc_cleanup; trap - EXIT; exit 143' TERM

    OS=$(sosc_uname)
    case $OS in Darwin | Linux) ;; *) error "$(T unsupported_os "$OS")"; return 2 ;; esac
    local tool
    for tool in curl unzip; do
        command -v "$tool" >/dev/null 2>&1 || { error "$(T missing_tool "$tool")"; return 2; }
    done

    io_setup
    NONINTERACTIVE=0
    if [ "$OPT_YES" = 1 ] || [ "$HAVE_INPUT" != 1 ]; then NONINTERACTIVE=1; fi

    info "$(T title)"
    [ "$HAVE_INPUT" = 1 ] || [ "$OPT_YES" = 1 ] || warn "$(T no_input)"
    local action=$OPT_ACTION
    if [ -z "$action" ]; then
        if [ "$NONINTERACTIVE" = 1 ]; then
            action=install
        else
            while [ -z "$action" ]; do
                main_choice || return 0
                case $SEL in
                    1) action=install ;;
                    2) action=uninstall ;;
                    0) info "$(T cancelled)"; return 0 ;;
                    *) warn "$(T invalid)" ;;
                esac
            done
        fi
    fi

    if [ "$(id -u)" = 0 ]; then
        warn "$(T root_warn)"
        if [ "$NONINTERACTIVE" = 1 ]; then error "$(T root_refused)"; return 2; fi
        confirm "$(T root_confirm)" no || { info "$(T cancelled)"; return 0; }
    fi

    info "$(T detecting)"
    if [ "$action" = install ]; then
        ensure_mpv || return 2
        if [ "$OS" = Darwin ] && sosc_iina; then info "$(T iina_note)"; fi
    else
        MPV_EXE=$(sosc_find_mpv)
    fi
    [ -z "${MPV_HOME:-}" ] || info "$(T mpv_home_note "$MPV_HOME")"
    find_candidates
    choose_targets "$action"
    rc=$?
    if [ "$rc" != 0 ]; then
        [ "$USAGE_ERROR" = 1 ] && return 2
        info "$(T cancelled)"
        return 0
    fi
    check_targets "$action"
    if [ "$REFUSED" = 1 ] && [ "$NONINTERACTIVE" = 1 ]; then return 2; fi
    if [ "${#TARGETS[@]}" -eq 0 ]; then
        if [ "$NONINTERACTIVE" = 1 ]; then error "$(T usage_none)"; return 2; fi
        info "$(T cancelled)"
        return 0
    fi

    STAMP=$(date +%Y%m%d-%H%M%S)
    local done_count=0 t
    if [ "$action" = install ]; then
        TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sosc-install.XXXXXX") || { error "$(T error_generic mktemp)"; return 1; }
        if ! get_source || ! get_artifacts; then
            error "$(T error_generic "$SOSC_ERR")"
            return 1
        fi
        A4K_SRC=''
        A4K_ERROR=''
        [ "$OPT_ANIME4K" = no ] || get_anime4k || :
    fi
    for t in "${TARGETS[@]}"; do
        SOSC_ERR=''
        if [ "$action" = install ]; then
            if install_target "$t"; then done_count=$((done_count + 1)); else error "$(T target_failed "${C_DIR[t]}" "$SOSC_ERR")"; fi
        else
            if uninstall_target "$t"; then done_count=$((done_count + 1)); else error "$(T target_failed "${C_DIR[t]}" "$SOSC_ERR")"; fi
        fi
    done
    sosc_cleanup
    info ''
    info "$(T summary "$done_count" "${#TARGETS[@]}")"
    [ "$done_count" -eq 0 ] || info "$(T restart)"
    [ "$done_count" -eq "${#TARGETS[@]}" ] || return 1
    return 0
}

main "$@"
