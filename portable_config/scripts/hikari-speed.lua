-- hikari-speed: playback speed menu for uosc.
--
-- Opens a uosc menu with a few fixed speeds; picking one sets `speed` and uosc
-- closes the menu.
--
-- mpv turns this file name into the script name `hikari_speed`, so:
--   input.conf:  <key> script-binding hikari_speed/open-menu

local msg = require('mp.msg')
local utils = require('mp.utils')

local script_name = mp.get_script_name()

-- `arg` is what travels through the menu and what `set speed` receives, kept as
-- a string so the decimal separator never depends on the C locale.
local SPEEDS = {
	{arg = '0.5', value = 0.5, label = '0,5×'},
	{arg = '0.75', value = 0.75, label = '0,75×'},
	{arg = '1', value = 1, label = '1× (normal)'},
	{arg = '1.25', value = 1.25, label = '1,25×'},
	{arg = '1.5', value = 1.5, label = '1,5×'},
	{arg = '2', value = 2, label = '2×'},
}
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

local function menu_data()
	local current = mp.get_property_number('speed')
	local items = {}
	for _, speed in ipairs(SPEEDS) do
		local active = is_current(speed, current)
		items[#items + 1] = {
			title = speed.label,
			hint = active and 'actual' or nil,
			active = active,
			value = {'script-message-to', script_name, 'select-speed', speed.arg},
		}
	end
	return {type = 'hikari-speed', title = 'Velocidad', items = items}
end

local function open_menu()
	local json, err = utils.format_json(menu_data())
	if not json then
		msg.error('Could not build the speed menu: ' .. tostring(err))
		return
	end
	mp.commandv('script-message-to', 'uosc', 'open-menu', json)
end

mp.register_script_message('select-speed', select_speed)
mp.add_key_binding(nil, 'open-menu', open_menu)

if HIKARI_SPEED_TEST then
	return {SPEEDS = SPEEDS, select_speed = select_speed, menu_data = menu_data, open_menu = open_menu}
end
