---
title: "hikari in your language: 13 languages for mpv and uosc"
description: "hikari's menus, buttons and messages in mpv come in the 13 languages of uosc. It follows your system, Alt+l changes it, and uosc follows hikari."
---

# Languages

Everything hikari shows in mpv (its menus, the tooltips of its buttons, the *Skip opening ›* button, its messages and the season and episode labels of [titles](titles.md)) comes in the 13 languages of uosc 5.13:

| | | | |
| --- | --- | --- | --- |
| English | Español | Deutsch | Français |
| Italiano | Polski | Português | Română |
| Русский | Türkçe | Українська | 中文（香港） |
| 简体中文 | | | |

Palette names (Catppuccin, Nord, SCEPTIC...) are names, so they stay as they are. The installer itself only speaks English and Spanish.

## Your system's language, by default

On a first install, the installer writes your system's language to `~~/hikari-language.conf`: the Windows display language, the first preferred language of macOS, or `LC_ALL`, `LC_MESSAGES` or `LANG` on Linux. Portuguese from Brazil or Portugal is *Português*; Simplified Chinese (China, Singapore) is *简体中文*; Traditional Chinese (Taiwan, Hong Kong, Macau) is *中文（香港）*; any other language is English. Updates keep your choice.

Without that file (a copy made by hand), hikari follows `LC_ALL`, `LC_MESSAGES` or `LANG` and otherwise speaks English.

## Changing it

`Alt+l` opens the language menu, with each language written in itself and the current one marked. Pick one and hikari switches at once: open menus are redrawn, the skip button and the title of the file playing change, and the choice is saved for the next start.

uosc's own menus and buttons (*Subtitles*, *Playlist*, *Chapters*...) are translated by uosc, which only reads its translations when mpv starts. hikari tells uosc the same language (the `uosc-languages` script option), so after a switch a short message reminds you to restart mpv to translate uosc's menus too. Until then, uosc follows the language it started with.

`Alt+l` is listed in uosc's *Key bindings* menu, but not in uosc's main menu: uosc only builds that menu from `input.conf` when `input.conf` describes all of it, and hikari leaves uosc's default menu as it is.

To bind another key, use `script-binding hikari_language/open-menu` in `input.conf`.

## By hand

`~~/hikari-language.conf` (in the mpv config folder, `portable_config/` in a portable install) holds two lines, which you can also write yourself:

```
script-opts-append=hikari-language=es
script-opts-append=uosc-languages=es,en
```

The codes are those of the menu: `en`, `es`, `de`, `fr`, `it`, `pl`, `pt`, `ro`, `ru`, `tr`, `uk`, `zh-HK` and `zh-hans`. Uninstalling asks whether to delete this file together with your other choices.

## uosc's own language setting

The second line sets uosc's `languages` option, and a script option set in `mpv.conf` wins over the same option in `script-opts/uosc.conf`. So once the installer or `Alt+l` has written this file, hikari's language also decides uosc's: a `languages=` line of yours in `uosc.conf` is ignored, and uosc no longer follows `slang` (its default, `slang,en`, picks the language of your preferred subtitles).

To give that back to uosc and keep hikari's language for hikari only, add a file of your own after hikari's, for example `~~/my-uosc-language.conf` with this line:

```
script-opts-remove=uosc-languages
```

and include it at the end of your `mpv.conf`, after the hikari block:

```
include="~~/my-uosc-language.conf"
```

It has to be an `include`: mpv reads the included files after the rest of `mpv.conf`, in order, so a `script-opts-remove` line written straight into `mpv.conf` would run before hikari's file and change nothing. `Alt+l` rewrites `hikari-language.conf`, but not your file, so this keeps working after every switch; uosc then reads `languages` from `uosc.conf` again (or uses `slang,en`). The only side effect is that the reminder to restart mpv shows after every switch, since hikari no longer knows uosc's language. To undo it, delete the `include` line.

## How the button tooltips are translated

uosc translates the tooltips of its own buttons, but the tooltip of a custom button is the text after `?` in the `controls` line of `script-opts/uosc.conf`, shown as it is. hikari's `uosc.conf` writes them in English; `hikari-language.lua` gives hikari's buttons (subtitle style, upscaling, speed, palettes, update) the tooltip in your language when mpv starts and after every switch. Your own buttons and the rest of the `controls` line are left exactly as you wrote them.

## Better translations

The translations are in `portable_config/script-modules/hikari-i18n.lua`, one entry per text with every language side by side. If a text reads wrong in your language, [open an issue](https://github.com/SCEPTICG/hikari-mpv/issues) or a pull request with a better one.
