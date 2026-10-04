-- Run from the repository root: lua tests/test_title.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/sosc-title.lua'
local SCRIPT_NAME = 'sosc_title'

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
	SOSC_TITLE_TEST = true
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

test('Seanime URL: title is the filename without extension or token', function()
	load()
	local title = start(SEANIME)
	eq(title, 'Even.the.Student.Council.Has.Its.Holes.S01E01.1080p.UNCENSORED.ADN.WEB-DL.JPN.AAC2.0.H.264.MSubs-ToonsHub')
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
	eq(t.title_for('https://h/x?filename=%FF%FEabc'), 'abc', 'invalid UTF-8 bytes dropped')
end)

test('unknown extensions are kept', function()
	local t = load()
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
	eq(t.title_for('https://h/x?filename=' .. string.rep('a', t.MAX_CHARS)), string.rep('a', t.MAX_CHARS), 'exact limit kept')
end)

test('enabled=no disables the script', function()
	load({['sosc-title-enabled'] = 'no'})
	eq(start(SEANIME), nil)
end)

test('the script avoids os.execute, io.popen and load*', function()
	local f = assert(io.open(SCRIPT, 'rb')); local src = f:read('*a'); f:close()
	for _, bad in ipairs({'os.execute', 'io.popen', 'loadstring', 'loadfile', 'dofile', 'load('}) do
		assert(not src:find(bad, 1, true), bad)
	end
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
