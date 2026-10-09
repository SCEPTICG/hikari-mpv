-- Run from the repository root: lua tests/test_title.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/hikari-title.lua'
local SCRIPT_NAME = 'hikari_title'

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

local function load(opts)
	mock.install(SCRIPT_NAME)
	mock.script_opts = opts or {}
	HIKARI_TITLE_TEST = true
	local chunk = assert(loadfile(SCRIPT))
	return chunk()
end

-- Plays `path` as mpv would: sets `path` and fires start-file.
local function start(path)
	mock.props.path = path
	mock.events['start-file']()
	return mock.props['force-media-title']
end

local function utf8_len(s) return select(2, s:gsub('[^\128-\191]', '')) end

local SEANIME = 'https://media.example.net/3f1c2a9e-7b4d-4e2a-9c1f-0a1b2c3d4e5f?token=s3cr3tT0k3n'
	.. '&filename=Even.the.Student.Council.Has.Its.Holes.S01E01.1080p.UNCENSORED.ADN.WEB-DL.JPN.AAC2.0.H.264.MSubs-ToonsHub.mkv'
local SEANIME_RAW = 'Even.the.Student.Council.Has.Its.Holes.S01E01.1080p.UNCENSORED.ADN.WEB-DL.JPN.AAC2.0.H.264.MSubs-ToonsHub'
local SEANIME_TITLE = 'Even the Student Council Has Its Holes · T1 E01'

test('Seanime URL: title is the tidied filename, no extension or token', function()
	load()
	local title = start(SEANIME)
	eq(title, SEANIME_TITLE)
	assert(not title:find('token', 1, true) and not title:find('s3cr3t', 1, true), 'token leaked')
end)

test('filename is URL-decoded: %20, + and UTF-8', function()
	local t = load()
	eq(t.title_for('https://h/x?filename=Mi%20serie+-+01%C3%B1.mp4&token=a'), 'Mi serie - 01ñ')
	eq(t.title_for('http://h/x?token=a&filename=Show%2BPlus.WEBM'), 'Show+Plus', '%2B and upper-case ext')
end)

test('invalid %-sequences do not fail and are kept literally', function()
	local t = load()
	eq(t.title_for('https://h/x?filename=100%25%zz%4.mkv'), '100%%zz%4')
	eq(t.title_for('https://h/x?filename=%'), '%')
	eq(t.title_for('https://h/x?filename=%FF%FEAbc'), 'Abc', 'invalid UTF-8 bytes dropped')
end)

test('unknown extensions are kept', function()
	local t = load({['hikari-title-pretty'] = 'no'})
	eq(t.title_for('https://h/x?filename=Show.S01E01.part2'), 'Show.S01E01.part2')
end)

test('URL without filename: last path segment, no query', function()
	load()
	local title = start('https://h.example/api/stream/Episode%2001.mkv?token=abc&x=1')
	eq(title, 'Episode 01.mkv')
	local t = load()
	eq(t.title_for('https://h/a/b/?token=abc'), 'b', 'trailing slash')
	eq(t.title_for('https://user:pw@h.example:8000/?token=abc'), 'h.example:8000', 'empty path: host')
	eq(t.title_for('https://h/seg?token=abc&filename='), 'seg', 'empty filename')
	eq(t.title_for('https://h/a+b?token=x'), 'a+b', '+ is literal in the path')
end)

test('local files and URLs without a query are untouched', function()
	local t = load()
	for _, path in ipairs({
		'/home/u/Anime/Show.S01E01.mkv', 'C:\\Videos\\a.mkv?filename=x.mkv', 'file:///tmp/a.mkv?x=1',
		'https://h/video.mkv', 'https://h/video.mkv#t=10', 'ytdl://abc?filename=x', 'rtsp://h/a?token=1',
	}) do
		eq(t.title_for(path), nil, path)
	end
	start('/home/u/Anime/Show.S01E01.mkv')
	eq(mock.props['force-media-title'], nil, 'property not set')
end)

test('title does not stick to the next file', function()
	load()
	start(SEANIME)
	mock.end_file()
	eq(start('/home/u/local.mkv'), '', 'restored after a stream')
	mock.end_file()
	eq(start('https://h/b?token=1&filename=Second.mkv'), 'Second', 'second stream')
	mock.end_file()
	eq(mock.props['force-media-title'], '', 'restored at the end')
end)

test('a force-media-title set by the user is respected', function()
	load()
	mock.props['force-media-title'] = 'Mi título'
	eq(start(SEANIME), 'Mi título')
	mock.end_file()
	eq(mock.props['force-media-title'], 'Mi título', 'still there after the file')
end)

test('control characters, newlines and bidi overrides are removed', function()
	local t = load()
	eq(t.title_for('https://h/x?filename=A%0D%0AB%09C%00D%1BE%7FF%C2%85G%E2%80%AEH.mkv'), 'A B CDEFGH')
	eq(t.sanitize('  a \n\n b  '), 'a b')
	eq(t.title_for('https://h/x?filename=%0A%0D'), 'x', 'only control chars: falls back')
end)

test('long titles are cut on a character boundary with an ellipsis', function()
	local t = load()
	local long = string.rep('ñ', 400)
	local title = t.title_for('https://h/x?filename=' .. long)
	eq(utf8_len(title), t.MAX_CHARS + 1, 'length in characters')
	eq(title:sub(-3), '…', 'ellipsis')
	eq(t.sanitize(title), title, 'still valid UTF-8')
	eq(t.title_for('https://h/x?filename=' .. string.rep('A', t.MAX_CHARS)), string.rep('A', t.MAX_CHARS), 'exact limit kept')
end)

test('enabled=no disables the script', function()
	load({['hikari-title-enabled'] = 'no'})
	eq(start(SEANIME), nil)
end)

test('a playlist entry with its own title (#EXTINF) is respected', function()
	load()
	mock.props['playlist-playing-pos'] = 0
	mock.props['playlist/0/title'] = 'Canal 1'
	eq(start(SEANIME), nil, 'nothing set')
	mock.props['playlist/0/title'] = ''
	eq(start(SEANIME), SEANIME_TITLE, 'empty entry title: set')
end)

test('fallback title gives way to the container title tag', function()
	load()
	eq(start('https://jf.example/Videos/abc/stream?api_key=SECRET'), 'stream', 'fallback at start')
	mock.props['metadata/by-key/title'] = 'Episode 1 - Pilot'
	mock.events['file-loaded']()
	eq(mock.props['force-media-title'], '', 'cleared so the tag shows')
	mock.end_file()
	eq(mock.props['force-media-title'], '', 'restored at the end')
end)

test('fallback title stays when the file has no title tag', function()
	load()
	start('https://h/live/master.m3u8?token=abc')
	mock.props['metadata/by-key/title'] = nil
	mock.events['file-loaded']()
	eq(mock.props['force-media-title'], 'master.m3u8')
end)

test('fallback title is not withdrawn if something else replaced it', function()
	load()
	start('https://www.youtube.com/watch?v=abc')
	mock.props['force-media-title'] = 'Real video title' -- e.g. ytdl_hook
	mock.props['metadata/by-key/title'] = 'Tag'
	mock.events['file-loaded']()
	eq(mock.props['force-media-title'], 'Real video title')
end)

test('a title from filename= is kept even if the file has a title tag', function()
	load()
	start(SEANIME)
	mock.props['metadata/by-key/title'] = 'ToonsHub'
	mock.events['file-loaded']()
	eq(mock.props['force-media-title'], SEANIME_TITLE)
end)

test('huge inputs are cut before decoding and finish quickly', function()
	local t = load()
	local huge = string.rep('%E2%80%8B', 200000) .. string.rep('a', 100000)
	local clock = os.clock()
	local title = t.title_for('https://h/seg?filename=' .. huge .. '&x=1')
	local seg = t.title_for('https://h/' .. string.rep('b', 1000000) .. '?token=1')
	local deep = t.title_for('https://h/' .. string.rep('a', 50000) .. '/x/?token=1')
	assert(os.clock() - clock < 2, 'too slow: ' .. (os.clock() - clock))
	eq(title, 'seg', 'only zero-width chars survive the cut: fallback')
	eq(utf8_len(seg), t.MAX_CHARS + 1, 'segment truncated')
	eq(deep, 'x', 'long segment before the last one stays fast')
	local long = t.title_for('https://h/x?filename=' .. string.rep('c', 1000000))
	eq(utf8_len(long), t.MAX_CHARS + 1, 'filename truncated')
end)

test('invisible characters are removed; empty result falls back', function()
	local t = load()
	eq(t.title_for('https://h/x?filename=A%E2%80%8BB%E2%80%8FC%D8%9CD%EF%BB%BFE.mkv'), 'ABCDE')
	eq(t.title_for('https://h/seg?filename=%E2%80%8B%EF%BB%BF'), 'seg', 'only invisible: fallback')
end)

test('credentials without a path or query: bare host', function()
	local t = load()
	eq(t.title_for('https://user:pass@host.example'), 'host.example')
	eq(t.title_for('https://user:pass@host.example/'), 'host.example')
	eq(t.title_for('https://user:pass@host.example/video.mkv'), nil, 'with a path: untouched')
	eq(t.title_for('https://host.example/'), nil, 'no credentials: untouched')
end)

test('pretty: the two real Seanime releases', function()
	local t = load()
	eq(t.title_for('https://h/x?token=1&filename=Reborn.as.a.Space.Mercenary.I.Woke.Up.Piloting.the.Strongest.Starship'
		.. '.S01E01.1080p.CR.WEB-DL.DUAL.AAC2.0.H.264.MSubs-ToonsHub.mkv'),
		'Reborn as a Space Mercenary I Woke Up Piloting the Strongest Starship · T1 E01')
	eq(t.pretty_title(SEANIME_RAW), SEANIME_TITLE)
end)

test('pretty: season and episode markers', function()
	local p = load().pretty_title
	eq(p('Show.Name.S02E10.720p.WEB-DL'), 'Show Name · T2 E10')
	eq(p('show_name_s1e1'), 'Show name · T1 E01', 's1e1 and underscores (and the capital of an all lower-case name)')
	eq(p('Show.S01E01v2.1080p'), 'Show · T1 E01', 'version dropped')
	eq(p('Show.S01E01-E02.1080p'), 'Show · T1 E01-E02', 'range')
	eq(p('Show.S01E01E02'), 'Show · T1 E01-E02', 'range without dash')
	eq(p('Show.S10E105'), 'Show · T10 E105', 'three-digit episode')
	eq(p('Show.S00E03.1080p'), 'Show · Especial E03', 'season 0: special')
	eq(p('Show EP01 1080p'), 'Show · E01')
	eq(p('Show.E7.1080p'), 'Show · E07')
	eq(p('Show - Episode 7 [1080p]'), 'Show · E07')
	eq(p('Dr. Stone - 03 [720p]'), 'Dr. Stone · E03', 'dots kept in spaced names')
end)

test('pretty: anime releases with [Group] and technical brackets', function()
	local p = load().pretty_title
	eq(p('[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234]'), 'Sousou no Frieren · E05')
	eq(p('[Erai-raws] Show Name 2nd Season - 12v2 [1080p][Multiple Subtitle]'), 'Show Name 2nd Season · E12')
	eq(p('[SubsPlease] [Oshi no Ko] - 05 (1080p) [ABCD1234]'), '[Oshi no Ko] · E05', 'bracketed title kept')
	eq(p('Show - 2049'), 'Show - 2049', 'a year is not an episode')
end)

test('pretty: an all lower-case name gets a capital first letter', function()
	local p = load().pretty_title
	eq(p('[Erai-raws] jukishi - 15 [1080p CR WEB-DL AVC AAC][MultiSub][799A2A46]'), 'Jukishi · E15', 'the real Erai-raws release')
	eq(p('show.name.s01e02.1080p'), 'Show name · T1 E02', 'only the first letter')
	eq(p('some.film.2021.1080p.web-dl'), 'Some film (2021)', 'films too')
	eq(p('[Grp] sousou no Frieren - 05'), 'sousou no Frieren · E05', 'any capital: left as it is')
	eq(p('[Grp] DanMachi - 01'), 'DanMachi · E01')
	eq(p('[Grp] 86 eighty-six - 03'), '86 eighty-six · E03', 'not a letter first: left as it is')
	eq(p('[Grp] ñandú - 01'), 'ñandú · E01', 'non-ASCII first letter: left as it is')
	eq(p('[Grp] [oshi no ko] - 05'), '[oshi no ko] · E05', 'bracket first: left as it is')
end)

test('pretty: films and names without a marker', function()
	local p = load().pretty_title
	eq(p('Blade.Runner.2049.2017.1080p.BluRay.x264-GRP'), 'Blade Runner 2049 (2017)')
	eq(p('Movie.Name.2023.NF.WEB-DL.DDP5.1.H.264'), 'Movie Name (2023)', 'weak tags before the cut go too')
	eq(p('Movie (2023) (1080p BD HEVC)'), 'Movie (2023)')
	eq(p('Charlottes.Web.1973.1080p'), 'Charlottes Web (1973)', 'Web alone is a word')
	eq(p('Blade Runner 2049'), 'Blade Runner 2049', 'nothing technical: untouched')
	eq(p('Ace Attorney Dual Destinies'), 'Ace Attorney Dual Destinies', 'weak tag alone is not cut')
	eq(p('Mi serie - 01ñ'), 'Mi serie - 01ñ')
	eq(p('2012.1080p'), '2012', 'first word never cut')
end)

test('pretty: nothing sensible left gives the original name', function()
	local p = load().pretty_title
	eq(p(''), '')
	eq(p('S01E01.1080p'), 'S01E01.1080p', 'no series name')
	eq(p('[Group] [1080p]'), '[Group] [1080p]')
	eq(p('((('), '(((')
	eq(p('- 01'), '- 01')
end)

test('pretty: only filename= titles; pretty=no keeps the name', function()
	local t = load()
	eq(t.title_for('https://h/Show.S01E01.1080p?token=1'), 'Show.S01E01.1080p', 'path fallback untouched')
	eq(t.title_for('https://h/x?filename='), 'x', 'empty filename: fallback')
	load()
	mock.props['playlist-playing-pos'] = 0
	mock.props['playlist/0/title'] = 'Show.S01E01.1080p'
	eq(start(SEANIME), nil, 'playlist title left alone')
	load({['hikari-title-pretty'] = 'no'})
	eq(start(SEANIME), SEANIME_RAW)
end)

test('pretty: long and hostile names stay fast', function()
	local t = load()
	local clock = os.clock()
	local inputs = {
		-- Far beyond MAX_RAW (the real input): a quadratic step would take minutes.
		string.rep('Word.', 20000) .. 'S01E01.1080p',
		string.rep('[(', 20000), string.rep('(', 40000) .. ')', string.rep('- ', 20000),
		string.rep('S1E1-', 20000), string.rep('a.1080p.', 10000),
	}
	for _, s in ipairs(inputs) do
		local title = t.title_for('https://h/x?filename=' .. s)
		assert(title and t.sanitize(title) == title, 'valid title')
		t.pretty_title(s)
	end
	assert(os.clock() - clock < 2, 'too slow: ' .. (os.clock() - clock))
end)

test('the script avoids os.execute, io.popen and load*', function()
	local f = assert(io.open(SCRIPT, 'rb')); local src = f:read('*a'); f:close()
	for _, bad in ipairs({'os.execute', 'io.popen', 'loadstring', 'loadfile', 'dofile', 'load('}) do
		assert(not src:find(bad, 1, true), bad)
	end
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
