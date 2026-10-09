# Coming from sosc

hikari was called sosc until v0.3.0. Both installers recognise a folder with sosc in it (its `sosc-installed.txt`, or `sosc-*` files) and, after the usual backup, which includes the files of sosc, carry it over to hikari:

- Your palette, subtitle and upscaling choices move to `hikari-palette.conf`, `hikari-subs.conf` and `hikari-upscale.conf`.
- The sosc blocks in `mpv.conf` and `input.conf` become hikari blocks, and what sosc set aside or turned off (with `# sosc: ` in front) is taken over by hikari, so uninstalling hikari leaves the folder as it was before sosc.
- Lines of your own outside the blocks that use the names of sosc (`script-binding sosc_palettes/open-menu`, `script-message-to sosc_upscale set-mode a`, `include="~~/sosc-subs.conf"`, `script-opts-append=sosc-update-enabled=no`...) are changed to hikari's, and the installer shows each one.
- The sosc scripts, options, record and update-check state go. Old `<folder>-respaldo-sosc-<date>` backups are left alone (the installer says how many there are): delete them yourself when you no longer need them.

*Uninstall* works on a folder with sosc too. sosc itself is never put back. The update check of sosc 0.3.0 does not announce hikari, so run the install line once by hand.
