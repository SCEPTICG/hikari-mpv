# Security policy

## Supported versions

Only the latest release of hikari gets fixes. The install line always installs the latest release, so running it again is how you update.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately instead: on GitHub, open the **Security** tab of [SCEPTICG/hikari-mpv](https://github.com/SCEPTICG/hikari-mpv/security) and choose **Report a vulnerability**.

Useful details: your system, your player (mpv, mpv.net, AnimeJaNai...), the hikari version (`hikari_version=` in `hikari-installed.txt`, in your mpv config folder) and the steps to reproduce it.

hikari is maintained by one person in their spare time. You can expect an answer within a week; a fix, once confirmed, goes into a new release, and the report is credited in its notes unless you prefer otherwise.

## Scope

In scope: the installers (`hikari.ps1`, `hikari.sh`), hikari's own Lua scripts and modules, and the release files.

uosc, thumbfast and Anime4K are separate projects that the installer downloads from their official sources at fixed versions, each checked against its SHA256. A problem in one of them should be reported to that project; if hikari's pinned version is affected, tell us too and the pin will be updated.

## How releases are checked

Every download the installer makes is pinned and checked against a SHA256 written inside the installer. The installer itself cannot check itself: see "Checking the installer first" in the [Windows](https://scepticg.github.io/hikari-mpv/install/windows/) and [macOS and Linux](https://scepticg.github.io/hikari-mpv/install/macos-linux/) install pages to verify it against the release's `SHA256SUMS` before running it, and what that check does and does not prove.
