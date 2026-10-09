# Update check

`hikari-update.lua` tells you when a new version of hikari is out. It only tells you: it never downloads or installs anything by itself.

When there is one, opening a file shows *hikari 0.4.1 disponible · Alt+u* for a few seconds, and an *Actualizar hikari* button (download icon) appears in the controls bar, before *fullscreen*. The button, or `Alt+u`, opens a menu with:

- **Ver novedades de la 0.4.1**: opens that version's release page on GitHub in your browser.
- **Copiar comando de actualización**: copies the update command, the same one as in [Install](../install/windows.md): `irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1 | iex` on Windows (paste it into PowerShell), `curl -fsSL https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.sh | bash` on macOS and Linux (paste it into a terminal). If the clipboard cannot be reached, the command is shown on screen to type it by hand.
- **No avisar de esta versión**: no more notice or button for that version. The next one is announced as usual, and `Alt+u` still opens the menu.

How it checks: on the first file you open after starting mpv (never at start-up, so nothing waits for it), and at most once a day, hikari runs `curl` in the background to ask `https://github.com/SCEPTICG/hikari-mpv/releases/latest` where it points, and reads the version from the answer. That is the only request: no GitHub API, no account, nothing about you or your files is sent beyond what any visit to that page sends (your IP address and curl's name). Without `curl` or without network nothing is shown, and it tries again the next day. The installed version comes from `hikari-installed.txt`, which the installer writes; a copy installed by hand or from the repository (`dev`) is never checked. The time of the last check, the latest version found and the one you dismissed are kept in `hikari-update.txt` in the config folder. If that file cannot be written (a read-only config folder), it still asks only once per mpv session, but every new session asks again. On Windows it runs `curl.exe` (and, from the menu, `cmd.exe`, `clip.exe` and PowerShell) only from the `System32` folder of Windows, never from mpv's folder or the video's.

It is on by default. To turn it off, set `enabled=no` in `script-opts/hikari-update.conf`; updating hikari replaces that file, so to keep it off for good add this line to your own `mpv.conf` instead (outside the hikari block):

```
script-opts-append=hikari-update-enabled=no
```

`interval_hours` in the same file sets the hours between checks (24 by default, at least 1). To use another key, bind `script-binding hikari_update/open-menu` in `input.conf`.
