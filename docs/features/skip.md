---
title: "Skip opening and ending button for mpv"
description: "hikari shows a Skip opening button in mpv while a chapter looks like an anime opening, intro or ending, or, without such chapters, at the times AniSkip knows. One click or Alt+s skips it."
---

# Skip openings and endings

`hikari-skip.lua` shows a **Skip opening ›** / **Skip ending ›** button (in your [language](language.md): *Saltar opening ›* in Spanish, *跳过片头 ›* in Simplified Chinese...) at the bottom right, above uosc's controls, for as long as playback is inside a chapter that looks like an opening or an ending, even when uosc's controls are hidden or playback is paused. Clicking it, or pressing `Alt+s`, jumps to the start of the next chapter. Files that do not mark their opening and ending with chapters get the times from [AniSkip](#aniskip) instead. Outside those ranges, while idle and while a uosc menu or the console is open, nothing is drawn and the mouse is left to uosc and mpv.

Chapters are recognised by title, with the same rules uosc uses to colour its chapter ranges: `OP`, `Opening`, `... OP`, `... Opening` and `オープニング` for openings (only when another chapter follows), `ED`, `Ending`, `ED ...`, `Ending ...`, `... ED`, `... Ending`, `Credits`, `Credits ...`, `... Credits` and `エンディング` for endings. Titles such as `Operation`, `OP1` or `Opening Night` do not count; add your own patterns with `extra_openings` / `extra_endings` (Lua patterns separated by `|`, matched against the lower-case title). Intros (`Intro`, `Avant`, `Prologue`, shown as **Skip intro ›**) are on by default, because many releases name the opening song `Intro`; turn them off with `intros=no`. Outros (`Outro`, `Closing`, `Preview`, `PV`, shown as **Skip preview ›**) are off by default; turn them on with `outros=yes`.

When the ending is the last chapter, skipping it moves on to the next playlist entry if there is one; otherwise it seeks to one second before the end, so the file finishes as it normally would.

## Next episode

For episodes of a series on your disk or a network share, [continue watching](resume.md#series) finds the next episode in the folder (and queues it, unless you turned that off). When that next episode is the next entry of mpv's playlist, the button at the end of the episode reads **Next episode ›** and plays it:

- instead of **Skip ending ›**, when the ending is the last chapter;
- after an ending that [AniSkip](#aniskip) knows, when less than 10 seconds of the file are left after it: the button stays until the end;
- for the last 5 % of an episode with no known ending (no ending chapter and nothing from AniSkip). With `endings=no` the ending chapters do not count either, so the button shows there even in an episode that has one.

Click or `Alt+s`, as always. Streams (Seanime and similar apps) are left as they were. It needs continue watching: with `enabled=no` in `hikari-resume.conf` there is no *Next episode ›* button. To keep the button as it was, set `next_episode=no` in `script-opts/hikari-skip.conf` (or add `script-opts-append=hikari-skip-next_episode=no` to your own `mpv.conf`, since updating replaces that file).

## AniSkip

Many fansub releases have no chapters, or none named after the opening or the ending. For those, hikari asks [AniSkip](https://aniskip.com), a free, community-made database of opening and ending times, and the button shows at those times, the same as with chapters (same label, `Alt+s`, click). Openings and endings that AniSkip marks as mixed with scenes of the episode are offered for skipping too, as openings and endings. It is on by default, and only for files that:

- **do not have opening, intro or ending chapters**: when the file has them, they are used and nothing is asked;
- **look like an anime episode**: a release name with one episode number and, besides it, a clear sign of an anime release. That is one of these three:
    - a `[Group]` in front (with letters: `[2024]` or `[01]` are not groups);
    - an anime service (`CR`, `Crunchyroll`, `HIDIVE`, `ADN`, `FUNI`, `Funimation`, `B-Global`, `Bilibili`) after the episode number: in the technical tail on its own, or in brackets together with at least one resolution, source or CRC (a lone `(ADN)` or `[CR]` is not enough);
    - the `Show - 05` style together with **two** of these after the episode number: a resolution (`1080p`, `720p`, `2160p`...), a source (`BD`, `BluRay`, `WEB-DL`, `WEBRip`...) and a CRC (`[ABCD1234]`). One alone is not enough: a `(1080p)` or a CRC is easy to find on a personal video.

    After the episode number, a service, resolution, source or CRC only counts in two places:

    - **inside brackets or parentheses made only of technical words**: resolutions, sources, codecs, audio formats, services, a CRC and release labels such as `Multiple Subtitle`, `MultiSub`, `Multi-Subs`, `Dual Audio` or `Uncensored` (`[1080p]`, `(HIDIVE)`, `[ABCD1234]`, `[1080p CR WEB-DL AVC AAC]`). A group with any other word, such as `(prueba ADN Garcia)` or `[Prueba ADN]`, counts for nothing;
    - **in the technical tail** of the release. It starts exactly at the first strong technical word after the number (a resolution, `WEB-DL`, `WEBRip`, `BluRay`, a codec such as `x264`), never at a weaker word before it: in `Costa Rica CR 720p` or `Prueba.ADN.1080p` the `CR` and the `ADN` are not in the tail. It goes on while every word is technical (`.1080p.CR.WEB-DL.AAC2`) and ends at the first one that is not, so in `1080p.Prueba.ADN` the `ADN` does not count either. `BD` on its own is an everyday abbreviation: it counts in brackets (`[BD]`) and in the tail of a dotted name (`.1080p.BD.x264`), never loose in a name with spaces (`Boda Ana - 01 BD 1080p`, `- 01 1080p BD`).

    Loose words after the number (an episode title, a description) never count, and neither do the words of the series name, because the series name is what gets sent.

    So `[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv`, `[Erai-raws] Show - 12 [1080p][Multiple Subtitle].mkv`, `[Erai-raws] jukishi - 15 [1080p CR WEB-DL AVC AAC][MultiSub][799A2A46].mkv`, `Show - 05 (1080p) [ABCD1234].mkv`, `Show S01E05 (HIDIVE) [1080p].mkv`, `Show.S01E05.1080p.CR.WEB-DL.mkv`, `Show.S01E05.1080p.UNCENSORED.ADN.WEB-DL.mkv` and `Frieren.S01E05.Le.Voyage.1080p.ADN.WEB-DL.mkv` are looked up, while `The Office - 05.mkv`, `Holiday - 01.mp4`, `Boda Ana - 01 (1080p).mp4`, `Familia Lopez - 03 [ABCD1234].mkv`, `Paciente Garcia - 02 - Prueba ADN.mkv`, `Boda Ana - 02 - Costa Rica CR.mp4`, `Analisis.paciente.Garcia.S01E02.Prueba.ADN.mkv`, `Analisis ADN paciente Garcia - 02.mkv`, `Boda Ana - 02 - Costa Rica CR 720p.mp4`, `Paciente.Garcia.S01E02.ADN.1080p.mkv`, `Paciente Garcia - 02 (prueba ADN Garcia).mkv`, `Consulta Garcia - 02 (ADN).mkv`, `[2024] Trip S01E02.mkv` or `Show.S01E05.1080p.WEB-DL.mkv` never are. Nor are `Show S01E05 (HIDIVE).mkv` or `Show.S01E05.CR.WEB-DL.mkv`: a service alone in brackets, or a service before the tail, looks exactly like a personal video that mentions it; such releases are only looked up with a `[Group]` in front or another sign. Streams from Seanime and similar servers count too, through the file name they carry. Films, specials, OVAs and half episodes (`12.5`) are never looked up.

**What is sent, and to whom.** Four public services, without an account or a key, through `curl` in the background (playback never waits):

1. To **AniList** (`graphql.anilist.co`): the series name as hikari reads it from the file name (`Sousou no Frieren`), to find its MyAnimeList id. Only if AniList cannot be reached or answers with an error, the same name goes to **Kitsu** (`kitsu.app`) instead, and only if Kitsu fails too, to **Jikan** (`api.jikan.moe`, an unofficial MyAnimeList API).
2. To **AniSkip** (`api.aniskip.com`): that MyAnimeList id, the episode number and the episode's length in whole seconds (`52991`, episode `5`, `1470`), so that it answers with the times submitted for a release of that length.

Nothing else: not the file name, the folder, the release group or the file itself. Like any visit to a website, each request also tells those servers your IP address and that it comes from curl. The answers are kept in `hikari-aniskip.json` in your config folder (the MyAnimeList id for 30 days, the times for 30 days; a "not found" for 7 days and 3 days), so watching an episode again, or the next one of the same series, sends nothing or only the AniSkip request (the times are kept per length: a release of another length asks again).

**When it shows nothing.** hikari would rather show no button than a wrong one. The series must match an AniList (or Kitsu, or Jikan) title exactly (romaji, English, Japanese or a synonym; for a later season, as `Show 2nd Season`, `Show Season 2` or `Show 2`), and only one series may match. AniSkip answers with the times submitted for the length closest to yours, and hikari only uses them when that length is within 10 seconds of yours, so a release with another cut gets nothing. Without `curl`, without network or when a service fails, nothing is shown (the next time it asks again). Times that arrive after the opening is over change nothing; the ending button still shows when its time comes. Openings and endings follow the same `openings` and `endings` settings as chapters.

To turn it off, set `aniskip=no` in `script-opts/hikari-skip.conf`; updating hikari replaces that file, so to keep it off for good add this line to your own `mpv.conf` instead (outside the hikari block):

```
script-opts-append=hikari-skip-aniskip=no
```

The series name and episode come from [hikari-title.lua](titles.md), whatever its own settings say; without that script, AniSkip is never asked.

## Look and settings

The button follows the active palette (background and border from uosc's `background` and `foreground`, filled with `foreground` on hover). Position, size and opacity are set in `script-opts/hikari-skip.conf`. To use another key, bind `script-binding hikari_skip/skip` in `input.conf`.
