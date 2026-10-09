-- hikari-speed: playback speed menu for uosc.
--
-- Opens a uosc menu with a few fixed speeds; picking one sets `speed` and uosc
-- closes the menu. Labels use the decimal separator of hikari's language
-- (`0,75×` in Spanish, `0.75×` in English).
--
-- mpv turns this file name into the script name `hikari_speed`, so:
--   input.conf:  <key> script-binding hikari_speed/open-menu

local msg = require('mp.msg')
local utils = require('mp.utils')

-- Texts in the chosen language: ~~/script-modules/hikari-i18n.lua. Single-file
-- scripts get no mpv folder in package.path, so the folder is added for this
-- one require and taken out again (see the header of hikari-i18n.lua).
local i18n = (function()
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then
		error('hikari: unusable script-modules folder: ' .. tostring(dir))
	end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, 'hikari-i18n')
	package.path = saved
	if not ok then error('hikari: cannot load script-modules/hikari-i18n.lua (reinstall hikari): ' .. tostring(module)) end
	return module
end)()

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
		msg.warn('Ignoring unknown speed: ' .. tostring(arg))
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

local function send_menu(message)
	local json, err = utils.format_json(menu_data())
	if not json then
		msg.error('Could not build the speed menu: ' .. tostring(err))
		return
	end
	mp.commandv('script-message-to', 'uosc', message, json)
end

local function open_menu() send_menu('open-menu') end

mp.register_script_message('select-speed', select_speed)
mp.add_key_binding(nil, 'open-menu', open_menu)
-- Another language: an open speed menu is redrawn in it.
i18n.on_change(function()
	if mp.get_property('user-data/uosc/menu/type') == MENU_TYPE then send_menu('update-menu') end
end)

if HIKARI_SPEED_TEST then
	return {SPEEDS = SPEEDS, label = label, select_speed = select_speed, menu_data = menu_data, open_menu = open_menu}
end
