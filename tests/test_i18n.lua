-- Run from the repository root: lua tests/test_i18n.lua
-- The shared texts module (script-modules/hikari-i18n.lua) and the loader every
-- hikari script uses for it.
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local MODULE = 'portable_config/script-modules/hikari-i18n.lua'
local SCRIPTS = {
	'hikari-language', 'hikari-palettes', 'hikari-skip', 'hikari-speed', 'hikari-subs',
	'hikari-title', 'hikari-update', 'hikari-upscale',
}
local CODES = {'en', 'es', 'de', 'fr', 'it', 'pl', 'pt', 'ro', 'ru', 'tr', 'uk', 'zh-HK', 'zh-hans'}
-- Keys that may leave languages out on purpose: those fall back to English
-- (`S1`, `E05`), which is what those languages write too.
local PARTIAL = {title_season = true, title_episode = true, title_episodes = true}

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

-- A fresh module, as each mpv script gets one, with `opts` as script-opts and
-- `env` as the environment.
local function fresh(opts, env)
	mock.install('hikari_test')
	mock.script_opts = opts or {}
	local i18n = assert(loadfile(MODULE))()
	i18n.getenv = function(name) return (env or {})[name] end
	return i18n
end

local function read(path)
	local f = assert(io.open(path, 'rb'))
	local s = f:read('*a')
	f:close()
	return s
end

local function placeholders(text)
	local list = {}
	for name in text:gmatch('{(%w+)}') do list[#list + 1] = name end
	table.sort(list)
	return table.concat(list, ',')
end

test('13 languages, the ones of uosc 5.13, each with its own name', function()
	local i18n = fresh()
	eq(#i18n.LANGUAGES, #CODES, 'count')
	for i, code in ipairs(CODES) do
		eq(i18n.LANGUAGES[i].code, code, 'order #' .. i)
		assert(type(i18n.LANGUAGES[i].name) == 'string' and #i18n.LANGUAGES[i].name > 0, code)
	end
	eq(i18n.name('es'), 'Español'); eq(i18n.name('zh-HK'), '中文（香港）'); eq(i18n.name('xx'), nil)
end)

test('the menu: the 13 languages, Spanish and Portuguese once per regional variant', function()
	local i18n = fresh()
	local codes, languages = {}, {}
	for i, variant in ipairs(i18n.VARIANTS) do
		codes[i], languages[i] = variant.code, variant.language
		assert(i18n.is_language(variant.language), variant.code)
		assert(type(variant.name) == 'string' and #variant.name > 0, variant.code)
	end
	eq(table.concat(codes, ' '), 'en es-ES es-419 de fr it pl pt-BR pt-PT ro ru tr uk zh-HK zh-hans', 'codes')
	eq(table.concat(languages, ' '), 'en es es de fr it pl pt pt ro ru tr uk zh-HK zh-hans', 'languages')
	eq(i18n.VARIANTS[3].name, 'Español (Latinoamérica)'); eq(i18n.VARIANTS[9].name, 'Português (Portugal)')
	eq(i18n.is_variant('es-419'), true); eq(i18n.is_variant('es'), false); eq(i18n.is_variant('es-MX'), false)
	eq(i18n.language_of('pt-PT'), 'pt'); eq(i18n.language_of('de'), 'de'); eq(i18n.language_of('es'), nil)
	for language, regional in pairs(i18n.REGIONAL) do
		for _, key in ipairs({'default', 'rest'}) do eq(i18n.language_of(regional[key]), language, language .. ' ' .. key) end
		for code in pairs(regional.variants) do eq(i18n.language_of(code), language, code) end
	end
end)

test('variants: locale names and tags to an entry of the menu, by region', function()
	local i18n = fresh()
	local cases = {
		{'es', 'es-ES'}, {'es_ES.UTF-8', 'es-ES'}, {'es-es', 'es-ES'}, {'es_MX.UTF-8', 'es-419'}, {'es-419', 'es-419'},
		{'es_AR', 'es-419'}, {'es-US', 'es-419'}, {'es-Latn-CO', 'es-419'}, {'ES_mx', 'es-419'}, {'es.UTF-8', 'es-ES'},
		{'es@euro', 'es-ES'}, {'pt', 'pt-BR'}, {'pt_BR', 'pt-BR'}, {'pt_PT.UTF-8', 'pt-PT'}, {'pt-AO', 'pt-PT'},
		{'es--MX', 'es-ES'}, {'de_AT', 'de'}, {'en_GB', 'en'}, {'zh_TW', 'zh-HK'}, {'zh-Hans-HK', 'zh-hans'}, {'ja_JP', nil}, {'C', nil},
	}
	for _, case in ipairs(cases) do eq(i18n.variant_of(case[1]), case[2], case[1]) end
	eq(i18n.region_of('es-Latn-MX'), 'MX'); eq(i18n.region_of('es-419'), '419'); eq(i18n.region_of('es'), nil)
	eq(i18n.region_of('zh-Hant'), nil); eq(i18n.region_of('es-x-private'), nil); eq(i18n.region_of(nil), nil)
end)

test('variants: the option, a saved choice of hikari 0.5 and the system', function()
	eq(fresh({['hikari-language'] = 'es'}).variant(), 'es-ES', 'hikari 0.5 saved es: Spain')
	eq(fresh({['hikari-language'] = 'pt'}).variant(), 'pt-BR', 'hikari 0.5 saved pt: Brazil')
	local i18n = fresh({['hikari-language'] = 'es-419'})
	eq(i18n.variant(), 'es-419'); eq(i18n.language(), 'es')
	eq(i18n.t('skip_opening'), 'Saltar opening ›', 'the Spanish texts')
	eq(fresh({}, {LANG = 'es_MX.UTF-8'}).variant(), 'es-419', 'system')
	eq(fresh({}, {LANG = 'pt_PT.UTF-8'}).language(), 'pt', 'system, texts')
	eq(fresh({}, {LANG = 'de_DE'}).variant(), 'de')
	eq(fresh({['hikari-language'] = 'es'}).t('skip_opening', nil, 'pt-PT'), 'Pular abertura ›', 'an entry as `lang`')
end)

test('every text: English always, every language unless partial on purpose, only known languages', function()
	local i18n = fresh()
	local known = {}
	for _, code in ipairs(CODES) do known[code] = true end
	local count = 0
	for key, entry in pairs(i18n.STRINGS) do
		count = count + 1
		assert(type(entry.en) == 'string' and entry.en ~= '', 'no English for ' .. key)
		for code, text in pairs(entry) do
			assert(known[code], key .. ': unknown language ' .. tostring(code))
			assert(type(text) == 'string' and text ~= '', key .. '.' .. code)
			assert(i18n.normalize(code) == code, code .. ' is not a canonical code')
		end
		if not PARTIAL[key] then
			for _, code in ipairs(CODES) do assert(entry[code], key .. ' has no ' .. code) end
		end
	end
	assert(count >= 70, 'only ' .. count .. ' texts')
end)

test('translations keep the placeholders of the English text', function()
	local i18n = fresh()
	for key, entry in pairs(i18n.STRINGS) do
		local expected = placeholders(entry.en)
		for code, text in pairs(entry) do eq(placeholders(text), expected, key .. '.' .. code) end
	end
end)

test('texts are valid UTF-8 without control characters (but \\n where English has one)', function()
	local i18n = fresh()
	for key, entry in pairs(i18n.STRINGS) do
		for code, text in pairs(entry) do
			local stripped = text:gsub('[\1-\127\194-\244][\128-\191]*', '')
			eq(stripped, '', key .. '.' .. code .. ' is not UTF-8')
			assert(not text:gsub('\n', ''):find('%c'), key .. '.' .. code .. ' has a control character')
			eq(select(2, text:gsub('\n', '')), select(2, entry.en:gsub('\n', '')), key .. '.' .. code .. ' line breaks')
		end
	end
end)

test('button tooltips have no , or ? (separators of uosc controls)', function()
	local i18n = fresh()
	for key, entry in pairs(i18n.STRINGS) do
		if key:match('^tooltip_') then
			for code, text in pairs(entry) do assert(not text:find('[,?]'), key .. '.' .. code) end
		end
	end
end)

test('the Spanish and English texts that used to be fixed', function()
	local i18n = fresh({['hikari-language'] = 'es'})
	eq(i18n.t('skip_opening'), 'Saltar opening ›')
	eq(i18n.t('subs_style_dark_box'), 'Caja oscura')
	eq(i18n.t('upscale_mode_auto'), 'Automático')
	eq(i18n.t('tooltip_update'), 'Actualizar hikari')
	eq(i18n.t('title_season', {season = 1}), 'T1')
	eq(i18n.t('skip_opening', nil, 'en'), 'Skip opening ›')
	eq(i18n.t('title_season', {season = 1}, 'en'), 'S1')
end)

test('normalize: locale names and tags to one of the 13 codes', function()
	local i18n = fresh()
	local cases = {
		{'es', 'es'}, {'es_ES.UTF-8', 'es'}, {'es-419', 'es'}, {'ES_mx', 'es'}, {'de_DE@euro', 'de'},
		{'de_AT.UTF-8', 'de'}, {'pt_BR', 'pt'}, {'pt-PT', 'pt'}, {'fr_CA.utf8', 'fr'}, {'en_GB.UTF-8', 'en'},
		{'ru_RU.KOI8-R', 'ru'}, {'uk_UA', 'uk'}, {'tr_TR', 'tr'}, {'pl_PL', 'pl'}, {'ro_RO', 'ro'}, {'it_IT', 'it'},
		{'zh_CN.UTF-8', 'zh-hans'}, {'zh_SG', 'zh-hans'}, {'zh-Hans', 'zh-hans'}, {'zh-Hans-HK', 'zh-hans'},
		{'zh', 'zh-hans'}, {'zh_TW.UTF-8', 'zh-HK'}, {'zh_HK', 'zh-HK'}, {'zh-MO', 'zh-HK'}, {'zh-Hant', 'zh-HK'},
		{'zh-Hant-TW', 'zh-HK'}, {'zh-HK', 'zh-HK'}, {'zh-hans', 'zh-hans'},
		{'C', nil}, {'POSIX', nil}, {'C.UTF-8', nil}, {'ja_JP.UTF-8', nil}, {'', nil}, {'   ', nil},
		{'nl_NL', nil}, {'english', nil}, {string.rep('e', 100), nil},
	}
	for _, case in ipairs(cases) do eq(i18n.normalize(case[1]), case[2], case[1]) end
	eq(i18n.normalize(nil), nil, 'nil'); eq(i18n.normalize(42), nil, 'number')
end)

test('no option: the system language from LC_ALL, LC_MESSAGES or LANG, else English', function()
	eq(fresh({}, {LANG = 'de_DE.UTF-8'}).language(), 'de')
	eq(fresh({}, {LC_ALL = 'fr_FR.UTF-8', LANG = 'de_DE.UTF-8'}).language(), 'fr', 'LC_ALL first')
	eq(fresh({}, {LC_MESSAGES = 'it_IT', LANG = 'de_DE'}).language(), 'it', 'LC_MESSAGES before LANG')
	eq(fresh({}, {LC_ALL = 'C', LANG = 'de_DE'}).language(), 'en', 'the first one set decides, even C')
	eq(fresh({}, {LC_ALL = '', LANG = 'pt_BR'}).language(), 'pt', 'empty means unset')
	eq(fresh({}, {LANG = 'ja_JP.UTF-8'}).language(), 'en', 'unknown: English')
	eq(fresh({}, {}).language(), 'en', 'nothing set (Windows)')
	eq(fresh({['hikari-language'] = 'auto'}, {LANG = 'ru_RU'}).language(), 'ru', 'auto')
end)

test('the option wins over the system; unknown values are English, with a warning', function()
	eq(fresh({['hikari-language'] = 'uk'}, {LANG = 'de_DE'}).language(), 'uk')
	eq(fresh({['hikari-language'] = 'zh-HK'}).language(), 'zh-HK')
	local i18n = fresh({['hikari-language'] = 'klingon'}, {LANG = 'de_DE'})
	eq(i18n.language(), 'en')
	assert(mock.logs.warn[1] and mock.logs.warn[1]:find('klingon', 1, true), 'warned')
	fresh({['hikari-language'] = 'xx\27[31m\nfake line' .. string.rep('z', 100)}, {}).language()
	local warning = mock.logs.warn[1]
	assert(warning and not warning:find('%c'), 'no control characters in the warning')
	assert(warning:find('xx?[31m?fake line', 1, true), 'replaced by ?')
	assert(not warning:find(string.rep('z', 60), 1, true), 'cut to 64 characters')
end)

test('t: fallbacks, placeholders and odd values', function()
	local i18n = fresh({['hikari-language'] = 'es'})
	i18n.STRINGS.only_english = {en = 'Only {x}'}
	eq(i18n.t('only_english', {x = 'here'}), 'Only here', 'missing language: English')
	eq(i18n.t('no_such_key'), 'no_such_key', 'unknown key: the key')
	eq(i18n.t('no_such_key'), 'no_such_key')
	eq(#mock.logs.warn, 1, 'warned once')
	eq(i18n.t('update_notice', {version = '1%2.0'}), 'hikari 1%2.0 disponible · Alt+u', '% kept')
	eq(i18n.t('update_notice'), 'hikari {version} disponible · Alt+u', 'placeholder without value')
	eq(i18n.t('update_notice', {version = 7}), 'hikari 7 disponible · Alt+u', 'numbers')
	eq(i18n.t('skip_opening', nil, 'xx'), 'Skip opening ›', 'unknown language argument: English')
end)

test('decimal: the separator of the language', function()
	eq(fresh({['hikari-language'] = 'es'}).decimal('0.75'), '0,75')
	eq(fresh({['hikari-language'] = 'en'}).decimal('0.75'), '0.75')
	eq(fresh({['hikari-language'] = 'zh-hans'}).decimal('1.5'), '1.5')
	eq(fresh({['hikari-language'] = 'de'}).decimal('2'), '2')
end)

test('on_change: called once per real switch, not for other options', function()
	local i18n = fresh({['hikari-language'] = 'es'})
	local calls = {}
	i18n.on_change(function(lang) calls[#calls + 1] = lang end)
	i18n.on_change(function(lang) calls[#calls + 1] = 'second:' .. lang end)
	eq(#mock.observers['options/script-opts'], 1, 'one observer for every callback')
	mock.set_script_opt('uosc-color', 'foreground=ffffff')
	eq(#calls, 0, 'another option')
	mock.set_script_opt('hikari-language', 'es')
	eq(#calls, 0, 'same language')
	mock.set_script_opt('hikari-language', 'fr')
	eq(table.concat(calls, ' '), 'fr second:fr')
	eq(i18n.language(), 'fr')
	eq(i18n.t('skip_opening'), 'Passer l’opening ›', 'texts follow')
	mock.set_script_opt('hikari-language', nil)
	eq(i18n.language(), 'en', 'option removed: the system (none here)')
end)

test('on_change: a switch between variants calls back with the same language', function()
	local i18n = fresh({['hikari-language'] = 'es'})
	local calls = {}
	i18n.on_change(function(lang, variant) calls[#calls + 1] = lang .. '/' .. variant end)
	mock.set_script_opt('hikari-language', 'es-ES')
	eq(#calls, 0, 'es is es-ES')
	mock.set_script_opt('hikari-language', 'es-419')
	mock.set_script_opt('hikari-language', 'pt')
	eq(table.concat(calls, ' '), 'es/es-419 pt/pt-BR')
end)

-- The loader block, from its comment to the end of the function call.
local function loader_of(src)
	local s = src:find('-- Texts in the chosen language:', 1, true)
	local e = s and select(2, src:find('end)()\n', s, true))
	return s and src:sub(s, e) or nil
end

test('every hikari script loads the module with the same loader', function()
	local reference = loader_of(read('portable_config/scripts/hikari-language.lua'))
	assert(reference, 'loader in hikari-language.lua')
	for _, name in ipairs(SCRIPTS) do
		eq(loader_of(read('portable_config/scripts/' .. name .. '.lua')), reference, name)
	end
end)

test('the loader finds the module in ~~/script-modules and leaves package.path as it was', function()
	mock.install('hikari_test')
	local before = package.path
	local chunk = loader_of(read('portable_config/scripts/hikari-language.lua'))
	local i18n = assert((loadstring or load)('local i18n = ' .. chunk:match('local i18n = (.*)$') .. ' return i18n'))()
	eq(type(i18n.t), 'function', 'module')
	eq(package.path, before, 'package.path restored')
	for _, dir in ipairs({'C:\\a;b', '/a?b', ''}) do
		mock.install('hikari_test')
		mock.expand['~~/script-modules'] = dir
		local ok, err = pcall((loadstring or load)('local i18n = ' .. chunk:match('local i18n = (.*)$') .. ' return i18n'))
		assert(not ok and tostring(err):find('unusable', 1, true), 'refused: ' .. dir)
		eq(package.path, before, 'unchanged after ' .. dir)
	end
	mock.expand['~~/script-modules'] = '/nonexistent/hikari'
	local ok, err = pcall((loadstring or load)('local i18n = ' .. chunk:match('local i18n = (.*)$') .. ' return i18n'))
	assert(not ok and tostring(err):find('reinstall hikari', 1, true), 'missing module: clear error')
	eq(package.path, before, 'restored after a failure')
	mock.expand['~~/script-modules'] = nil
end)

test('the module avoids os.execute, io.popen, load* and file writes', function()
	local src = read(MODULE)
	for _, bad in ipairs({'os.execute', 'io.popen', 'io.open', 'loadstring', 'loadfile', 'dofile', 'load('}) do
		assert(not src:find(bad, 1, true), bad)
	end
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
