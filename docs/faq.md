---
title: "hikari mpv theme: frequently asked questions"
description: "Answers about hikari, a theme for mpv built on uosc: supported players, backups, languages, Anime4K and AnimeJaNai, thumbnails on macOS, privacy and uninstalling."
---

# Frequently asked questions

## Does hikari replace uosc?

No. hikari installs the official [uosc](https://github.com/tomasklaen/uosc) (5.13.0) and configures it: colours, buttons and timeline through `script-opts/uosc.conf`, plus a few Lua scripts of its own (`hikari-*.lua`) that talk to uosc through its menu API. uosc keeps being uosc.

## Which players does it work with?

- **Windows**: [mpv](https://mpv.io/installation/), [mpv.net](https://github.com/mpvnet-player/mpv.net) and bundles built on mpv.net such as [AnimeJaNai](https://github.com/the-database/mpv-upscale-2x_animejanai).
- **macOS**: mpv from Homebrew or mpv.app, which read `~/.config/mpv`. IINA keeps its own settings and is not touched.
- **Linux**: mpv from your distribution, Flatpak or Snap. The Linux installer is new and still being tested.

See [Install on Windows](install/windows.md) and [Install on macOS and Linux](install/macos-linux.md).

## Will it break my mpv configuration?

It is built not to. Before touching anything it backs up the files it may change next to your config folder (`<folder>-respaldo-hikari-<date>`), it only adds a marked block to `mpv.conf` and `input.conf` and leaves the rest of both files as they are, and *Uninstall* puts back what was there before. Other interfaces it has to set aside (ModernX, ModernZ...) are moved, never deleted.

## What language are the labels in?

Yours, if it is one of the 13 languages of uosc: English, Spanish, German, French, Italian, Polish, Portuguese, Romanian, Russian, Turkish, Ukrainian, Simplified Chinese or Chinese from Hong Kong. The installer picks your system's language, and `Alt+l` changes it in mpv (restart mpv to translate uosc's own menus too). Any other language gets English. The documentation is in English, and the installer speaks English or Spanish. See [Languages](features/language.md).

## Does it tidy the titles of my local files too?

Yes. Since 0.5.0, a local video file whose name looks like a release (`[SubsPlease] Show - 05 (1080p) [ABCD1234].mkv`, `Show.S01E05.1080p.WEB-DL.mkv`) shows as `Show · E05` or `Show · S1 E05`, as streamed links do. Names that do not look like a release keep mpv's title. See [Titles](features/titles.md).

## I use AnimeJaNai: do I need Anime4K?

No. AnimeJaNai already upscales with AI and uses `Ctrl+1` to `Ctrl+9` for it, so the installer does not offer Anime4K there. Everything else in hikari works the same. See [Anime4K upscaling](features/anime4k.md).

## The thumbnails come out black on macOS

mpv started from Finder or from another app (Seanime...) does not have Homebrew's folder in its `PATH`, so thumbfast cannot start a second mpv. The installer writes the full path into `script-opts/thumbfast.conf` (`mpv_path=/opt/homebrew/bin/mpv`); if you installed hikari by hand, add that line yourself. See [Thumbnails](features/thumbnails.md).

## The title of an episode looks short or odd

hikari tidies release names, and it can only show what the file name carries. Some groups use their own short names (Erai-raws calls one series just `jukishi`), and the full title, which Seanime knows, is not passed to mpv. If a release name comes out wrong, [open an issue](https://github.com/SCEPTICG/hikari-mpv/issues) with the exact file name. See [Titles](features/titles.md).

## Does hikari phone home?

Only the update check, and only to GitHub: at most once a day it asks `https://github.com/SCEPTICG/hikari-mpv/releases/latest` where it points. Nothing about you or your files is sent, and it never updates anything by itself. Turn it off with `enabled=no` in `script-opts/hikari-update.conf`. See [Update check](features/update-check.md).

## On Windows, `irm` fails with an SSL/TLS error

Older Windows 10 builds do not use TLS 1.2 by default in Windows PowerShell 5.1. Turn it on for that window and run the line again:

```
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1 | iex
```

## How do I uninstall it?

Run the install line again and choose *Uninstall* (on macOS and Linux you can add `bash -s -- --uninstall`). It backs up again, removes hikari and its blocks, and asks whether to remove uosc and thumbfast too and whether to put back what it set aside.

## Where do I report a problem?

Open an issue on [GitHub](https://github.com/SCEPTICG/hikari-mpv/issues), with your system, your player and, if you can, what the installer printed.
