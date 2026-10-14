-- Run from the repository root: lua tests/test_release.lua
-- The release names module (script-modules/hikari-release.lua): what
-- hikari-title.lua and hikari-resume.lua read from a file name. The titles
-- themselves are tested through hikari-title in test_title.lua.
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local MODULE = 'portable_config/script-modules/hikari-release.lua'

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
	local f = assert(io.open(path, 'rb'))
	local s = f:read('*a')
	f:close()
	return s
end

-- A fresh module, loaded the way the scripts do (hikari-i18n first, from
-- ~~/script-modules in package.path), in Spanish.
local function fresh()
	mock.install('hikari_test')
	mock.script_opts = {['hikari-language'] = 'es'}
	local saved = package.path
	package.path = 'portable_config/script-modules/?.lua;' .. saved
	require('hikari-i18n')
	local release = require('hikari-release')
	package.path = saved
	return release
end

test('the module gives the titles hikari-title gave', function()
	local r = fresh()
	eq(r.pretty_title('[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234]'), 'Sousou no Frieren · E05')
	eq(r.pretty_title('Show.Name.S01E05.1080p.WEB-DL'), 'Show Name · T1 E05')
	eq(r.pretty_title('Show S01E05', 'en'), 'Show · S1 E05')
	local info = r.release_for('/a/[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv')
	eq(info.series, 'Sousou no Frieren'); eq(info.episode, 5); eq(info.anime, true)
	eq(r.release_for('https://h/x?token=a&filename=Show%20-%2005.mkv').episode, 5)
	eq(r.release_name('/a/b/Show - 05.mkv'), 'Show - 05')
	eq(r.MAX_CHARS, 150); eq(r.MAX_RAW, 1800)
end)

test('episodes: `- 05` and `S01E05` are the same series; another season is another', function()
	local r = fresh()
	local a = r.episode_of('[SubsPlease] Sousou no Frieren - 05 (1080p).mkv')
	local b = r.episode_of('Sousou.no.Frieren.S01E06.1080p.WEB-DL.mkv')
	local c = r.episode_of('Sousou no Frieren S02E01.mkv')
	eq(a.key, 'sousou no frieren|1'); eq(a.episode, 5); eq(a.season, 1); eq(a.series, 'Sousou no Frieren')
	eq(b.key, a.key, 'same series'); eq(b.episode, 6)
	eq(c.key, 'sousou no frieren|2'); eq(c.season, 2)
	eq(r.episode_of('Sousou no Frieren Season 2 - 03.mkv').key, 'sousou no frieren|2', 'a season before the number')
	eq(r.episode_of("FRIEREN'S - 01.mkv").key, r.episode_of("frierens - 02.mkv").key, 'case and apostrophes')
	eq(r.episode_of('Show.S01E05.1080p.WEB-DL.mkv').key, 'show|1', 'not anime: still an episode')
end)

test('episodes: specials, OVAs, ranges, half episodes, films and other files are not', function()
	local r = fresh()
	for _, name in ipairs({'Show - 12.5.mkv', 'Show - OVA.mkv', 'Show OVA 2.mkv', 'Show SP01.mkv', 'Show Special 1.mkv',
		'Show S00E03.mkv', 'Show S01E01-E02.mkv', 'Show - 01-02.mkv', 'Blade Runner 2049 (2017) 1080p.mkv',
		'Holiday video.mkv', 'Show - 05.srt', 'Show - 05', '- 05.mkv', 'a/Show - 05.mkv', 'a\\Show - 05.mkv', ''}) do
		eq(r.episode_of(name), nil, name)
	end
	eq(r.episode_of(nil), nil); eq(r.episode_of(42), nil)
	eq(r.episode_of('Show - 05.MKV').episode, 5, 'extension case')
end)

test('groups: the [Group] in front, or a -Group at the end', function()
	local r = fresh()
	eq(r.episode_of('[SubsPlease] Show - 05 (1080p).mkv').group, 'subsplease')
	eq(r.episode_of('Show.S01E05.1080p.WEB-DL.x264-GRP.mkv').group, 'grp')
	eq(r.episode_of('Show - 05.mkv').group, nil)
end)

test('normalize: as hikari-aniskip does', function()
	local r = fresh()
	mock.install('hikari_test')
	local aniskip = assert(loadfile('portable_config/script-modules/hikari-aniskip.lua'))()
	for _, text in ipairs({'Sousou no Frieren', "JoJo's Bizarre Adventure", 'Hunter × Hunter', 'Re:Zero',
		'  Spaced   Out  ', 'Ñandú – ÁÉ', 'Dr. Stone'}) do
		eq(r.normalize(text), aniskip.normalize(text), text)
	end
end)

local function names(list) return list end

test('next episode: the smallest number above, gaps and order do not matter', function()
	local r = fresh()
	local folder = names({'Show - 08.mkv', 'Show - 05.mkv', 'Show - 07.mkv', 'Show - 03.mkv', 'Show - 07.srt'})
	eq(r.next_episode('Show - 05.mkv', folder), 'Show - 07.mkv')
	eq(r.next_episode('Show - 07.mkv', folder), 'Show - 08.mkv')
	eq(r.next_episode('Show - 08.mkv', folder), nil, 'the last one')
	eq(r.next_episode('Show - 03.mkv', {'Show S01E04.mkv'}), 'Show S01E04.mkv', 'another way of writing it')
end)

test('next episode: other series and seasons in the same folder are left out', function()
	local r = fresh()
	local folder = {'Show - 05.mkv', 'Other Show - 06.mkv', 'Show S02E06.mkv', 'Show - 06.5.mkv', 'Show SP06.mkv',
		'Show - 07.mkv'}
	eq(r.next_episode('Show - 05.mkv', folder), 'Show - 07.mkv')
	eq(r.next_episode('Show S02E01.mkv', folder), 'Show S02E06.mkv')
end)

test('next episode: of several versions, the same group, otherwise the first by name', function()
	local r = fresh()
	local folder = {'[B] Show - 06 (1080p).mkv', '[A] Show - 06 (1080p).mkv', '[A] Show - 06 (720p).mkv', '[C] Show - 07.mkv'}
	eq(r.next_episode('[A] Show - 05 (1080p).mkv', folder), '[A] Show - 06 (1080p).mkv', 'same group, first by name')
	eq(r.next_episode('[C] Show - 05.mkv', folder), '[A] Show - 06 (1080p).mkv', 'no 06 of its group: first by name')
	eq(r.next_episode('Show - 05.mkv', {'show - 06 b.mkv', 'Show - 06 a.mkv'}), 'Show - 06 a.mkv', 'by name, without case')
end)

test('next episode: a folder over the limit has none; junk is ignored', function()
	local r = fresh()
	local folder = {}
	for i = 1, 100 do folder[i] = 'file' .. i .. '.mkv' end
	folder[#folder + 1] = 'Show - 06.mkv'
	eq(r.next_episode('Show - 05.mkv', folder, 101), 'Show - 06.mkv')
	eq(r.next_episode('Show - 05.mkv', folder, 100), nil, 'over the limit')
	eq(r.next_episode('Show - 05.mkv', nil), nil, 'unreadable')
	eq(r.next_episode('Holiday.mkv', folder), nil, 'not an episode')
	eq(r.next_episode('Show - 05.mkv', {42, false, 'Show - 06.mkv'}), 'Show - 06.mkv')
end)

test('hostile names stay fast', function()
	local r = fresh()
	local folder = {}
	-- A folder full of the longest names a file system takes (255 bytes).
	for i = 1, 2000 do folder[i] = (string.rep('[(', 60) .. ' Show - ' .. i .. string.rep(' x', 60)):sub(1, 250) .. '.mkv' end
	local clock = os.clock()
	r.next_episode(folder[1], folder, 2000)
	r.episode_of(string.rep('a', 100000) .. ' - 05.mkv')
	assert(os.clock() - clock < 5, 'too slow: ' .. (os.clock() - clock))
end)

test('the module avoids os.execute, io.popen, io.open and load*', function()
	local src = read(MODULE)
	for _, bad in ipairs({'os.execute', 'io.popen', 'io.open', 'loadstring', 'loadfile', 'dofile', 'load('}) do
		assert(not src:find(bad, 1, true), bad)
	end
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
