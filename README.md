# sosc

A cross-platform mpv theme (Windows, Linux, macOS) built on top of [uosc](https://github.com/tomasklaen/uosc), with its own palette, thumbnails via [thumbfast](https://github.com/po5/thumbfast), and a few extras such as skipping anime openings and endings.

Work in progress.

## Palettes

sosc ships a palette picker for uosc. Open it with the palette button in the controls bar or `Alt+p`, then pick a palette; it is applied straight away.

- Dark: uosc (original), Catppuccin Mocha, Tokyo Night, Dracula, Nord, Gruvbox, Rosé Pine, Kanagawa, One Dark, Everforest.
- Light: Catppuccin Latte, Gruvbox light, Solarized light.
- Custom: SCEPTIC, defined in `portable_config/scripts/sosc-palettes.lua`.

A palette can also set transparency through an optional `opacity` table (uosc's `opacity` keys, values 0 to 1); palettes without it use uosc's default opacity.

sosc owns uosc's `color` and `opacity` options: values set in `script-opts/uosc.conf` are overridden by the active palette. Customise them by editing a palette instead.

The choice is saved to `~~/sosc-palette.conf` (the mpv config folder, `portable_config/` in a portable install), which `mpv.conf` includes on start-up. To bind another key, use `script-binding sosc_palettes/open-menu` in `input.conf`.

Tests: `lua tests/test_palettes.lua` from the repository root.

## License

MIT. uosc (LGPL-2.1) and thumbfast (MPL-2.0) are not included in this repository; the installer downloads them from their official releases.
