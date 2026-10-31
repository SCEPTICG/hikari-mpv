-- hikari-speed: playback speed menu.
--
-- Opens a menu with a few fixed speeds (uosc's, or mpv's own selector without
-- uosc: script-modules/hikari-menu.lua); picking one sets `speed` and the menu
-- closes. Labels use the decimal separator of hikari's language (`0,75×` in
-- Spanish, `0.75×` in English).
--
-- mpv turns this file name into the script name `hikari_speed`, so:
--   input.conf:  <key> script-binding hikari_speed/open-menu

local msg = require('mp.msg')

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

-- `arg` is what travels through the menu and what `set speed` receives, kept as
-- a string so the decimal separator never depends on the C locale. `normal`
-- marks the speed labelled "(normal)".
local SPEEDS = {
	{arg = '0.5', value = 0.5},
	{arg = '0.75', value = 0.75},
	{arg = '1', value = 1, normal = true},
	{arg = '1.25', value = 1.25},
	{arg = '1.5', value = 1.5},
	{arg = '2', value = 2},
}
local MENU_TYPE = 'hikari-speed'
local by_arg = {}
for _, speed in ipairs(SPEEDS) do by_arg[speed.arg] = speed end

local TOLERANCE = 0.001

local function is_current(speed, current)
	return type(current) == 'number' and math.abs(current - speed.value) < TOLERANCE
end

-- Handler for menu selections. The argument comes from outside, so only the
-- exact strings in SPEEDS are accepted.
local function select_speed(arg)
	local speed = by_arg[arg]
	if not speed then
		msg.warn('Ignoring unknown speed: ' .. (tostring(arg):sub(1, 64):gsub('%c', '?')))
		return
	end
	mp.commandv('set', 'speed', speed.arg)
end

-- `0,75×`, `1× (normal)`: the menu label of a speed in the current language.
local function label(speed)
	local text = i18n.decimal(speed.arg) .. '×'
	if speed.normal then return i18n.t('speed_normal', {speed = text}) end
	return text
end

local function menu_data()
	local current = mp.get_property_number('speed')
	local items = {}
	for _, speed in ipairs(SPEEDS) do
		local active = is_current(speed, current)
		items[#items + 1] = {
			title = label(speed),
			hint = active and i18n.t('current') or nil,
			active = active,
			value = {'script-message-to', script_name, 'select-speed', speed.arg},
		}
	end
	return {type = MENU_TYPE, title = i18n.t('speed_title'), items = items}
end

local function open_menu() menu.open(menu_data()) end

mp.register_script_message('select-speed', select_speed)
mp.add_key_binding(nil, 'open-menu', open_menu)
-- Another language: an open speed menu is redrawn in it.
i18n.on_change(function()
	if menu.is_open(MENU_TYPE) then menu.update(menu_data()) end
end)

if HIKARI_SPEED_TEST then
	return {SPEEDS = SPEEDS, label = label, select_speed = select_speed, menu_data = menu_data, open_menu = open_menu}
end
