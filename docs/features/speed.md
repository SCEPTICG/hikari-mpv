---
title: "Playback speed menu for mpv"
description: "hikari replaces the uosc speed slider in mpv with a menu of fixed speeds from 0.5x to 2x."
---

# Speed menu

The speed button in the controls bar opens a menu with 0.5×, 0.75×, 1×, 1.25×, 1.5× and 2×; the current speed is marked. mpv's own `[`, `]` and `Backspace` keep working. To open the menu from the keyboard, add a line like this to `input.conf`:

```
Alt+v  script-binding hikari_speed/open-menu
```
