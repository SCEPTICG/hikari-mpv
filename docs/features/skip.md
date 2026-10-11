---
title: "Skip opening and ending button for mpv"
description: "hikari shows a Skip opening button in mpv while a chapter looks like an anime opening, intro or ending, or, without such chapters, at the times AniSkip knows. One click or Alt+s skips it."
---

# Skip openings and endings

`hikari-skip.lua` shows a **Skip opening ›** / **Skip ending ›** button (in your [language](language.md): *Saltar opening ›* in Spanish, *跳过片头 ›* in Simplified Chinese...) at the bottom right, above uosc's controls, for as long as playback is inside a chapter that looks like an opening or an ending, even when uosc's controls are hidden or playback is paused. Clicking it, or pressing `Alt+s`, jumps to the start of the next chapter. Files that do not mark their opening and ending with chapters get the times from [AniSkip](#aniskip) instead. Outside those ranges, while idle and while a uosc menu or the console is open, nothing is drawn and the mouse is left to uosc and mpv.

Chapters are recognised by title, with the same rules uosc uses to colour its chapter ranges: `OP`, `Opening`, `... OP`, `... Opening` and `オープニング` for openings (only when another chapter follows), `ED`, `Ending`, `ED ...`, `Ending ...`, `... ED`, `... Ending`, `Credits`, `Credits ...`, `... Credits` and `エンディング` for endings. Titles such as `Operation`, `OP1` or `Opening Night` do not count; add your own patterns with `extra_openings` / `extra_endings` (Lua patterns separated by `|`, matched against the lower-case title). Intros (`Intro`, `Avant`, `Prologue`, shown as **Skip intro ›**) are on by default, because many releases name the opening song `Intro`; turn them off with `intros=no`. Outros (`Outro`, `Closing`, `Preview`, `PV`, shown as **Skip preview ›**) are off by default; turn them on with `outros=yes`.

When the ending is the last chapter, skipping it moves on to the next playlist entry if there is one; otherwise it seeks to one second before the end, so the file finishes as it normally would.

## AniSkip

Many fansub releases have no chapters, or none named after the opening or the ending. For those, hikari asks [AniSkip](https://aniskip.com), a free, community-made database of opening and ending times, and the button shows at those times, the same as with chapters (same label, `Alt+s`, click). It is on by default, and only for files that:

- **do not have opening, intro or ending chapters**: when the file has them, they are used and nothing is asked;
- **look like an anime episode**: a release name with one episode number and a sign of anime, such as a `[Group]` in front, the `Show - 05` style or an anime service (`CR`, `HIDIVE`...) in the name: `[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv`, `Show S2 - 05`, `Show.S02E05.1080p.CR.WEB-DL.mkv`. Streams from Seanime and similar servers count too, through the file name they carry. Films, specials, OVAs, half episodes (`12.5`) and names that do not look like anime are never looked up.

**What is sent, and to whom.** Three public services, without an account or a key, through `curl` in the background (playback never waits):

1. To **AniList** (`graphql.anilist.co`): the series name as hikari reads it from the file name (`Sousou no Frieren`), to find its MyAnimeList id. Only if AniList cannot be reached or answers with an error, the same name goes to **Jikan** (`api.jikan.moe`, an unofficial MyAnimeList API) instead.
2. To **AniSkip** (`api.aniskip.com`): that MyAnimeList id and the episode number (`52991`, episode `5`).

Nothing else: not the file name, the folder, the release group or the file itself. Like any visit to a website, each request also tells those servers your IP address and that it comes from curl. The answers are kept in `hikari-aniskip.json` in your config folder (the MyAnimeList id for 30 days, the times for 30 days; a "not found" for 7 days and 3 days), so watching an episode again, or the next one of the same series, sends nothing or only the AniSkip request.

**When it shows nothing.** hikari would rather show no button than a wrong one. The series must match an AniList title exactly (romaji, English, Japanese or a synonym; for a later season, as `Show 2nd Season`, `Show Season 2` or `Show 2`), and only one series may match. The times must have been submitted for an episode of the same length as yours (within 10 seconds), so a release with another cut gets nothing. Without `curl`, without network or when a service fails, nothing is shown (the next time it asks again). Times that arrive after the opening is over change nothing; the ending button still shows when its time comes. Openings and endings follow the same `openings` and `endings` settings as chapters.

To turn it off, set `aniskip=no` in `script-opts/hikari-skip.conf`; updating hikari replaces that file, so to keep it off for good add this line to your own `mpv.conf` instead (outside the hikari block):

```
script-opts-append=hikari-skip-aniskip=no
```

The series name and episode come from [hikari-title.lua](titles.md), whatever its own settings say; without that script, AniSkip is never asked.

## Look and settings

The button follows the active palette (background and border from uosc's `background` and `foreground`, filled with `foreground` on hover). Position, size and opacity are set in `script-opts/hikari-skip.conf`. To use another key, bind `script-binding hikari_skip/skip` in `input.conf`.
