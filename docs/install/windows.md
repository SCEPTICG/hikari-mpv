---
title: "Install the hikari mpv theme on Windows (mpv, mpv.net, AnimeJaNai)"
description: "Install hikari, a uosc-based theme for mpv, on Windows with one PowerShell line. Works with mpv, mpv.net and AnimeJaNai, backs up your config first and can be uninstalled."
---

# Install on Windows

## Requirements

- **Windows** 10 or 11, **macOS** or **Linux** (the Linux installer is new and still being tested; see [macOS and Linux](../install/macos-linux.md)).
- Windows: a player based on mpv: [mpv](https://mpv.io/installation/), [mpv.net](https://github.com/mpvnet-player/mpv.net), or a bundle built on mpv.net such as [AnimeJaNai](https://github.com/the-database/mpv-upscale-2x_animejanai). If none is installed, the installer offers to install mpv.net with `winget`. Windows PowerShell 5.1 (built into Windows) or PowerShell 7. No administrator rights.
- macOS and Linux: [mpv](https://mpv.io/installation/) (on macOS from Homebrew or mpv.app; on Linux from your distribution, Flatpak or Snap), and `bash`, `curl` and `unzip`, which macOS and most Linux systems already have. No `sudo`.

On Windows, open PowerShell (Start menu, type *PowerShell*) and run (for macOS and Linux, see [macOS and Linux](../install/macos-linux.md)):

```
irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1 | iex
```

`irm` downloads the installer of the latest release and `iex` runs it. A menu opens: choose *Install or update*, then the player (or players) to install hikari for. The installer:

- finds mpv, mpv.net and AnimeJaNai and the config folder each one reads;
- backs up the files it may change, next to that folder (`<folder>-respaldo-hikari-<date>`; it keeps the three newest and the one from before the first install);
- downloads hikari, uosc and thumbfast (and Anime4K, if you want it) from GitHub, always the same versions, and checks every download against its SHA256 before using it;
- sets aside other on-screen controllers that would clash with uosc (nothing is deleted);
- copies the scripts and their settings, and adds a marked block to `mpv.conf` and `input.conf`, leaving the rest of both files as it is.

It only touches that config folder and the backup next to it, plus a temporary folder that it deletes when it ends (and, only if you choose it when no player is found, installs mpv.net with `winget`). No administrator rights, no registry, no `PATH` changes. Through `iex` it does not close or change your PowerShell window: it only leaves its result in `$LASTEXITCODE`. Messages are in Spanish when Windows is set to Spanish, in English otherwise. Restart the player afterwards.

If `irm` itself fails with an error about a secure channel (SSL/TLS), your Windows PowerShell 5.1 does not use TLS 1.2 by default (older Windows 10 builds). Switch it on for that window and run the line again:

```
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1 | iex
```

- **Update**: run the same line again and choose *Install or update*. Your saved palette, subtitle and upscaling choices are kept.
- **Uninstall**: run the same line again and choose *Uninstall*. It backs up again, removes hikari and its blocks, and asks whether to remove uosc and thumbfast too and whether to put back what it set aside.

## Options

`iex` cannot pass options to the installer. To pass them, run it as a script block:

```
& ([scriptblock]::Create((irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1))) -Action uninstall
```

| Option | Meaning |
| --- | --- |
| `-Action install` / `-Action uninstall` | Skip the first menu. |
| `-Target <config folder>` | Work on that folder (several separated by `;`) instead of choosing from the list. |
| `-Yes` | No questions: take the default answer to everything. Needs `-Action`, and `-Target` when more than one folder is found. |
| `-NoMenu` | Ask with numbers and typed answers instead of the keyboard menus. |
| `-Anime4K yes` / `-Anime4K no` | Answer the Anime4K questions instead of asking: install it (and take over an Anime4K installed by hand), or leave it out. See [Anime4K upscaling](../features/anime4k.md). |

Exit codes (in `$LASTEXITCODE`): 0 done or cancelled, 1 a folder failed, 2 wrong usage or nothing to do. For example:

```
& ([scriptblock]::Create((irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1))) -Action install -Target "$env:APPDATA\mpv" -Yes
```

## Checking the installer first

`irm ... | iex` runs whatever the server sends without checking it: the installer verifies everything it downloads, but it cannot verify itself. The address always points to a file attached to a tagged release, never to the `main` branch. To check it yourself, download `hikari.ps1` and `SHA256SUMS` from the [release page](https://github.com/SCEPTICG/hikari-mpv/releases/latest), compare the hash and run the file:

```
Get-FileHash .\hikari.ps1 -Algorithm SHA256
Get-Content .\SHA256SUMS
powershell -ExecutionPolicy Bypass -File .\hikari.ps1
```

The first line must print the hash `SHA256SUMS` lists for `hikari.ps1`. The options above work after the file name too (`-File .\hikari.ps1 -Action uninstall`). Each release's `hikari.ps1` only installs the `hikari.zip` of that same release, and only if its SHA256 matches the one written inside the script.

Be aware of what this check proves: `SHA256SUMS` comes from the same release, published by the same GitHub account, as `hikari.ps1`. It catches a file that was corrupted or changed on the way to you, but not a compromised account: whoever could replace `hikari.ps1` there could replace `SHA256SUMS` too. Reading `hikari.ps1` before running it is the only check that does not depend on the account.

From a copy of this repository (clone it, or download it as a zip and extract it), open PowerShell in that folder and run `powershell -ExecutionPolicy Bypass -File install\hikari.ps1`: the hikari files then come from that copy.

## How the installer works

The installer is driven with the keyboard: `↑`/`↓` move through a menu (going past the last entry takes you back to the first), `Enter` chooses and `Esc` leaves. Where you can pick several folders, `Space` ticks or unticks each one and `Enter` confirms; with nothing ticked, `Enter` takes the highlighted folder, so with a single player found `Enter` is enough. *Other folder…* and *Exit* are entries you choose, not boxes you tick. Yes/no questions show `Yes` and `No` side by side, starting on the default answer: `←`/`→` change it, `Enter` confirms, and `Y`/`N` (`S`/`N` in Spanish) answer straight away. `Esc` (and `Ctrl+C` while a menu is open) always answers *No* or leaves, which is never the option that removes or moves anything. So `Ctrl+C` in a yes/no question answers *No* and the installation carries on: it does not stop it. Outside a menu (while it downloads or copies, or at a typed answer) `Ctrl+C` stops the script as usual. Letter shortcuts only count on their own (`Ctrl+S` or `Alt+Y` do not answer *Yes*), keys pressed before a question appears are ignored, and in the single-choice menus the old numbers still work (`1`, `2`... and `0` for *Exit*). In a window too low for a menu, the installer first draws a compact version (folders shortened on the same line, one short help line) and, if even that does not fit, asks with numbers. When there is no interactive console (input or output redirected, `-NonInteractive`, the PowerShell ISE...) the installer asks with numbers and typed answers instead, as it also does with `-NoMenu`. Typing a folder path is always a normal typed answer.

Choose *Install or update* and the installer lists the players it finds, with the config folder each one reads:

- **AnimeJaNai** (`%LOCALAPPDATA%\Programs\mpv-AnimeJaNai`) and **mpv.net**: `portable_config` next to `mpvnet.exe` if it exists, otherwise `%APPDATA%\mpv.net` (not `%APPDATA%\mpv`).
- **mpv** (in `PATH`, Scoop, Chocolatey or `Program Files\mpv`): `portable_config` next to `mpv.exe` if it exists, otherwise `%APPDATA%\mpv`.
- Existing `%APPDATA%\mpv` and `%APPDATA%\mpv.net` folders, even without a player.

Pick one or several (or, with `-NoMenu`, type their numbers: `1,3`), or type another folder (`%APPDATA%\mpv` and relative paths work). If you type the player's own folder, the one with `mpv.exe` or `mpvnet.exe`, the installer uses its `portable_config` or offers the config folder that player reads. Drive roots and your bare user folder are refused, and a folder with no sign of mpv in it (no `mpv.conf`, `input.conf`, `scripts`, `script-opts` and no mpv next to it) is only used if you confirm it; with `-Yes` it is refused. If `MPV_HOME` is set, mpv reads that folder before any `portable_config`, and so does the installer for mpv (not for mpv.net, which picks its own folder). A folder you cannot write to (a `portable_config` under `Program Files`, say) is flagged, and the installer offers the user folder instead; note that a player with a `portable_config` only reads that folder. If no player is found at all, it offers to install mpv.net with `winget` (asking first), to type a folder, or to prepare `%APPDATA%\mpv` for an mpv installed later. Ways to get mpv: <https://mpv.io/installation/>.

For each folder it:

1. Copies the files it may change to `<folder>-respaldo-hikari-<date>` next to it, and shows the size of that copy: `mpv.conf`, `input.conf`, `scripts`, `script-opts`, `fonts`, `hikari-palette.conf`, `hikari-subs.conf`, `hikari-upscale.conf`, `hikari-installed.txt`, and `scripts-desactivados`, `shaders-desactivados` and `hikari-originales` if they exist. Nothing else in the folder is copied (`cache`, `watch_later`...); in `shaders` hikari only adds and removes its own Anime4K files, and an Anime4K installed by hand is moved, never deleted, so `shaders` is not copied either. Junctions and symbolic links are skipped with a warning, never followed. If the copy fails, the half-made copy is deleted and that folder is left alone. Then only the three newest backups of that folder are kept, plus the one made before hikari's first install (the only one with your config as it was before hikari, marked with a `hikari-backup-original.txt` file inside so it is kept even after uninstalling and installing again); older ones are deleted, and the installer says which. Only folders named exactly `<folder>-respaldo-hikari-<date>` next to it count: nothing else is touched.
2. Moves other on-screen controllers that clash with uosc (ModernX, ModernZ, custom `osc.lua`, `mpv-osc-*`...) to `scripts-desactivados`, together with their `script-opts` and fonts. Nothing is deleted. It also offers to move there the `.lua` files in `scripts` that are really the error page of a failed download (first line `404: Not Found`, `Not Found` or an HTML page), for which mpv logs an error at every start; they come back on uninstall.
3. Downloads uosc 5.13.0 and thumbfast (fixed commit) from GitHub and checks their SHA256 before using them. uosc's own `uosc.conf` is not installed: hikari's is.
4. Copies the hikari scripts and `script-opts`. `hikari-palette.conf` and `hikari-subs.conf` are only copied when missing, so your saved palette and subtitle choices survive updates.
5. Anime4K: asks whether to install it (see [Anime4K upscaling](../features/anime4k.md)) and writes `hikari-upscale.conf` if it is missing, with the quality that suits your graphics card; when it has just installed Anime4K there, in *Automático*.
6. Adds a marked block at the end of `mpv.conf` (`osc=no`, `osd-bar=no` and the three `include` lines) and of `input.conf` (`Alt+p`, `Alt+s`, `Alt+t`, `Alt+u`, and `Ctrl+0` to `Ctrl+7` when hikari installed Anime4K). The rest of both files is left as it is. Running the installer again rewrites the block: in `mpv.conf` it is moved back to the end, so the saved subtitle style still wins over `sub-*` lines you added later; in `input.conf` it stays where it is. If `mpv.conf` ends inside a `[profile]`, the block starts with `[default]`. A key you already use for something else is left to you, and the installer says so.
7. For mpv.net and AnimeJaNai, writes `mpv_path=<path to mpvnet.exe>` into `script-opts/thumbfast.conf`, because some mpv.net builds do not tell thumbfast where they are (see [Thumbnails](../features/thumbnails.md)).
8. Writes `hikari-installed.txt` with the versions installed and what was already there, for updates and uninstalling.

Run it again at any time to update. *Uninstall* (after another backup of the same files) removes the hikari scripts and options, the Anime4K shaders it installed (only those) and both blocks, and asks whether to remove uosc and thumbfast (yes by default only if hikari installed them), whether to move back what it set aside (interfaces, and an Anime4K installed by hand), whether to turn back on the `input.conf` and `mpv.conf` lines it turned off (only those, and only if they are still there as hikari left them), and whether to delete your saved choices. `hikari-update.txt`, where the update check keeps its state, goes without asking, like `hikari-installed.txt`; updating keeps it. A file that had no line break at its end gets it back that way.

If uosc goes and your own `mpv.conf` (outside the hikari block) still has `osc=no` or `osc=false`, the player would be left without on-screen controls. The installer says so and offers to move back the interfaces it set aside, or else to turn that line off by putting `# hikari: ` in front of it. With `-Yes` it only warns.

Lines you added to `mpv.conf` or `input.conf` by hand, for a copy of hikari installed without the installer, are not touched: once the installer's block is there you can delete them.

