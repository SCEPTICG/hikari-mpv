---
title: "Readable anime titles in mpv, for local files and streams"
description: "hikari turns anime release names into readable titles in mpv, such as Sousou no Frieren · E05, for local files and for streamed links from Seanime and similar apps, keeping access tokens out of the title bar."
---

# Titles

mpv shows a file's own title, or its file name. For anime releases neither reads well: a name like `[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv`, a title that is just the release group, or, for streaming apps such as Seanime, a whole URL with its access token. `hikari-title.lua` shows a tidy title instead, in uosc's top bar and the window title:

| File name | Title |
| --- | --- |
| `[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv` | `Sousou no Frieren · E05` |
| `[Erai-raws] Mushoku Tensei II - Isekai Ittara Honki Dasu 2nd Season - 05 [1080p][MultiSub].mkv` | `Mushoku Tensei II - Isekai Ittara Honki Dasu · S2 E05` |
| `[Judas] Vinland Saga (Season 2) - 05 [1080p][HEVC x265 10bit].mkv` | `Vinland Saga · S2 E05` |
| `Frieren.Beyond.Journeys.End.S01E05.1080p.CR.WEB-DL.AAC2.0.H.264-VARYG.mkv` | `Frieren Beyond Journeys End · S1 E05` |
| `Frieren (2023) - S01E05 - The Hero's Party.mkv` | `Frieren (2023) · S1 E05 · The Hero's Party` |
| `Show - 12.5.mkv`, `Show - 05v2.mkv` | `Show · E12.5`, `Show · E05` |
| `[Group] Show - OVA [1080p].mkv`, `Show - SP01.mkv` | `Show · OVA`, `Show · Special E01` |
| `Show.S00E03.mkv` | `Show · Special E03` (season 0 holds the specials) |
| `Show.S01E01-E02.mkv` | `Show · S1 E01-E02` |
| `Movie.Name.2023.1080p.BluRay.x264.mkv` | `Movie Name (2023)` |

The labels follow hikari's [language](language.md): `S1 E05` in English, `T1 E05` in Spanish and Portuguese (*temporada*), `S1 B05` in Turkish (*bölüm*), `第1季 第05集` in Chinese, and *Special* translated. The title of the file playing changes with the language.

## What gets a title

- **Local files** with a video extension (`.mkv`, `.mp4`, `.webm`...), opened by path or as `file://`: when the file name looks like a release (an episode marker, a technical tail such as `1080p.WEB-DL`, or `[group]` / `(1080p)` brackets to drop), its tidy title replaces mpv's, even if the file has a title of its own (in these releases it is often just the group). Any other name, such as `Holiday video.mkv`, keeps mpv's title.
- **Streamed links with a `filename` parameter**, such as the ones Seanime hands out (`https://host/<id>?token=...&filename=Show.S01E01.mkv`): the decoded `filename`, always. The title is set as the file starts, so the token is kept out of the top bar except, at most, for an instant while the stream opens.
- **Links whose last part is a video file name** that looks like a release (`https://host/files/[SubsPlease] Show - 05 (1080p).mkv`), as for local files.
- **Other http(s) links with a query** (`https://host/videos/abc/stream?api_key=...`): the last path segment without the query, so the key does not show. It gives way to the file's own title once the file has loaded.
- Anything else keeps mpv's own title: `ytdl://`, `rtsp://`, discs, other protocols. Sites played through yt-dlp, such as YouTube, get their real title from yt-dlp, which replaces hikari's as the video opens. A `force-media-title` you set yourself and playlist entries with their own title (M3U `#EXTINF`) are left alone too. The title only lasts for that file.

## How names are read

Recognised episode markers: `S01E01`, `s1e1`, `S01E01v2`, `S01E01-E02`, `E01`, `EP01`, `Episode 01`, anime-style ` - 01`, ` - 01v2` and ` - 12.5`, specials `SP01` and `Special 01`, and `OVA`, `OAD` and `ONA` (alone or with a number). A season written before an anime-style number is read too: `S2`, `Season 2`, `2nd Season`, `Second Season`, `(Season 2)`. Release groups, hashes and technical tags go. After the marker, an episode title is kept when it is clearly one: after ` - ` in names with spaces (`Show - S01E05 - Title [1080p]`, the Plex, Jellyfin and Sonarr style), or up to the technical tail in dotted names (`Show.S01E05.Title.1080p.WEB`).

A name with no marker is treated as a film and only cut at its first technical tag (resolution, source, codec, audio...), keeping its year as `(2023)`; if nothing sensible is left, the name is shown as it comes. A name written all in lower case, as some groups do (Erai-raws calls one series just `jukishi`), gets a capital first letter (`Jukishi · E15`); a name with any capital letter is left as it was written. Only the file name is available: the full series title (which Seanime knows) is not passed to mpv.

Scope: this covers uosc's top bar and the window title. For streams, the full URL is still visible in uosc's playlist menu, in mpv's stats overlay, and in mpv's logs and `watch_later` files.

## Options

In `script-opts/hikari-title.conf`:

- `pretty=no`: no tidying. Local files keep mpv's own title, and streamed links get their `filename` as it comes, without its video extension.
- `enabled=no`: the whole script off.
