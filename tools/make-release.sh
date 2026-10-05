#!/usr/bin/env bash
# Builds the files of a sosc release in dist/. It uploads nothing.
#
#   tools/make-release.sh vX.Y.Z
#
#   dist/sosc.zip     portable_config/, LICENSE and README.md of the current commit
#                     (git archive: the committed files, nothing from the work tree)
#   dist/sosc.ps1     install/sosc.ps1 of the current commit with its three release
#                     markers filled in: the version, the URL of this release's
#                     sosc.zip and that zip's SHA256
#   dist/SHA256SUMS   SHA256 of both files
#
# Then attach dist/sosc.ps1 and dist/sosc.zip (and SHA256SUMS) to the GitHub
# release vX.Y.Z of SCEPTICG/sosc. dist/sosc.ps1 only installs the sosc.zip
# published under that same tag, and only if its SHA256 matches.
#
# Needs: git, a SHA256 tool (sha256sum or shasum), awk and PowerShell 7 (pwsh in
# PATH, $PWSH, or ~/.local/opt/powershell/pwsh) to check that the result parses.
set -euo pipefail

die() { printf 'make-release: %s\n' "$*" >&2; exit 1; }

readonly RELEASE_BASE='https://github.com/SCEPTICG/sosc/releases/download'

tag="${1:-}"
[[ $# -eq 1 ]] || die "usage: tools/make-release.sh vX.Y.Z"
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    die "the tag must look like vX.Y.Z (e.g. v0.1.0), not '$tag'"
version="${tag#v}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ "$(git rev-parse --show-toplevel)" == "$root" ]] || die "$root is not the top of a git repository"

[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
    die "the work tree is not clean (commit or remove the changes first): the release must be exactly a commit"
commit="$(git rev-parse --verify HEAD)"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    tagged="$(git rev-parse "$tag^{commit}")"
    [[ "$tagged" == "$commit" ]] || die "tag $tag already exists and points to $tagged, not to HEAD ($commit)"
fi

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

# What the installer reads from the zip (Get-SoscReleaseSource, Install-SoscTarget):
# portable_config/ with scripts/sosc-*.lua, script-opts/*.conf and the two
# choice files. LICENSE and README.md go along for whoever opens the zip.
for f in portable_config/scripts/sosc-palettes.lua portable_config/sosc-palette.conf \
    portable_config/sosc-subs.conf portable_config/script-opts LICENSE README.md install/sosc.ps1; do
    git cat-file -e "HEAD:$f" 2>/dev/null || die "$f is not in the commit"
done

mkdir -p dist
rm -f dist/sosc.zip dist/sosc.ps1 dist/SHA256SUMS dist/sosc.ps1.tmp

git archive --format=zip -o dist/sosc.zip HEAD -- portable_config LICENSE README.md
zip_sha="$(sha256 dist/sosc.zip)"
[[ "$zip_sha" =~ ^[0-9a-f]{64}$ ]] || die "could not hash dist/sosc.zip"
url="$RELEASE_BASE/$tag/sosc.zip"

# Whole lines, each exactly once. The values are a checked tag, a URL built
# from it and a hex hash: nothing in them can break out of the quotes.
git show "HEAD:install/sosc.ps1" | awk \
    -v m1="\$script:SoscVersion = 'dev'" -v r1="\$script:SoscVersion = '$version'" \
    -v m2="\$script:SoscReleaseUrl = ''" -v r2="\$script:SoscReleaseUrl = '$url'" \
    -v m3="\$script:SoscReleaseSha256 = ''" -v r3="\$script:SoscReleaseSha256 = '$zip_sha'" '
    $0 == m1 { print r1; c1++; next }
    $0 == m2 { print r2; c2++; next }
    $0 == m3 { print r3; c3++; next }
    { print }
    END {
        if (c1 != 1 || c2 != 1 || c3 != 1) {
            printf "make-release: release markers found %d, %d and %d times (each must be there exactly once)\n", c1, c2, c3 > "/dev/stderr"
            exit 1
        }
    }' >dist/sosc.ps1.tmp || { rm -f dist/sosc.ps1.tmp dist/sosc.zip; die "could not fill in the release markers of install/sosc.ps1"; }

changed="$(git show "HEAD:install/sosc.ps1" | diff - dist/sosc.ps1.tmp | grep -c '^>' || true)"
[[ "$changed" == 3 ]] || { rm -f dist/sosc.ps1.tmp dist/sosc.zip; die "expected 3 changed lines in sosc.ps1, got $changed"; }

# Windows PowerShell 5.1 reads a BOM-less script as ANSI: it must stay ASCII.
non_ascii="$(LC_ALL=C tr -d '\000-\177' <dist/sosc.ps1.tmp | wc -c | tr -d ' ')"
[[ "$non_ascii" == 0 ]] || { rm -f dist/sosc.ps1.tmp dist/sosc.zip; die "dist/sosc.ps1 has $non_ascii non-ASCII bytes"; }

# shellcheck disable=SC2016 # PowerShell code, expanded by pwsh.
SOSC_PARSE_FILE="$root/dist/sosc.ps1.tmp" "$pwsh_bin" -NoProfile -NonInteractive -Command '
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($env:SOSC_PARSE_FILE, [ref]$null, [ref]$errors)
    if (@($errors).Count -gt 0) { foreach ($e in $errors) { [Console]::Error.WriteLine($e.ToString()) }; exit 1 }
    exit 0' || { rm -f dist/sosc.ps1.tmp dist/sosc.zip; die "dist/sosc.ps1 does not parse"; }

mv dist/sosc.ps1.tmp dist/sosc.ps1
ps1_sha="$(sha256 dist/sosc.ps1)"
printf '%s  sosc.ps1\n%s  sosc.zip\n' "$ps1_sha" "$zip_sha" >dist/SHA256SUMS

cat <<EOF
sosc $tag built from commit $commit:
  dist/sosc.ps1   $ps1_sha
  dist/sosc.zip   $zip_sha
  dist/SHA256SUMS
sosc.ps1 installs from $url
Nothing was uploaded. Attach the three files to the GitHub release $tag.
EOF
