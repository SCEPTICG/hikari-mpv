# Development

How to run the tests and how a hikari release is made. For what hikari is and how to install it, see the [README](../README.md).

## Tests

From the repository root:

```
lua tests/test_palettes.lua
lua tests/test_title.lua
lua tests/test_speed.lua
lua tests/test_skip.lua
lua tests/test_subs.lua
lua tests/test_upscale.lua
lua tests/test_update.lua
pwsh -NoProfile -File tests/install.Tests.ps1
bash tests/install.test.sh
bash tests/make-release.test.sh
```

The installer tests need PowerShell 7 (on any system, no Pester) and simulate Windows folders, so they run on Linux too; they do not download anything. Some of them start a new `pwsh` and run the installer through `iex`, as a user would, to check that it neither exits nor leaves anything behind in the session. `tests/install.test.sh` tests `install/hikari.sh` with fake home folders and fake downloads (no network, no real config), including a copy of a real Mac config, the keyboard menus (through a pseudo-terminal) and a run without a terminal; it needs `python3`. It runs the installer with the same `bash` that runs it, so run it also with a `bash` 3.2 (the one of macOS) to check the installer there: `/path/to/bash-3.2/bash tests/install.test.sh`. `tests/make-release.test.sh` builds a release in a throw-away copy of the repository and installs hikari from it, through `iex` and through `bash -s` as `curl ... | bash` does. To test the move from sosc, both installer test files also run the real installer of sosc 0.3.0, taken from the `v0.3.0` tag with `git` (skipped in a copy without that tag), and then install and uninstall hikari over it.

## Making a release

The one-line installs download `https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1` and `.../hikari.sh`, which only works when every step below is done. For a release `v0.1.0`:

1. Commit everything and tag that commit. The tag must exist before building and point to the current commit, or the script refuses:

   ```
   git tag v0.1.0
   tools/make-release.sh v0.1.0
   ```

   It needs a clean work tree and builds, from that commit, `dist/hikari.zip` (`portable_config/`, `LICENSE`, `README.md`), `dist/hikari.ps1` (the installer with the version, the URL `https://github.com/SCEPTICG/hikari-mpv/releases/download/v0.1.0/hikari.zip` and that zip's SHA256 filled in), `dist/hikari.sh` (the macOS and Linux installer, with the same three values) and `dist/SHA256SUMS`. It uploads nothing; `dist/` is not tracked.

2. Push the tag to the original repository: `git push origin v0.1.0`. The GitHub repository is a mirror of a Forgejo one (see [Contributing](../README.md#contributing)), so the tag reaches GitHub through the mirror: wait until `v0.1.0` shows up in GitHub's tag list (or sync the mirror by hand) before the next step.

3. On GitHub, create the release **from that existing tag** (choose `v0.1.0` in the tag list; do not let GitHub create a new tag, which would point to the tip of the default branch instead of the commit the files were built from).

4. Attach `dist/hikari.ps1`, `dist/hikari.sh`, `dist/hikari.zip` and `dist/SHA256SUMS` with exactly those names: `hikari.ps1` and `hikari.sh` look for `hikari.zip` under that tag, and the install lines look for `hikari.ps1` and `hikari.sh`.

5. Publish it as the **Latest** release: not a draft and not a pre-release. `releases/latest/download/...` only sees the release marked Latest.

To try it before it becomes the Latest release, publish it first as a pre-release (a draft cannot be downloaded) and use the fixed address of its files, which works for any published release; then mark it Latest:

```
irm https://github.com/SCEPTICG/hikari-mpv/releases/download/v0.1.0/hikari.ps1 | iex
```

