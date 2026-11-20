-- hikari-palettes: colour palette picker for uosc.
--
-- Opens a menu with the available palettes, applies the chosen one on the
-- fly through the `uosc-color` and `uosc-opacity` script options and saves it to
-- `~~/hikari-palette.conf`, which mpv.conf includes on the next start.
--
-- mpv turns this file name into the script name `hikari_palettes`, so:
--   input.conf:  Alt+p script-binding hikari_palettes/open-menu
--   options:     script-opts=hikari_palettes-palette=<id>
--
-- Without uosc (script-modules/hikari-menu.lua) the menu opens in mpv's own
-- selector, with a first line saying that palettes colour uosc. A choice is
-- still applied and saved, for when uosc is back: the two script options are
-- what the saved file sets on the next start anyway, and hikari-skip's button
-- takes its colours from `uosc-color`.
--
-- suji (hikari's own interface, in development) has one colour, its accent:
-- the `suji-accent` script option, which it follows at run time. A palette
-- sets it to its foreground (the colour of uosc's timeline and active items)
-- while suji is turned on (menu.suji()), and again each time
-- user-data/suji/enabled becomes true: suji sets it at the end of its
-- start-up, after this script has loaded, and when it is turned on again,
-- maybe after another palette was picked while it was off. The saved file
-- always carries it, like `uosc-color`, so suji starts with it. When the menu
-- goes to suji, its first line, muted, says that the palette changes suji's
-- accent; the selector's note (palettes_need_uosc) is for the selector only.
--
-- Side bars: a 4:3 episode on a wider screen leaves bars left and right. The
-- `bars` option (script-opts=hikari_palettes-bars=<value>, also in the menu)
-- can colour them: `black` leaves mpv alone, `palette` sets mpv's
-- `background-color` to the palette's curtain, `stripes` does that, draws
-- three VHS-style stripes in each bar and keeps text subtitles inside the
-- picture (`sub-use-margins`) so they do not end up under them. Only while
-- there are bars at both sides of a real video: otherwise `background-color`
-- and `sub-use-margins` go back to what they were just before this script
-- changed them (the user's own, or mpv's), and no stripes. The saved file
-- carries the choice with the palette.

local msg = require('mp.msg')
local options = require('mp.options')

-- hikari's modules in ~~/script-modules. Single-file scripts get no mpv folder
-- in package.path, so the folder is added for each require and taken out again
-- (see the header of hikari-i18n.lua). An optional one that cannot be loaded
-- is a warning and nil, not an error.
local function load_module(name, optional)
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then
		if optional then return nil end
		error('hikari: unusable script-modules folder: ' .. tostring(dir))
	end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, name)
	package.path = saved
	if not ok then
		local text = 'hikari: cannot load script-modules/' .. name .. '.lua (reinstall hikari): ' .. tostring(module)
		if optional then
			msg.warn(text)
			return nil
		end
		error(text)
	end
	return module
end

-- Texts in the chosen language: ~~/script-modules/hikari-i18n.lua.
local i18n = load_module('hikari-i18n')

-- Menus: ~~/script-modules/hikari-menu.lua (uosc's, or mpv's own selector
-- without uosc), loaded like the texts above.
local menu = load_module('hikari-menu')

local script_name = mp.get_script_name()

-- Colour keys understood by uosc's `color` option, in the order we write them.
local COLOR_KEYS = {
	'foreground', 'foreground_text', 'background', 'background_text', 'curtain',
	'success', 'error', 'match', 'heatmap', 'window_border',
}

-- Opacity keys understood by uosc's `opacity` option, in the order we write them:
-- config_defaults.opacity in uosc's main.lua plus pause_indicator, which uosc.conf
-- documents and PauseIndicator.lua reads. Anything else is rejected.
local OPACITY_KEYS = {
	'timeline', 'position', 'chapters', 'slider', 'slider_gauge', 'controls', 'speed',
	'menu', 'submenu', 'border', 'title', 'tooltip', 'thumbnail', 'curtain',
	'idle_indicator', 'audio_indicator', 'buffering_indicator', 'playlist_position',
	'heatmap', 'pause_indicator',
}
local OPACITY_KEY_SET = {}
for _, key in ipairs(OPACITY_KEYS) do OPACITY_KEY_SET[key] = true end

local DEFAULT_ID = 'uosc'
local MENU_TYPE = 'hikari-palettes'
local PERSIST_PATH = '~~/hikari-palette.conf'

-- Side bar styles, in menu order, with their menu texts (hikari-i18n).
local BARS = {
	{id = 'black', key = 'bars_black'},
	{id = 'palette', key = 'bars_palette'},
	{id = 'stripes', key = 'bars_stripes'},
}
local BARS_SET = {}
for _, bars in ipairs(BARS) do BARS_SET[bars.id] = true end
local DEFAULT_BARS = 'black'
-- Bars narrower than this share of the window width are not bars: a pixel or
-- two of rounding around a 16:9 video must not get coloured.
local BARS_MIN_SHARE = 0.02

-- group: 'dark', 'light', 'retro' or 'custom'. Colours are RRGGBB without '#'.
-- Optional `opacity`: table of OPACITY_KEYS -> number 0..1. Keys left out (or the
-- whole table) keep uosc's default opacity.
local PALETTES = {
	-- uosc defaults, copied from uosc.conf (`color=` comment) and main.lua.
	{
		id = 'uosc', name = 'uosc (original)', group = 'dark',
		foreground = 'ffffff', foreground_text = '000000',
		background = '000000', background_text = 'ffffff',
		curtain = '111111', success = 'a5e075', error = 'ff616e',
		match = '69c5ff', heatmap = '00adee', window_border = '000000',
	},
	-- https://catppuccin.com/palette (Mocha): base, text, mauve, crust, green, red, blue, peach.
	{
		id = 'catppuccin_mocha', name = 'Catppuccin Mocha', group = 'dark',
		foreground = 'cba6f7', foreground_text = '1e1e2e',
		background = '1e1e2e', background_text = 'cdd6f4',
		curtain = '11111b', success = 'a6e3a1', error = 'f38ba8',
		match = '89b4fa', heatmap = 'fab387', window_border = '11111b',
	},
	-- https://github.com/folke/tokyonight.nvim (night): bg, fg, blue, bg_dark, green, red, cyan, orange.
	{
		id = 'tokyo_night', name = 'Tokyo Night', group = 'dark',
		foreground = '7aa2f7', foreground_text = '1a1b26',
		background = '1a1b26', background_text = 'c0caf5',
		curtain = '16161e', success = '9ece6a', error = 'f7768e',
		match = '7dcfff', heatmap = 'ff9e64', window_border = '16161e',
	},
	-- https://draculatheme.com/contribute (spec): background, foreground, purple, cyan, green, red, pink.
	{
		id = 'dracula', name = 'Dracula', group = 'dark',
		foreground = 'bd93f9', foreground_text = '282a36',
		background = '282a36', background_text = 'f8f8f2',
		curtain = '21222c', success = '50fa7b', error = 'ff5555',
		match = '8be9fd', heatmap = 'ff79c6', window_border = '21222c',
	},
	-- https://www.nordtheme.com/docs/colors-and-palettes: nord0, nord6, nord8, nord9, nord11, nord14, nord15.
	{
		id = 'nord', name = 'Nord', group = 'dark',
		foreground = '88c0d0', foreground_text = '2e3440',
		background = '2e3440', background_text = 'eceff4',
		curtain = '2e3440', success = 'a3be8c', error = 'bf616a',
		match = '81a1c1', heatmap = 'b48ead', window_border = '3b4252',
	},
	-- https://github.com/morhetz/gruvbox (dark): bg0, fg1, bright yellow/green/red/blue/orange, bg0_h.
	{
		id = 'gruvbox_dark', name = 'Gruvbox', group = 'dark',
		foreground = 'fabd2f', foreground_text = '282828',
		background = '282828', background_text = 'ebdbb2',
		curtain = '1d2021', success = 'b8bb26', error = 'fb4934',
		match = '83a598', heatmap = 'fe8019', window_border = '1d2021',
	},
	-- https://rosepinetheme.com/palette (main): base, text, rose, surface, love, gold.
	-- No green or blue in this scheme: foam (used for git additions) for success, iris for match.
	{
		id = 'rose_pine', name = 'Rosé Pine', group = 'dark',
		foreground = 'ebbcba', foreground_text = '191724',
		background = '191724', background_text = 'e0def4',
		curtain = '191724', success = '9ccfd8', error = 'eb6f92',
		match = 'c4a7e7', heatmap = 'f6c177', window_border = '1f1d2e',
	},
	-- https://github.com/rebelot/kanagawa.nvim (wave): sumiInk3, fujiWhite, crystalBlue,
	-- sumiInk0, springGreen, samuraiRed, springBlue, surimiOrange.
	{
		id = 'kanagawa_wave', name = 'Kanagawa', group = 'dark',
		foreground = '7e9cd8', foreground_text = '1f1f28',
		background = '1f1f28', background_text = 'dcd7ba',
		curtain = '16161d', success = '98bb6c', error = 'e82424',
		match = '7fb4ca', heatmap = 'ffa066', window_border = '16161d',
	},
	-- Atom One Dark (https://github.com/atom/atom/tree/master/packages/one-dark-syntax): bg, fg, blue,
	-- darker bg, green, red, cyan, purple.
	{
		id = 'one_dark', name = 'One Dark', group = 'dark',
		foreground = '61afef', foreground_text = '282c34',
		background = '282c34', background_text = 'abb2bf',
		curtain = '21252b', success = '98c379', error = 'e06c75',
		match = '56b6c2', heatmap = 'c678dd', window_border = '21252b',
	},
	-- https://github.com/sainnhe/everforest/blob/master/palette.md (dark, medium): bg0, fg, green,
	-- bg_dim, aqua, red, blue, orange.
	{
		id = 'everforest_dark', name = 'Everforest', group = 'dark',
		foreground = 'a7c080', foreground_text = '2d353b',
		background = '2d353b', background_text = 'd3c6aa',
		curtain = '232a2e', success = '83c092', error = 'e67e80',
		match = '7fbbb3', heatmap = 'e69875', window_border = '232a2e',
	},
	-- https://catppuccin.com/palette (Latte): base, text, mauve, crust, green, red, blue, peach.
	{
		id = 'catppuccin_latte', name = 'Catppuccin Latte', group = 'light',
		foreground = '8839ef', foreground_text = 'eff1f5',
		background = 'eff1f5', background_text = '4c4f69',
		curtain = 'dce0e8', success = '40a02b', error = 'd20f39',
		match = '1e66f5', heatmap = 'fe640b', window_border = 'dce0e8',
	},
	-- https://github.com/morhetz/gruvbox (light): bg0, fg1, faded orange/green/red/blue/purple, bg1.
	{
		id = 'gruvbox_light', name_key = 'palette_gruvbox_light', group = 'light',
		foreground = 'af3a03', foreground_text = 'fbf1c7',
		background = 'fbf1c7', background_text = '3c3836',
		curtain = 'ebdbb2', success = '79740e', error = '9d0006',
		match = '076678', heatmap = '8f3f71', window_border = 'ebdbb2',
	},
	-- https://ethanschoonover.com/solarized (light): base3, base01, blue, base2, green, red, cyan, orange.
	{
		id = 'solarized_light', name_key = 'palette_solarized_light', group = 'light',
		foreground = '268bd2', foreground_text = 'fdf6e3',
		background = 'fdf6e3', background_text = '586e75',
		curtain = 'eee8d5', success = '859900', error = 'dc322f',
		match = '2aa198', heatmap = 'cb4b16', window_border = 'eee8d5',
	},
	-- Retro: hikari's own palettes after 80s and 90s anime, not copies of a theme.
	-- Cel: hand-painted celluloid, vermilion on a warm brown-black, cream text.
	{
		id = 'cel', name = 'Cel', group = 'retro',
		foreground = 'e8643a', foreground_text = '1f1a16',
		background = '1f1a16', background_text = 'efe4cc',
		curtain = '120e0b', success = '8fae5a', error = 'd8434f',
		match = '6fa8b8', heatmap = 'e8b04a', window_border = '120e0b',
	},
	-- City Pop: 80s album covers and city nights, neon pink on navy.
	{
		id = 'city_pop', name = 'City Pop', group = 'retro',
		foreground = 'ff7eb3', foreground_text = '1d1a3a',
		background = '1d1a3a', background_text = 'f7eaf3',
		curtain = '120f27', success = '7de3c6', error = 'ff5d5d',
		match = '72d4ff', heatmap = 'ffb36b', window_border = '120f27',
	},
	-- Phosphor: the amber and green screens of 90s science fiction.
	{
		id = 'phosphor', name = 'Phosphor', group = 'retro',
		foreground = 'ffb000', foreground_text = '0f1412',
		background = '0f1412', background_text = 'd9e6d3',
		curtain = '080b0a', success = '4fd96b', error = 'ff5a48',
		match = '5ad1d6', heatmap = 'd27be0', window_border = '080b0a',
	},
	-- Cel Light: Cel by day, its inks darkened to read on a paper-coloured background.
	{
		id = 'cel_light', name_key = 'palette_cel_light', group = 'retro',
		foreground = 'c24a2c', foreground_text = 'f2e8d3',
		background = 'f2e8d3', background_text = '2e2620',
		curtain = 'e2d5ba', success = '5d7f2e', error = 'a3243a',
		match = '2f6e88', heatmap = 'b86f12', window_border = 'e2d5ba',
	},
	-- SCEPTIC: personal palette (dark, cyan accent, medium transparency). Edit freely.
	--   foreground      fill of the timeline and volume bar, active buttons and the selected menu item
	--   foreground_text text drawn on top of foreground (selected item, timeline time labels)
	--   background      background of menus, timeline and bars
	--   background_text text and icons drawn on top of background
	--   curtain         dims the video behind open menus
	--   success / error colours for success and error messages and states
	--   match           letters that match a menu search
	--   heatmap         "most replayed" graph drawn over the timeline (YouTube)
	--   window_border   thin border around the window in borderless mode
	--   opacity         0 = fully transparent, 1 = opaque; only backgrounds and shapes, never text.
	--                   Keys left out keep uosc's default (see OPACITY_KEYS for the full list).
	{
		id = 'sceptic', name = 'SCEPTIC', group = 'custom',
		foreground = '5ad4e6', foreground_text = '0b0d12',
		background = '0b0d12', background_text = 'e6edf3',
		curtain = '05070a', success = '7ee787', error = 'ff6b7a',
		match = 'b48cff', heatmap = '5ad4e6', window_border = '0b0d12',
		opacity = {menu = 0.75, title = 0.75, tooltip = 0.75, timeline = 0.6, position = 0.5, curtain = 0.5},
	},
}

local GROUP_TITLES = {
	dark = 'palettes_group_dark', light = 'palettes_group_light', retro = 'palettes_group_retro',
	custom = 'palettes_group_custom',
}

-- A palette's name in the menu: its own name, or the translated one for the
-- few with a word in it ("Gruvbox Light").
local function palette_name(palette)
	if palette.name_key then return i18n.t(palette.name_key) end
	return palette.name
end

local by_id = {}
for _, palette in ipairs(PALETTES) do by_id[palette.id] = palette end

local function is_valid_id(id) return type(id) == 'string' and id:match('^[a-z0-9_-]+$') ~= nil end
local function is_valid_color(color) return type(color) == 'string' and color:match('^%x%x%x%x%x%x$') ~= nil end

-- Formats an opacity 0..1 as `0.75` with two decimals. Built from integers so the
-- decimal separator is always '.', whatever the C locale says. Nil if out of range.
local function format_opacity(value)
	if type(value) ~= 'number' or value ~= value or value < 0 or value > 1 then return nil end
	local hundredths = math.floor(value * 100 + 0.5)
	local text = string.format('%d.%02d', math.floor(hundredths / 100), hundredths % 100)
	return text:match('^[01]%.%d%d$') and text or nil
end

-- Returns the palette for `id`, or the uosc original when the id is unknown.
local function get_palette(id)
	return by_id[id] or by_id[DEFAULT_ID]
end

-- Builds the value of uosc's `color` option: `foreground=ffffff,background=000000,...`.
-- Returns nil if any colour is malformed.
local function color_string(palette)
	local parts = {}
	for _, key in ipairs(COLOR_KEYS) do
		local color = palette[key]
		if not is_valid_color(color) then
			msg.error('Palette "' .. tostring(palette.id) .. '" has an invalid ' .. key .. ': ' .. tostring(color))
			return nil
		end
		parts[#parts + 1] = key .. '=' .. color:lower()
	end
	return table.concat(parts, ',')
end

-- Builds the value of uosc's `opacity` option: `timeline=0.60,menu=0.75,...`, or ''
-- when the palette has no opacity (uosc then falls back to its defaults).
-- Returns nil if a key is unknown or a value is not a number in 0..1.
local function opacity_string(palette)
	local opacity = palette.opacity
	if opacity == nil then return '' end
	if type(opacity) ~= 'table' then
		msg.error('Palette "' .. tostring(palette.id) .. '" has an invalid opacity table')
		return nil
	end
	for key in pairs(opacity) do
		if not OPACITY_KEY_SET[key] then
			msg.error('Palette "' .. tostring(palette.id) .. '" has an unknown opacity key: ' .. tostring(key))
			return nil
		end
	end
	local parts = {}
	for _, key in ipairs(OPACITY_KEYS) do
		if opacity[key] ~= nil then
			local text = format_opacity(opacity[key])
			if not text then
				msg.error('Palette "' .. tostring(palette.id) .. '" has an invalid opacity ' .. key .. ': '
					.. tostring(opacity[key]))
				return nil
			end
			parts[#parts + 1] = key .. '=' .. text
		end
	end
	return table.concat(parts, ',')
end

-- Content of the persisted config file, or nil if the palette or the side bar
-- style (`black` when left out) doesn't validate.
local function persist_content(palette, bars)
	bars = bars or DEFAULT_BARS
	local colors, opacity = color_string(palette), opacity_string(palette)
	if not colors or not opacity or not is_valid_id(palette.id) or not is_valid_id(script_name) then return nil end
	if not BARS_SET[bars] then return nil end
	return '# Generated by hikari-palettes.lua. Palette: ' .. palette.id .. '\n'
		.. 'script-opts-append=uosc-color=' .. colors .. '\n'
		.. 'script-opts-append=uosc-opacity=' .. opacity .. '\n'
		.. 'script-opts-append=suji-accent=' .. palette.foreground:lower() .. '\n'
		.. 'script-opts-append=' .. script_name .. '-palette=' .. palette.id .. '\n'
		.. 'script-opts-append=' .. script_name .. '-bars=' .. bars .. '\n'
end

-- Writes a whole file or none (script-modules/hikari-files.lua).
local write_file_atomic = load_module('hikari-files').write_file_atomic

-- A side bar style from outside (options), or black with a warning.
local function checked_bars(value)
	if BARS_SET[value] then return value end
	msg.warn('Unknown side bar style "' .. (tostring(value):sub(1, 64):gsub('%c', '?')) .. '", using ' .. DEFAULT_BARS)
	return DEFAULT_BARS
end

local update_bars -- defined below, called when the option changes
local opts = {palette = DEFAULT_ID, bars = DEFAULT_BARS}
options.read_options(opts, script_name, function(changed)
	if changed.bars then
		opts.bars = checked_bars(opts.bars)
		update_bars()
	end
end)
opts.bars = checked_bars(opts.bars)
local active_id = get_palette(opts.palette).id
if active_id ~= opts.palette then
	msg.warn('Unknown palette "' .. (tostring(opts.palette):sub(1, 64):gsub('%c', '?')) .. '", using ' .. DEFAULT_ID)
end

-- suji's accent, the palette's foreground, while suji is turned on.
local function apply_accent(palette)
	if menu.suji() and is_valid_color(palette.foreground) then
		mp.commandv('change-list', 'script-opts', 'append', 'suji-accent=' .. palette.foreground:lower())
	end
end

-- Side bars ------------------------------------------------------------------

-- What the side bars need: osd-dimensions and current-tracks/video, as observed.
local bars_state = {dims = nil, video = nil}
-- `background-color` as it was just before this script coloured the bars: the
-- user's own or mpv's. Read again each time the bars get coloured, so a value
-- changed meanwhile (a conditional profile, the console) is the one put back.
-- Nil when this mpv has no such property; then the bars stay black, with one warning.
local original_bg = nil
local bg_set = nil       -- the colour this script put in background-color, nil when none
local bg_warned = false
-- `sub-use-margins` as it was just before the stripes turned it off, read
-- again each time like `background-color`; subs_set is true while it is off
-- because of them. See update_bars.
local original_subs = nil
local subs_set = false
-- True while this script has taken sub-use-margins out of watch-later-options.
local watch_later_removed = false
local stripes_overlay = mp.create_osd_overlay('ass-events')
-- Below uosc, suji and hikari-skip's button (all at the default z, 0). Script
-- overlays are drawn over subtitles whatever their z, so while the stripes
-- are there text subtitles are kept inside the picture (see update_bars).
stripes_overlay.z = -10
local stripes_drawn = nil -- what the overlay shows, nil when removed

local function round(value) return math.floor(value + 0.5) end

-- Window size and left and right margins when the video has bars at both sides
-- (osd-dimensions, in OSD pixels), or nil: no video, a picture or cover art, no
-- window yet, or margins too thin to be bars.
local function side_bars()
	local d, video = bars_state.dims, bars_state.video
	if type(d) ~= 'table' or type(video) ~= 'table' or video.image or video.albumart then return nil end
	local w, h, ml, mr = tonumber(d.w), tonumber(d.h), tonumber(d.ml), tonumber(d.mr)
	if not (w and h and ml and mr) or w <= 0 or h <= 0 then return nil end
	local min = w * BARS_MIN_SHARE
	if ml < min or mr < min then return nil end
	return w, h, ml, mr
end

-- RRGGBB -> BBGGRR, the order ASS colour tags use (as in hikari-skip.lua).
local function to_bgr(hex)
	return (hex:sub(5, 6) .. hex:sub(3, 4) .. hex:sub(1, 2)):upper()
end

-- ASS for the stripes: foreground, heatmap and match, from the image edge out,
-- the right bar a mirror of the left one, top to bottom like the stripes on
-- the spine of an 80s VHS box. The three take up 20 % of the bar's width and
-- start 10 % of it away from the image, so they read as part of the frame
-- without touching the picture. Each stripe is a quarter of that 20 %, the two
-- gaps an eighth each: 3 * 1/4 + 2 * 1/8 = 1. A stripe is at least one pixel.
-- They can sit this close to the picture because subtitles stay inside it
-- while they are drawn (update_bars). With mpv's default sub-use-margins a
-- long line gets within 7 to 68 px of the window edge (libass 0.17.3, 4:3
-- video, windows 600 to 2160 px high): that room follows the window height,
-- not the bar, and was too narrow for stripes of a visible width.
-- Nil if a colour is malformed.
local function stripes_ass(palette, w, h, ml, mr)
	local events = {}
	for i, key in ipairs({'foreground', 'heatmap', 'match'}) do
		local color = palette[key]
		if not is_valid_color(color) then return nil end
		local shapes = {}
		for _, side in ipairs({{bar = ml, edge = ml, dir = -1}, {bar = mr, edge = w - mr, dir = 1}}) do
			local width = side.bar * 0.20 / 4
			local near = side.edge + side.dir * (side.bar * 0.10 + (i - 1) * width * 1.5)
			local far = near + side.dir * width
			local x0, x1 = round(math.min(near, far)), round(math.max(near, far))
			if x1 <= x0 then x1 = x0 + 1 end
			shapes[#shapes + 1] = string.format('m %d 0 l %d 0 l %d %d l %d %d', x0, x1, x1, h, x0, h)
		end
		events[#events + 1] = string.format('{\\an7\\pos(0,0)\\bord0\\shad0\\blur0\\1c&H%s&\\1a&H00&\\p1}%s{\\p0}',
			to_bgr(color:lower()), table.concat(shapes, ' '))
	end
	return table.concat(events, '\n')
end

local function warn_background_once(text)
	if bg_warned then return end
	bg_warned = true
	msg.warn(text)
end

-- Puts the side bars in line with the option, the active palette, the window
-- and the video. Cheap when nothing changed: mpv and the overlay are only
-- touched when what they show has to change.
update_bars = function()
	local palette = get_palette(active_id)
	local w, h, ml, mr = side_bars()
	local color = nil
	if opts.bars ~= 'black' and w and is_valid_color(palette.curtain) then color = '#' .. palette.curtain:lower() end
	if color and not bg_set then original_bg = mp.get_property('background-color') end
	if color and original_bg == nil then
		warn_background_once('This mpv has no background-color property: side bars stay black')
		color = nil
	end
	if color then
		if color ~= bg_set then
			if mp.set_property('background-color', color) then
				bg_set = color
			else
				warn_background_once('Could not set background-color: side bars stay black')
			end
		end
	elseif bg_set then
		-- Kept as set when mpv refuses: the next update tries again.
		if mp.set_property('background-color', original_bg) then bg_set = nil end
	end

	local data = opts.bars == 'stripes' and w and stripes_ass(palette, w, h, ml, mr) or nil
	-- Text subtitles inside the picture while the stripes are drawn, as on a
	-- TV of the time: the stripes would cover a line spreading into the bars.
	-- ASS subtitles are left alone: they only go into the bars with
	-- sub-ass-force-margins, off by default, and whoever turned it on wants
	-- them there. With `palette` (colour only) nothing covers
	-- subtitles, so sub-use-margins is not touched.
	-- Meanwhile sub-use-margins is out of watch-later-options (in it by
	-- default): with save-position-on-quit, closing mpv with the stripes on
	-- would save hikari's `no`, and resuming would bring it back as the user's.
	if data and not subs_set then
		original_subs = mp.get_property('sub-use-margins')
		if original_subs ~= nil and mp.set_property('sub-use-margins', 'no') then
			subs_set = true
			local list = mp.get_property_native('watch-later-options')
			local listed = false
			for _, name in ipairs(type(list) == 'table' and list or {}) do
				if name == 'sub-use-margins' then listed = true end
			end
			if listed and mp.commandv('change-list', 'watch-later-options', 'remove', 'sub-use-margins') then
				watch_later_removed = true
			end
		end
	elseif not data and subs_set then
		if mp.set_property('sub-use-margins', original_subs) then subs_set = false end
	end
	-- Back in the list once the user's value is; tried again if mpv refuses.
	if not subs_set and watch_later_removed
		and mp.commandv('change-list', 'watch-later-options', 'append', 'sub-use-margins') then
		watch_later_removed = false
	end
	if data then
		local key = w .. 'x' .. h .. '\n' .. data
		if key ~= stripes_drawn then
			stripes_overlay.res_x, stripes_overlay.res_y = w, h
			stripes_overlay.data = data
			stripes_overlay:update()
			stripes_drawn = key
		end
	elseif stripes_drawn then
		stripes_overlay:remove()
		stripes_drawn = nil
	end
end

-- Palettes ------------------------------------------------------------------

-- Applies a palette on the fly; uosc reacts to script-opts changes by itself.
-- Opacity is always set, empty for palettes without it, so a previous palette's
-- transparency doesn't stick.
local function apply(palette)
	local colors, opacity = color_string(palette), opacity_string(palette)
	if not colors or not opacity then return false end
	mp.commandv('change-list', 'script-opts', 'append', 'uosc-color=' .. colors)
	mp.commandv('change-list', 'script-opts', 'append', 'uosc-opacity=' .. opacity)
	apply_accent(palette)
	active_id = palette.id
	-- Coloured side bars follow the palette at once.
	update_bars()
	return true
end

-- Saves the palette together with the side bar style in use.
local function save(palette)
	local content = persist_content(palette, opts.bars)
	local path = mp.command_native({'expand-path', PERSIST_PATH})
	local ok, err = false, 'invalid palette data'
	if content and path then ok, err = write_file_atomic(path, content) end
	if not ok then
		msg.warn('Could not save palette to ' .. tostring(path) .. ': ' .. tostring(err))
		mp.osd_message(i18n.t('palettes_save_failed'), 3)
	end
	return ok
end

-- Handler for menu selections. The id comes from outside, so it must match the table.
local function select_palette(id)
	local palette = by_id[id]
	if not palette then
		msg.warn('Ignoring unknown palette id: ' .. (tostring(id):sub(1, 64):gsub('%c', '?')))
		return
	end
	if apply(palette) then save(palette) end
end

-- Handler for the side bar items of the menu; the value must be in BARS.
local function select_bars(value)
	if not BARS_SET[value] then
		msg.warn('Ignoring unknown side bar style: ' .. (tostring(value):sub(1, 64):gsub('%c', '?')))
		return
	end
	opts.bars = value
	update_bars()
	save(get_palette(active_id))
end

local function menu_data()
	local items = {}
	local last_group
	for _, palette in ipairs(PALETTES) do
		if palette.group ~= last_group then
			if #items > 0 then items[#items].separator = true end
			items[#items + 1] = {
				title = i18n.t(GROUP_TITLES[palette.group]), selectable = false, muted = true, italic = true,
			}
			last_group = palette.group
		end
		items[#items + 1] = {
			title = palette_name(palette),
			hint = palette.id == active_id and i18n.t('active') or nil,
			active = palette.id == active_id,
			value = {'script-message-to', script_name, 'select-palette', palette.id},
		}
	end
	-- The side bar styles last, after SCEPTIC, marked like the palettes.
	items[#items].separator = true
	items[#items + 1] = {title = i18n.t('palettes_group_bars'), selectable = false, muted = true, italic = true}
	for _, bars in ipairs(BARS) do
		items[#items + 1] = {
			title = i18n.t(bars.key),
			hint = bars.id == opts.bars and i18n.t('active') or nil,
			active = bars.id == opts.bars,
			value = {'script-message-to', script_name, 'select-bars', bars.id},
		}
	end
	return {type = MENU_TYPE, title = i18n.t('palettes_title'), items = items}
end

-- Only shown by mpv's selector, when uosc is not there to be coloured.
local function menu_opts() return {note = i18n.t('palettes_need_uosc')} end

-- The menu as it goes out: in suji, with a first line about its accent.
local function shown_data()
	local data = menu_data()
	if menu.suji() then
		table.insert(data.items, 1, {title = i18n.t('palettes_suji_accent'), selectable = false, muted = true})
	end
	return data
end

local function open_menu() menu.open(shown_data(), menu_opts()) end

mp.register_script_message('select-palette', select_palette)
mp.register_script_message('select-bars', select_bars)
mp.add_key_binding(nil, 'open-menu', open_menu)
-- Another language: an open palette menu is redrawn in it.
i18n.on_change(function()
	if menu.is_open(MENU_TYPE) then menu.update(shown_data(), menu_opts()) end
end)

-- Re-apply from the table at start-up so edits to a palette (e.g. SCEPTIC) take
-- effect without picking it again; the included .conf only covers the first frame.
apply(get_palette(active_id))
-- suji started after this script, or was turned on again: the accent of the
-- palette in use. Without suji the property never exists: nothing is sent.
mp.observe_property('user-data/suji/enabled', 'native', function(_, value)
	if value == true then apply_accent(get_palette(active_id)) end
end)
-- Side bars come and go with the window size, the video's shape and the file.
mp.observe_property('osd-dimensions', 'native', function(_, dims)
	bars_state.dims = dims
	update_bars()
end)
mp.observe_property('current-tracks/video', 'native', function(_, video)
	bars_state.video = video
	update_bars()
end)

if HIKARI_PALETTES_TEST then
	return {
		PALETTES = PALETTES, COLOR_KEYS = COLOR_KEYS, OPACITY_KEYS = OPACITY_KEYS,
		get_palette = get_palette, color_string = color_string,
		opacity_string = opacity_string, format_opacity = format_opacity,
		persist_content = persist_content, write_file_atomic = write_file_atomic,
		apply = apply, save = save, select_palette = select_palette,
		menu_data = menu_data, shown_data = shown_data, open_menu = open_menu,
		is_valid_id = is_valid_id, is_valid_color = is_valid_color,
		get_active_id = function() return active_id end,
		BARS = BARS, select_bars = select_bars, stripes_ass = stripes_ass, side_bars = side_bars,
		get_bars = function() return opts.bars end,
		stripes_overlay = stripes_overlay,
	}
end
