# sosc

A theme for the [mpv](https://mpv.io) video player, built on top of [uosc](https://github.com/tomasklaen/uosc), with its own colour palettes and a few extras for watching series and anime.

- **Palettes**: 14 colour palettes for uosc, including sosc's own, SCEPTIC, picked from a menu and applied straight away.
- **Skip button**: a *Saltar opening / intro / ending* button while a chapter looks like an opening, intro or ending.
- **Stream titles**: readable titles for streamed URLs, with the access token kept out of the title bar.
- **Speed menu**: a button with fixed speeds (0.5× to 2×) instead of a slider.
- **Subtitle styles**: a menu with three subtitle styles, plus size and height.
- **Thumbnails**: timeline thumbnails through [thumbfast](https://github.com/po5/thumbfast), on network streams too.
- **Anime4K upscaling**: an *Escalado* menu and `Ctrl+0`–`Ctrl+6` for [Anime4K](https://github.com/bloc97/Anime4K)'s modes, with a quality that suits your graphics card.
- **Adapted controls bar**: a filled timeline and a controls bar arranged for watching single episodes.

The on-screen labels are in Spanish for now (*Saltar opening*, *Subtítulos*, *Velocidad*, *Paletas*, *Escalado*).

## Requirements

- **Windows** 10 or 11. macOS and Linux: coming soon (see [Linux and macOS](#linux-and-macos) for a manual setup in the meantime).
- A player based on mpv: [mpv](https://mpv.io/installation/), [mpv.net](https://github.com/mpvnet-player/mpv.net), or a bundle built on mpv.net such as [AnimeJaNai](https://github.com/the-database/mpv-upscale-2x_animejanai). If none is installed, the installer offers to install mpv.net with `winget`.
- Windows PowerShell 5.1 (built into Windows) or PowerShell 7. No administrator rights.

## Install

Open PowerShell (Start menu, type *PowerShell*) and run:

```
irm https://github.com/SCEPTICG/sosc/releases/latest/download/sosc.ps1 | iex
```

`irm` downloads the installer of the latest release and `iex` runs it. A menu opens: choose *Install or update*, then the player (or players) to install sosc for. The installer:

- finds mpv, mpv.net and AnimeJaNai and the config folder each one reads;
- backs up the files it may change, next to that folder (`<folder>-respaldo-sosc-<date>`; it keeps the three newest and the one from before the first install);
- downloads sosc, uosc and thumbfast (and Anime4K, if you want it) from GitHub, always the same versions, and checks every download against its SHA256 before using it;
- sets aside other on-screen controllers that would clash with uosc (nothing is deleted);
- copies the scripts and their settings, and adds a marked block to `mpv.conf` and `input.conf`, leaving the rest of both files as it is.

It only touches that config folder and the backup next to it, plus a temporary folder that it deletes when it ends (and, only if you choose it when no player is found, installs mpv.net with `winget`). No administrator rights, no registry, no `PATH` changes. Through `iex` it does not close or change your PowerShell window: it only leaves its result in `$LASTEXITCODE`. Messages are in Spanish when Windows is set to Spanish, in English otherwise. Restart the player afterwards.

If `irm` itself fails with an error about a secure channel (SSL/TLS), your Windows PowerShell 5.1 does not use TLS 1.2 by default (older Windows 10 builds). Switch it on for that window and run the line again:

```
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; irm https://github.com/SCEPTICG/sosc/releases/latest/download/sosc.ps1 | iex
```

- **Update**: run the same line again and choose *Install or update*. Your saved palette, subtitle and upscaling choices are kept.
- **Uninstall**: run the same line again and choose *Uninstall*. It backs up again, removes sosc and its blocks, and asks whether to remove uosc and thumbfast too and whether to put back what it set aside.

### Options

`iex` cannot pass options to the installer. To pass them, run it as a script block:

```
& ([scriptblock]::Create((irm https://github.com/SCEPTICG/sosc/releases/latest/download/sosc.ps1))) -Action uninstall
```

| Option | Meaning |
| --- | --- |
| `-Action install` / `-Action uninstall` | Skip the first menu. |
| `-Target <config folder>` | Work on that folder (several separated by `;`) instead of choosing from the list. |
| `-Yes` | No questions: take the default answer to everything. Needs `-Action`, and `-Target` when more than one folder is found. |
| `-NoMenu` | Ask with numbers and typed answers instead of the keyboard menus. |
| `-Anime4K yes` / `-Anime4K no` | Answer the Anime4K questions instead of asking: install it (and take over an Anime4K installed by hand), or leave it out. See [Anime4K upscaling](#anime4k-upscaling). |

Exit codes (in `$LASTEXITCODE`): 0 done or cancelled, 1 a folder failed, 2 wrong usage or nothing to do. For example:

```
& ([scriptblock]::Create((irm https://github.com/SCEPTICG/sosc/releases/latest/download/sosc.ps1))) -Action install -Target "$env:APPDATA\mpv" -Yes
```

### Checking the installer first

`irm ... | iex` runs whatever the server sends without checking it: the installer verifies everything it downloads, but it cannot verify itself. The address always points to a file attached to a tagged release, never to the `main` branch. To check it yourself, download `sosc.ps1` and `SHA256SUMS` from the [release page](https://github.com/SCEPTICG/sosc/releases/latest), compare the hash and run the file:

```
Get-FileHash .\sosc.ps1 -Algorithm SHA256
Get-Content .\SHA256SUMS
powershell -ExecutionPolicy Bypass -File .\sosc.ps1
```

The first line must print the hash `SHA256SUMS` lists for `sosc.ps1`. The options above work after the file name too (`-File .\sosc.ps1 -Action uninstall`). Each release's `sosc.ps1` only installs the `sosc.zip` of that same release, and only if its SHA256 matches the one written inside the script.

Be aware of what this check proves: `SHA256SUMS` comes from the same release, published by the same GitHub account, as `sosc.ps1`. It catches a file that was corrupted or changed on the way to you, but not a compromised account: whoever could replace `sosc.ps1` there could replace `SHA256SUMS` too. Reading `sosc.ps1` before running it is the only check that does not depend on the account.

From a copy of this repository (clone it, or download it as a zip and extract it), open PowerShell in that folder and run `powershell -ExecutionPolicy Bypass -File install\sosc.ps1`: the sosc files then come from that copy.

### How the installer works

The installer is driven with the keyboard: `↑`/`↓` move through a menu (going past the last entry takes you back to the first), `Enter` chooses and `Esc` leaves. Where you can pick several folders, `Space` ticks or unticks each one and `Enter` confirms; with nothing ticked, `Enter` takes the highlighted folder, so with a single player found `Enter` is enough. *Other folder…* and *Exit* are entries you choose, not boxes you tick. Yes/no questions show `Yes` and `No` side by side, starting on the default answer: `←`/`→` change it, `Enter` confirms, and `Y`/`N` (`S`/`N` in Spanish) answer straight away. `Esc` (and `Ctrl+C` while a menu is open) always answers *No* or leaves, which is never the option that removes or moves anything. So `Ctrl+C` in a yes/no question answers *No* and the installation carries on: it does not stop it. Outside a menu (while it downloads or copies, or at a typed answer) `Ctrl+C` stops the script as usual. Letter shortcuts only count on their own (`Ctrl+S` or `Alt+Y` do not answer *Yes*), keys pressed before a question appears are ignored, and in the single-choice menus the old numbers still work (`1`, `2`... and `0` for *Exit*). In a window too low for a menu, the installer first draws a compact version (folders shortened on the same line, one short help line) and, if even that does not fit, asks with numbers. When there is no interactive console (input or output redirected, `-NonInteractive`, the PowerShell ISE...) the installer asks with numbers and typed answers instead, as it also does with `-NoMenu`. Typing a folder path is always a normal typed answer.

Choose *Install or update* and the installer lists the players it finds, with the config folder each one reads:

- **AnimeJaNai** (`%LOCALAPPDATA%\Programs\mpv-AnimeJaNai`) and **mpv.net**: `portable_config` next to `mpvnet.exe` if it exists, otherwise `%APPDATA%\mpv.net` (not `%APPDATA%\mpv`).
- **mpv** (in `PATH`, Scoop, Chocolatey or `Program Files\mpv`): `portable_config` next to `mpv.exe` if it exists, otherwise `%APPDATA%\mpv`.
- Existing `%APPDATA%\mpv` and `%APPDATA%\mpv.net` folders, even without a player.

Pick one or several (or, with `-NoMenu`, type their numbers: `1,3`), or type another folder (`%APPDATA%\mpv` and relative paths work). If you type the player's own folder, the one with `mpv.exe` or `mpvnet.exe`, the installer uses its `portable_config` or offers the config folder that player reads. Drive roots and your bare user folder are refused, and a folder with no sign of mpv in it (no `mpv.conf`, `input.conf`, `scripts`, `script-opts` and no mpv next to it) is only used if you confirm it; with `-Yes` it is refused. If `MPV_HOME` is set, mpv reads that folder before any `portable_config`, and so does the installer for mpv (not for mpv.net, which picks its own folder). A folder you cannot write to (a `portable_config` under `Program Files`, say) is flagged, and the installer offers the user folder instead; note that a player with a `portable_config` only reads that folder. If no player is found at all, it offers to install mpv.net with `winget` (asking first), to type a folder, or to prepare `%APPDATA%\mpv` for an mpv installed later. Ways to get mpv: <https://mpv.io/installation/>.

For each folder it:

1. Copies the files it may change to `<folder>-respaldo-sosc-<date>` next to it, and shows the size of that copy: `mpv.conf`, `input.conf`, `scripts`, `script-opts`, `fonts`, `sosc-palette.conf`, `sosc-subs.conf`, `sosc-upscale.conf`, `sosc-installed.txt`, and `scripts-desactivados`, `shaders-desactivados` and `sosc-originales` if they exist. Nothing else in the folder is copied (`cache`, `watch_later`...); in `shaders` sosc only adds and removes its own Anime4K files, and an Anime4K installed by hand is moved, never deleted, so `shaders` is not copied either. Junctions and symbolic links are skipped with a warning, never followed. If the copy fails, the half-made copy is deleted and that folder is left alone. Then only the three newest backups of that folder are kept, plus the one made before sosc's first install (the only one with your config as it was before sosc); older ones are deleted, and the installer says which. Only folders named exactly `<folder>-respaldo-sosc-<date>` next to it count: nothing else is touched.
2. Moves other on-screen controllers that clash with uosc (ModernX, ModernZ, custom `osc.lua`, `mpv-osc-*`...) to `scripts-desactivados`, together with their `script-opts` and fonts. Nothing is deleted.
3. Downloads uosc 5.13.0 and thumbfast (fixed commit) from GitHub and checks their SHA256 before using them. uosc's own `uosc.conf` is not installed: sosc's is.
4. Copies the sosc scripts and `script-opts`. `sosc-palette.conf` and `sosc-subs.conf` are only copied when missing, so your saved palette and subtitle choices survive updates.
5. Anime4K: asks whether to install it (see [Anime4K upscaling](#anime4k-upscaling)) and writes `sosc-upscale.conf` if it is missing, with the quality that suits your graphics card.
6. Adds a marked block at the end of `mpv.conf` (`osc=no`, `osd-bar=no` and the three `include` lines) and of `input.conf` (`Alt+p`, `Alt+s`, `Alt+t`, and `Ctrl+0` to `Ctrl+6` when sosc installed Anime4K). The rest of both files is left as it is. Running the installer again rewrites the block: in `mpv.conf` it is moved back to the end, so the saved subtitle style still wins over `sub-*` lines you added later; in `input.conf` it stays where it is. If `mpv.conf` ends inside a `[profile]`, the block starts with `[default]`. A key you already use for something else is left to you, and the installer says so.
7. For mpv.net and AnimeJaNai, writes `mpv_path=<path to mpvnet.exe>` into `script-opts/thumbfast.conf`, because some mpv.net builds do not tell thumbfast where they are (see [Thumbnails](#thumbnails)).
8. Writes `sosc-installed.txt` with the versions installed and what was already there, for updates and uninstalling.

Run it again at any time to update. *Uninstall* (after another backup of the same files) removes the sosc scripts and options, the Anime4K shaders it installed (only those) and both blocks, and asks whether to remove uosc and thumbfast (yes by default only if sosc installed them), whether to move back what it set aside (interfaces, and an Anime4K installed by hand), whether to turn back on the `input.conf` lines it turned off, and whether to delete your saved choices.

If uosc goes and your own `mpv.conf` (outside the sosc block) still has `osc=no` or `osc=false`, the player would be left without on-screen controls. The installer says so and offers to move back the interfaces it set aside, or else to turn that line off by putting `# sosc: ` in front of it. With `-Yes` it only warns.

Lines you added to `mpv.conf` or `input.conf` by hand for an earlier sosc install are not touched: once the installer's block is there you can delete them.

### Linux and macOS

Coming soon. Until then, by hand: copy the contents of `portable_config/` into `~/.config/mpv/`, except `mpv.conf` and `input.conf` if you already have your own (then add the `osc=no`, `osd-bar=no` and `include` lines of the repository's `mpv.conf`, and the bindings of its `input.conf`, to yours). Then install [uosc](https://github.com/tomasklaen/uosc#install) and put [thumbfast.lua](https://github.com/po5/thumbfast) in `scripts/`. For Anime4K, extract the `.glsl` files of [Anime4K_v4.0.zip](https://github.com/bloc97/Anime4K/releases/tag/v4.0.1) into `~/.config/mpv/shaders/` (the `Ctrl+0` to `Ctrl+6` lines of the repository's `input.conf` drive it).

## Usage

| Key | Action |
| --- | --- |
| `Alt+p` | Palette menu |
| `Alt+s` | Skip the current opening, intro or ending (while the button is on screen) |
| `Alt+t` | Subtitle menu (style, size, height) |
| `Ctrl+1` … `Ctrl+6` | Anime4K modes A, B, C, A+A, B+B, C+A (when sosc installed Anime4K) |
| `Ctrl+0` | Anime4K off |

The controls bar has up to four sosc buttons before *fullscreen*: subtitles (text icon), *Escalado* (sparkles icon, only for videos and only when Anime4K is installed), speed and palettes. The *Saltar opening ›* button appears at the bottom right during openings, intros and endings; click it or press `Alt+s`. A key you already use for something else is left to you: the installer says so, and you can bind another key to the same command (the commands are listed in each section below).

## Configuration

Everything lives in the player's config folder (the one the installer showed you):

| File | What it sets |
| --- | --- |
| `script-opts/uosc.conf` | uosc: timeline style and the buttons of the controls bar. |
| `script-opts/thumbfast.conf` | Thumbnails: on streams, GPU decoding, size. |
| `script-opts/sosc-skip.conf` | Skip button: which chapters, extra title patterns, position, size, opacity. |
| `script-opts/sosc-title.conf` | Stream titles: on/off and tidying of release names. |
| `sosc-palette.conf`, `sosc-subs.conf`, `sosc-upscale.conf` | Your chosen palette, subtitle style and Anime4K mode and quality, saved by the menus. Kept on update. |

Updating sosc replaces the `script-opts` files above with sosc's (your earlier `uosc.conf` and `thumbfast.conf` are kept in `sosc-originales` and put back on uninstall), so keep a copy of any change you make to them. Your own `mpv.conf` and `input.conf` lines are never changed: only the marked sosc block is.

### Example: audio and subtitle languages

sosc does not choose languages for you. A common recipe for anime with Spanish dubs (Spanish audio when there is one, otherwise Japanese with Spanish subtitles) goes in your own `mpv.conf`, before the sosc block:

```
alang=spa,es,es-ES,ja,jpn
slang=spa,es,es-ES
subs-with-matching-audio=no
```

`alang` and `slang` list the preferred audio and subtitle languages in order; `subs-with-matching-audio=no` stops mpv from turning on subtitles in the same language as the audio. Change the codes to your languages.

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

## Anime4K upscaling

[Anime4K](https://github.com/bloc97/Anime4K) (by bloc97, MIT) is a set of mpv shaders that clean up and upscale anime on the graphics card. sosc does not include it: the installer downloads release v4.0.1 (`Anime4K_v4.0.zip`) from GitHub, checks its SHA256 and copies its `Anime4K_*.glsl` files, and nothing else, into `shaders/`. Installed, it stays **off** until you pick a mode.

The **Escalado** button in the controls bar (sparkles icon, `auto_awesome`) opens a menu with two groups; picking an option applies it straight away and the menu stays open:

- **Modo**: *Apagado* and Anime4K's six official modes. The guide of Anime4K says the right one is the one that looks best; roughly:

  | Mode | For |
  | --- | --- |
  | A | Most 1080p anime, blurry or with compression artifacts. |
  | B | Most 720p anime (and 1080p scaled down to 720p): less blur, more aliasing and ringing. |
  | C | SD (480p) without much damage, wallpapers and clean images. |
  | A+A, B+B, C+A | The same, sharper and slower. Only for scaling by 2× or more (720p and below on a 1080p screen). |

- **Calidad**: *Alta* (Anime4K's *HQ* shader lists, for capable graphics cards) or *Rápida* (its *Fast* lists).

`Ctrl+1` to `Ctrl+6` pick the modes in the same order and `Ctrl+0` turns Anime4K off, as in Anime4K's own instructions; each shows a short message such as *Anime4K: Modo A (Rápido)*. The shader lists are exactly those of Anime4K's official mpv templates. If the shaders are missing, the menu says so (*Anime4K no está instalado: ejecuta el instalador*) and the button stays hidden.

The choice is saved to `~~/sosc-upscale.conf`, which `mpv.conf` includes, so the mode is active from the first frame on the next start. With *Apagado* that file sets no `glsl-shaders` at all, so your own `glsl-shaders` line keeps working; with a mode on, the mode's Anime4K shaders replace the whole list (like Anime4K's own keys do), and *Apagado* puts your list back. The shader list is set as a list, never as one joined string, so it does not depend on the path separator (`;` on Windows, `:` elsewhere). The button needs mpv 0.36 or newer (it is shown through a `user-data` property); with an older mpv use the keys.

What the installer does:

- **AnimeJaNai**: nothing. It already upscales with AI and uses `Ctrl+1` to `Ctrl+9` for it.
- **No Anime4K yet**: it explains what it is and asks *Install Anime4K?* (yes by default; with `-Yes`, yes). If you say no, it asks again on the next update, then with no as the default.
- **Anime4K installed by hand** (`Anime4K_*.glsl` in `shaders/` that sosc did not put there): it offers to take it over (no by default; with `-Yes`, no). If you accept, your files are moved to `shaders-desactivados/` (nothing is deleted), sosc installs its own copy, and `Ctrl+0` to `Ctrl+6` lines of yours that change `glsl-shaders` can be turned off by putting `# sosc: ` in front of them, so the sosc keys can use those keys. Uninstalling moves your files back and turns those lines on again. If you do not accept, nothing is touched: your keys keep working, but the *Escalado* menu does not know what they turned on.
- `-Anime4K yes` installs it (and takes over one installed by hand) without asking; `-Anime4K no` leaves it out (an Anime4K that sosc installed earlier is left as it is).

The quality is chosen from your graphics card the first time `sosc-upscale.conf` is written, and the installer says so in one line (*Gráfica: NVIDIA GeForce RTX 3060 → calidad Alta*). When there are several cards, the most capable one decides. *Alta*: NVIDIA RTX, NVIDIA GTX 1060 and newer (GTX 16xx too), AMD Radeon RX 500 series and newer, RX Vega 56/64 and Radeon VII, Intel Arc. *Rápida*: Intel UHD/Iris/HD, AMD integrated graphics, NVIDIA MX and GT, and anything unknown. It never changes the quality you picked afterwards: change it in the menu at any time. If the video stutters, use *Rápida* or a mode without `+`.

The modes, qualities and shader lists are defined in `portable_config/scripts/sosc-upscale.lua`. To open the menu from the keyboard, bind `script-binding sosc_upscale/open-menu` in `input.conf`; to pick a mode, `script-message-to sosc_upscale set-mode <off|a|b|c|aa|bb|ca>` (and `set-quality <hq|fast>`).

## Skip openings and endings

`sosc-skip.lua` shows a **Saltar opening ›** / **Saltar ending ›** button at the bottom right, above uosc's controls, for as long as playback is inside a chapter that looks like an opening or an ending, even when uosc's controls are hidden or playback is paused. Clicking it, or pressing `Alt+s`, jumps to the start of the next chapter. Outside those chapters, in files without chapters, while idle and while a uosc menu or the console is open, nothing is drawn and the mouse is left to uosc and mpv.

Chapters are recognised by title, with the same rules uosc uses to colour its chapter ranges: `OP`, `Opening`, `... OP`, `... Opening` and `オープニング` for openings (only when another chapter follows), `ED`, `Ending`, `ED ...`, `Ending ...`, `... ED`, `... Ending`, `Credits`, `Credits ...`, `... Credits` and `エンディング` for endings. Titles such as `Operation`, `OP1` or `Opening Night` do not count; add your own patterns with `extra_openings` / `extra_endings` (Lua patterns separated by `|`, matched against the lower-case title). Intros (`Intro`, `Avant`, `Prologue`, shown as **Saltar intro ›**) are on by default, because many releases name the opening song `Intro`; turn them off with `intros=no`. Outros (`Outro`, `Closing`, `Preview`, `PV`, shown as **Saltar avance ›**) are off by default; turn them on with `outros=yes`.

When the ending is the last chapter, skipping it moves on to the next playlist entry if there is one; otherwise it seeks to one second before the end, so the file finishes as it normally would.

The button follows the active palette (background and border from uosc's `background` and `foreground`, filled with `foreground` on hover). Position, size and opacity are set in `script-opts/sosc-skip.conf`. To use another key, bind `script-binding sosc_skip/skip` in `input.conf`.

## Thumbnails

Timeline thumbnails come from [thumbfast](https://github.com/po5/thumbfast), which uosc picks up automatically. thumbfast is not bundled (MPL-2.0); install `thumbfast.lua` into `scripts/` (the installer will do it). sosc ships `script-opts/thumbfast.conf` with thumbnails enabled on network streams (`network=yes`), GPU decoding (`hwdec=yes`) and the thumbnailer started only when the timeline is first hovered (`spawn_first=no`). On streams thumbfast opens its own connection, so it uses some extra bandwidth and the first thumbnail can take a moment. mpv.net 7+ is meant to work without extra setup, but some builds (seen with the AnimeJaNai bundle, mpv.net 7.1.2) do not report their path to thumbfast in time and it shows "install standalone mpv". In that case add the full path to `script-opts/thumbfast.conf`, e.g. `mpv_path=C:\Users\<you>\AppData\Local\Programs\mpv-AnimeJaNai\mpvnet.exe` (the installer will write it for you). On streams each new thumbnail takes a moment, since thumbfast has to fetch that part of the video over the network.

## Tests

From the repository root:

```
lua tests/test_palettes.lua
lua tests/test_title.lua
lua tests/test_speed.lua
lua tests/test_skip.lua
lua tests/test_subs.lua
lua tests/test_upscale.lua
pwsh -NoProfile -File tests/install.Tests.ps1
bash tests/make-release.test.sh
```

The installer tests need PowerShell 7 (on any system, no Pester) and simulate Windows folders, so they run on Linux too; they do not download anything. Some of them start a new `pwsh` and run the installer through `iex`, as a user would, to check that it neither exits nor leaves anything behind in the session. `tests/make-release.test.sh` builds a release in a throw-away copy of the repository and installs sosc from it.

## Making a release

The one-line install downloads `https://github.com/SCEPTICG/sosc/releases/latest/download/sosc.ps1`, which only works when every step below is done. For a release `v0.1.0`:

1. Commit everything and tag that commit. The tag must exist before building and point to the current commit, or the script refuses:

   ```
   git tag v0.1.0
   tools/make-release.sh v0.1.0
   ```

   It needs a clean work tree and builds, from that commit, `dist/sosc.zip` (`portable_config/`, `LICENSE`, `README.md`), `dist/sosc.ps1` (the installer with the version, the URL `https://github.com/SCEPTICG/sosc/releases/download/v0.1.0/sosc.zip` and that zip's SHA256 filled in) and `dist/SHA256SUMS`. It uploads nothing; `dist/` is not tracked.

2. Push the tag to the original repository: `git push origin v0.1.0`. The GitHub repository is a mirror of a Forgejo one (see [Contributing](#contributing)), so the tag reaches GitHub through the mirror: wait until `v0.1.0` shows up in GitHub's tag list (or sync the mirror by hand) before the next step.

3. On GitHub, create the release **from that existing tag** (choose `v0.1.0` in the tag list; do not let GitHub create a new tag, which would point to the tip of the default branch instead of the commit the files were built from).

4. Attach `dist/sosc.ps1`, `dist/sosc.zip` and `dist/SHA256SUMS` with exactly those names: `sosc.ps1` looks for `sosc.zip` under that tag, and the install line looks for `sosc.ps1`.

5. Publish it as the **Latest** release: not a draft and not a pre-release. `releases/latest/download/...` only sees the release marked Latest.

To try it before it becomes the Latest release, publish it first as a pre-release (a draft cannot be downloaded) and use the fixed address of its files, which works for any published release; then mark it Latest:

```
irm https://github.com/SCEPTICG/sosc/releases/download/v0.1.0/sosc.ps1 | iex
```

## Contributing

The GitHub repository is a read-only mirror of a self-hosted Forgejo repository, where the work happens. Issues are welcome on GitHub. Pull requests are not merged on GitHub, because the next sync of the mirror would overwrite them: a good one is applied by hand in the original repository, crediting its author, and reaches GitHub with the next sync.

## Credits

- [uosc](https://github.com/tomasklaen/uosc) by tomasklaen, LGPL-2.1.
- [thumbfast](https://github.com/po5/thumbfast) by po5, MPL-2.0.
- [Anime4K](https://github.com/bloc97/Anime4K) by bloc97, MIT.

None of them is included in this repository: the installer downloads them from their official sources (uosc 5.13.0, a fixed thumbfast commit and Anime4K v4.0.1, the last only if you want it) and checks their SHA256.

## License

MIT, see [LICENSE](LICENSE).
