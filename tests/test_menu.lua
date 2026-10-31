-- Run from the repository root: lua tests/test_menu.lua
-- The menus module (script-modules/hikari-menu.lua): uosc's messages when uosc
-- is there, mpv's own selector (mp.input.select) when it is not.
package.path = './tests/?.lua;./portable_config/script-modules/?.lua;' .. package.path
local mock = require('mock_mp')

local MODULE = 'portable_config/script-modules/hikari-menu.lua'
local TYPE_PROP = 'user-data/uosc/menu/type'

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

local function read(path)
	local f = assert(io.open(path, 'rb'))
	local s = f:read('*a')
	f:close()
	return s
end

-- A fresh module, as each mpv script gets one. `uosc`: whether uosc is loaded;
-- `input`: whether mpv has mp.input (0.39+).
local function fresh(uosc, input)
	mock.install('hikari_test')
	mock.script_opts = {['hikari-language'] = 'es'}
	mock.uosc = uosc
	if input then mock.enable_input() end
	return require('hikari-menu')
end

local function command(...) return {'script-message-to', 'hikari_test', ...} end

-- A menu like the palette one: a heading, the active item, a plain one, a
-- disabled one and a note.
local function sample(extra)
	local data = {
		type = 'hikari-test', title = 'Paletas',
		items = {
			{title = 'Oscuras', selectable = false, muted = true, italic = true},
			{title = 'Nord', hint = 'activa', active = true, value = command('pick', 'nord')},
			{title = 'Dracula', value = command('pick', 'dracula')},
			{title = 'Serie · E05', hint = 'No disponible', selectable = false, muted = true},
			{title = 'Gruvbox', hint = 'Al día', selectable = false, muted = true, value = command('pick', 'gruvbox')},
			{title = 'Nota', selectable = false, muted = true, italic = true, align = 'center'},
		},
	}
	for k, v in pairs(extra or {}) do data[k] = v end
	return data
end

-- The commands sent other than to uosc (what the selector ran).
local function ran()
	local out = {}
	for _, c in ipairs(mock.commands) do
		if not (c[1] == 'script-message-to' and c[2] == 'uosc') then out[#out + 1] = table.concat(c, ' ') end
	end
	return out
end

-- With uosc ---------------------------------------------------------------------

test('with uosc: open, update and close are the uosc messages, with the same JSON', function()
	local menu = fresh(true)
	local data = sample()
	eq(menu.open(data), true, 'opened')
	eq(#mock.commands, 1, 'one message')
	local c = mock.commands[1]
	eq(c[1], 'script-message-to'); eq(c[2], 'uosc'); eq(c[3], 'open-menu')
	eq(c[4], mock.format_json(data), 'the JSON as before')
	eq(#c, 4)
	menu.update(data)
	eq(table.concat(mock.commands[2], ' ', 1, 3), 'script-message-to uosc update-menu')
	eq(mock.commands[2][4], mock.format_json(data))
	menu.close('hikari-test')
	eq(table.concat(mock.commands[3], ' '), 'script-message-to uosc close-menu hikari-test')
	eq(#mock.selects, 0, 'no selector')
	eq(#mock.osd, 0)
end)

test('with uosc: is_open and observe follow user-data/uosc/menu/type', function()
	local menu = fresh(true, true)
	local seen = {}
	menu.observe(function(value) seen[#seen + 1] = tostring(value) end)
	menu.observe(function(value) seen[#seen + 1] = 'second ' .. tostring(value) end)
	eq(#mock.observers[TYPE_PROP], 1, 'one observer for both')
	eq(menu.is_open('hikari-test'), false)
	mock.set(TYPE_PROP, 'hikari-test')
	eq(menu.is_open('hikari-test'), true)
	eq(menu.is_open('hikari-other'), false)
	mock.set(TYPE_PROP, nil)
	eq(table.concat(seen, ','), 'hikari-test,second hikari-test,nil,second nil')
end)

test('with uosc and mp.input: uosc wins, the selector stays out', function()
	local menu = fresh(true, true)
	menu.open(sample())
	mock.console()
	eq(#mock.selects, 0)
	eq(mock.commands[1][3], 'open-menu')
end)

test('uosc(): a message that reaches uosc, or its uosc-version broadcast', function()
	local menu = fresh(true)
	eq(menu.uosc(), true)
	eq(table.concat(mock.commands[1], ' '), 'script-message-to uosc hikari-probe', 'probe')
	eq(menu.uosc(), true)
	eq(#mock.commands, 1, 'known from then on')
	menu = fresh(false)
	eq(menu.uosc(), false)
	eq(menu.uosc(), false)
	eq(#mock.commands, 2, 'asks again each time')
	local calls = 0
	menu.on_uosc(function() calls = calls + 1 end)
	menu.on_uosc(function() calls = calls + 10 end)
	mock.uosc = true
	mock.commands = {}
	mock.messages['uosc-version']('5.13.0')
	eq(calls, 11, 'every callback')
	eq(menu.uosc(), true)
	eq(#mock.commands, 0, 'no probe after the broadcast')
end)

test('a menu that cannot be encoded: an error in the log, nothing sent', function()
	local menu = fresh(true)
	local data = sample()
	package.loaded['mp.utils'].format_json = function() return nil, 'cannot encode' end
	eq(menu.open(data), false)
	eq(#mock.commands, 0)
	assert(mock.logs.error[1]:find('Could not build the menu hikari-test', 1, true), mock.logs.error[1])
end)

-- Without uosc: mpv's selector ----------------------------------------------------

test('no uosc: the selector, one line per item, hint after the title', function()
	local menu = fresh(false, true)
	eq(menu.open(sample()), true, 'opened')
	eq(#mock.selects, 1)
	local t = mock.selects[1]
	eq(t.prompt, 'Paletas:')
	eq(t.items[1], '— Oscuras —', 'heading')
	eq(t.items[2], '• Nord  ·  activa', 'active, marked')
	eq(t.items[3], 'Dracula')
	eq(t.items[4], '(Serie · E05  ·  No disponible)', 'disabled')
	eq(t.items[5], '(Gruvbox  ·  Al día)', 'disabled with a value')
	eq(t.items[6], '— Nota —', 'note')
	eq(#t.items, 6)
	eq(t.default_item, 2, 'the active item by default')
	eq(#mock.osd, 0)
end)

test('no uosc: selected_index wins over the active item; else the first item that can be chosen', function()
	local menu = fresh(false, true)
	menu.open(sample({selected_index = 3}))
	eq(mock.selects[1].default_item, 3)
	menu = fresh(false, true)
	local data = sample()
	data.items[2].active = nil
	menu.open(data)
	eq(mock.selects[1].default_item, 2, 'first that can be chosen')
	eq(mock.selects[1].items[2], 'Nord  ·  activa', 'no mark')
end)

test('no uosc: a note goes first, as a line that does nothing', function()
	local menu = fresh(false, true)
	menu.open(sample(), {note = 'Las paletas cambian los colores de uosc'})
	local t = mock.selects[1]
	eq(t.items[1], '— Las paletas cambian los colores de uosc —')
	eq(t.items[3], '• Nord  ·  activa')
	eq(t.default_item, 3)
end)

test('no uosc: control characters in titles become spaces', function()
	local menu = fresh(false, true)
	menu.open({type = 'hikari-test', title = 'A\nB', items = {{title = 'x\r\ny', hint = 'h\tz', value = command('x')}}})
	eq(mock.selects[1].prompt, 'A B:')
	eq(mock.selects[1].items[1], 'x  y  ·  h z')
end)

test('no uosc: choosing an item runs its value and closes the menu, told once the value is handled', function()
	local menu = fresh(false, true)
	local seen = {}
	menu.observe(function(value) seen[#seen + 1] = tostring(value) end)
	menu.open(sample())
	eq(menu.is_open('hikari-test'), true)
	mock.console()
	mock.choose(3)
	eq(table.concat(ran(), ';'), 'script-message-to hikari_test pick dracula')
	-- The value is a message to the script, handled after this: the close comes later.
	eq(table.concat(seen, ','), 'hikari-test', 'not told yet')
	mock.advance(menu.REOPEN_DELAY / 2)
	eq(table.concat(seen, ','), 'hikari-test', 'still not')
	mock.advance(menu.REOPEN_DELAY / 2)
	eq(table.concat(seen, ','), 'hikari-test,nil', 'told after REOPEN_DELAY')
	eq(menu.is_open('hikari-test'), false)
	mock.advance(1)
	mock.console()
	eq(#mock.selects, 1, 'not opened again')
	eq(mock.terminates, 0, 'the console closed by itself')
	eq(table.concat(seen, ','), 'hikari-test,nil')
end)

test('no uosc: headings, notes and disabled items do nothing; the menu comes back', function()
	local menu = fresh(false, true)
	menu.open(sample())
	for _, line in ipairs({1, 4, 5, 6}) do
		mock.console()
		mock.choose(line)
		eq(#ran(), 0, 'nothing run for line ' .. line)
		eq(menu.is_open('hikari-test'), true, 'still open')
		mock.advance(menu.REOPEN_DELAY)
		mock.console()
		assert(mock.on_screen, 'back on screen after line ' .. line)
	end
	eq(#mock.selects, 5)
	eq(mock.selects[5].default_item, 2)
end)

test('no uosc: keep_open: the value runs and the menu comes back with the newest data', function()
	local menu = fresh(false, true)
	local data = sample({keep_open = true})
	menu.open(data)
	mock.console()
	mock.choose(3)
	eq(table.concat(ran(), ';'), 'script-message-to hikari_test pick dracula')
	-- The script's own message then sends update-menu, before the menu comes back.
	local updated = sample({keep_open = true})
	updated.items[2].active, updated.items[2].hint = nil, nil
	updated.items[3].active, updated.items[3].hint = true, 'activa'
	menu.update(updated)
	eq(mock.terminates, 0, 'nothing to close')
	mock.advance(menu.REOPEN_DELAY)
	mock.console()
	eq(#mock.selects, 2, 'opened once more')
	eq(mock.selects[2].items[3], '• Dracula  ·  activa')
	eq(mock.selects[2].default_item, 3)
	assert(mock.on_screen == mock.selects[2], 'on screen')
end)

test('no uosc: keep_open: the cursor comes back on the line chosen, if it can still be chosen', function()
	local menu = fresh(false, true)
	menu.open(sample({keep_open = true}))
	mock.console()
	-- Nord is the active one (line 2); Dracula is picked but the update does not mark it.
	mock.choose(3)
	menu.update(sample({keep_open = true}))
	mock.advance(menu.REOPEN_DELAY)
	mock.console()
	eq(mock.selects[2].default_item, 3, 'the line chosen, not the active one')
	-- A heading chosen: not a line to land on; the active item instead.
	mock.choose(1)
	mock.advance(menu.REOPEN_DELAY)
	mock.console()
	eq(mock.selects[3].default_item, 2)
	-- The line chosen cannot be chosen any more: the active item.
	mock.choose(3)
	local updated = sample({keep_open = true})
	updated.items[3].selectable = false
	menu.update(updated)
	mock.advance(menu.REOPEN_DELAY)
	mock.console()
	eq(mock.selects[4].items[3], '(Dracula)')
	eq(mock.selects[4].default_item, 2)
end)

test('no uosc: an update while the video plays (no choice, same language) leaves the menu on screen', function()
	local menu = fresh(false, true)
	menu.open(sample())
	mock.console()
	for i = 1, 6 do
		menu.update(sample({title = 'Paletas ' .. i}))
		mock.advance(10)
		mock.console()
	end
	eq(mock.terminates, 0, 'never closed')
	eq(#mock.selects, 1, 'never opened again')
	assert(mock.on_screen == mock.selects[1], 'still on screen')
	eq(menu.is_open('hikari-test'), true)
	-- The newest data shows the next time the menu comes back.
	mock.choose(1)
	mock.advance(menu.REOPEN_DELAY)
	mock.console()
	eq(mock.selects[2].prompt, 'Paletas 6:')
end)

test('no uosc: a language switch with the menu on screen: closed and opened with the new data', function()
	local menu = fresh(false, true)
	menu.open(sample())
	mock.console()
	mock.set_script_opt('hikari-language', 'en')
	menu.update(sample({title = 'Palettes'}))
	eq(mock.terminates, 1)
	menu.update(sample({title = 'Farbpaletten'}))
	eq(mock.terminates, 1, 'one close is enough')
	mock.console()
	eq(mock.on_screen, nil, 'closed')
	mock.advance(menu.REOPEN_DELAY)
	mock.console()
	eq(#mock.selects, 2)
	eq(mock.selects[2].prompt, 'Farbpaletten:', 'the newest data')
	eq(menu.is_open('hikari-test'), true)
end)

test('no uosc: update-menu for a menu not open: nothing on screen', function()
	local menu = fresh(false, true)
	menu.update(sample())
	mock.console()
	eq(#mock.selects, 0)
	eq(mock.commands[1][3], 'update-menu', 'tried uosc, as before')
end)

test('no uosc: a language switch while the request is on its way: shown, then redone', function()
	local menu = fresh(false, true)
	menu.open(sample())
	mock.set_script_opt('hikari-language', 'en')
	menu.update(sample({title = 'Palettes'}))
	eq(#mock.selects, 1, 'one request at a time')
	mock.console()
	eq(mock.terminates, 1, 'out of date once opened')
	mock.console()
	mock.advance(menu.REOPEN_DELAY)
	mock.console()
	eq(mock.selects[2].prompt, 'Palettes:')
	assert(mock.on_screen == mock.selects[2])
end)

test('no uosc: close-menu closes it; Esc too, without running anything', function()
	local menu = fresh(false, true)
	local seen = {}
	menu.observe(function(value) seen[#seen + 1] = tostring(value) end)
	menu.open(sample())
	mock.console()
	menu.close('hikari-other')
	eq(mock.terminates, 0, 'another type: not ours')
	menu.close('hikari-test')
	eq(mock.terminates, 1)
	eq(menu.is_open('hikari-test'), false)
	mock.console()
	mock.advance(1)
	mock.console()
	eq(#mock.selects, 1, 'not opened again')
	menu.open(sample())
	mock.console()
	mock.escape()
	eq(#ran(), 0)
	eq(menu.is_open('hikari-test'), false)
	mock.advance(1)
	mock.console()
	eq(mock.on_screen, nil, 'stays closed')
	eq(table.concat(seen, ','), 'hikari-test,nil,hikari-test,nil')
end)

test('no uosc: close-menu before the console opened it: closed as soon as it opens', function()
	local menu = fresh(false, true)
	menu.open(sample())
	menu.close('hikari-test')
	mock.console()
	eq(mock.terminates, 1)
	mock.console()
	eq(mock.on_screen, nil)
end)

test('no uosc: another menu of the script replaces the one on screen', function()
	local menu = fresh(false, true)
	local seen = {}
	menu.observe(function(value) seen[#seen + 1] = tostring(value) end)
	menu.open(sample())
	mock.console()
	menu.open(sample({type = 'hikari-other', title = 'Otro'}))
	eq(menu.is_open('hikari-test'), false)
	eq(menu.is_open('hikari-other'), true)
	mock.console()
	mock.advance(menu.REOPEN_DELAY)
	mock.console()
	eq(mock.on_screen.prompt, 'Otro:')
	eq(table.concat(seen, ','), 'hikari-test,hikari-other')
end)

test('no uosc: a console that never opens the menu (0.39 busy): given up, the next one opens', function()
	local menu = fresh(false, true)
	local seen = {}
	menu.observe(function(value) seen[#seen + 1] = tostring(value) end)
	-- Someone else's input is on screen: the console ignores our request.
	mock.on_screen = {}
	menu.open(sample())
	mock.console()
	mock.advance(menu.OPEN_TIMEOUT)
	eq(menu.is_open('hikari-test'), false)
	assert(mock.logs.warn[1]:find('did not open', 1, true), 'warned')
	eq(table.concat(seen, ','), 'hikari-test,nil')
	mock.on_screen = nil
	menu.open(sample())
	mock.console()
	assert(mock.on_screen == mock.selects[2], 'opens now')
end)

test('no uosc and no mp.input (mpv before 0.39): a translated message, a warning, no error', function()
	local menu = fresh(false, false)
	eq(menu.open(sample()), false)
	eq(mock.osd[1], 'Este menú necesita uosc o mpv 0.39 o posterior')
	assert(mock.logs.warn[1]:find('uosc is not loaded', 1, true), 'warned')
	eq(menu.is_open('hikari-test'), false)
	menu.update(sample())
	menu.close('hikari-test')
	eq(#mock.logs.error, 0)
	eq(menu.open(sample(), {silent = true}), false)
	eq(#mock.osd, 1, 'silent: no message')
	menu = fresh(false, false)
	mock.set_script_opt('hikari-language', 'en')
	menu.open(sample())
	eq(mock.osd[1], 'This menu needs uosc or mpv 0.39 or later')
end)

-- With suji ---------------------------------------------------------------------

local SUJI_TYPE_PROP = 'user-data/suji/menu/type'
local SUJI_ENABLED = 'user-data/suji/enabled'

-- A fresh module with a script called suji loaded; `enabled` is what suji
-- publishes in user-data/suji/enabled (true while it is turned on).
local function fresh_suji(enabled, uosc, input)
	local menu = fresh(uosc, input)
	mock.suji = true
	mock.props[SUJI_ENABLED] = enabled
	return menu
end

-- The messages sent to `target`.
local function sent_to(target)
	local out = {}
	for _, c in ipairs(mock.commands) do
		if c[1] == 'script-message-to' and c[2] == target then out[#out + 1] = c end
	end
	return out
end

test('only suji, turned on: open, update and close go to suji, with the JSON uosc gets', function()
	local menu = fresh_suji(true, false, true)
	local data = sample()
	eq(menu.open(data), true, 'opened')
	eq(#mock.commands, 1, 'one message')
	local c = mock.commands[1]
	eq(c[1], 'script-message-to'); eq(c[2], 'suji'); eq(c[3], 'open-menu')
	eq(c[4], mock.format_json(data), 'the same JSON')
	eq(#c, 4)
	menu.update(data)
	eq(table.concat(mock.commands[2], ' ', 1, 3), 'script-message-to suji update-menu')
	eq(mock.commands[2][4], mock.format_json(data))
	menu.close('hikari-test')
	eq(table.concat(mock.commands[3], ' '), 'script-message-to suji close-menu hikari-test')
	eq(#sent_to('uosc'), 0, 'nothing for uosc')
	eq(#mock.selects, 0, 'no selector')
	eq(#mock.osd, 0)
end)

test('the note is for the selector only: suji gets the same JSON without it', function()
	local menu = fresh_suji(true, false, true)
	local data = sample()
	menu.open(data, {note = 'Las paletas cambian los colores de uosc'})
	eq(mock.commands[1][4], mock.format_json(data))
	assert(not mock.commands[1][4]:find('Las paletas', 1, true), 'no note in the JSON')
end)

test('suji loaded but not turned on: not even asked; uosc, else the selector', function()
	for _, enabled in ipairs({false, 'yes', 1}) do
		local menu = fresh_suji(enabled, true, true)
		menu.open(sample())
		eq(#sent_to('suji'), 0, 'nothing for suji with enabled = ' .. tostring(enabled))
		eq(mock.commands[1][2], 'uosc')
		eq(mock.commands[1][3], 'open-menu')
		menu = fresh_suji(enabled, false, true)
		menu.open(sample())
		eq(#sent_to('suji'), 0)
		eq(#mock.selects, 1, 'the selector')
	end
	-- Not published at all (suji gone, or never there).
	local menu = fresh(true, true)
	mock.suji = true
	menu.open(sample())
	eq(#sent_to('suji'), 0)
end)

test('suji turned on but its message fails (it died without its shutdown): uosc, else the selector', function()
	local menu = fresh(true, true)
	mock.props[SUJI_ENABLED] = true
	eq(menu.open(sample()), true)
	eq(#mock.commands, 2, 'tried suji, then uosc')
	eq(mock.commands[1][2], 'suji')
	eq(mock.commands[2][2], 'uosc'); eq(mock.commands[2][3], 'open-menu')
	menu.update(sample())
	menu.close('hikari-test')
	eq(mock.commands[3][2], 'uosc'); eq(mock.commands[3][3], 'update-menu')
	eq(mock.commands[4][2], 'uosc'); eq(mock.commands[4][3], 'close-menu')
	menu = fresh(false, true)
	mock.props[SUJI_ENABLED] = true
	eq(menu.open(sample()), true)
	eq(#mock.selects, 1, 'the selector')
	-- And without mp.input either: the usual message.
	menu = fresh(false, false)
	mock.props[SUJI_ENABLED] = true
	eq(menu.open(sample()), false)
	eq(mock.osd[1], 'Este menú necesita uosc o mpv 0.39 o posterior')
end)

test('user-data/suji/enabled nil while the script loads, true from the first file-loaded: read at each open', function()
	-- hikari's scripts load before suji, which sets the property at the end of its start-up.
	local menu = fresh(true, true)
	mock.suji = true
	eq(menu.suji(), false, 'not yet')
	mock.props[SUJI_ENABLED] = true
	eq(menu.suji(), true)
	menu.open(sample())
	eq(#mock.commands, 1)
	eq(mock.commands[1][2], 'suji', 'the open after start-up goes to suji')
	-- Turned off later (enabled=no), and on again.
	mock.props[SUJI_ENABLED] = false
	menu.open(sample({type = 'hikari-other'}))
	eq(mock.commands[2][2], 'uosc')
	mock.props[SUJI_ENABLED] = true
	menu.open(sample({type = 'hikari-other'}))
	eq(mock.commands[3][2], 'suji')
end)

test('suji and uosc both loaded: suji wins', function()
	local menu = fresh_suji(true, true, true)
	menu.open(sample())
	eq(#mock.commands, 1)
	eq(mock.commands[1][2], 'suji')
	eq(#sent_to('uosc'), 0)
end)

test('neither suji nor uosc: the selector', function()
	local menu = fresh(false, true)
	eq(menu.open(sample()), true)
	mock.console()
	assert(mock.on_screen == mock.selects[1], 'on screen')
	eq(#sent_to('suji'), 0)
end)

test('update and close go where the menu was opened, per type', function()
	local menu = fresh_suji(true, true, true)
	menu.open(sample())
	-- suji turned off: the next menu goes to uosc; the first stays suji's.
	mock.props[SUJI_ENABLED] = false
	menu.open(sample({type = 'hikari-other'}))
	mock.commands = {}
	menu.update(sample())
	menu.update(sample({type = 'hikari-other'}))
	menu.close('hikari-test')
	menu.close('hikari-other')
	local got = {}
	for _, c in ipairs(mock.commands) do got[#got + 1] = c[2] .. ' ' .. c[3] end
	eq(table.concat(got, ','), 'suji update-menu,uosc update-menu,suji close-menu,uosc close-menu')
	-- Opened again, now in uosc: from then on uosc.
	menu.open(sample())
	mock.commands = {}
	menu.update(sample())
	eq(mock.commands[1][2], 'uosc')
end)

test('update and close of a type never opened here: uosc, as before', function()
	local menu = fresh_suji(true, true, true)
	menu.update(sample())
	menu.close('hikari-test')
	eq(#sent_to('suji'), 0)
	eq(mock.commands[1][2], 'uosc'); eq(mock.commands[1][3], 'update-menu')
	eq(mock.commands[2][2], 'uosc'); eq(mock.commands[2][3], 'close-menu')
end)

test('a menu opened in the selector, then suji comes: its update goes to uosc, as before', function()
	local menu = fresh(false, true)
	menu.open(sample())
	mock.console()
	mock.escape()
	mock.suji = true
	mock.props[SUJI_ENABLED] = true
	mock.commands = {}
	menu.update(sample())
	eq(mock.commands[1][2], 'uosc', 'not opened in suji')
end)

test('is_open and observe follow user-data/suji/menu/type too', function()
	local menu = fresh_suji(true, false, true)
	local seen = {}
	menu.observe(function(value) seen[#seen + 1] = tostring(value) end)
	menu.observe(function(value) seen[#seen + 1] = 'second ' .. tostring(value) end)
	eq(#mock.observers[SUJI_TYPE_PROP], 1, 'one observer for both')
	eq(#mock.observers[TYPE_PROP], 1)
	eq(menu.is_open('hikari-test'), false)
	mock.set(SUJI_TYPE_PROP, 'hikari-test')
	eq(menu.is_open('hikari-test'), true)
	eq(menu.is_open('hikari-other'), false)
	mock.set(SUJI_TYPE_PROP, 'hikari-other')
	eq(menu.is_open('hikari-test'), false)
	eq(menu.is_open('hikari-other'), true)
	mock.set(SUJI_TYPE_PROP, nil)
	eq(menu.is_open('hikari-other'), false)
	eq(table.concat(seen, ','),
		'hikari-test,second hikari-test,hikari-other,second hikari-other,nil,second nil')
end)

test('observe: one closes while the other still has a menu: the other type, then nil', function()
	local menu = fresh_suji(true, true, true)
	local seen = {}
	menu.observe(function(value) seen[#seen + 1] = tostring(value) end)
	mock.set(TYPE_PROP, 'hikari-a')
	mock.set(SUJI_TYPE_PROP, 'hikari-b')
	mock.set(SUJI_TYPE_PROP, nil)
	mock.set(TYPE_PROP, nil)
	eq(table.concat(seen, ','), 'hikari-a,hikari-b,hikari-a,nil')
	seen = {}
	mock.set(SUJI_TYPE_PROP, 'hikari-b')
	mock.set(TYPE_PROP, 'hikari-a')
	mock.set(TYPE_PROP, nil)
	mock.set(SUJI_TYPE_PROP, nil)
	eq(table.concat(seen, ','), 'hikari-b,hikari-a,hikari-b,nil')
end)

test('suji(): user-data/suji/enabled is true, now', function()
	local menu = fresh(true)
	eq(menu.suji(), false, 'nothing published')
	mock.props[SUJI_ENABLED] = true
	eq(menu.suji(), true)
	mock.props[SUJI_ENABLED] = false
	eq(menu.suji(), false, 'turned off')
	mock.props[SUJI_ENABLED] = 'yes'
	eq(menu.suji(), false, 'only true counts')
	eq(#mock.commands, 0, 'no probe')
	eq(menu.uosc(), true, 'uosc() still means uosc')
	-- suji alone: uosc() stays false.
	menu = fresh_suji(true, false)
	menu.open(sample())
	eq(menu.uosc(), false, 'a menu in suji is not uosc')
end)

-- Every script -----------------------------------------------------------------

local SCRIPTS = {
	{'hikari-language', 'hikari_language', 'HIKARI_LANGUAGE_TEST'},
	{'hikari-media-language', 'hikari_media_language', 'HIKARI_MEDIA_LANGUAGE_TEST'},
	{'hikari-palettes', 'hikari_palettes', 'HIKARI_PALETTES_TEST'},
	{'hikari-resume', 'hikari_resume', 'HIKARI_RESUME_TEST'},
	{'hikari-skip', 'hikari_skip', 'HIKARI_SKIP_TEST'},
	{'hikari-speed', 'hikari_speed', 'HIKARI_SPEED_TEST'},
	{'hikari-subs', 'hikari_subs', 'HIKARI_SUBS_TEST'},
	{'hikari-title', 'hikari_title', 'HIKARI_TITLE_TEST'},
	{'hikari-update', 'hikari_update', 'HIKARI_UPDATE_TEST'},
	{'hikari-upscale', 'hikari_upscale', 'HIKARI_UPSCALE_TEST'},
}

test('every script starts without uosc (and without mp.input): no error, nothing sent to uosc but the probe', function()
	local resume_list = os.tmpname()
	for _, s in ipairs(SCRIPTS) do
		mock.install(s[2])
		mock.uosc = false
		mock.script_opts = {['hikari-language'] = 'es'}
		mock.expand['~~/hikari-resume.json'] = resume_list
		mock.config_files['script-opts/uosc.conf'] = 'portable_config/script-opts/uosc.conf'
		_G[s[3]] = true
		local ok, err = pcall(function() return assert(loadfile('portable_config/scripts/' .. s[1] .. '.lua'))() end)
		assert(ok, s[1] .. ': ' .. tostring(err))
		eq(#mock.logs.error, 0, s[1] .. ' errors')
		for _, c in ipairs(mock.commands) do
			if c[2] == 'uosc' then eq(c[3], 'hikari-probe', s[1] .. ' sent ' .. tostring(c[3])) end
			assert(not (c[1] == 'change-list' and tostring(c[4]):find('^uosc%-controls=')), s[1] .. ' set uosc-controls')
		end
		eq(#mock.osd, 0, s[1] .. ' OSD')
	end
	os.remove(resume_list)
end)

test('only suji, turned on: the eight menus go to suji with the JSON uosc gets (palettes: one line more)', function()
	local eight = {
		{'hikari-language', 'hikari_language'}, {'hikari-palettes', 'hikari_palettes'},
		{'hikari-resume', 'hikari_resume'}, {'hikari-skip', 'hikari_skip'}, {'hikari-speed', 'hikari_speed'},
		{'hikari-subs', 'hikari_subs'}, {'hikari-update', 'hikari_update'}, {'hikari-upscale', 'hikari_upscale'},
	}
	-- Opens the script's menu with uosc only, or suji only, and gives back
	-- where the open-menu went and its JSON.
	local function opened(s, suji)
		local resume_list, record, state = os.tmpname(), os.tmpname(), os.tmpname()
		os.remove(state)
		local f = assert(io.open(record, 'wb'))
		f:write('hikari_version=0.2.1\n')
		f:close()
		mock.install(s[2])
		mock.uosc, mock.suji = not suji, suji
		if suji then mock.props[SUJI_ENABLED] = true end
		mock.script_opts = {['hikari-language'] = 'es'}
		mock.expand['~~/hikari-resume.json'] = resume_list
		mock.expand['~~/hikari-installed.txt'] = record
		mock.expand['~~/hikari-update.txt'] = state
		mock.config_files['script-opts/uosc.conf'] = 'portable_config/script-opts/uosc.conf'
		assert(loadfile('portable_config/scripts/' .. s[1] .. '.lua'))()
		if s[1] == 'hikari-update' then
			-- A newer version known, so Alt+u has a menu to open.
			mock.events['file-loaded']()
			mock.finish_async(true, {status = 0, error_string = '',
				stdout = 'HTTP/2 302\r\nlocation: https://github.com/SCEPTICG/hikari-mpv/releases/tag/v0.3.1\r\n\r\n'})
		end
		mock.commands = {}
		mock.bindings['open-menu']()
		os.remove(resume_list); os.remove(record); os.remove(state); os.remove(state .. '.tmp')
		eq(#mock.commands, 1, s[1] .. ': one message')
		local c = mock.commands[1]
		eq(c[1] .. ' ' .. c[3], 'script-message-to open-menu', s[1])
		return c[2], c[4]
	end
	for _, s in ipairs(eight) do
		local to_uosc, json_uosc = opened(s, false)
		local to_suji, json_suji = opened(s, true)
		eq(to_uosc, 'uosc', s[1])
		eq(to_suji, 'suji', s[1])
		if s[1] == 'hikari-palettes' then
			local data_uosc, data_suji = mock.parse_json(json_uosc), mock.parse_json(json_suji)
			local first = table.remove(data_suji.items, 1)
			eq(first.title, 'Con suji, la paleta cambia el color de acento', 'palettes: the line about the accent')
			eq(first.selectable, false); eq(first.muted, true); eq(first.value, nil)
			eq(mock.format_json(data_suji), mock.format_json(data_uosc), 'palettes: the rest as for uosc')
		else
			eq(json_suji, json_uosc, s[1] .. ': the same JSON')
		end
	end
end)

test('the eight menu scripts load the module; nobody else talks to uosc directly', function()
	local with_menu = {
		['hikari-language'] = true, ['hikari-palettes'] = true, ['hikari-resume'] = true, ['hikari-skip'] = true,
		['hikari-speed'] = true, ['hikari-subs'] = true, ['hikari-update'] = true, ['hikari-upscale'] = true,
	}
	for _, s in ipairs(SCRIPTS) do
		local src = read('portable_config/scripts/' .. s[1] .. '.lua')
		eq(src:find("'hikari-menu'", 1, true) ~= nil, with_menu[s[1]] == true, s[1] .. ' loads hikari-menu')
		assert(not src:find("'script-message-to', 'uosc'", 1, true), s[1] .. ' sends to uosc itself')
		assert(not src:find("get_property_native('user-data/uosc/menu/type')", 1, true), s[1] .. ' reads the menu type itself')
	end
end)

test('no uosc: only command lists run; any other value is ignored with a warning', function()
	local menu = fresh(false, true)
	menu.open({type = 'hikari-test', title = 'T', items = {
		{title = 'text', value = 'quit'}, {title = 'number', value = 7}, {title = 'list', value = command('ok')},
	}})
	for line = 1, 2 do
		mock.console()
		mock.commands = {}
		mock.choose(line)
		eq(#mock.commands, 0, 'nothing run for line ' .. line)
		mock.advance(1)
		menu.open({type = 'hikari-test', title = 'T', items = {
			{title = 'text', value = 'quit'}, {title = 'number', value = 7}, {title = 'list', value = command('ok')},
		}})
	end
	eq(#mock.logs.warn, 2, 'one warning each')
	mock.console()
	mock.commands = {}
	mock.choose(3)
	eq(table.concat(ran(), ';'), 'script-message-to hikari_test ok')
	local src = read(MODULE)
	assert(not src:find('mp.command(', 1, true), 'no mp.command with a string')
end)

test('the module avoids os.execute, io.popen, load* and file access', function()
	local src = read(MODULE)
	for _, bad in ipairs({'os.execute', 'io.popen', 'io.open', 'loadstring', 'loadfile', 'dofile', 'load('}) do
		assert(not src:find(bad, 1, true), bad)
	end
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
