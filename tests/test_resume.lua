-- Run from the repository root: lua tests/test_resume.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/hikari-resume.lua'
local SCRIPT_NAME = 'hikari_resume'
local AVAILABLE = 'user-data/hikari_resume/available'
local MENU_TYPE_PROP = 'user-data/uosc/menu/type'
local PID = 4242

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
	local file = io.open(path, 'rb')
	if not file then return nil end
	local content = file:read('*a')
	file:close()
	return content
end

local function write(path, content)
	local file = assert(io.open(path, 'wb'))
	file:write(content)
	file:close()
end

-- The list lives in a temporary folder of its own.
local DIR = os.tmpname()
os.remove(DIR)
assert(os.execute('mkdir -p "' .. DIR .. '"'))
local LIST = DIR .. '/hikari-resume.json'

local function clean_dir()
	os.execute('rm -rf "' .. DIR .. '"/* "' .. DIR .. '"/.[!.]* 2>/dev/null')
end

local function dir_names()
	local names = {}
	local p = io.popen('ls -A "' .. DIR .. '"')
	for line in p:lines() do names[#names + 1] = line end
	p:close()
	table.sort(names)
	return names
end

-- Fixed "now": 2026-10-12 20:00 local time.
local NOW = os.time({year = 2026, month = 10, day = 12, hour = 20})

-- Loads the script with fresh mocks and an empty list folder (unless `keep`).
-- `opts` are hikari-resume options (enabled, ask, history_size).
local function load(opts, keep)
	if not keep then clean_dir() end
	mock.install(SCRIPT_NAME)
	mock.script_opts = {['hikari-language'] = 'es'}
	for k, v in pairs(opts or {}) do mock.script_opts['hikari-resume-' .. k] = v end
	mock.expand['~~/hikari-resume.json'] = LIST
	mock.props.platform = 'linux'
	mock.props.pid = PID
	HIKARI_RESUME_TEST = true
	local s = assert(loadfile(SCRIPT))()
	if s then s.clock.now = function() return NOW end end
	return s
end

local function list_json(entries)
	return mock.format_json({version = 1, entries = entries})
end

local function saved()
	local content = read(LIST)
	if not content then return nil end
	local value = assert(mock.parse_json(content), 'the list is JSON')
	return value.entries
end

-- Opens `path` as mpv would: properties first, then file-loaded.
local function open(path, props)
	props = props or {}
	mock.props.path = path
	mock.props['working-directory'] = props.wd or '/home/user'
	mock.props['time-pos'] = props.time or 0
	mock.props.duration = props.duration == nil and 1420 or props.duration
	if props.duration == false then mock.props.duration = nil end
	mock.props['chapter-list'] = props.chapters
	mock.props.pause = props.pause or false
	mock.events['file-loaded']()
end

-- Plays on to `time` (time-pos changes, then the periodic save runs).
local function play_to(time)
	mock.set('time-pos', time)
	mock.advance(10)
end

local function ends()
	mock.events['end-file']()
	mock.props['time-pos'] = nil
end

local function last_command() return mock.commands[#mock.commands] end

local function commands_named(name)
	local out = {}
	for _, c in ipairs(mock.commands) do
		if c[1] == name or c[3] == name then out[#out + 1] = c end
	end
	return out
end

-- The last menu sent to uosc, decoded: data and message (open-menu / update-menu).
local function last_menu()
	for i = #mock.commands, 1, -1 do
		local c = mock.commands[i]
		if c[1] == 'script-message-to' and c[2] == 'uosc' and (c[3] == 'open-menu' or c[3] == 'update-menu') then
			return assert(mock.parse_json(c[4])), c[3]
		end
	end
	return nil
end

local EP = '/mnt/anime/Frieren/[SubsPlease] Sousou no Frieren - 05 (1080p).mkv'
local EP_TITLE = '[SubsPlease] Sousou no Frieren - 05 (1080p)'

local function entry(path, position, updated, duration)
	return {path = path, title = path:match('([^/]+)%.%w+$'), position = position, duration = duration or 1420,
		updated = updated or NOW - 60}
end

-- Files and URLs -----------------------------------------------------------------

test('files: local, network and relative paths, made absolute and normalised', function()
	local s = load()
	eq(s.file_path('/mnt/anime/ep.mkv', '/x', false), '/mnt/anime/ep.mkv')
	eq(s.file_path('/Volumes/data/anime/ep.mkv', '/x', false), '/Volumes/data/anime/ep.mkv')
	eq(s.file_path('ep.mkv', '/home/user', false), '/home/user/ep.mkv', 'relative')
	eq(s.file_path('./a/../b/./ep.mkv', '/home/user/', false), '/home/user/b/ep.mkv', 'dots')
	eq(s.file_path('//mnt///anime/ep.mkv', nil, false), '/mnt/anime/ep.mkv', 'separators')
	eq(s.file_path('C:\\Anime\\ep.mkv', nil, true), 'C:\\Anime\\ep.mkv')
	eq(s.file_path('C:/Anime/ep.mkv', nil, true), 'C:\\Anime\\ep.mkv', 'forward slashes')
	eq(s.file_path('\\\\NAS\\anime\\ep.mkv', nil, true), '\\\\NAS\\anime\\ep.mkv', 'UNC')
	eq(s.file_path('//NAS/anime/ep.mkv', nil, true), '\\\\NAS\\anime\\ep.mkv', 'UNC with slashes')
	eq(s.file_path('ep.mkv', 'D:\\Videos', true), 'D:\\Videos\\ep.mkv', 'Windows relative')
	eq(s.file_path('..\\ep.mkv', 'D:\\Videos\\Anime', true), 'D:\\Videos\\ep.mkv')
	eq(s.file_path('\\Anime\\ep.mkv', 'D:\\Videos', true), 'D:\\Anime\\ep.mkv', 'root of the drive')
	eq(s.file_path('ep.mkv', nil, false), nil, 'relative without working directory')
	eq(s.file_path('C:ep.mkv', 'C:\\x', true), nil, 'relative to a drive')
end)

test('file:// URLs are files; a drive letter is not a scheme', function()
	local s = load()
	eq(s.file_path('file:///home/user/a%20b.mkv', nil, false), '/home/user/a b.mkv')
	eq(s.file_path('FILE://localhost/home/user/ep.mkv', nil, false), '/home/user/ep.mkv')
	eq(s.file_path('file:///C:/Anime/ep%201.mkv', nil, true), 'C:\\Anime\\ep 1.mkv')
	eq(s.file_path('file://NAS/anime/ep.mkv', nil, true), '\\\\NAS\\anime\\ep.mkv', 'share')
	eq(s.file_path('file://NAS/anime/ep.mkv', nil, false), nil, 'no shares outside Windows')
	eq(s.file_path('C:\\ep.mkv', nil, true), 'C:\\ep.mkv')
	eq(s.file_path('c:/ep.mkv', nil, true), 'c:\\ep.mkv')
end)

test('URLs and other inputs are never files', function()
	local s = load()
	for _, url in ipairs({'https://example.com/ep.mkv', 'http://127.0.0.1:43211/stream/ep?token=abc',
		'ytdl://abc', 'edl://ep.mkv,0,10', 'memory://text', 'smb://nas/anime/ep.mkv', 'dvd://', 'av://lavfi:x',
		'hls+https://x/y', '-', '', 'file://', 'file:///a%00b.mkv'}) do
		eq(s.file_path(url, '/home/user', false), nil, url)
		eq(s.file_path(url, 'C:\\x', true), nil, url .. ' (Windows)')
	end
	eq(s.file_path(nil, '/x', false), nil)
	eq(s.file_path('/x/' .. string.rep('a', 5000), '/x', false), nil, 'absurdly long')
end)

test('a stream is neither saved nor asked about', function()
	write(LIST, list_json({entry('/x/ep.mkv', 100)}))
	load(nil, true)
	open('http://127.0.0.1:43211/api/v1/mediastream/file?token=secret')
	eq(#mock.commands, 0, 'nothing asked')
	play_to(60); play_to(600)
	ends()
	assert(not read(LIST):find('token', 1, true), 'the URL was never written')
	eq(#saved(), 1, 'the list is as it was')
end)

test('titles: the file name without folder or extension', function()
	local s = load()
	eq(s.title_of(EP), EP_TITLE)
	eq(s.title_of('C:\\Anime\\ep.05.mkv'), 'ep.05')
	eq(s.title_of('/x/noext'), 'noext')
	eq(s.title_of('/x/.hidden'), '.hidden')
end)

-- What is saved -------------------------------------------------------------------

test('under 30 s nothing is saved; from 30 s on, the position', function()
	local s = load()
	open(EP)
	play_to(29)
	ends()
	eq(read(LIST), nil, 'nothing written')
	open(EP)
	play_to(31)
	local e = saved()
	eq(#e, 1); eq(e[1].path, EP); eq(e[1].title, EP_TITLE); eq(e[1].position, 31)
	eq(e[1].duration, 1420); eq(e[1].updated, NOW)
	eq(mock.props[AVAILABLE], true, 'the button shows')
	eq(s.opts.history_size, 30)
end)

test('under 30 s an entry already there stays as it was', function()
	write(LIST, list_json({entry(EP, 700)}))
	load(nil, true)
	open(EP)
	mock.messages['prompt-answer']('start', '1')
	play_to(20)
	ends()
	eq(saved()[1].position, 700)
end)

test('only while playing, and only when the position moved', function()
	load()
	open(EP)
	mock.props.pause = true
	play_to(100)
	eq(read(LIST), nil, 'paused: nothing')
	mock.props.pause = false
	mock.advance(10)
	eq(saved()[1].position, 100)
	os.remove(LIST)
	mock.advance(10)
	eq(read(LIST), nil, 'same position: nothing written')
	play_to(100.5)
	eq(read(LIST), nil, 'under a second: nothing')
	play_to(112)
	eq(saved()[1].position, 112)
end)

test('end-file saves the last position seen, even with time-pos gone', function()
	load()
	open(EP)
	mock.set('time-pos', 300)
	mock.set('time-pos', nil)
	mock.events['end-file']()
	eq(saved()[1].position, 300)
end)

test('shutdown saves too, once', function()
	load()
	open(EP)
	mock.set('time-pos', 400)
	mock.events['shutdown']()
	eq(saved()[1].position, 400)
	os.remove(LIST)
	mock.events['end-file']()
	eq(read(LIST), nil, 'nothing more after it')
end)

test('watched at 95 %: removed, and next time it starts from zero without asking', function()
	write(LIST, list_json({entry(EP, 700), entry('/x/other.mkv', 50)}))
	load(nil, true)
	open(EP)
	mock.messages['prompt-answer']('continue', '1')
	play_to(1348)
	eq(saved()[1].path, EP, 'just under')
	play_to(1349)
	local e = saved()
	eq(#e, 1, 'removed'); eq(e[1].path, '/x/other.mkv')
	ends()
	mock.commands = {}
	open(EP)
	eq(#mock.commands, 0, 'not asked')
end)

test('watched once the (last) ending chapter starts', function()
	local s = load()
	local chapters = {{time = 0, title = 'Prologue'}, {time = 90, title = 'Opening'}, {time = 180, title = 'Part A'},
		{time = 1290, title = 'ED'}, {time = 1380, title = 'Preview'}}
	eq(s.ending_start(chapters, 1420), 1290)
	eq(s.ending_start({{time = 900, title = 'Ending'}, {time = 1200, title = 'エンディング'}}, 1420), 1200, 'the last one')
	eq(s.ending_start({{time = 800, title = 'Credits Roll'}}, 1420), 800)
	eq(s.ending_start({{time = 900, title = 'Edward'}}, 1420), nil)
	eq(s.ending_start(nil, 1420), nil)
	eq(s.ending_start(chapters, nil), nil, 'no duration')
	open(EP, {chapters = chapters})
	play_to(1280)
	eq(saved()[1].position, 1280)
	play_to(1291)
	eq(#saved(), 0, 'removed at the ending')
end)

test('no known duration: nothing is saved', function()
	load()
	open(EP, {duration = false})
	play_to(200)
	ends()
	eq(read(LIST), nil)
	open(EP, {duration = 0})
	play_to(200)
	eq(read(LIST), nil, 'zero')
end)

-- The question --------------------------------------------------------------------

test('a file with an entry: pauses and asks, continue selected by default', function()
	write(LIST, list_json({entry(EP, 754)}))
	load(nil, true)
	open(EP)
	eq(mock.props.pause, true, 'paused')
	local data, message = last_menu()
	eq(message, 'open-menu'); eq(data.type, 'hikari-resume-prompt'); eq(data.title, EP_TITLE)
	eq(data.selected_index, 1)
	eq(#data.items, 2)
	eq(data.items[1].title, 'Continuar desde 12:34')
	eq(data.items[2].title, 'Empezar desde el principio')
	local v = data.items[1].value
	eq(v[1], 'script-message-to'); eq(v[2], SCRIPT_NAME); eq(v[3], 'prompt-answer'); eq(v[4], 'continue')
	-- Nothing saved while asking.
	mock.advance(30)
	eq(saved()[1].position, 754)
	mock.set(MENU_TYPE_PROP, 'hikari-resume-prompt')
	mock.messages['prompt-answer']('continue', v[5])
	local seek = commands_named('seek')[1]
	eq(seek[2], '754.000'); eq(seek[3], 'absolute+exact')
	eq(mock.props.pause, false, 'playing again')
	mock.set(MENU_TYPE_PROP, nil)
	eq(#commands_named('seek'), 1, 'closing after the answer changes nothing')
	eq(mock.props.pause, false)
end)

test('start from the beginning: no seek, playing again', function()
	write(LIST, list_json({entry(EP, 754)}))
	load(nil, true)
	open(EP)
	local data = last_menu()
	mock.messages['prompt-answer']('start', data.items[2].value[5])
	eq(#commands_named('seek'), 0)
	eq(mock.props.pause, false)
end)

test('already paused: stays paused after answering', function()
	write(LIST, list_json({entry(EP, 754)}))
	load(nil, true)
	open(EP, {pause = true})
	local sets = #mock.native_sets
	mock.messages['prompt-answer']('continue', '1')
	eq(mock.props.pause, true)
	eq(#commands_named('seek'), 1)
	for i = sets + 1, #mock.native_sets do assert(mock.native_sets[i][1] ~= 'pause', 'pause not touched') end
end)

test('Esc (menu closed without choosing) starts from the beginning', function()
	write(LIST, list_json({entry(EP, 754)}))
	load(nil, true)
	open(EP)
	mock.set(MENU_TYPE_PROP, 'hikari-resume-prompt')
	mock.set(MENU_TYPE_PROP, nil)
	eq(#commands_named('seek'), 0)
	eq(mock.props.pause, false, 'playing')
	-- The answer may still come after the close (uosc closes first): it counts.
	mock.messages['prompt-answer']('continue', '1')
	eq(#commands_named('seek'), 1)
	-- Saving goes on once the menu is closed.
	play_to(800)
	eq(saved()[1].position, 800)
end)

test('answers for another file or with junk are ignored', function()
	write(LIST, list_json({entry(EP, 754)}))
	load(nil, true)
	open(EP)
	mock.messages['prompt-answer']('continue', '7')
	mock.messages['prompt-answer']('seek 0', '1')
	mock.messages['prompt-answer'](nil, nil)
	eq(#commands_named('seek'), 0)
	eq(mock.props.pause, true, 'still asking')
end)

test('no uosc: the pause goes back after a while', function()
	write(LIST, list_json({entry(EP, 754)}))
	local s = load(nil, true)
	open(EP)
	mock.advance(s.PROMPT_TIMEOUT)
	eq(mock.props.pause, false)
	eq(#commands_named('seek'), 0)
	assert(mock.logs.warn[1]:find('uosc', 1, true), 'warned')
end)

test('another file while asking: the question goes, the pause comes back', function()
	write(LIST, list_json({entry(EP, 754)}))
	load(nil, true)
	open(EP)
	mock.set(MENU_TYPE_PROP, 'hikari-resume-prompt')
	ends()
	local close = commands_named('close-menu')[1]
	eq(close[4], 'hikari-resume-prompt')
	eq(mock.props.pause, false)
	mock.messages['prompt-answer']('continue', '1')
	eq(#commands_named('seek'), 0, 'too late')
	eq(saved()[1].position, 754, 'nothing saved at 0')
end)

test('ask=no: continues without asking', function()
	write(LIST, list_json({entry(EP, 754)}))
	load({ask = 'no'}, true)
	open(EP)
	eq(#commands_named('open-menu'), 0)
	eq(commands_named('seek')[1][2], '754.000')
	eq(mock.props.pause, false)
end)

test('not asked when mpv already moved (time-pos 1 s or more at load)', function()
	write(LIST, list_json({entry(EP, 754)}))
	load(nil, true)
	open(EP, {time = 750})
	eq(#mock.commands, 0)
	eq(mock.props.pause, false)
	ends()
	open(EP, {time = 0.5})
	eq(#commands_named('open-menu'), 1, 'under a second still asks')
end)

test('a saved position near the end of the file as it is now: from zero, not asked', function()
	write(LIST, list_json({entry(EP, 1300, nil, 1420)}))
	load(nil, true)
	open(EP, {duration = 1305})
	eq(#mock.commands, 0)
	eq(mock.props.pause, false)
end)

test('the language of the question follows hikari', function()
	write(LIST, list_json({entry(EP, 3723, nil, 5400)}))
	load(nil, true)
	open(EP, {duration = 5400})
	mock.set(MENU_TYPE_PROP, 'hikari-resume-prompt')
	mock.set_script_opt('hikari-language', 'en')
	local data, message = last_menu()
	eq(message, 'update-menu')
	eq(data.items[1].title, 'Continue from 1:02:03')
	eq(data.items[2].title, 'Start from the beginning')
end)

-- The list menu -------------------------------------------------------------------

test('list: newest first, title · time · date, then Clear history', function()
	local yesterday = os.time({year = 2026, month = 10, day = 11, hour = 23})
	local march = os.time({year = 2026, month = 3, day = 5, hour = 12})
	local old = os.time({year = 2025, month = 12, day = 31, hour = 12})
	write(LIST, list_json({entry('/a/old.mkv', 60, old), entry('/a/today.mkv', 754, NOW - 3600),
		entry('/a/march.mkv', 3723, march, 5400), entry('/a/yesterday.mkv', 90, yesterday)}))
	load(nil, true)
	for _, p in ipairs({'/a/old.mkv', '/a/today.mkv', '/a/march.mkv', '/a/yesterday.mkv'}) do mock.files[p] = {is_file = true} end
	mock.files['/a'] = {is_dir = true}
	eq(mock.props[AVAILABLE], true, 'published at start-up')
	mock.bindings['open-menu']()
	local data, message = last_menu()
	eq(message, 'open-menu'); eq(data.type, 'hikari-resume'); eq(data.title, 'Seguir viendo')
	eq(#data.items, 5)
	eq(data.items[1].title, 'today'); eq(data.items[1].hint, '12:34 / 23:40 · hoy')
	eq(data.items[2].title, 'yesterday'); eq(data.items[2].hint, '1:30 / 23:40 · ayer')
	eq(data.items[3].title, 'march'); eq(data.items[3].hint, '1:02:03 / 1:30:00 · 5 mar')
	eq(data.items[4].title, 'old'); eq(data.items[4].hint, '1:00 / 23:40 · 31 dic 2025')
	eq(data.items[4].separator, true)
	eq(data.items[5].title, 'Borrar historial')
	local v = data.items[1].value
	eq(v[3], 'open-file'); eq(v[4], '/a/today.mkv')
end)

test('dates in other languages', function()
	local s = load()
	local oct = os.time({year = 2026, month = 10, day = 1, hour = 12})
	local old = os.time({year = 2025, month = 5, day = 9, hour = 12})
	local cases = {
		en = {'today', 'yesterday', 'Oct 1', 'May 9, 2025'},
		de = {'heute', 'gestern', '1. Okt.', '9. Mai 2025'},
		ru = {'сегодня', 'вчера', '1 окт.', '9 мая 2025'},
		['zh-hans'] = {'今天', '昨天', '10月1日', '2025年5月9日'},
	}
	for lang, want in pairs(cases) do
		mock.set_script_opt('hikari-language', lang)
		eq(s.format_date(NOW - 60, NOW), want[1], lang)
		eq(s.format_date(NOW - 86400, NOW), want[2], lang)
		eq(s.format_date(oct, NOW), want[3], lang)
		eq(s.format_date(old, NOW), want[4], lang)
	end
	-- Just after midnight, a minute before is yesterday.
	mock.set_script_opt('hikari-language', 'zh-hans')
	local midnight = os.time({year = 2026, month = 3, day = 1, hour = 0, min = 0, sec = 30})
	eq(s.format_date(midnight - 60, midnight), '昨天', 'across a month')
	eq(s.format_clock(0), '0:00'); eq(s.format_clock(59.9), '0:59'); eq(s.format_clock(3600), '1:00:00')
end)

test('a file that cannot be found: grey row, Not available, kept', function()
	write(LIST, list_json({entry('/nas/ep1.mkv', 100), entry('/a/ep2.mkv', 200, NOW - 120)}))
	load(nil, true)
	mock.files['/a/ep2.mkv'] = {is_file = true}
	mock.files['/a'] = {is_dir = true}
	mock.bindings['open-menu']()
	local data = last_menu()
	eq(data.items[1].title, 'ep1'); eq(data.items[1].hint, 'No disponible')
	eq(data.items[1].muted, true); eq(data.items[1].selectable, false); eq(data.items[1].value, nil)
	eq(data.items[2].muted, nil)
	eq(#saved(), 2, 'still in the list')
end)

test('picking a row opens the file (only files of the list)', function()
	write(LIST, list_json({entry('/a/ep 1.mkv', 100)}))
	load(nil, true)
	mock.messages['open-file']('/a/ep 1.mkv')
	local c = last_command()
	eq(c[1], 'loadfile'); eq(c[2], '/a/ep 1.mkv'); eq(c[3], 'replace')
	local count = #mock.commands
	mock.messages['open-file']('/etc/passwd')
	mock.messages['open-file']('https://example.com/x')
	mock.messages['open-file'](nil)
	eq(#mock.commands, count, 'nothing else loaded')
end)

test('Clear history empties the list and the file; the button goes', function()
	write(LIST, list_json({entry('/a/ep1.mkv', 100), entry('/a/ep2.mkv', 200)}))
	local s = load(nil, true)
	mock.messages['clear-history']()
	eq(#saved(), 0)
	eq(mock.props[AVAILABLE], false)
	mock.bindings['open-menu']()
	local data = last_menu()
	eq(#data.items, 1); eq(data.items[1].title, 'No hay nada a medias'); eq(data.items[1].selectable, false)
	eq(#s.read_list(), 0)
end)

test('an open list is updated when a position is saved', function()
	load()
	mock.bindings['open-menu']()
	mock.set(MENU_TYPE_PROP, 'hikari-resume')
	mock.files[EP] = {is_file = true}
	mock.files['/mnt/anime'] = {is_dir = true}
	open(EP)
	play_to(100)
	local data, message = last_menu()
	eq(message, 'update-menu')
	eq(data.items[1].title, EP_TITLE); eq(data.items[1].hint, '1:40 / 23:40 · hoy')
end)

-- Storage -------------------------------------------------------------------------

test('at most history_size entries: the oldest go', function()
	local s = load({history_size = '3'})
	eq(s.opts.history_size, 3)
	for i = 1, 5 do
		s.clock.now = function() return NOW + i end
		open('/a/ep' .. i .. '.mkv')
		play_to(100)
		ends()
	end
	local e = saved()
	eq(#e, 3)
	eq(e[1].path, '/a/ep5.mkv'); eq(e[2].path, '/a/ep4.mkv'); eq(e[3].path, '/a/ep3.mkv')
	eq(load({history_size = '0'}).opts.history_size, 1)
	eq(load({history_size = '500'}).opts.history_size, 100)
	eq(load({history_size = 'x'}).opts.history_size, 30)
end)

test('a damaged list: empty, one warning, left alone until there is something to save', function()
	write(LIST, '{"version":1,"entries":[{"path":"/a/ep.mkv",')
	local s = load(nil, true)
	eq(#s.read_list(), 0)
	eq(#s.read_list(), 0)
	eq(#mock.logs.warn, 1, 'warned once')
	assert(mock.logs.warn[1]:find('damaged', 1, true))
	eq(mock.props[AVAILABLE], false)
	open(EP)
	eq(#mock.commands, 0, 'nothing asked')
	play_to(20)
	play_to(1400)
	eq(read(LIST), '{"version":1,"entries":[{"path":"/a/ep.mkv",', 'not rewritten')
	ends()
	open(EP)
	play_to(100)
	eq(saved()[1].position, 100, 'written once there is something to save')
end)

test('broken entries are dropped, good ones kept', function()
	write(LIST, '{"version":1,"entries":[' .. table.concat({
		'{"path":"https://x/ep.mkv?token=1","title":"x","position":100,"duration":1420,"updated":1}',
		'{"path":"relative.mkv","title":"x","position":100,"duration":1420,"updated":1}',
		'{"path":"/a/neg.mkv","title":"x","position":-1,"duration":1420,"updated":1}',
		'{"path":"/a/nodur.mkv","title":"x","position":100,"duration":0,"updated":1}',
		'{"path":"/a/ok.mkv","title":"","position":100,"duration":1420,"updated":5}',
		'{"path":"/a/ok.mkv","title":"older","position":50,"duration":1420,"updated":2}',
		'null', '"text"', '{"path":42}',
	}, ',') .. ']}')
	local s = load(nil, true)
	local list = s.read_list()
	eq(#list, 1)
	eq(list[1].path, '/a/ok.mkv'); eq(list[1].title, 'ok', 'title from the path'); eq(list[1].position, 100)
	write(LIST, '[]')
	eq(#s.read_list(), 0, 'no version')
	write(LIST, '{"version":1,"entries":[]}' .. string.rep(' ', 1024 * 1024))
	eq(#s.read_list(), 0, 'too big')
end)

test('written through a temporary file that is renamed: no leftovers', function()
	load()
	open(EP)
	play_to(100)
	local names = dir_names()
	eq(#names, 1, 'only the list: ' .. table.concat(names, ' '))
	eq(names[1], 'hikari-resume.json')
	-- A leftover (or a link) at the temporary name goes first: never written through.
	local target = DIR .. '/target.txt'
	write(target, 'keep')
	os.execute('ln -s "' .. target .. '" "' .. LIST .. '.' .. PID .. '-2.tmp"')
	play_to(200)
	eq(read(target), 'keep')
	eq(saved()[1].position, 200)
	-- Old temporary files of a dead mpv are removed on the first write; others not.
	os.remove(target)
end)

test('old temporary files of a dead mpv go on the first write; young ones and others stay', function()
	load()
	local names = {'hikari-resume.json.111-1.tmp', 'hikari-resume.json.222-3.tmp', 'hikari-resume.json.bak',
		'hikari-resume.json.x-1.tmp'}
	mock.dirs[DIR .. '/'] = names
	for i, name in ipairs(names) do
		write(DIR .. '/' .. name, 'x')
		mock.files[DIR .. '/' .. name] = {is_file = true, mtime = i == 2 and NOW - 60 or NOW - 2 * 86400}
	end
	open(EP)
	play_to(100)
	eq(read(DIR .. '/' .. names[1]), nil, 'old one removed')
	for i = 2, 4 do eq(read(DIR .. '/' .. names[i]), 'x', names[i]) end
	os.remove(DIR .. '/' .. names[1])
	write(DIR .. '/' .. names[1], 'x')
	play_to(200)
	eq(read(DIR .. '/' .. names[1]), 'x', 'only on the first write')
end)

test('Windows: the old list goes aside before the rename, and comes back if it fails', function()
	local function win(name, position)
		return {path = 'C:\\a\\' .. name, title = name, position = position, duration = 1420, updated = NOW - 60}
	end
	clean_dir()
	write(LIST, list_json({win('ep1.mkv', 100)}))
	load(nil, true)
	mock.props.platform = 'windows'
	local real, fail_next = os.rename, false
	-- rename() as on Windows: it never replaces an existing file.
	os.rename = function(from, to)
		local existing = io.open(to, 'rb')
		if existing then existing:close() return nil, to .. ': File exists' end
		if fail_next and to == LIST then fail_next = false return nil, to .. ': Permission denied' end
		return real(from, to)
	end
	local ok, err = pcall(function()
		open('C:\\a\\ep2.mkv', {wd = 'C:\\'})
		play_to(100)
		local e = saved()
		eq(#e, 2, 'replaced'); eq(e[1].path, 'C:\\a\\ep2.mkv')
		eq(#dir_names(), 1, 'nothing left aside')
		local before = read(LIST)
		fail_next = true
		play_to(200)
		eq(read(LIST), before, 'the old list is back')
		eq(#dir_names(), 1, 'no leftovers: ' .. table.concat(dir_names(), ' '))
		assert(mock.logs.warn[#mock.logs.warn]:find('Could not save', 1, true), 'warned')
	end)
	os.rename = real
	assert(ok, err)
end)

test('a link at the list name is replaced, never written through', function()
	clean_dir()
	local target = DIR .. '/elsewhere.json'
	write(target, list_json({entry('/a/ep1.mkv', 100)}))
	os.execute('ln -s "' .. target .. '" "' .. LIST .. '"')
	load(nil, true)
	open(EP)
	play_to(100)
	eq(read(target), list_json({entry('/a/ep1.mkv', 100)}), 'the target is untouched')
	local p = io.popen('test -L "' .. LIST .. '" && echo link || echo file')
	eq(p:read('*l'), 'file')
	p:close()
	eq(#saved(), 2, 'its entries carried over')
end)

test('two mpv at once: the list is read again and only our entry changes', function()
	load()
	open(EP)
	play_to(100)
	-- Another window saves its own file meanwhile.
	local list = saved()
	list[#list + 1] = entry('/b/other.mkv', 500, NOW - 5)
	write(LIST, list_json(list))
	play_to(200)
	local e = saved()
	eq(#e, 2)
	eq(e[1].path, EP); eq(e[1].position, 200)
	eq(e[2].path, '/b/other.mkv'); eq(e[2].position, 500)
	-- And when it finishes ours, theirs stays.
	play_to(1400)
	e = saved()
	eq(#e, 1); eq(e[1].path, '/b/other.mkv')
end)

test('Windows: paths compared without case', function()
	write(LIST, list_json({{path = 'C:\\Anime\\EP.mkv', title = 'EP', position = 754, duration = 1420, updated = NOW}}))
	load(nil, true)
	mock.props.platform = 'windows'
	open('c:/anime/ep.mkv', {wd = 'C:\\Users\\me'})
	eq(#commands_named('open-menu'), 1, 'asked')
	mock.messages['prompt-answer']('continue', '1')
	play_to(800)
	local e = saved()
	eq(#e, 1, 'one entry for the file')
	eq(e[1].path, 'c:\\anime\\ep.mkv'); eq(e[1].position, 800)
end)

test('enabled=no: nothing saved, nothing asked, no button, no menu', function()
	write(LIST, list_json({entry(EP, 754)}))
	load({enabled = 'no'}, true)
	eq(mock.props[AVAILABLE], false)
	eq(mock.events['file-loaded'], nil, 'no events')
	eq(#mock.periodic, 0, 'no timer')
	mock.bindings['open-menu']()
	eq(#mock.commands, 0)
	eq(saved()[1].position, 754)
end)

test('an ending chapter in the first half of the file is no ending', function()
	local s = load()
	local chapters = {{time = 0, title = 'Opening Credits'}, {time = 90, title = 'Part A'}, {time = 700, title = 'Ending'},
		{time = 720, title = 'Part B'}}
	eq(s.ending_start(chapters, 1420), nil, 'both before the half')
	eq(s.is_watched(100, 1420, chapters), false)
	eq(s.ending_start(chapters, 1400), 700, 'exactly at the half counts')
	open(EP, {chapters = chapters})
	play_to(100)
	eq(saved()[1].position, 100, 'saved, not taken as watched')
	play_to(800)
	eq(saved()[1].position, 800)
end)

test('a list with thousands of entries: only the newest history_size are used', function()
	local list = {}
	for i = 1, 3000 do list[i] = entry('/a/ep' .. i .. '.mkv', 100, NOW - 4000 + i) end
	write(LIST, list_json(list))
	local s = load({history_size = '5'}, true)
	local read_back = s.read_list()
	eq(#read_back, 5)
	eq(read_back[1].path, '/a/ep3000.mkv'); eq(read_back[5].path, '/a/ep2996.mkv')
	mock.bindings['open-menu']()
	eq(#last_menu().items, 6, 'five rows and Clear history')
	load(nil, true)
	mock.bindings['open-menu']()
	eq(#last_menu().items, 31, 'default size: thirty rows')
end)

test('roots: a share or mount that does not answer is asked once for all its files', function()
	local s = load()
	eq(s.root_of('\\\\NAS\\anime\\Frieren\\ep.mkv', true), '\\\\NAS\\anime\\')
	eq(s.root_of('C:\\Anime\\ep.mkv', true), 'C:\\')
	eq(s.root_of('/Volumes/data/anime/ep.mkv', false), '/Volumes/data')
	eq(s.root_of('/mnt/nas/anime/ep.mkv', false), '/mnt/nas')
	eq(s.root_of('/media/me/disk/ep.mkv', false), '/media/me/disk')
	eq(s.root_of('/run/media/me/disk/a/ep.mkv', false), '/run/media/me/disk')
	eq(s.root_of('/home/me/anime/ep.mkv', false), '/home/me/anime', 'otherwise the folder')
	eq(s.root_of('/ep.mkv', false), '/')
	local list = {}
	for i = 1, 6 do list[i] = entry('/mnt/nas/anime/ep' .. i .. '.mkv', 100, NOW - i) end
	list[7] = entry('/home/me/ep7.mkv', 100, NOW - 7)
	write(LIST, list_json(list))
	load(nil, true)
	mock.files['/home/me'] = {is_dir = true}
	mock.files['/home/me/ep7.mkv'] = {is_file = true}
	local utils = package.loaded['mp.utils']
	local real, asked = utils.file_info, {}
	utils.file_info = function(path)
		asked[#asked + 1] = path
		return real(path)
	end
	mock.bindings['open-menu']()
	local data = last_menu()
	for i = 1, 6 do eq(data.items[i].hint, 'No disponible', 'row ' .. i); eq(data.items[i].selectable, false) end
	eq(data.items[7].title, 'ep7'); eq(data.items[7].selectable, nil, 'a file that is there')
	local nas = 0
	for _, path in ipairs(asked) do if path:find('/mnt/nas', 1, true) then nas = nas + 1 end end
	eq(nas, 1, 'one question for the six files of the share: ' .. table.concat(asked, ' '))
	-- An update of the open menu asks nothing again; a new opening asks again.
	mock.set(MENU_TYPE_PROP, 'hikari-resume')
	local before = #asked
	mock.set_script_opt('hikari-language', 'en')
	eq(#asked, before, 'cached while open')
	mock.bindings['open-menu']()
	eq(#asked, before + 3, 'root of the share, folder and file of the other')
	utils.file_info = real
end)

test('a root that answers: each file is checked', function()
	write(LIST, list_json({entry('/mnt/nas/a.mkv', 100), entry('/mnt/nas/b.mkv', 100, NOW - 120)}))
	load(nil, true)
	mock.files['/mnt/nas'] = {is_dir = true}
	mock.files['/mnt/nas/a.mkv'] = {is_file = true}
	mock.bindings['open-menu']()
	local data = last_menu()
	eq(data.items[1].selectable, nil); eq(data.items[2].hint, 'No disponible')
end)

test('enabled=no: Alt+r says so on screen', function()
	load({enabled = 'no'})
	mock.bindings['open-menu']()
	eq(mock.osd[1], 'hikari: seguir viendo está desactivado')
	eq(#mock.commands, 0)
end)

test('after Clear history the file playing only comes back when it ends', function()
	load()
	open(EP)
	play_to(100)
	eq(#saved(), 1)
	mock.messages['clear-history']()
	play_to(200); play_to(300)
	eq(#saved(), 0, 'not saved again while it plays')
	eq(mock.props[AVAILABLE], false)
	ends()
	eq(saved()[1].position, 300, 'saved when it ends')
	eq(mock.props[AVAILABLE], true)
	open('/a/next.mkv')
	play_to(100)
	eq(#saved(), 2, 'the next file is saved as usual')
end)

test('the script makes no network connection and runs no program', function()
	local source = read(SCRIPT)
	for _, word in ipairs({'subprocess', 'curl', 'http', 'io.popen', 'os.execute', 'socket'}) do
		local code = source:gsub('%-%-[^\n]*', '')
		assert(not code:find(word, 1, true), word)
	end
end)

os.execute('rm -rf "' .. DIR .. '"')
print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
