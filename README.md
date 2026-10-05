# sosc

A cross-platform mpv theme (Windows, Linux, macOS) built on top of [uosc](https://github.com/tomasklaen/uosc), with its own palette, thumbnails via [thumbfast](https://github.com/po5/thumbfast), and a few extras such as skipping anime openings and endings.

Work in progress.

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
```

## License

MIT. uosc (LGPL-2.1) and thumbfast (MPL-2.0) are not included in this repository; the installer downloads them from their official releases.
