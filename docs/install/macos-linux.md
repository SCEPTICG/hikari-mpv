---
title: "Install the hikari mpv theme on macOS and Linux"
description: "Install hikari, a uosc-based theme for mpv, on macOS and Linux with one curl line, no sudo. Backs up your mpv config first and can be uninstalled."
---

# Install on macOS and Linux

Open Terminal and run:

```
curl -fsSL https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.sh | bash
```

`curl` downloads the installer of the latest release and `bash` runs it. It is the same installer as on Windows, written for the `bash` 3.2 that comes with macOS: the same menus (`↑`/`↓`, `Enter`, `Esc`, `Space`, `Y`/`N`, `S`/`N` in Spanish), messages, backups and rotation, marked blocks, record, set-aside interfaces, *Interface* question (uosc or the experimental suji), Anime4K questions and uninstall (see [How the installer works](../install/windows.md#how-the-installer-works)). The questions are read from the terminal even though the script itself comes through the pipe. Messages are in Spanish when `LC_ALL`, `LC_MESSAGES` or `LANG` (the first one set) starts with `es`, in English otherwise. Inside mpv, hikari gets the system language if it is one of its [13 languages](../features/language.md): on macOS the first language of *System Settings* (mpv started from the Finder never sees the terminal's `LANG`), on Linux `LC_ALL`, `LC_MESSAGES` or `LANG`. What is different:

- **Config folder**. On macOS, `$MPV_HOME` if it is set, otherwise `~/.config/mpv`, the folder both Homebrew's mpv and mpv.app read. IINA keeps its own settings and is not touched (the installer says so if it finds IINA). On Linux, `$MPV_HOME` or `${XDG_CONFIG_HOME:-~/.config}/mpv` for a native mpv, plus `~/.var/app/io.mpv.Mpv/config/mpv` for the Flatpak and `~/snap/mpv/current/.config/mpv` for the Snap when those are installed; with more than one, you pick in a list. On both, an old `~/.mpv` is used when there is no `~/.config/mpv`, as mpv does (creating `~/.config/mpv` would hide it from mpv).
- **No mpv**. On macOS with Homebrew it offers to run `brew install mpv` (asking first, never without questions); without Homebrew it explains how to get mpv and stops. On Linux it names the package of the usual distributions (`sudo apt install mpv`, `sudo dnf install mpv`...) and stops: it never runs `sudo` itself.
- **thumbfast**. It writes the full path of mpv (`mpv_path=/opt/homebrew/bin/mpv`, say) into `script-opts/thumbfast.conf`: an mpv started from Finder or from another app (Seanime...) does not have `/opt/homebrew/bin` in its `PATH`, and the thumbnails would come out black. Not for the Flatpak or Snap, where `mpv` inside the sandbox is the right one.
- **Graphics card**. The Anime4K quality comes from the chip on macOS (`Apple M… Pro`, `Max` and `Ultra`: *High*; the base M chips and Intel Macs: *Fast*) and from `lspci` on Linux (a dedicated NVIDIA or AMD card: *High*; anything else, or no `lspci`: *Fast*).
- No AnimeJaNai or mpv.net there, and no administrator questions: run it as your own user. As root (`sudo`) it warns and asks, and without questions it refuses.

Run the same line to update. To see which version you have, without changing anything:

```
curl -fsSL https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.sh | bash -s -- --version
```

It prints one line per config folder, such as `mpv (/Users/you/.config/mpv): hikari 0.6.0 (older than this installer)`: `older`, `the same as` or `newer than` compares it with the installer you ran (the latest release, with the line above), `dev` is a copy installed from the repository and `0.10.0+dev.…` a test build made on 0.10.0 (`preview-…` in older test builds). Paste that line when you report a problem.

To uninstall:

```
curl -fsSL https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.sh | bash -s -- --uninstall
```

| Option | Meaning |
| --- | --- |
| `--install` / `--uninstall` | Skip the first menu. |
| `--target <config folder>` | Work on that folder instead of choosing from the list (repeat it for several). |
| `--yes` | No questions: take the default answer to everything (and install when no action is given). Needs `--target` when more than one folder is found. |
| `--no-menu` | Ask with numbers and typed answers instead of the keyboard menus. |
| `--anime4k yes` / `--anime4k no` | Answer the Anime4K questions instead of asking, as `-Anime4K` on Windows. |
| `--interface uosc` / `--interface suji` | Answer the *Interface* question instead of asking, as `-Interface` on Windows: uosc, or [suji](../compatibility.md#hikari-with-suji-experimental) (experimental). Without it and without questions, each folder keeps the one hikari installed there, uosc on a first install. |
| `--version` | Show the hikari version in each config folder found (and in each `--target`) and the installer's own, then leave. It only reads: nothing is installed, backed up or changed. Also in the menu, as *Show installed version*. |
| `--verbose` | Show every step on a line of its own (each download with its address, the backup folder, each file kept or moved...), without animations. Use it when you report a problem. |

Options go after `bash -s --`, as above. In a terminal the installer shows a short summary: a progress bar for each download, a spinner while it backs up and installs that turns into a tick when done, and one line at the end. Without a terminal (output to a file or a pipe, `TERM=dumb`, `NO_COLOR` or `CI` set) it shows the same summary as plain lines, with no animation and no escape sequence. Errors, warnings and questions always show in full; `--verbose` adds every detail. When uosc, thumbfast or Anime4K are already installed exactly as the release pins them (see [How the installer works](../install/windows.md#how-the-installer-works)), they are not downloaded again and the summary says *up to date*.

 With no terminal at all (a script, `ssh` without `-t`...) it runs as with `--yes`, and when an answer is really needed (several folders and no `--target`) it stops with a clear message. Exit codes: 0 done or cancelled, 1 a folder failed, 2 wrong usage or nothing to do. The whole script is inside one function that its last line calls, so a download cut short runs nothing.

To check it before running it, download `hikari.sh` and `SHA256SUMS` from the [release page](https://github.com/SCEPTICG/hikari-mpv/releases/latest), compare `shasum -a 256 hikari.sh` (`sha256sum hikari.sh` on Linux) with the line for `hikari.sh` in `SHA256SUMS`, and run `bash hikari.sh` (the options above work after it). The same caveat as for `hikari.ps1` applies (see [Checking the installer first](../install/windows.md#checking-the-installer-first)). From a copy of this repository, `bash install/hikari.sh` installs the hikari files of that copy.
