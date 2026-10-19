---
title: "hikari compatibility: tested mpv, uosc and system versions"
description: "Which versions of mpv, mpv.net, uosc, thumbfast and Anime4K hikari is tested with on Windows, macOS and Linux."
---

# Compatibility

## Components hikari installs

The installer always downloads these exact versions and checks each one against its SHA256, so every installation of a given hikari release gets the same files.

| Component | Version |
| --- | --- |
| [uosc](https://github.com/tomasklaen/uosc) | 5.13.0 |
| [thumbfast](https://github.com/po5/thumbfast) | commit `0f711de` |
| [Anime4K](https://github.com/bloc97/Anime4K) (optional) | 4.0.1 |

hikari's scripts talk to uosc through its menu messages, `user-data` properties and options. A new uosc version is only adopted after hikari has been tested with it.

## Tested systems

Each release is tested by hand on these setups, besides the automated tests:

| System | Player |
| --- | --- |
| Windows 11 | mpv.net 7.1.2 (mpv 0.41.0-dev), AnimeJaNai bundle |
| macOS (Apple Silicon) | mpv 0.41.0 from Homebrew |
| Linux: Debian 13, arm64 | mpv 0.40.0 |

uosc 5.13 itself needs mpv 0.33 or newer. hikari is only tested with the recent versions above: older ones may work, but nobody has checked. The Linux installer is the newest of the three and has seen the least real-world use; reports are welcome.

## hikari without uosc

The installer always installs uosc, and hikari is made to sit on top of it. If uosc is not there anyway (you moved `scripts/uosc` away, or another OSC took its place), hikari keeps working:

- Its menus open in mpv's own selector instead of uosc's menus: `Alt+p` (palettes), `Alt+t` (subtitles), `Alt+r` (continue watching), `Alt+u` (update) and `Alt+l` (language). Type to filter, use the arrow keys and `Enter` to pick, `Esc` to close. The speed and Anime4K menus only have a button in uosc's bar; to reach them without uosc, bind `script-binding hikari_speed/open-menu` and `script-binding hikari_upscale/open-menu` to keys of your own in `input.conf` (the `Ctrl+1`...`Ctrl+0` Anime4K keys work as always).
- The [continue watching](features/resume.md) question shows in that selector too; `Esc` starts from the beginning.
- Tidy titles, the skip button, AniSkip, subtitle styles, track languages, Anime4K, speeds and the update notice work the same.

The selector needs **mpv 0.39 or newer**. On an older mpv without uosc, a menu key only shows a message saying the menu needs uosc or mpv 0.39, and a file you left half-watched starts from the beginning.

What only uosc gives you: the buttons of the controls bar (they are uosc's), uosc's own menus, and the colours of the [palettes](features/palettes.md), which colour uosc. Without uosc the palette menu still opens and keeps your choice for when uosc is back; the skip button follows it.
