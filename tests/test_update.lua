-- Run from the repository root: lua tests/test_update.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/hikari-update.lua'
local SCRIPT_NAME = 'hikari_update'
local AVAILABLE = 'user-data/hikari_update/available'
local LATEST_URL = 'https://github.com/SCEPTICG/hikari-mpv/releases/latest'
local DAY = 24 * 3600
local T0 = 1800000000

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

local function tmp_path()
	local path = os.tmpname()
	os.remove(path)
	return path
end

local function read(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	local content = f:read('*a'); f:close()
	return content
end

local function write(path, content)
	local f = assert(io.open(path, 'wb')); f:write(content); f:close()
end

-- PATH holds a fake curl, so the tests do not depend on the machine having one
-- (the script only looks for it; the mock never runs anything).
local FAKE_BIN = tmp_path()
assert(os.execute('mkdir -p "' .. FAKE_BIN .. '"'))
write(FAKE_BIN .. '/curl', '#!/bin/sh\nexit 1\n')
-- SystemRoot as on Windows, whatever the machine running the tests.
local SYSTEM32 = 'C:\\Windows\\System32'
local fake_env = {SystemRoot = 'C:\\Windows'}
local system_getenv = os.getenv
os.getenv = function(name)
	if name == 'PATH' then return FAKE_BIN end
	if name == 'SystemRoot' then return fake_env.SystemRoot end
	return system_getenv(name)
end

-- curl's answer for a release tag, as GitHub sends it over HTTP/2.
local function answer(tag, eol)
	eol = eol or '\r\n'
	return 'HTTP/2 302' .. eol .. 'content-type: text/html; charset=utf-8' .. eol
		.. 'location: https://github.com/SCEPTICG/hikari-mpv/releases/tag/' .. tag .. eol .. eol
end

-- Loads the script with a record saying `version` (nil: no record) and the
-- state file `state_text` (nil: none). The clock reads `env.time`.
local function load(version, state_text, script_opts)
	mock.install(SCRIPT_NAME)
	mock.script_opts = script_opts or {}
	local env = {record = tmp_path(), state = tmp_path(), time = T0}
	if version then write(env.record, '# Written by the hikari installer\r\nhikari_version=' .. version .. '\r\n') end
	if state_text then write(env.state, state_text) end
	mock.expand['~~/hikari-installed.txt'] = env.record
	mock.expand['~~/hikari-update.txt'] = env.state
	mock.files[SYSTEM32 .. '\\curl.exe'] = {is_file = true}
	HIKARI_UPDATE_TEST = true
	local t = assert(loadfile(SCRIPT))()
	t.set_now(function() return env.time end)
	env.t = t
	return t, env
end

local function file_loaded() mock.events['file-loaded']() end
local function button() return mock.props[AVAILABLE] end
local function cleanup(env)
	os.remove(env.record); os.remove(env.state); os.remove(env.state .. '.tmp')
end

-- ---------------------------------------------------------------------------

test('Location: lower case, CRLF, HTTP/2', function()
	local t = load()
	eq(t.parse_location(answer('v0.3.1')), '0.3.1')
end)

test('Location: capitalised, LF only, HTTP/1.1, extra spaces', function()
	local t = load()
	eq(t.parse_location('HTTP/1.1 302 Found\nLocation:   https://github.com/SCEPTICG/hikari-mpv/releases/tag/v1.20.300  \n\n'), '1.20.300')
	eq(t.parse_location('HTTP/1.1 302 Found\r\nLOCATION: https://github.com/SCEPTICG/hikari-mpv/releases/tag/v2.0.0\r\n'), '2.0.0')
end)

test('Location: leading zeros are normalised', function()
	local t = load()
	eq(t.parse_location(answer('v0.03.010')), '0.3.10')
end)

test('Location: strange URLs give nothing', function()
	local t = load()
	local bad = {
		'https://github.com/SCEPTICG/hikari-mpv/releases',                       -- no release yet
		'https://github.com/SCEPTICG/hikari-mpv/releases/tag/0.3.1',             -- no v
		'https://github.com/SCEPTICG/hikari-mpv/releases/tag/v0.3',              -- two numbers
		'https://github.com/SCEPTICG/hikari-mpv/releases/tag/v0.3.1.4',          -- four numbers
		'https://github.com/SCEPTICG/hikari-mpv/releases/tag/v0.3.1-beta',       -- suffix
		'https://github.com/SCEPTICG/hikari-mpv/releases/tag/v0.3.x',            -- not a number
		'https://github.com/SCEPTICG/hikari-mpv/releases/tag/v1234567890.0.0',   -- too long
		'https://github.com/SCEPTICG/hikari-mpv/releases/tag/v0.3.1?x=1',        -- query
		'https://evil.example/SCEPTICG/hikari-mpv/releases/tag/v9.9.9',          -- other host
		'http://github.com/SCEPTICG/hikari-mpv/releases/tag/v9.9.9',             -- not https
		'https://github.com/other/hikari-mpv/releases/tag/v9.9.9',               -- other repo
		'https://github.com/SCEPTICG/sosc/releases/tag/v9.9.9',                  -- the old name (sosc until v0.3.0)
		'https://github.com/SCEPTICG/hikari/releases/tag/v9.9.9',                -- not the repository's name
		'https://github.com/SCEPTICG/hikari-mpv/releases/tag/v9.9.9/../../x',
		'/SCEPTICG/hikari-mpv/releases/tag/v9.9.9',                              -- relative
		'https://github.com/SCEPTICG/hikari-mpv/releases/tag/v',
		'',
	}
	for _, url in ipairs(bad) do
		eq(t.parse_location('HTTP/2 302\r\nlocation: ' .. url .. '\r\n'), nil, url)
	end
end)

test('Location: injection attempts give nothing', function()
	local t = load()
	local prefix = 'https://github.com/SCEPTICG/hikari-mpv/releases/tag/'
	for _, tag in ipairs({
		'v0.3.1" & calc & "', 'v0.3.1;rm -rf ~', 'v0.3.1|whoami', 'v0.3.1`id`', 'v0.3.1$(id)',
		'v0.3.1 v0.3.2', 'v0.3.1%0d%0a', 'v0.3.1\0', 'v0.3.1\tx',
	}) do
		eq(t.parse_location('HTTP/2 302\r\nlocation: ' .. prefix .. tag .. '\r\n'), nil, tag)
	end
	-- A second header line cannot smuggle a version in after a bad first one.
	eq(t.parse_location('HTTP/2 302\r\nlocation: https://evil.example/x\r\nlocation: ' .. prefix .. 'v9.9.9\r\n'), nil, 'first wins')
	-- A header named like location is not location.
	eq(t.parse_location('HTTP/2 302\r\nx-location: ' .. prefix .. 'v9.9.9\r\n'), nil, 'x-location')
	eq(t.parse_location(nil), nil, 'nil')
	eq(t.parse_location('garbage'), nil, 'garbage')
	eq(t.parse_location(''), nil, 'empty')
end)

test('versions compare as numbers', function()
	local t = load()
	eq(t.compare_versions('0.10.0', '0.9.9'), 1, '0.10.0 > 0.9.9')
	eq(t.compare_versions('0.9.9', '0.10.0'), -1)
	eq(t.compare_versions('1.0.0', '0.99.99'), 1)
	eq(t.compare_versions('0.3.1', '0.3.1'), 0)
	eq(t.compare_versions('0.3.10', '0.3.9'), 1)
	eq(t.compare_versions('dev', '0.3.1'), nil, 'dev')
	eq(t.is_newer('0.2.1', '0.3.0'), false)
	eq(t.normalize('v0.3.1'), nil, 'no v in versions')
	eq(t.normalize(' 0.3.1'), nil, 'no spaces')
end)

test('no record: nothing is checked, nothing shown', function()
	local _, env = load(nil)
	file_loaded()
	eq(#mock.async, 0, 'no curl')
	eq(button(), false, 'button off')
	eq(#mock.osd, 0, 'no notice')
	eq(read(env.state), nil, 'no state written')
	cleanup(env)
end)

test('dev version: nothing is checked', function()
	local _, env = load('dev')
	file_loaded()
	eq(#mock.async, 0, 'no curl')
	eq(read(env.state), nil, 'no state written')
	cleanup(env)
end)

test('record with spaces, CRLF and two versions: the last one counts', function()
	local t, env = load(nil)
	write(env.record, 'hikari_version=0.1.0\r\n  hikari_version = 0.2.1  \r\nhikari_commit=abc\r\n')
	eq(t.installed_version(), '0.2.1')
	cleanup(env)
end)

test('disabled: no request, no button, Alt+u says so', function()
	local t, env = load('0.2.1', nil, {['hikari-update-enabled'] = 'no'})
	eq(t.opts.enabled, false)
	file_loaded()
	eq(#mock.async, 0, 'no curl')
	eq(button(), false)
	mock.bindings['open-menu']()
	eq(#mock.commands, 0, 'no menu')
	assert(mock.osd[1]:find('desactivado', 1, true), 'osd: ' .. tostring(mock.osd[1]))
	cleanup(env)
end)

test('not at start-up: only on the first file-loaded', function()
	local _, env = load('0.2.1')
	eq(#mock.async, 0, 'nothing at start')
	eq(button(), false, 'button defined and off at start')
	file_loaded()
	eq(#mock.async, 1, 'one curl')
	cleanup(env)
end)

test('curl command: headers only, no redirects, short timeout, https only', function()
	local _, env = load('0.2.1')
	file_loaded()
	local cmd = mock.async[1].cmd
	eq(cmd.name, 'subprocess')
	eq(cmd.playback_only, false, 'playback_only')
	eq(cmd.capture_stdout, true, 'capture_stdout')
	local args = table.concat(cmd.args, ' ')
	eq(cmd.args[1], 'curl')
	eq(cmd.args[2], '-q', 'no .curlrc: -q first')
	eq(cmd.args[#cmd.args], LATEST_URL, 'url last')
	assert(args:find('--head', 1, true), args)
	assert(args:find('--max-time 10', 1, true), args)
	assert(args:find('--max-redirs 0', 1, true), args)
	assert(args:find('--proto =https', 1, true), args)
	assert(not args:find('-L', 1, true) and not args:find('--location', 1, true), 'never follows redirects')
	assert(not args:find('api.github.com', 1, true), 'no API')
	cleanup(env)
end)

test('newer version: notice, button on, state saved', function()
	local t, env = load('0.2.1')
	file_loaded()
	mock.finish_async(true, {status = 0, stdout = answer('v0.3.1'), error_string = ''})
	eq(button(), true, 'button on')
	mock.advance(5)
	eq(mock.osd[#mock.osd], 'hikari 0.3.1 disponible · Alt+u')
	local state = t.read_state()
	eq(state.latest, '0.3.1')
	eq(state.last_check, T0)
	eq(state.dismissed, nil)
	cleanup(env)
end)

test('same or older version: nothing shown', function()
	for _, tag in ipairs({'v0.2.1', 'v0.2.0', 'v0.1.9'}) do
		local _, env = load('0.2.1')
		file_loaded()
		mock.finish_async(true, {status = 0, stdout = answer(tag), error_string = ''})
		eq(button(), false, tag)
		eq(#mock.osd, 0, tag)
		cleanup(env)
	end
end)

test('only the first file-loaded checks', function()
	local _, env = load('0.2.1')
	file_loaded()
	mock.finish_async(true, {status = 0, stdout = answer('v0.3.1'), error_string = ''})
	file_loaded(); file_loaded()
	mock.advance(5)
	eq(#mock.async, 0, 'no second curl')
	eq(#mock.osd, 1, 'one notice')
	cleanup(env)
end)

test('inside the interval: no network, the saved version is announced', function()
	local _, env = load('0.2.1', 'last_check=' .. (T0 - 3600) .. '\nlatest=0.3.1\n')
	file_loaded()
	eq(#mock.async, 0, 'no curl')
	eq(button(), true)
	eq(#mock.osd, 0, 'not yet: the media title is on the OSD')
	mock.advance(3.9)
	eq(#mock.osd, 0, 'still not')
	mock.advance(0.2)
	eq(mock.osd[1], 'hikari 0.3.1 disponible · Alt+u', '4 s after the file loaded')
	cleanup(env)
end)

test('a slow answer is shown at once, a fast one waits for the 4 s', function()
	local _, env = load('0.2.1')
	file_loaded()
	mock.advance(6)
	mock.finish_async(true, {status = 0, stdout = answer('v0.3.1'), error_string = ''})
	eq(mock.osd[1], 'hikari 0.3.1 disponible · Alt+u', 'answer after 6 s: no extra wait')
	cleanup(env)
	_, env = load('0.2.1')
	file_loaded()
	mock.advance(1)
	mock.finish_async(true, {status = 0, stdout = answer('v0.3.1'), error_string = ''})
	eq(#mock.osd, 0, 'answer after 1 s: waits')
	mock.advance(3)
	eq(#mock.osd, 1, 'shown at 4 s, only once')
	mock.advance(10)
	eq(#mock.osd, 1)
	cleanup(env)
end)

test('inside the interval with nothing new: silence', function()
	local _, env = load('0.3.1', 'last_check=' .. (T0 - 3600) .. '\nlatest=0.3.1\n')
	file_loaded()
	eq(#mock.async, 0)
	eq(button(), false)
	eq(#mock.osd, 0)
	cleanup(env)
end)

test('interval elapsed: checks again', function()
	local _, env = load('0.2.1', 'last_check=' .. (T0 - DAY) .. '\nlatest=0.3.1\n')
	file_loaded()
	eq(#mock.async, 1, 'curl after 24 h')
	cleanup(env)
end)

test('interval_hours is read, and clamped to at least 1 hour', function()
	local t, env = load('0.2.1', 'last_check=' .. (T0 - 2 * 3600) .. '\n', {['hikari-update-interval_hours'] = '3'})
	eq(t.interval_seconds(), 3 * 3600)
	file_loaded()
	eq(#mock.async, 0, '2 h < 3 h')
	cleanup(env)
	t, env = load('0.2.1', nil, {['hikari-update-interval_hours'] = '0'})
	eq(t.interval_seconds(), 3600, 'min 1 h')
	cleanup(env)
	t, env = load('0.2.1', nil, {['hikari-update-interval_hours'] = 'nope'})
	eq(t.interval_seconds(), 24 * 3600, 'default for garbage')
	cleanup(env)
end)

test('a last check in the future (clock moved back) counts as old', function()
	local _, env = load('0.2.1', 'last_check=' .. (T0 + DAY) .. '\n')
	file_loaded()
	eq(#mock.async, 1)
	cleanup(env)
end)

test('no curl in PATH (outside Windows): no subprocess at all, saved version still used', function()
	local real_getenv = os.getenv
	os.getenv = function(name) if name == 'PATH' then return '/nonexistent-hikari-a:/nonexistent-hikari-b' end return real_getenv(name) end
	local ok, err = pcall(function()
		local _, env = load('0.2.1', 'last_check=' .. (T0 - 2 * DAY) .. '\nlatest=0.3.1\n')
		mock.props.platform = 'linux'
		file_loaded()
		eq(#mock.async, 0, 'no curl run')
		eq(button(), true, 'saved version announced')
		eq(#mock.logs.warn, 0, 'no warning')
		cleanup(env)
	end)
	os.getenv = real_getenv
	assert(ok, err)
end)

test('curl in PATH is found; on Windows PATH is not searched', function()
	local t = load()
	local dir = tmp_path()
	assert(os.execute('mkdir -p "' .. dir .. '"'))
	write(dir .. '/curl', '#!/bin/sh\n')
	local real_getenv = os.getenv
	os.getenv = function(name) if name == 'PATH' then return '/nonexistent-hikari:' .. dir end return real_getenv(name) end
	local ok, err = pcall(function()
		eq(t.in_path('curl'), true)
		eq(t.in_path('nope-hikari'), false)
		local _, env = load('0.2.1')
		mock.props.platform = 'windows'
		os.getenv = function(name) if name == 'PATH' then return '' end return real_getenv(name) end
		file_loaded()
		eq(#mock.async, 1, 'Windows: curl run without looking in PATH')
		eq(mock.async[1].cmd.args[1], SYSTEM32 .. '\\curl.exe', 'absolute path')
		eq(mock.async[1].cmd.args[2], '-q')
		cleanup(env)
	end)
	os.getenv = real_getenv
	os.remove(dir .. '/curl'); os.remove(dir)
	assert(ok, err)
end)

test('curl fails to start: silence, attempt saved, retried in the next interval', function()
	local t, env = load('0.2.1')
	file_loaded()
	mock.finish_async(true, {status = -3, error_string = 'init', stdout = ''})
	eq(button(), false)
	eq(#mock.osd, 0, 'no notice')
	eq(#mock.logs.warn, 0, 'no warning')
	eq(t.read_state().last_check, T0, 'attempt saved')
	cleanup(env)
end)

test('curl fails (network, timeout, mpv error): silence, saved version still used', function()
	local _, env = load('0.2.1', 'last_check=' .. (T0 - 2 * DAY) .. '\nlatest=0.3.1\n')
	file_loaded()
	mock.finish_async(true, {status = 28, error_string = '', stdout = '', stderr = 'timeout'})
	eq(button(), true, 'saved 0.3.1 still announced')
	mock.advance(5)
	eq(mock.osd[1], 'hikari 0.3.1 disponible · Alt+u')
	cleanup(env)
	_, env = load('0.2.1')
	file_loaded()
	mock.finish_async(false, nil, 'subprocess failed')
	eq(button(), false)
	eq(#mock.osd, 0)
	cleanup(env)
end)

test('curl answers without a version: latest kept as it was', function()
	local t, env = load('0.2.1', 'last_check=' .. (T0 - 2 * DAY) .. '\nlatest=0.2.1\n')
	file_loaded()
	mock.finish_async(true, {status = 0, error_string = '', stdout = 'HTTP/2 200\r\n\r\n'})
	eq(t.read_state().latest, '0.2.1')
	eq(button(), false)
	cleanup(env)
end)

test('corrupt state file: treated as never checked, then rewritten clean', function()
	local t, env = load('0.2.1', '\0\255garbage\nlast_check=yesterday\nlatest=0.3\ndismissed=v9\nlast_check=99999999999999999\n')
	local state = t.read_state()
	eq(state.last_check, nil); eq(state.latest, nil); eq(state.dismissed, nil)
	file_loaded()
	eq(#mock.async, 1, 'checks')
	mock.finish_async(true, {status = 0, stdout = answer('v0.3.1'), error_string = ''})
	local text = read(env.state)
	assert(not text:find('garbage', 1, true), 'rewritten')
	assert(text:find('\nlast_check=' .. T0 .. '\nlatest=0.3.1\n', 1, true), text)
	cleanup(env)
end)

test('state file is written atomically (no .tmp left)', function()
	local _, env = load('0.2.1')
	file_loaded()
	mock.finish_async(true, {status = 0, stdout = answer('v0.3.1'), error_string = ''})
	eq(read(env.state .. '.tmp'), nil)
	cleanup(env)
end)

test('dismissed version: no notice, no button; the next one is announced', function()
	local _, env = load('0.2.1', 'last_check=' .. (T0 - 3600) .. '\nlatest=0.3.1\ndismissed=0.3.1\n')
	file_loaded()
	eq(button(), false)
	eq(#mock.osd, 0)
	cleanup(env)
	_, env = load('0.2.1', 'last_check=' .. (T0 - 2 * DAY) .. '\nlatest=0.3.1\ndismissed=0.3.1\n')
	file_loaded()
	mock.finish_async(true, {status = 0, stdout = answer('v0.3.2'), error_string = ''})
	eq(button(), true)
	mock.advance(5)
	eq(mock.osd[1], 'hikari 0.3.2 disponible · Alt+u')
	cleanup(env)
end)

test('"No avisar de esta versión": saved, button off, menu closed', function()
	local t, env = load('0.2.1')
	file_loaded()
	mock.finish_async(true, {status = 0, stdout = answer('v0.3.1'), error_string = ''})
	mock.messages['dismiss']()
	eq(button(), false)
	eq(t.read_state().dismissed, '0.3.1')
	eq(t.read_state().latest, '0.3.1')
	eq(t.read_state().last_check, T0, 'last check kept')
	local last = mock.commands[#mock.commands]
	eq(table.concat(last, ' '), 'script-message-to uosc close-menu hikari-update')
	-- A new session does not announce it again.
	local _, env2 = load('0.2.1', read(env.state))
	file_loaded()
	eq(#mock.osd, 0); eq(button(), false)
	cleanup(env); cleanup(env2)
end)

test('button follows user-data on and off', function()
	local _, env = load('0.2.1')
	eq(mock.props[AVAILABLE], false, 'off at start')
	file_loaded()
	mock.finish_async(true, {status = 0, stdout = answer('v1.0.0'), error_string = ''})
	eq(mock.props[AVAILABLE], true, 'on')
	mock.messages['dismiss']()
	eq(mock.props[AVAILABLE], false, 'off after dismiss')
	cleanup(env)
end)

test('menu: three items, sends to uosc, release notes of that version', function()
	local t, env = load('0.2.1')
	file_loaded()
	mock.finish_async(true, {status = 0, stdout = answer('v0.3.1'), error_string = ''})
	mock.bindings['open-menu']()
	local cmd = mock.commands[#mock.commands]
	eq(cmd[1], 'script-message-to'); eq(cmd[2], 'uosc'); eq(cmd[3], 'open-menu')
	local data = t.menu_data()
	eq(data.type, 'hikari-update')
	eq(#data.items, 3)
	eq(data.items[1].title, 'Ver novedades de la 0.3.1')
	eq(data.items[2].title, 'Copiar comando de actualización')
	eq(data.items[3].title, 'No avisar de esta versión')
	eq(table.concat(data.items[1].value, ' '), 'script-message-to hikari_update open-notes')
	eq(table.concat(data.items[2].value, ' '), 'script-message-to hikari_update copy-command')
	eq(table.concat(data.items[3].value, ' '), 'script-message-to hikari_update dismiss')
	cleanup(env)
end)

test('menu after a dismissal: still opens, dismiss greyed out', function()
	local t, env = load('0.2.1', 'last_check=' .. (T0 - 3600) .. '\nlatest=0.3.1\ndismissed=0.3.1\n')
	file_loaded()
	mock.bindings['open-menu']()
	eq(mock.commands[#mock.commands][3], 'open-menu')
	eq(t.menu_data().items[3].selectable, false)
	cleanup(env)
end)

test('Alt+u with nothing new: an OSD line, no menu', function()
	local _, env = load('0.3.1', 'last_check=' .. (T0 - 3600) .. '\nlatest=0.3.1\n')
	file_loaded()
	mock.bindings['open-menu']()
	eq(#mock.commands, 0)
	eq(mock.osd[1], 'hikari 0.3.1: no hay ninguna versión nueva')
	cleanup(env)
	_, env = load('dev')
	mock.bindings['open-menu']()
	eq(#mock.commands, 0)
	assert(mock.osd[1]:find('desconocida', 1, true))
	cleanup(env)
end)

test('open notes: the command per platform, the URL of the version', function()
	local url = 'https://github.com/SCEPTICG/hikari-mpv/releases/tag/v0.3.1'
	for platform, want in pairs({
		windows = SYSTEM32 .. '\\cmd.exe /c start  ' .. url, darwin = 'open ' .. url, linux = 'xdg-open ' .. url, freebsd = 'xdg-open ' .. url,
	}) do
		local t, env = load('0.2.1', 'last_check=' .. (T0 - 3600) .. '\nlatest=0.3.1\n')
		mock.props.platform = platform
		file_loaded()
		eq(t.release_url('0.3.1'), url)
		mock.messages['open-notes']()
		local cmd = mock.finish_async(true, {status = 0, error_string = ''})
		eq(table.concat(cmd.args, ' '), want, platform)
		eq(cmd.detach, true, 'detached')
		eq(cmd.playback_only, false)
		if platform == 'windows' then eq(cmd.args[4], '', 'start "" title') end
		assert(mock.osd[#mock.osd]:find('navegador', 1, true))
		cleanup(env)
	end
end)

test('open notes: launcher missing -> the URL on screen', function()
	local _, env = load('0.2.1', 'last_check=' .. (T0 - 3600) .. '\nlatest=0.3.1\n')
	mock.props.platform = 'linux'
	file_loaded()
	mock.messages['open-notes']()
	mock.finish_async(true, {status = -3, error_string = 'init'})
	assert(mock.osd[#mock.osd]:find('https://github.com/SCEPTICG/hikari-mpv/releases/tag/v0.3.1', 1, true), mock.osd[#mock.osd])
	cleanup(env)
end)

test('open_url_args refuses anything but a plain https URL', function()
	local t = load()
	eq(t.open_url_args('https://github.com/x" & calc', 'windows'), nil)
	eq(t.open_url_args('https://github.com/x&calc', 'windows'), nil)
	eq(t.open_url_args('file:///etc/passwd', 'linux'), nil)
	eq(t.open_url_args(nil, 'linux'), nil)
	eq(t.release_url('dev'), nil)
end)

test('update command per platform', function()
	local t = load()
	eq(t.update_command('windows'), 'irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1 | iex')
	eq(t.update_command('darwin'), 'curl -fsSL https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.sh | bash')
	eq(t.update_command('linux'), 'curl -fsSL https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.sh | bash')
end)

test('copy: mpv clipboard property first', function()
	local _, env = load('0.2.1', 'last_check=' .. (T0 - 3600) .. '\nlatest=0.3.1\n')
	mock.props.platform = 'windows'
	file_loaded()
	mock.messages['copy-command']()
	eq(mock.props['clipboard/text'], 'irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1 | iex')
	eq(#mock.async, 0, 'no external tool')
	eq(mock.osd[#mock.osd], 'Comando copiado: pégalo en PowerShell')
	cleanup(env)
end)

test('copy: without the property, the tools of each platform in turn, via stdin', function()
	local cases = {
		windows = {SYSTEM32 .. '\\clip.exe', SYSTEM32 .. '\\WindowsPowerShell\\v1.0\\powershell.exe'},
		darwin = {'pbcopy'},
		linux = {'xclip', 'xsel'},
	}
	for platform, tools in pairs(cases) do
		local t, env = load('0.2.1')
		mock.props.platform = platform
		mock.set_fails['clipboard/text'] = true
		mock.messages['copy-command']()
		for i, tool in ipairs(tools) do
			local cmd = mock.async[1].cmd
			local program = platform == 'linux' and cmd.args[4] or cmd.args[1]
			eq(program, tool, platform .. ' tool ' .. i)
			eq(cmd.stdin_data, t.update_command(platform), 'stdin')
			eq(cmd.capture_stdout, false, 'not captured')
			mock.finish_async(true, {status = 1, error_string = ''})
		end
		eq(#mock.async, 0, platform .. ': no more tools')
		local osd = mock.osd[#mock.osd]
		assert(osd:find('No se pudo copiar', 1, true), osd)
		assert(osd:find(t.update_command(platform), 1, true), 'command on screen')
		cleanup(env)
	end
end)

test('copy: the first tool that works wins', function()
	local _, env = load('0.2.1')
	mock.props.platform = 'darwin'
	mock.set_fails['clipboard/text'] = true
	mock.messages['copy-command']()
	mock.finish_async(true, {status = 0, error_string = ''})
	eq(#mock.async, 0)
	eq(mock.osd[#mock.osd], 'Comando copiado: pégalo en un terminal')
	cleanup(env)
end)

test('copy: wl-copy first under Wayland', function()
	local t = load()
	local real_getenv = os.getenv
	os.getenv = function(name) if name == 'WAYLAND_DISPLAY' then return 'wayland-0' end return real_getenv(name) end
	local ok, err = pcall(function()
		local tools = t.clipboard_tools('linux')
		eq(tools[1][4], 'wl-copy')
		eq(tools[2][4], 'xclip')
	end)
	os.getenv = real_getenv
	assert(ok, err)
end)

test('copy on Linux: each tool through sh, stdout and stderr to /dev/null', function()
	local t = load()
	local real_getenv = os.getenv
	os.getenv = function(name) if name == 'WAYLAND_DISPLAY' then return nil end return real_getenv(name) end
	local ok, err = pcall(function()
		local tools = t.clipboard_tools('linux')
		eq(#tools, 2)
		eq(table.concat(tools[1], '|'), 'sh|-c|exec "$0" "$@" >/dev/null 2>&1|xclip|-selection|clipboard')
		eq(table.concat(tools[2], '|'), 'sh|-c|exec "$0" "$@" >/dev/null 2>&1|xsel|--clipboard|--input')
		os.getenv = function(name) if name == 'WAYLAND_DISPLAY' then return 'wayland-0' end return real_getenv(name) end
		tools = t.clipboard_tools('linux')
		eq(table.concat(tools[1], '|'), 'sh|-c|exec "$0" "$@" >/dev/null 2>&1|wl-copy')
		-- macOS and Windows run their programs directly.
		eq(table.concat(t.clipboard_tools('darwin')[1], '|'), 'pbcopy')
		eq(t.clipboard_tools('windows')[1][1], SYSTEM32 .. '\\clip.exe')
	end)
	os.getenv = real_getenv
	assert(ok, err)
end)

test('SystemRoot: only a plain drive path is used', function()
	local t = load()
	local good = {['C:\\Windows'] = 'C:\\Windows\\System32', ['C:\\Windows\\'] = 'C:\\Windows\\System32',
		['D:\\WINNT'] = 'D:\\WINNT\\System32', ['C:\\Program Files (x86)\\W'] = 'C:\\Program Files (x86)\\W\\System32'}
	local bad = {false, '', 'Windows', '\\Windows', 'C:', 'C:\\', 'C:Windows', 'C:/Windows', '\\\\server\\share',
		'C:\\Win"dows', 'C:\\Windows\n', 'C:\\%x%', 'C:\\a|b', 'C:\\a\\\\b', 'C:\\Windows\\\\', 'CC:\\Windows'}
	local saved = fake_env.SystemRoot
	local ok, err = pcall(function()
		for value, want in pairs(good) do
			fake_env.SystemRoot = value
			eq(t.system32(), want, value)
		end
		for _, value in ipairs(bad) do
			fake_env.SystemRoot = value or nil
			eq(t.system32(), nil, tostring(value))
		end
	end)
	fake_env.SystemRoot = saved
	assert(ok, err)
end)

test('Windows without a usable SystemRoot: nothing is ever started', function()
	local saved = fake_env.SystemRoot
	local ok, err = pcall(function()
		for _, value in ipairs({false, 'C:', '..\\evil', 'C:\\x"y'}) do
			fake_env.SystemRoot = value or nil
			local t, env = load('0.2.1', 'last_check=' .. (T0 - 2 * DAY) .. '\nlatest=0.3.1\n')
			mock.props.platform = 'windows'
			file_loaded()
			eq(#mock.async, 0, 'no curl: ' .. tostring(value))
			eq(button(), true, 'saved version still announced')
			eq(t.curl_program('windows'), nil)
			eq(t.open_url_args('https://github.com/x', 'windows'), nil)
			eq(#t.clipboard_tools('windows'), 0)
			mock.messages['open-notes']()
			eq(#mock.async, 0, 'no cmd')
			assert(mock.osd[#mock.osd]:find('releases/tag/v0.3.1', 1, true), mock.osd[#mock.osd])
			mock.set_fails['clipboard/text'] = true
			mock.messages['copy-command']()
			eq(#mock.async, 0, 'no clip, no powershell')
			assert(mock.osd[#mock.osd]:find('No se pudo copiar', 1, true), mock.osd[#mock.osd])
			cleanup(env)
		end
	end)
	fake_env.SystemRoot = saved
	assert(ok, err)
end)

test('Windows without System32\\curl.exe: no subprocess, no log noise', function()
	local _, env = load('0.2.1')
	mock.props.platform = 'windows'
	mock.files = {}
	file_loaded()
	eq(#mock.async, 0, 'no curl run')
	eq(#mock.logs.warn, 0, 'no warning')
	cleanup(env)
	_, env = load('0.2.1')
	mock.props.platform = 'windows'
	mock.files[SYSTEM32 .. '\\curl.exe'] = {is_file = false}
	file_loaded()
	eq(#mock.async, 0, 'a folder named curl.exe is not curl')
	cleanup(env)
end)

test('state file: a link left at the .tmp path is replaced, not followed', function()
	local t = load()
	local target, path = tmp_path(), tmp_path()
	write(target, 'untouched')
	assert(os.execute('ln -s "' .. target .. '" "' .. path .. '.tmp"'))
	assert(t.write_file_atomic(path, 'new\n'))
	eq(read(target), 'untouched', 'link target')
	eq(read(path), 'new\n')
	eq(read(path .. '.tmp'), nil, 'no .tmp left')
	os.remove(target); os.remove(path)
end)

test('platform: mpv property, else a guess', function()
	local t = load()
	mock.props.platform = 'darwin'
	eq(t.platform(), 'darwin')
	mock.props.platform = nil
	local guess = t.platform()
	assert(guess == 'windows' or guess == 'darwin' or guess == 'linux', guess)
end)

test('two quick file-loaded events in another mpv never mean two requests', function()
	local t, env = load('0.2.1')
	file_loaded()
	eq(t.read_state().last_check, T0, 'attempt saved before the answer')
	local _, env2 = load('0.2.1', read(env.state))
	file_loaded()
	eq(#mock.async, 0, 'second mpv: no request')
	cleanup(env); cleanup(env2)
end)

test('state file cannot be written: a warning, still announced', function()
	local _, env = load('0.2.1')
	mock.expand['~~/hikari-update.txt'] = '/nonexistent-dir-hikari/hikari-update.txt'
	file_loaded()
	mock.finish_async(true, {status = 0, stdout = answer('v0.3.1'), error_string = ''})
	assert(#mock.logs.warn >= 1, 'warned')
	eq(button(), true)
	cleanup(env)
end)

os.getenv = system_getenv
os.remove(FAKE_BIN .. '/curl'); os.remove(FAKE_BIN)
print(('\n%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
