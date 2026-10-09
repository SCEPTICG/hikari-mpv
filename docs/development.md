---
title: "hikari development: tests and releases"
description: "How to run hikari's tests and how a release of the mpv theme is made."
---

# Development

How to run the tests and how a hikari release is made. For what hikari is and how to install it, see the [home page](index.md).

## Tests

From the repository root:

```
for f in tests/test_*.lua; do lua "$f"; done
pwsh -NoProfile -File tests/install.Tests.ps1
bash tests/install.test.sh
bash tests/make-release.test.sh
```

The Lua tests (`test_i18n`, `test_language`, `test_media_language`, `test_palettes`, `test_skip`, `test_speed`, `test_subs`, `test_title`, `test_update`, `test_upscale`) load each script with a small stand-in for mpv's API (`tests/mock_mp.lua`); they need Lua 5.1 or LuaJIT, as mpv uses. When `lua` is there, both installer test files also check that the installers write `hikari-language.conf` byte for byte as `hikari-language.lua` does, and read locale names with the same rules as `hikari-i18n.lua`.

The installer tests need PowerShell 7 (on any system, no Pester) and simulate Windows folders, so they run on Linux too; they do not download anything. Some of them start a new `pwsh` and run the installer through `iex`, as a user would, to check that it neither exits nor leaves anything behind in the session. `tests/install.test.sh` tests `install/hikari.sh` with fake home folders and fake downloads (no network, no real config), including a copy of a real Mac config, the keyboard menus (through a pseudo-terminal) and a run without a terminal; it needs `python3`. It runs the installer with the same `bash` that runs it, so run it also with a `bash` 3.2 (the one of macOS) to check the installer there: `/path/to/bash-3.2/bash tests/install.test.sh`. `tests/make-release.test.sh` builds a release in a throw-away copy of the repository and installs hikari from it, through `iex` and through `bash -s` as `curl ... | bash` does. To test the move from sosc, both installer test files also run the real installer of sosc 0.3.0, taken from the `v0.3.0` tag with `git` (skipped in a copy without that tag), and then install and uninstall hikari over it.

## Translations

Every text hikari shows in mpv lives in `portable_config/script-modules/hikari-i18n.lua`, one entry per text with all 13 languages side by side (`en` is required, the others fall back to it). Scripts get them with `i18n.t('key', {name = value})`; placeholders are `{name}`. `tests/test_i18n.lua` checks that every text has every language (except the few title labels that use the English form on purpose), keeps the placeholders of the English text, and that button tooltips have no `,` or `?`. The module is loaded with the same few lines at the top of every script (single-file mpv scripts get no mpv folder in Lua's `package.path`); the tests check that all of them are identical.

## Making a release

The one-line installs download `https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1` and `.../hikari.sh`, which only works when every step below is done. For a release `v0.1.0`:

1. Commit everything and tag that commit. The tag must exist before building and point to the current commit, or the script refuses:

   ```
   git tag v0.1.0
   tools/make-release.sh v0.1.0
   ```

   It needs a clean work tree and builds, from that commit, `dist/hikari.zip` (`portable_config/`, `LICENSE`, `README.md`), `dist/hikari.ps1` (the installer with the version, the URL `https://github.com/SCEPTICG/hikari-mpv/releases/download/v0.1.0/hikari.zip` and that zip's SHA256 filled in), `dist/hikari.sh` (the macOS and Linux installer, with the same three values) and `dist/SHA256SUMS`. It uploads nothing; `dist/` is not tracked.

2. Push the tag (`git push origin v0.1.0`) and wait until `v0.1.0` shows up in GitHub's tag list before the next step.

3. On GitHub, create the release **from that existing tag** (choose `v0.1.0` in the tag list; do not let GitHub create a new tag, which would point to the tip of the default branch instead of the commit the files were built from).

4. Attach `dist/hikari.ps1`, `dist/hikari.sh`, `dist/hikari.zip` and `dist/SHA256SUMS` with exactly those names: `hikari.ps1` and `hikari.sh` look for `hikari.zip` under that tag, and the install lines look for `hikari.ps1` and `hikari.sh`.

5. Publish it as the **Latest** release: not a draft and not a pre-release. `releases/latest/download/...` only sees the release marked Latest.

To try it before it becomes the Latest release, publish it first as a pre-release (a draft cannot be downloaded) and use the fixed address of its files, which works for any published release; then mark it Latest:

```
irm https://github.com/SCEPTICG/hikari-mpv/releases/download/v0.1.0/hikari.ps1 | iex
```


## Preview builds

To try the `dev` branch on real machines before a release, there is a test channel: a GitHub **pre-release** under the moving tag `preview`, with the same four files as a release and the same SHA256 check. It is for testing only; it is not on the public install pages.

```
irm https://github.com/SCEPTICG/hikari-mpv/releases/download/preview/hikari.ps1 | iex
curl -fsSL https://github.com/SCEPTICG/hikari-mpv/releases/download/preview/hikari.sh | bash
```

The version written in the installers is `preview-` and the short hash of the commit (e.g. `preview-ffebb37`), so `hikari-installed.txt` tells which build is installed. The installers say it when they start: `Preview build (preview-ffebb37). To go back to the stable version:` and the usual install line. That version is not `X.Y.Z`, so `hikari-update.lua` does not look for updates on a preview install (as with a copy of the repository, `dev`). To go back, run the normal install line: the stable version installs over a preview (there is no version check), removes the hikari files the preview had and it does not, and keeps the palette, subtitle, upscaling and language choices.

To publish a new preview build:

1. Merge the work into `dev` and check it out, with a clean work tree.

2. Move the tag to that commit and build. The tag must point to the current commit, or the script refuses:

   ```
   git tag -f preview
   tools/make-release.sh preview
   ```

   It checks and builds the same files as for a release, with `https://github.com/SCEPTICG/hikari-mpv/releases/download/preview/hikari.zip` as the address of the zip.

3. Push the moved tag (`git push -f origin preview`) and wait until GitHub (through the mirror) has `preview` on the new commit.

4. On GitHub, delete the previous `preview` release (its files would otherwise stay attached), then create it again **from the existing tag** `preview`, attach `dist/hikari.ps1`, `dist/hikari.sh`, `dist/hikari.zip` and `dist/SHA256SUMS` with those names, and publish it as a **pre-release**. Never mark it Latest: `releases/latest` must keep pointing at the stable version.
