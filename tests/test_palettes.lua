-- Run from the repository root: lua tests/test_palettes.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/hikari-palettes.lua'
local SCRIPT_NAME = 'hikari_palettes'

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
	-- The assertions below are in Spanish: unless a test says otherwise, hikari speaks Spanish.
	if mock.script_opts['hikari-language'] == nil then mock.script_opts['hikari-language'] = 'es' end
	HIKARI_PALETTES_TEST = true
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
	'solarized_light', 'cel', 'city_pop', 'phosphor', 'cel_light', 'sceptic',
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

test('the 18 palettes exist in the expected order', function()
	local p = load()
	eq(#p.PALETTES, #EXPECTED_ORDER, 'palette count')
	for i, id in ipairs(EXPECTED_ORDER) do eq(p.PALETTES[i].id, id, 'palette #' .. i) end
	eq(p.PALETTES[1].group, 'dark', 'uosc group')
	eq(p.PALETTES[11].group, 'light', 'latte group')
	for i = 14, 17 do eq(p.PALETTES[i].group, 'retro', p.PALETTES[i].id .. ' group') end
	eq(p.PALETTES[18].group, 'custom', 'sceptic group')
end)

test('the retro palettes have the agreed colours, no opacity, and Cel Light a translated name', function()
	local p = load()
	eq(p.color_string(p.get_palette('cel')),
		'foreground=e8643a,foreground_text=1f1a16,background=1f1a16,background_text=efe4cc,curtain=120e0b,'
		.. 'success=8fae5a,error=d8434f,match=6fa8b8,heatmap=e8b04a,window_border=120e0b', 'cel')
	eq(p.color_string(p.get_palette('city_pop')),
		'foreground=ff7eb3,foreground_text=1d1a3a,background=1d1a3a,background_text=f7eaf3,curtain=120f27,'
		.. 'success=7de3c6,error=ff5d5d,match=72d4ff,heatmap=ffb36b,window_border=120f27', 'city pop')
	eq(p.color_string(p.get_palette('phosphor')),
		'foreground=ffb000,foreground_text=0f1412,background=0f1412,background_text=d9e6d3,curtain=080b0a,'
		.. 'success=4fd96b,error=ff5a48,match=5ad1d6,heatmap=d27be0,window_border=080b0a', 'phosphor')
	eq(p.color_string(p.get_palette('cel_light')),
		'foreground=c24a2c,foreground_text=f2e8d3,background=f2e8d3,background_text=2e2620,curtain=e2d5ba,'
		.. 'success=5d7f2e,error=a3243a,match=2f6e88,heatmap=b86f12,window_border=e2d5ba', 'cel light')
	for _, id in ipairs({'cel', 'city_pop', 'phosphor', 'cel_light'}) do
		eq(p.get_palette(id).opacity, nil, id .. ' opacity')
	end
	eq(p.get_palette('cel').name, 'Cel'); eq(p.get_palette('city_pop').name, 'City Pop')
	eq(p.get_palette('phosphor').name, 'Phosphor')
	eq(p.get_palette('cel_light').name_key, 'palette_cel_light')
	local titles = {}
	for _, item in ipairs(p.menu_data().items) do titles[#titles + 1] = item.title end
	local list = table.concat(titles, '|')
	assert(list:find('|Retro|Cel|City Pop|Phosphor|Cel claro|Propia|SCEPTIC|', 1, true), list)
end)

test('every palette has the 10 keys as 6-digit hex and a valid id', function()
	local p = load()
	eq(#p.COLOR_KEYS, 10, 'key count')
	for _, palette in ipairs(p.PALETTES) do
		assert(p.is_valid_id(palette.id), 'bad id ' .. tostring(palette.id))
		-- A name, or the key of a translated one (hikari-i18n) with an English text.
		local named = type(palette.name) == 'string' and #palette.name > 0
		local strings = dofile('portable_config/script-modules/hikari-i18n.lua').STRINGS
		local keyed = palette.name_key ~= nil and strings[palette.name_key] ~= nil and strings[palette.name_key].en ~= nil
		assert(named ~= keyed, 'one name (or name key) in ' .. palette.id)
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
	eq(mock.commands[2][4], 'uosc-opacity=timeline=0.60,position=0.50,menu=0.75,title=0.75,tooltip=0.75,curtain=0.50', 'opacity')
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
		'# Generated by hikari-palettes.lua. Palette: gruvbox_light\n'
		.. 'script-opts-append=uosc-color=' .. p.color_string(p.get_palette('gruvbox_light')) .. '\n'
		.. 'script-opts-append=uosc-opacity=\n'
		.. 'script-opts-append=suji-accent=af3a03\n'
		.. 'script-opts-append=hikari_palettes-palette=gruvbox_light\n'
		.. 'script-opts-append=hikari_palettes-bars=black\n', 'content')
	eq(p.persist_content(p.get_palette('sceptic')),
		'# Generated by hikari-palettes.lua. Palette: sceptic\n'
		.. 'script-opts-append=uosc-color=' .. p.color_string(p.get_palette('sceptic')) .. '\n'
		.. 'script-opts-append=uosc-opacity=timeline=0.60,position=0.50,menu=0.75,title=0.75,tooltip=0.75,curtain=0.50\n'
		.. 'script-opts-append=suji-accent=5ad4e6\n'
		.. 'script-opts-append=hikari_palettes-palette=sceptic\n'
		.. 'script-opts-append=hikari_palettes-bars=black\n', 'sceptic content')
	-- The side bar style goes last; an unknown one saves nothing.
	local content = p.persist_content(p.get_palette('cel'), 'stripes')
	local tail = '\nscript-opts-append=hikari_palettes-palette=cel\nscript-opts-append=hikari_palettes-bars=stripes\n'
	eq(content:sub(-#tail), tail, 'bars last')
	eq(p.persist_content(p.get_palette('cel'), 'evil\nscript-opts-append=x'), nil, 'bad bars')
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
	mock.expand['~~/hikari-palette.conf'] = path
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
	mock.expand['~~/hikari-palette.conf'] = '/nonexistent-dir/hikari-palette.conf'
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
	for i, item in ipairs(data.items) do
		if item.active then active[#active + 1] = item.title end
		if item.value then
			selectable = selectable + 1
			eq(item.value[1], 'script-message-to'); eq(item.value[2], SCRIPT_NAME)
			eq(item.value[3], i <= 22 and 'select-palette' or 'select-bars', 'message of item #' .. i)
		end
	end
	eq(selectable, 18 + 3, 'selectable items: palettes and side bar styles')
	eq(#active, 2, 'active count')
	eq(active[1], 'Nord', 'active title')
	eq(active[2], 'Negras', 'active side bars')
	eq(#data.items, 18 + 4 + 1 + 3, 'items incl. 4 palette group headers and the side bar one')
	eq(data.items[1].selectable, false, 'header not selectable')
	eq(data.items[11].separator, true, 'separator before light group')
	eq(data.items[22].separator, true, 'separator after SCEPTIC')
	eq(data.items[23].title, 'Barras laterales (4:3)'); eq(data.items[23].selectable, false)
	eq(data.items[24].hint, 'activa', 'Black marked')
	eq(table.concat(data.items[26].value, ' '), 'script-message-to hikari_palettes select-bars stripes')

	mock.commands = {}
	mock.bindings['open-menu']()
	local c = mock.commands[1]
	eq(c[1], 'script-message-to'); eq(c[2], 'uosc'); eq(c[3], 'open-menu')
	eq(c[4], mock.format_json(data), 'json payload')
	assert(c[4]:find('"active":true,"hint":"activa","title":"Nord"', 1, true), 'active item in JSON')
end)

test('shipped hikari-palette.conf matches what the script would write', function()
	local p = load()
	local f = assert(io.open('portable_config/hikari-palette.conf', 'rb')); local content = f:read('*a'); f:close()
	eq(content, p.persist_content(p.get_palette('uosc')), 'default file')
	assert(content:find('\nscript-opts-append=uosc-opacity=\n', 1, true), 'default file resets opacity')
end)

test('a language switch redraws an open palette menu; names with a word follow', function()
	local p = load()
	local light = p.menu_data().items
	local found = false
	for _, item in ipairs(light) do if item.title == 'Gruvbox claro' then found = true end end
	assert(found, 'Spanish name')
	mock.props['user-data/uosc/menu/type'] = 'hikari-palettes'
	local count = #mock.commands
	mock.set_script_opt('hikari-language', 'en')
	eq(#mock.commands, count + 1, 'one message')
	local last = mock.commands[#mock.commands]
	eq(last[3], 'update-menu')
	assert(last[4]:find('"title":"Palettes"', 1, true) and last[4]:find('Gruvbox Light', 1, true)
		and last[4]:find('Catppuccin Mocha', 1, true), 'English, proper names kept')
	mock.props['user-data/uosc/menu/type'] = nil
	mock.set_script_opt('hikari-language', 'de')
	eq(#mock.commands, count + 1, 'menu closed: nothing')
end)

-- Without uosc -------------------------------------------------------------------

test('without uosc: mpv\'s selector says palettes colour uosc; a pick is still applied and saved', function()
	local path = tmp_path()
	local p = load({[SCRIPT_NAME .. '-palette'] = 'nord'})
	mock.uosc = false
	mock.enable_input()
	mock.expand['~~/hikari-palette.conf'] = path
	mock.bindings['open-menu']()
	local t = assert(mock.selects[1], 'selector')
	eq(t.prompt, 'Paletas:')
	eq(t.items[1], '— Las paletas cambian los colores de uosc —', 'the note first')
	eq(t.items[2], '— Oscuras —', 'group heading')
	local nord, dracula
	for i, line in ipairs(t.items) do
		if line == '• Nord  ·  activa' then nord = i end
		if line == 'Dracula' then dracula = i end
	end
	assert(nord and dracula, 'Nord marked, Dracula listed')
	eq(t.default_item, nord)
	mock.console()
	mock.commands = {}
	mock.choose(1)
	eq(#mock.commands, 0, 'the note does nothing')
	mock.advance(1)
	mock.console()
	assert(mock.on_screen, 'the menu came back')
	mock.choose(dracula)
	eq(table.concat(mock.commands[1], ' '), 'script-message-to hikari_palettes select-palette dracula')
	mock.messages['select-palette']('dracula')
	eq(p.get_active_id(), 'dracula')
	local f = assert(io.open(path, 'rb')); local content = f:read('*a'); f:close()
	eq(content, p.persist_content(p.get_palette('dracula')), 'saved, for when uosc is back')
	os.remove(path)
end)

test('without uosc: a language switch redraws the selector with the note in the new language', function()
	load()
	mock.uosc = false
	mock.enable_input()
	mock.bindings['open-menu']()
	mock.console()
	mock.set_script_opt('hikari-language', 'en')
	mock.console()
	mock.advance(1)
	mock.console()
	local t = mock.on_screen
	eq(t.prompt, 'Palettes:')
	eq(t.items[1], '— Palettes change the colours of uosc —')
end)

test('without uosc on mpv before 0.39: a message on screen, no error', function()
	load()
	mock.uosc = false
	mock.bindings['open-menu']()
	eq(mock.osd[1], 'Este menú necesita uosc o mpv 0.39 o posterior')
	eq(#mock.logs.error, 0)
end)

-- With suji -----------------------------------------------------------------------

-- Like load(opts), with a script called suji loaded and `enabled` as suji
-- publishes it (true while it is turned on); `uosc` loaded or not.
local function load_with_suji(opts, enabled, uosc)
	mock.install(SCRIPT_NAME)
	mock.suji, mock.uosc = true, uosc == true
	mock.props['user-data/suji/enabled'] = enabled
	mock.script_opts = opts or {}
	if mock.script_opts['hikari-language'] == nil then mock.script_opts['hikari-language'] = 'es' end
	HIKARI_PALETTES_TEST = true
	return assert(loadfile(SCRIPT))()
end

-- The values of the change-list script-opts append commands sent.
local function appended()
	local out = {}
	for _, c in ipairs(mock.commands) do
		if c[1] == 'change-list' and c[2] == 'script-opts' and c[3] == 'append' then out[#out + 1] = c[4] end
	end
	return out
end

test('with suji: start-up and a pick set suji-accent to the foreground; the saved file has it', function()
	local path = tmp_path()
	local p = load_with_suji({[SCRIPT_NAME .. '-palette'] = 'nord'}, true)
	local sent = appended()
	eq(#sent, 3, 'start-up: colour, opacity, accent')
	eq(sent[1], 'uosc-color=' .. p.color_string(p.get_palette('nord')))
	eq(sent[2], 'uosc-opacity=')
	eq(sent[3], 'suji-accent=88c0d0')
	mock.expand['~~/hikari-palette.conf'] = path
	mock.commands = {}
	mock.messages['select-palette']('sceptic')
	sent = appended()
	eq(#sent, 3)
	eq(sent[3], 'suji-accent=5ad4e6', 'the accent of the palette picked')
	local f = assert(io.open(path, 'rb')); local content = f:read('*a'); f:close()
	assert(content:find('\nscript-opts-append=suji-accent=5ad4e6\n', 1, true), 'saved: ' .. content)
	eq(content, p.persist_content(p.get_palette('sceptic')))
	os.remove(path)
end)

test('suji loaded but turned off, or not there: no suji-accent at run time, the saved file has it all the same', function()
	local path = tmp_path()
	local p = load_with_suji(nil, false, true)
	eq(#appended(), 2, 'start-up: colour and opacity only')
	mock.expand['~~/hikari-palette.conf'] = path
	mock.commands = {}
	mock.messages['select-palette']('dracula')
	eq(#appended(), 2)
	local f = assert(io.open(path, 'rb')); local content = f:read('*a'); f:close()
	assert(content:find('\nscript-opts-append=suji-accent=bd93f9\n', 1, true), 'saved for when suji comes')
	os.remove(path)
	p = load()
	mock.commands = {}
	assert(p.apply(p.get_palette('nord')))
	for _, value in ipairs(appended()) do assert(not value:find('^suji'), value) end
end)

test('suji loads after this script (enabled nil at start-up): when it turns true, the accent of the active palette', function()
	load_with_suji({[SCRIPT_NAME .. '-palette'] = 'dracula'}, nil, true)
	eq(#appended(), 2, 'no suji yet')
	mock.commands = {}
	mock.set('user-data/suji/enabled', nil)
	eq(#mock.commands, 0, 'nil: nothing')
	mock.set('user-data/suji/enabled', true)
	eq(table.concat(appended(), ';'), 'suji-accent=bd93f9', 'only the accent')
end)

test('suji on, off, another palette picked, on again: the new palette\'s accent', function()
	local path = tmp_path()
	load_with_suji({[SCRIPT_NAME .. '-palette'] = 'nord'}, true, true)
	eq(appended()[3], 'suji-accent=88c0d0', 'on: Nord')
	mock.expand['~~/hikari-palette.conf'] = path
	mock.set('user-data/suji/enabled', false)
	mock.commands = {}
	mock.messages['select-palette']('dracula')
	eq(#appended(), 2, 'off: no accent at run time')
	mock.commands = {}
	mock.set('user-data/suji/enabled', true)
	eq(table.concat(appended(), ';'), 'suji-accent=bd93f9', 'on again: Dracula')
	os.remove(path)
end)

test('with suji: the menu opens in suji with a muted first line about the accent; no uosc note', function()
	local p = load_with_suji({[SCRIPT_NAME .. '-palette'] = 'nord'}, true)
	mock.commands = {}
	mock.bindings['open-menu']()
	eq(#mock.commands, 1)
	local c = mock.commands[1]
	eq(c[2], 'suji'); eq(c[3], 'open-menu')
	local data = mock.parse_json(c[4])
	eq(data.items[1].title, 'Con suji, la paleta cambia el color de acento')
	eq(data.items[1].selectable, false); eq(data.items[1].muted, true); eq(data.items[1].value, nil)
	eq(#data.items, #p.menu_data().items + 1, 'the rest as before')
	assert(not c[4]:find('colores de uosc', 1, true), 'no uosc note')
	-- A language switch with it open: in suji, in the new language, with the line.
	mock.props['user-data/suji/menu/type'] = 'hikari-palettes'
	mock.commands = {}
	mock.set_script_opt('hikari-language', 'en')
	eq(#mock.commands, 1)
	eq(mock.commands[1][2], 'suji'); eq(mock.commands[1][3], 'update-menu')
	data = mock.parse_json(mock.commands[1][4])
	eq(data.items[1].title, 'With suji, the palette changes the accent colour')
	eq(data.title, 'Palettes')
end)

test('with uosc and suji turned off: the menu as before, no accent line', function()
	local p = load_with_suji(nil, false, true)
	mock.commands = {}
	mock.bindings['open-menu']()
	eq(mock.commands[1][2], 'uosc')
	eq(mock.commands[1][4], mock.format_json(p.menu_data()))
end)

-- Side bars ----------------------------------------------------------------------

local VIDEO = {id = 1, image = false, albumart = false}
local PILLARBOX = {w = 1920, h = 1080, ml = 240, mr = 240, mt = 0, mb = 0}   -- 4:3 in 16:9
local FULL = {w = 1920, h = 1080, ml = 0, mr = 0, mt = 0, mb = 0}           -- 16:9 in 16:9
local LETTERBOX = {w = 1920, h = 1080, ml = 0, mr = 0, mt = 140, mb = 140}  -- 2.39:1 in 16:9

-- The values this script gave background-color, in order.
local function bg_sets()
	local out = {}
	for _, set in ipairs(mock.sets) do
		if set[1] == 'background-color' then out[#out + 1] = set[2] end
	end
	return out
end

-- Like load(opts), with `bg` as the background-color mpv has (nil: no such property).
-- Picks save to a temporary file; drop_saved() removes it.
local function load_bars(opts, bg)
	mock.install(SCRIPT_NAME)
	mock.expand['~~/hikari-palette.conf'] = tmp_path()
	mock.props['background-color'] = bg
	mock.script_opts = opts or {}
	if mock.script_opts['hikari-language'] == nil then mock.script_opts['hikari-language'] = 'es' end
	HIKARI_PALETTES_TEST = true
	return assert(loadfile(SCRIPT))()
end
local function drop_saved() os.remove(mock.expand['~~/hikari-palette.conf']) end

test('an old hikari-palette.conf without the bars line: black bars, background-color untouched', function()
	local p = load_bars({[SCRIPT_NAME .. '-palette'] = 'cel'}, '#FF000000')
	eq(p.get_bars(), 'black')
	eq(#mock.logs.warn, 0, 'no warning')
	mock.set('current-tracks/video', VIDEO)
	mock.set('osd-dimensions', PILLARBOX)
	eq(#bg_sets(), 0, 'nothing set')
	eq(p.stripes_overlay.updates, 0, 'no stripes')
end)

test('an unknown bars option warns and means black', function()
	local p = load_bars({[SCRIPT_NAME .. '-bars'] = 'rainbow'}, '#FF000000')
	eq(p.get_bars(), 'black')
	eq(#mock.logs.warn, 1, 'warning')
	mock.set('current-tracks/video', VIDEO)
	mock.set('osd-dimensions', PILLARBOX)
	eq(#bg_sets(), 0)
end)

test('palette: background-color is the curtain only while there are bars at both sides, then the user\'s again', function()
	local p = load_bars({[SCRIPT_NAME .. '-palette'] = 'cel', [SCRIPT_NAME .. '-bars'] = 'palette'}, '#FF102030')
	eq(#bg_sets(), 0, 'no window yet')
	mock.set('osd-dimensions', PILLARBOX)
	eq(#bg_sets(), 0, 'no video yet (idle)')
	mock.set('current-tracks/video', VIDEO)
	eq(table.concat(bg_sets(), ' '), '#120e0b', 'bars: the curtain')
	eq(mock.props['background-color'], '#120e0b')
	mock.set('osd-dimensions', {w = 1920, h = 1080, ml = 240, mr = 240, mt = 0, mb = 0})
	eq(#bg_sets(), 1, 'same bars: not set again')
	mock.set('osd-dimensions', FULL)
	eq(table.concat(bg_sets(), ' '), '#120e0b #FF102030', '16:9: back to the user\'s')
	mock.set('osd-dimensions', LETTERBOX)
	eq(#bg_sets(), 2, 'letterbox: nothing')
	mock.set('osd-dimensions', {w = 1920, h = 1080, ml = 1, mr = 1, mt = 0, mb = 0})
	eq(#bg_sets(), 2, 'a rounding pixel is no bar')
	mock.set('osd-dimensions', {w = 1920, h = 1080, ml = 240, mr = 0, mt = 0, mb = 0})
	eq(#bg_sets(), 2, 'one side only is no pillarbox')
	mock.set('osd-dimensions', PILLARBOX)
	eq(#bg_sets(), 3, 'bars again')
	-- Another palette: the bars follow at once.
	mock.messages['select-palette']('city_pop')
	eq(bg_sets()[4], '#120f27', 'City Pop curtain')
	-- A picture or cover art, or no video at all: the user's colour.
	mock.set('current-tracks/video', {id = 1, image = true, albumart = false})
	eq(bg_sets()[5], '#FF102030', 'picture')
	mock.set('current-tracks/video', VIDEO)
	mock.set('current-tracks/video', {id = 1, image = true, albumart = true})
	eq(bg_sets()[7], '#FF102030', 'cover art')
	mock.set('current-tracks/video', VIDEO)
	mock.set('current-tracks/video', nil)
	eq(bg_sets()[9], '#FF102030', 'no video')
	eq(p.stripes_overlay.updates, 0, 'palette: no stripes')
	eq(#mock.logs.warn, 0)
	drop_saved()
end)

test('select-bars: a known style is applied and saved, an unknown one ignored', function()
	local p = load_bars({[SCRIPT_NAME .. '-palette'] = 'phosphor'}, '#FF000000')
	local path = mock.expand['~~/hikari-palette.conf']
	mock.set('current-tracks/video', VIDEO)
	mock.set('osd-dimensions', PILLARBOX)
	mock.messages['select-bars']('palette')
	eq(p.get_bars(), 'palette')
	eq(table.concat(bg_sets(), ' '), '#080b0a', 'applied at once')
	local f = assert(io.open(path, 'rb')); local content = f:read('*a'); f:close()
	eq(content, p.persist_content(p.get_palette('phosphor'), 'palette'), 'saved with the palette')
	-- Picking a palette keeps the side bars in the file.
	mock.messages['select-palette']('cel')
	f = assert(io.open(path, 'rb')); content = f:read('*a'); f:close()
	eq(content, p.persist_content(p.get_palette('cel'), 'palette'), 'palette saved with the bars')
	os.remove(path)
	mock.sets = {}
	mock.messages['select-bars']('x\nscript-opts-append=evil')
	eq(p.get_bars(), 'palette', 'unknown: ignored')
	eq(#bg_sets(), 0)
	eq(#mock.logs.warn, 1, 'warned')
	eq(io.open(path, 'rb'), nil, 'nothing saved')
	mock.messages['select-bars']('black')
	eq(table.concat(bg_sets(), ' '), '#FF000000', 'black: the original back')
	os.remove(path)
end)

test('stripes: three stripes per bar next to the image, mirrored, below the interfaces; gone without bars', function()
	local p = load_bars({[SCRIPT_NAME .. '-palette'] = 'cel', [SCRIPT_NAME .. '-bars'] = 'stripes'}, '#FF000000')
	local o = p.stripes_overlay
	assert(o.z < 0, 'z below the default 0')
	eq(o.format, 'ass-events')
	mock.set('current-tracks/video', VIDEO)
	eq(o.updates, 0, 'no window yet')
	mock.set('osd-dimensions', PILLARBOX)
	eq(table.concat(bg_sets(), ' '), '#120e0b', 'the curtain as well')
	eq(o.updates, 1); eq(o.visible, true)
	eq(o.res_x, 1920); eq(o.res_y, 1080)
	local lines = {}
	for line in (o.data .. '\n'):gmatch('([^\n]*)\n') do lines[#lines + 1] = line end
	eq(#lines, 3, 'one event per colour')
	-- 240 px bars: the stripes are 12 px wide with 6 px gaps, the first 24 px from the image.
	eq(lines[1], '{\\an7\\pos(0,0)\\bord0\\shad0\\blur0\\1c&H3A64E8&\\1a&H00&\\p1}'
		.. 'm 204 0 l 216 0 l 216 1080 l 204 1080 m 1704 0 l 1716 0 l 1716 1080 l 1704 1080{\\p0}', 'foreground')
	assert(lines[2]:find('\\1c&H4AB0E8&', 1, true) and lines[2]:find('m 186 0 l 198 0', 1, true)
		and lines[2]:find('m 1722 0 l 1734 0', 1, true), 'heatmap: ' .. lines[2])
	assert(lines[3]:find('\\1c&HB8A86F&', 1, true) and lines[3]:find('m 168 0 l 180 0', 1, true)
		and lines[3]:find('m 1740 0 l 1752 0', 1, true), 'match: ' .. lines[3])
	mock.set('osd-dimensions', PILLARBOX)
	eq(o.updates, 1, 'same picture: not redrawn')
	-- Another palette: new colours at once.
	mock.messages['select-palette']('phosphor')
	eq(o.updates, 2)
	assert(o.data:find('\\1c&H00B0FF&', 1, true), 'Phosphor foreground')
	-- 16:9: no stripes, the original colour back.
	mock.set('osd-dimensions', FULL)
	eq(o.visible, false); eq(o.removes, 1)
	eq(bg_sets()[#bg_sets()], '#FF000000')
	-- Back to bars, then to palette: the stripes go, the colour stays.
	mock.set('osd-dimensions', PILLARBOX)
	eq(o.visible, true)
	mock.messages['select-bars']('palette')
	eq(o.visible, false, 'palette: no stripes')
	eq(bg_sets()[#bg_sets()], '#080b0a', 'still the curtain')
	drop_saved()
end)

test('a background-color changed after start-up (a profile, the console) is the one put back', function()
	load_bars({[SCRIPT_NAME .. '-palette'] = 'cel', [SCRIPT_NAME .. '-bars'] = 'palette'}, '#FF102030')
	mock.props['background-color'] = '#FFAABBCC'
	mock.set('current-tracks/video', VIDEO)
	mock.set('osd-dimensions', PILLARBOX)
	mock.set('osd-dimensions', FULL)
	eq(table.concat(bg_sets(), ' '), '#120e0b #FFAABBCC', 'the newer value back')
	mock.props['background-color'] = '#FF445566'
	mock.set('osd-dimensions', PILLARBOX)
	mock.messages['select-palette']('city_pop')
	mock.set('osd-dimensions', FULL)
	eq(table.concat(bg_sets(), ' '), '#120e0b #FFAABBCC #120e0b #120f27 #FF445566',
		'read again when the bars come back, not between palettes')
	drop_saved()
end)

-- The values this script gave sub-use-margins, in order.
local function subs_sets()
	local out = {}
	for _, set in ipairs(mock.sets) do
		if set[1] == 'sub-use-margins' then out[#out + 1] = set[2] end
	end
	return table.concat(out, ' ')
end

test('stripes keep text subtitles inside the picture while drawn, and give sub-use-margins back on every way out', function()
	load_bars({[SCRIPT_NAME .. '-palette'] = 'cel', [SCRIPT_NAME .. '-bars'] = 'stripes'}, '#FF000000')
	mock.props['sub-use-margins'] = 'yes'
	mock.set('osd-dimensions', PILLARBOX)
	eq(subs_sets(), '', 'no video yet')
	mock.set('current-tracks/video', VIDEO)
	eq(subs_sets(), 'no', 'stripes: inside the picture')
	mock.messages['select-palette']('phosphor')
	eq(subs_sets(), 'no', 'another palette: not set again')
	mock.set('osd-dimensions', FULL)
	eq(subs_sets(), 'no yes', 'no bars: back')
	mock.set('osd-dimensions', PILLARBOX)
	mock.set('current-tracks/video', nil)
	eq(subs_sets(), 'no yes no yes', 'no video (idle): back')
	mock.set('current-tracks/video', VIDEO)
	mock.set('current-tracks/video', {id = 1, image = true, albumart = false})
	eq(subs_sets(), 'no yes no yes no yes', 'a picture: back')
	mock.set('current-tracks/video', VIDEO)
	mock.messages['select-bars']('palette')
	eq(subs_sets(), 'no yes no yes no yes no yes', 'palette: back')
	mock.messages['select-bars']('stripes')
	mock.messages['select-bars']('black')
	eq(subs_sets(), 'no yes no yes no yes no yes no yes', 'black: back')
	eq(mock.props['sub-use-margins'], 'yes')
	drop_saved()
end)

test('palette (colour only) leaves sub-use-margins alone', function()
	load_bars({[SCRIPT_NAME .. '-bars'] = 'palette'}, '#FF000000')
	mock.props['sub-use-margins'] = 'yes'
	mock.set('current-tracks/video', VIDEO)
	mock.set('osd-dimensions', PILLARBOX)
	eq(#bg_sets(), 1, 'coloured')
	eq(subs_sets(), '', 'untouched')
end)

test('sub-use-margins changed after start-up is the one given back; a refused set marks nothing', function()
	load_bars({[SCRIPT_NAME .. '-bars'] = 'stripes'}, '#FF000000')
	mock.props['sub-use-margins'] = 'yes'
	mock.set('current-tracks/video', VIDEO)
	mock.props['sub-use-margins'] = 'no'   -- a profile turned it off meanwhile
	mock.set('osd-dimensions', PILLARBOX)
	mock.set('osd-dimensions', FULL)
	eq(subs_sets(), 'no no', 'its own value back')
	-- mpv refuses: nothing marked, nothing to give back.
	mock.sets = {}
	mock.props['sub-use-margins'] = 'yes'
	mock.set_fails['sub-use-margins'] = true
	mock.set('osd-dimensions', PILLARBOX)
	mock.set('osd-dimensions', FULL)
	eq(subs_sets(), 'no', 'one refused try, no give-back')
	eq(mock.props['sub-use-margins'], 'yes')
	-- A refused give-back is tried again on the next update.
	mock.set_fails['sub-use-margins'] = nil
	mock.sets = {}
	mock.set('osd-dimensions', PILLARBOX)
	mock.set_fails['sub-use-margins'] = true
	mock.set('osd-dimensions', FULL)
	mock.set_fails['sub-use-margins'] = nil
	mock.set('osd-dimensions', LETTERBOX)
	eq(subs_sets(), 'no yes yes', 'given back on the second try')
	eq(mock.props['sub-use-margins'], 'yes')
end)

test('a refused background-color give-back stays marked and is tried again', function()
	load_bars({[SCRIPT_NAME .. '-bars'] = 'palette'}, '#FF102030')
	mock.set('current-tracks/video', VIDEO)
	mock.set('osd-dimensions', PILLARBOX)
	mock.set_fails['background-color'] = true
	mock.set('osd-dimensions', FULL)
	mock.set_fails['background-color'] = nil
	mock.set('osd-dimensions', LETTERBOX)
	eq(table.concat(bg_sets(), ' '), '#111111 #FF102030 #FF102030', 'tried again')
	eq(mock.props['background-color'], '#FF102030')
	mock.set('osd-dimensions', FULL)
	eq(#bg_sets(), 3, 'then left alone')
end)

test('stripes in a narrow bar are still at least one pixel wide', function()
	local p = load_bars(nil, '#FF000000')
	local data = p.stripes_ass(p.get_palette('uosc'), 1000, 750, 20, 20)
	for x0, x1 in data:gmatch('m (%d+) 0 l (%d+) 0') do
		assert(tonumber(x1) > tonumber(x0), x0 .. '..' .. x1)
	end
end)

test('an mpv without background-color: no colour, one warning, the stripes still drawn', function()
	local p = load_bars({[SCRIPT_NAME .. '-bars'] = 'stripes'}, nil)
	mock.set('current-tracks/video', VIDEO)
	mock.set('osd-dimensions', PILLARBOX)
	mock.set('osd-dimensions', {w = 1600, h = 900, ml = 200, mr = 200, mt = 0, mb = 0})
	mock.messages['select-palette']('cel')
	mock.set('osd-dimensions', FULL)
	eq(#bg_sets(), 0, 'never set')
	eq(#mock.logs.warn, 1, 'one warning')
	eq(#mock.logs.error, 0)
	eq(p.stripes_overlay.removes, 1, 'stripes drawn, then gone')
	drop_saved()
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
