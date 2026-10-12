---
title: "Continue watching in mpv with hikari"
description: "hikari remembers where you left each video file and asks whether to continue from there. Files only, never streams; the list stays on your computer."
---

# Continue watching

`hikari-resume.lua` remembers where you left each file and picks up from there next time.

When you open a file you left half-watched, mpv pauses and a menu asks:

- **Continue from 12:34** (selected: `Enter` picks it) jumps to where you were.
- **Start from the beginning** plays it from the start.

Closing the menu without choosing (`Esc`, a click outside it) starts from the beginning. If mpv was playing, it plays on once you answer; if it was paused, it stays paused.

A file counts as watched, and leaves the list, once you reach 95 % of it or the start of its ending (a chapter called `ED`, `Ending`, `Credits`, `エンディング`..., the same ones the [skip button](skip.md) knows). Next time it starts from the beginning without asking. Under 30 seconds nothing is remembered, so peeking into an episode does not lose your place in it. A file whose length mpv cannot tell is not remembered either.

## Files only, never streams

It works with files on your disk or on a network share (`C:\Anime\...`, `\\NAS\anime\...`, `/Volumes/data/...`, `/mnt/...`). Anything mpv opens from a link (`https://`, `ytdl://` and the like) is left alone: nothing is saved and nothing is asked. Seanime and similar apps already keep your position for what they stream, and two players jumping to a position each would fight; their links also carry an access token, which hikari never writes down.

If you use mpv's own `save-position-on-quit` (or start a file with `--start`), mpv has already jumped when the file opens, and hikari does not ask again.

## The list

`Alt+r`, or the button with the clock icon in the controls bar (it only shows when the list has something), opens *Continue watching*: the files you left half-watched, newest first, each with where you stopped, its length and when you watched it (*today*, *yesterday* or the date). Picking one opens it, and the question above comes up. A file that cannot be found right now (a network share that is not mounted, a file you deleted) shows greyed out as *Not available* and stays in the list until it comes back. *Clear history*, at the end, empties the list.

The title of each row is the file name, without folder or extension.

## What is saved, and where

The list is `hikari-resume.json`, in mpv's config folder. For each file: its full path, its name, where you stopped, its length and when. It keeps the 30 most recent files (the oldest go first), and only those started and not finished.

It never leaves your computer: this script makes no network connection at all, and each computer has its own list. The installer does not copy it into its backups, and uninstalling hikari deletes it. Two mpv windows open at once each keep their own files in the same list.

## Options

`script-opts/hikari-resume.conf`; updating hikari keeps your copy of this file.

| Option | Default | What it does |
| --- | --- | --- |
| `enabled` | `yes` | `no` turns it all off: nothing saved, nothing asked, no button. |
| `ask` | `yes` | `no` continues from where you were without asking. |
| `history_size` | `30` | How many files the list keeps, from 1 to 100. |

To use another key, bind `script-binding hikari_resume/open-menu` in `input.conf`.
