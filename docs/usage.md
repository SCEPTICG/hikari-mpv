---
title: "hikari keys and configuration for mpv"
description: "Keyboard shortcuts and configuration files of hikari, a theme for the mpv video player built on uosc."
---

# Usage and configuration

## Keys and buttons

| Key | Action |
| --- | --- |
| `Alt+p` | Palette menu |
| `Alt+s` | Skip the current opening, intro or ending (while the button is on screen) |
| `Alt+t` | Subtitle menu (style, size, height) |
| `Alt+u` | New hikari version: release notes, update command (see [Update check](features/update-check.md)) |
| `Alt+l` | Language of hikari (and of uosc after a restart) (see [Languages](features/language.md)) |
| `Ctrl+1` … `Ctrl+6` | Anime4K modes A, B, C, A+A, B+B, C+A (when hikari installed Anime4K) |
| `Ctrl+7` | Anime4K *Automatic*: the mode from each video's resolution |
| `Ctrl+0` | Anime4K off |

The controls bar has up to five hikari buttons before *fullscreen*: subtitle style (text icon), *Upscaling* (sparkles icon, only for videos and only when Anime4K is installed), speed, palettes and *Update hikari* (download icon, only when a new hikari version is out). Their tooltips, like every hikari text, are in your [language](features/language.md). The *Skip opening ›* button appears at the bottom right during openings, intros and endings; click it or press `Alt+s`. A key you already use for something else is left to you: the installer says so, and you can bind another key to the same command (the commands are listed in each section below).

## Configuration

Everything lives in the player's config folder (the one the installer showed you):

| File | What it sets |
| --- | --- |
| `script-opts/uosc.conf` | uosc: timeline style and the buttons of the controls bar. |
| `script-opts/thumbfast.conf` | Thumbnails: on streams, GPU decoding, size. |
| `script-opts/hikari-skip.conf` | Skip button: which chapters, extra title patterns, position, size, opacity. |
| `script-opts/hikari-title.conf` | Titles: on/off and tidying of release names. |
| `script-opts/hikari-update.conf` | Update check: on/off and hours between checks. |
| `hikari-palette.conf`, `hikari-subs.conf`, `hikari-upscale.conf`, `hikari-language.conf` | Your chosen palette, subtitle style, Anime4K mode and quality, and language, saved by the menus. Kept on update. |
| `script-modules/hikari-i18n.lua` | hikari's texts in its 13 languages, shared by its scripts (replaced on update). |

Updating hikari replaces the `script-opts` files above with hikari's (your earlier `uosc.conf` and `thumbfast.conf` are kept in `hikari-originales` and put back on uninstall), so keep a copy of any change you make to them. Your own `mpv.conf` and `input.conf` lines are never changed: only the marked hikari block is.

## Example: audio and subtitle languages

hikari already picks audio and subtitle languages from its own [language](features/language.md#audio-and-subtitles): the dub in your language when there is one, otherwise Japanese with subtitles in your language. You only need your own lines for a different preference, and each line you write wins over hikari for that option. For example, to always play the Japanese audio and still get hikari's subtitle language:

```
alang=ja,jpn
```

`alang` and `slang` list the preferred audio and subtitle languages in order; `subs-with-matching-audio` says what to do when the audio is already in the subtitle language: `no` turns no subtitles on, `forced` only the forced ones (signs and song lyrics), `yes` (mpv's default) turns them on as usual. hikari uses `forced`. A `slang` line of yours also takes `subs-with-matching-audio` out of hikari's hands, so write both if you want a value other than `yes`. Put your lines before the hikari block. If you used the old recipe of this page (`alang=spa,es,es-ES,ja,jpn`, `slang=spa,es,es-ES`, `subs-with-matching-audio=no`), you can delete those lines and let hikari do the same, with the regional codes too, with the signs and songs of a Spanish dub kept, and telling the Spanish of Spain from the Latin American one when both tracks are tagged `es`.
