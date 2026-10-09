-- Run from the repository root: lua tests/test_speed.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/hikari-speed.lua'
local SCRIPT_NAME = 'hikari_speed'

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print('ok   ' .. name)
	else
		failed = failed + 1
		print('FAIL ' .. name .. '\n     ' .. tostring(err))
	end
end

local function eq(actual, expected, what)
	if actual ~= expected then
		error((what or 'value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
	end
end

local function load()
	mock.install(SCRIPT_NAME)
	-- The assertions below are in Spanish.
	mock.script_opts = {['hikari-language'] = 'es'}
	HIKARI_SPEED_TEST = true
	local chunk = assert(loadfile(SCRIPT))
	return chunk()
end

test('binding and script message are registered', function()
	load()
	assert(mock.bindings['open-menu'], 'open-menu binding')
	assert(mock.messages['select-speed'], 'select-speed message')
end)

test('menu lists the six speeds with Spanish labels', function()
	local s = load()
	local data = s.menu_data()
	eq(data.title, 'Velocidad'); eq(data.type, 'hikari-speed')
	local expected = {'0,5×', '0,75×', '1× (normal)', '1,25×', '1,5×', '2×'}
	eq(#data.items, #expected, 'item count')
	for i, label in ipairs(expected) do
		eq(data.items[i].title, label, 'item ' .. i)
		local v = data.items[i].value
		eq(v[1], 'script-message-to'); eq(v[2], SCRIPT_NAME); eq(v[3], 'select-speed')
		eq(v[4], s.SPEEDS[i].arg)
	end
end)

test('the current speed is marked active (with tolerance)', function()
	local s = load()
	mock.props.speed = 1.2500001
	local data = s.menu_data()
	for i, item in ipairs(data.items) do eq(item.active, i == 4, 'active ' .. i) end
	eq(data.items[4].hint, 'actual')
	mock.props.speed = 1.1
	for _, item in ipairs(s.menu_data().items) do eq(item.active, false, 'no match') end
end)

test('open-menu sends the JSON to uosc with the active item', function()
	local s = load()
	mock.props.speed = 1
	mock.bindings['open-menu']()
	local c = mock.commands[1]
	eq(c[1], 'script-message-to'); eq(c[2], 'uosc'); eq(c[3], 'open-menu')
	eq(c[4], mock.format_json(s.menu_data()), 'json payload')
	assert(c[4]:find('"active":true,"hint":"actual","title":"1× (normal)"', 1, true), 'active item in JSON')
	assert(not c[4]:find('keep_open', 1, true), 'menu closes after picking')
end)

test('picking a listed speed sets it', function()
	load()
	mock.messages['select-speed']('0.75')
	eq(#mock.commands, 1)
	local c = mock.commands[1]
	eq(c[1], 'set'); eq(c[2], 'speed'); eq(c[3], '0.75')
end)

test('values not in the list are ignored', function()
	load()
	for _, bad in ipairs({'3', '0.7500', '1.0', '', 'speed', '1;quit', '-1'}) do
		mock.messages['select-speed'](bad)
	end
	mock.messages['select-speed'](nil)
	eq(#mock.commands, 0, 'no command sent')
	eq(#mock.logs.warn, 8, 'one warning each')
end)

test('labels follow the language, decimal separator included; an open menu is redrawn', function()
	local s = load()
	eq(s.label(s.SPEEDS[2]), '0,75×'); eq(s.label(s.SPEEDS[3]), '1× (normal)')
	mock.props['user-data/uosc/menu/type'] = 'hikari-speed'
	mock.set_script_opt('hikari-language', 'en')
	eq(s.label(s.SPEEDS[2]), '0.75×')
	local last = mock.commands[#mock.commands]
	eq(last[3], 'update-menu', 'redrawn')
	assert(last[4]:find('"title":"Speed"', 1, true) and last[4]:find('0.75×', 1, true), 'in English')
	mock.set_script_opt('hikari-language', 'fr')
	eq(s.label(s.SPEEDS[3]), '1× (normale)')
	mock.props['user-data/uosc/menu/type'] = 'hikari-palettes'
	local count = #mock.commands
	mock.set_script_opt('hikari-language', 'de')
	eq(#mock.commands, count, 'another menu open: nothing sent')
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
