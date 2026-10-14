---
title: "Continue watching in mpv with hikari"
description: "hikari remembers where you left each video file and asks whether to continue from there; for a series, it keeps your place and finds the next episode in the folder. Files only, never streams; hikari never sends the list anywhere."
---

# Continue watching

`hikari-resume.lua` remembers where you left each file and picks up from there next time.

When you open a file you left half-watched, mpv pauses and a menu asks:

- **Continue from 12:34** (selected: `Enter` picks it) jumps to where you were.
- **Start from the beginning** plays it from the start.

Closing the menu without choosing (`Esc`, a click outside it) starts from the beginning. If mpv was playing, it plays on once you answer; if it was paused, it stays paused.

A file counts as watched once you reach 95 % of it or the start of its ending (a chapter called `ED`, `Ending`, `Credits`, `エンディング`..., the same ones the [skip button](skip.md) knows): a single file leaves the list, and an episode of a series stays as watched (see [Series](#series)). Next time it starts from the beginning without asking. Under 30 seconds nothing is remembered, so peeking into an episode does not lose your place in it. A file whose length mpv cannot tell is not remembered either.

## Files only, never streams

It works with files on your disk or on a network share (`C:\Anime\...`, `\\NAS\anime\...`, `/Volumes/data/...`, `/mnt/...`). Anything mpv opens from a link (`https://`, `ytdl://` and the like) is left alone: nothing is saved and nothing is asked. Seanime and similar apps already keep your position for what they stream, and two players jumping to a position each would fight; their links also carry an access token, which hikari never writes down.

This goes by how mpv opens the file, not by the app that started it: if an app such as Seanime hands mpv a file on your disk by its path (not by a link), hikari treats it as any other file and may ask on top of whatever that app does. If that bothers you, turn it off with `enabled=no` (see [Options](#options)).

If you use mpv's own `save-position-on-quit` (or start a file with `--start`), mpv has already jumped when the file opens, and hikari does not ask again.

## Series

A file whose name has one episode number is an episode of a series: `[SubsPlease] Sousou no Frieren - 05 (1080p).mkv`, `Sousou no Frieren S01E05.mkv`, `Show.S01E05.1080p.WEB-DL.mkv`. hikari reads the name the same way as for the [titles](titles.md). For those, the list keeps one row per series and season instead of one per file: `Sousou no Frieren - 05` and `Sousou no Frieren S01E06` are the same series (capitals and punctuation do not matter), `Sousou no Frieren S02E01` is another one. Specials, OVAs, double episodes (`S01E01-E02`) and half episodes (`12.5`) are not counted as episodes: they are single files, as anything else.

The row of a series is always the last episode you played (`Sousou no Frieren · E05`, or `· S2 E05` from the second season on, in your [language](language.md)):

- **Half-watched**: where you stopped, its length and the date, as for a single file. Picking it opens that episode and asks whether to continue.
- **Watched, and the next one is in the folder**: the row shows the next episode and *Next*. Picking it opens that episode.
- **Watched, and there is no next one yet**: *Up to date*, greyed out. Every time you open the list hikari looks at the folder again, so as soon as you download the new episode the row turns into *Next* on its own.
- **The folder cannot be reached** (the NAS is off): *Not available*, as for files.

Playing another episode of the series (from 30 seconds on, as always) makes it the row of the series, even an older one you watch again.

**How the next episode is chosen.** Only in the same folder as the episode, among video files of the same series and season: the one with the smallest episode number above it (after 05 comes 06; if 06 is missing, 07). If there are several files with that number (two releases, two resolutions), the one from the same release group wins (`[SubsPlease]` in front, or `-GROUP` at the end of the name); otherwise the first by name. A folder with more than 2000 files is not searched.

**Out of this:** going from the last episode of a season to the first of the next one, a series spread over several folders, and keeping the list in step between computers.

### Playing the next episode on its own

When an episode is the last thing in mpv's playlist (you opened just that file), hikari adds the next episode of the folder behind it, so mpv moves on to it when the episode ends, and uosc's *next* button works. If something is already queued after it (mpv's `autoload`, a folder you opened, your own playlist), hikari leaves the playlist alone, and it never adds a file that is already in it. If the next episode was half-watched, the usual question comes up.

Some players fill the playlist with the whole folder by themselves (mpv's `autocreate-playlist`, which mpv.net and AnimeJaNai turn on). mpv would also put in the images of the folder, such as the `-thumb.jpg` that Jellyfin or Sonarr leave next to each episode, and they would play between episodes. hikari's block in `mpv.conf` sets `directory-filter-types=video,audio` so only videos and audio go in; if your `mpv.conf` already sets `directory-filter-types`, the installer leaves yours.

To turn it off, set `autoplay_next=no`. Do so too if others you do not fully trust can put files in that folder (a shared NAS folder, say): playing on this way opens the next file of the folder without you picking it. Your copy of `hikari-resume.conf` is kept on update, so if it comes from hikari 0.8 the line is not there: the default, `yes`, applies.

The [skip button](skip.md#next-episode) reads *Next episode ›* at the end of an episode when the next one is queued. Moving on from an episode straight to that next one (with that button, uosc's *next* button, or at the end of the file) in the second half of the episode counts it as watched, even before 95 %, for instance when you skip an ending that AniSkip knows. A peek of under 30 seconds, a jump from earlier in the episode or a file that stops on an error (the NAS went away) do not count: the episode stays as it was.

## The list

`Alt+r`, or the button with the clock icon in the controls bar (it only shows when the list has something), opens *Continue watching*: the files you left half-watched and your [series](#series), newest first, each with where you stopped, its length and when you watched it (*today*, *yesterday* or the date). Picking one opens it, and the question above comes up. A file that cannot be found right now (a network share that is not mounted, a file you deleted) shows greyed out as *Not available* and stays in the list until it comes back. *Clear history*, at the end, empties the list. The file playing at that moment is not saved again while it plays, only when you close it or move on, so it comes back then if you stopped halfway.

The title of each row is the file name, without folder or extension; for a series, its name and the episode.

## What is saved, and where

The list is `hikari-resume.json`, in mpv's config folder. For each file: its full path, its name, where you stopped, its length and when; for a series, the same for its last episode, plus the series name, season, episode number and whether you finished it. It keeps the 30 most recent rows (the oldest go first): single files only while started and not finished, series also once watched. A list from hikari 0.8 is read and updated to the new format the next time something is saved. Going back to a hikari older than 0.9.0 after that empties the list: those versions cannot read the new format.

hikari never sends it anywhere: this script makes no network connection at all, and each computer has its own list. The one exception is up to you: if mpv's config folder is synchronised (your dotfiles in a repository, a `portable_config` in a cloud folder), the list travels with it, paths and all. The installer does not copy it into its backups, and uninstalling hikari deletes it. Two mpv windows open at once each keep their own files in the same list.

## Options

`script-opts/hikari-resume.conf`; updating hikari keeps your copy of this file.

| Option | Default | What it does |
| --- | --- | --- |
| `enabled` | `yes` | `no` turns it all off: nothing saved, nothing asked, no button. |
| `ask` | `yes` | `no` continues from where you were without asking. |
| `history_size` | `30` | How many rows the list keeps (a series is one), from 1 to 100. |
| `autoplay_next` | `yes` | `no`: hikari does not queue the next episode of a series. Missing from a copy of the file made by hikari 0.8: `yes`. |

To use another key, bind `script-binding hikari_resume/open-menu` in `input.conf`.
