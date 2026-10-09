# Anime4K upscaling

[Anime4K](https://github.com/bloc97/Anime4K) (by bloc97, MIT) is a set of mpv shaders that clean up and upscale anime on the graphics card. hikari does not include it: the installer downloads release v4.0.1 (`Anime4K_v4.0.zip`) from GitHub, checks its SHA256 and copies its `Anime4K_*.glsl` files, and nothing else, into `shaders/`. Once installed it starts in **Automático** (see below); pick another mode, or *Apagado*, at any time.

The **Escalado** button in the controls bar (sparkles icon, `auto_awesome`) opens a menu with two groups; picking an option applies it straight away and the menu stays open:

- **Modo**: *Apagado*, *Automático* and Anime4K's six official modes. *Automático* picks the mode from the height of each video, with the chosen quality: C up to 576 lines (480p, 576p), B up to 810 (720p), A+A up to 1100 (1080p), and no shaders for taller videos (1440p, 4K), which do not need upscaling. It works it out again for every file (and whenever the height changes), so a playlist that mixes resolutions gets the right mode for each one. The guide of Anime4K says the right mode is the one that looks best; roughly:

  | Mode | For |
  | --- | --- |
  | A | Most 1080p anime, blurry or with compression artifacts. |
  | B | Most 720p anime (and 1080p scaled down to 720p): less blur, more aliasing and ringing. |
  | C | SD (480p) without much damage, wallpapers and clean images. |
  | A+A, B+B, C+A | The same, sharper and slower. Only for scaling by 2× or more (720p and below on a 1080p screen). |

- **Calidad**: *Alta* (Anime4K's *HQ* shader lists, for capable graphics cards) or *Rápida* (its *Fast* lists).

`Ctrl+1` to `Ctrl+6` pick the modes in the same order and `Ctrl+0` turns Anime4K off, as in Anime4K's own instructions; `Ctrl+7` is *Automático*. Each shows a short message such as *Anime4K: Modo A (Rápido)* or *Anime4K: Automático (B, 720p)*. The shader lists are exactly those of Anime4K's official mpv templates. If the shaders are missing, the menu says so (*Anime4K no está instalado: ejecuta el instalador*) and the button stays hidden.

The choice is saved to `~~/hikari-upscale.conf`, which `mpv.conf` includes, so a fixed mode is active from the first frame on the next start. With *Apagado* that file sets no `glsl-shaders` at all, so your own `glsl-shaders` line keeps working; with a mode on, the mode's Anime4K shaders replace the whole list (like Anime4K's own keys do), and *Apagado* puts your list back. *Automático* cannot know the height before a file is open, so its file only says `mode=auto`: the script sets the shaders when each file loads, and with no mode for a video (too tall, or no video) your own list applies, as with *Apagado*. The shader list is set as a list, never as one joined string, so it does not depend on the path separator (`;` on Windows, `:` elsewhere). The button needs mpv 0.36 or newer (it is shown through a `user-data` property); with an older mpv use the keys.

What the installer does:

- **AnimeJaNai**: nothing. It already upscales with AI and uses `Ctrl+1` to `Ctrl+9` for it.
- **No Anime4K yet**: it explains what it is and asks *Install Anime4K?* (yes by default; with `-Yes`, yes). Installed, it starts in *Automático*: `hikari-upscale.conf` is written with `mode=auto` and the quality for your card, even if an earlier one said *Apagado*. If you say no, it asks again on the next update, then with no as the default. If the download or its check fails, the installer says so and installs the rest of hikari; Anime4K is offered again next time, yes by default.
- **Already installed by hikari**: an update leaves it alone when it is the same version and every shader hikari needs is there; if one is missing or the version changed, it is downloaded and installed again. The mode you chose is kept.
- **Anime4K installed by hand** (`Anime4K_*.glsl` in `shaders/` that hikari did not put there): it offers to take it over (no by default; with `-Yes`, no). If you accept, hikari first downloads and checks its copy (if that fails, nothing of yours is touched), then your files are moved to `shaders-desactivados/` (nothing is deleted), hikari installs its own copy (in *Automático*), and `Ctrl+0` to `Ctrl+6` lines of yours that change `glsl-shaders` (`CTRL+1` and `Ctrl+1` alike) can be turned off by putting `# hikari: ` in front of them, so the hikari keys can use those keys. A `glsl-shaders=` line with Anime4K shaders in your `mpv.conf` (Anime4K's templates have one; so do `[profile]`s that pick a mode by height, which *Automático* replaces) is turned off the same way (yes by default, and with `-Yes`): otherwise that mode would be on at every start, even with *Apagado*. The same happens if hikari installs Anime4K where such a line was already waiting for the shaders. Uninstalling moves your files back and turns those lines on again. If you do not accept, nothing is touched: your keys keep working, but the *Escalado* menu does not know what they turned on.
- `-Anime4K yes` installs it (and takes over one installed by hand) without asking; `-Anime4K no` leaves it out (an Anime4K that hikari installed earlier is left as it is).

The quality is chosen from your graphics card the first time `hikari-upscale.conf` is written, and the installer says so in one line (*Gráfica: NVIDIA GeForce RTX 3060 → calidad Alta*). When there are several cards, the most capable one decides. The line follows [Anime4K's own guide](https://github.com/bloc97/Anime4K/blob/master/md/GLSL_Instructions_Windows_MPV.md), which puts GTX 1080, RTX 2070, RTX 3060, RX 590, Vega 56, 5700 XT and 6600 XT among the higher-end cards and GTX 980, GTX 1060 and RX 570 among the lower-end ones; a card that is not clearly as fast as an RTX 2070 gets *Rápida*:

| | *Alta* | *Rápida* |
| --- | --- | --- |
| NVIDIA | GTX 1080 / 1080 Ti; RTX 2070 and up; RTX 3060, 4060, 5060 and up; TITAN Xp / V / RTX; professional RTX 4000 and up | GTX 1070, GTX 16xx, GTX 1060 and older; RTX 2060 (Super too); RTX 3050, 4050, 5050; RTX A2000 and smaller; MX, GT |
| AMD | RX 590; RX 5600, 5700; RX 6600 and up; RX 7600 and up; RX 9060 and up; RX Vega 56/64, Radeon VII | RX 580, 570 and older; RX 5500; RX 6400, 6500; RX 7400; integrated graphics (*Radeon Graphics*, *780M*...) |
| Intel | Arc A580, A750, A770, B570, B580 (and A770M) | *Arc Graphics* with no model number and Arc 140V (integrated in Core Ultra), Arc A380, laptop Arc below A770M, UHD, Iris, HD |
| Apple | M Pro, Max and Ultra | M base chips, Intel Macs |
| Linux (`hikari.sh`, from `lspci`) | a dedicated NVIDIA or AMD card | Intel, AMD integrated, no `lspci` |
| Other | | anything unknown |

It never changes the quality you picked afterwards: change it in the menu at any time. If the video stutters, use *Rápida* or a mode without `+`.

The modes, qualities and shader lists are defined in `portable_config/scripts/hikari-upscale.lua`. To open the menu from the keyboard, bind `script-binding hikari_upscale/open-menu` in `input.conf`; to pick a mode, `script-message-to hikari_upscale set-mode <off|auto|a|b|c|aa|bb|ca>` (and `set-quality <hq|fast>`).
