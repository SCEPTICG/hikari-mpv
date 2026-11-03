---
title: "What's new in hikari"
description: "The new features of each hikari version, newest first: automatic skip of openings and endings, suji, continue watching, AniSkip, your language and more."
---

# What's new

The new features of each hikari version, newest first. Smaller versions in between (0.11.1, 0.11.2...) fix things and are listed with their notes on [GitHub releases](https://github.com/SCEPTICG/hikari-mpv/releases).

To update, run the same command you installed with (see [Windows](install/windows.md) or [macOS and Linux](install/macos-linux.md)): your choices are kept. hikari tells you when a new version is out (see [Update check](features/update-check.md)).

## 0.11: openings and endings skip themselves

*October 2026*

- **Automatic skip.** hikari can skip openings, endings or both without you pressing the button. It is off until you turn it on: with **`Alt+Shift+s`**, with its button in the controls or with `auto_skip` in `hikari-skip.conf`. It only skips when playback reaches the opening or ending, never when you go back to it yourself, and for 5 seconds afterwards the button reads **‹ Watch opening** to go back. See [Automatic skip](features/skip.md#automatic-skip).
- **Language and automatic-skip buttons** in the controls, so neither needs a key.

Since then: with the pointer on the skip button the controls show whole instead of half faded (0.11.3), and the skip button finds more series on AniSkip, also through Seanime (0.11.4 and 0.11.5).

## 0.10: hikari without uosc, and suji

*October 2026*

- **suji (experimental).** The installer asks which interface you want: uosc, as before, or [suji](https://github.com/SCEPTICG/suji), hikari's own controls bar for mpv. hikari's buttons, the skip button and the episode title all work in suji. See [Compatibility](compatibility.md).
- **hikari works without uosc.** If uosc is missing, hikari's menus open in mpv's own selector (mpv 0.39 or newer).

## 0.9: continue watching by series

*October 2026*

- **One row per series** in the Continue watching list. Once you finish an episode, the row offers the **Next** one from the same folder, or reads **Up to date** until it lands. See [Continue watching](features/resume.md#series).
- **Next episode.** At the end of an episode, hikari queues the next one from the folder, and the skip button becomes **Next episode ›** at the final ending.
- **Cleaner folder playlists:** posters and thumbnails in the folder no longer end up in the playlist.

## 0.8: continue where you left off

*October 2026*

- Open a file you left half-watched and mpv asks: **Continue from 12:34** or **Start from the beginning**. `Alt+r`, or the clock button, lists what you left half-watched. Files on your disk or a network share only, never streams. See [Continue watching](features/resume.md).

## 0.7: skip openings without chapters

*October 2026*

- **AniSkip.** The skip button also works on episodes with no chapters, with the times other viewers submitted to [AniSkip](https://aniskip.com). See [AniSkip](features/skip.md#aniskip) for what is sent and how to turn it off.
- **See your version.** The installer can show the hikari version in each mpv folder and whether a newer one exists, changing nothing.

## 0.6: audio and subtitles in your language

*October 2026*

- The language you pick in hikari also picks the tracks: your language when the episode is dubbed, otherwise Japanese with full subtitles in your language. Your own `alang` and `slang` settings still win. See [Languages](features/language.md).
- **Regional variants:** Spanish (Spain or Latin America) and Portuguese (Brazil or Portugal).

## 0.5: your language, and clean titles

*October 2026*

- hikari's buttons and menus in **13 languages**, picked from your system and changed with **`Alt+l`**. See [Languages](features/language.md).
- **Clean titles** for downloaded files too: `[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv` shows as *Sousou no Frieren · S1 E05*. See [Titles](features/titles.md).

## 0.4: sosc is now hikari

*October 2026*

- Same theme, new name. The installer moves a sosc install to hikari and keeps your choices.

## 0.1 to 0.3: the beginning

*October 2026*

- **0.3:** hikari tells you when a new version is out, and never updates by itself. See [Update check](features/update-check.md).
- **0.2:** the macOS installer, and Anime4K's automatic mode, which picks the upscaling from the video's height. See [Anime4K](features/anime4k.md).
- **0.1:** the first version, for Windows: the palette menu, the skip buttons, readable stream titles, the speed and subtitle style menus, and timeline thumbnails.
