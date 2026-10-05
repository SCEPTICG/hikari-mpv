-- Run from the repository root: lua tests/test_subs.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/sosc-subs.lua'
local SCRIPT_NAME = 'sosc_subs'
local CONF = '~~/sosc-subs.conf'

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

-- Options of a recent mpv (0.38+) and of mpv 0.37 (old names, no sub-shadow-color).
local NEW_MPV = {
	['sub-color'] = '#FFFFFFFF', ['sub-outline-color'] = '#FF000000', ['sub-outline-size'] = '3.000000',
	['sub-shadow-offset'] = '0.000000', ['sub-shadow-color'] = '#FF000000', ['sub-back-color'] = '#00000000',
	['sub-bold'] = 'no', ['sub-border-style'] = 'outline-and-shadow',
}
local OLD_MPV = {
	['sub-color'] = '#FFFFFFFF', ['sub-border-color'] = '#FF000000', ['sub-border-size'] = '3.000000',
	['sub-shadow-offset'] = '0.000000', ['sub-back-color'] = '#00000000',
	['sub-bold'] = 'no', ['sub-border-style'] = 'outline-and-shadow',
}

-- Loads the script with fresh mocks. `mpv_opts` are the options this mpv knows,
-- with their mpv defaults; `current` overrides what they are set to right now
-- (mpv.conf, the included .conf).
local function load(script_opts, mpv_opts, current)
	mock.install(SCRIPT_NAME)
	mock.script_opts = script_opts or {}
	for prop, default in pairs(mpv_opts or NEW_MPV) do
		mock.props['option-info/' .. prop .. '/name'] = prop
		mock.props['option-info/' .. prop .. '/default-value'] = default
		mock.props[prop] = default
	end
	for prop, value in pairs(current or {}) do mock.props[prop] = value end
	SOSC_SUBS_TEST = true
	local chunk = assert(loadfile(SCRIPT))
	return chunk()
end

local function tmp_path()
	local path = os.tmpname()
	os.remove(path)
	return path
end

local function read(path)
	local f = assert(io.open(path, 'rb')); local content = f:read('*a'); f:close()
	return content
end

-- `set` commands sent since the last reset, as prop -> value (and their count).
local function sets()
	local t, n = {}, 0
	for _, c in ipairs(mock.commands) do
		if c[1] == 'set' then
			eq(#c, 3, 'set argument count')
			t[c[2]] = c[3]; n = n + 1
		end
	end
	return t, n
end

local function opt(what, id) return {[SCRIPT_NAME .. '-' .. what] = id} end

test('tables: ids, names and values are valid', function()
	local s = load()
	local expected = {
		{s.STYLES, {'original', 'dark_box', 'thick_outline', 'yellow'}},
		{s.SIZES, {'small', 'normal', 'large', 'xlarge'}},
		{s.HEIGHTS, {'normal', 'raised', 'high'}},
	}
	for _, pair in ipairs(expected) do
		eq(#pair[1], #pair[2], 'count')
		for i, id in ipairs(pair[2]) do
			eq(pair[1][i].id, id, 'id #' .. i)
			assert(s.is_valid_id(id), id)
			assert(type(pair[1][i].name) == 'string' and #pair[1][i].name > 0, 'name of ' .. id)
		end
	end
	for _, size in ipairs(s.SIZES) do assert(s.is_valid_value('number', size.value), size.id) end
	for _, height in ipairs(s.HEIGHTS) do assert(s.is_valid_value('number', height.value), height.id) end
	eq(s.size_by_id.normal.value, '1', 'normal size'); eq(s.height_by_id.normal.value, '100', 'normal height')
	for _, style in ipairs(s.STYLES) do
		for _, spec in ipairs(s.STYLE_KEYS) do
			if style[spec.key] ~= nil then assert(s.is_valid_value(spec.kind, style[spec.key]), style.id .. '.' .. spec.key) end
		end
		-- On mpv < 0.38 both are sub-back-color.
		assert(not (style.shadow_color and style.box_color), style.id .. ' sets shadow_color and box_color')
	end
end)

test('validators reject malformed values', function()
	local s = load()
	for _, v in ipairs({'#FFF', 'FFFFFFFF', '#FFFFFFFF\n', '#GGFFFFFF', '#FFFFFFFF"'}) do
		assert(not s.is_valid_value('color', v), 'color ' .. v)
	end
	for _, v in ipairs({'1,2', '-1', '1e3', '.5', '1.', '1.2\n', ''}) do
		assert(not s.is_valid_value('number', v), 'number ' .. v)
	end
	assert(not s.is_valid_value('bool', 'true'), 'bool')
	assert(not s.is_valid_value('border_style', 'box'), 'border style')
	assert(not s.is_valid_value('color', 1), 'non-string')
	assert(not s.is_valid_value('nope', 'x'), 'unknown kind')
	assert(not s.is_valid_id('../evil'), 'path-like id'); assert(not s.is_valid_id('a\nb'), 'newline id')
	assert(not s.is_safe_mpv_value('a b'), 'space'); assert(not s.is_safe_mpv_value('"x"'), 'quote')
	assert(s.is_safe_mpv_value('#FFFFFFFF') and s.is_safe_mpv_value('3.000000') and s.is_safe_mpv_value('opaque-box'), 'mpv values')
	local bad = {id = 'bad', text_color = '#FFF'}
	eq(s.style_settings(bad), nil, 'bad style settings')
	eq(s.persist_content(bad, s.size_by_id.normal, s.height_by_id.normal), nil, 'bad style content')
	mock.commands = {}
	eq(s.apply_style(bad), false, 'bad style applied')
	eq(#mock.commands, 0, 'commands for bad style')
end)

test('option names: new mpv uses sub-outline-* and sub-shadow-color', function()
	local s = load()
	local settings = s.style_settings(s.style_by_id.thick_outline)
	local t = {}
	for _, kv in ipairs(settings) do t[kv[1]] = kv[2] end
	eq(t['sub-outline-color'], '#FF000000'); eq(t['sub-outline-size'], '4')
	eq(t['sub-shadow-color'], '#80000000'); eq(t['sub-border-color'], nil); eq(t['sub-back-color'], nil)
	eq(#s.get_managed_props(), 8, 'managed options')
end)

test('option names: mpv 0.37 uses sub-border-* and sub-back-color for both', function()
	local s = load(nil, OLD_MPV)
	eq(#s.get_managed_props(), 7, 'managed options')
	for _, style in ipairs(s.STYLES) do assert(s.style_settings(style), style.id .. ' conflicts on old mpv') end
	local t = {}
	for _, kv in ipairs(s.style_settings(s.style_by_id.yellow)) do t[kv[1]] = kv[2] end
	eq(t['sub-border-color'], '#FF000000'); eq(t['sub-border-size'], '3'); eq(t['sub-back-color'], '#A0000000')
	t = {}
	for _, kv in ipairs(s.style_settings(s.style_by_id.dark_box)) do t[kv[1]] = kv[2] end
	eq(t['sub-back-color'], '#C0000000'); eq(t['sub-border-style'], 'opaque-box')
end)

test('mpv without sub-border-style skips it', function()
	local old = {}
	for k, v in pairs(OLD_MPV) do old[k] = v end
	old['sub-border-style'] = nil
	local s = load(nil, old)
	for _, kv in ipairs(s.style_settings(s.style_by_id.dark_box)) do assert(kv[1] ~= 'sub-border-style', 'border style set') end
end)

test('menu: three groups, headers, info line and the active options', function()
	local s = load(opt('style', 'yellow'))
	local data = s.menu_data()
	eq(data.type, 'sosc-subs'); eq(data.title, 'Subtítulos'); eq(data.keep_open, true, 'keep_open')
	local headers, active, selectable = {}, {}, 0
	for i, item in ipairs(data.items) do
		if item.selectable == false then headers[#headers + 1] = item.title end
		if item.active then active[#active + 1] = item.title; eq(item.hint, 'activa', 'hint') end
		if item.value then
			selectable = selectable + 1
			eq(item.value[1], 'script-message-to'); eq(item.value[2], SCRIPT_NAME)
			assert(s.is_valid_id(item.value[4]), 'value id')
		end
	end
	eq(selectable, 4 + 4 + 3, 'selectable items')
	eq(#data.items, 11 + 4, 'items incl. 3 headers and the info line')
	eq(headers[1], 'Estilo'); eq(headers[2], 'Tamaño'); eq(headers[3], 'Altura')
	eq(headers[4], 'Los estilos solo cambian SRT; los ASS conservan el suyo')
	eq(#active, 3, 'active count')
	eq(active[1], 'Amarillo clásico'); eq(active[2], 'Normal'); eq(active[3], 'Normal')
	eq(data.items[5].separator, true, 'separator after styles')
	eq(data.items[10].separator, true, 'separator after sizes')
	eq(data.items[14].separator, true, 'separator before the info line')
	eq(data.items[2].value[3], 'select-style'); eq(data.items[7].value[3], 'select-size')
	eq(data.items[12].value[3], 'select-height')

	mock.commands = {}
	mock.bindings['open-menu']()
	local c = mock.commands[1]
	eq(c[1], 'script-message-to'); eq(c[2], 'uosc'); eq(c[3], 'open-menu')
	eq(c[4], mock.format_json(data), 'json payload')
end)

test('choosing a style applies every managed option, saves and refreshes the menu', function()
	local s = load()
	local path = tmp_path()
	mock.expand[CONF] = path
	mock.commands = {}
	mock.messages['select-style']('dark_box')
	local t, n = sets()
	eq(n, 8, 'set count')
	eq(t['sub-color'], '#FFFFFFFF'); eq(t['sub-outline-color'], '#C0000000'); eq(t['sub-outline-size'], '2.5')
	eq(t['sub-shadow-offset'], '0'); eq(t['sub-back-color'], '#C0000000'); eq(t['sub-bold'], 'no')
	eq(t['sub-border-style'], 'opaque-box')
	eq(t['sub-shadow-color'], '#FF000000', 'not in the style: baseline')
	eq(s.get_active().style.id, 'dark_box')
	eq(read(path), s.persist_content(s.style_by_id.dark_box, s.size_by_id.normal, s.height_by_id.normal), 'saved')
	local last = mock.commands[#mock.commands]
	eq(last[1], 'script-message-to'); eq(last[2], 'uosc'); eq(last[3], 'update-menu')
	eq(last[4], mock.format_json(s.menu_data()), 'refreshed menu')
	assert(last[4]:find('"active":true,"hint":"activa","title":"Caja oscura"', 1, true), 'new active style')
	eq(#mock.osd, 0, 'osd'); eq(#mock.logs.warn, 0, 'warnings')
	os.remove(path)
end)

test('switching styles leaves nothing behind from the previous one', function()
	local s = load()
	mock.expand[CONF] = tmp_path()
	mock.messages['select-style']('dark_box')
	mock.commands = {}
	mock.messages['select-style']('thick_outline')
	local t = sets()
	eq(t['sub-back-color'], '#00000000', 'box colour back to baseline')
	eq(t['sub-border-style'], 'outline-and-shadow'); eq(t['sub-bold'], 'yes'); eq(t['sub-shadow-color'], '#80000000')
	os.remove(mock.expand[CONF])
end)

test('size and height set sub-scale and sub-pos and keep the rest', function()
	local s = load()
	local path = tmp_path()
	mock.expand[CONF] = path
	mock.messages['select-style']('yellow')
	mock.commands = {}
	mock.messages['select-size']('xlarge')
	local t, n = sets()
	eq(n, 1); eq(t['sub-scale'], '1.4')
	mock.commands = {}
	mock.messages['select-height']('high')
	t, n = sets()
	eq(n, 1); eq(t['sub-pos'], '90')
	eq(read(path), s.persist_content(s.style_by_id.yellow, s.size_by_id.xlarge, s.height_by_id.high), 'saved combination')
	eq(mock.commands[#mock.commands][3], 'update-menu', 'menu refreshed')
	os.remove(path)
end)

test('Original restores the values mpv had at start-up', function()
	-- mpv.conf set its own colour and outline; the saved style is Original.
	local s = load(nil, NEW_MPV, {['sub-color'] = '#FF00FF00', ['sub-outline-size'] = '2.000000'})
	mock.expand[CONF] = tmp_path()
	mock.commands = {}
	eq(#mock.commands, 0)
	mock.messages['select-style']('yellow')
	mock.commands = {}
	mock.messages['select-style']('original')
	local t, n = sets()
	eq(n, 8, 'set count')
	eq(t['sub-color'], '#FF00FF00', 'mpv.conf colour'); eq(t['sub-outline-size'], '2.000000', 'mpv.conf size')
	eq(t['sub-outline-color'], '#FF000000'); eq(t['sub-back-color'], '#00000000'); eq(t['sub-bold'], 'no')
	eq(t['sub-border-style'], 'outline-and-shadow'); eq(t['sub-shadow-offset'], '0.000000')
	os.remove(mock.expand[CONF])
end)

test('Original after starting with another style restores mpv defaults', function()
	local s = load(opt('style', 'yellow'), NEW_MPV, {['sub-color'] = '#FFFFE600', ['sub-outline-size'] = '3'})
	eq(s.get_baseline()['sub-color'], '#FFFFFFFF', 'baseline from option-info default')
	mock.expand[CONF] = tmp_path()
	mock.commands = {}
	mock.messages['select-style']('original')
	local t = sets()
	eq(t['sub-color'], '#FFFFFFFF'); eq(t['sub-outline-size'], '3.000000')
	os.remove(mock.expand[CONF])
end)

test('unsafe values read from mpv are not used', function()
	local s = load(nil, NEW_MPV, {['sub-color'] = '#FF00FF00\nsub-pos=0'})
	eq(s.get_baseline()['sub-color'], nil, 'unsafe baseline')
	eq(#mock.logs.warn, 1, 'warning')
end)

test('unknown ids from messages are ignored', function()
	local s = load()
	mock.commands = {}
	mock.messages['select-style']('x\nsub-color=evil')
	mock.messages['select-size']('huge')
	mock.messages['select-height']('100')
	mock.messages['select-style'](nil)
	eq(#mock.commands, 0, 'commands')
	eq(s.get_active().style.id, 'original'); eq(s.get_active().size.id, 'normal'); eq(s.get_active().height.id, 'normal')
	eq(#mock.logs.warn, 4, 'warnings')
end)

test('start-up applies the saved combination', function()
	local s = load({[SCRIPT_NAME .. '-style'] = 'thick_outline', [SCRIPT_NAME .. '-size'] = 'large',
		[SCRIPT_NAME .. '-height'] = 'raised'})
	local t, n = sets()
	eq(n, 8 + 2, 'set count')
	eq(t['sub-bold'], 'yes'); eq(t['sub-outline-size'], '4'); eq(t['sub-scale'], '1.2'); eq(t['sub-pos'], '95')
	eq(s.get_active().style.id, 'thick_outline')
end)

test('start-up with Original only sets size and height', function()
	load()
	local t, n = sets()
	eq(n, 2, 'set count'); eq(t['sub-scale'], '1'); eq(t['sub-pos'], '100')
end)

test('unknown saved ids fall back to the defaults', function()
	local s = load({[SCRIPT_NAME .. '-style'] = 'nope', [SCRIPT_NAME .. '-size'] = 'x', [SCRIPT_NAME .. '-height'] = 'y'})
	eq(s.get_active().style.id, 'original'); eq(s.get_active().size.id, 'normal'); eq(s.get_active().height.id, 'normal')
	eq(#mock.logs.warn, 3, 'warnings')
end)

test('.conf content is exact, quoted and uses a decimal point', function()
	local s = load()
	local expected = '# Generated by sosc-subs.lua. Style: dark_box, size: small, height: raised\n'
		.. 'sub-color="#FFFFFFFF"\n'
		.. 'sub-outline-color="#C0000000"\n'
		.. 'sub-outline-size="2.5"\n'
		.. 'sub-shadow-offset="0"\n'
		.. 'sub-back-color="#C0000000"\n'
		.. 'sub-bold="no"\n'
		.. 'sub-border-style="opaque-box"\n'
		.. 'sub-scale="0.85"\n'
		.. 'sub-pos="95"\n'
		.. 'script-opts-append=sosc_subs-style=dark_box\n'
		.. 'script-opts-append=sosc_subs-size=small\n'
		.. 'script-opts-append=sosc_subs-height=raised\n'
	eq(s.persist_content(s.style_by_id.dark_box, s.size_by_id.small, s.height_by_id.raised), expected, 'content')
	-- Same result under a comma-decimal locale.
	local saved = os.setlocale(nil, 'numeric')
	for _, loc in ipairs({'es_ES.UTF-8', 'de_DE.UTF-8'}) do
		if os.setlocale(loc, 'numeric') then
			eq(s.persist_content(s.style_by_id.dark_box, s.size_by_id.small, s.height_by_id.raised), expected, loc)
		end
	end
	os.setlocale(saved, 'numeric')
	-- Every line is a comment, a quoted sub-* option or our script-opts; no stray '#'.
	for _, style in ipairs(s.STYLES) do
		for _, size in ipairs(s.SIZES) do
			for _, height in ipairs(s.HEIGHTS) do
				local content = assert(s.persist_content(style, size, height))
				for line in content:gmatch('([^\n]*)\n') do
					assert(line:match('^# Generated by sosc%-subs%.lua%.') or line:match('^sub%-[a-z-]+="[%w#%.%-]+"$')
						or line:match('^script%-opts%-append=sosc_subs%-[a-z]+=[a-z0-9_-]+$'), 'bad line: ' .. line)
				end
			end
		end
	end
end)

test('Original writes no style lines, whatever the mpv version', function()
	local new = load()
	local a = new.persist_content(new.style_by_id.original, new.size_by_id.normal, new.height_by_id.normal)
	local old = load(nil, OLD_MPV)
	local b = old.persist_content(old.style_by_id.original, old.size_by_id.normal, old.height_by_id.normal)
	eq(a, b, 'same on old and new mpv')
	assert(not a:find('sub%-color') and not a:find('border') and not a:find('outline'), 'style lines in Original')
end)

test('shipped sosc-subs.conf matches what the script would write', function()
	local s = load()
	eq(read('portable_config/sosc-subs.conf'),
		s.persist_content(s.style_by_id.original, s.size_by_id.normal, s.height_by_id.normal), 'default file')
end)

test('atomic write creates and then replaces the file', function()
	local s = load()
	local path = tmp_path()
	assert(s.write_file_atomic(path, 'one\n'))
	assert(s.write_file_atomic(path, 'two\n'))
	eq(read(path), 'two\n', 'content')
	eq(io.open(path .. '.tmp', 'rb'), nil, 'leftover temp file')
	os.remove(path)
end)

test('a failed save still applies and warns', function()
	local s = load()
	mock.expand[CONF] = '/nonexistent-dir/sosc-subs.conf'
	mock.commands = {}
	mock.messages['select-size']('large')
	local t = sets()
	eq(t['sub-scale'], '1.2', 'applied')
	eq(s.get_active().size.id, 'large', 'active')
	eq(#mock.logs.warn, 1, 'warnings'); eq(#mock.osd, 1, 'osd messages')
	eq(mock.commands[#mock.commands][3], 'update-menu', 'menu still refreshed')
end)

test('the script avoids os.execute, io.popen and load*', function()
	local src = read(SCRIPT)
	for _, bad in ipairs({'os.execute', 'io.popen', 'loadstring', 'loadfile', 'dofile', 'load('}) do
		assert(not src:find(bad, 1, true), bad)
	end
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
