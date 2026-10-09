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
| macOS (Apple Silicon) | mpv from Homebrew |
| Linux: Debian 13, arm64 | mpv 0.40.0 |

uosc 5.13 itself needs mpv 0.33 or newer. hikari is only tested with the recent versions above: older ones may work, but nobody has checked. The Linux installer is the newest of the three and has seen the least real-world use; reports are welcome.
