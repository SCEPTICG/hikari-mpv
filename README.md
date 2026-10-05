# sosc

A cross-platform mpv theme (Windows, Linux, macOS) built on top of [uosc](https://github.com/tomasklaen/uosc), with its own palette, thumbnails via [thumbfast](https://github.com/po5/thumbfast), and a few extras such as skipping anime openings and endings.

Work in progress.

## Install

### Windows

From a copy of this repository (download it as a zip and extract it, or clone it), open PowerShell in that folder and run:

```
powershell -ExecutionPolicy Bypass -File install\install.ps1
```

It works with Windows PowerShell 5.1 (built into Windows 10 and 11) and PowerShell 7, needs no administrator rights and does not touch the registry or `PATH`. Messages are in Spanish when Windows is set to Spanish, in English otherwise.

Choose *Install or update* and the installer lists the players it finds, with the config folder each one reads:

- **AnimeJaNai** (`%LOCALAPPDATA%\Programs\mpv-AnimeJaNai`) and **mpv.net**: `portable_config` next to `mpvnet.exe` if it exists, otherwise `%APPDATA%\mpv.net` (not `%APPDATA%\mpv`).
- **mpv** (in `PATH`, Scoop, Chocolatey or `Program Files\mpv`): `portable_config` next to `mpv.exe` if it exists, otherwise `%APPDATA%\mpv`.
- Existing `%APPDATA%\mpv` and `%APPDATA%\mpv.net` folders, even without a player.

Pick one or several (`1,3`), or type another folder. A folder you cannot write to (a `portable_config` under `Program Files`, say) is flagged, and the installer offers the user folder instead; note that a player with a `portable_config` only reads that folder. If no player is found at all, it offers to install mpv.net with `winget` (asking first), to type a folder, or to prepare `%APPDATA%\mpv` for an mpv installed later. Ways to get mpv: <https://mpv.io/installation/>.

For each folder it:

1. Copies the whole folder to `<folder>-respaldo-sosc-<date>` next to it (without `cache` and `watch_later`). If the copy fails, that folder is left alone.
2. Moves other on-screen controllers that clash with uosc (ModernX, ModernZ, custom `osc.lua`, `mpv-osc-*`...) to `scripts-desactivados`, together with their `script-opts` and fonts. Nothing is deleted.
3. Downloads uosc 5.13.0 and thumbfast (fixed commit) from GitHub and checks their SHA256 before using them. uosc's own `uosc.conf` is not installed: sosc's is.
4. Copies the sosc scripts and `script-opts`. `sosc-palette.conf` and `sosc-subs.conf` are only copied when missing, so your saved palette and subtitle choices survive updates.
5. Adds a marked block at the end of `mpv.conf` (`osc=no`, `osd-bar=no` and the two `include` lines) and of `input.conf` (`Alt+p`, `Alt+s`, `Alt+t`). The rest of both files is left as it is; running the installer again only rewrites the block. A key you already use for something else is left to you, and the installer says so.
6. For mpv.net and AnimeJaNai, writes `mpv_path=<path to mpvnet.exe>` into `script-opts/thumbfast.conf`, because some mpv.net builds do not tell thumbfast where they are (see [Thumbnails](#thumbnails)).
7. Writes `sosc-installed.txt` with the versions installed and what was already there, for updates and uninstalling.

Run it again at any time to update. *Uninstall* (after another backup) removes the sosc scripts and options and both blocks, and asks whether to remove uosc and thumbfast (yes by default only if sosc installed them), whether to move back what it set aside and whether to delete your saved choices.

Lines you added to `mpv.conf` or `input.conf` by hand for an earlier sosc install are not touched: once the installer's block is there you can delete them.

For scripts: `-Action install|uninstall`, `-Target <config folder>` (several separated by `;`) and `-Yes` (no questions, default answers). Exit code 0 means done, 1 that a folder failed, 2 wrong usage or nothing to do.

```
powershell -ExecutionPolicy Bypass -File install\install.ps1 -Action install -Target "$env:APPDATA\mpv" -Yes
```

### Linux and macOS

No installer yet: copy the contents of `portable_config/` into `~/.config/mpv/` (keeping your own `mpv.conf` and `input.conf`, and adding the lines above to them), install [uosc](https://github.com/tomasklaen/uosc#install) and put [thumbfast.lua](https://github.com/po5/thumbfast) in `scripts/`.

## Palettes

sosc ships a palette picker for uosc. Open it with the palette button in the controls bar or `Alt+p`, then pick a palette; it is applied straight away.

- Dark: uosc (original), Catppuccin Mocha, Tokyo Night, Dracula, Nord, Gruvbox, Rosé Pine, Kanagawa, One Dark, Everforest.
- Light: Catppuccin Latte, Gruvbox light, Solarized light.
- Custom: SCEPTIC, defined in `portable_config/scripts/sosc-palettes.lua`.

A palette can also set transparency through an optional `opacity` table (uosc's `opacity` keys, values 0 to 1); palettes without it use uosc's default opacity.

sosc owns uosc's `color` and `opacity` options: values set in `script-opts/uosc.conf` are overridden by the active palette. Customise them by editing a palette instead.

The choice is saved to `~~/sosc-palette.conf` (the mpv config folder, `portable_config/` in a portable install), which `mpv.conf` includes on start-up. To bind another key, use `script-binding sosc_palettes/open-menu` in `input.conf`.

## Stream titles

When mpv plays an http(s) URL with a query string, such as the links Seanime hands out (`https://host/<id>?token=...&filename=Show.S01E01.mkv`), `sosc-title.lua` sets the title to the decoded `filename` parameter without its video extension, or to the last path segment when there is no `filename`. The title is set as the file starts, so the token is kept out of the top bar except, at most, for an instant while the stream opens. Local files and URLs without a query keep mpv's own title, and a `force-media-title` you set yourself is left alone. The title only lasts for that file.

It also leaves alone playlist entries that carry their own title (M3U `#EXTINF`), and when there is no `filename` the path segment it falls back to (`stream`, `master.m3u8`...) gives way to the file's own `title` tag once the file has loaded.

Scope: this covers uosc's top bar and the window title. The full URL is still visible in uosc's playlist menu, in mpv's stats overlay, and in mpv's logs and `watch_later` files.

With `pretty=yes` (the default) a title taken from `filename` is tidied up: dots and underscores become spaces, release groups, hashes and technical tags go, and the episode marker is shown as `T<season> E<episode>` (T for *temporada*, season):

| `filename` | Title |
| --- | --- |
| `Reborn.as.a.Space.Mercenary.I.Woke.Up.Piloting.the.Strongest.Starship.S01E01.1080p.CR.WEB-DL.DUAL.AAC2.0.H.264.MSubs-ToonsHub.mkv` | `Reborn as a Space Mercenary I Woke Up Piloting the Strongest Starship · T1 E01` |
| `[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv` | `Sousou no Frieren · E05` |
| `Show.S01E01-E02.mkv` | `Show · T1 E01-E02` |
| `Show.S00E03.mkv` | `Show · Especial E03` (season 0 holds the specials) |
| `Movie.Name.2023.1080p.BluRay.x264.mkv` | `Movie Name (2023)` |

Recognised markers: `S01E01`, `s1e1`, `S01E01v2`, `S01E01-E02`, `E01`, `EP01`, `Episode 01` and anime-style ` - 01` / ` - 01v2`. A name with no marker is treated as a film and only cut at its first technical tag (resolution, source, codec, audio...); if nothing sensible is left, the name is shown as it comes. The path-segment fallback and playlist titles are never changed. Set `pretty=no` to get the filename as it comes, without its video extension.

Disable the whole script with `enabled=no` in `script-opts/sosc-title.conf`.

## Speed menu

The speed button in the controls bar opens a menu with 0.5×, 0.75×, 1×, 1.25×, 1.5× and 2×; the current speed is marked. mpv's own `[`, `]` and `Backspace` keep working. To open the menu from the keyboard, add a line like this to `input.conf`:

```
Alt+v  script-binding sosc_speed/open-menu
```

## Subtitle styles

The subtitles button with the text icon (`text_fields`) in the controls bar, or `Alt+t`, opens a **Subtítulos** menu with three groups. Picking an option applies it straight away and the menu stays open, with the new choice marked, so several things can be adjusted in a row.

- **Style**: *Original* (sets nothing: mpv's defaults or your own `sub-*` lines in `mpv.conf`), *Caja oscura* (white text on a translucent black box, Netflix-like), *Borde grueso* (bold white text, thick black outline, soft shadow, Crunchyroll-like) and *Amarillo clásico* (yellow text, black outline and shadow).
- **Size**: `sub-scale` 0.85, *Normal*, 1.2 or 1.4.
- **Height**: `sub-pos` *Normal*, 95 or 90.

*Original* and *Normal* set nothing, so whatever your `mpv.conf` says (or mpv's default: `sub-scale=1`, `sub-pos=100`) stays in charge. Choosing them again puts back the values mpv had when the script started; if mpv was started with another choice saved, those values were already the choice's, so mpv's built-in defaults are used instead until the next start, when your `mpv.conf` applies again.

The choice is saved to `~~/sosc-subs.conf`, which `mpv.conf` includes on start-up. The styles are defined in `portable_config/scripts/sosc-subs.lua`. Colours use mpv's `#AARRGGBB`, where the alpha is opacity (`FF` opaque, `00` invisible), the reverse of ASS. To bind another key, use `script-binding sosc_subs/open-menu` in `input.conf`.

ASS subtitles keep their own styling: sosc leaves mpv's `sub-ass-override=scale` alone, so the style only applies to text subtitles (SRT, WebVTT...). With that setting mpv still applies `sub-scale` to ASS, so the size options do change them. `sub-pos` is passed to libass as the line position and moves ASS dialogue too; lines placed with `\pos` (signs, karaoke) should stay where they are. This last point still has to be checked in mpv with real files.

mpv 0.39 changed the subtitle border options, and the script adapts to the version it runs on, always writing the real option name (never an alias):

- mpv 0.39 and newer: `sub-outline-color`/`sub-outline-size`, `sub-back-color` for the shadow colour (`sub-shadow-color` is an alias of it), and `sub-border-style`. *Caja oscura* uses `sub-border-style=opaque-box`.
- mpv 0.38 and older: `sub-border-color`/`sub-border-size`, a separate `sub-shadow-color`, and no `sub-border-style`. *Caja oscura* still gets its box: a translucent `sub-back-color` makes mpv draw a background box in that colour. The other styles never give `sub-back-color` any opacity of their own (they put back the value it had at start-up), so no box appears with them.

A `sosc-subs.conf` written by mpv 0.39 or newer uses option names that mpv 0.38 and older don't know: if the same config folder is used with an older mpv, it logs an unknown-option error for those lines and starts normally, without that style until it is picked again.

## Skip openings and endings

`sosc-skip.lua` shows a **Saltar opening ›** / **Saltar ending ›** button at the bottom right, above uosc's controls, for as long as playback is inside a chapter that looks like an opening or an ending, even when uosc's controls are hidden or playback is paused. Clicking it, or pressing `Alt+s`, jumps to the start of the next chapter. Outside those chapters, in files without chapters, while idle and while a uosc menu or the console is open, nothing is drawn and the mouse is left to uosc and mpv.

Chapters are recognised by title, with the same rules uosc uses to colour its chapter ranges: `OP`, `Opening`, `... OP`, `... Opening` and `オープニング` for openings (only when another chapter follows), `ED`, `Ending`, `ED ...`, `Ending ...`, `... ED`, `... Ending` and `エンディング` for endings. Titles such as `Operation`, `OP1` or `Opening Night` do not count; add your own patterns with `extra_openings` / `extra_endings` (Lua patterns separated by `|`, matched against the lower-case title). Intros (`Intro`, `Avant`, `Prologue`, shown as **Saltar intro ›**) are on by default, because many releases name the opening song `Intro`; turn them off with `intros=no`. Outros (`Outro`, `Closing`, `Preview`, `PV`, shown as **Saltar avance ›**) are off by default; turn them on with `outros=yes`.

When the ending is the last chapter, skipping it moves on to the next playlist entry if there is one; otherwise it seeks to one second before the end, so the file finishes as it normally would.

The button follows the active palette (background and border from uosc's `background` and `foreground`, filled with `foreground` on hover). Position, size and opacity are set in `script-opts/sosc-skip.conf`. To use another key, bind `script-binding sosc_skip/skip` in `input.conf`.

## Tests

From the repository root:

```
lua tests/test_palettes.lua
lua tests/test_title.lua
lua tests/test_speed.lua
lua tests/test_skip.lua
lua tests/test_subs.lua
pwsh -NoProfile -File tests/install.Tests.ps1
```

The installer tests need PowerShell 7 (on any system, no Pester) and simulate Windows folders, so they run on Linux too; they do not download anything.

## Thumbnails

Timeline thumbnails come from [thumbfast](https://github.com/po5/thumbfast), which uosc picks up automatically. thumbfast is not bundled (MPL-2.0); install `thumbfast.lua` into `scripts/` (the installer will do it). sosc ships `script-opts/thumbfast.conf` with thumbnails enabled on network streams (`network=yes`), GPU decoding (`hwdec=yes`) and the thumbnailer started only when the timeline is first hovered (`spawn_first=no`). On streams thumbfast opens its own connection, so it uses some extra bandwidth and the first thumbnail can take a moment. mpv.net 7+ is meant to work without extra setup, but some builds (seen with the AnimeJaNai bundle, mpv.net 7.1.2) do not report their path to thumbfast in time and it shows "install standalone mpv". In that case add the full path to `script-opts/thumbfast.conf`, e.g. `mpv_path=C:\Users\<you>\AppData\Local\Programs\mpv-AnimeJaNai\mpvnet.exe` (the installer will write it for you). On streams each new thumbnail takes a moment, since thumbfast has to fetch that part of the video over the network.

## License

MIT. uosc (LGPL-2.1) and thumbfast (MPL-2.0) are not included in this repository; the installer downloads them from their official releases.
