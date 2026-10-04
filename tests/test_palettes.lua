-- Run from the repository root: lua tests/test_palettes.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/sosc-palettes.lua'
local SCRIPT_NAME = 'sosc_palettes'

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

-- Loads the script with fresh mocks; `opts` are the script-opts mpv would pass.
local function load(opts)
	mock.install(SCRIPT_NAME)
	mock.script_opts = opts or {}
	SOSC_PALETTES_TEST = true
	local chunk = assert(loadfile(SCRIPT))
	return chunk()
end

local function tmp_path()
	local path = os.tmpname()
	os.remove(path)
	return path
end

local EXPECTED_ORDER = {
	'uosc', 'catppuccin_mocha', 'tokyo_night', 'dracula', 'nord', 'gruvbox_dark', 'rose_pine',
	'kanagawa_wave', 'one_dark', 'everforest_dark', 'catppuccin_latte', 'gruvbox_light',
	'solarized_light', 'sceptic',
}

-- WCAG relative luminance and contrast ratio, to sanity check text colours.
local function luminance(hex)
	local function channel(i)
		local c = tonumber(hex:sub(i, i + 1), 16) / 255
		return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5)
end
local function contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

test('the 14 palettes exist in the expected order', function()
	local p = load()
	eq(#p.PALETTES, #EXPECTED_ORDER, 'palette count')
	for i, id in ipairs(EXPECTED_ORDER) do eq(p.PALETTES[i].id, id, 'palette #' .. i) end
	eq(p.PALETTES[1].group, 'dark', 'uosc group')
	eq(p.PALETTES[11].group, 'light', 'latte group')
	eq(p.PALETTES[14].group, 'custom', 'sceptic group')
end)

test('every palette has the 10 keys as 6-digit hex and a valid id', function()
	local p = load()
	eq(#p.COLOR_KEYS, 10, 'key count')
	for _, palette in ipairs(p.PALETTES) do
		assert(p.is_valid_id(palette.id), 'bad id ' .. tostring(palette.id))
		assert(type(palette.name) == 'string' and #palette.name > 0, 'missing name in ' .. palette.id)
		for _, key in ipairs(p.COLOR_KEYS) do
			assert(tostring(palette[key]):match('^%x%x%x%x%x%x$'), palette.id .. '.' .. key .. ' = ' .. tostring(palette[key]))
		end
	end
end)

test('uosc palette matches uosc defaults', function()
	local p = load()
	eq(p.color_string(p.get_palette('uosc')),
		'foreground=ffffff,foreground_text=000000,background=000000,background_text=ffffff,curtain=111111,'
		.. 'success=a5e075,error=ff616e,match=69c5ff,heatmap=00adee,window_border=000000', 'uosc colors')
end)

test('text colours are readable on their backgrounds (all palettes, SCEPTIC included)', function()
	local p = load()
	for _, palette in ipairs(p.PALETTES) do
		local fg = contrast(palette.foreground, palette.foreground_text)
		local bg = contrast(palette.background, palette.background_text)
		assert(fg >= 3, string.format('%s foreground contrast %.2f', palette.id, fg))
		assert(bg >= 4.5, string.format('%s background contrast %.2f', palette.id, bg))
	end
end)

test('colour string has the key=value,key=value format uosc expects', function()
	local p = load()
	for _, palette in ipairs(p.PALETTES) do
		local s = p.color_string(palette)
		local i = 0
		for pair in (s .. ','):gmatch('([^,]*),') do
			i = i + 1
			local key, value = pair:match('^([a-z_]+)=(%x%x%x%x%x%x)$')
			eq(key, p.COLOR_KEYS[i], palette.id .. ' key #' .. i)
			eq(value, palette[key], palette.id .. ' ' .. key)
		end
		eq(i, 10, palette.id .. ' pair count')
	end
end)

test('invalid colours are rejected', function()
	local p = load()
	local bad = {id = 'bad'}
	for _, key in ipairs(p.COLOR_KEYS) do bad[key] = '000000' end
	bad.match = '#00000'
	eq(p.color_string(bad), nil, 'color string')
	eq(p.persist_content(bad), nil, 'persist content')
	assert(not p.is_valid_id('../evil'), 'path-like id accepted')
	assert(not p.is_valid_id('a\nb'), 'newline id accepted')
	assert(not p.is_valid_color('ffffff\n'), 'colour with newline accepted')
end)

test('applying a palette calls change-list with the right arguments', function()
	local p = load()
	mock.commands = {}
	assert(p.apply(p.get_palette('nord')))
	eq(#mock.commands, 2, 'command count')
	local c = mock.commands[1]
	eq(c[1], 'change-list'); eq(c[2], 'script-opts'); eq(c[3], 'append')
	eq(c[4], 'uosc-color=' .. p.color_string(p.get_palette('nord')), 'value')
	c = mock.commands[2]
	eq(c[1], 'change-list'); eq(c[2], 'script-opts'); eq(c[3], 'append')
	eq(c[4], 'uosc-opacity=', 'empty opacity for a palette without it')
	eq(p.get_active_id(), 'nord', 'active id')
end)

test('SCEPTIC applies its opacity, and switching away resets it', function()
	local p = load()
	mock.commands = {}
	assert(p.apply(p.get_palette('sceptic')))
	eq(#mock.commands, 2, 'command count')
	eq(mock.commands[2][1], 'change-list'); eq(mock.commands[2][2], 'script-opts'); eq(mock.commands[2][3], 'append')
	eq(mock.commands[2][4], 'uosc-opacity=timeline=0.60,menu=0.75,title=0.75,tooltip=0.75,curtain=0.50', 'opacity')
	mock.commands = {}
	assert(p.apply(p.get_palette('dracula')))
	eq(mock.commands[2][4], 'uosc-opacity=', 'reset after switching')
end)

test('opacity string follows uosc key order and its key=value syntax', function()
	local p = load()
	eq(p.opacity_string({id = 'x', opacity = {heatmap = 0.4, timeline = 1, controls = 0}}),
		'timeline=1.00,controls=0.00,heatmap=0.40', 'ordered')
	eq(p.opacity_string({id = 'x'}), '', 'no opacity')
	eq(p.opacity_string({id = 'x', opacity = {}}), '', 'empty table')
	for _, palette in ipairs(p.PALETTES) do
		local s = assert(p.opacity_string(palette), palette.id)
		if s ~= '' then
			for pair in (s .. ','):gmatch('([^,]*),') do
				-- Same pattern uosc's serialize_key_value_list uses, plus our stricter value check.
				local key, value = pair:match('^([%w_]+)=([%w%.]+)$')
				assert(key and value:match('^[01]%.%d%d$'), palette.id .. ' bad pair ' .. pair)
			end
		end
	end
end)

test('opacity values are formatted with a decimal point, two decimals, no exponent', function()
	local p = load()
	eq(p.format_opacity(0), '0.00'); eq(p.format_opacity(1), '1.00'); eq(p.format_opacity(0.6), '0.60')
	eq(p.format_opacity(0.755), '0.76'); eq(p.format_opacity(1e-9), '0.00'); eq(p.format_opacity(0.999), '1.00')
	-- Whatever the process locale, the separator must be a point.
	local saved = os.setlocale(nil, 'numeric')
	for _, loc in ipairs({'es_ES.UTF-8', 'de_DE.UTF-8', 'fr_FR.UTF-8'}) do
		if os.setlocale(loc, 'numeric') then eq(p.format_opacity(0.75), '0.75', 'under ' .. loc) end
	end
	os.setlocale(saved, 'numeric')
end)

test('invalid opacity keys and values are rejected', function()
	local p = load()
	local base = p.get_palette('uosc')
	local function with(opacity)
		local t = {}
		for k, v in pairs(base) do t[k] = v end
		t.id = 'bad'; t.opacity = opacity
		return t
	end
	local bad = {
		{menu = 1.5}, {menu = -0.1}, {menu = 0 / 0}, {menu = 1 / 0}, {menu = '0.5'}, {menu = true},
		{evil = 0.5}, {['menu=0,x'] = 0.5}, {[1] = 0.5}, {['MENU'] = 0.5}, 'menu=0.5',
	}
	for i, opacity in ipairs(bad) do
		local palette = with(opacity)
		eq(p.opacity_string(palette), nil, 'opacity string #' .. i)
		eq(p.persist_content(palette), nil, 'persist content #' .. i)
		mock.commands = {}
		eq(p.apply(palette), false, 'apply #' .. i)
		eq(#mock.commands, 0, 'commands #' .. i)
	end
	for _, v in ipairs({1.5, -0.1, 0 / 0, 1 / 0, -1 / 0, '1'}) do
		eq(p.format_opacity(v), nil, 'format ' .. tostring(v))
	end
end)

test('opacity whitelist matches uosc keys', function()
	local p = load()
	eq(#p.OPACITY_KEYS, 20, 'key count')
	local seen = {}
	for _, key in ipairs(p.OPACITY_KEYS) do
		assert(key:match('^[a-z_]+$'), key)
		assert(not seen[key], 'duplicate ' .. key)
		seen[key] = true
	end
end)

test('start-up applies the configured palette', function()
	local p = load({[SCRIPT_NAME .. '-palette'] = 'dracula'})
	eq(p.get_active_id(), 'dracula', 'active id')
	eq(mock.commands[1][4], 'uosc-color=' .. p.color_string(p.get_palette('dracula')), 'start-up value')
end)

test('unknown palette id falls back to the uosc original', function()
	local p = load({[SCRIPT_NAME .. '-palette'] = 'does_not_exist'})
	eq(p.get_active_id(), 'uosc', 'active id')
	eq(p.get_palette('nope').id, 'uosc', 'get_palette fallback')
	eq(mock.commands[1][4], 'uosc-color=' .. p.color_string(p.get_palette('uosc')), 'start-up value')
	eq(#mock.logs.warn, 1, 'warning count')
end)

test('persisted file content is correct', function()
	local p = load()
	eq(p.persist_content(p.get_palette('gruvbox_light')),
		'# Generated by sosc-palettes.lua. Palette: gruvbox_light\n'
		.. 'script-opts-append=uosc-color=' .. p.color_string(p.get_palette('gruvbox_light')) .. '\n'
		.. 'script-opts-append=uosc-opacity=\n'
		.. 'script-opts-append=sosc_palettes-palette=gruvbox_light\n', 'content')
	eq(p.persist_content(p.get_palette('sceptic')),
		'# Generated by sosc-palettes.lua. Palette: sceptic\n'
		.. 'script-opts-append=uosc-color=' .. p.color_string(p.get_palette('sceptic')) .. '\n'
		.. 'script-opts-append=uosc-opacity=timeline=0.60,menu=0.75,title=0.75,tooltip=0.75,curtain=0.50\n'
		.. 'script-opts-append=sosc_palettes-palette=sceptic\n', 'sceptic content')
end)

test('atomic write creates and then replaces the file', function()
	local p = load()
	local path = tmp_path()
	assert(p.write_file_atomic(path, 'one\n'))
	assert(p.write_file_atomic(path, 'two\n'))
	local f = assert(io.open(path, 'rb')); local content = f:read('*a'); f:close()
	eq(content, 'two\n', 'content')
	eq(io.open(path .. '.tmp', 'rb'), nil, 'leftover temp file')
	os.remove(path)
end)

test('selecting from the menu applies and saves the palette', function()
	local p = load()
	local path = tmp_path()
	mock.expand['~~/sosc-palette.conf'] = path
	mock.commands = {}
	mock.messages['select-palette']('tokyo_night')
	eq(mock.commands[1][4], 'uosc-color=' .. p.color_string(p.get_palette('tokyo_night')), 'applied')
	eq(mock.commands[2][4], 'uosc-opacity=', 'opacity applied')
	local f = assert(io.open(path, 'rb')); local content = f:read('*a'); f:close()
	eq(content, p.persist_content(p.get_palette('tokyo_night')), 'saved')
	eq(#mock.osd, 0, 'osd messages')
	os.remove(path)
end)

test('unknown id from a message is ignored', function()
	local p = load()
	mock.commands = {}
	mock.messages['select-palette']('x\nscript-opts-append=evil')
	eq(#mock.commands, 0, 'commands')
	eq(p.get_active_id(), 'uosc', 'active id')
end)

test('a failed save still applies the palette and warns', function()
	local p = load()
	mock.expand['~~/sosc-palette.conf'] = '/nonexistent-dir/sosc-palette.conf'
	mock.commands = {}
	mock.messages['select-palette']('nord')
	eq(mock.commands[1][4], 'uosc-color=' .. p.color_string(p.get_palette('nord')), 'applied')
	eq(p.get_active_id(), 'nord', 'active id')
	eq(#mock.logs.warn, 1, 'warnings')
	eq(#mock.osd, 1, 'osd messages')
end)

test('menu marks the active palette and sends JSON to uosc', function()
	local p = load({[SCRIPT_NAME .. '-palette'] = 'nord'})
	local data = p.menu_data()
	local active, selectable = {}, 0
	for _, item in ipairs(data.items) do
		if item.active then active[#active + 1] = item.title end
		if item.value then
			selectable = selectable + 1
			eq(item.value[1], 'script-message-to'); eq(item.value[2], SCRIPT_NAME); eq(item.value[3], 'select-palette')
		end
	end
	eq(selectable, 14, 'selectable items')
	eq(#active, 1, 'active count')
	eq(active[1], 'Nord', 'active title')
	eq(#data.items, 14 + 3, 'items incl. 3 group headers')
	eq(data.items[1].selectable, false, 'header not selectable')
	eq(data.items[11].separator, true, 'separator before light group')

	mock.commands = {}
	mock.bindings['open-menu']()
	local c = mock.commands[1]
	eq(c[1], 'script-message-to'); eq(c[2], 'uosc'); eq(c[3], 'open-menu')
	eq(c[4], mock.format_json(data), 'json payload')
	assert(c[4]:find('"active":true,"hint":"activa","title":"Nord"', 1, true), 'active item in JSON')
end)

test('shipped sosc-palette.conf matches what the script would write', function()
	local p = load()
	local f = assert(io.open('portable_config/sosc-palette.conf', 'rb')); local content = f:read('*a'); f:close()
	eq(content, p.persist_content(p.get_palette('uosc')), 'default file')
	assert(content:find('\nscript-opts-append=uosc-opacity=\n', 1, true), 'default file resets opacity')
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
