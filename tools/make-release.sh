#!/usr/bin/env bash
# Builds the files of a hikari release in dist/. It uploads nothing.
#
#   tools/make-release.sh vX.Y.Z
#   tools/make-release.sh preview
#
#   dist/hikari.zip   portable_config/, LICENSE and README.md of the current commit
#                     (git archive: the committed files, nothing from the work tree)
#   dist/hikari.ps1   install/hikari.ps1 of the current commit with its three release
#                     markers filled in: the version, the URL of this release's
#                     hikari.zip and that zip's SHA256
#   dist/hikari.sh    install/hikari.sh (macOS and Linux) of the current commit,
#                     with the same three markers filled in
#   dist/SHA256SUMS   SHA256 of the three files
#
# The tag vX.Y.Z must already exist and point to the current commit. Then push
# the tag, create the GitHub release of SCEPTICG/hikari-mpv from it, attach
# dist/hikari.ps1, dist/hikari.sh, dist/hikari.zip and dist/SHA256SUMS with those names
# and publish it as Latest (see docs/development.md, "Making a release"). dist/hikari.ps1 and
# dist/hikari.sh only install the hikari.zip published under that same tag, and only
# if its SHA256 matches.
#
# preview builds a test version of the current commit (the dev branch) the same
# way, for the moving tag preview: the tag preview must exist and point to the
# current commit, the files point at .../releases/download/preview/hikari.zip
# and the version written in them is preview-<short commit hash> (e.g.
# preview-ffebb37), so the installers say it is a test version and record which
# build is installed. hikari-update.lua only reads X.Y.Z versions, so a preview
# install never looks for updates (as a copy of the repository, `dev`). It is
# published as a GitHub pre-release, never as Latest (see docs/development.md,
# "Preview builds").
#
# Needs: git, a SHA256 tool (sha256sum or shasum), awk, bash, and PowerShell 7
# (pwsh in PATH, $PWSH, or ~/.local/opt/powershell/pwsh) to check that the
# results parse.
set -euo pipefail

die() { printf 'make-release: %s\n' "$*" >&2; exit 1; }

readonly RELEASE_BASE='https://github.com/SCEPTICG/hikari-mpv/releases/download'

tag="${1:-}"
[[ $# -eq 1 ]] || die "usage: tools/make-release.sh vX.Y.Z | preview"
if [[ "$tag" == preview ]]; then
    preview=1
elif [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    preview=0
else
    die "the tag must look like vX.Y.Z (e.g. v0.1.0) or be preview, not '$tag'"
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ "$(git rev-parse --show-toplevel)" == "$root" ]] || die "$root is not the top of a git repository"

[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
    die "the work tree is not clean (commit or remove the changes first): the release must be exactly a commit"
commit="$(git rev-parse --verify HEAD)"
# The release must be built from the very commit its tag names: the GitHub
# release is created from that tag, and hikari.ps1 points at its hikari.zip.
# preview is a moving tag: it is moved (-f) to each new build.
if [[ $preview == 1 ]]; then tag_cmd="git tag -f $tag" push_cmd="git push -f origin $tag"
else tag_cmd="git tag $tag" push_cmd="git push origin $tag"
fi
git rev-parse -q --verify "refs/tags/$tag" >/dev/null ||
    die "tag $tag does not exist: create it on this commit first ($tag_cmd), build, then push it ($push_cmd)"
# By its full name: a branch called like the tag must not be taken instead.
tagged="$(git rev-parse "refs/tags/$tag^{commit}")"
[[ "$tagged" == "$commit" ]] || die "tag $tag points to $tagged, not to HEAD ($commit): move it first ($tag_cmd)"

if [[ $preview == 1 ]]; then
    version="preview-$(git rev-parse --short=7 HEAD)"
else
    version="${tag#v}"
fi
# Written between single quotes in both installers: only these characters.
[[ "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+|preview-[0-9a-f]{7,40})$ ]] || die "unexpected version '$version'"

if command -v sha256sum >/dev/null 2>&1; then
    sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
    sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
    die "no sha256sum or shasum found"
fi

pwsh_bin="${PWSH:-}"
if [[ -z "$pwsh_bin" ]]; then
    if command -v pwsh >/dev/null 2>&1; then pwsh_bin="$(command -v pwsh)"
    elif [[ -x "$HOME/.local/opt/powershell/pwsh" ]]; then pwsh_bin="$HOME/.local/opt/powershell/pwsh"
    else die "PowerShell 7 (pwsh) not found: set PWSH to its path"
    fi
fi

# What the installer reads from the zip (Get-HikariReleaseSource, Install-HikariTarget):
# portable_config/ with scripts/hikari-*.lua, script-modules/hikari-*.lua (the
# texts every script needs), script-opts/*.conf and the choice files.
# LICENSE and README.md go along for whoever opens the zip.
for f in portable_config/scripts/hikari-palettes.lua portable_config/script-modules/hikari-i18n.lua \
    portable_config/hikari-palette.conf portable_config/hikari-subs.conf portable_config/hikari-language.conf \
    portable_config/script-opts LICENSE README.md install/hikari.ps1 install/hikari.sh; do
    git cat-file -e "HEAD:$f" 2>/dev/null || die "$f is not in the commit"
done

mkdir -p dist
rm -f dist/hikari.zip dist/hikari.ps1 dist/hikari.sh dist/SHA256SUMS dist/hikari.ps1.tmp dist/hikari.sh.tmp

git archive --format=zip -o dist/hikari.zip HEAD -- portable_config LICENSE README.md
zip_sha="$(sha256 dist/hikari.zip)"
[[ "$zip_sha" =~ ^[0-9a-f]{64}$ ]] || die "could not hash dist/hikari.zip"
url="$RELEASE_BASE/$tag/hikari.zip"

# Whole lines, each exactly once. The values are a checked version, a URL built
# from the checked tag and a hex hash: nothing in them can break out of the quotes.
git show "HEAD:install/hikari.ps1" | awk \
    -v m1="\$script:HikariVersion = 'dev'" -v r1="\$script:HikariVersion = '$version'" \
    -v m2="\$script:HikariReleaseUrl = ''" -v r2="\$script:HikariReleaseUrl = '$url'" \
    -v m3="\$script:HikariReleaseSha256 = ''" -v r3="\$script:HikariReleaseSha256 = '$zip_sha'" '
    $0 == m1 { print r1; c1++; next }
    $0 == m2 { print r2; c2++; next }
    $0 == m3 { print r3; c3++; next }
    { print }
    END {
        if (c1 != 1 || c2 != 1 || c3 != 1) {
            printf "make-release: release markers found %d, %d and %d times (each must be there exactly once)\n", c1, c2, c3 > "/dev/stderr"
            exit 1
        }
    }' >dist/hikari.ps1.tmp || { rm -f dist/hikari.ps1.tmp dist/hikari.zip; die "could not fill in the release markers of install/hikari.ps1"; }

changed="$(git show "HEAD:install/hikari.ps1" | diff - dist/hikari.ps1.tmp | grep -c '^>' || true)"
[[ "$changed" == 3 ]] || { rm -f dist/hikari.ps1.tmp dist/hikari.zip; die "expected 3 changed lines in hikari.ps1, got $changed"; }

# Windows PowerShell 5.1 reads a BOM-less script as ANSI: it must stay ASCII.
non_ascii="$(LC_ALL=C tr -d '\000-\177' <dist/hikari.ps1.tmp | wc -c | tr -d ' ')"
[[ "$non_ascii" == 0 ]] || { rm -f dist/hikari.ps1.tmp dist/hikari.zip; die "dist/hikari.ps1 has $non_ascii non-ASCII bytes"; }

# shellcheck disable=SC2016 # PowerShell code, expanded by pwsh.
HIKARI_PARSE_FILE="$root/dist/hikari.ps1.tmp" "$pwsh_bin" -NoProfile -NonInteractive -Command '
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($env:HIKARI_PARSE_FILE, [ref]$null, [ref]$errors)
    if (@($errors).Count -gt 0) { foreach ($e in $errors) { [Console]::Error.WriteLine($e.ToString()) }; exit 1 }
    exit 0' || { rm -f dist/hikari.ps1.tmp dist/hikari.zip; die "dist/hikari.ps1 does not parse"; }

# The same three markers in install/hikari.sh (indented, inside hikari_defaults).
cleanup_sh() { rm -f dist/hikari.ps1.tmp dist/hikari.sh.tmp dist/hikari.zip; }
git show "HEAD:install/hikari.sh" | awk \
    -v m1="    HIKARI_VERSION='dev'" -v r1="    HIKARI_VERSION='$version'" \
    -v m2="    HIKARI_RELEASE_URL=''" -v r2="    HIKARI_RELEASE_URL='$url'" \
    -v m3="    HIKARI_RELEASE_SHA256=''" -v r3="    HIKARI_RELEASE_SHA256='$zip_sha'" '
    $0 == m1 { print r1; c1++; next }
    $0 == m2 { print r2; c2++; next }
    $0 == m3 { print r3; c3++; next }
    { print }
    END {
        if (c1 != 1 || c2 != 1 || c3 != 1) {
            printf "make-release: hikari.sh release markers found %d, %d and %d times (each must be there exactly once)\n", c1, c2, c3 > "/dev/stderr"
            exit 1
        }
    }' >dist/hikari.sh.tmp || { cleanup_sh; die "could not fill in the release markers of install/hikari.sh"; }

changed="$(git show "HEAD:install/hikari.sh" | diff - dist/hikari.sh.tmp | grep -c '^>' || true)"
[[ "$changed" == 3 ]] || { cleanup_sh; die "expected 3 changed lines in hikari.sh, got $changed"; }
# The last line must still be the call to main, in braces: a download cut short
# (even inside that line) runs nothing.
# shellcheck disable=SC2016 # the line itself, not an expansion.
[[ "$(tail -n 1 dist/hikari.sh.tmp)" == '{ main "$@"; }' ]] || { cleanup_sh; die "dist/hikari.sh does not end with the call to main"; }
bash -n dist/hikari.sh.tmp || { cleanup_sh; die "dist/hikari.sh does not parse"; }

mv dist/hikari.ps1.tmp dist/hikari.ps1
mv dist/hikari.sh.tmp dist/hikari.sh
ps1_sha="$(sha256 dist/hikari.ps1)"
sh_sha="$(sha256 dist/hikari.sh)"
printf '%s  hikari.ps1\n%s  hikari.sh\n%s  hikari.zip\n' "$ps1_sha" "$sh_sha" "$zip_sha" >dist/SHA256SUMS

cat <<EOF
hikari $version ($tag) built from commit $commit:
  dist/hikari.ps1  $ps1_sha
  dist/hikari.sh   $sh_sha
  dist/hikari.zip  $zip_sha
  dist/SHA256SUMS
hikari.ps1 and hikari.sh install from $url
EOF
if [[ $preview == 1 ]]; then
    cat <<EOF
Nothing was uploaded. Next: $push_cmd, wait until GitHub has the moved tag,
delete the old preview release, create it again from that tag, attach the four
files with these names and publish it as a pre-release (never as Latest).
EOF
else
    cat <<EOF
Nothing was uploaded. Next: $push_cmd, create the GitHub release
from that tag, attach the four files with these names, publish it as Latest.
EOF
fi
