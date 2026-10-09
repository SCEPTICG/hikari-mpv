-- Run from the repository root: lua tests/test_media_language.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/hikari-media-language.lua'
local SCRIPT_NAME = 'hikari_media_language'
local CODES = {'en', 'es', 'de', 'fr', 'it', 'pl', 'pt', 'ro', 'ru', 'tr', 'uk', 'zh-HK', 'zh-hans'}
local SWMA = 'subs-with-matching-audio'

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

local function join(list) return type(list) == 'table' and table.concat(list, ',') or tostring(list) end

local tmp_files = {}
local function conf_file(text)
	local path = os.tmpname()
	tmp_files[#tmp_files + 1] = path
	local f = assert(io.open(path, 'wb'))
	f:write(text)
	f:close()
	return path
end

-- Loads the script as mpv would start it. `setup` may hold:
--   lang:    the hikari-language script option
--   values:  option name -> value already in effect (what mpv.conf etc. left)
--   cmdline: option name -> true when set on the command line
--   conf:    the text of ~~/mpv.conf (none by default)
--   unknown: option name -> true when this mpv gives no option-info for it
--   fail:    option name -> true when mp.set_property fails for it
-- Options not in `values` hold mpv's defaults, as mpv 0.40 gives them natively.
local function load(setup)
	setup = setup or {}
	mock.install(SCRIPT_NAME)
	mock.script_opts = {['hikari-language'] = setup.lang or 'es'}
	local defaults = {alang = {}, slang = {}, [SWMA] = true}
	for name, default in pairs(defaults) do
		if not (setup.unknown or {})[name] then
			mock.props['option-info/' .. name .. '/default-value'] = default
			mock.props['option-info/' .. name .. '/set-from-commandline'] = (setup.cmdline or {})[name] == true
		end
		local value = (setup.values or {})[name]
		if value == nil then value = default end
		mock.props[name] = value
	end
	if setup.conf then mock.config_files['mpv.conf'] = conf_file(setup.conf) end
	for name in pairs(setup.fail or {}) do mock.set_fails[name] = true end
	HIKARI_MEDIA_LANGUAGE_TEST = true
	local chunk = assert(loadfile(SCRIPT))
	return chunk()
end

local function sets_of(name)
	local list = {}
	for _, s in ipairs(mock.sets) do
		if s[1] == name then list[#list + 1] = tostring(s[2]) end
	end
	return table.concat(list, ' ')
end

local function native_sets_of(name)
	local n = 0
	for _, s in ipairs(mock.native_sets) do
		if s[1] == name then n = n + 1 end
	end
	return n
end

-- A file playing with mpv's own track choice (aid/sid options `auto`).
local function play(m, aid, sid)
	mock.props['options/aid'], mock.props['options/sid'] = 'auto', 'auto'
	mock.props.aid, mock.props.sid = aid or 1, sid == nil and false or sid
	mock.events['start-file']()
	mock.events['file-loaded']()
	eq(m.is_playing(), true, 'playing')
	mock.sets = {}
end

-- Codes ----------------------------------------------------------------------

test('codes: every language of hikari has its list, and nothing else does', function()
	local i18n = load().i18n
	local n = 0
	for code in pairs(i18n.MEDIA_LANGUAGES) do
		n = n + 1
		assert(i18n.is_language(code), code .. ' is not a language of hikari')
	end
	eq(n, #CODES, 'lists')
	for _, code in ipairs(CODES) do assert(i18n.MEDIA_LANGUAGES[code], 'no list for ' .. code) end
end)

test('codes: language tags only, no repeats, nothing a list option would split', function()
	local i18n = load().i18n
	local lists = {ja = i18n.ORIGINAL_AUDIO}
	for code, list in pairs(i18n.MEDIA_LANGUAGES) do lists[code] = list end
	for code, list in pairs(lists) do
		local seen = {}
		assert(#list > 0, code .. ' is empty')
		for _, tag in ipairs(list) do
			assert(tag:match('^%a%a%a?$') or tag:match('^%a%a%-%w+$'), code .. ': odd tag ' .. tag)
			assert(not seen[tag:lower()], code .. ': ' .. tag .. ' twice')
			seen[tag:lower()] = true
		end
	end
end)

test('codes: each list starts with the 2-letter code, Chinese with its script', function()
	local i18n = load().i18n
	for _, code in ipairs(CODES) do
		local first = i18n.MEDIA_LANGUAGES[code][1]
		if code == 'zh-HK' then eq(first, 'zh-Hant', code)
		elseif code == 'zh-hans' then eq(first, 'zh-Hans', code)
		else eq(first, code, code) end
	end
	eq(join(i18n.ORIGINAL_AUDIO), 'ja,jpn', 'original audio')
end)

test('codes: the regional tags of real dubs come before Japanese', function()
	local m = load()
	local alang = join(m.recipe('es').alang)
	eq(alang, 'es,spa,es-ES,es-419,ja,jpn', 'es')
	eq(join(m.recipe('pt').alang), 'pt,por,pt-BR,pt-PT,ja,jpn', 'pt')
	eq(join(m.recipe('de').slang), 'de,ger,deu,de-DE', 'de')
	eq(join(m.recipe('zh-HK').slang), 'zh-Hant,zh-HK,zh-TW,zh,chi,zho,zh-Hans,zh-CN', 'zh-HK')
	eq(join(m.recipe('zh-hans').slang), 'zh-Hans,zh-CN,zh,chi,zho,zh-Hant,zh-TW', 'zh-hans')
end)

test('recipe: English is the same recipe in English; an unknown code falls back to it', function()
	local m = load()
	eq(join(m.recipe('en').alang), 'en,eng,en-US,en-GB,ja,jpn', 'alang')
	eq(join(m.recipe('en').slang), 'en,eng,en-US,en-GB', 'slang')
	eq(m.recipe('en')[SWMA], 'no', 'swma')
	eq(join(m.recipe('xx').slang), 'en,eng,en-US,en-GB', 'unknown')
end)

test('recipe: returns fresh lists (changing one leaves the table alone)', function()
	local m = load()
	local r = m.recipe('es')
	r.alang[1] = 'xx'
	r.slang[1] = 'xx'
	eq(m.i18n.MEDIA_LANGUAGES.es[1], 'es', 'table')
end)

-- Values ---------------------------------------------------------------------

test('values: lists, flags and strings compare the way mpv gives them', function()
	local m = load()
	eq(m.same_value({}, {}), true, 'empty lists')
	eq(m.same_value({'es', 'ja'}, {'es', 'ja'}), true, 'lists')
	eq(m.same_value({'es,ja'}, {'es', 'ja'}), false, 'one item with a comma')
	eq(m.same_value(false, 'no'), true, 'flag no')
	eq(m.same_value(true, 'yes'), true, 'flag yes')
	eq(m.same_value('forced', 'no'), false, 'forced')
	eq(m.same_value(nil, 'no'), false, 'nil')
end)

-- Start ----------------------------------------------------------------------

test('start: nothing of yours: all three options get the recipe', function()
	load({lang = 'es'})
	eq(join(mock.props.alang), 'es,spa,es-ES,es-419,ja,jpn', 'alang')
	eq(join(mock.props.slang), 'es,spa,es-ES,es-419', 'slang')
	eq(mock.props[SWMA], false, 'subs-with-matching-audio (no, a flag natively)')
	eq(sets_of(SWMA), 'no', 'set as mpv takes it')
	eq(#mock.logs.warn, 0, 'warnings')
end)

test('start: an alang of yours (any source) is kept, the other two set', function()
	load({lang = 'es', values = {alang = {'ja'}}})
	eq(join(mock.props.alang), 'ja', 'alang untouched')
	eq(native_sets_of('alang'), 0, 'alang never set')
	eq(join(mock.props.slang), 'es,spa,es-ES,es-419', 'slang')
	eq(mock.props[SWMA], false, 'swma')
end)

test('start: subs-with-matching-audio=forced of yours is kept', function()
	load({values = {[SWMA] = 'forced'}})
	eq(mock.props[SWMA], 'forced', 'kept')
	eq(sets_of(SWMA), '', 'never set')
end)

test('start: the default value written on the command line is yours', function()
	load({cmdline = {slang = true}})
	eq(join(mock.props.slang), '', 'slang= on the command line kept')
	eq(native_sets_of('slang'), 0, 'slang never set')
	eq(join(mock.props.alang), 'es,spa,es-ES,es-419,ja,jpn', 'alang set')
end)

test('start: the default value written in mpv.conf is yours', function()
	load({conf = 'subs-with-matching-audio=yes\n'})
	eq(mock.props[SWMA], true, 'yes kept')
	eq(sets_of(SWMA), '', 'never set')
	eq(join(mock.props.alang), 'es,spa,es-ES,es-419,ja,jpn', 'alang set')
end)

test('start: an option this mpv does not report is left alone', function()
	local m = load({unknown = {slang = true}})
	eq(m.managed.slang, false, 'slang')
	eq(m.managed.alang, true, 'alang')
	eq(native_sets_of('slang'), 0, 'slang never set')
end)

test('start: a failed set is a warning, not an error', function()
	local m = load({fail = {[SWMA] = true}})
	eq(#mock.logs.warn, 1, 'one warning')
	assert(mock.logs.warn[1]:find(SWMA, 1, true), mock.logs.warn[1])
	eq(m.applied[SWMA], nil, 'not recorded as set')
end)

-- mpv.conf -------------------------------------------------------------------

test('mpv.conf: the ways mpv reads a line', function()
	local m = load()
	local found = m.conf_options(table.concat({
		'\239\187\191alang=ja',                 -- after a BOM
		'  --slang = es # mine',                -- --, blanks, comment
		'no-subs-with-matching-audio',          -- a choice with no
	}, '\r\n'))
	eq(found.alang, true, 'alang')
	eq(found.slang, true, 'slang')
	eq(found[SWMA], true, 'swma')
end)

test('mpv.conf: list actions count, other options do not', function()
	local m = load()
	eq(m.conf_options('alang-append=ja\n').alang, true, 'alang-append')
	eq(m.conf_options('slang-clr\n').slang, true, 'slang-clr')
	eq(m.conf_options('alangs=ja\nvlang=ja\nsubs-with-matching-audio-x=1\n').alang, nil, 'alangs')
	eq(next(m.conf_options('vlang=ja\nsubs-fallback=yes\nsecondary-slang=en\n')), nil, 'others')
end)

test('mpv.conf: comments, the hikari block and profiles do not count', function()
	local m = load()
	local found = m.conf_options(table.concat({
		'# alang=ja',
		'#slang=es',
		'# hikari: subs-with-matching-audio=no',
		'# >>> hikari (managed block, do not edit) >>>',
		'alang=ja',
		'# <<< hikari <<<',
		'[anime]',
		'slang=es',
		'[default]',
		'',
	}, '\n'))
	eq(next(found), nil, 'nothing')
	eq(m.conf_options('[anime]\nalang=ja\n[default]\nslang=es\n').slang, true, '[default] is the top level')
	eq(m.conf_options('[anime]\nalang=ja\n').alang, nil, 'inside a profile')
end)

test('mpv.conf: no file, or not a string, finds nothing', function()
	local m = load()
	eq(next(m.conf_options(nil)), nil, 'nil')
	eq(next(m.user_conf_options()), nil, 'no mpv.conf')
	mock.config_files['mpv.conf'] = '/nonexistent/hikari/mpv.conf'
	eq(next(m.user_conf_options()), nil, 'unreadable')
end)

test('mpv.conf: the user\'s recipe of the docs keeps all three', function()
	load({
		values = {alang = {'spa', 'es', 'es-ES', 'ja', 'jpn'}, slang = {'spa', 'es', 'es-ES'}, [SWMA] = false},
		conf = 'alang=spa,es,es-ES,ja,jpn\nslang=spa,es,es-ES\nsubs-with-matching-audio=no\n',
	})
	eq(native_sets_of('alang') + native_sets_of('slang'), 0, 'lists never set')
	eq(sets_of(SWMA), '', 'swma never set')
	eq(join(mock.props.alang), 'spa,es,es-ES,ja,jpn', 'alang')
end)

-- Language switch ------------------------------------------------------------

test('switch: new recipe, no file playing: nothing is reselected', function()
	load({lang = 'es'})
	mock.sets = {}
	mock.set_script_opt('hikari-language', 'en')
	eq(join(mock.props.alang), 'en,eng,en-US,en-GB,ja,jpn', 'alang')
	eq(join(mock.props.slang), 'en,eng,en-US,en-GB', 'slang')
	eq(sets_of('aid') .. sets_of('sid'), '', 'no track touched')
end)

test('switch: a file playing with mpv\'s choice: audio, then subtitles, picked again', function()
	local m = load({lang = 'es'})
	play(m, 2, false)
	mock.set_script_opt('hikari-language', 'en')
	local order = {}
	for _, s in ipairs(mock.sets) do order[#order + 1] = s[1] .. '=' .. tostring(s[2]) end
	eq(table.concat(order, ' '), 'aid=2 aid=auto sid=no sid=auto', 'the current track, then auto')
end)

test('switch: tracks you picked stay', function()
	local m = load({lang = 'es'})
	play(m, 2, 1)
	mock.props['options/aid'] = 2
	mock.props['options/sid'] = 1
	mock.set_script_opt('hikari-language', 'en')
	eq(sets_of('aid') .. sets_of('sid'), '', 'untouched')
	eq(join(mock.props.slang), 'en,eng,en-US,en-GB', 'the languages still change')
end)

test('switch: only the subtitles picked again when the audio was picked by hand', function()
	local m = load({lang = 'es'})
	play(m, 1, false)
	mock.props['options/aid'] = 1
	mock.set_script_opt('hikari-language', 'en')
	eq(sets_of('aid'), '', 'audio')
	eq(sets_of('sid'), 'no auto', 'subtitles')
end)

test('switch: alang yours: only subtitles picked again, alang untouched', function()
	local m = load({lang = 'es', values = {alang = {'ja'}}})
	play(m, 1, false)
	mock.set_script_opt('hikari-language', 'en')
	eq(join(mock.props.alang), 'ja', 'alang')
	eq(sets_of('aid'), '', 'audio')
	eq(sets_of('sid'), 'no auto', 'subtitles')
end)

test('switch: all three yours: nothing at all', function()
	local m = load({lang = 'es', values = {alang = {'ja'}, slang = {'en'}, [SWMA] = 'forced'}})
	play(m, 1, false)
	mock.set_script_opt('hikari-language', 'en')
	eq(#mock.sets + #mock.native_sets, 0, 'no set')
end)

test('switch: with lavfi-complex the tracks are not touched', function()
	local m = load({lang = 'es'})
	play(m, 1, false)
	mock.props['lavfi-complex'] = '[aid1] [aid2] amix [ao]'
	mock.set_script_opt('hikari-language', 'en')
	eq(sets_of('aid') .. sets_of('sid'), '', 'untouched')
end)

test('switch: after the file ends, nothing is reselected', function()
	local m = load({lang = 'es'})
	play(m, 1, false)
	mock.events['end-file']()
	mock.set_script_opt('hikari-language', 'en')
	eq(sets_of('aid') .. sets_of('sid'), '', 'untouched')
end)

test('switch: an option changed by someone else since is skipped, the rest set', function()
	load({lang = 'es'})
	mock.props.slang = {'fr'}   -- `set slang fr` in the console
	mock.set_script_opt('hikari-language', 'en')
	eq(join(mock.props.slang), 'fr', 'slang kept')
	eq(join(mock.props.alang), 'en,eng,en-US,en-GB,ja,jpn', 'alang')
end)

test('switch: once it holds hikari\'s value again (a profile restored it), it follows again', function()
	load({lang = 'es'})
	local hikari_slang = mock.props.slang
	mock.props.slang = {'fr'}
	mock.set_script_opt('hikari-language', 'en')
	mock.props.slang = hikari_slang
	mock.set_script_opt('hikari-language', 'de')
	eq(join(mock.props.slang), 'de,ger,deu,de-DE', 'slang')
end)

test('switch: to the same language changes nothing', function()
	load({lang = 'es'})
	mock.sets, mock.native_sets = {}, {}
	mock.set_script_opt('hikari-language', 'es')
	mock.set_script_opt('other-option', 'x')
	eq(#mock.sets + #mock.native_sets, 0, 'no set')
end)

test('switch: no language chosen follows the system language', function()
	local m = load({lang = 'auto'})
	-- The system language of whoever runs the tests: whatever it is, the recipe
	-- matches hikari's language.
	eq(join(mock.props.slang), join(m.recipe(m.i18n.language()).slang), 'slang')
end)

-- Reselect ---------------------------------------------------------------------

test('reselect: an empty answer from mpv does nothing', function()
	local m = load()
	mock.props['options/aid'] = 'auto'
	mock.props.aid = nil
	mock.sets = {}
	eq(m.reselect('aid'), false, 'result')
	eq(#mock.sets, 0, 'sets')
end)

for _, path in ipairs(tmp_files) do os.remove(path) end
print(string.format('\n%d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
