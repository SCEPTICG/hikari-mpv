#!/usr/bin/env bash
# Tests for install/hikari.sh (macOS and Linux installer). Run from anywhere:
#   bash tests/install.test.sh
#   ~/.local/opt/bash-3.2/bin/bash tests/install.test.sh
# The installer runs with the same bash as this file (or $HIKARI_TEST_BASH), so
# running it with bash 3.2 checks the installer under the bash of macOS.
#
# Nothing is downloaded and no real config is touched: every run gets a fake
# HOME in a temporary folder, and a test copy of hikari.sh whose uosc, thumbfast
# and Anime4K hashes are swapped for the ones of fake files, with a few
# functions replaced (downloads, uname, the chip, lspci, where mpv is, the
# terminal). Everything else is the installer as shipped.
# Exit code 0 when everything passes. Needs python3 (to build the fake zips
# and to drive the keyboard menus through a pseudo-terminal).
# shellcheck shell=bash
# Single quotes around $ on purpose (code for another shell), variables set in
# subshells on purpose (each run gets its own environment), ls on folders the
# tests made themselves:
# shellcheck disable=SC2016,SC2030,SC2031,SC2012,SC2059
set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
under=${HIKARI_TEST_BASH:-$BASH}

passed=0
failed=0
ok() { passed=$((passed + 1)); printf 'ok   %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; }
check() { # check <name> <command...>
    local name="$1"
    shift
    if "$@"; then ok "$name"; else fail "$name"; fi
}
same() { cmp -s "$1" "$2"; }
has() { grep -qF -- "$2" "$1"; }
hasnt() { ! grep -qF -- "$2" "$1"; }
count_of() { grep -cF -- "$2" "$1"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/hikari-sh-tests.XXXXXX")"
[ -n "${HIKARI_TEST_KEEP:-}" ] || trap 'rm -rf "$tmp"' EXIT
fake="$tmp/fake"
mkdir -p "$fake" "$tmp/tmpdir"

printf 'installer runs with: %s\n' "$("$under" -c 'echo "$BASH_VERSION"')"

# --- fake downloads ------------------------------------------------------------

# 39 shader names, like the real Anime4K v4.0.1 zip (every one hikari needs among them).
A4K_NAMES="Anime4K_3DGraphics_AA_Upscale_x2_US.glsl Anime4K_3DGraphics_Upscale_x2_US.glsl Anime4K_AutoDownscalePre_x2.glsl
Anime4K_AutoDownscalePre_x4.glsl Anime4K_Clamp_Highlights.glsl Anime4K_Darken_Fast.glsl Anime4K_Darken_HQ.glsl
Anime4K_Darken_VeryFast.glsl Anime4K_Deblur_DoG.glsl Anime4K_Deblur_Original.glsl Anime4K_Denoise_Bilateral_Mean.glsl
Anime4K_Denoise_Bilateral_Median.glsl Anime4K_Denoise_Bilateral_Mode.glsl Anime4K_Restore_CNN_L.glsl Anime4K_Restore_CNN_M.glsl
Anime4K_Restore_CNN_S.glsl Anime4K_Restore_CNN_Soft_L.glsl Anime4K_Restore_CNN_Soft_M.glsl Anime4K_Restore_CNN_Soft_S.glsl
Anime4K_Restore_CNN_Soft_UL.glsl Anime4K_Restore_CNN_Soft_VL.glsl Anime4K_Restore_CNN_UL.glsl Anime4K_Restore_CNN_VL.glsl
Anime4K_Thin_Fast.glsl Anime4K_Thin_HQ.glsl Anime4K_Thin_VeryFast.glsl Anime4K_Upscale_CNN_x2_L.glsl Anime4K_Upscale_CNN_x2_M.glsl
Anime4K_Upscale_CNN_x2_S.glsl Anime4K_Upscale_CNN_x2_UL.glsl Anime4K_Upscale_CNN_x2_VL.glsl Anime4K_Upscale_DoG_x2.glsl
Anime4K_Upscale_DTD_x2.glsl Anime4K_Upscale_Deblur_DoG_x2.glsl Anime4K_Upscale_Deblur_Original_x2.glsl
Anime4K_Upscale_Denoise_CNN_x2_L.glsl Anime4K_Upscale_Denoise_CNN_x2_M.glsl Anime4K_Upscale_Denoise_CNN_x2_UL.glsl
Anime4K_Upscale_Denoise_CNN_x2_VL.glsl"

# make_zip <zip> <name=content>...
make_zip() {
    python3 -I - "$@" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], 'w')
for item in sys.argv[2:]:
    name, _, content = item.partition('=')
    z.writestr(name, content)
z.close()
PY
}

# shellcheck disable=SC2086 # the names are split on purpose.
set -- $A4K_NAMES
a4k_args=()
for n in "$@"; do a4k_args[${#a4k_args[@]}]="$n=// fake $n"; done
make_zip "$fake/anime4k.zip" "${a4k_args[@]}" 'readme.txt=not a shader' '../Anime4K_Evil.glsl=// outside'
make_zip "$fake/uosc.zip" 'scripts/uosc/main.lua=-- fake uosc 5.13.0' 'scripts/uosc/lib/x.lua=-- lib' \
    'fonts/uosc_icons.otf=icons 5.13' 'fonts/uosc_textures.ttf=textures 5.13' 'script-opts/uosc.conf=# uosc default conf'
printf '%s\n' '-- fake thumbfast' >"$fake/thumbfast.lua"
a4k_count=$(printf '%s\n' "$A4K_NAMES" | tr ' ' '\n' | grep -c .)
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# The test copy: fake hashes, and the overrides loaded just before main runs.
# It sits in a copy of the repository layout, so it installs the hikari files of
# this work tree (portable_config/ next to install/), as the real one does.
mkdir -p "$tmp/repo/install"
cp -R "$repo/portable_config" "$tmp/repo/portable_config"
ln -s "$repo/.git" "$tmp/repo/.git"
copy="$tmp/repo/install/hikari.sh"
sed -e "s/^\(    UOSC_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sha "$fake/uosc.zip")'/" \
    -e "s/^\(    THUMBFAST_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sha "$fake/thumbfast.lua")'/" \
    -e "s/^\(    ANIME4K_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sha "$fake/anime4k.zip")'/" \
    -e '$d' "$repo/install/hikari.sh" >"$copy"
printf '. "$HIKARI_TEST_OVERRIDES"\n' >>"$copy"
tail -n 1 "$repo/install/hikari.sh" >>"$copy"
cat >"$tmp/overrides.sh" <<'EOF'
# Replaces what would reach outside the test: downloads, the system, the terminal.
hikari_fetch() {
    local f=''
    printf '%s\n' "$1" >>"$FAKE/downloads.log"
    case $1 in
        "$UOSC_URL") f=$FAKE/uosc.zip ;;
        "$THUMBFAST_URL") f=$FAKE/thumbfast.lua ;;
        "$ANIME4K_URL") f=$FAKE/anime4k.zip ;;
    esac
    [ -z "${HIKARI_TEST_FAIL_URL:-}" ] || [ "$1" != "$HIKARI_TEST_FAIL_URL" ] || return 22
    [ -n "$f" ] && [ -f "$f" ] && cp "$f" "$2"
}
hikari_uname() { printf '%s' "${HIKARI_TEST_OS:-Darwin}"; }
hikari_apple_languages() { [ -z "${HIKARI_TEST_APPLE_LANGS:-}" ] || printf '%b\n' "$HIKARI_TEST_APPLE_LANGS"; }
hikari_cpu_brand() { printf '%s' "${HIKARI_TEST_CHIP-Apple M5}"; }
hikari_lspci() { [ -z "${HIKARI_TEST_LSPCI:-}" ] || printf '%b\n' "$HIKARI_TEST_LSPCI"; }
hikari_find_mpv() {
    if [ -f "$FAKE/mpv-path" ]; then cat "$FAKE/mpv-path"; return; fi
    printf '%s' "${HIKARI_TEST_MPV-/opt/homebrew/bin/mpv}"
}
hikari_brew() { printf '%s' "${HIKARI_TEST_BREW:-}"; }
hikari_iina() { [ -n "${HIKARI_TEST_IINA:-}" ]; }
hikari_flatpak_mpv() { [ -n "${HIKARI_TEST_FLATPAK:-}" ]; }
hikari_snap_mpv() { [ -n "${HIKARI_TEST_SNAP:-}" ]; }
if [ -n "${HIKARI_TEST_TTY+x}" ]; then hikari_tty_path() { printf '%s' "$HIKARI_TEST_TTY"; }; fi
EOF

# run <home> <args...>: runs the test copy, output in $out, exit code in $rc.
# Settings come from HIKARI_TEST_* variables set (or not) by the caller.
out="$tmp/out.txt"
run() {
    local home=$1
    shift
    (
        export HOME="$home" HIKARI_LANG="${HIKARI_LANG-en}" TMPDIR="$tmp/tmpdir" FAKE="$fake" HIKARI_TEST_OVERRIDES="$tmp/overrides.sh"
        export HIKARI_TEST_TTY="${HIKARI_TEST_TTY-}"
        unset MPV_HOME XDG_CONFIG_HOME LC_ALL LC_MESSAGES
        [ -z "${T_MPV_HOME:-}" ] || export MPV_HOME="$T_MPV_HOME"
        "$under" "$copy" "$@" </dev/null
    ) >"$out" 2>&1
    rc=$?
    shell_errors
}
# Any shell error in any run (an unset variable under set -u, a bad
# subscript...) is a failure, even when the checks after it pass.
shell_errors() {
    grep -E 'unbound variable|command not found|syntax error|bad (array )?subscript|integer expression expected|too many arguments' "$out" >>"$tmp/shell-errors.log"
}
answers() { printf "$1" >"$tmp/answers.txt"; HIKARI_TEST_TTY="$tmp/answers.txt"; }
no_answers() { unset HIKARI_TEST_TTY; }
newhome() { local h="$tmp/home-$1"; mkdir -p "$h"; printf '%s' "$h"; }
show_out() { sed 's/^/     | /' "$out"; }
rec() { grep "^$2=" "$1/hikari-installed.txt" | head -n 1 | cut -d= -f2-; }
shader_list() { (cd "$1" 2>/dev/null && ls | sort | tr '\n' ' '); }

# --- pinned downloads: the same as install/hikari.ps1 ----------------------------

ps1_value() { sed -n "s/^\$script:$1 = '\(.*\)'\$/\1/p" "$repo/install/hikari.ps1"; }
sh_value() { sed -n "s/^    $1='\(.*\)'\$/\1/p" "$repo/install/hikari.sh"; }
same_pins=true
for pair in UoscVersion:UOSC_VERSION UoscUrl:UOSC_URL UoscSha256:UOSC_SHA256 ThumbfastCommit:THUMBFAST_COMMIT \
    ThumbfastUrl:THUMBFAST_URL ThumbfastSha256:THUMBFAST_SHA256 Anime4KVersion:ANIME4K_VERSION Anime4KUrl:ANIME4K_URL \
    Anime4KSha256:ANIME4K_SHA256; do
    a=$(ps1_value "${pair%%:*}")
    b=$(sh_value "${pair#*:}")
    if [ -z "$a" ] || [ "$a" != "$b" ]; then same_pins=false; echo "     differs: $pair ($a / $b)"; fi
done
check 'uosc, thumbfast and Anime4K: same versions, URLs and SHA256 as hikari.ps1' $same_pins
# The files that show a folder is mpv's: the same list in both installers.
ps1_cfg=$(sed -n "s/^\$script:MpvConfigFiles = @(\(.*\))\$/\1/p" "$repo/install/hikari.ps1" | tr -d "', ")
sh_cfg=$(sed -n "s/^    MPV_CONFIG_FILES=(\(.*\))\$/\1/p" "$repo/install/hikari.sh" | tr -d "' ")
check 'signs of an mpv folder: the same files as hikari.ps1, hikari-language.conf included' \
    test -n "$sh_cfg" -a "$sh_cfg" = "$ps1_cfg" -a -z "${sh_cfg##*hikari-language.conf*}"
check 'release markers are empty in the repository' test "$(sh_value HIKARI_VERSION)|$(sh_value HIKARI_RELEASE_URL)|$(sh_value HIKARI_RELEASE_SHA256)" = 'dev||'
check 'the last line calls main, in braces' test "$(tail -n 1 "$repo/install/hikari.sh")" = '{ main "$@"; }'
# Without its last line the script only defines functions: no output, no
# variable set, nothing touched (what a download cut short would run).
mkdir -p "$tmp/cut-home"
sed '$d' "$repo/install/hikari.sh" >"$tmp/cut.sh"
cut_out=$(cd "$tmp/cut-home" && HOME="$tmp/cut-home" "$under" -c '
    vars() { set | grep -E "^[A-Za-z][A-Za-z0-9_]*=" | grep -vE "^(BASH_[A-Z]+|PIPESTATUS|_|before|after)="; }
    before=$(vars); . "$1"; after=$(vars)
    [ "$before" = "$after" ] || echo "variables set"
    declare -F main >/dev/null || echo "no main"' _ "$tmp/cut.sh" 2>&1)
check 'without the last line nothing runs (only functions are defined)' test -z "$cut_out" -a -z "$(ls -A "$tmp/cut-home")"

# --- usage ----------------------------------------------------------------------

h=$(newhome usage)
run "$h" --help
check '--help exits 0 and shows the options' test "$rc" = 0 -a -n "$(grep -- '--uninstall' "$out")"
run "$h" --frobnicate
check 'unknown option exits 2' test "$rc" = 2
run "$h" --anime4k maybe
check '--anime4k needs yes or no' test "$rc" = 2
HIKARI_TEST_OS=FreeBSD run "$h" --yes
check 'other systems are refused (exit 2)' test "$rc" = 2 -a -n "$(grep 'macOS and Linux' "$out")"
check 'nothing written in HOME by the refusals' test -z "$(ls -A "$h")"

# --- clean install -------------------------------------------------------------

h=$(newhome clean)
cfg="$h/.config/mpv"
: >"$fake/downloads.log"
no_answers
run "$h" --yes
if [ "$rc" = 0 ]; then ok 'clean install: exit 0'; else fail "clean install: exit $rc"; show_out; fi
check 'clean install: says there is no terminal? no: --yes is quiet about it' hasnt "$out" 'No terminal'
all_same=true
for f in "$repo"/portable_config/scripts/*.lua "$repo"/portable_config/script-opts/hikari-*.conf \
    "$repo"/portable_config/script-modules/*.lua \
    "$repo"/portable_config/hikari-palette.conf "$repo"/portable_config/hikari-subs.conf; do
    rel="${f#"$repo"/portable_config/}"
    same "$f" "$cfg/$rel" || { all_same=false; echo "     differs: $rel"; }
done
check 'clean install: hikari files are the repository ones' $all_same
check 'clean install: the update check and its options' test -f "$cfg/scripts/hikari-update.lua" -a -f "$cfg/script-opts/hikari-update.conf"
check 'clean install: the update check state is not created by the installer' test ! -e "$cfg/hikari-update.txt"
check 'clean install: uosc.conf is hikari'"'"'s' same "$repo/portable_config/script-opts/uosc.conf" "$cfg/script-opts/uosc.conf"
check 'clean install: uosc and its fonts' test -f "$cfg/scripts/uosc/main.lua" -a -f "$cfg/scripts/uosc/lib/x.lua" -a -f "$cfg/fonts/uosc_icons.otf" -a -f "$cfg/fonts/uosc_textures.ttf"
check 'clean install: uosc'"'"'s own uosc.conf not used' hasnt "$cfg/script-opts/uosc.conf" '# uosc default conf'
check 'clean install: thumbfast' same "$fake/thumbfast.lua" "$cfg/scripts/thumbfast.lua"
check 'clean install: thumbfast.conf has mpv_path of the mpv found' test "$(grep -c '^mpv_path=/opt/homebrew/bin/mpv$' "$cfg/script-opts/thumbfast.conf")" = 1
cat >"$tmp/want-mpv.conf" <<'EOF'
# >>> hikari (managed block, do not edit) >>>
osc=no
osd-bar=no
include="~~/hikari-palette.conf"
include="~~/hikari-subs.conf"
include="~~/hikari-upscale.conf"
include="~~/hikari-language.conf"
# <<< hikari <<<
EOF
check 'clean install: mpv.conf is exactly the block' same "$tmp/want-mpv.conf" "$cfg/mpv.conf"
cat >"$tmp/want-input.conf" <<'EOF'
# >>> hikari (managed block, do not edit) >>>
Alt+p  script-binding hikari_palettes/open-menu
Alt+s  script-binding hikari_skip/skip
Alt+t  script-binding hikari_subs/open-menu
Alt+u  script-binding hikari_update/open-menu
Alt+l  script-binding hikari_language/open-menu
Ctrl+1  script-message-to hikari_upscale set-mode a
Ctrl+2  script-message-to hikari_upscale set-mode b
Ctrl+3  script-message-to hikari_upscale set-mode c
Ctrl+4  script-message-to hikari_upscale set-mode aa
Ctrl+5  script-message-to hikari_upscale set-mode bb
Ctrl+6  script-message-to hikari_upscale set-mode ca
Ctrl+7  script-message-to hikari_upscale set-mode auto
Ctrl+0  script-message-to hikari_upscale set-mode off
# <<< hikari <<<
EOF
check 'clean install: input.conf is exactly the block, with Ctrl+7' same "$tmp/want-input.conf" "$cfg/input.conf"
check 'clean install: the repository input.conf has the same bindings' bash -c "grep -v '^#' '$tmp/want-input.conf' | while IFS= read -r l; do grep -qxF \"\$l\" '$repo/portable_config/input.conf' || exit 1; done"
count_glob() { local n=0 f; for f in "$@"; do [ -e "$f" ] && n=$((n + 1)); done; printf '%s' "$n"; }
check "clean install: the $a4k_count Anime4K shaders" test "$(count_glob "$cfg"/shaders/Anime4K_*.glsl)" = "$a4k_count"
check 'clean install: nothing but Anime4K_*.glsl taken from the zip' test ! -e "$cfg/shaders/readme.txt" -a ! -e "$h/.config/Anime4K_Evil.glsl" -a ! -e "$cfg/Anime4K_Evil.glsl"
printf '# Generated by hikari-upscale.lua. Mode: auto, quality: fast\nscript-opts-append=hikari_upscale-mode=auto\nscript-opts-append=hikari_upscale-quality=fast\n' >"$tmp/want-auto-fast"
check 'clean install: hikari-upscale.conf in Automático, quality fast (Apple M5)' same "$tmp/want-auto-fast" "$cfg/hikari-upscale.conf"
check 'clean install: the card is named' has "$out" 'Graphics card: Apple M5 → quality Fast'
check 'clean install: record' test "$(rec "$cfg" anime4k)/$(rec "$cfg" anime4k_version)/$(rec "$cfg" hikari_version)/$(rec "$cfg" player_exe)" = "hikari/4.0.1/dev//opt/homebrew/bin/mpv"
check 'clean install: record says nothing was there' test "$(rec "$cfg" mpv_conf_preexisting)$(rec "$cfg" uosc_preexisting)$(rec "$cfg" shaders_preexisting)" = nonono
check 'clean install: record lists the files' test "$(grep -c '^file=shaders/Anime4K_' "$cfg/hikari-installed.txt")" = "$a4k_count"
check 'clean install: hikari commit recorded (repository copy)' test -n "$(rec "$cfg" hikari_commit)"
check 'clean install: no backup of a folder that did not exist' test -z "$(ls -d "$h"/.config/mpv-respaldo-hikari-* 2>/dev/null)"
check 'clean install: downloads verified, once each' test "$(sort "$fake/downloads.log" | uniq -d | wc -l | tr -d ' ')/$(wc -l <"$fake/downloads.log" | tr -d ' ')" = 0/3
check 'clean install: temporary folder removed' test -z "$(ls -A "$tmp/tmpdir")"
check 'clean install: no temporary files left in the folder' test -z "$(find "$cfg" -name '*.hikari-tmp.*')"
perm() { ls -l "$1" | cut -c1-10; }
check 'clean install: a new mpv.conf gets the permissions of the umask (not the 600 of mktemp)' \
    test "$(perm "$cfg/mpv.conf")" = "$(f="$tmp/perm-probe"; : >"$f"; perm "$f")"

# --- update: choices respected ------------------------------------------------

printf '# Generated by hikari-upscale.lua. Mode: b, quality: hq\nglsl-shaders-clr\n' >"$cfg/hikari-upscale.conf"
printf 'mine\n' >"$cfg/hikari-palette.conf"
printf 'last_check=1800000000\nlatest=9.9.9\ndismissed=9.9.9\n' >"$cfg/hikari-update.txt"
cp "$cfg/hikari-update.txt" "$tmp/update-state-before"
cp "$cfg/input.conf" "$tmp/input-before-update"
: >"$fake/downloads.log"
run "$h" --yes
check 'update: exit 0' test "$rc" = 0
check 'update: upscale mode kept' test "$(head -n 1 "$cfg/hikari-upscale.conf")" = '# Generated by hikari-upscale.lua. Mode: b, quality: hq'
check 'update: palette kept' test "$(cat "$cfg/hikari-palette.conf")" = mine
check 'update: update check state kept as it was' same "$tmp/update-state-before" "$cfg/hikari-update.txt"
check 'update: Anime4K up to date, not copied again' has "$out" 'Anime4K 4.0.1 is already installed'
check 'update: blocks not repeated' same "$tmp/input-before-update" "$cfg/input.conf"
check 'update: mpv.conf block still once' test "$(count_of "$cfg/mpv.conf" '# >>> hikari')" = 1
check 'update: a backup of the folder now' test -n "$(ls -d "$h"/.config/mpv-respaldo-hikari-* 2>/dev/null)"
check 'update: that backup is the original one (no record before? no: there was one, so no mark)' test -z "$(ls "$h"/.config/mpv-respaldo-hikari-*/hikari-backup-original.txt 2>/dev/null)"
run "$h" --yes --anime4k no
check 'update with --anime4k no: Anime4K left as it is' test "$rc/$(rec "$cfg" anime4k)" = 0/hikari
check 'update with --anime4k no: keys kept' same "$tmp/input-before-update" "$cfg/input.conf"
# A required shader missing: installed again.
rm -f "$cfg/shaders/Anime4K_Restore_CNN_S.glsl"
run "$h" --yes
check 'update: a missing shader is put back' test -f "$cfg/shaders/Anime4K_Restore_CNN_S.glsl"
check 'update: user upscale choice still kept' test "$(head -n 1 "$cfg/hikari-upscale.conf")" = '# Generated by hikari-upscale.lua. Mode: b, quality: hq'

# --- uninstall: byte for byte -------------------------------------------------

h=$(newhome bytes)
cfg="$h/.config/mpv"
mkdir -p "$cfg/script-opts"
printf 'volume=50\r\nalang=ja\r\n# no final line break\r\nsub-auto=fuzzy' >"$cfg/mpv.conf"
printf 'Alt+p cycle pause\nq quit\n' >"$cfg/input.conf"
chmod 640 "$cfg/input.conf"
printf 'timeline_style=line\n' >"$cfg/script-opts/uosc.conf"
cp "$cfg/mpv.conf" "$tmp/b-mpv"; cp "$cfg/input.conf" "$tmp/b-input"; cp "$cfg/script-opts/uosc.conf" "$tmp/b-uosc"
run "$h" --yes
check 'byte test: install exit 0' test "$rc" = 0
check 'byte test: CRLF kept for the block' test "$(grep -c $'\r$' "$cfg/mpv.conf")" = 12
check 'byte test: Alt+p of the user left alone and reported' test "$(count_of "$cfg/input.conf" 'Alt+p')" = 1 -a -n "$(grep 'Alt+p is already bound' "$out")"
check 'byte test: original uosc.conf kept aside' same "$tmp/b-uosc" "$cfg/hikari-originales/script-opts/uosc.conf"
check 'byte test: the first backup is marked as the original' test -f "$(rec "$cfg" first_backup)/hikari-backup-original.txt"
check 'byte test: the backup has the files as they were' same "$tmp/b-mpv" "$(rec "$cfg" first_backup)/mpv.conf"
run "$h" --uninstall --yes
check 'byte test: uninstall exit 0' test "$rc" = 0
check 'byte test: mpv.conf byte for byte (CRLF, no final line break)' same "$tmp/b-mpv" "$cfg/mpv.conf"
check 'byte test: input.conf byte for byte' same "$tmp/b-input" "$cfg/input.conf"
check 'byte test: uosc.conf byte for byte' same "$tmp/b-uosc" "$cfg/script-opts/uosc.conf"
check 'byte test: input.conf keeps its permissions (640)' test "$(perm "$cfg/input.conf")" = '-rw-r-----'
check 'byte test: hikari, uosc, thumbfast and Anime4K gone' test ! -e "$cfg/scripts" -a ! -e "$cfg/shaders" -a ! -e "$cfg/fonts" -a ! -e "$cfg/script-opts/thumbfast.conf"
check 'byte test: record and hikari-originales gone' test ! -e "$cfg/hikari-installed.txt" -a ! -e "$cfg/hikari-originales"
check 'byte test: saved choices kept by default' test -f "$cfg/hikari-palette.conf" -a -f "$cfg/hikari-upscale.conf"
check 'byte test: the original backup is still there' test -n "$(ls "$h"/.config/mpv-respaldo-hikari-*/hikari-backup-original.txt 2>/dev/null)"

# A folder hikari created on its own: removed files, nothing left but the choices.
h=$(newhome created)
cfg="$h/.config/mpv"
run "$h" --yes
printf 'last_check=1800000000\n' >"$cfg/hikari-update.txt"
printf 'x' >"$cfg/hikari-update.txt.tmp"
run "$h" --uninstall --yes
check 'created by hikari: update check state removed (no question)' test ! -e "$cfg/hikari-update.txt" -a ! -e "$cfg/hikari-update.txt.tmp" -a ! -e "$cfg/scripts/hikari-update.lua"
check 'created by hikari: mpv.conf and input.conf removed' test ! -e "$cfg/mpv.conf" -a ! -e "$cfg/input.conf"

# --- mpv.conf that ends inside a profile ------------------------------------

h=$(newhome profile)
cfg="$h/.config/mpv"
mkdir -p "$cfg"
printf 'hwdec=auto\n\n[anime]\nprofile-cond=get("height", 0) <= 576\ndeband=yes\n' >"$cfg/mpv.conf"
cp "$cfg/mpv.conf" "$tmp/p-mpv"
run "$h" --yes --anime4k no
check 'profile: the block starts with [default]' test "$(sed -n '/^# >>> hikari/{n;p;}' "$cfg/mpv.conf")" = '[default]'
check 'profile: said so' has "$out" 'ends inside a [profile]'
check 'profile: the user lines are untouched' test "$(head -n 5 "$cfg/mpv.conf" | cksum)" = "$(cksum <"$tmp/p-mpv")"
run "$h" --yes --anime4k no
check 'profile: update keeps one [default]' test "$(count_of "$cfg/mpv.conf" '[default]')" = 1
run "$h" --uninstall --yes
check 'profile: given back' same "$tmp/p-mpv" "$cfg/mpv.conf"
h=$(newhome profile-default)
cfg="$h/.config/mpv"
mkdir -p "$cfg"
printf '[anime]\ndeband=yes\n[default]\nvolume=50\n' >"$cfg/mpv.conf"
run "$h" --yes --anime4k no
check 'profile: already back in [default]: no extra header' test "$(count_of "$cfg/mpv.conf" '[default]')" = 1

# --- the Mac of SCEPTICG ----------------------------------------------------

# make_mac <cfg>: the real config of the Mac (mpv 0.41.0 of Homebrew).
make_mac() {
    local c=$1 n
    mkdir -p "$c/fonts" "$c/script-opts" "$c/scripts/uosc/elements" "$c/shaders" "$c/watch_later"
    printf 'icons 2023' >"$c/fonts/uosc_icons.otf"
    printf 'textures 2023' >"$c/fonts/uosc_textures.ttf"
    printf 'timeline_style=line\nautohide=no\n' >"$c/script-opts/uosc.conf"
    printf -- '-- old uosc\n' >"$c/scripts/uosc/main.lua"
    printf -- '-- old element\n' >"$c/scripts/uosc/elements/Timeline.lua"
    printf '404: Not Found' >"$c/scripts/aniskip.lua"
    for n in $A4K_NAMES; do printf '// mine %s\n' "$n" >"$c/shaders/$n"; done
    printf 'start=123\n' >"$c/watch_later/ABCDEF"
    printf 'icns' >"$c/mpv.icns"
    cat >"$c/mpv.conf" <<'EOF'
profile=high-quality
hwdec=videotoolbox
deband=yes
alang=es,spa,es-ES,es-419,ja,jpn
slang=es,spa,es-ES,es-419
osc=no
osd-bar=no
cursor-autohide=1000
osd-font="Helvetica Neue"
keep-open=yes
save-position-on-quit=yes
native-fs=yes
target-trc=gamma2.2

# ── Anime4K por resolución ──────────────────────────
[anime4k-480]
profile-desc=Anime4K modo C (480p/576p)
profile-cond=get("height", 0) > 0 and get("height", 0) <= 576
profile-restore=copy
glsl-shaders="~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Upscale_Denoise_CNN_x2_M.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"

# ──
[anime4k-720]
profile-desc=Anime4K modo B (720p)
profile-cond=get("height", 0) > 576 and get("height", 0) <= 810
profile-restore=copy
glsl-shaders="~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_Soft_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"

# ──
[anime4k-1080]
profile-desc=Anime4K modo A+A (1080p)
profile-cond=get("height", 0) > 810 and get("height", 0) <= 1100
profile-restore=copy
glsl-shaders="~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl:~~/shaders/Anime4K_Restore_CNN_S.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"
EOF
    cat >"$c/input.conf" <<'EOF'
CTRL+1 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: Mode A (Fast)"
CTRL+2 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_Soft_M.glsl"; show-text "Anime4K: Mode B (Fast)"
CTRL+3 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Upscale_Denoise_CNN_x2_M.glsl"; show-text "Anime4K: Mode C (Fast)"
CTRL+4 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Restore_CNN_S.glsl"; show-text "Anime4K: Mode A+A (Fast)"
CTRL+5 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Restore_CNN_Soft_S.glsl"; show-text "Anime4K: Mode B+B (Fast)"
CTRL+6 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Restore_CNN_S.glsl"; show-text "Anime4K: Mode C+A (Fast)"
CTRL+0 no-osd change-list glsl-shaders clr ""; show-text "Anime4K desactivado"
CTRL+t cycle-values target-trc auto gamma2.2 srgb gamma2.0; show-text "Curva: ${target-trc}"
WHEEL_UP    add volume -2
WHEEL_DOWN  add volume 2
WHEEL_LEFT  seek 10
WHEEL_RIGHT seek -10
EOF
}

# snapshot <cfg> <dir>: the files whose way back must be exact.
snapshot() {
    mkdir -p "$2/shaders"
    cp "$1/mpv.conf" "$1/input.conf" "$1/script-opts/uosc.conf" "$1/scripts/aniskip.lua" "$2/"
    cp "$1"/shaders/* "$2/shaders/"
}

# check_mac_installed <label>: the expected result of taking over the Mac config.
check_mac_installed() {
    local l=$1 c=$cfg
    check "$l: aniskip.lua (404) set aside, not deleted" test ! -e "$c/scripts/aniskip.lua" -a "$(cat "$c/scripts-desactivados/aniskip.lua")" = '404: Not Found'
    check "$l: broken script recorded" test "$(rec "$c" broken)" = 'scripts-desactivados/aniskip.lua|scripts/aniskip.lua'
    check "$l: uosc replaced by 5.13.0, old one in the backup" test "$(cat "$c/scripts/uosc/main.lua")" = '-- fake uosc 5.13.0' -a -f "$(rec "$c" first_backup)/scripts/uosc/elements/Timeline.lua"
    check "$l: old uosc files not left behind" test ! -e "$c/scripts/uosc/elements"
    check "$l: fonts updated" test "$(cat "$c/fonts/uosc_icons.otf")" = 'icons 5.13'
    check "$l: record knows uosc and uosc.conf were there" test "$(rec "$c" uosc_preexisting)/$(rec "$c" uosc_conf_preexisting)" = yes/yes
    check "$l: the user's uosc.conf kept aside" same "$snap/uosc.conf" "$c/hikari-originales/script-opts/uosc.conf"
    check "$l: the $a4k_count hand-installed shaders moved to shaders-desactivados" test "$(ls "$c/shaders-desactivados" | wc -l | tr -d ' ')" = "$a4k_count" -a "$(cat "$c/shaders-desactivados/Anime4K_Thin_HQ.glsl")" = '// mine Anime4K_Thin_HQ.glsl'
    check "$l: hikari's copy installed" test "$(cat "$c/shaders/Anime4K_Thin_HQ.glsl")" = '// fake Anime4K_Thin_HQ.glsl' -a "$(ls "$c/shaders" | wc -l | tr -d ' ')" = "$a4k_count"
    check "$l: moves recorded" test "$(grep -c '^a4k_moved=shaders-desactivados/Anime4K_' "$c/hikari-installed.txt")" = "$a4k_count"
    check "$l: the three glsl-shaders lines in the profiles turned off" test "$(grep -c '^# hikari: glsl-shaders="~~/shaders/Anime4K_' "$c/mpv.conf")" = 3
    check "$l: no Anime4K line left on in mpv.conf" test "$(grep -c '^glsl-shaders' "$c/mpv.conf")" = 0
    check "$l: the profiles otherwise untouched" test "$(grep -c '^profile-cond=get("height", 0)' "$c/mpv.conf")/$(grep -c '^profile-restore=copy$' "$c/mpv.conf")" = 3/3
    check "$l: user options untouched" bash -c "for l in 'hwdec=videotoolbox' 'target-trc=gamma2.2' 'deband=yes' 'alang=es,spa,es-ES,es-419,ja,jpn' 'osd-font=\"Helvetica Neue\"'; do grep -qxF \"\$l\" '$c/mpv.conf' || exit 1; done"
    check "$l: block at the end, starting with [default]" test "$(tail -n 9 "$c/mpv.conf" | head -n 2 | tr '\n' '|')" = '# >>> hikari (managed block, do not edit) >>>|[default]|' -a "$(tail -n 1 "$c/mpv.conf")" = '# <<< hikari <<<'
    check "$l: the 7 CTRL+0..6 lines turned off" test "$(grep -c '^# hikari: CTRL+[0-6] no-osd change-list glsl-shaders' "$c/input.conf")" = 7
    check "$l: CTRL+t and WHEEL_* untouched" test "$(grep -c '^CTRL+t cycle-values\|^WHEEL_' "$c/input.conf")" = 5
    check "$l: hikari binds Ctrl+0..7 (keys free now)" test "$(grep -c '^Ctrl+[0-7]  script-message-to hikari_upscale set-mode ' "$c/input.conf")" = 8
    check "$l: commented lines recorded" test "$(grep -c '^a4k_commented=' "$c/hikari-installed.txt")/$(grep -c '^a4k_commented_mpv=' "$c/hikari-installed.txt")" = 7/3
    check "$l: Automático, quality fast (Apple M5)" same "$tmp/want-auto-fast" "$c/hikari-upscale.conf"
    check "$l: thumbfast gets the Homebrew mpv" test "$(grep '^mpv_path=' "$c/script-opts/thumbfast.conf")" = 'mpv_path=/opt/homebrew/bin/mpv'
    check "$l: watch_later and mpv.icns untouched" test "$(cat "$c/watch_later/ABCDEF")|$(cat "$c/mpv.icns")" = 'start=123|icns'
}

# check_mac_restored <label>: the way back after uninstalling.
check_mac_restored() {
    local l=$1 c=$cfg f all=true
    check "$l: mpv.conf byte for byte" same "$snap/mpv.conf" "$c/mpv.conf"
    check "$l: input.conf byte for byte" same "$snap/input.conf" "$c/input.conf"
    check "$l: uosc.conf byte for byte" same "$snap/uosc.conf" "$c/script-opts/uosc.conf"
    check "$l: aniskip.lua back as it was" same "$snap/aniskip.lua" "$c/scripts/aniskip.lua"
    for f in "$snap"/shaders/*; do same "$f" "$c/shaders/${f##*/}" || all=false; done
    check "$l: own shaders back byte for byte, hikari's gone" test "$all" = true -a "$(shader_list "$c/shaders")" = "$(shader_list "$snap/shaders")"
    check "$l: shaders-desactivados, scripts-desactivados, record gone" test ! -e "$c/shaders-desactivados" -a ! -e "$c/scripts-desactivados" -a ! -e "$c/hikari-installed.txt" -a ! -e "$c/hikari-originales"
    check "$l: thumbfast (hikari's) removed, uosc (was there) kept" test ! -e "$c/scripts/thumbfast.lua" -a ! -e "$c/script-opts/thumbfast.conf" -a -d "$c/scripts/uosc"
    check "$l: no hikari scripts left" test "$(count_glob "$c"/scripts/hikari-*)" = 0
    check "$l: watch_later untouched" test "$(cat "$c/watch_later/ABCDEF")" = 'start=123'
}

h=$(newhome mac)
cfg="$h/.config/mpv"
snap="$tmp/snap-mac"
make_mac "$cfg"
snapshot "$cfg" "$snap"
no_answers
run "$h" --yes
check 'Mac, --yes: exit 0' test "$rc" = 0
check 'Mac, --yes: the hand-installed Anime4K is left alone (default no)' test "$(rec "$cfg" anime4k)" = manual -a ! -e "$cfg/shaders-desactivados"
check 'Mac, --yes: its keys and mpv.conf lines left on' test "$(grep -c '^# hikari:' "$cfg/mpv.conf" "$cfg/input.conf" | cut -d: -f2 | tr '\n' ' ')" = '0 0 '
check 'Mac, --yes: hikari does not bind Ctrl+0..7 over them' test "$(grep -c 'set-mode' "$cfg/input.conf")" = 0
check 'Mac, --yes: hikari-upscale.conf off (Anime4K is not hikari'"'"'s)' test "$(sed -n 2p "$cfg/hikari-upscale.conf")" = 'script-opts-append=hikari_upscale-mode=off'
run "$h" --uninstall --yes
check 'Mac, --yes: uninstall gives mpv.conf back' same "$snap/mpv.conf" "$cfg/mpv.conf"
check 'Mac, --yes: uninstall gives input.conf back' same "$snap/input.conf" "$cfg/input.conf"
check 'Mac, --yes: uninstall gives uosc.conf back' same "$snap/uosc.conf" "$cfg/script-opts/uosc.conf"

h=$(newhome mac2)
cfg="$h/.config/mpv"
snap="$tmp/snap-mac2"
make_mac "$cfg"
snapshot "$cfg" "$snap"
run "$h" --yes --anime4k yes
check 'Mac, take over (--anime4k yes): exit 0' test "$rc" = 0
[ "$rc" = 0 ] || show_out
check_mac_installed 'Mac, take over'
run "$h" --yes
check 'Mac, update: exit 0' test "$rc" = 0
check 'Mac, update: lines not turned off twice' test "$(grep -c '^# hikari: # hikari:' "$cfg/mpv.conf" "$cfg/input.conf" | cut -d: -f2 | tr '\n' ' ')" = '0 0 '
check 'Mac, update: still 3 + 7 recorded' test "$(grep -c '^a4k_commented=' "$cfg/hikari-installed.txt")/$(grep -c '^a4k_commented_mpv=' "$cfg/hikari-installed.txt")" = 7/3
check 'Mac, update: Automático kept (it is the user'"'"'s mode now)' same "$tmp/want-auto-fast" "$cfg/hikari-upscale.conf"
check 'Mac, update: broken script still recorded once' test "$(grep -c '^broken=' "$cfg/hikari-installed.txt")" = 1
run "$h" --uninstall --yes
check 'Mac, uninstall: exit 0' test "$rc" = 0
check_mac_restored 'Mac, uninstall'

# The same answering the questions (numbers and typed answers, as without
# arrows): 1 install, 1 the folder, then Enter (yes) for the broken script,
# y to let hikari take care of Anime4K, Enter for the keys and the mpv.conf lines.
h=$(newhome mac3)
cfg="$h/.config/mpv"
snap="$tmp/snap-mac3"
make_mac "$cfg"
snapshot "$cfg" "$snap"
answers '1\n1\n\ny\n\n\n'
run "$h"
check 'Mac, interactive: exit 0' test "$rc" = 0
check 'Mac, interactive: asked to take care of Anime4K, default no' has "$out" 'Let hikari take care of it?'
check 'Mac, interactive: asked about the keys, default yes' has "$out" 'so the hikari keys can use them? They are turned back on when you uninstall. [Y/n]'
check_mac_installed 'Mac, interactive'
answers '2\n1\n\n\n\n\n\n\n\n'
run "$h"
check 'Mac, interactive uninstall: exit 0' test "$rc" = 0
check_mac_restored 'Mac, interactive uninstall'
no_answers

# Spanish, through LANG.
h=$(newhome spanish)
(export LANG=es_ES.UTF-8; HIKARI_LANG='' run "$h" --yes --anime4k no; printf '%s' "$rc" >"$tmp/rc")
check 'LANG=es_ES.UTF-8: messages in Spanish' has "$out" 'Instalando hikari en'
(export LANG=en_US.UTF-8; HIKARI_LANG='' run "$h" --yes --anime4k no)
check 'LANG=en_US.UTF-8: messages in English' has "$out" 'Installing hikari into'
# macOS set to Spanish with LANG=en_US.UTF-8 in the terminal (the usual case):
# the system language wins over LANG, LC_ALL still wins over both.
(export LANG=en_US.UTF-8 HIKARI_TEST_APPLE_LANGS='(\n    "es-ES"\n)'; HIKARI_LANG='' run "$h" --yes --anime4k no)
check 'macOS in Spanish, LANG=en_US: messages in Spanish' has "$out" 'Instalando hikari en'
(export LANG=es_ES.UTF-8 HIKARI_TEST_APPLE_LANGS='(\n    "en-GB",\n    "es-ES"\n)'; HIKARI_LANG='' run "$h" --yes --anime4k no)
check 'macOS in English, LANG=es_ES: messages in English' has "$out" 'Installing hikari into'
(export LANG=es_ES.UTF-8 HIKARI_TEST_OS=Linux HIKARI_TEST_APPLE_LANGS='(\n    "en-GB"\n)'; HIKARI_LANG='' run "$h" --yes --anime4k no)
check 'Linux: the macOS language list is not read' has "$out" 'Instalando hikari en'

# --- language of hikari in mpv --------------------------------------------------

# The installer's hikari-language.conf and locale rules against the ones of
# hikari-language.lua and hikari-i18n.lua (when lua is there to ask them).
sed -n '/^hikari_defaults() {/,/^}/p; /^lower() /p; /^mpv_language_code() {/,/^}/p; /^language_conf_text() {/,/^}/p' \
    "$repo/install/hikari.sh" >"$tmp/lang-funcs.sh"
lang_conf() { "$under" -c '. "$1"; hikari_defaults; language_conf_text "$2"' _ "$tmp/lang-funcs.sh" "$1"; }
want_lang() { lang_conf "$1" >"$tmp/want-lang-$1"; printf '%s' "$tmp/want-lang-$1"; }
lang_code() { "$under" -c '. "$1"; mpv_language_code "$2" || printf -' _ "$tmp/lang-funcs.sh" "$1"; }
LANG_CODES='en es de fr it pl pt ro ru tr uk zh-HK zh-hans'
LANG_LOCALES='es_ES.UTF-8 de_DE@euro pt_BR fr_CA.utf8 en_GB ru_RU.KOI8-R uk_UA tr_TR pl_PL ro_RO it_IT zh_CN.UTF-8 zh_SG zh-Hans zh-Hans-HK zh zh_TW zh_HK zh-MO zh-Hant zh-Hant-TW C POSIX C.UTF-8 ja_JP.UTF-8 nl_NL es-419'
if command -v lua >/dev/null 2>&1; then
    cat >"$tmp/lang.lua" <<'EOF'
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')
mock.install('hikari_language')
HIKARI_LANGUAGE_TEST = true
local l = assert(loadfile('portable_config/scripts/hikari-language.lua'))()
if arg[1] == 'conf' then io.write(l.persist_content(arg[2])) else io.write(l.i18n.normalize(arg[2]) or '-') end
EOF
    same_lang=true
    for code in $LANG_CODES; do
        lang_conf "$code" >"$tmp/lang-sh"
        (cd "$repo" && lua "$tmp/lang.lua" conf "$code") >"$tmp/lang-lua"
        same "$tmp/lang-sh" "$tmp/lang-lua" || { same_lang=false; echo "     differs: $code"; }
    done
    check 'language: hikari-language.conf byte for byte what hikari-language.lua writes, 13 languages' $same_lang
    same_rules=true
    for loc in $LANG_LOCALES; do
        a=$(lang_code "$loc")
        b=$(cd "$repo" && lua "$tmp/lang.lua" code "$loc")
        [ "$a" = "$b" ] || { same_rules=false; echo "     differs: $loc ($a / $b)"; }
    done
    check 'language: the same locale rules as hikari-i18n.lua' $same_rules
else
    echo 'skip language: no lua to compare with'
fi
check 'language: zh-HK also by the path of the uosc file' test "$(lang_conf zh-HK | tail -n 1)" = 'script-opts-append=uosc-languages=~~/scripts/uosc/intl/zh-HK.json,zh-HK,en'
check 'language: an unknown code (a newline in it) is written as English' test "$(lang_conf $'es\nx' | head -n 1)" = '# Generated by hikari-language.lua. Language: en'

h=$(newhome lang)
cfg="$h/.config/mpv"
(export LANG=de_DE.UTF-8 HIKARI_TEST_APPLE_LANGS='(\n    "pt-BR",\n    "en-US"\n)'; run "$h" --yes --anime4k no)
check 'language: macOS, first install: the system language (pt), not LANG' same "$cfg/hikari-language.conf" "$(want_lang pt)"
check 'language: the installer says it, in its own language' has "$out" 'hikari language in mpv: pt (the system'"'"'s; change it in mpv with Alt+l).'
check 'language: the texts module installed and recorded' test -f "$cfg/script-modules/hikari-i18n.lua" -a "$(grep -c '^file=script-modules/hikari-i18n.lua$' "$cfg/hikari-installed.txt")" = 1
check 'language: the language script installed' same "$repo/portable_config/scripts/hikari-language.lua" "$cfg/scripts/hikari-language.lua"
(export LANG=de_DE.UTF-8; run "$h" --yes --anime4k no)
check 'language: update: the choice kept' same "$cfg/hikari-language.conf" "$(want_lang pt)"
check 'language: update: said so' has "$out" 'hikari-language.conf already exists: kept'
lang_conf fr >"$cfg/hikari-language.conf"
printf '# mine\n' >>"$cfg/hikari-language.conf"
cp "$cfg/hikari-language.conf" "$tmp/lang-mine"
(export LANG=de_DE.UTF-8; run "$h" --yes --anime4k no)
check 'language: update: a choice made in mpv kept byte for byte' same "$tmp/lang-mine" "$cfg/hikari-language.conf"
# The copy from the hikari files (no choice in it) is replaced by the system language.
cp "$repo/portable_config/hikari-language.conf" "$cfg/hikari-language.conf"
(export HIKARI_TEST_OS=Linux LANG=zh_TW.UTF-8 HIKARI_TEST_APPLE_LANGS='(\n    "es-ES"\n)'; run "$h" --yes --anime4k no)
check 'language: no choice yet: the system language (Linux, zh_TW -> zh-HK, LANG read)' same "$cfg/hikari-language.conf" "$(want_lang zh-HK)"
rm -f "$cfg/hikari-language.conf"
(export HIKARI_TEST_OS=Linux LANG=ja_JP.UTF-8; run "$h" --yes --anime4k no)
check 'language: a language hikari does not have: English' same "$cfg/hikari-language.conf" "$(want_lang en)"
rm -f "$cfg/hikari-language.conf"
(export HIKARI_MPV_LANG=uk LANG=de_DE.UTF-8; run "$h" --yes --anime4k no)
check 'language: HIKARI_MPV_LANG wins' same "$cfg/hikari-language.conf" "$(want_lang uk)"
# A module left by an older hikari that is no longer shipped goes on update;
# a file of someone else in script-modules stays.
printf -- '-- old\n' >"$cfg/script-modules/hikari-old.lua"
printf -- '-- mine\n' >"$cfg/script-modules/mine.lua"
printf 'file=script-modules/hikari-old.lua\n' >>"$cfg/hikari-installed.txt"
run "$h" --yes --anime4k no
check 'language: stale hikari module removed on update, the user'"'"'s left' test ! -e "$cfg/script-modules/hikari-old.lua" -a -f "$cfg/script-modules/mine.lua"
run "$h" --uninstall --yes
check 'language: uninstall: the module goes, the user'"'"'s file stays' test ! -e "$cfg/script-modules/hikari-i18n.lua" -a -f "$cfg/script-modules/mine.lua"
check 'language: uninstall: the language choice kept by default' test -f "$cfg/hikari-language.conf"
rm -f "$cfg/script-modules/mine.lua"
run "$h" --yes --anime4k no
run "$h" --uninstall --yes
check 'language: uninstall: script-modules removed once empty' test ! -e "$cfg/script-modules"

# --- chip and card -> quality ---------------------------------------------------

lib="$tmp/hikari-lib.sh"
sed '$d' "$repo/install/hikari.sh" >"$lib"
quality() { # quality <os> <chip or lspci text>
    "$under" -c '. "$1"; hikari_defaults; OS=$2; PROBE=$3; hikari_cpu_brand() { printf "%s" "$PROBE"; }; hikari_lspci() { printf "%b\n" "$PROBE"; }; gpu_detect; printf "%s|%s" "$GPU_QUALITY" "$GPU_NAME"' _ "$lib" "$1" "$2"
}
for c in 'Apple M5|fast' 'Apple M1|fast' 'Apple M3|fast' 'Apple M4 Pro|hq' 'Apple M1 Pro|hq' 'Apple M2 Max|hq' 'Apple M3 Ultra|hq' \
    'Intel(R) Core(TM) i7-8559U CPU @ 2.70GHz|fast' 'Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz|fast' '|fast' 'Apple M5 Proto|fast'; do
    got=$(quality Darwin "${c%|*}")
    check "chip '${c%|*}' -> ${c#*|}" test "${got%%|*}" = "${c#*|}"
done
# Language straight from hikari_language (run unsets LC_ALL and LC_MESSAGES).
lang_of() { # lang_of <LC_ALL> <LC_MESSAGES> <LANG> <os> <AppleLanguages output>
    env -u HIKARI_LANG LC_ALL="$1" LC_MESSAGES="$2" LANG="$3" "$under" -c '. "$1"; T_OS=$2 T_LANGS=$3; hikari_uname() { printf "%s" "$T_OS"; }; hikari_apple_languages() { printf "%b\n" "$T_LANGS"; }; hikari_language' _ "$lib" "$4" "$5" 2>/dev/null
}
es_mac='(\n    "es-ES"\n)'
check 'language: macOS in Spanish, LANG=en_US -> es' test "$(lang_of '' '' en_US.UTF-8 Darwin "$es_mac")" = es
check 'language: macOS in Spanish, LC_ALL=en_US -> en (LC_ALL wins)' test "$(lang_of en_US.UTF-8 '' es_ES.UTF-8 Darwin "$es_mac")" = en
check 'language: macOS in Spanish, LC_MESSAGES=en_US -> en' test "$(lang_of '' en_US.UTF-8 '' Darwin "$es_mac")" = en
check 'language: macOS without a language list -> LANG' test "$(lang_of '' '' es_ES.UTF-8 Darwin '')" = es
check 'language: es-419 first -> es' test "$(lang_of '' '' en_US.UTF-8 Darwin '(\n    "es-419",\n    "en-US"\n)')" = es
check 'language: Linux ignores the macOS list' test "$(lang_of '' '' en_US.UTF-8 Linux "$es_mac")" = en
check 'chip: the name is shown as read' test "$(quality Darwin 'Apple M5')" = 'fast|Apple M5'
nv='00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 630\n01:00.0 VGA compatible controller: NVIDIA Corporation GA106 [GeForce RTX 3060]'
check 'lspci: NVIDIA next to Intel -> hq, named' test "$(quality Linux "$nv")" = 'hq|NVIDIA Corporation GA106 [GeForce RTX 3060]'
check 'lspci: AMD Navi -> hq' test "$(quality Linux '03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600/6600 XT/6600M]' | cut -d'|' -f1)" = hq
check 'lspci: AMD integrated -> fast' test "$(quality Linux '05:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Cezanne [Radeon Vega Series / Radeon Vega Mobile Series]' | cut -d'|' -f1)" = fast
check 'lspci: Intel only -> fast' test "$(quality Linux '00:02.0 VGA compatible controller: Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics]')" = 'fast|Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics]'
check 'lspci: NVIDIA as 3D controller (laptop) -> hq' test "$(quality Linux '01:00.0 3D controller: NVIDIA Corporation TU117M' | cut -d'|' -f1)" = hq
check 'no lspci -> fast, unknown' test "$(quality Linux '')" = 'fast|'
h=$(newhome chip-pro)
HIKARI_TEST_CHIP='Apple M4 Pro' run "$h" --yes
check 'Apple M4 Pro: install writes Automático, quality hq' test "$(head -n 1 "$h/.config/mpv/hikari-upscale.conf")" = '# Generated by hikari-upscale.lua. Mode: auto, quality: hq'

# --- initial mode: auto vs respected ------------------------------------------

h=$(newhome mode)
cfg="$h/.config/mpv"
run "$h" --yes --anime4k no
check 'mode: Anime4K declined -> off' test "$(rec "$cfg" anime4k)/$(sed -n 2p "$cfg/hikari-upscale.conf")" = 'declined/script-opts-append=hikari_upscale-mode=off'
run "$h" --yes
check 'mode: --yes after a no keeps it declined' test "$(rec "$cfg" anime4k)" = declined
run "$h" --yes --anime4k yes
check 'mode: installed later -> the off file is replaced by Automático' same "$tmp/want-auto-fast" "$cfg/hikari-upscale.conf"
printf '# Generated by hikari-upscale.lua. Mode: ca, quality: hq\n' >"$cfg/hikari-upscale.conf"
run "$h" --yes --anime4k yes
check 'mode: an update with --anime4k yes respects the chosen mode' test "$(head -n 1 "$cfg/hikari-upscale.conf")" = '# Generated by hikari-upscale.lua. Mode: ca, quality: hq'
rm -f "$cfg/hikari-upscale.conf"
run "$h" --yes
check 'mode: missing on an update of hikari'"'"'s Anime4K -> Automático' same "$tmp/want-auto-fast" "$cfg/hikari-upscale.conf"
check 'mode: the shipped hikari-upscale.conf is off' test "$(sed -n 2p "$repo/portable_config/hikari-upscale.conf")" = 'script-opts-append=hikari_upscale-mode=off'

# --- no terminal ------------------------------------------------------------------

h=$(newhome notty)
cfg="$h/.config/mpv"
no_answers
(
    export HOME="$h" HIKARI_LANG=en TMPDIR="$tmp/tmpdir" FAKE="$fake" HIKARI_TEST_OVERRIDES="$tmp/overrides.sh"
    unset HIKARI_TEST_TTY MPV_HOME XDG_CONFIG_HOME
    setsid -w "$under" "$copy" --anime4k no </dev/null
) >"$out" 2>&1
rc=$?
shell_errors
check 'no tty (setsid, the real /dev/tty): installs with the default answers' test "$rc" = 0 -a -f "$cfg/hikari-installed.txt"
check 'no tty: says every question takes its default' has "$out" 'No terminal to ask on'
HIKARI_TEST_TTY='' run "$h" --uninstall
check 'no tty: --uninstall works without questions' test "$rc" = 0 -a ! -e "$cfg/hikari-installed.txt"
h=$(newhome notty-linux)
mkdir -p "$h/.config/mpv" "$h/.var/app/io.mpv.Mpv/config/mpv"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv HIKARI_TEST_FLATPAK=1 HIKARI_TEST_TTY='' run "$h"
check 'no tty, two folders found: clear error, exit 2, nothing done' test "$rc" = 2 -a -n "$(grep 'choose with --target' "$out")" -a ! -e "$h/.config/mpv/hikari-installed.txt"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv HIKARI_TEST_FLATPAK=1 HIKARI_TEST_TTY='' run "$h" --target "$h/.var/app/io.mpv.Mpv/config/mpv"
check 'no tty, --target picks one' test "$rc" = 0 -a -f "$h/.var/app/io.mpv.Mpv/config/mpv/hikari-installed.txt"
check 'Flatpak: no mpv_path (mpv inside the sandbox is the right one)' test -z "$(grep '^mpv_path' "$h/.var/app/io.mpv.Mpv/config/mpv/script-opts/thumbfast.conf")"
check 'Flatpak: recorded as such' test "$(rec "$h/.var/app/io.mpv.Mpv/config/mpv" player)" = flatpak

# --- Linux folders, MPV_HOME, typed folder --------------------------------------

h=$(newhome linux)
answers '1\n2\n\n'
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv HIKARI_TEST_SNAP=1 HIKARI_TEST_LSPCI='01:00.0 VGA compatible controller: NVIDIA Corporation AD104 [GeForce RTX 4070]' run "$h"
check 'Linux: both folders listed' test -n "$(grep -F "Config: $h/.config/mpv" "$out")" -a -n "$(grep -F "Config: $h/snap/mpv/current/.config/mpv" "$out")"
check 'Linux: number 2 picks the Snap folder' test -f "$h/snap/mpv/current/.config/mpv/hikari-installed.txt" -a ! -e "$h/.config/mpv/hikari-installed.txt"
check 'Linux: NVIDIA -> hq' test "$(head -n 1 "$h/snap/mpv/current/.config/mpv/hikari-upscale.conf")" = '# Generated by hikari-upscale.lua. Mode: auto, quality: hq'
h=$(newhome mpvhome)
mkdir -p "$h/custom"
T_MPV_HOME="$h/custom" run "$h" --yes
check 'MPV_HOME: used instead of ~/.config/mpv' test -f "$h/custom/hikari-installed.txt" -a ! -e "$h/.config/mpv"
check 'MPV_HOME: said so' has "$out" "MPV_HOME is set: mpv reads its config from $h/custom"
h=$(newhome other)
mkdir -p "$h/elsewhere/mpvcfg"
answers '1\no\n'"$h/elsewhere/mpvcfg"'\n\n\n\n\n\n\n' 
run "$h"
check 'typed folder ("O"): installed there' test "$rc" = 0 -a -f "$h/elsewhere/mpvcfg/hikari-installed.txt"
answers '1\n0\n'
run "$h"
check '"0" at the folder list: cancelled, exit 0, nothing done' test "$rc" = 0 -a ! -e "$h/.config/mpv" -a -n "$(grep Cancelled "$out")"
answers '0\n'
run "$h"
check '"0" at the first menu: exit 0' test "$rc" = 0
answers '7\n'
run "$h"
check 'invalid answer then end of input: says so and leaves' test "$rc" = 0 -a -n "$(grep 'Invalid option' "$out")"
no_answers
h=$(newhome refuse)
mkdir -p "$h/docs"
printf 'x' >"$h/docs/letter.txt"
run "$h" --yes --target "$h/docs"
check 'without questions a folder that is not mpv'"'"'s is refused (exit 2)' test "$rc" = 2 -a "$(ls "$h/docs")" = letter.txt
run "$h" --yes --target "$h"
check 'the home folder is refused' test "$rc" = 2 -a -n "$(grep 'Refusing' "$out")"
run "$h" --yes --target /
check 'the root folder is refused' test "$rc" = 2
h=$(newhome langonly)
mkdir -p "$h/cfg"
printf '# Generated by hikari-language.lua. Language: es\n' >"$h/cfg/hikari-language.conf"
run "$h" --yes --anime4k no --target "$h/cfg"
check 'a folder with only hikari-language.conf is taken as mpv'"'"'s' test "$rc" = 0 -a -f "$h/cfg/mpv.conf"

# --- mpv missing -----------------------------------------------------------------

h=$(newhome nompv)
HIKARI_TEST_MPV='' run "$h" --yes
check 'macOS without mpv nor brew: explains and exits 2' test "$rc" = 2 -a -n "$(grep 'brew install mpv' "$out")" -a ! -e "$h/.config"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV='' run "$h" --yes
check 'Linux without mpv: names the packages, no sudo run, exit 2' test "$rc" = 2 -a -n "$(grep 'sudo apt install mpv' "$out")"
printf '#!/bin/sh\necho "fake brew $*" >"%s/brew.log"\nprintf /opt/homebrew/bin/mpv >"%s/mpv-path"\n' "$fake" "$fake" >"$fake/brew"
chmod +x "$fake/brew"
HIKARI_TEST_MPV='' HIKARI_TEST_BREW="$fake/brew" run "$h" --yes
check 'brew is never run without questions' test "$rc" = 2 -a ! -e "$fake/brew.log"
answers 'y\n1\n\n'
HIKARI_TEST_MPV='' HIKARI_TEST_BREW="$fake/brew" run "$h" --install --anime4k no
check 'brew offered and run when accepted, then install goes on' test "$rc" = 0 -a "$(cat "$fake/brew.log" 2>/dev/null)" = 'fake brew install mpv' -a -f "$h/.config/mpv/hikari-installed.txt"
rm -f "$fake/mpv-path" "$fake/brew.log"
no_answers
h=$(newhome iina)
HIKARI_TEST_IINA=1 run "$h" --yes --anime4k no
check 'IINA: told it is not touched' has "$out" 'IINA is installed'

# --- downloads checked before anything is touched -----------------------------

h=$(newhome badhash)
cfg="$h/.config/mpv"
make_mac "$cfg"
snapshot "$cfg" "$tmp/snap-bad"
cp "$fake/thumbfast.lua" "$tmp/thumb.keep"
printf -- '-- tampered\n' >"$fake/thumbfast.lua"
run "$h" --yes --anime4k yes
cp "$tmp/thumb.keep" "$fake/thumbfast.lua"
check 'bad thumbfast hash: exit 1, says so' test "$rc" = 1 -a -n "$(grep 'does not match its expected SHA256' "$out")"
check 'bad hash: nothing moved or changed, no backup' test -e "$cfg/scripts/aniskip.lua" -a ! -e "$cfg/shaders-desactivados" -a -z "$(ls -d "$h"/.config/mpv-respaldo-* 2>/dev/null)"
check 'bad hash: mpv.conf and input.conf untouched' test "$(same "$tmp/snap-bad/mpv.conf" "$cfg/mpv.conf" && same "$tmp/snap-bad/input.conf" "$cfg/input.conf" && echo y)" = y
check 'bad hash: temporary folder removed' test -z "$(ls -A "$tmp/tmpdir")"
HIKARI_TEST_FAIL_URL='https://github.com/tomasklaen/uosc/releases/download/5.13.0/uosc.zip' run "$h" --yes
check 'failed uosc download: exit 1, nothing done' test "$rc" = 1 -a -e "$cfg/scripts/aniskip.lua" -a ! -e "$cfg/hikari-installed.txt"
HIKARI_TEST_FAIL_URL='https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip' run "$h" --yes --anime4k yes
check 'failed Anime4K download: the rest is installed (exit 0), state failed' test "$rc" = 0 -a "$(rec "$cfg" anime4k)" = failed
check 'failed Anime4K download: no shader moved, no line turned off' test ! -e "$cfg/shaders-desactivados" -a "$(grep -c '^# hikari:' "$cfg/mpv.conf")" = 0 -a "$(cat "$cfg/shaders/Anime4K_Clamp_Highlights.glsl")" = '// mine Anime4K_Clamp_Highlights.glsl'

# --- conflicts, malformed block, backups ----------------------------------------

h=$(newhome conflict)
cfg="$h/.config/mpv"
mkdir -p "$cfg/scripts" "$cfg/script-opts" "$cfg/fonts"
printf -- '-- modernx\n' >"$cfg/scripts/ModernX.lua"
printf 'x=1\n' >"$cfg/script-opts/modernx.conf"
printf 'font' >"$cfg/fonts/modernx.ttf"
printf -- '-- fine\n' >"$cfg/scripts/autoload.lua"
printf '\377\376\200 NOT UTF-8\n' >"$cfg/scripts/latin.lua"
run "$h" --yes --anime4k no
check 'conflict: ModernX (any case), its conf and font set aside' test ! -e "$cfg/scripts/ModernX.lua" -a -f "$cfg/scripts-desactivados/ModernX.lua" -a -f "$cfg/scripts-desactivados/script-opts/modernx.conf" -a -f "$cfg/scripts-desactivados/fonts/modernx.ttf"
check 'conflict: other scripts left' test -f "$cfg/scripts/autoload.lua"
check 'a script with bytes that are not UTF-8 is not "broken", and tr does not complain' \
    test -f "$cfg/scripts/latin.lua" -a -z "$(grep -i 'byte sequence' "$out")"
run "$h" --uninstall --yes
check 'conflict: given back on uninstall (uosc was hikari'"'"'s)' test -f "$cfg/scripts/ModernX.lua" -a -f "$cfg/script-opts/modernx.conf" -a -f "$cfg/fonts/modernx.ttf" -a ! -e "$cfg/scripts-desactivados"

h=$(newhome malformed)
cfg="$h/.config/mpv"
mkdir -p "$cfg"
printf 'a=1\n# >>> hikari (managed block, do not edit) >>>\nosc=no\n' >"$cfg/mpv.conf"
run "$h" --yes --anime4k no
check 'malformed block: that folder fails (exit 1) and says where the backup is' test "$rc" = 1 -a -n "$(grep 'incomplete or repeated hikari block' "$out")" -a -n "$(grep 'Your previous config is in' "$out")"

h=$(newhome rotation)
cfg="$h/.config/mpv"
mkdir -p "$cfg"
printf 'volume=40\n' >"$cfg/mpv.conf"
for _ in 1 2 3 4 5; do run "$h" --yes --anime4k no; done
check 'backups: the three newest plus the original are kept' test "$(ls -d "$h"/.config/mpv-respaldo-hikari-* | wc -l | tr -d ' ')" = 4
check 'backups: the original (before hikari) is one of them' test "$(cat "$(ls -d "$h"/.config/mpv-respaldo-hikari-*/hikari-backup-original.txt | head -n 1 | xargs dirname)/mpv.conf")" = 'volume=40'
check 'backups: the old ones were announced' has "$out" 'Old backup deleted'
mkdir -p "$h/.config/mpv-respaldo-hikari-notes" "$h/.config/other-respaldo-hikari-20200101-000000"
run "$h" --yes --anime4k no
check 'backups: folders with other names are never touched' test -d "$h/.config/mpv-respaldo-hikari-notes" -a -d "$h/.config/other-respaldo-hikari-20200101-000000"

# --- osc=no of the user's own once uosc goes ---------------------------------

h=$(newhome osc)
cfg="$h/.config/mpv"
mkdir -p "$cfg"
printf 'osc=no\nvolume=40\n' >"$cfg/mpv.conf"
run "$h" --yes --anime4k no
run "$h" --uninstall --yes
check 'osc=no without uosc: warned, and left as it is without questions' test -n "$(grep 'no on-screen controls' "$out")" -a "$(cat "$cfg/mpv.conf")" = 'osc=no
volume=40'
run "$h" --yes --anime4k no
answers '2\n1\n\n\ny\n\n'
run "$h"
check 'osc=no without uosc: turned off with the hikari prefix when asked' test "$rc" = 0 -a "$(head -n 1 "$cfg/mpv.conf")" = '# hikari: osc=no'
no_answers

# --- migration from sosc (the name of hikari until v0.3.0) ---------------------

# The real installer of sosc 0.3.0 and its files, taken from the v0.3.0 tag,
# with the same fake downloads and overrides (under sosc's names). Skipped
# when git or the tag is not available (a copy without history).
sosc_ok=0
sosc_copy="$tmp/sosc-repo/install/sosc.sh"
if command -v git >/dev/null 2>&1 && git -C "$repo" cat-file -e v0.3.0:install/sosc.sh 2>/dev/null; then
    mkdir -p "$tmp/sosc-repo/install"
    git -C "$repo" archive v0.3.0 portable_config | tar -x -C "$tmp/sosc-repo"
    git -C "$repo" show v0.3.0:install/sosc.sh >"$tmp/sosc-orig.sh"
    sed -e "s/^\(    UOSC_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sha "$fake/uosc.zip")'/" \
        -e "s/^\(    THUMBFAST_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sha "$fake/thumbfast.lua")'/" \
        -e "s/^\(    ANIME4K_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sha "$fake/anime4k.zip")'/" \
        -e '$d' "$tmp/sosc-orig.sh" >"$sosc_copy"
    printf '. "$SOSC_TEST_OVERRIDES"\n' >>"$sosc_copy"
    tail -n 1 "$tmp/sosc-orig.sh" >>"$sosc_copy"
    sed -e 's/hikari_/sosc_/g' -e 's/HIKARI_/SOSC_/g' "$tmp/overrides.sh" >"$tmp/sosc-overrides.sh"
    sosc_ok=1
fi
# run_sosc <home> <args...>: like run, with sosc 0.3.0.
run_sosc() {
    local home=$1
    shift
    (
        export HOME="$home" SOSC_LANG=en TMPDIR="$tmp/tmpdir" FAKE="$fake" SOSC_TEST_OVERRIDES="$tmp/sosc-overrides.sh"
        unset MPV_HOME XDG_CONFIG_HOME LC_ALL LC_MESSAGES SOSC_TEST_TTY
        "$under" "$sosc_copy" "$@" </dev/null
    ) >"$out" 2>&1
    rc=$?
    shell_errors
}
# Files and folders of a config whose name or content still says sosc.
sosc_left() { (cd "$1" && { find . -iname '*sosc*'; grep -rlI -i sosc . 2>/dev/null; } | sort -u | tr '\n' ' '); }

if [ "$sosc_ok" = 1 ]; then
    # The Mac of SCEPTICG with sosc 0.3.0: Anime4K installed by hand taken over,
    # aniskip.lua (404) set aside, CTRL+0..6 and the profiles turned off.
    h=$(newhome mig-mac)
    cfg="$h/.config/mpv"
    make_mac "$cfg"
    snapshot "$cfg" "$tmp/snap-sosc-pre"
    run_sosc "$h" --yes --anime4k yes
    check 'sosc 0.3.0: installed on the Mac (exit 0)' test "$rc" = 0 -a -f "$cfg/sosc-installed.txt"
    [ "$rc" = 0 ] || show_out
    check 'sosc 0.3.0: Anime4K taken over, lines turned off with "# sosc: "' \
        test "$(grep -c '^# sosc: ' "$cfg/mpv.conf")/$(grep -c '^# sosc: ' "$cfg/input.conf")/$(grep -c '^anime4k=sosc$' "$cfg/sosc-installed.txt")" = 3/7/1
    # What SCEPTICG did afterwards: p for the palettes and the update check off
    # by hand, outside the blocks; another palette and subtitle style.
    printf 'p script-binding sosc_palettes/open-menu\n' >>"$cfg/input.conf"
    printf 'script-opts-append=sosc-update-enabled=no\ninclude="~~/sosc-subs.conf"\n' >>"$cfg/mpv.conf"
    printf '# Generated by sosc-palettes.lua. Palette: sceptic\nscript-opts-append=uosc-color=foreground=5ad4e6\nscript-opts-append=sosc_palettes-palette=sceptic\n' >"$cfg/sosc-palette.conf"
    printf '# Generated by sosc-subs.lua. Style: box, size: large, height: normal\nscript-opts-append=sosc_subs-style=box\nscript-opts-append=sosc_subs-size=large\nscript-opts-append=sosc_subs-height=normal\nsub-back-color="#C0000000"\n' >"$cfg/sosc-subs.conf"
    printf 'last_check=1800000000\nlatest=0.3.0\n' >"$cfg/sosc-update.txt"
    sosc_backups=$(count_glob "$h"/.config/mpv-respaldo-sosc-*)
    sosc_first=$(grep '^first_backup=' "$cfg/sosc-installed.txt" | cut -d= -f2-)
    sosc_block_at=$(grep -n '^# >>> sosc' "$cfg/input.conf" | cut -d: -f1)
    # What uninstalling must give back: the Mac from before sosc, plus those lines
    # of his own (now with hikari's names).
    snap="$tmp/snap-sosc-mac"
    cp -R "$tmp/snap-sosc-pre" "$snap"
    printf 'p script-binding hikari_palettes/open-menu\n' >>"$snap/input.conf"
    printf 'script-opts-append=hikari-update-enabled=no\ninclude="~~/hikari-subs.conf"\n' >>"$snap/mpv.conf"

    run "$h" --yes
    check 'sosc -> hikari: exit 0' test "$rc" = 0
    [ "$rc" = 0 ] || show_out
    check 'sosc -> hikari: said so, and that uninstalling goes back to before sosc' \
        test -n "$(grep 'sosc is installed here' "$out")" -a -n "$(grep 'as it was before sosc' "$out")"
    check 'sosc -> hikari: nothing of sosc left (only the first backup in the record)' test "$(sosc_left "$cfg")" = './hikari-installed.txt '
    check 'sosc -> hikari: the record of sosc inherited' \
        test "$(rec "$cfg" first_backup)|$(rec "$cfg" anime4k)|$(rec "$cfg" hikari_version)|$(grep -c '^sosc_' "$cfg/hikari-installed.txt")" = "$sosc_first|hikari|dev|0"
    check 'sosc -> hikari: the first backup is the one from before sosc' test -f "$sosc_first/sosc-backup-original.txt" -a -f "$sosc_first/scripts/uosc/elements/Timeline.lua"
    check_mac_installed 'sosc -> hikari'
    check 'sosc -> hikari: its block took the place of the sosc block in input.conf' \
        test "$(grep -n '^# >>> hikari' "$cfg/input.conf" | cut -d: -f1)" = "$sosc_block_at"
    check 'sosc -> hikari: p of the user now points to hikari, and said so' \
        test "$(grep -cx 'p script-binding hikari_palettes/open-menu' "$cfg/input.conf")" = 1 -a -n "$(grep 'input.conf: line of yours changed from sosc to hikari: p script-binding hikari_palettes/open-menu' "$out")"
    # (hikari-subs.conf twice: the user's line and the one in the block.)
    check 'sosc -> hikari: mpv.conf lines of the user changed too' \
        test "$(grep -cx 'script-opts-append=hikari-update-enabled=no' "$cfg/mpv.conf")/$(grep -cx 'include="~~/hikari-subs.conf"' "$cfg/mpv.conf")/$(grep -c 'line of yours changed' "$out")" = 1/2/3
    check 'sosc -> hikari: palette choice kept, under hikari'"'"'s names' \
        test "$(cat "$cfg/hikari-palette.conf")" = "$(printf '# Generated by hikari-palettes.lua. Palette: sceptic\nscript-opts-append=uosc-color=foreground=5ad4e6\nscript-opts-append=hikari_palettes-palette=sceptic')"
    check 'sosc -> hikari: subtitle choice kept, under hikari'"'"'s names' \
        test "$(sed -n 2p "$cfg/hikari-subs.conf")|$(tail -n 1 "$cfg/hikari-subs.conf")" = 'script-opts-append=hikari_subs-style=box|sub-back-color="#C0000000"'
    check 'sosc -> hikari: upscale choice kept (Automático)' same "$tmp/want-auto-fast" "$cfg/hikari-upscale.conf"
    check 'sosc -> hikari: update check state of sosc not carried over' test ! -e "$cfg/sosc-update.txt" -a ! -e "$cfg/hikari-update.txt"
    check 'sosc -> hikari: old sosc backups left alone, and reported' \
        test "$(count_glob "$h"/.config/mpv-respaldo-sosc-*)" = "$sosc_backups" -a -n "$(grep "There are $sosc_backups old sosc backups" "$out")"
    hk_backup=$(rec "$cfg" last_backup)
    check 'sosc -> hikari: backup made before the migration, with the files of sosc' \
        test -f "$hk_backup/sosc-installed.txt" -a -f "$hk_backup/scripts/sosc-palettes.lua" -a -f "$hk_backup/sosc-palette.conf" -a -f "$hk_backup/sosc-originales/script-opts/uosc.conf"
    check 'sosc -> hikari: that backup is not marked as the original' test ! -e "$hk_backup/hikari-backup-original.txt"

    run "$h" --yes
    check 'sosc -> hikari, update: exit 0, nothing to migrate' test "$rc" = 0 -a -z "$(grep 'sosc is installed here' "$out")"
    check 'sosc -> hikari, update: lines not turned off twice' test "$(grep -c '^# hikari: # hikari:' "$cfg/mpv.conf" "$cfg/input.conf" | cut -d: -f2 | tr '\n' ' ')" = '0 0 '
    run "$h" --uninstall --yes
    check 'sosc -> hikari, uninstall: exit 0' test "$rc" = 0
    [ "$rc" = 0 ] || show_out
    check_mac_restored 'sosc -> hikari, uninstall (as before sosc)'
    check 'sosc -> hikari, uninstall: sosc is not put back' test "$(sosc_left "$cfg")" = ''

    # Uninstalling hikari straight from sosc 0.3.0 (with --yes the Anime4K by
    # hand was left alone): back to before sosc.
    h=$(newhome mig-uninst)
    cfg="$h/.config/mpv"
    snap="$tmp/snap-sosc-uninst"
    make_mac "$cfg"
    snapshot "$cfg" "$snap"
    run_sosc "$h" --yes
    check 'sosc 0.3.0 (Anime4K by hand kept): installed' test "$rc" = 0 -a -f "$cfg/sosc-installed.txt"
    run "$h" --uninstall --yes
    check 'uninstall from sosc: the folder is found (exit 0)' test "$rc" = 0 -a -n "$(grep 'sosc is installed here' "$out")"
    check 'uninstall from sosc: mpv.conf byte for byte' same "$snap/mpv.conf" "$cfg/mpv.conf"
    check 'uninstall from sosc: input.conf byte for byte' same "$snap/input.conf" "$cfg/input.conf"
    check 'uninstall from sosc: uosc.conf byte for byte' same "$snap/uosc.conf" "$cfg/script-opts/uosc.conf"
    check 'uninstall from sosc: aniskip.lua back' same "$snap/aniskip.lua" "$cfg/scripts/aniskip.lua"
    check 'uninstall from sosc: nothing of sosc or hikari left' \
        test "$(sosc_left "$cfg")" = '' -a "$(count_glob "$cfg"/scripts/hikari-* "$cfg"/hikari-installed.txt "$cfg"/hikari-originales)" = 0

    # A migration cut short: the blocks, the lines turned off, the choices and
    # sosc-originales already carried over, but sosc's record and scripts still
    # there (no record of hikari yet). The next run finishes it.
    h=$(newhome mig-cut)
    cfg="$h/.config/mpv"
    snap="$tmp/snap-sosc-cut"
    make_mac "$cfg"
    snapshot "$cfg" "$snap"
    run_sosc "$h" --yes --anime4k yes
    check 'cut short: sosc 0.3.0 installed' test "$rc" = 0 -a -f "$cfg/sosc-installed.txt"
    sosc_first=$(grep '^first_backup=' "$cfg/sosc-installed.txt" | cut -d= -f2-)
    for f in mpv.conf input.conf; do
        sed -e 's/^# >>> sosc (managed block, do not edit) >>>$/# >>> hikari (managed block, do not edit) >>>/' \
            -e 's/^# <<< sosc <<<$/# <<< hikari <<</' -e 's/^# sosc: /# hikari: /' "$cfg/$f" >"$tmp/cut-$f"
        cat "$tmp/cut-$f" >"$cfg/$f"
    done
    for f in "$cfg"/sosc-palette.conf "$cfg"/sosc-subs.conf "$cfg"/sosc-upscale.conf; do
        [ -f "$f" ] || continue
        sed 's/sosc/hikari/g' "$f" >"$cfg/hikari-${f##*/sosc-}"
        rm -f "$f"
    done
    mv "$cfg/sosc-originales" "$cfg/hikari-originales"
    run "$h" --yes
    check 'cut short: the next run finishes it (exit 0)' test "$rc" = 0 -a -n "$(grep 'sosc is installed here' "$out")"
    [ "$rc" = 0 ] || show_out
    check 'cut short: nothing of sosc left, its record inherited' \
        test "$(sosc_left "$cfg")|$(rec "$cfg" first_backup)|$(rec "$cfg" anime4k)" = "./hikari-installed.txt |$sosc_first|hikari"
    check 'cut short: lines not turned off twice' test "$(grep -c '^# hikari: # hikari:' "$cfg/mpv.conf" "$cfg/input.conf" | cut -d: -f2 | tr '\n' ' ')" = '0 0 '
    run "$h" --uninstall --yes
    check 'cut short, uninstall: exit 0' test "$rc" = 0
    check_mac_restored 'cut short, uninstall (as before sosc)'
else
    printf 'skip migration from sosc 0.3.0: the v0.3.0 tag is not in this copy\n'
fi

# Files of sosc copied by hand (no record): changed over all the same.
h=$(newhome mig-manual)
cfg="$h/.config/mpv"
mkdir -p "$cfg/scripts" "$cfg/script-opts"
printf -- '-- sosc palettes\n' >"$cfg/scripts/sosc-palettes.lua"
printf 'enabled=yes\n' >"$cfg/script-opts/sosc-title.conf"
printf 'script-opts-append=sosc_palettes-palette=nord\n' >"$cfg/sosc-palette.conf"
printf 'volume=50\ninclude="~~/sosc-palette.conf"\n# include="~~/sosc-subs.conf" (a comment of mine)\n' >"$cfg/mpv.conf"
printf 'Alt+p script-binding sosc_palettes/open-menu\nCtrl+9 script-message-to sosc_upscale set-mode auto\n' >"$cfg/input.conf"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv run "$h" --yes --anime4k no
check 'sosc by hand: exit 0' test "$rc" = 0
check 'sosc by hand: its files go, its choice stays under hikari'"'"'s name' \
    test "$(sosc_left "$cfg")|$(cat "$cfg/hikari-palette.conf")" = './mpv.conf |script-opts-append=hikari_palettes-palette=nord'
check 'sosc by hand: lines of the user changed, comments left alone' \
    test "$(head -n 3 "$cfg/mpv.conf" | tr '\n' '|')" = 'volume=50|include="~~/hikari-palette.conf"|# include="~~/sosc-subs.conf" (a comment of mine)|'
check 'sosc by hand: its Alt+p and Ctrl+9 now run hikari (Alt+p not repeated in the block)' \
    test "$(head -n 2 "$cfg/input.conf" | tr '\n' '|')/$(grep -c '^Alt+p' "$cfg/input.conf")" = 'Alt+p script-binding hikari_palettes/open-menu|Ctrl+9 script-message-to hikari_upscale set-mode auto|/1'
check 'sosc by hand: no record of sosc to inherit, the backup is the original' test -f "$(rec "$cfg" first_backup)/hikari-backup-original.txt"

# A broken sosc block: nothing is changed.
h=$(newhome mig-broken)
cfg="$h/.config/mpv"
mkdir -p "$cfg"
printf 'volume=50\n# >>> sosc (managed block, do not edit) >>>\nosc=no\n' >"$cfg/mpv.conf"
printf 'sosc_version=0.3.0\n' >"$cfg/sosc-installed.txt"
cp "$cfg/mpv.conf" "$tmp/sosc-broken-mpv"
run "$h" --yes --anime4k no
check 'broken sosc block: refused (exit 1), nothing changed' \
    test "$rc" = 1 -a -f "$cfg/sosc-installed.txt" -a ! -e "$cfg/hikari-installed.txt" -a ! -e "$cfg/scripts" -a -n "$(grep 'mpv.conf (sosc) has an incomplete' "$out")"
check 'broken sosc block: mpv.conf untouched' same "$tmp/sosc-broken-mpv" "$cfg/mpv.conf"

# Only the files sosc installed count as sosc: a sosc-other.lua of someone else
# is not sosc, and stays.
h=$(newhome mig-foreign)
cfg="$h/.config/mpv"
mkdir -p "$cfg/scripts" "$cfg/script-opts"
printf -- '-- not sosc\n' >"$cfg/scripts/sosc-otro.lua"
printf 'x=1\n' >"$cfg/script-opts/sosc-otro.conf"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv run "$h" --yes --anime4k no
check 'sosc-otro.lua alone: not taken for sosc' test "$rc" = 0 -a -z "$(grep 'sosc is installed here' "$out")"
check 'sosc-otro.lua alone: left where it was' test -f "$cfg/scripts/sosc-otro.lua" -a -f "$cfg/script-opts/sosc-otro.conf"
h=$(newhome mig-foreign2)
cfg="$h/.config/mpv"
mkdir -p "$cfg/scripts" "$cfg/script-opts"
printf -- '-- not sosc\n' >"$cfg/scripts/sosc-otro.lua"
printf 'x=1\n' >"$cfg/script-opts/sosc-otro.conf"
printf -- '-- sosc skip\n' >"$cfg/scripts/sosc-skip.lua"
printf 'x=1\n' >"$cfg/script-opts/sosc-skip.conf"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv run "$h" --yes --anime4k no
check 'sosc with a sosc-otro.lua of someone else: only sosc'"'"'s files go' \
    test "$rc" = 0 -a -n "$(grep 'sosc is installed here' "$out")" -a -f "$cfg/scripts/sosc-otro.lua" -a -f "$cfg/script-opts/sosc-otro.conf" \
    -a ! -e "$cfg/scripts/sosc-skip.lua" -a ! -e "$cfg/script-opts/sosc-skip.conf"

# Lines of the user: only whole names change; control characters are not shown.
h=$(newhome mig-words)
cfg="$h/.config/mpv"
mkdir -p "$cfg/scripts"
printf -- '-- sosc palettes\n' >"$cfg/scripts/sosc-palettes.lua"
printf 'include="~~/sosc-subs.conf"\nscript-opts-append=sosc-update-enabled=no\nscript-opts-append=mysosc_skipper-x=1,a-sosc-skip=2\n' >"$cfg/mpv.conf"
printf 'p script-binding sosc_palettes/open-menu\nx script-binding mysosc_skipper/x\nk script-binding sosc_skip/x \033[31mred\a\n' >"$cfg/input.conf"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv run "$h" --yes --anime4k no
check 'whole names: exit 0' test "$rc" = 0
check 'whole names: sosc names at the start or after = " or a space changed' \
    test "$(head -n 2 "$cfg/mpv.conf" | tr '\n' '|')$(head -n 1 "$cfg/input.conf")" = 'include="~~/hikari-subs.conf"|script-opts-append=hikari-update-enabled=no|p script-binding hikari_palettes/open-menu'
check 'whole names: mysosc_skipper and a-sosc-skip left alone' \
    test "$(sed -n 3p "$cfg/mpv.conf")|$(sed -n 2p "$cfg/input.conf")" = 'script-opts-append=mysosc_skipper-x=1,a-sosc-skip=2|x script-binding mysosc_skipper/x'
check 'whole names: the line with control characters changed in the file, as it was' \
    test "$(sed -n 3p "$cfg/input.conf")" = "$(printf 'k script-binding hikari_skip/x \033[31mred\a')"
check 'control characters: not sent to the terminal' \
    test -n "$(grep -F 'line of yours changed from sosc to hikari: k script-binding hikari_skip/x [31mred' "$out")" -a "$(grep -c "$(printf '\033\[31m')" "$out")" = 0 -a "$(grep -c "$(printf '\a')" "$out")" = 0

# Symbolic links in the way of sosc-originales: nothing is moved through them.
outside="$tmp/outside-orig"
mig_orig() { # mig_orig <name>: a home with sosc-originales/script-opts/uosc.conf
    h=$(newhome "$1")
    cfg="$h/.config/mpv"
    mkdir -p "$cfg/scripts" "$cfg/sosc-originales/script-opts"
    printf -- '-- sosc skip\n' >"$cfg/scripts/sosc-skip.lua"
    printf '# my uosc.conf\n' >"$cfg/sosc-originales/script-opts/uosc.conf"
    rm -rf "$outside"
    mkdir -p "$outside"
}
mig_orig mig-link1
mkdir -p "$cfg/hikari-originales"
ln -s "$outside" "$cfg/hikari-originales/script-opts"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv run "$h" --uninstall --yes
check 'link hikari-originales/script-opts: nothing moved out of the folder, said so' \
    test -z "$(ls -A "$outside")" -a -f "$cfg/sosc-originales/script-opts/uosc.conf" -a -n "$(grep 'is a symbolic link, nothing is written or moved' "$out")"
mig_orig mig-link2
ln -s "$outside" "$cfg/hikari-originales"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv run "$h" --uninstall --yes
check 'link hikari-originales: nothing moved out of the folder' test -z "$(ls -A "$outside")" -a -f "$cfg/sosc-originales/script-opts/uosc.conf"
mig_orig mig-link3
printf '# outside\n' >"$outside/uosc.conf"
rm -rf "$cfg/sosc-originales/script-opts"
ln -s "$outside" "$cfg/sosc-originales/script-opts"
mkdir -p "$cfg/hikari-originales"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv run "$h" --uninstall --yes
check 'link sosc-originales/script-opts: what it points to is not moved' \
    test "$(cat "$outside/uosc.conf")" = '# outside' -a ! -e "$cfg/hikari-originales/script-opts/uosc.conf"
mig_orig mig-link4
mkdir -p "$cfg/hikari-originales"
printf '# outside thumbfast\n' >"$outside/thumbfast.conf"
ln -s "$outside/thumbfast.conf" "$cfg/sosc-originales/script-opts/thumbfast.conf"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv run "$h" --yes --anime4k no
check 'a file of sosc-originales that is a link: not moved, the rest is' \
    test "$rc" = 0 -a "$(cat "$outside/thumbfast.conf")" = '# outside thumbfast' -a ! -L "$cfg/hikari-originales/script-opts/thumbfast.conf" \
    -a "$(cat "$cfg/hikari-originales/script-opts/uosc.conf")" = '# my uosc.conf'

# A broken link where the record of hikari goes: sosc's record is not written through it.
h=$(newhome mig-reclink)
cfg="$h/.config/mpv"
mkdir -p "$cfg/scripts"
printf -- '-- sosc skip\n' >"$cfg/scripts/sosc-skip.lua"
printf 'sosc_version=0.3.0\n' >"$cfg/sosc-installed.txt"
rm -f "$tmp/outside-record.txt"
ln -s "$tmp/outside-record.txt" "$cfg/hikari-installed.txt"
HIKARI_TEST_OS=Linux HIKARI_TEST_MPV=/usr/bin/mpv run "$h" --uninstall --yes
check 'broken link for the record: nothing written through it, said so' \
    test ! -e "$tmp/outside-record.txt" -a -n "$(grep "hikari-installed.txt is a symbolic link" "$out")"

# --- keyboard menus (pseudo-terminal) ------------------------------------------

# pty_run <home> <keys...>: runs the installer on a pseudo-terminal (100x40),
# sending each key after the screen settles; killed after 20 s of silence at
# the end (exit 124). Options for the installer in PTY_OPTS. Output in $out,
# exit code in $rc.
cat >"$tmp/pty.py" <<'PY'
import os, pty, sys, time, select, signal, fcntl, termios, struct
argv = [sys.argv[1], sys.argv[2]] + os.environ.get('PTY_OPTS', '').split()
keys = [k.encode().decode('unicode_escape').encode('latin-1') for k in sys.argv[3:]]
env = dict(os.environ)
env.pop('HIKARI_TEST_TTY', None)
pid, fd = pty.fork()
if pid == 0:
    os.execve(argv[0], argv, env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 100, 0, 0))
out = b''
def drain(t):
    global out
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return False
            if not data:
                return False
            out += data
    return True
alive = drain(1.5)
for k in keys:
    if not alive:
        break
    os.write(fd, k)
    alive = drain(0.8)
end = time.time() + 20
while alive and time.time() < end:
    alive = drain(0.2)
code = None
for _ in range(50):
    p, status = os.waitpid(pid, os.WNOHANG)
    if p:
        code = os.waitstatus_to_exitcode(status)
        break
    time.sleep(0.1)
if code is None:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    code = 124
sys.stdout.write(out.decode('utf-8', 'replace'))
sys.exit(code)
PY
pty_run() {
    local home=$1
    shift
    HOME="$home" HIKARI_LANG=en TMPDIR="$tmp/tmpdir" FAKE="$fake" HIKARI_TEST_OVERRIDES="$tmp/overrides.sh" TERM=xterm \
        PTY_OPTS="${PTY_OPTS:-}" python3 -I "$tmp/pty.py" "$under" "$copy" "$@" >"$out" 2>&1
    rc=$?
    shell_errors
}

h=$(newhome menu)
cfg="$h/.config/mpv"
# Main menu: Enter (install); folders: Enter (the highlighted one); Anime4K: n.
pty_run "$h" '\r' '\r' 'n'
check 'menus: install through the keyboard menus' test "$rc" = 0 -a -f "$cfg/hikari-installed.txt"
check 'menus: help line shown' has "$out" '↑/↓ to move · Enter to choose · Esc to exit'
check 'menus: N answered no (Anime4K declined)' test "$(rec "$cfg" anime4k)" = declined
check 'menus: the terminal is put back (cursor shown again)' has "$out" $'\033[?25h'
# Down, Enter (uninstall); Space ticks the folder, Enter; Esc answers No to everything.
pty_run "$h" '\x1b[B' '\r' ' ' '\r' '\x1b' '\x1b' '\x1b' '\x1b' '\x1b' '\x1b'
check 'menus: uninstall with arrows and Space, Esc = No' test "$rc" = 0 -a ! -e "$cfg/hikari-installed.txt" -a -f "$cfg/hikari-palette.conf"
check 'menus: Esc kept uosc (No to "Remove uosc too?")' test -d "$cfg/scripts/uosc"
pty_run "$h" '\x1b'
check 'menus: Esc at the first menu leaves' test "$rc" = 0 -a -n "$(grep Cancelled "$out")"
pty_run "$h" '\x03'
check 'menus: Ctrl+C in a menu acts as Esc' test "$rc" = 0
pty_run "$h" '2'
check 'menus: digit hotkey 2 = uninstall' has "$out" 'hikari does not seem to be installed'
# --no-menu on a terminal: numbers and typed answers.
h=$(newhome nomenu)
PTY_OPTS='--no-menu' pty_run "$h" '0\r'
check 'menus: --no-menu asks with numbers on a terminal' test "$rc" = 0 -a -n "$(grep 'Choose an option:' "$out")"

check 'no shell error in any run' test ! -s "$tmp/shell-errors.log"
[ ! -s "$tmp/shell-errors.log" ] || sed 's/^/     | /' "$tmp/shell-errors.log"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
