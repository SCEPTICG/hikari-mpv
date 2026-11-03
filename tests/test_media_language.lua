-- Run from the repository root: lua tests/test_media_language.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/hikari-media-language.lua'
local SCRIPT_NAME = 'hikari_media_language'
-- The entries of the language menu.
local CODES = {'en', 'es-ES', 'es-419', 'de', 'fr', 'it', 'pl', 'pt-BR', 'pt-PT', 'ro', 'ru', 'tr', 'uk', 'zh-HK', 'zh-hans'}
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
--   animejanai: the text of ~~/mpv-animejanai.conf (none by default)
--   etc_conf: the text of the mpv.conf that mp.find_config_file would find
--            (/etc/mpv/mpv.conf when there is no ~~/mpv.conf)
--   unknown: option name -> true when this mpv gives no option-info for it
--   fail:    option name -> true when mp.set_property fails for it
--   series:  the path of ~~/hikari-tracks.json (none by default)
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
	if setup.conf then
		local path = conf_file(setup.conf)
		mock.expand['~~/mpv.conf'] = path
		mock.files[path] = {is_file = true, is_dir = false}
	end
	if setup.animejanai then
		local path = conf_file(setup.animejanai)
		mock.expand['~~/mpv-animejanai.conf'] = path
		mock.files[path] = {is_file = true, is_dir = false}
	end
	if setup.etc_conf then mock.config_files['mpv.conf'] = conf_file(setup.etc_conf) end
	for name in pairs(setup.fail or {}) do mock.set_fails[name] = true end
	mock.expand['~~/hikari-tracks.json'] = setup.series
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

test('codes: every entry of the language menu has its list, and nothing else does', function()
	local i18n = load().i18n
	local n = 0
	for code in pairs(i18n.MEDIA_LANGUAGES) do
		n = n + 1
		assert(i18n.is_variant(code), code .. ' is not an entry of the menu')
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

test('codes: each list starts with its own code (variants with their region), Chinese with its script', function()
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
	eq(join(m.recipe('es-ES').alang), 'es-ES,es,spa,es-419,es-MX,ja,jpn', 'es-ES')
	eq(join(m.recipe('es-419').alang), 'es-419,es,spa,es-MX,es-ES,ja,jpn', 'es-419')
	eq(join(m.recipe('pt-BR').alang), 'pt-BR,pt,por,pt-PT,ja,jpn', 'pt-BR')
	eq(join(m.recipe('pt-PT').alang), 'pt-PT,pt,por,pt-BR,ja,jpn', 'pt-PT')
	eq(join(m.recipe('de').slang), 'de,ger,deu,de-DE', 'de')
	eq(join(m.recipe('zh-HK').slang), 'zh-Hant,zh-HK,zh-TW,zh,chi,zho,zh-Hans,zh-CN', 'zh-HK')
	eq(join(m.recipe('zh-hans').slang), 'zh-Hans,zh-CN,zh,chi,zho,zh-Hant,zh-TW', 'zh-hans')
end)

test('recipe: English is the same recipe in English; an unknown code falls back to it', function()
	local m = load()
	eq(join(m.recipe('en').alang), 'en,eng,en-US,en-GB,ja,jpn', 'alang')
	eq(join(m.recipe('en').slang), 'en,eng,en-US,en-GB', 'slang')
	eq(m.recipe('en')[SWMA], 'forced', 'swma')
	eq(join(m.recipe('xx').slang), 'en,eng,en-US,en-GB', 'unknown')
end)

test('recipe: returns fresh lists (changing one leaves the table alone)', function()
	local m = load()
	local r = m.recipe('es-ES')
	r.alang[1] = 'xx'
	r.slang[1] = 'xx'
	eq(m.i18n.MEDIA_LANGUAGES['es-ES'][1], 'es-ES', 'table')
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
	eq(join(mock.props.alang), 'es-ES,es,spa,es-419,es-MX,ja,jpn', 'alang')
	eq(join(mock.props.slang), 'es-ES,es,spa,es-419,es-MX', 'slang')
	eq(mock.props[SWMA], 'forced', 'subs-with-matching-audio')
	eq(sets_of(SWMA), 'forced', 'set as mpv takes it')
	eq(#mock.logs.warn, 0, 'warnings')
end)

test('start: an alang of yours (any source) is kept, the other two set', function()
	load({lang = 'es', values = {alang = {'ja'}}})
	eq(join(mock.props.alang), 'ja', 'alang untouched')
	eq(native_sets_of('alang'), 0, 'alang never set')
	eq(join(mock.props.slang), 'es-ES,es,spa,es-419,es-MX', 'slang')
	eq(mock.props[SWMA], 'forced', 'swma')
end)

test('start: subs-with-matching-audio of yours is kept, slang still set', function()
	local m = load({values = {[SWMA] = false}})
	eq(mock.props[SWMA], false, 'no kept')
	eq(sets_of(SWMA), '', 'never set')
	eq(m.managed.slang, true, 'slang managed')
	eq(join(mock.props.slang), 'es-ES,es,spa,es-419,es-MX', 'slang')
end)

test('start: a slang of yours takes subs-with-matching-audio with it', function()
	local m = load({values = {slang = {'en'}}})
	eq(m.managed[SWMA], false, 'swma not managed')
	eq(mock.props[SWMA], true, 'mpv default kept')
	eq(sets_of(SWMA), '', 'never set')
	eq(join(mock.props.slang), 'en', 'slang kept')
	eq(join(mock.props.alang), 'es-ES,es,spa,es-419,es-MX,ja,jpn', 'alang still set')
	local logged = table.concat(mock.logs.info, '\n')
	assert(logged:find(SWMA .. ' left to you: slang is yours', 1, true), logged)
end)

test('start: slang= in mpv.conf (the default value) takes subs-with-matching-audio too', function()
	local m = load({conf = 'slang=\n'})
	eq(m.managed.slang, false, 'slang')
	eq(m.managed[SWMA], false, 'swma')
	eq(sets_of(SWMA), '', 'never set')
	eq(m.managed.alang, true, 'alang')
end)

test('switch: slang yours: subs-with-matching-audio stays out after a switch too', function()
	local m = load({lang = 'es', values = {slang = {'en'}}})
	play(m, 1, false)
	mock.set_script_opt('hikari-language', 'en')
	eq(sets_of(SWMA), '', 'never set')
	eq(mock.props[SWMA], true, 'mpv default kept')
	eq(join(mock.props.alang), 'en,eng,en-US,en-GB,ja,jpn', 'alang follows')
end)

test('start: the value in the log has no control characters', function()
	load({values = {alang = {'ja\n[fake] line\27'}}})
	local logged = table.concat(mock.logs.info, '|')
	assert(logged:find('already set (ja?[fake] line?)', 1, true), logged)
	assert(not logged:find('%c'), 'control character in the log')
end)

test('start: the default value written on the command line is yours', function()
	load({cmdline = {slang = true}})
	eq(join(mock.props.slang), '', 'slang= on the command line kept')
	eq(native_sets_of('slang'), 0, 'slang never set')
	eq(sets_of(SWMA), '', 'swma goes with slang')
	eq(join(mock.props.alang), 'es-ES,es,spa,es-419,es-MX,ja,jpn', 'alang set')
end)

test('start: the default value written in mpv.conf is yours', function()
	load({conf = 'subs-with-matching-audio=yes\n'})
	eq(mock.props[SWMA], true, 'yes kept')
	eq(sets_of(SWMA), '', 'never set')
	eq(join(mock.props.alang), 'es-ES,es,spa,es-419,es-MX,ja,jpn', 'alang set')
end)

test('start: an option this mpv does not report is left alone', function()
	local m = load({unknown = {slang = true}})
	eq(m.managed.slang, false, 'slang')
	eq(m.managed.alang, true, 'alang')
	eq(native_sets_of('slang'), 0, 'slang never set')
	eq(m.managed[SWMA], false, 'swma goes with slang')
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
	mock.expand['~~/mpv.conf'] = '/nonexistent/hikari/mpv.conf'
	mock.files['/nonexistent/hikari/mpv.conf'] = {is_file = true}
	eq(next(m.user_conf_options()), nil, 'unreadable')
end)

test('mpv.conf: only ~~/mpv.conf, never the one in /etc/mpv', function()
	local m = load({etc_conf = 'subs-with-matching-audio=yes\n'})
	eq(m.managed[SWMA], true, 'swma managed')
	eq(mock.props[SWMA], 'forced', 'swma set')
	eq(next(m.user_conf_options()), nil, 'nothing found')
end)

test('mpv.conf: a folder called mpv.conf is not read', function()
	local m = load()
	local dir = os.tmpname()
	os.remove(dir)
	assert(os.execute('mkdir ' .. dir))
	mock.expand['~~/mpv.conf'] = dir
	mock.files[dir] = {is_file = false, is_dir = true}
	eq(next(m.user_conf_options()), nil, 'nothing found')
	os.remove(dir)
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
	eq(join(mock.props.slang), join(m.recipe(m.i18n.variant()).slang), 'slang')
end)


-- AnimeJaNai -----------------------------------------------------------------

-- What AnimeJaNai's mpv-animejanai.conf comes with (the lines that matter).
local ANIMEJANAI = table.concat({
	'# AnimeJaNai',
	'vo=gpu-next',
	"alang = 'jpn'",
	"slang = 'eng'",
	'[upscale-off]',
	'alang=eng',
	'',
}, '\r\n')
local ANIMEJANAI_VALUES = {alang = {'jpn'}, slang = {'eng'}}

test('mpv.conf values: as mpv reads them', function()
	local m = load()
	eq(m.conf_value(" = 'jpn'"), 'jpn', 'single quotes')
	eq(m.conf_value('="a b" # c'), 'a b', 'double quotes, comment after')
	eq(m.conf_value('= jpn # x'), 'jpn', 'bare, comment')
	eq(m.conf_value('=jpn,eng'), 'jpn,eng', 'list')
	eq(m.conf_value('='), '', 'empty')
	eq(m.conf_value(''), nil, 'no value')
	eq(m.conf_value('=%3%jpn'), false, 'length quoting: not read')
	eq(m.conf_value("= 'jpn"), false, 'missing quote')
	eq(m.conf_value("= 'jpn' x"), false, 'something after the quotes')
	eq(m.conf_value('=  ja , jpn  \t # x'), 'ja , jpn', 'blanks inside kept, around cut')
	eq(m.conf_value('=   \t  '), '', 'only blanks')
	eq(m.conf_value('= #x'), '', 'only a comment')
end)

test('mpv.conf values: a line of 40000 blanks is read at once', function()
	local m = load()
	local started = os.clock()
	eq(m.conf_value('=a' .. string.rep(' ', 40000) .. 'b'), 'a' .. string.rep(' ', 40000) .. 'b', 'blanks inside')
	eq(m.conf_value('=' .. string.rep(' ', 40000) .. 'x' .. string.rep(' ', 40000)), 'x', 'blanks around')
	eq(m.conf_value('=x' .. string.rep(' \t', 40000)), 'x', 'blanks after')
	local found = m.conf_lines('alang=ja' .. string.rep(' ', 40000) .. '\n')
	eq(found[1] and found[1].value, 'ja', 'in mpv.conf')
	assert(os.clock() - started < 1, 'took ' .. (os.clock() - started) .. ' s')
end)

test('AnimeJaNai: its own alang and slang are not yours: hikari\'s recipe', function()
	local m = load({lang = 'es-ES', values = ANIMEJANAI_VALUES, animejanai = ANIMEJANAI})
	eq(m.managed.alang, true, 'alang'); eq(m.managed.slang, true, 'slang'); eq(m.managed[SWMA], true, 'swma')
	eq(join(mock.props.alang), 'es-ES,es,spa,es-419,es-MX,ja,jpn', 'alang')
	eq(join(mock.props.slang), 'es-ES,es,spa,es-419,es-MX', 'slang')
	eq(mock.props[SWMA], 'forced', 'swma')
	eq(m.animejanai_conf_defaults().alang, true, 'read from ~~/mpv-animejanai.conf')
end)

test('AnimeJaNai: the ways its lines may be written', function()
	local m = load()
	eq(m.animejanai_defaults('alang=jpn\n--slang = "eng" # mine\n').slang, true, 'quotes, --, comment')
	eq(m.animejanai_defaults('\239\187\191alang = \'jpn\'\n').alang, true, 'BOM')
	eq(m.animejanai_defaults('# alang = \'eng\'\nalang = \'jpn\'\n[p]\nalang-append=eng\n').alang, true,
		'comments and profiles do not count')
	eq(next(m.animejanai_defaults(nil)), nil, 'no file')
end)

test('AnimeJaNai: lines you changed are yours', function()
	local m = load()
	local cases = {
		"alang = 'jpn,eng'", "alang = 'eng'", "alang = 'jpn'\nalang-append = 'eng'", "alang = 'jpn'\nalang = 'jpn'",
		"alang-set = 'jpn'", "alang = %3%jpn", "alang = 'JPN'",
	}
	for _, text in ipairs(cases) do eq(m.animejanai_defaults(text).alang, nil, text) end
	eq(m.animejanai_defaults("alang = 'jpn'").slang, nil, 'slang not in the file')
end)

test('AnimeJaNai: a value that is not the file\'s (set somewhere else) is yours', function()
	local m = load({values = {alang = {'jpn', 'eng'}, slang = {'eng'}}, animejanai = ANIMEJANAI})
	eq(m.managed.alang, false, 'alang')
	eq(m.managed.slang, true, 'slang still AnimeJaNai\'s')
	eq(join(mock.props.alang), 'jpn,eng', 'alang kept')
end)

test('AnimeJaNai: your own line in mpv.conf or on the command line still wins', function()
	local m = load({values = ANIMEJANAI_VALUES, animejanai = ANIMEJANAI, conf = 'alang=jpn\n', cmdline = {slang = true}})
	eq(m.managed.alang, false, 'alang in mpv.conf')
	eq(m.managed.slang, false, 'slang on the command line')
	eq(join(mock.props.alang), 'jpn', 'kept')
	eq(join(mock.props.slang), 'eng', 'kept')
end)

test('AnimeJaNai: without its file, jpn and eng are values like any other', function()
	local m = load({values = ANIMEJANAI_VALUES})
	eq(m.managed.alang, false, 'alang'); eq(m.managed.slang, false, 'slang')
end)

test('AnimeJaNai: the file is only read, never written', function()
	local path
	load({values = ANIMEJANAI_VALUES, animejanai = ANIMEJANAI})
	path = mock.expand['~~/mpv-animejanai.conf']
	local f = assert(io.open(path, 'rb'))
	eq(f:read('*a'), ANIMEJANAI, 'unchanged')
	f:close()
	local src = assert(io.open(SCRIPT, 'rb')):read('*a')
	-- The one file opened for writing is the temporary file of the list of
	-- tracks per series (write_series).
	local writes = 0
	for call in src:gmatch("io%.open%([^)]*'w[^)]*%)") do
		writes = writes + 1
		eq(call, "io.open(tmp, 'wb')", 'opened for writing')
	end
	eq(writes, 1, 'files opened for writing')
end)

-- Newer AnimeJaNai: its lines live in an [animejanai] profile that mpv.conf
-- applies (the lines that matter).
local ANIMEJANAI_PROFILE = table.concat({
	'# AnimeJaNai managed settings - DO NOT EDIT.',
	'profile-restore=copy-equal',
	'[animejanai]',
	'vo=gpu-next',
	'profile=high-quality',
	"alang = 'jpn'",
	"slang = 'eng'",
	'profile=upscale-on',
	'[extension.gif]',
	'loop-file=inf',
	'[upscale-off]',
	'vf=""',
	'[upscale-on]',
	'vf=@aji:animejanai',
	'',
}, '\r\n')
local ANIMEJANAI_MPV_CONF = 'include="~~/mpv-animejanai.conf"\r\nprofile = animejanai\r\n'

test('AnimeJaNai profile: applied by mpv.conf, its alang and slang are not yours', function()
	local m = load({lang = 'es-ES', values = ANIMEJANAI_VALUES, animejanai = ANIMEJANAI_PROFILE,
		conf = ANIMEJANAI_MPV_CONF})
	eq(m.managed.alang, true, 'alang'); eq(m.managed.slang, true, 'slang'); eq(m.managed[SWMA], true, 'swma')
	eq(join(mock.props.alang), 'es-ES,es,spa,es-419,es-MX,ja,jpn', 'alang')
	eq(join(mock.props.slang), 'es-ES,es,spa,es-419,es-MX', 'slang')
end)

test('AnimeJaNai profile: applied by mpv-animejanai.conf itself', function()
	local m = load({lang = 'es-ES', values = ANIMEJANAI_VALUES,
		animejanai = 'profile=animejanai\n' .. ANIMEJANAI_PROFILE})
	eq(m.managed.alang, true, 'alang'); eq(m.managed.slang, true, 'slang')
	eq(join(mock.props.slang), 'es-ES,es,spa,es-419,es-MX', 'slang')
end)

test('AnimeJaNai profile: the ways a profile line may name it', function()
	local m = load()
	local yes = {
		'profile=animejanai', 'profile = animejanai', "--profile = 'animejanai' # x", 'profile="gpu-hq,animejanai"',
		'profile=animejanai,upscale-on', '[x]\nfoo=1\n[default]\nprofile=animejanai',
	}
	for _, text in ipairs(yes) do eq(m.applies_profile(text, 'animejanai'), true, text) end
	local no = {
		'# profile = animejanai', 'profile=animejanai2', 'profile=gpu-hq, animejanai', 'profile-append=animejanai',
		'[animejanai]\nprofile=animejanai', '[x]\nprofile=animejanai', 'profile=%10%animejanai', 'profile',
		'# >>> hikari\nprofile=animejanai\n# <<< hikari',
	}
	for _, text in ipairs(no) do eq(m.applies_profile(text, 'animejanai'), false, text) end
	eq(m.applies_profile(nil, 'animejanai'), false, 'no file')
end)

test('AnimeJaNai profile: nobody applies it, so its lines are yours', function()
	local m = load({values = ANIMEJANAI_VALUES, animejanai = ANIMEJANAI_PROFILE, conf = 'include="~~/mpv-animejanai.conf"\n'})
	eq(m.managed.alang, false, 'alang'); eq(m.managed.slang, false, 'slang')
	eq(join(mock.props.slang), 'eng', 'kept')
	eq(next(m.animejanai_defaults(ANIMEJANAI_PROFILE)), nil, 'not applied: nothing')
end)

test('AnimeJaNai profile: a line in another section does not count', function()
	local m = load()
	eq(m.animejanai_defaults("[upscale-on]\nslang = 'eng'\n", true).slang, nil, 'in [upscale-on]')
	eq(m.animejanai_defaults("[subs-gpu]\nslang = 'eng'\n[extension.gif]\nalang = 'jpn'\n", true).alang, nil,
		'in [extension.gif]')
	eq(m.animejanai_defaults("[animejanai]\nslang = 'eng'\n[upscale-on]\nslang = 'eng'\n", true).slang, true,
		'only the one in [animejanai] counts')
	m = load({values = ANIMEJANAI_VALUES, conf = ANIMEJANAI_MPV_CONF,
		animejanai = "profile=animejanai\n[upscale-on]\nalang = 'jpn'\nslang = 'eng'\n"})
	eq(m.managed.alang, false, 'alang'); eq(m.managed.slang, false, 'slang')
end)

test('AnimeJaNai profile: one line at the top and one in [animejanai] are yours', function()
	local m = load({values = ANIMEJANAI_VALUES, conf = ANIMEJANAI_MPV_CONF,
		animejanai = "slang = 'eng'\n" .. ANIMEJANAI_PROFILE})
	eq(m.managed.slang, false, 'slang twice')
	eq(m.managed.alang, true, 'alang once')
	eq(join(mock.props.slang), 'eng', 'kept')
end)

test('AnimeJaNai profile: your own line in mpv.conf still wins', function()
	local m = load({values = ANIMEJANAI_VALUES, animejanai = ANIMEJANAI_PROFILE,
		conf = ANIMEJANAI_MPV_CONF .. 'slang = eng\n'})
	eq(m.managed.slang, false, 'slang in mpv.conf')
	eq(m.managed.alang, true, 'alang still AnimeJaNai\'s')
	eq(join(mock.props.slang), 'eng', 'kept')
end)

test('AnimeJaNai profile: the older form still works with mpv.conf applying the profile', function()
	local m = load({lang = 'es-ES', values = ANIMEJANAI_VALUES, animejanai = ANIMEJANAI, conf = ANIMEJANAI_MPV_CONF})
	eq(m.managed.alang, true, 'alang'); eq(m.managed.slang, true, 'slang')
end)

-- Regional variants ----------------------------------------------------------

test('variants: the variant of a track, by tag, then title, then bare Spanish as Spain\'s', function()
	local m = load()
	local cases = {
		{'es', 'CR_Spanish(Latin_America)', 'es-419'}, {'es', 'Spanish(Latin_America)', 'es-419'},
		{'es', 'CR_Spanish', 'es-ES'}, {'es', 'Spanish', 'es-ES'}, {'es', nil, 'es-ES'}, {'spa', '', 'es-ES'},
		{'es', 'Español (España)', 'es-ES'}, {'es', 'ESPAÑA', 'es-ES'}, {'spa', 'Castilian', 'es-ES'},
		{'es', 'Castellano', 'es-ES'}, {'es', '[ESP] Subs', 'es-ES'}, {'es', 'European Spanish', 'es-ES'},
		{'es', 'Español Latino', 'es-419'}, {'es', 'LATAM', 'es-419'}, {'es', 'Español (AMÉRICA)', 'es-419'},
		{'es', 'Spanish (419)', 'es-419'}, {'es-419', 'Spanish', 'es-419'}, {'es-MX', nil, 'es-419'},
		{'es-AR', 'Castellano', 'es-419'}, {'es-ES', 'Latino', 'es-ES'}, {'spa-ES', nil, 'es-ES'},
		{'es', 'Spain and Latin America', nil},
	}
	for _, c in ipairs(cases) do
		eq(m.track_variant({lang = c[1], title = c[2]}, 'es'), c[3], tostring(c[1]) .. ' ' .. tostring(c[2]))
	end
	local pt = {
		{'pt-BR', 'Portuguese', 'pt-BR'}, {'pt', 'Brazilian Portuguese', 'pt-BR'}, {'por', 'Portuguese (BR)', 'pt-BR'},
		{'pt', 'Português (Brasil)', 'pt-BR'}, {'pt', 'Portuguese (Portugal)', 'pt-PT'}, {'pt-PT', nil, 'pt-PT'},
		{'pt-AO', nil, 'pt-PT'}, {'pt', 'European Portuguese', 'pt-PT'}, {'pt', 'Portuguese', nil},
		{'pt', 'Bravo', nil}, {'pt', 'BRA', nil},
	}
	for _, c in ipairs(pt) do
		eq(m.track_variant({lang = c[1], title = c[2]}, 'pt'), c[3], tostring(c[1]) .. ' ' .. tostring(c[2]))
	end
end)

test('variants: which tracks are in the language', function()
	local m = load()
	for _, lang in ipairs({'es', 'spa', 'es-419', 'ES', 'es-ES', 'spa-ES'}) do
		eq(m.in_language({lang = lang}, 'es'), true, lang)
	end
	for _, lang in ipairs({'en', 'eng', 'pt', 'esp', 'est', ''}) do eq(m.in_language({lang = lang}, 'es'), false, lang) end
	eq(m.in_language({}, 'es'), false, 'no tag')
	eq(m.in_language({lang = 'por'}, 'pt'), true, 'por')
end)

-- A Crunchyroll release: Japanese audio and its nine subtitle tracks, both
-- Spanish ones tagged `es`, the Latin American one first.
local function crunchyroll(latin_tag)
	return {
		{id = 1, type = 'video', lang = nil},
		{id = 1, type = 'audio', lang = 'ja', title = 'Japanese', default = true},
		{id = 1, type = 'sub', lang = 'en', title = 'CR_English', default = true},
		{id = 2, type = 'sub', lang = 'pt-BR', title = 'CR_Portuguese(Brazil)'},
		{id = 3, type = 'sub', lang = latin_tag or 'es', title = 'CR_Spanish(Latin_America)'},
		{id = 4, type = 'sub', lang = 'es', title = 'CR_Spanish'},
		{id = 5, type = 'sub', lang = 'ar', title = 'CR_Arabic'},
		{id = 6, type = 'sub', lang = 'fr', title = 'CR_French'},
		{id = 7, type = 'sub', lang = 'de', title = 'CR_German'},
		{id = 8, type = 'sub', lang = 'it', title = 'CR_Italian'},
		{id = 9, type = 'sub', lang = 'ru', title = 'CR_Russian'},
	}
end

-- Plays a file with `tracks`; mpv's own picks are `picks` (property -> id, or
-- a function of the property); options `auto` unless `options` says.
local function play_tracks(m, tracks, picks, options)
	mock.tracks = tracks
	mock.pick = function(property)
		local pick = picks[property]
		if type(pick) == 'function' then return pick() end
		return pick or false
	end
	mock.events['start-file']()
	for _, property in ipairs({'aid', 'sid'}) do
		local option = (options or {})[property] or 'auto'
		mock.props['options/' .. property] = option
		if option == 'auto' then
			mock.props[property] = mock.pick(property)
		else
			mock.props[property] = option
		end
	end
	mock.sets = {}
	mock.events['file-loaded']()
	eq(m.is_playing(), true, 'playing')
end

test('variants: Spain, Crunchyroll: mpv takes the Latin American subtitles, hikari Spain\'s', function()
	local m = load({lang = 'es-ES'})
	play_tracks(m, crunchyroll(), {aid = 1, sid = 3})
	eq(mock.props.sid, 4, 'CR_Spanish')
	eq(sets_of('file-local-options/sid'), '4', 'for this file only')
	eq(sets_of('file-local-options/aid'), '', 'audio untouched')
	eq(m.get_switched().sid, 4, 'remembered')
	mock.events['end-file']()
	mock.end_file()
	eq(mock.props['options/sid'], 'auto', 'the next file starts from auto')
end)

test('variants: Spain, Crunchyroll with es-419: the same', function()
	local m = load({lang = 'es-ES'})
	play_tracks(m, crunchyroll('es-419'), {aid = 1, sid = 3})
	eq(mock.props.sid, 4, 'CR_Spanish')
	play_tracks(m, crunchyroll('es-419'), {aid = 1, sid = 4})
	eq(#mock.sets, 0, 'mpv already took Spain\'s: nothing done')
end)

test('variants: Latin America, Crunchyroll: mpv\'s pick stays, or hikari takes the Latin American one', function()
	local m = load({lang = 'es-419'})
	play_tracks(m, crunchyroll(), {aid = 1, sid = 3})
	eq(#mock.sets, 0, 'already the Latin American one')
	play_tracks(m, crunchyroll(), {aid = 1, sid = 4})
	eq(mock.props.sid, 3, 'CR_Spanish(Latin_America)')
	eq(sets_of('file-local-options/sid'), '3', 'switched')
end)

test('variants: only the other variant: it stays (another accent rather than none)', function()
	local tracks = crunchyroll()
	table.remove(tracks, 6) -- no CR_Spanish
	local m = load({lang = 'es-ES'})
	play_tracks(m, tracks, {aid = 1, sid = 3})
	eq(#mock.sets, 0, 'nothing done')
	eq(mock.props.sid, 3, 'Latin American subtitles')
end)

test('variants: other languages and English are never touched', function()
	local m = load({lang = 'en'})
	play_tracks(m, crunchyroll(), {aid = 1, sid = 1})
	eq(#mock.sets, 0, 'English')
	m = load({lang = 'es-ES'})
	play_tracks(m, crunchyroll(), {aid = 1, sid = 1})
	eq(#mock.sets, 0, 'mpv picked English subtitles: not hikari\'s language')
	m = load({lang = 'de'})
	play_tracks(m, crunchyroll(), {aid = 1, sid = 7})
	eq(#mock.sets, 0, 'no variants')
end)

test('variants: a dub of the variant, and its forced signs; never full subtitles instead of signs', function()
	local tracks = {
		{id = 1, type = 'audio', lang = 'ja'},
		{id = 2, type = 'audio', lang = 'es', title = 'Spanish (Latin America)'},
		{id = 3, type = 'audio', lang = 'es', title = 'Spanish'},
		{id = 1, type = 'sub', lang = 'es', title = 'Spanish (Latin America)'},
		{id = 2, type = 'sub', lang = 'es', title = 'Spanish (Latin America) [Signs]', forced = true},
		{id = 3, type = 'sub', lang = 'es', title = 'Spanish'},
		{id = 4, type = 'sub', lang = 'es', title = 'Spanish [Signs]', forced = true},
	}
	local m = load({lang = 'es-ES'})
	play_tracks(m, tracks, {aid = 2, sid = 2})
	eq(mock.props.aid, 3, 'Spain\'s dub')
	eq(mock.props.sid, 4, 'Spain\'s signs')
	-- Without signs of Spain, the Latin American ones stay: not the dialogue.
	table.remove(tracks, 7)
	play_tracks(m, tracks, {aid = 2, sid = 2})
	eq(mock.props.aid, 3, 'Spain\'s dub')
	eq(mock.props.sid, 2, 'Latin American signs kept')
	-- No subtitles picked (no signs at all): none added.
	play_tracks(m, tracks, {aid = 3, sid = false})
	eq(#mock.sets, 0, 'nothing')
end)

test('variants: external subtitles are only swapped for external ones', function()
	local tracks = {
		{id = 1, type = 'audio', lang = 'ja'},
		{id = 1, type = 'sub', lang = 'es', title = 'Spanish'},
		{id = 2, type = 'sub', lang = 'es', title = 'Latino', external = true},
	}
	local m = load({lang = 'es-ES'})
	play_tracks(m, tracks, {aid = 1, sid = 2})
	eq(#mock.sets, 0, 'mpv\'s external pick kept')
end)

test('variants: Portuguese, by tag or title', function()
	local tracks = {
		{id = 1, type = 'audio', lang = 'ja'},
		{id = 1, type = 'sub', lang = 'pt', title = 'Portuguese'},
		{id = 2, type = 'sub', lang = 'pt-BR', title = 'Portuguese'},
		{id = 3, type = 'sub', lang = 'pt', title = 'Português (Portugal)'},
	}
	local m = load({lang = 'pt-BR'})
	play_tracks(m, tracks, {aid = 1, sid = 1})
	eq(mock.props.sid, 2, 'Brazil: the pt-BR track')
	m = load({lang = 'pt-PT'})
	play_tracks(m, tracks, {aid = 1, sid = 1})
	eq(mock.props.sid, 3, 'Portugal: the one titled Portugal')
	m = load({lang = 'pt'})
	play_tracks(m, tracks, {aid = 1, sid = 3})
	eq(mock.props.sid, 2, 'a saved `pt` is Brazil')
end)

test('variants: tracks you picked or fixed stay', function()
	local m = load({lang = 'es-ES'})
	play_tracks(m, crunchyroll(), {aid = 1, sid = 3}, {sid = 3})
	eq(#mock.sets, 0, '--sid=3, the menu or a resumed position')
	mock.props['lavfi-complex'] = '[aid1] [aid2] amix [ao]'
	play_tracks(m, crunchyroll(), {aid = 1, sid = 3})
	eq(#mock.sets, 0, 'lavfi-complex')
end)

test('variants: a script of your own that already picked the track wins', function()
	local m = load({lang = 'es-419'})
	mock.tracks = crunchyroll()
	mock.events['start-file']()
	mock.props['options/aid'], mock.props.aid = 'auto', 1
	mock.props['options/sid'], mock.props.sid = 4, 4   -- sub-castellano.lua: `set sid 4`
	mock.sets = {}
	mock.events['file-loaded']()
	eq(#mock.sets, 0, 'untouched')
end)

test('variants: a language switch picks again and checks the variant again', function()
	local m = load({lang = 'es-ES'})
	-- mpv: the first Spanish track for Spanish, English otherwise.
	local function sub_pick()
		return mock.props.slang[1]:sub(1, 2) == 'es' and 3 or 1
	end
	play_tracks(m, crunchyroll(), {aid = 1, sid = sub_pick})
	eq(mock.props.sid, 4, 'Spain')
	mock.sets = {}
	mock.set_script_opt('hikari-language', 'es-419')
	eq(mock.props.sid, 3, 'Latin America: mpv\'s pick again, kept')
	eq(mock.props['options/sid'], 'auto', 'back to auto')
	eq(m.get_switched().sid, nil, 'nothing of hikari left')
	mock.set_script_opt('hikari-language', 'es-ES')
	eq(mock.props.sid, 4, 'Spain again')
	mock.set_script_opt('hikari-language', 'en')
	eq(mock.props.sid, 1, 'English')
	eq(mock.props['options/sid'], 'auto', 'auto')
end)

test('variants: mpv\'s rank of a tag against a list, as mp_match_lang', function()
	local m = load()
	local MAX = 2147483647
	eq(m.lang_rank({'es-419', 'en'}, 'es-419'), MAX, 'exact, first entry')
	eq(m.lang_rank({'es-419', 'en'}, 'spa'), MAX, 'a bare track matches a longer entry')
	eq(m.lang_rank({'es-419', 'en'}, 'es'), MAX, 'es too')
	eq(m.lang_rank({'es', 'en'}, 'es-419'), MAX - 1000, 'a track with more subtags loses 1000')
	eq(m.lang_rank({'es-ES', 'es'}, 'es-MX'), MAX - 1000, 'another region: 1000, whatever the entry')
	eq(m.lang_rank({'en', 'spa'}, 'es'), MAX - 1, 'second entry; es and spa are one code')
	eq(m.lang_rank({'ja', 'jpn'}, 'jpn'), MAX, 'Japanese')
	eq(m.lang_rank({'ja', 'jpn'}, 'ja-JP'), MAX - 1000, 'Japanese with a region')
	eq(m.lang_rank({'en'}, 'es'), 0, 'no match')
	eq(m.lang_rank({}, 'es'), 0, 'empty list')
	eq(m.lang_rank({'es'}, nil), 0, 'no tag')
	eq(m.lang_rank({'ES-es'}, 'es-ES'), MAX, 'case does not matter')
end)

test('variants: your own slang: only tracks with the same tag are swapped', function()
	-- Reported in review: mpv 0.40, slang=es-419,en in mpv.conf; mpv takes 1.
	local tracks = {
		{id = 1, type = 'audio', lang = 'ja'},
		{id = 1, type = 'sub', lang = 'es-419', title = 'CR_Spanish(Latin_America)'},
		{id = 2, type = 'sub', lang = 'spa', title = 'CR_Spanish'},
	}
	local m = load({lang = 'es-ES', values = {slang = {'es-419', 'en'}}})
	eq(m.managed.slang, false, 'slang yours')
	play_tracks(m, tracks, {aid = 1, sid = 1})
	eq(#mock.sets, 0, 'your list names es-419: kept')
	eq(mock.props.sid, 1, 'Latin America, as your slang says')
	-- Tagged alike (es and spa are one code): hikari's variant decides.
	tracks[2].lang = 'es'
	tracks[3].lang = 'spa'
	play_tracks(m, tracks, {aid = 1, sid = 1})
	eq(mock.props.sid, 2, 'es and spa: Spain\'s')
	-- slang=es: mpv ranks spa over es-419 and took Spain's; Latin America keeps it.
	tracks[2].lang = 'es-419'
	m = load({lang = 'es-419', values = {slang = {'es'}}})
	play_tracks(m, tracks, {aid = 1, sid = 2})
	eq(#mock.sets, 0, 'kept')
end)

test('variants: the same tag for mpv', function()
	local m = load()
	eq(m.same_tag('es', 'spa'), true, 'es, spa')
	eq(m.same_tag('ES', 'es'), true, 'case')
	eq(m.same_tag('spa-ES', 'es-es'), true, 'with a region')
	eq(m.same_tag('es', 'es-419'), false, 'a region more')
	eq(m.same_tag('es-MX', 'es-419'), false, 'another region')
	eq(m.same_tag('pt', 'por'), true, 'pt, por')
	eq(m.same_tag('es', nil), false, 'no tag')
	eq(m.same_tag('', ''), false, 'empty')
end)

test('variants: your own alang: the same for the audio', function()
	local tracks = {
		{id = 1, type = 'audio', lang = 'es-419', title = 'Spanish (Latin America)'},
		{id = 2, type = 'audio', lang = 'spa', title = 'Spanish'},
		{id = 3, type = 'audio', lang = 'ja'},
	}
	local m = load({lang = 'es-ES', values = {alang = {'es-419', 'ja'}}})
	play_tracks(m, tracks, {aid = 1, sid = false})
	eq(#mock.sets, 0, 'your es-419 dub stays')
	tracks[1].lang = 'es'
	play_tracks(m, tracks, {aid = 1, sid = false})
	eq(mock.props.aid, 2, 'tagged alike: Spain\'s dub')
end)

test('variants: hikari\'s slang: any track of the language, whatever its tag', function()
	local tracks = {
		{id = 1, type = 'audio', lang = 'ja'},
		{id = 1, type = 'sub', lang = 'es', title = 'Spanish'},
		{id = 2, type = 'sub', lang = 'es-MX', title = 'Spanish'},
	}
	local m = load({lang = 'es-419'})
	play_tracks(m, tracks, {aid = 1, sid = 1})
	eq(mock.props.sid, 2, 'es-MX, though mpv ranks `es` higher with hikari\'s list')
end)

test('variants: a slang that someone changed since is not hikari\'s', function()
	local tracks = {
		{id = 1, type = 'audio', lang = 'ja'},
		{id = 1, type = 'sub', lang = 'es-419', title = 'CR_Spanish(Latin_America)'},
		{id = 2, type = 'sub', lang = 'spa', title = 'CR_Spanish'},
	}
	local m = load({lang = 'es-ES'})
	mock.props.slang = {'es-419'}   -- `set slang es-419` in the console
	play_tracks(m, tracks, {aid = 1, sid = 1})
	eq(#mock.sets, 0, 'kept, as with your own slang')
end)

test('variants: a switch with all options yours applies the new variant where mpv cannot tell', function()
	local m = load({lang = 'es-ES', values = {alang = {'ja'}, slang = {'es'}, [SWMA] = 'forced'}})
	play_tracks(m, crunchyroll(), {aid = 1, sid = 3})
	eq(mock.props.sid, 4, 'Spain: both `es`, your slang cannot tell them apart')
	mock.set_script_opt('hikari-language', 'es-419')
	eq(mock.props.sid, 3, 'Latin America')
	mock.set_script_opt('hikari-language', 'de')
	eq(mock.props.sid, 3, 'German: mpv\'s own pick back')
	eq(join(mock.props.slang), 'es', 'your slang untouched')
	-- Tagged es-419, your slang=es ranks Spain's first: mpv's pick, kept.
	m = load({lang = 'es-419', values = {alang = {'ja'}, slang = {'es'}, [SWMA] = 'forced'}})
	play_tracks(m, crunchyroll('es-419'), {aid = 1, sid = 4})
	eq(#mock.sets, 0, 'mpv told them apart by your list')
end)

-- A file with Japanese audio and a dub of one variant only, and subtitles of
-- both: mpv (as with hikari's lists) takes the dub and, for subtitles, only a
-- forced track while the audio is in your language, otherwise the first one
-- of the language.
local function one_dub(dub_lang, dub_title)
	return {
		{id = 1, type = 'audio', lang = 'jpn', title = 'Japanese'},
		{id = 2, type = 'audio', lang = dub_lang, title = dub_title},
		{id = 1, type = 'sub', lang = 'spa', title = 'CR_Spanish'},
		{id = 2, type = 'sub', lang = 'spa', title = 'CR_Spanish(Latin_America)'},
	}
end
local function one_dub_picks(tracks)
	return {
		aid = 2,
		sid = function()
			for _, t in ipairs(tracks) do
				if t.type == 'audio' and t.id == mock.props.aid and t.lang ~= 'jpn' then return false end
			end
			return 1
		end,
	}
end

test('variants: a dub of the other variant only: Japanese, with subtitles of your variant', function()
	local tracks = one_dub('spa', 'Spanish(Latin_America)')
	local m = load({lang = 'es-ES'})
	play_tracks(m, tracks, one_dub_picks(tracks))
	eq(mock.props.aid, 1, 'Japanese')
	eq(sets_of('file-local-options/aid'), '1', 'for this file only')
	eq(mock.props.sid, 1, 'full subtitles of Spain, picked again for the Japanese audio')
	eq(mock.props['options/sid'], 'auto', 'still mpv\'s own choice')
	-- By tag, and with Latin American subtitles first.
	tracks = one_dub('es-MX', 'Spanish')
	tracks[3].title, tracks[4].title = 'CR_Spanish(Latin_America)', 'CR_Spanish'
	play_tracks(m, tracks, one_dub_picks(tracks))
	eq(mock.props.aid, 1, 'Japanese (es-MX dub)')
	eq(mock.props.sid, 2, 'Spain\'s subtitles, after mpv\'s first one')
end)

test('variants: the same the other way round, and for Portuguese', function()
	local tracks = one_dub('es-ES', 'Spanish')
	local m = load({lang = 'es-419'})
	play_tracks(m, tracks, one_dub_picks(tracks))
	eq(mock.props.aid, 1, 'Latin America, only Spain\'s dub: Japanese')
	eq(mock.props.sid, 2, 'Latin American subtitles')
	tracks = one_dub('spa', 'Castellano')
	play_tracks(m, tracks, one_dub_picks(tracks))
	eq(mock.props.aid, 1, 'by the title')
	tracks = {
		{id = 1, type = 'audio', lang = 'ja'},
		{id = 2, type = 'audio', lang = 'pt-PT'},
		{id = 1, type = 'sub', lang = 'pt-BR'},
	}
	m = load({lang = 'pt-BR'})
	play_tracks(m, tracks, {aid = 2, sid = function() return mock.props.aid == 1 and 1 or false end})
	eq(mock.props.aid, 1, 'Brazil, only Portugal\'s dub: Japanese')
	eq(mock.props.sid, 1, 'Brazilian subtitles')
end)

test('variants: a dub that may be yours stays', function()
	-- A bare Spanish dub says nothing: kept for Latin America too.
	local tracks = one_dub('spa', '')
	local m = load({lang = 'es-419'})
	play_tracks(m, tracks, one_dub_picks(tracks))
	eq(#mock.sets, 0, 'bare `spa` dub kept')
	-- Both variants: yours is taken, not Japanese.
	tracks = one_dub('es', 'Spanish(Latin_America)')
	table.insert(tracks, 3, {id = 3, type = 'audio', lang = 'es', title = 'Spanish'})
	m = load({lang = 'es-ES'})
	play_tracks(m, tracks, one_dub_picks(tracks))
	eq(mock.props.aid, 3, 'Spain\'s dub')
	-- No Japanese audio: the dub of the other variant stays.
	tracks = one_dub('es-419', 'Spanish')
	tracks[1].lang = 'en'
	play_tracks(m, tracks, one_dub_picks(tracks))
	eq(#mock.sets, 0, 'no original audio to go back to')
	-- Portuguese with no region: either variant.
	tracks = {{id = 1, type = 'audio', lang = 'ja'}, {id = 2, type = 'audio', lang = 'por', title = 'Portuguese'}}
	m = load({lang = 'pt-PT'})
	play_tracks(m, tracks, {aid = 2, sid = false})
	eq(#mock.sets, 0, 'Portuguese that could be Portugal\'s')
end)

test('variants: with your own alang, a dub of the other variant is your choice', function()
	local tracks = one_dub('es-419', 'Spanish(Latin_America)')
	local m = load({lang = 'es-ES', values = {alang = {'es', 'ja'}}})
	play_tracks(m, tracks, one_dub_picks(tracks))
	eq(sets_of('file-local-options/aid') .. sets_of('aid'), '', 'audio untouched')
	-- hikari's alang changed by someone else since: the same.
	m = load({lang = 'es-ES'})
	mock.props.alang = {'es-419', 'ja'}
	play_tracks(m, tracks, one_dub_picks(tracks))
	eq(sets_of('file-local-options/aid') .. sets_of('aid'), '', 'audio untouched')
end)

test('variants: Japanese over the other variant\'s dub after a language switch too', function()
	local tracks = one_dub('es-419', 'Spanish(Latin_America)')
	local m = load({lang = 'es-419'})
	play_tracks(m, tracks, one_dub_picks(tracks))
	eq(#mock.sets, 0, 'Latin America: its dub, no full subtitles')
	eq(mock.props.sid, false, 'none')
	mock.set_script_opt('hikari-language', 'es-ES')
	eq(mock.props.aid, 1, 'Spain: Japanese')
	eq(mock.props.sid, 1, 'Spain\'s full subtitles')
	mock.set_script_opt('hikari-language', 'es-419')
	eq(mock.props.aid, 2, 'Latin America: the dub again')
	eq(mock.props.sid, false, 'no full subtitles again')
end)

test('variants: the original audio, among several Japanese tracks', function()
	local m = load({lang = 'es-ES'})
	local tracks = {
		{id = 1, type = 'audio', lang = 'es-419'},
		{id = 2, type = 'audio', lang = 'ja-JP'},
		{id = 3, type = 'audio', lang = 'jpn', title = 'Commentary'},
		{id = 4, type = 'audio', lang = 'ja', default = true},
		{id = 5, type = 'audio', lang = 'en'},
	}
	eq(m.original_audio(tracks, 1, 'es-ES'), 4, 'best rank, then the default mark')
	tracks[4].default = nil
	eq(m.original_audio(tracks, 1, 'es-ES'), 3, 'then the file\'s order')
	eq(m.original_audio(tracks, 5, 'es-ES'), nil, 'not a dub of the language')
	eq(m.original_audio(tracks, 1, 'es-419'), nil, 'a dub of your variant')
	eq(m.original_audio(tracks, 1, 'de'), nil, 'no variants')
end)

-- Signs and songs without the forced mark ------------------------------------

test('signs: titles that say signs and songs only', function()
	local m = load()
	for _, title in ipairs({'Spanish [Signs]', 'Signs & Songs', 'Carteles', 'Forced', 'Spanish (Forced)',
		'Español (Forzados)', 'CARTELES Y CANCIONES', 'Song lyrics', 'Letreros', 'Legendas forçadas', 'SIGN'}) do
		eq(m.signs_only({type = 'sub', title = title}), true, title)
	end
	for _, title in ipairs({'Spanish', 'Design notes', 'Signos', 'Full', 'Forcedor', '',
		-- Full subtitles that also name signs or songs.
		'Full + Songs', 'English [Full Subs + Songs]', 'Dialogue + Signs', 'Full (Songs Included)',
		'Spanish (non-forced)', 'Spanish (Non Forced)', 'Spanish (nonforced)', 'English (not forced)',
		'Dialog & Songs', 'Castellano [Full + Songs]', 'Diálogos + Carteles', 'DIÁLOGO y canciones',
		'Dialogos y carteles', 'Completos + Carteles', 'Subtítulos completos (canciones)',
		'Legendas completas + letreiros', 'Complete + Signs', 'Español (no forzados)',
		'Português (não forçadas)', 'Portugues (nao forcadas)'}) do
		eq(m.signs_only({type = 'sub', title = title}), false, title)
	end
	eq(m.signs_only({type = 'sub'}), false, 'no title')
	eq(m.signs_only({type = 'audio', title = 'Songs'}), false, 'only subtitles')
	-- Full ones of Spain named with songs, after Latin American ones: Spain's.
	local tracks = {
		{id = 1, type = 'sub', lang = 'es', title = 'Español (Latino)'},
		{id = 2, type = 'sub', lang = 'es', title = 'Castellano [Full + Songs]'},
	}
	eq(m.preferred_track(tracks, 'sub', 1, 'es-ES', false), 2, 'Spain\'s full ones with songs')
	eq(m.preferred_track(tracks, 'sub', 2, 'es-ES', false), nil, 'and they stay')
	-- Full ones with songs and dialogue only: both full, the first stays.
	tracks = {
		{id = 1, type = 'sub', lang = 'es', title = 'Spanish [Full + Songs]'},
		{id = 2, type = 'sub', lang = 'es', title = 'Spanish [Dialogue]'},
	}
	eq(m.preferred_track(tracks, 'sub', 1, 'es-ES', false), nil, 'full with songs kept')
end)

test('signs: full subtitles of the language over a signs track without the mark', function()
	local tracks = {
		{id = 1, type = 'audio', lang = 'ja'},
		{id = 1, type = 'sub', lang = 'es', title = 'Spanish [Signs]'},
		{id = 2, type = 'sub', lang = 'es', title = 'Spanish'},
	}
	local m = load({lang = 'es-ES'})
	play_tracks(m, tracks, {aid = 1, sid = 1})
	eq(mock.props.sid, 2, 'the full ones')
	for _, title in ipairs({'Signs & Songs', 'Carteles', 'Forced'}) do
		tracks[2].title = title
		play_tracks(m, tracks, {aid = 1, sid = 1})
		eq(mock.props.sid, 2, title)
	end
	-- The only Spanish track: kept.
	table.remove(tracks, 3)
	play_tracks(m, tracks, {aid = 1, sid = 1})
	eq(#mock.sets, 0, 'the only one stays')
end)

test('signs: dialogue of the other variant rather than signs of yours', function()
	local tracks = {
		{id = 1, type = 'audio', lang = 'ja'},
		{id = 1, type = 'sub', lang = 'es', title = 'Spanish(Latin_America)'},
		{id = 2, type = 'sub', lang = 'es', title = 'Spanish [Signs]'},
		{id = 3, type = 'sub', lang = 'es', title = 'Latin America [Signs]'},
	}
	local m = load({lang = 'es-ES'})
	play_tracks(m, tracks, {aid = 1, sid = 1})
	eq(#mock.sets, 0, 'Latin American dialogue kept')
	play_tracks(m, tracks, {aid = 1, sid = 3})
	eq(mock.props.sid, 1, 'from Latin American signs to Latin American dialogue')
	-- Signs of both variants and nothing else: yours.
	table.remove(tracks, 2)
	play_tracks(m, tracks, {aid = 1, sid = 3})
	eq(mock.props.sid, 2, 'Spain\'s signs')
	-- Forced ones are compared with forced ones only, the words do not matter.
	tracks = {
		{id = 1, type = 'audio', lang = 'es'},
		{id = 1, type = 'sub', lang = 'es', title = 'Latino [Forced]', forced = true},
		{id = 2, type = 'sub', lang = 'es', title = 'Castellano', forced = true},
	}
	play_tracks(m, tracks, {aid = 1, sid = 1})
	eq(mock.props.sid, 2, 'Spain\'s forced track')
end)

test('variants: a track you pick after hikari\'s switch stays on a language switch', function()
	local m = load({lang = 'es-ES'})
	play_tracks(m, crunchyroll(), {aid = 1, sid = 3})
	eq(mock.props.sid, 4, 'hikari\'s switch')
	mock.props['options/sid'], mock.props.sid = 6, 6   -- French, from the menu
	mock.sets = {}
	mock.set_script_opt('hikari-language', 'es-419')
	eq(sets_of('sid') .. sets_of('file-local-options/sid'), '', 'untouched')
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

-- Per series -------------------------------------------------------------------

-- A new, empty place for ~~/hikari-tracks.json (no file yet).
local function series_file()
	local path = os.tmpname()
	os.remove(path)
	tmp_files[#tmp_files + 1] = path
	return path
end

local function read_text(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	local text = f:read('*a')
	f:close()
	return text
end

local function write_text(path, text)
	local f = assert(io.open(path, 'wb'))
	f:write(text)
	f:close()
end

-- The entry of `key` in the list on disk, or nil.
local function saved(path, key)
	local value = mock.parse_json(read_text(path) or 'null')
	for _, entry in ipairs(type(value) == 'table' and value.series or {}) do
		if entry.key == key then return entry end
	end
	return nil
end

-- What mpv does after a change of the track playing: the observers of
-- `aid`/`sid` run.
-- Like mpv, only when the property changed since the observers last saw it
-- (the first time always, as when an observer is registered).
local notified = setmetatable({}, {__mode = 'k'})
local function notify(property)
	notified[mp] = notified[mp] or {}
	local last, value = notified[mp], tostring(mock.props[property])
	if last[property] == value then return end
	last[property] = value
	for _, fn in ipairs(mock.observers[property] or {}) do fn(property, mock.props[property]) end
end

-- The user picks a track (or `no`) from the menu or with a key: mpv tells the
-- observers of the track playing and of the option, each if it changed.
local function user_picks(property, value)
	mp.set_property(property, tostring(value))
	notify(property)
	notify('options/' .. property)
end

-- Plays the file at `path` (mpv's `path`) as play_tracks does, then lets the
-- observers see what mpv and hikari picked.
local function play_episode(m, path, tracks, picks, options)
	mock.props.path = path
	play_tracks(m, tracks, picks, options)
	notify('aid')
	notify('sid')
end

-- An episode: Japanese audio and a Latin American dub, Spanish subtitles
-- (mpv's pick with hikari's lists for Spain), full English ones and English
-- signs.
local function episode_tracks()
	return {
		{id = 1, type = 'video'},
		{id = 1, type = 'audio', lang = 'ja', title = 'Japanese', default = true},
		{id = 2, type = 'audio', lang = 'es-419', title = 'Spanish (Latin America)'},
		{id = 1, type = 'sub', lang = 'es', title = 'Spanish', default = true},
		{id = 2, type = 'sub', lang = 'en', title = 'English'},
		{id = 3, type = 'sub', lang = 'eng', title = 'English [Signs]'},
	}
end

local FRIEREN = 'sousou no frieren'

test('series: the key is the series name, normalised, without season, also for streams', function()
	local m = load()
	eq(m.series_key('/anime/[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv'), FRIEREN, 'file')
	eq(m.series_key('/anime/Sousou.no.Frieren.S02E03.1080p.WEB-DL.mkv'), FRIEREN, 'another season')
	eq(m.series_key('https://host/x?token=secret&filename=Sousou%20no%20Frieren%20-%2007.mkv'), FRIEREN, 'stream')
	eq(m.series_key('/films/Some Film (2023).mkv'), nil, 'a film')
	eq(m.series_key('/anime/Show - OVA.mkv'), nil, 'no plain episode')
	eq(m.series_key(nil), nil, 'nothing')
end)

test('series: what is saved of a track', function()
	local m = load()
	local a = m.describe({type = 'audio', lang = 'jpn'})
	eq(a.lang, 'ja', 'jpn is ja'); eq(a.variant, nil, 'no variant'); eq(a.kind, nil, 'no kind for audio')
	a = m.describe({type = 'audio', lang = 'spa', title = 'Spanish (Latin America)'})
	eq(a.lang, 'es', 'spa is es'); eq(a.variant, 'es-419', 'variant from the title')
	local s = m.describe({type = 'sub', lang = 'en', title = 'Signs & Songs'})
	eq(s.lang .. ' ' .. s.kind, 'en signs', 'signs by title')
	s = m.describe({type = 'sub', lang = 'ger', forced = true})
	eq(s.lang .. ' ' .. s.kind, 'de signs', 'forced')
	eq(m.describe({type = 'sub', lang = 'eng', title = 'Full + Songs'}).kind, 'full', 'full by title')
	eq(m.describe({type = 'sub', lang = 'kor'}).lang, 'kor', 'other languages as they come')
	eq(m.describe({type = 'sub'}), nil, 'no language')
	eq(m.describe({type = 'sub', lang = 'und'}), nil, 'undetermined')
end)

test('series: a track you pick is saved for the series, nothing else', function()
	local path = series_file()
	local m = load({lang = 'es-ES', series = path})
	play_episode(m, '/anime/[SubsPlease] Sousou no Frieren - 05 (1080p).mkv', episode_tracks(), {aid = 1, sid = 1})
	eq(read_text(path), nil, 'nothing saved for mpv\'s own pick')
	user_picks('sid', 2)
	local entry = saved(path, FRIEREN)
	assert(entry and entry.subs, 'saved')
	eq(entry.subs.lang .. ' ' .. entry.subs.kind, 'en full', 'full English')
	eq(entry.audio, nil, 'the audio was not picked')
	local text = read_text(path)
	assert(not text:find('anime', 1, true) and not text:find('SubsPlease', 1, true), 'no path or file name')
	-- The audio, later: added to the same series.
	user_picks('aid', 2)
	entry = saved(path, FRIEREN)
	eq(entry.audio.lang .. ' ' .. entry.audio.variant, 'es es-419', 'the Latin American dub')
	eq(entry.subs.lang, 'en', 'subtitles kept')
	-- No subtitles at all.
	user_picks('sid', 'no')
	eq(saved(path, FRIEREN).subs.kind, 'none', 'none')
end)

test('series: hikari\'s own switches and --aid/--sid are not saved', function()
	local path = series_file()
	local m = load({lang = 'es-ES', series = path})
	-- hikari takes Spain's subtitles over the Latin American ones mpv picked.
	play_episode(m, '/anime/Show - 01.mkv', crunchyroll(), {aid = 1, sid = 3})
	eq(mock.props.sid, 4, 'hikari\'s switch')
	notify('sid')
	eq(read_text(path), nil, 'the variant switch')
	-- A language switch: mpv picks again, hikari checks the variant again and
	-- switches, after file-loaded.
	m = load({lang = 'es-419', series = path})
	play_episode(m, '/anime/Show - 01.mkv', crunchyroll(), {aid = 1, sid = 3})
	eq(mock.props['options/sid'], 'auto', 'mpv\'s pick is Latin American')
	mock.set_script_opt('hikari-language', 'es-ES')
	eq(mock.props['options/sid'], 4, 'hikari\'s switch after the language switch')
	notify('aid'); notify('sid')
	eq(read_text(path), nil, 'after a language switch')
	-- Tracks fixed when the file starts (command line, a resumed position).
	play_episode(m, '/anime/Show - 02.mkv', crunchyroll(), {aid = 1, sid = 3}, {sid = 6})
	eq(read_text(path), nil, '--sid')
	-- Not an episode of a series: nothing is watched.
	play_episode(m, '/films/Some Film (2023).mkv', crunchyroll(), {aid = 1, sid = 3})
	user_picks('sid', 1)
	eq(read_text(path), nil, 'a film')
	-- With lavfi-complex nothing is watched either.
	mock.props['lavfi-complex'] = '[aid1] [aid2] amix [ao]'
	play_episode(m, '/anime/Show - 03.mkv', crunchyroll(), {aid = 1, sid = 3})
	user_picks('sid', 1)
	eq(read_text(path), nil, 'lavfi-complex')
	mock.props['lavfi-complex'] = ''
end)

test('series: you pick the track hikari had put before: saved', function()
	local path = series_file()
	local m = load({lang = 'es-ES', series = path})
	play_episode(m, '/anime/Show - 01.mkv', crunchyroll(), {aid = 1, sid = 3})
	eq(mock.props.sid, 4, 'hikari\'s switch')
	user_picks('sid', 1)
	eq(saved(path, 'show').subs.lang, 'en', 'English')
	user_picks('sid', 4)
	eq(saved(path, 'show').subs.variant, 'es-ES', 'back to Spain\'s, now yours')
	-- hikari's switch, then mpv's pick again after a language switch: the
	-- track hikari had put is no longer hikari's.
	os.remove(path)
	play_episode(m, '/anime/Show - 02.mkv', crunchyroll(), {aid = 1, sid = 3})
	eq(mock.props.sid, 4, 'hikari\'s switch')
	mock.set_script_opt('hikari-language', 'es-419')
	notify('sid')
	eq(mock.props.sid, 3, 'mpv\'s pick for Latin America')
	eq(read_text(path), nil, 'nothing saved yet')
	user_picks('sid', 4)
	eq(saved(path, 'show').subs.variant, 'es-ES', 'Spain\'s, yours')
end)

test('series: the next episode, of any season, gets what you picked', function()
	local path = series_file()
	local m = load({lang = 'es-ES', series = path})
	play_episode(m, '/anime/Sousou no Frieren - 05.mkv', episode_tracks(), {aid = 1, sid = 1})
	user_picks('sid', 2)
	mock.end_file()
	-- Season 2, another release: the English track is the third one.
	local tracks = episode_tracks()
	table.insert(tracks, 4, {id = 4, type = 'sub', lang = 'pt-BR'})
	tracks[5].id, tracks[6].id, tracks[7].id = 1, 3, 2
	tracks[6].title, tracks[7].title = 'English', 'English [Signs]'
	tracks[6].lang = 'eng'
	mock.sets = {}
	play_episode(m, '/anime/Sousou.no.Frieren.S02E01.1080p.WEB-DL.mkv', tracks, {aid = 1, sid = 1})
	eq(mock.props.sid, 3, 'full English, not the signs')
	eq(sets_of('file-local-options/sid'), '3', 'for this file only')
	eq(mock.props.aid, 1, 'audio as mpv picked it')
	-- hikari's own switch is not saved as yours.
	eq(saved(path, FRIEREN).subs.tag, 'en', 'still the first pick')
end)

test('series: what you picked wins over your own slang and over the variant check', function()
	local path = series_file()
	write_text(path, '{"version":1,"series":[{"key":"show","updated":5,'
		.. '"subs":{"lang":"es","variant":"es-419","kind":"full","tag":"es"}}]}')
	local m = load({lang = 'es-ES', series = path, conf = 'slang=en\n', values = {slang = {'en'}}})
	eq(m.managed.slang, false, 'slang is yours')
	play_episode(m, '/anime/Show - 02.mkv', crunchyroll(), {aid = 1, sid = 1})
	eq(mock.props.sid, 3, 'the Latin American ones, as picked for the series')
	eq(m.get_switched().sid, nil, 'not a variant switch')
	-- A language switch leaves them, as a track you picked.
	mock.sets = {}
	mock.set_script_opt('hikari-language', 'en')
	eq(sets_of('sid') .. sets_of('file-local-options/sid'), '', 'untouched')
end)

test('series: the audio picked for the series, and mpv picks the subtitles for it', function()
	local path = series_file()
	write_text(path, '{"version":1,"series":[{"key":"show","updated":5,'
		.. '"audio":{"lang":"es","variant":"es-419","tag":"spa"}}]}')
	local m = load({lang = 'es-ES', series = path})
	local tracks = {
		{id = 1, type = 'audio', lang = 'ja'},
		{id = 2, type = 'audio', lang = 'spa', title = 'Castellano'},
		{id = 3, type = 'audio', lang = 'spa', title = 'Latino'},
		{id = 1, type = 'sub', lang = 'es', title = 'Spanish'},
		{id = 2, type = 'sub', lang = 'es', title = 'Spanish [Forced]', forced = true},
	}
	-- mpv: Spain's dub (Spanish first), so only the forced subtitles.
	play_episode(m, '/anime/Show S03E01.mkv', tracks, {aid = 2, sid = function() return 2 end})
	eq(mock.props.aid, 3, 'the Latin American dub')
	eq(sets_of('sid'), '2 auto', 'mpv picked the subtitles again')
	eq(read_text(path):find('Latino', 1, true), nil, 'nothing new saved')
	-- No dub of that variant in this release: mpv's pick (here Japanese)
	-- stays, quietly; a dub of the other variant is not taken for it.
	table.remove(tracks, 3)
	mock.logs.warn = {}
	play_episode(m, '/anime/Show S03E02.mkv', tracks, {aid = 1, sid = 1})
	eq(sets_of('file-local-options/aid'), '', 'audio untouched')
	eq(mock.props.aid, 1, 'mpv\'s pick')
	eq(#mock.logs.warn, 0, 'no warning')
end)

test('series: a release without the track keeps mpv\'s pick, and none means none', function()
	local path = series_file()
	write_text(path, '{"version":1,"series":[{"key":"show","updated":5,"subs":{"lang":"fr","kind":"full"}},'
		.. '{"key":"other","updated":4,"subs":{"kind":"none"}}]}')
	local m = load({lang = 'en', series = path})
	play_episode(m, '/anime/Show - 02.mkv', episode_tracks(), {aid = 1, sid = 2})
	eq(mock.props.sid, 2, 'no French: mpv\'s pick')
	eq(#mock.logs.warn, 0, 'no warning')
	play_episode(m, '/anime/Other - 02.mkv', episode_tracks(), {aid = 1, sid = 2})
	eq(mock.props.sid, false, 'no subtitles')
	eq(sets_of('file-local-options/sid'), 'no', 'for this file only')
	-- Already none: held for this file, so a language switch leaves it.
	play_episode(m, '/anime/Other - 03.mkv', episode_tracks(), {aid = 1, sid = false})
	eq(sets_of('file-local-options/sid'), 'no', 'held')
	eq(mock.props.sid, false, 'still none')
	-- A track you picked or fixed stays.
	play_episode(m, '/anime/Other - 04.mkv', episode_tracks(), {aid = 1, sid = 2}, {sid = 3})
	eq(mock.props.sid, 3, '--sid')
	-- track-auto-selection=no: nothing is picked.
	mock.props['track-auto-selection'] = false
	play_episode(m, '/anime/Other - 05.mkv', episode_tracks(), {aid = 1, sid = 2})
	eq(sets_of('file-local-options/sid'), '', 'track-auto-selection=no')
	mock.props['track-auto-selection'] = nil
end)

test('series: mpv already picked the series\' tracks: they still survive a language switch', function()
	local path = series_file()
	write_text(path, '{"version":1,"series":[{"key":"show","updated":5,'
		.. '"audio":{"lang":"ja","tag":"jpn"},"subs":{"kind":"none"}}]}')
	local m = load({lang = 'en', series = path})
	local tracks = {
		{id = 1, type = 'audio', lang = 'jpn'},
		{id = 2, type = 'audio', lang = 'spa'},
		{id = 1, type = 'sub', lang = 'eng'},
		{id = 2, type = 'sub', lang = 'spa'},
	}
	-- mpv: Japanese and no subtitles, as saved; with Spanish it would take
	-- the dub and the Spanish subtitles.
	local spanish = false
	play_episode(m, '/anime/Show - 03.mkv', tracks, {
		aid = function() return spanish and 2 or 1 end,
		sid = function() return spanish and 2 or false end,
	})
	eq(sets_of('file-local-options/aid') .. ' ' .. sets_of('file-local-options/sid'), '1 no', 'held for this file')
	spanish = true
	mock.sets = {}
	mock.set_script_opt('hikari-language', 'es-ES')
	notify('aid'); notify('sid')
	eq(mock.props.aid, 1, 'still Japanese')
	eq(mock.props.sid, false, 'still no subtitles')
	eq(sets_of('aid') .. sets_of('sid'), '', 'not picked again')
	-- Held by hikari, not picked by you: the list is as it was.
	eq(saved(path, 'show').updated, 5, 'nothing saved')
end)

test('series: subtitles turned off by hand in another file give way to the series\' ones', function()
	local path = series_file()
	write_text(path, '{"version":1,"series":[{"key":"show","updated":5,"subs":{"lang":"en","kind":"full"}}]}')
	local m = load({lang = 'es-ES', series = path})
	-- A film, subtitles off by hand (`set sid no`, though mpv showed none):
	-- mpv keeps that `no` for the next file.
	play_episode(m, '/films/Some Film (2023).mkv', episode_tracks(), {aid = 1, sid = false})
	user_picks('sid', 'no')
	eq(read_text(path):find('none', 1, true), nil, 'nothing saved for a film')
	mock.end_file()
	play_episode(m, '/anime/Show - 04.mkv', episode_tracks(), {aid = 1, sid = 1}, {sid = 'no'})
	eq(mock.props.sid, 2, 'the series\' English subtitles')
	eq(sets_of('file-local-options/sid'), '2', 'for this file only')
	mock.end_file()
	eq(mock.props['options/sid'], 'no', 'the `no` comes back after it')
	-- A series without subtitles of its own: the `no` stays.
	play_episode(m, '/anime/Other - 01.mkv', episode_tracks(), {aid = 1, sid = 1}, {sid = 'no'})
	eq(sets_of('file-local-options/sid'), '', 'no series choice')
	-- --sid=no (or sid=no in mpv.conf), never changed by hand: yours, it wins.
	m = load({lang = 'es-ES', series = path})
	play_episode(m, '/anime/Show - 05.mkv', episode_tracks(), {aid = 1, sid = 1}, {sid = 'no'})
	eq(sets_of('file-local-options/sid'), '', '--sid=no wins')
	-- A `no` of yours followed by a track picked by hand: nothing left behind.
	user_picks('sid', 1)
	mock.end_file()
	play_episode(m, '/anime/Show - 06.mkv', episode_tracks(), {aid = 1, sid = 1}, {sid = 'no'})
	eq(sets_of('file-local-options/sid'), '', 'not a `no` you left')
end)

test('series: a track without a language leaves what was saved', function()
	local path = series_file()
	local m = load({lang = 'es-ES', series = path})
	local tracks = episode_tracks()
	tracks[#tracks + 1] = {id = 4, type = 'sub', title = 's.srt', external = true}
	play_episode(m, '/anime/Show - 01.mkv', tracks, {aid = 1, sid = 1})
	user_picks('sid', 2)
	local before = read_text(path)
	user_picks('sid', 4)
	eq(read_text(path), before, 'unchanged')
	eq(saved(path, 'show').subs.lang, 'en', 'still English')
end)

test('series: streams too, without the URL, its token or its host', function()
	local path = series_file()
	local m = load({lang = 'es-ES', series = path})
	local url = 'https://seanime.local:43211/api/v1/stream/9f2c?token=SECRET123&filename=Sousou%20no%20Frieren%20-%2001.mkv'
	play_episode(m, url, episode_tracks(), {aid = 1, sid = 1})
	user_picks('sid', 2)
	local text = read_text(path)
	assert(text and text:find(FRIEREN, 1, true), 'saved by series')
	for _, part in ipairs({'SECRET123', 'token', 'seanime', '43211', 'stream', 'https', '9f2c'}) do
		assert(not text:find(part, 1, true), part .. ' saved')
	end
	play_episode(m, url:gsub('01', '02'), episode_tracks(), {aid = 1, sid = 1})
	eq(mock.props.sid, 2, 'the next stream gets it')
end)

test('series: a broken, huge, newer or unchecked list is not used, and is written over', function()
	local path = series_file()
	local m
	for _, case in ipairs({
		{'not json', 'damaged'}, {'', 'empty'}, {'{"version":1,"series":"x"}', 'damaged'},
		{'{"version":2,"series":[]}', 'newer hikari'},
		{'{"version":1,"series":[' .. string.rep('{"key":"show","updated":1},', 30000) .. '{}]}', 'too big'},
	}) do
		write_text(path, case[1])
		m = load({lang = 'es-ES', series = path})
		eq(#m.read_series(), 0, case[2])
		eq(#mock.logs.warn, 1, case[2] .. ': one warning')
		m.read_series()
		eq(#mock.logs.warn, 1, case[2] .. ': only once')
	end
	-- The next pick writes a good list over it.
	play_episode(m, '/anime/Show - 01.mkv', episode_tracks(), {aid = 1, sid = 1})
	user_picks('sid', 2)
	eq(saved(path, 'show').subs.lang, 'en', 'written over')
	-- Entries and parts that do not check out are left out.
	write_text(path, '{"version":1,"series":[null,'
		.. '{"key":"a","updated":1,"audio":{"lang":"jpn"}},'                       -- not as saved
		.. '{"key":"b","updated":1,"audio":{"lang":"es","variant":"es-MX"}},'      -- unknown variant
		.. '{"key":"c","updated":1,"subs":{"lang":"en","kind":"most"}},'           -- unknown kind
		.. '{"key":"d","updated":-1,"subs":{"kind":"none"}},'                      -- bad time
		.. '{"key":"e\\n","updated":1,"subs":{"kind":"none"}},'                    -- control character
		.. '{"key":"' .. string.rep('x', 300) .. '","updated":1,"subs":{"kind":"none"}},'
		.. '{"key":"f","updated":2,"audio":{"lang":"ja","tag":"a b"},"subs":{"kind":"none"}},'
		.. '{"key":"g","updated":3,"audio":{"lang":"ja","tag":"JA"}}]}')
	local entries = m.read_series()
	eq(#entries, 2, 'two left')
	eq(entries[1].key .. ' ' .. entries[1].audio.tag, 'g ja', 'newest first, tag lower case')
	eq(entries[2].key, 'f', 'f'); eq(entries[2].audio, nil, 'its bad audio left out')
	eq(entries[2].subs.kind, 'none', 'its subtitles kept')
end)

test('series: at most MAX_SERIES, the oldest out; another window\'s series kept', function()
	local path = series_file()
	local m = load({lang = 'es-ES', series = path})
	local list = {}
	for i = 1, m.MAX_SERIES do
		list[#list + 1] = string.format('{"key":"s%d","updated":%d,"subs":{"kind":"none"}}', i, 1000 + i)
	end
	write_text(path, '{"version":1,"series":[' .. table.concat(list, ',') .. ']}')
	m.clock.now = function() return 5000 end
	play_episode(m, '/anime/Show - 01.mkv', episode_tracks(), {aid = 1, sid = 1})
	-- Another mpv window saves a series meanwhile.
	local value = mock.parse_json(read_text(path))
	value.series[1].updated = 4000
	value.series[1].key = 'other window'
	write_text(path, mock.format_json(value))
	user_picks('sid', 2)
	local entries = m.read_series()
	eq(#entries, m.MAX_SERIES, 'bounded')
	eq(entries[1].key, 'show', 'newest first')
	eq(entries[2].key, 'other window', 'the other window\'s')
	eq(saved(path, 's2'), nil, 'the oldest left')
	assert(saved(path, 's3'), 'the next oldest stays')
	-- A list with more series than that: only the newest are read.
	list[#list + 1] = '{"key":"newer","updated":9000,"subs":{"kind":"none"}}'
	write_text(path, '{"version":1,"series":[' .. table.concat(list, ',') .. ']}')
	entries = m.read_series()
	eq(#entries, m.MAX_SERIES, 'read bounded')
	eq(entries[1].key .. ' ' .. entries[#entries].key, 'newer s2', 'the newest')
end)

test('series: an unreadable list is not written over', function()
	local path = series_file()
	local m = load({lang = 'es-ES', series = path .. '/nope'})
	mock.files[path .. '/nope'] = {is_file = true}
	play_episode(m, '/anime/Show - 01.mkv', episode_tracks(), {aid = 1, sid = 1})
	user_picks('sid', 2)
	eq(#mock.logs.warn, 1, 'one warning')
	eq(read_text(path .. '/nope'), nil, 'nothing written')
end)

for _, path in ipairs(tmp_files) do os.remove(path) end
print(string.format('\n%d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
