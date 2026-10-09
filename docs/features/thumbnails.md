---
title: "Timeline thumbnails in mpv with uosc and thumbfast"
description: "hikari sets up thumbfast so mpv shows thumbnail previews on the uosc timeline, network streams included."
---

# Thumbnails

Timeline thumbnails come from [thumbfast](https://github.com/po5/thumbfast), which uosc picks up automatically. thumbfast is not bundled (MPL-2.0); install `thumbfast.lua` into `scripts/` (the installer will do it). hikari ships `script-opts/thumbfast.conf` with thumbnails enabled on network streams (`network=yes`), GPU decoding (`hwdec=yes`) and the thumbnailer started only when the timeline is first hovered (`spawn_first=no`). On streams thumbfast opens its own connection, so it uses some extra bandwidth and the first thumbnail can take a moment. mpv.net 7+ is meant to work without extra setup, but some builds (seen with the AnimeJaNai bundle, mpv.net 7.1.2) do not report their path to thumbfast in time and it shows "install standalone mpv". In that case add the full path to `script-opts/thumbfast.conf`, e.g. `mpv_path=C:\Users\<you>\AppData\Local\Programs\mpv-AnimeJaNai\mpvnet.exe` (the installer will write it for you). On macOS the installer always writes it (`mpv_path=/opt/homebrew/bin/mpv`, say): mpv started from Finder or another app does not find `mpv` in its `PATH`, and the thumbnails come out black. On streams each new thumbnail takes a moment, since thumbfast has to fetch that part of the video over the network.
