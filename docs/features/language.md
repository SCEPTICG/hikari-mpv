---
title: "hikari in your language: 13 languages for mpv and uosc"
description: "hikari's menus, buttons and messages in mpv come in the 13 languages of uosc. It follows your system, Alt+l changes it, uosc follows hikari, and so do the audio and subtitle tracks mpv picks, Spain or Latin America, Brazil or Portugal included."
---

# Languages

Everything hikari shows in mpv (its menus, the tooltips of its buttons, the *Skip opening ›* button, its messages and the season and episode labels of [titles](titles.md)) comes in the 13 languages of uosc 5.13:

| | | | |
| --- | --- | --- | --- |
| English | Español (España) | Español (Latinoamérica) | Deutsch |
| Français | Italiano | Polski | Português (Brasil) |
| Português (Portugal) | Română | Русский | Türkçe |
| Українська | 中文（香港） | 简体中文 | |

Spanish and Portuguese come twice, once per [regional variant](#spanish-and-portuguese-two-variants): both read the same texts, and they differ in the audio and subtitle tracks hikari prefers. Palette names (Catppuccin, Nord, SCEPTIC...) are names, so they stay as they are. The installer itself only speaks English and Spanish.

## Your system's language, by default

On a first install, the installer writes your system's language to `~~/hikari-language.conf`: the Windows display language, the first preferred language of macOS, or `LC_ALL`, `LC_MESSAGES` or `LANG` on Linux. The region picks the variant: Spanish from Spain (or with no region) is *Español (España)*, Spanish from anywhere else (Mexico, Argentina, `es-419`...) is *Español (Latinoamérica)*; Portuguese from Brazil (or with no region) is *Português (Brasil)*, from Portugal or anywhere else *Português (Portugal)*. Simplified Chinese (China, Singapore) is *简体中文*; Traditional Chinese (Taiwan, Hong Kong, Macau) is *中文（香港）*; any other language is English. Updates keep your choice.

Without that file (a copy made by hand), hikari follows `LC_ALL`, `LC_MESSAGES` or `LANG` and otherwise speaks English.

## Changing it

`Alt+l` opens the language menu, with each language written in itself and the current one marked. Pick one and hikari switches at once: open menus are redrawn, the skip button and the title of the file playing change, and the choice is saved for the next start.

uosc's own menus and buttons (*Subtitles*, *Playlist*, *Chapters*...) are translated by uosc, which only reads its translations when mpv starts. hikari tells uosc the same language (the `uosc-languages` script option), so after a switch a short message reminds you to restart mpv to translate uosc's menus too. Until then, uosc follows the language it started with.

`Alt+l` is listed in uosc's *Key bindings* menu, but not in uosc's main menu: uosc only builds that menu from `input.conf` when `input.conf` describes all of it, and hikari leaves uosc's default menu as it is.

To bind another key, use `script-binding hikari_language/open-menu` in `input.conf`.

## Audio and subtitles

hikari's language also decides which audio and subtitle tracks mpv picks on its own, with a recipe made for anime:

- **Audio**: a dub in your language when the file has one (for Spanish and Portuguese, [of your variant](#spanish-and-portuguese-two-variants)), otherwise Japanese.
- **Subtitles**: in your language. When the audio already is in your language, the dialogue subtitles stay off (a dub needs no subtitles on top), but forced subtitles still show: the track that only translates signs, on-screen text and song lyrics, which the dub does not cover. mpv knows it by the *forced* mark of the track.

With *Español (España)*, that is the same as these three lines in `mpv.conf`:

```
alang=es-ES,es,spa,es-419,es-MX,ja,jpn
slang=es-ES,es,spa,es-419,es-MX
subs-with-matching-audio=forced
```

plus [the choice between two tracks of the same language](#spanish-and-portuguese-two-variants), which mpv cannot do on its own. There is nothing to turn on: it follows the language menu. Each entry has its own list of codes:

| Language | Codes |
| --- | --- |
| English | `en,eng,en-US,en-GB` |
| Español (España) | `es-ES,es,spa,es-419,es-MX` |
| Español (Latinoamérica) | `es-419,es,spa,es-MX,es-ES` |
| Deutsch | `de,ger,deu,de-DE` |
| Français | `fr,fre,fra,fr-FR,fr-CA` |
| Italiano | `it,ita,it-IT` |
| Polski | `pl,pol,pl-PL` |
| Português (Brasil) | `pt-BR,pt,por,pt-PT` |
| Português (Portugal) | `pt-PT,pt,por,pt-BR` |
| Română | `ro,rum,ron,ro-RO` |
| Русский | `ru,rus,ru-RU` |
| Türkçe | `tr,tur,tr-TR` |
| Українська | `uk,ukr,uk-UA` |
| 中文（香港） | `zh-Hant,zh-HK,zh-TW,zh,chi,zho,zh-Hans,zh-CN` |
| 简体中文 | `zh-Hans,zh-CN,zh,chi,zho,zh-Hant,zh-TW` |

Japanese (`ja,jpn`) follows in the audio list. The regional codes are there because of how mpv 0.40 ranks tracks: a dub tagged `es-419` or `pt-BR`, as many releases tag them, would otherwise lose to a `jpn` track. A region that is not in the list (say `es-AR`) still beats Japanese tagged `ja-JP`, but not a plain `ja` or `jpn`. Each variant lists its own region first: mpv takes a track tagged just `es` or `spa` as a match for `es-ES` too, so for Spain `es-ES` and `es` rank the same and `es-419` comes after them, and the other way round for Latin America. Chinese lists its own script first and the other one last, so a Chinese dub tagged with any code of its list (or just `zh`) beats Japanese, whatever its script. A longer tag such as `zh-Hans-CN` or `zh-Hant-TW` is in neither list and, like an unlisted region, loses to a plain `ja` or `jpn`. Tracks with no language at all are left to mpv's usual rules.

### Spanish and Portuguese: two variants

mpv only compares language tags, and many releases tag both variants alike. Crunchyroll, for instance, ships two Spanish subtitle tracks, both tagged `es`: *Spanish(Latin_America)* first and *Spanish* (Spain) after it, so mpv on its own always takes the Latin American one. hikari tells them apart:

1. mpv picks the tracks as usual, with the lists above.
2. If the audio track mpv picked is in your language but of the other variant, and the file has another audio track in your language of your variant, hikari switches to it. Then the same for the subtitles. It only swaps like for like: forced subtitles (signs and songs) for forced ones, full subtitles for full ones, external files for external files.
3. A track's variant comes from the region in its tag (`es-ES`; `es-419`, `es-MX`, `es-AR`...; `pt-BR`; `pt-PT`), or else from its title:

    | Variant | Words in the title |
    | --- | --- |
    | Español (España) | España, Spain, Castilian, Castellano, [ESP], European |
    | Español (Latinoamérica) | Latin, Latino, Latinoamérica, LATAM, América, 419 |
    | Português (Brasil) | Brazil, Brasil, BR |
    | Português (Portugal) | Portugal, European |

    A Spanish track whose tag and title say nothing counts as Spain's (Crunchyroll only names the Latin American one). A Portuguese one could be either, and loses only to a track of your variant.

4. Some releases put the signs and songs in a track without the *forced* mark, titled *Spanish [Signs]*, *Signs & Songs*, *Carteles*, *Forced* or the like. When mpv picks one of those as your subtitles and the file has full subtitles in your language, hikari takes the full ones, even of the other variant: dialogue with another accent is better than signs only. If that track is the only one in your language, it stays. A title that also says the subtitles are full ones, such as *Full + Songs*, *Dialogue + Signs* or *Spanish (non-forced)*, does not count as signs only.

So with *Español (España)* that Crunchyroll file plays the *Spanish* subtitles, and with *Español (Latinoamérica)* the Latin American ones. With a dub of your variant, the forced signs track of your variant is preferred too.

**A dub of the other variant does not count as yours.** Say you picked *Español (España)* and the file has the Japanese audio, a Latin American dub and Spanish subtitles from Spain. mpv on its own would play the Latin American dub (it is Spanish, and Spanish comes before Japanese) and show no subtitles. hikari plays the Japanese audio instead, with the full subtitles of Spain. The same the other way round (*Español (Latinoamérica)* and only a dub from Spain) and for Brazil and Portugal. This needs the dub's tag or title to say which variant it is (`es-419`, `es-MX`, *Spanish(Latin_America)*, *Castellano*...): a dub tagged just `spa` with no telling title could be yours, so it plays. It also needs a Japanese audio track; without one, the dub stays. With an `alang` of your own, the dub is your list's choice and hikari leaves it.

Some things stay as they are:

- **Subtitles of the other variant only**: they are used. Subtitles with another accent are better than none.
- **Whether to show subtitles** is still mpv's decision with the options above (with a dub in your language, only forced ones): hikari only changes which track of your language is used, and plays Japanese instead of a dub of the other variant.
- **Tracks you chose** (menu, keys, `--aid`/`--sid`, a resumed position) are never touched, and neither is anything with `lavfi-complex`.
- **It lasts for that file only.** The next file starts again from mpv's own choice.
- **Your own `alang` or `slang`** still win. With hikari's lists, hikari may take any track of your language. With a list of yours (or one changed since hikari set it), hikari only chooses between tracks with the same language tag, the ones no list can tell apart: two tracks tagged `es` (or `es` and `spa`, which are the same for mpv), but not `es-419` and `spa`. So with `slang=es-419,en` in your `mpv.conf`, a track tagged `es-419` stays even next to a `spa` one titled *CR_Spanish*. The signs rule above still works with a `slang` of your own, but only between tracks with the same tag, the ones your list does not tell apart.

A script of your own that sets `aid` or `sid` (such as a `sub-castellano.lua` that picks the Spanish subtitles by their title) wins over hikari: once it has picked a track, mpv no longer treats the choice as its own and hikari leaves it. If hikari's choice is what you wanted, you can remove that script.

### When it applies

- **When mpv starts**, before the first file opens, so the first episode already gets it.
- **When each file is loaded**, for the [choice between variants](#spanish-and-portuguese-two-variants).
- **After every switch with `Alt+l`** (also between the two variants of a language). If a file is playing, mpv picks its tracks again with the new languages, and hikari checks the variant again, but only for the tracks picked automatically: an audio or subtitle track you chose yourself (from the menu, with a key, with `--aid`/`--sid` or saved with your position) stays. The next files use the new languages anyway.

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

The values that AnimeJaNai comes with are the exception: see [AnimeJaNai](#animejanai) below.

The only setting hikari cannot see is one that writes mpv's default value from somewhere other than that `mpv.conf` (an included file, `/etc/mpv/mpv.conf`, or a profile applied at start). Profiles that apply on their own later (with `profile-cond`) set their values over hikari's while they are active, as usual.

**To let hikari decide**, delete your `alang`, `slang` and `subs-with-matching-audio` lines from `mpv.conf` (all of them, or just the ones you want hikari to take over) and restart mpv. To keep some preference of your own, keep only that line: for example, `alang=ja,jpn` always plays the Japanese audio, and hikari still picks the subtitles in your language. A `slang` line takes the subtitles out of hikari's hands, as said above: add your own `subs-with-matching-audio` line if mpv's default (`yes`) is not what you want.

### AnimeJaNai

AnimeJaNai ships `portable_config/mpv-animejanai.conf`, which its configuration includes, with these two lines:

```
alang = 'jpn'
slang = 'eng'
```

They are AnimeJaNai's defaults rather than a choice of yours, so hikari does not count them as yours and applies its recipe over them. It checks it by reading that file the same way as `mpv.conf` (comments and `[profile]` sections do not count) and only when all of this holds:

- `alang` still holds `jpn` (or `slang` holds `eng`) when mpv starts, and
- `mpv-animejanai.conf` sets it in that one line, as it comes, and nowhere else in the file (no `alang-append` and the like), and
- neither your `mpv.conf` nor the command line sets it.

Change the line to anything else (say `alang = 'jpn,eng'`) and it is yours again: hikari leaves it alone. hikari never writes to `mpv-animejanai.conf`.

## By hand

`~~/hikari-language.conf` (in the mpv config folder, `portable_config/` in a portable install) holds two lines, which you can also write yourself:

```
script-opts-append=hikari-language=es-ES
script-opts-append=uosc-languages=es,en
```

The codes are those of the menu: `en`, `es-ES`, `es-419`, `de`, `fr`, `it`, `pl`, `pt-BR`, `pt-PT`, `ro`, `ru`, `tr`, `uk`, `zh-HK` and `zh-hans`. uosc has no regional variants, so it gets `es` or `pt`. A plain `es` or `pt`, as hikari 0.5 saved them, still works: it means *Español (España)* or *Português (Brasil)*; pick your variant once with `Alt+l` if that is not yours. Uninstalling asks whether to delete this file together with your other choices.

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
