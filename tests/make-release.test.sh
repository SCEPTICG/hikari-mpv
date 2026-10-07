#!/usr/bin/env bash
# Tests for tools/make-release.sh. Run from anywhere:
#   bash tests/make-release.test.sh
# Builds a throw-away git repository from the current work tree, runs the release
# script there (good and bad cases) and installs sosc from the dist/ it made:
# dist/sosc.ps1 run through iex, and dist/sosc.sh piped into bash (as
# curl ... | bash does), their sosc.zip served by a fake downloader. Only the
# uosc and thumbfast hashes of those copies are swapped for fake files, so
# nothing is downloaded; the release URL and hash of the zip are the real ones.
# Anime4K is swapped the same way (a fake zip with the shader names sosc needs).
# Exit code 0 when everything passes. Needs git, unzip, python3 and pwsh.
# Runs with bash 3.2 too (the installer is then piped into that bash).
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pwsh_bin="${PWSH:-}"
if [[ -z "$pwsh_bin" ]]; then
    if command -v pwsh >/dev/null 2>&1; then pwsh_bin="$(command -v pwsh)"
    else pwsh_bin="$HOME/.local/opt/powershell/pwsh"
    fi
fi
export PWSH="$pwsh_bin"

passed=0
failed=0
ok() { passed=$((passed + 1)); printf 'ok   %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; }
check() { # check <name> <command...>
    local name="$1"; shift
    if "$@"; then ok "$name"; else fail "$name"; fi
}
fails() { # fails <name> <message part> <command...>: must exit non-zero saying that
    local name="$1" want="$2" out; shift 2
    if out="$("$@" 2>&1)"; then fail "$name (it did not fail)"; return; fi
    if [[ "$out" == *"$want"* ]]; then ok "$name"; else fail "$name (said: $out)"; fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Throw-away repository with the current files (tracked and new, not ignored).
work="$tmp/repo"
mkdir -p "$work"
(cd "$repo" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | tar -xf - -C "$work"
cd "$work" || exit 1
git init -q
git -c user.name=test -c user.email=test@example.invalid add -A
git -c user.name=test -c user.email=test@example.invalid commit -q -m 'release test'
base="$(git rev-parse HEAD)"
commit_as() { git -c user.name=test -c user.email=test@example.invalid commit -q -am "$1"; }

# --- refused before building anything --------------------------------------
for bad in v1.2 1.2.3 v1.2.3-rc1 v01.2.3 'v1.2.3 ' ''; do
    fails "refuses tag '$bad'" 'must look like vX.Y.Z' tools/make-release.sh "$bad"
done
fails 'refuses two arguments' 'usage:' tools/make-release.sh v1.2.3 v1.2.4
check 'nothing built after the refusals' test ! -e dist/sosc.ps1

echo '# local change' >>README.md
fails 'refuses a modified work tree' 'not clean' tools/make-release.sh v1.2.3
git checkout -q -- README.md
touch stray.txt
fails 'refuses an untracked file' 'not clean' tools/make-release.sh v1.2.3
rm -f stray.txt

fails 'refuses a tag that does not exist' 'does not exist' tools/make-release.sh v1.2.3
check 'nothing built without a tag' test ! -e dist/sosc.ps1

git tag v0.0.1 "$base"
echo '# next' >>README.md
commit_as 'next commit'
fails 'refuses a tag that points elsewhere' 'not to HEAD' tools/make-release.sh v0.0.1
git reset -q --hard "$base"
git tag -d v0.0.1 >/dev/null
git tag v1.2.3 "$base"

sed -i "s/^\$script:SoscReleaseUrl = ''\$/\$script:SoscReleaseUrl = '' # changed/" install/sosc.ps1
commit_as 'marker changed'
git tag -f v1.2.3 >/dev/null
fails 'refuses a missing marker' 'found 1, 0 and 1 times' tools/make-release.sh v1.2.3
check 'no dist/sosc.ps1 when a marker is missing' test ! -e dist/sosc.ps1
git reset -q --hard "$base"
git tag -f v1.2.3 "$base" >/dev/null

printf "\n\$script:SoscReleaseSha256 = ''\n" >>install/sosc.ps1
commit_as 'marker twice'
git tag -f v1.2.3 >/dev/null
fails 'refuses a repeated marker' 'found 1, 1 and 2 times' tools/make-release.sh v1.2.3
git reset -q --hard "$base"
git tag -f v1.2.3 "$base" >/dev/null

sed "s/^    SOSC_RELEASE_URL=''\$/    SOSC_RELEASE_URL='' # changed/" install/sosc.sh >install/sosc.sh.new && mv install/sosc.sh.new install/sosc.sh
commit_as 'sosc.sh marker changed'
git tag -f v1.2.3 >/dev/null
fails 'refuses a missing sosc.sh marker' 'sosc.sh release markers found 1, 0 and 1 times' tools/make-release.sh v1.2.3
check 'nothing left in dist when a sosc.sh marker is missing' test ! -e dist/sosc.ps1 -a ! -e dist/sosc.sh -a ! -e dist/sosc.zip
git reset -q --hard "$base"
git tag -f v1.2.3 "$base" >/dev/null

printf "\n    SOSC_VERSION='dev'\n" >>install/sosc.sh
commit_as 'sosc.sh marker twice'
git tag -f v1.2.3 >/dev/null
fails 'refuses a repeated sosc.sh marker' 'sosc.sh release markers found 2, 1 and 1 times' tools/make-release.sh v1.2.3
git reset -q --hard "$base"
git tag -f v1.2.3 "$base" >/dev/null

# --- a good release ----------------------------------------------------------
if tools/make-release.sh v1.2.3 >"$tmp/out.txt" 2>&1; then ok 'builds v1.2.3'; else fail 'builds v1.2.3'; cat "$tmp/out.txt"; fi
check 'dist has the four files' test -f dist/sosc.zip -a -f dist/sosc.ps1 -a -f dist/sosc.sh -a -f dist/SHA256SUMS
check 'SHA256SUMS matches the three files' bash -c 'cd dist && sha256sum --quiet -c SHA256SUMS'
check 'SHA256SUMS lists sosc.ps1, sosc.sh and sosc.zip' bash -c "cut -d' ' -f3 dist/SHA256SUMS | tr '\n' ' ' | grep -qx 'sosc.ps1 sosc.sh sosc.zip '"
check 'the work tree is still clean' test -z "$(git status --porcelain)"

zip_sha="$(sha256sum dist/sosc.zip | cut -d' ' -f1)"
url='https://github.com/SCEPTICG/sosc/releases/download/v1.2.3/sosc.zip'
check 'version marker' grep -qFx "\$script:SoscVersion = '1.2.3'" dist/sosc.ps1
check 'URL marker' grep -qFx "\$script:SoscReleaseUrl = '$url'" dist/sosc.ps1
check 'hash marker is the zip hash' grep -qFx "\$script:SoscReleaseSha256 = '$zip_sha'" dist/sosc.ps1
check 'only those three lines changed' test "$(diff install/sosc.ps1 dist/sosc.ps1 | grep -c '^[<>]')" = 6
check 'dist/sosc.ps1 is ASCII' test "$(LC_ALL=C tr -d '\000-\177' <dist/sosc.ps1 | wc -c)" = 0
check 'sosc.sh version marker' grep -qFx "    SOSC_VERSION='1.2.3'" dist/sosc.sh
check 'sosc.sh URL marker' grep -qFx "    SOSC_RELEASE_URL='$url'" dist/sosc.sh
check 'sosc.sh hash marker is the zip hash' grep -qFx "    SOSC_RELEASE_SHA256='$zip_sha'" dist/sosc.sh
check 'sosc.sh: only those three lines changed' test "$(diff install/sosc.sh dist/sosc.sh | grep -c '^[<>]')" = 6
check 'sosc.sh: the last line still calls main' test "$(tail -n 1 dist/sosc.sh)" = '{ main "$@"; }'

unzip -Z1 dist/sosc.zip | grep -v '/$' | sort >"$tmp/zip.txt"
git ls-files portable_config LICENSE README.md | sort >"$tmp/want.txt"
check 'zip holds exactly portable_config, LICENSE and README.md' cmp -s "$tmp/zip.txt" "$tmp/want.txt"
check 'zip has no install, tests or tools' bash -c "! grep -qE '^(install|tests|tools)/' '$tmp/zip.txt'"

cp dist/sosc.zip "$tmp/first.zip"
tools/make-release.sh v1.2.3 >/dev/null 2>&1
check 'same commit, same zip (reproducible)' cmp -s dist/sosc.zip "$tmp/first.zip"

# --- install from that release, through iex --------------------------------
fake="$tmp/fake"
mkdir -p "$fake/uosc/scripts/uosc" "$fake/uosc/fonts"
echo '-- fake uosc main' >"$fake/uosc/scripts/uosc/main.lua"
echo 'icons' >"$fake/uosc/fonts/uosc_icons.otf"
(cd "$fake/uosc" && python3 -c 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],"w"); [z.write(p) for p in sys.argv[2:]]; z.close()' \
    "$fake/uosc.zip" scripts/uosc/main.lua fonts/uosc_icons.otf)
echo '-- fake thumbfast' >"$fake/thumbfast.lua"
# Anime4K: every name the installer requires, flat, like the real zip.
a4k_names=()
while IFS= read -r n; do a4k_names[${#a4k_names[@]}]=$n; done < <(sed -n "/^\$script:Anime4KRequired = @(/,/^)/p" dist/sosc.ps1 | grep -o "Anime4K_[A-Za-z0-9_]*\.glsl")
python3 - "$fake/anime4k.zip" "${a4k_names[@]}" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], 'w')
for name in sys.argv[2:]:
    z.writestr(name, '// fake ' + name)
z.close()
PY
uosc_url="$(sed -n "s/^\$script:UoscUrl = '\(.*\)'\$/\1/p" dist/sosc.ps1)"
thumb_url="$(sed -n "s/^\$script:ThumbfastUrl = '\(.*\)'\$/\1/p" dist/sosc.ps1)"
a4k_url="$(sed -n "s/^\$script:Anime4KUrl = '\(.*\)'\$/\1/p" dist/sosc.ps1)"
sed -e "s/^\(\$script:UoscSha256 = '\)[0-9a-f]\{64\}'\$/\1$(sha256sum "$fake/uosc.zip" | cut -d' ' -f1)'/" \
    -e "s/^\(\$script:ThumbfastSha256 = '\)[0-9a-f]\{64\}'\$/\1$(sha256sum "$fake/thumbfast.lua" | cut -d' ' -f1)'/" \
    -e "s/^\(\$script:Anime4KSha256 = '\)[0-9a-f]\{64\}'\$/\1$(sha256sum "$fake/anime4k.zip" | cut -d' ' -f1)'/" \
    dist/sosc.ps1 >"$tmp/sosc-test.ps1"
check 'Anime4K: 14 required shaders found in dist/sosc.ps1' test "${#a4k_names[@]}" = 14
check 'test copy differs from dist/sosc.ps1 only in the uosc, thumbfast and Anime4K hashes' \
    test "$(diff dist/sosc.ps1 "$tmp/sosc-test.ps1" | grep -c '^>')" = 3
python3 - "$tmp/dl.json" "$url" "$work/dist/sosc.zip" "$uosc_url" "$fake/uosc.zip" "$thumb_url" "$fake/thumbfast.lua" "$a4k_url" "$fake/anime4k.zip" <<'EOF'
import json, sys
a = sys.argv
json.dump({a[2]: a[3], a[4]: a[5], a[6]: a[7], a[8]: a[9]}, open(a[1], 'w'))
EOF

cfg="$tmp/target/mpv"
mkdir -p "$tmp/target" "$tmp/tmpdir"
# Install, "type the config folder myself" (no player here), the folder, then
# yes to Anime4K.
printf '1\n2\n%s\ny\n' "$cfg" | TMPDIR="$tmp/tmpdir" SOSC_LANG=en "$pwsh_bin" -NoProfile -Command \
    ". '$repo/tests/iex-harness.ps1' -Script '$tmp/sosc-test.ps1' -Report '$tmp/report.json' -Downloads '$tmp/dl.json' -Mode iex" \
    >"$tmp/install.txt" 2>&1
if [[ -f "$tmp/report.json" ]]; then ok 'iex run returned (no exit)'; else fail 'iex run returned (no exit)'; cat "$tmp/install.txt"; fi
# report <key> [index]: a value of the harness report; for a list, its length
# or (with an index) one element.
report() {
    python3 - "$tmp/report.json" "$@" 2>/dev/null <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding='utf-8-sig'))[sys.argv[2]]
if isinstance(value, list):
    value = value[int(sys.argv[3])] if len(sys.argv) > 3 else len(value)
print(value)
PY
}
check 'exit code 0' test "$(report ExitCode)" = 0
check 'release zip downloaded first' test "$(report Downloads 0)" = "$url"
check 'nothing left in the session' test "$(report NewVariables)$(report NewFunctions)$(report NewModules)" = 000
all_same=true
for f in "$work"/portable_config/scripts/*.lua "$work"/portable_config/script-opts/sosc-*.conf; do
    rel="${f#"$work"/portable_config/}"
    cmp -s "$f" "$cfg/$rel" || { all_same=false; echo "     differs: $rel"; }
done
check 'installed sosc files are the committed ones' $all_same
check 'record says 1.2.3' grep -q '^sosc_version=1.2.3' "$cfg/sosc-installed.txt"
check 'mpv.conf has the sosc block and nothing personal' bash -c "grep -q '^include=\"~~/sosc-subs.conf\"' '$cfg/mpv.conf' && ! grep -qE 'alang|slang|border=no' '$cfg/mpv.conf'"
check 'Anime4K installed from its (fake) zip' test -f "$cfg/shaders/Anime4K_Clamp_Highlights.glsl"
check 'sosc-upscale.conf written, in Automatico (Anime4K installed)' grep -q '^script-opts-append=sosc_upscale-mode=auto' "$cfg/sosc-upscale.conf"
check 'temporary folder removed' test -z "$(ls -A "$tmp/tmpdir")"

# --- install from that release: dist/sosc.sh piped into bash ----------------
# The same fakes; the release zip is the real dist/sosc.zip with its real hash.
# The copy only differs in the three hashes and one line, before the call to
# main, that loads the replacements of the downloader and the system probes.
bash_bin=${SOSC_TEST_BASH:-$BASH}
sh_sha() { sha256sum "$1" | cut -d' ' -f1; }
sed -e "s/^\(    UOSC_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sh_sha "$fake/uosc.zip")'/" \
    -e "s/^\(    THUMBFAST_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sh_sha "$fake/thumbfast.lua")'/" \
    -e "s/^\(    ANIME4K_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sh_sha "$fake/anime4k.zip")'/" \
    -e '$d' dist/sosc.sh >"$tmp/sosc-test.sh"
printf '. "%s"\n' "$tmp/overrides.sh" >>"$tmp/sosc-test.sh"
tail -n 1 dist/sosc.sh >>"$tmp/sosc-test.sh"
check 'sosc.sh test copy differs only in the three hashes and the overrides line' \
    test "$(diff dist/sosc.sh "$tmp/sosc-test.sh" | grep -c '^>')" = 4
cat >"$tmp/overrides.sh" <<EOF
sosc_fetch() {
    printf '%s\\n' "\$1" >>"$tmp/sh-downloads.log"
    case \$1 in
        '$url') cp '$work/dist/sosc.zip' "\$2" ;;
        '$uosc_url') cp '$fake/uosc.zip' "\$2" ;;
        '$thumb_url') cp '$fake/thumbfast.lua' "\$2" ;;
        '$a4k_url') cp '$fake/anime4k.zip' "\$2" ;;
        *) return 22 ;;
    esac
}
sosc_uname() { printf Darwin; }
sosc_cpu_brand() { printf 'Apple M5'; }
sosc_find_mpv() { printf /opt/homebrew/bin/mpv; }
sosc_brew() { :; }
sosc_iina() { return 1; }
sosc_tty_path() { :; }
EOF
home="$tmp/home-sh"
mkdir -p "$home" "$tmp/tmpdir-sh"
(cd "$tmp" && HOME="$home" TMPDIR="$tmp/tmpdir-sh" SOSC_LANG=en "$bash_bin" -s -- --yes --anime4k yes <"$tmp/sosc-test.sh") >"$tmp/sh-install.txt" 2>&1
rc=$?
if [[ $rc == 0 ]]; then ok 'curl | bash: exit code 0'; else fail "curl | bash: exit code $rc"; cat "$tmp/sh-install.txt"; fi
shcfg="$home/.config/mpv"
check 'curl | bash: release zip downloaded first' test "$(head -n 1 "$tmp/sh-downloads.log" 2>/dev/null)" = "$url"
all_same=true
for f in "$work"/portable_config/scripts/*.lua "$work"/portable_config/script-opts/sosc-*.conf; do
    rel="${f#"$work"/portable_config/}"
    cmp -s "$f" "$shcfg/$rel" || { all_same=false; echo "     differs: $rel"; }
done
check 'curl | bash: installed sosc files are the committed ones' $all_same
check 'curl | bash: record says 1.2.3' grep -q '^sosc_version=1.2.3$' "$shcfg/sosc-installed.txt"
check 'curl | bash: Anime4K in Automatico' grep -q '^script-opts-append=sosc_upscale-mode=auto$' "$shcfg/sosc-upscale.conf"
check 'curl | bash: temporary folder removed' test -z "$(ls -A "$tmp/tmpdir-sh")"
# A download cut short: the call to main is missing, so nothing runs.
home2="$tmp/home-cut"
mkdir -p "$home2"
head -c 30000 dist/sosc.sh | (cd "$tmp" && HOME="$home2" SOSC_LANG=en "$bash_bin" -s -- --yes) >/dev/null 2>&1
check 'a download cut short does nothing' test -z "$(ls -A "$home2")"
# Cut inside the last line, byte by byte ("{ main", "{ main ", "{ main \"$@\"; "...):
# a syntax error every time, main never runs. Only the final line break can go.
size=$(wc -c <dist/sosc.sh | tr -d ' ')
cut_ran=''
for n in 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17; do
    head -c $((size - n)) dist/sosc.sh | (cd "$tmp" && HOME="$home2" SOSC_LANG=en "$bash_bin" -s -- --help) >"$tmp/cut.txt" 2>&1
    if grep -q 'Usage' "$tmp/cut.txt" || [ -n "$(ls -A "$home2")" ]; then cut_ran="$cut_ran $n"; fi
done
check 'a download cut inside the last line never calls main' test -z "$cut_ran"
head -c $((size - 1)) dist/sosc.sh | (cd "$tmp" && HOME="$home2" SOSC_LANG=en "$bash_bin" -s -- --help) >"$tmp/cut.txt" 2>&1
check 'without only its final line break it still runs (the check above can see main)' grep -q 'Usage' "$tmp/cut.txt"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
