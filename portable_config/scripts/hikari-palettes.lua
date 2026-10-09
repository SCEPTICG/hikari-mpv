-- hikari-palettes: colour palette picker for uosc.
--
-- Opens a uosc menu with the available palettes, applies the chosen one on the
-- fly through the `uosc-color` and `uosc-opacity` script options and saves it to
-- `~~/hikari-palette.conf`, which mpv.conf includes on the next start.
--
-- mpv turns this file name into the script name `hikari_palettes`, so:
--   input.conf:  Alt+p script-binding hikari_palettes/open-menu
--   options:     script-opts=hikari_palettes-palette=<id>

local msg = require('mp.msg')
local utils = require('mp.utils')
local options = require('mp.options')

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
local PERSIST_PATH = '~~/hikari-palette.conf'

-- group: 'dark', 'light' or 'custom'. Colours are RRGGBB without '#'.
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
		id = 'gruvbox_light', name = 'Gruvbox claro', group = 'light',
		foreground = 'af3a03', foreground_text = 'fbf1c7',
		background = 'fbf1c7', background_text = '3c3836',
		curtain = 'ebdbb2', success = '79740e', error = '9d0006',
		match = '076678', heatmap = '8f3f71', window_border = 'ebdbb2',
	},
	-- https://ethanschoonover.com/solarized (light): base3, base01, blue, base2, green, red, cyan, orange.
	{
		id = 'solarized_light', name = 'Solarized claro', group = 'light',
		foreground = '268bd2', foreground_text = 'fdf6e3',
		background = 'fdf6e3', background_text = '586e75',
		curtain = 'eee8d5', success = '859900', error = 'dc322f',
		match = '2aa198', heatmap = 'cb4b16', window_border = 'eee8d5',
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

local GROUP_TITLES = {dark = 'Oscuras', light = 'Claras', custom = 'Propia'}

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

-- Content of the persisted config file, or nil if the palette doesn't validate.
local function persist_content(palette)
	local colors, opacity = color_string(palette), opacity_string(palette)
	if not colors or not opacity or not is_valid_id(palette.id) or not is_valid_id(script_name) then return nil end
	return '# Generated by hikari-palettes.lua. Palette: ' .. palette.id .. '\n'
		.. 'script-opts-append=uosc-color=' .. colors .. '\n'
		.. 'script-opts-append=uosc-opacity=' .. opacity .. '\n'
		.. 'script-opts-append=' .. script_name .. '-palette=' .. palette.id .. '\n'
end

-- Writes through a temporary file and a rename so a crash never leaves half a file.
local function write_file_atomic(path, content)
	local tmp = path .. '.tmp'
	local file, err = io.open(tmp, 'wb')
	if not file then return false, err end
	local ok, write_err = file:write(content)
	local closed, close_err = file:close()
	if not ok or not closed then
		os.remove(tmp)
		return false, write_err or close_err
	end
	local renamed, rename_err = os.rename(tmp, path)
	if not renamed then
		-- On Windows rename() won't replace an existing file: remove it and retry.
		os.remove(path)
		renamed, rename_err = os.rename(tmp, path)
	end
	if not renamed then
		os.remove(tmp)
		return false, rename_err
	end
	return true
end

local opts = {palette = DEFAULT_ID}
options.read_options(opts, script_name)
local active_id = get_palette(opts.palette).id
if active_id ~= opts.palette then
	msg.warn('Unknown palette "' .. tostring(opts.palette) .. '", using ' .. DEFAULT_ID)
end

-- Applies a palette on the fly; uosc reacts to script-opts changes by itself.
-- Opacity is always set, empty for palettes without it, so a previous palette's
-- transparency doesn't stick.
local function apply(palette)
	local colors, opacity = color_string(palette), opacity_string(palette)
	if not colors or not opacity then return false end
	mp.commandv('change-list', 'script-opts', 'append', 'uosc-color=' .. colors)
	mp.commandv('change-list', 'script-opts', 'append', 'uosc-opacity=' .. opacity)
	active_id = palette.id
	return true
end

local function save(palette)
	local content = persist_content(palette)
	local path = mp.command_native({'expand-path', PERSIST_PATH})
	local ok, err = false, 'invalid palette data'
	if content and path then ok, err = write_file_atomic(path, content) end
	if not ok then
		msg.warn('Could not save palette to ' .. tostring(path) .. ': ' .. tostring(err))
		mp.osd_message('hikari: no se pudo guardar la paleta', 3)
	end
	return ok
end

-- Handler for menu selections. The id comes from outside, so it must match the table.
local function select_palette(id)
	local palette = by_id[id]
	if not palette then
		msg.warn('Ignoring unknown palette id: ' .. tostring(id))
		return
	end
	if apply(palette) then save(palette) end
end

local function menu_data()
	local items = {}
	local last_group
	for _, palette in ipairs(PALETTES) do
		if palette.group ~= last_group then
			if #items > 0 then items[#items].separator = true end
			items[#items + 1] = {
				title = GROUP_TITLES[palette.group], selectable = false, muted = true, italic = true,
			}
			last_group = palette.group
		end
		items[#items + 1] = {
			title = palette.name,
			hint = palette.id == active_id and 'activa' or nil,
			active = palette.id == active_id,
			value = {'script-message-to', script_name, 'select-palette', palette.id},
		}
	end
	return {type = 'hikari-palettes', title = 'Paletas', items = items}
end

local function open_menu()
	local json, err = utils.format_json(menu_data())
	if not json then
		msg.error('Could not build the palette menu: ' .. tostring(err))
		return
	end
	mp.commandv('script-message-to', 'uosc', 'open-menu', json)
end

mp.register_script_message('select-palette', select_palette)
mp.add_key_binding(nil, 'open-menu', open_menu)

-- Re-apply from the table at start-up so edits to a palette (e.g. SCEPTIC) take
-- effect without picking it again; the included .conf only covers the first frame.
apply(get_palette(active_id))

if HIKARI_PALETTES_TEST then
	return {
		PALETTES = PALETTES, COLOR_KEYS = COLOR_KEYS, OPACITY_KEYS = OPACITY_KEYS,
		get_palette = get_palette, color_string = color_string,
		opacity_string = opacity_string, format_opacity = format_opacity,
		persist_content = persist_content, write_file_atomic = write_file_atomic,
		apply = apply, save = save, select_palette = select_palette,
		menu_data = menu_data, open_menu = open_menu,
		is_valid_id = is_valid_id, is_valid_color = is_valid_color,
		get_active_id = function() return active_id end,
	}
end
