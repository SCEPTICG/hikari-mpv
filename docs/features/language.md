---
title: "hikari in your language: 13 languages for mpv and uosc"
description: "hikari's menus, buttons and messages in mpv come in the 13 languages of uosc. It follows your system, Alt+l changes it, uosc follows hikari, and so do the audio and subtitle tracks mpv picks."
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

## Audio and subtitles

hikari's language also decides which audio and subtitle tracks mpv picks on its own, with a recipe made for anime:

- **Audio**: a dub in your language when the file has one, otherwise Japanese.
- **Subtitles**: in your language. When the audio already is in your language, the dialogue subtitles stay off (a dub needs no subtitles on top), but forced subtitles still show: the track that only translates signs, on-screen text and song lyrics, which the dub does not cover. mpv knows it by the *forced* mark of the track.

With Spanish, that is the same as these three lines in `mpv.conf`:

```
alang=es,spa,es-ES,es-419,ja,jpn
slang=es,spa,es-ES,es-419
subs-with-matching-audio=forced
```

There is nothing to turn on: it follows the language menu. Each language has its own list of codes:

| Language | Codes |
| --- | --- |
| English | `en,eng,en-US,en-GB` |
| Español | `es,spa,es-ES,es-419` |
| Deutsch | `de,ger,deu,de-DE` |
| Français | `fr,fre,fra,fr-FR,fr-CA` |
| Italiano | `it,ita,it-IT` |
| Polski | `pl,pol,pl-PL` |
| Português | `pt,por,pt-BR,pt-PT` |
| Română | `ro,rum,ron,ro-RO` |
| Русский | `ru,rus,ru-RU` |
| Türkçe | `tr,tur,tr-TR` |
| Українська | `uk,ukr,uk-UA` |
| 中文（香港） | `zh-Hant,zh-HK,zh-TW,zh,chi,zho,zh-Hans,zh-CN` |
| 简体中文 | `zh-Hans,zh-CN,zh,chi,zho,zh-Hant,zh-TW` |

Japanese (`ja,jpn`) follows in the audio list. The regional codes are there because of how mpv 0.40 ranks tracks: a dub tagged `es-419` or `pt-BR`, as many releases tag them, would otherwise lose to a `jpn` track. A region that is not in the list (say `es-AR`) still beats Japanese tagged `ja-JP`, but not a plain `ja` or `jpn`. Chinese lists its own script first and the other one last, so a Chinese dub tagged with any code of its list (or just `zh`) beats Japanese, whatever its script. A longer tag such as `zh-Hans-CN` or `zh-Hant-TW` is in neither list and, like an unlisted region, loses to a plain `ja` or `jpn`. Tracks with no language at all are left to mpv's usual rules.

### When it applies

- **When mpv starts**, before the first file opens, so the first episode already gets it.
- **After every switch with `Alt+l`**. If a file is playing, mpv picks its tracks again with the new languages, but only the ones it picked on its own: an audio or subtitle track you chose yourself (from the menu, with a key, with `--aid`/`--sid` or saved with your position) stays. The next files use the new languages anyway.

hikari only sets these options while mpv runs; it writes them to no file, so uninstalling hikari leaves nothing behind.

### Your own settings win

If you already set `alang`, `slang` or `subs-with-matching-audio` yourself, hikari leaves that option alone:

- **Audio and subtitles are separate.** With an `alang` of your own, hikari still sets the subtitles, and the other way round.
- **The subtitles go together, all or nothing.** `subs-with-matching-audio` only makes sense with the `slang` it goes with, so with a `slang` of your own hikari leaves `subs-with-matching-audio` alone too, even if you never set it (mpv's default then applies). With only `subs-with-matching-audio` of your own, hikari still sets `slang`.

It checks each option when mpv starts and takes it as yours when:

- it was set on the command line, or
- it no longer holds mpv's default value: from your `mpv.conf`, a file it includes, a profile applied at start, the settings of mpv.net or another script, or
- the `mpv.conf` of your config folder (`~~/mpv.conf`) has a line for it outside the hikari block and outside any `[profile]`, even one that writes mpv's default value (`subs-with-matching-audio=yes`).

It also stays away from an option that someone changed after hikari set it (`set alang ...` in the console, another script, an auto profile while it is active).

The only setting hikari cannot see is one that writes mpv's default value from somewhere other than that `mpv.conf` (an included file, `/etc/mpv/mpv.conf`, or a profile applied at start). Profiles that apply on their own later (with `profile-cond`) set their values over hikari's while they are active, as usual.

**To let hikari decide**, delete your `alang`, `slang` and `subs-with-matching-audio` lines from `mpv.conf` (all of them, or just the ones you want hikari to take over) and restart mpv. To keep some preference of your own, keep only that line: for example, `alang=ja,jpn` always plays the Japanese audio, and hikari still picks the subtitles in your language. A `slang` line takes the subtitles out of hikari's hands, as said above: add your own `subs-with-matching-audio` line if mpv's default (`yes`) is not what you want.

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
