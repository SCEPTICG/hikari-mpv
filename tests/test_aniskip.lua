-- Run from the repository root: lua tests/test_aniskip.lua
--
-- script-modules/hikari-aniskip.lua (AniSkip lookups) and its use in
-- hikari-skip.lua. The answers in tests/data/aniskip/ were recorded from the
-- real services (AniList, AniSkip) in October 2026, except the Jikan one,
-- written from Jikan's v4 documentation (api.jikan.moe was not reachable from
-- the machine that recorded the others).
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local MODULE = 'portable_config/script-modules/hikari-aniskip.lua'
local SKIP = 'portable_config/scripts/hikari-skip.lua'
local DATA = 'tests/data/aniskip/'
local RELEASE_PROP = 'user-data/hikari_title/release'
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

local function near(actual, expected, what)
	if type(actual) ~= 'number' or math.abs(actual - expected) > 1e-6 then
		error((what or 'value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
	end
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

local function tmp_path()
	local path = os.tmpname()
	os.remove(path)
	return path
end

local function data(name) return assert(read(DATA .. name), name) end

-- PATH holds a fake curl (the module only looks for it; the mock runs nothing).
local FAKE_BIN = tmp_path()
assert(os.execute('mkdir -p "' .. FAKE_BIN .. '"'))
write(FAKE_BIN .. '/curl', '#!/bin/sh\nexit 1\n')
local fake_env = {PATH = FAKE_BIN, SystemRoot = 'C:\\Windows'}
local system_getenv = os.getenv
os.getenv = function(name)
	if name == 'PATH' or name == 'SystemRoot' then return fake_env[name] end
	return system_getenv(name)
end

local CACHE = tmp_path()
local clock = {t = T0}

-- Fresh mocks and module, with an empty cache.
local function load_module()
	mock.install('hikari_skip')
	mock.props.platform = 'linux'
	mock.expand['~~/hikari-aniskip.json'] = CACHE
	os.remove(CACHE); os.remove(CACHE .. '.tmp')
	clock.t = T0
	fake_env.PATH = FAKE_BIN
	local m = dofile(MODULE)
	m.now = function() return clock.t end
	return m
end

-- curl's answer, as mpv gives it.
local function ok_answer(body) return true, {status = 0, stdout = body, stderr = '', error_string = ''} end

local function frieren(episode, season)
	return {series = 'Sousou no Frieren', episode = episode or 5, season = season, anime = true}
end

-- Runs lookup and returns a table that gets the answer.
local function lookup(m, release)
	local got = {called = false}
	m.lookup(assert(m.query(release), 'query'), function(results)
		got.called, got.results = true, results
	end)
	return got
end

local function arg_index(args, value)
	for i, a in ipairs(args) do if a == value then return i end end
	return nil
end

-- ---------------------------------------------------------------------------
-- Matching
-- ---------------------------------------------------------------------------

test('names are normalised: case, punctuation, apostrophes, ×', function()
	local m = load_module()
	eq(m.normalize('Frieren: Beyond Journey’s End'), 'frieren beyond journeys end')
	eq(m.normalize("Frieren - Beyond Journey's End"), 'frieren beyond journeys end')
	eq(m.normalize('HUNTER×HUNTER (2011)'), 'hunter x hunter 2011')
	eq(m.normalize('  Re:Zero  kara '), 're zero kara')
	eq(m.normalize('葬送のフリーレン'), '葬送のフリーレン')
	eq(m.normalize(nil), '')
end)

test('AniList (recorded): Frieren and its seasons by romaji and English name', function()
	local m = load_module()
	local list = assert(m.parse_anilist(data('anilist-sousou-no-frieren.json')))
	eq(#list, 6, 'series')
	local mal, episodes = m.pick(list, 'Sousou no Frieren')
	eq(mal, 52991, 'season 1'); eq(episodes, 28, 'episode count')
	eq(m.pick(list, 'Sousou no Frieren', 1), 52991, 'season 1 said')
	eq(m.pick(list, 'Sousou no Frieren', 2), 59978, '2nd Season')
	eq(m.pick(list, 'Sousou no Frieren', 3), 63816, '3rd Season')
	eq(m.pick(list, 'Sousou no Frieren', 4), nil, 'no 4th season')
	eq(m.pick(list, "Frieren - Beyond Journey's End"), 52991, 'English name')
	eq(m.pick(list, 'Frieren Beyond Journeys End', 2), 59978, 'English name, Season 2')
	eq(m.pick(list, '葬送のフリーレン'), 52991, 'native name')
	eq(m.pick(list, 'Frieren at the Funeral'), 52991, 'synonym')
	-- Close is not enough.
	eq(m.pick(list, 'Frieren'), nil, 'part of the name')
	eq(m.pick(list, 'Sousou no Frieren no Mahou'), nil, 'an ONA with no MAL id')
end)

test('AniList (recorded): Season N, N and the base name of long franchises', function()
	local m = load_module()
	local aot = assert(m.parse_anilist(data('anilist-shingeki-no-kyojin.json')))
	eq(m.pick(aot, 'Shingeki no Kyojin'), 16498, 'AoT 1')
	eq(m.pick(aot, 'Shingeki no Kyojin', 2), 25777, 'AoT Season 2')
	eq(m.pick(aot, 'Attack on Titan', 3), 35760, 'English, Season 3')
	eq(m.pick(aot, 'Shingeki no Kyojin', 4), 40028, 'The Final Season, by its synonym "Season 4"')
	local mha = assert(m.parse_anilist(data('anilist-boku-no-hero-academia.json')))
	eq(m.pick(mha, 'Boku no Hero Academia'), 31964, 'MHA 1')
	eq(m.pick(mha, 'Boku no Hero Academia', 6), 49918, '"Boku no Hero Academia 6"')
	eq(m.pick(mha, 'My Hero Academia', 2), 33486, 'English Season 2')
	local kusuriya = assert(m.parse_anilist(data('anilist-kusuriya-no-hitorigoto-2nd-season.json')))
	eq(m.pick(kusuriya, 'Kusuriya no Hitorigoto', 2), 58514, '2nd Season')
	eq(m.pick(kusuriya, 'The Apothecary Diaries', 2), 58514, 'English Season 2')
end)

test('a match must be clear: two ids, movies, specials and missing ids give nothing', function()
	local m = load_module()
	local function c(mal, format, names) return {mal = mal, format = format, names = names} end
	eq(m.pick({c(1, 'TV', {'Show'}), c(2, 'TV', {'Show'})}, 'Show'), nil, 'two ids')
	eq(m.pick({c(1, 'TV', {'Show'}), c(1, 'TV', {'SHOW!'})}, 'Show'), 1, 'same id twice')
	eq(m.pick({c(1, 'MOVIE', {'Show'})}, 'Show'), nil, 'movie')
	eq(m.pick({c(1, 'OVA', {'Show'}), c(2, 'TV', {'Show'})}, 'Show'), 2, 'OVA ignored')
	eq(m.pick({c(1, 'SPECIAL', {'Show'})}, 'Show'), nil, 'special')
	eq(m.pick({c(nil, 'TV', {'Show'})}, 'Show'), nil, 'no MAL id')
	eq(m.pick({c(3, 'ONA', {'Show'})}, 'Show'), 3, 'ONA')
	eq(m.pick({c(4, 'TV_SHORT', {'Show 2nd Season'})}, 'Show', 2), 4, 'TV_SHORT')
	eq(m.pick({c(5, 'TV', {'Show 2'})}, 'Show'), nil, 'a sequel is not season 1')
	eq(m.pick({}, 'Show'), nil, 'nothing found')
end)

test('AniList: errors, wrong types and oversized answers are refused', function()
	local m = load_module()
	eq(m.parse_anilist(nil), nil, 'no answer')
	eq(m.parse_anilist(''), nil, 'empty')
	eq(m.parse_anilist('<html>502 Bad Gateway</html>'), nil, 'HTML')
	eq(m.parse_anilist('{"data":null,"errors":[{"message":"Too Many Requests","status":429}]}'), nil, 'rate limit')
	eq(m.parse_anilist('{"data":{"Page":{"media":{"idMal":1}}}}'), nil, 'media not a list')
	eq(m.parse_anilist('{"data":{"Page":{}}}'), nil, 'no media')
	eq(m.parse_anilist('[1,2,3]'), nil, 'an array')
	eq(m.parse_anilist('{"data":{"Page":{"media":[]}}} trailing'), nil, 'trailing garbage')
	local many = {}
	for i = 1, 51 do many[i] = '{"idMal":' .. i .. ',"format":"TV","title":{"romaji":"S"}}' end
	eq(m.parse_anilist('{"data":{"Page":{"media":[' .. table.concat(many, ',') .. ']}}}'), nil, 'too many')
	local huge = '{"data":{"Page":{"media":[{"idMal":1,"format":"TV","title":{"romaji":"' .. string.rep('a', 300000) .. '"}}]}}}'
	eq(m.parse_anilist(huge), nil, 'too long')
	-- Bad fields inside a valid answer are dropped one by one.
	local list = assert(m.parse_anilist('{"data":{"Page":{"media":['
		.. '{"idMal":"52991","format":"TV","title":{"romaji":"A"}},'
		.. '{"idMal":1.5,"format":"TV","title":{"romaji":"B"}},'
		.. '{"idMal":-3,"format":"TV","title":{"romaji":"C"}},'
		.. '{"idMal":7,"format":"TV","episodes":"12","title":{"romaji":"Bad\\nname","english":7},"synonyms":"D"},'
		.. '"not a table"'
		.. ']}}}'))
	eq(#list, 4, 'tables kept')
	eq(list[1].mal, nil, 'string id'); eq(list[2].mal, nil, 'fraction'); eq(list[3].mal, nil, 'negative')
	eq(list[4].mal, 7); eq(list[4].episodes, nil, 'string episodes'); eq(#list[4].names, 0, 'bad names dropped')
end)

test('Jikan (documented format): same matching', function()
	local m = load_module()
	local list = assert(m.parse_jikan(data('jikan-sousou-no-frieren.json')))
	eq(#list, 3)
	eq(m.pick(list, 'Sousou no Frieren'), 52991)
	eq(m.pick(list, "Frieren: Beyond Journey's End", 2), 59978)
	eq(m.parse_jikan('{"status":429,"type":"RateLimitException","message":"..."}'), nil, 'rate limit')
	eq(m.parse_jikan('{"data":"x"}'), nil, 'data not a list')
end)

test('AniSkip (recorded): results, and "not found" as an empty list', function()
	local m = load_module()
	local results = assert(m.parse_aniskip(data('aniskip-52991-5.json')))
	eq(#results, 2)
	eq(results[1].type, 'op'); near(results[1].start, 153.346); near(results[1].finish, 243.346)
	near(results[1].length, 1469.9685)
	eq(results[2].type, 'ed'); near(results[2].start, 1370); near(results[2].finish, 1460)
	local none = assert(m.parse_aniskip(data('aniskip-not-found.json')))
	eq(#none, 0, 'not found')
end)

test('AniSkip: impossible or hostile results are dropped, broken answers refused', function()
	local m = load_module()
	local function one(result)
		local list = m.parse_aniskip('{"found":true,"results":[' .. result .. ']}')
		return list and #list
	end
	local function r(kind, s, e, len)
		return string.format('{"interval":{"startTime":%s,"endTime":%s},"skipType":%s,"episodeLength":%s}', s, e, kind, len)
	end
	eq(one(r('"op"', 10, 100, 1400)), 1, 'valid')
	eq(one(r('"mixed-ed"', 1300, 1390, 1400)), 1, 'mixed-ed')
	eq(one(r('"recap"', 10, 100, 1400)), 0, 'recap is not asked for')
	eq(one(r('"op\\"; rm -rf ~"', 10, 100, 1400)), 0, 'odd type')
	eq(one(r('"op"', -5, 100, 1400)), 0, 'negative start')
	eq(one(r('"op"', 100, 100, 1400)), 0, 'empty')
	eq(one(r('"op"', 200, 100, 1400)), 0, 'backwards')
	eq(one(r('"op"', 10, 700, 1400)), 0, 'longer than an opening can be')
	eq(one(r('"op"', 10, 100, 0)), 0, 'no episode length')
	eq(one(r('"op"', 10, 100, 1e308)), 0, 'absurd episode length')
	eq(one(r('"op"', 1e308, 1e308, 1400)), 0, 'absurd time')
	eq(one(r('"op"', 1500, 1590, 1400)), 0, 'after the end of the episode')
	eq(one(r('"op"', '"10"', 100, 1400)), 0, 'string time')
	eq(one('{"interval":[10,100],"skipType":"op","episodeLength":1400}'), 0, 'interval not an object')
	eq(one('"x"'), 0, 'not an object')
	eq(m.parse_aniskip('{"results":[]}'), nil, 'no found')
	eq(m.parse_aniskip('{"found":"true","results":[]}'), nil, 'found a string')
	eq(m.parse_aniskip('{"found":true,"results":{"a":1}}'), nil, 'results an object')
	eq(m.parse_aniskip('{"found":true}'), nil, 'no results')
	eq(m.parse_aniskip('{"found":true,"results":[' .. string.rep(r('"op"', 10, 100, 1400) .. ',', 30)
		.. r('"op"', 10, 100, 1400) .. ']}'), nil, 'too many results')
	eq(m.parse_aniskip('{"found":true,"results":[{"interval":'), nil, 'cut short')
	eq(m.parse_aniskip('Internal Server Error'), nil, 'not JSON')
end)

test('times are chosen for this file\'s duration', function()
	local m = load_module()
	local results = assert(m.parse_aniskip(data('aniskip-52991-5.json')))
	local ranges = m.select(results, 1470)
	eq(#ranges, 2)
	eq(ranges[1].kind, 'opening'); near(ranges[1].start, 153.346); near(ranges[1].finish, 243.346)
	eq(ranges[2].kind, 'ending'); near(ranges[2].start, 1370); near(ranges[2].finish, 1460)
	eq(#m.select(results, 1440), 0, 'another cut (30 s shorter): nothing')
	eq(#m.select(results, 1478), 2, 'within 10 s')
	eq(#m.select(results, 0 / 0), 0, 'NaN duration')
	eq(#m.select(results, nil), 0, 'no duration')
	eq(#m.select(nil, 1470), 0, 'no results')
	-- The closest submission wins; an ending is cut at the end of the file.
	local mixed = {
		{type = 'op', start = 10, finish = 100, length = 1400},
		{type = 'mixed-op', start = 12, finish = 102, length = 1405},
		{type = 'ed', start = 1350, finish = 1440, length = 1408},
	}
	ranges = m.select(mixed, 1406)
	near(ranges[1].start, 12, 'closest opening')
	near(ranges[2].finish, 1406, 'ending cut to the duration')
end)

test('what hikari-title publishes is checked before use', function()
	local m = load_module()
	local q = assert(m.query(frieren(5)))
	eq(q.series, 'Sousou no Frieren'); eq(q.episode, 5); eq(q.season, nil); eq(q.key, 'sousou no frieren|1')
	eq(m.query(frieren(5, 2)).key, 'sousou no frieren|2')
	eq(m.query({series = 'Show', episode = 1, anime = false}), nil, 'not anime')
	eq(m.query({series = 'Show', episode = 1}), nil, 'anime not said')
	eq(m.query({series = 'Show', episode = 0, anime = true}), nil, 'episode 0')
	eq(m.query({series = 'Show', episode = 1.5, anime = true}), nil, 'half episode')
	eq(m.query({series = 'Show', episode = '1', anime = true}), nil, 'string episode')
	eq(m.query({series = 'Show', episode = 10000, anime = true}), nil, 'episode too big')
	eq(m.query({series = 'Show', episode = 1, season = 0, anime = true}), nil, 'season 0')
	eq(m.query({series = 'Show', episode = 1, season = 'x', anime = true}), nil, 'string season')
	eq(m.query({series = '', episode = 1, anime = true}), nil, 'no series')
	eq(m.query({series = '!!!', episode = 1, anime = true}), nil, 'only punctuation')
	eq(m.query({series = 'Bad\nname', episode = 1, anime = true}), nil, 'control character')
	eq(m.query({series = string.rep('a', 201), episode = 1, anime = true}), nil, 'too long')
	eq(m.query('Show'), nil, 'not a table')
	eq(m.query(nil), nil, 'nil')
end)

-- ---------------------------------------------------------------------------
-- Network and cache
-- ---------------------------------------------------------------------------

test('first lookup: AniList, then AniSkip, both cached; the second asks nothing', function()
	local m = load_module()
	local got = lookup(m, frieren(5))
	eq(#mock.async, 1, 'one request')
	local cmd = mock.async[1].cmd
	local args = cmd.args
	eq(cmd.name, 'subprocess'); eq(cmd.playback_only, false); eq(cmd.capture_stdout, true)
	eq(args[1], 'curl'); eq(args[2], '-q', '-q first: no .curlrc')
	eq(args[arg_index(args, '--proto') + 1], '=https')
	eq(args[arg_index(args, '--max-redirs') + 1], '0')
	assert(arg_index(args, '--max-time'), 'timeout')
	eq(args[#args], 'https://graphql.anilist.co')
	eq(args[arg_index(args, '--data-binary') + 1], '@-', 'body on stdin')
	-- The series name only travels in the body, as a JSON value.
	for _, a in ipairs(args) do assert(not a:find('Frieren', 1, true), 'series in the command line') end
	local body = assert(mock.parse_json(cmd.stdin_data))
	eq(body.variables.search, 'Sousou no Frieren')
	assert(body.query:find('idMal', 1, true), 'asks for idMal')
	mock.finish_async(ok_answer(data('anilist-sousou-no-frieren.json')))
	eq(got.called, false, 'not yet')
	eq(#mock.async, 1, 'AniSkip asked')
	args = mock.async[1].cmd.args
	eq(args[#args], 'https://api.aniskip.com/v2/skip-times/52991/5'
		.. '?types%5B%5D=op&types%5B%5D=ed&types%5B%5D=mixed-op&types%5B%5D=mixed-ed&episodeLength=0')
	eq(mock.async[1].cmd.stdin_data, nil, 'GET')
	mock.finish_async(ok_answer(data('aniskip-52991-5.json')))
	eq(got.called, true); eq(#got.results, 2)
	-- On disk: the id and the times.
	local cache = assert(mock.parse_json(read(CACHE)))
	eq(cache.version, 1)
	eq(cache.titles['sousou no frieren|1'].mal, 52991)
	eq(cache.titles['sousou no frieren|1'].episodes, 28)
	eq(cache.titles['sousou no frieren|1'].at, T0)
	eq(#cache.episodes['52991:5'].results, 2)
	eq(read(CACHE .. '.tmp'), nil, 'no temporary file left')
	-- Again, an hour later: straight from the cache.
	clock.t = T0 + 3600
	got = lookup(m, frieren(5))
	eq(#mock.async, 0, 'nothing asked')
	eq(got.called, true); eq(#got.results, 2)
	-- Another episode of the same series: only AniSkip.
	got = lookup(m, frieren(6))
	eq(#mock.async, 1)
	args = mock.async[1].cmd.args
	assert(args[#args]:find('/52991/6?', 1, true), 'episode 6')
end)

test('"not found" is cached too, for less time', function()
	local m = load_module()
	local got = lookup(m, frieren(5))
	mock.finish_async(ok_answer(data('anilist-sousou-no-frieren.json')))
	mock.finish_async(ok_answer(data('aniskip-not-found.json')))
	eq(got.called, true); eq(#got.results, 0)
	eq(assert(mock.parse_json(read(CACHE))).episodes['52991:5'].found, false)
	clock.t = T0 + 2 * DAY
	got = lookup(m, frieren(5))
	eq(#mock.async, 0, 'within 3 days: from the cache')
	eq(#got.results, 0)
	clock.t = T0 + 4 * DAY
	lookup(m, frieren(5))
	eq(#mock.async, 1, 'after 3 days: asked again')
end)

test('no clear match: cached as such, nothing sent to AniSkip', function()
	local m = load_module()
	local got = lookup(m, {series = 'Some Unknown Show', episode = 3, anime = true})
	mock.finish_async(ok_answer('{"data":{"Page":{"media":[]}}}'))
	eq(got.called, true); eq(got.results, nil)
	eq(#mock.async, 0, 'no AniSkip')
	eq(assert(mock.parse_json(read(CACHE))).titles['some unknown show|1'].mal, 0)
	clock.t = T0 + 6 * DAY
	lookup(m, {series = 'Some Unknown Show', episode = 4, anime = true})
	eq(#mock.async, 0, 'within 7 days: nothing asked')
	clock.t = T0 + 8 * DAY
	lookup(m, {series = 'Some Unknown Show', episode = 4, anime = true})
	eq(#mock.async, 1, 'after 7 days: asked again')
end)

test('an episode past the known count is not looked up (absolute numbering)', function()
	local m = load_module()
	local got = lookup(m, frieren(29))
	mock.finish_async(ok_answer(data('anilist-sousou-no-frieren.json')))
	eq(#mock.async, 0, 'no AniSkip')
	eq(got.called, true); eq(got.results, nil)
end)

test('times expire after 30 days; a clock moved back counts as expired', function()
	local m = load_module()
	lookup(m, frieren(5))
	mock.finish_async(ok_answer(data('anilist-sousou-no-frieren.json')))
	mock.finish_async(ok_answer(data('aniskip-52991-5.json')))
	clock.t = T0 + 29 * DAY
	lookup(m, frieren(5))
	eq(#mock.async, 0, 'day 29')
	clock.t = T0 + 31 * DAY
	lookup(m, frieren(5))
	eq(#mock.async, 1, 'day 31: AniList again (the id expired too)')
	mock.async = {}
	clock.t = T0 - DAY
	lookup(m, frieren(5))
	eq(#mock.async, 1, 'entries from the future are not trusted')
end)

test('AniList down: Jikan is asked, with the name percent-encoded', function()
	local m = load_module()
	local got = lookup(m, {series = 'Sousou no Frieren', episode = 5, anime = true})
	mock.finish_async(true, {status = 28, stdout = '', stderr = 'curl: (28) timed out', error_string = ''})
	eq(#mock.async, 1, 'Jikan')
	local args = mock.async[1].cmd.args
	eq(args[#args], 'https://api.jikan.moe/v4/anime?limit=25&q=Sousou%20no%20Frieren')
	eq(args[2], '-q')
	mock.finish_async(ok_answer(data('jikan-sousou-no-frieren.json')))
	args = mock.async[1].cmd.args
	assert(args[#args]:find('/52991/5?', 1, true), 'AniSkip with the id from Jikan')
	mock.finish_async(ok_answer(data('aniskip-52991-5.json')))
	eq(#got.results, 2)
	-- Jikan's URL: nothing but the encoded name after q=.
	m = load_module()
	lookup(m, {series = 'A&b=c d/../#?é', episode = 1, anime = true})
	mock.finish_async(ok_answer('{"errors":[{"message":"Internal Server Error"}]}'))
	args = mock.async[1].cmd.args
	eq(args[#args], 'https://api.jikan.moe/v4/anime?limit=25&q=A%26b%3Dc%20d%2F..%2F%23%3F%C3%A9')
end)

test('no answer anywhere: nothing shown, nothing cached', function()
	local m = load_module()
	local got = lookup(m, frieren(5))
	mock.finish_async(false, nil, 'killed')
	mock.finish_async(ok_answer('<html>down</html>'))
	eq(got.called, true); eq(got.results, nil)
	eq(read(CACHE), nil, 'no cache written')
	-- AniSkip down: the id is kept, the times are not.
	got = lookup(m, frieren(5))
	mock.finish_async(ok_answer(data('anilist-sousou-no-frieren.json')))
	mock.finish_async(true, {status = 6, stdout = '', stderr = 'Could not resolve host', error_string = ''})
	eq(got.results, nil)
	local cache = assert(mock.parse_json(read(CACHE)))
	eq(cache.titles['sousou no frieren|1'].mal, 52991)
	eq(next(cache.episodes), nil, 'no times')
end)

test('no curl: no request at all', function()
	local m = load_module()
	fake_env.PATH = '/nonexistent'
	local got = lookup(m, frieren(5))
	eq(#mock.async, 0)
	eq(got.called, true); eq(got.results, nil)
end)

test('Windows: curl.exe by absolute path in System32, never from PATH', function()
	local m = load_module()
	mock.props.platform = 'windows'
	eq(m.curl_program(), nil, 'not there')
	mock.files['C:\\Windows\\System32\\curl.exe'] = {is_file = true}
	eq(m.curl_program(), 'C:\\Windows\\System32\\curl.exe')
	fake_env.SystemRoot = 'Windows'
	eq(m.curl_program(), nil, 'relative SystemRoot')
	fake_env.SystemRoot = 'C:\\Windows" & calc'
	eq(m.curl_program(), nil, 'odd SystemRoot')
	fake_env.SystemRoot = 'C:\\Windows'
end)

test('a broken cache is ignored and replaced', function()
	for _, content in ipairs({'not json', '{"version":2,"titles":{}}', '[]', '{"version":1,"titles":"x"}',
		string.rep(' ', 600000)}) do
		local m = load_module()
		write(CACHE, content)
		lookup(m, frieren(5))
		eq(#mock.async, 1, 'asked: ' .. content:sub(1, 20))
		mock.finish_async(ok_answer(data('anilist-sousou-no-frieren.json')))
		eq(assert(mock.parse_json(read(CACHE))).titles['sousou no frieren|1'].mal, 52991)
	end
end)

test('bad cache entries are dropped one by one', function()
	local m = load_module()
	write(CACHE, mock.format_json({
		version = 1,
		titles = {
			['good|1'] = {at = T0, mal = 7},
			['string id|1'] = {at = T0, mal = '7'},
			['no time|1'] = {mal = 7},
			['bad\nkey|1'] = {at = T0, mal = 7},
		},
		episodes = {
			['7:1'] = {at = T0, results = {{type = 'op', start = 1, finish = 90, length = 1400}}},
			['7:2'] = {at = T0, results = {{type = 'op', start = 90, finish = 1, length = 1400}}},
			['7:3'] = {at = T0, found = false},
			['7:4; rm'] = {at = T0, found = false},
			['7:5'] = {at = T0, results = 'x'},
		},
	}))
	local cache = m.read_cache()
	eq(cache.titles['good|1'].mal, 7)
	eq(cache.titles['string id|1'], nil); eq(cache.titles['no time|1'], nil); eq(cache.titles['bad\nkey|1'], nil)
	eq(#cache.episodes['7:1'].results, 1)
	eq(cache.episodes['7:2'], nil, 'impossible times')
	eq(cache.episodes['7:3'].found, false)
	eq(cache.episodes['7:4; rm'], nil); eq(cache.episodes['7:5'], nil)
end)

test('a long name made longer by normalising is still cached', function()
	local m = load_module()
	local series = string.rep('a×', 66) -- 198 bytes; normalised 'a x a x ...', 263
	local got = lookup(m, {series = series, episode = 1, anime = true})
	mock.finish_async(ok_answer('{"data":{"Page":{"media":[]}}}'))
	eq(got.called, true)
	lookup(m, {series = series, episode = 1, anime = true})
	eq(#mock.async, 0, 'the "no match" came from the cache')
end)

test('the cache keeps the newest entries within its limits', function()
	local m = load_module()
	m.CACHE_LIMITS.titles = 3
	for i = 1, 5 do
		clock.t = T0 + i
		m.save('titles', 'show ' .. i .. '|1', {at = clock.t, mal = i})
	end
	local cache = m.read_cache()
	local n = 0
	for _ in pairs(cache.titles) do n = n + 1 end
	eq(n, 3)
	eq(cache.titles['show 1|1'], nil); eq(cache.titles['show 2|1'], nil); eq(cache.titles['show 5|1'].mal, 5)
end)

test('another mpv\'s answers are kept when saving', function()
	local m = load_module()
	m.save('titles', 'a|1', {at = T0, mal = 1})
	-- Another window writes its own entry meanwhile.
	local other = assert(mock.parse_json(read(CACHE)))
	other.titles['b|1'] = {at = T0, mal = 2}
	write(CACHE, mock.format_json(other))
	m.save('titles', 'c|1', {at = T0, mal = 3})
	local cache = m.read_cache()
	eq(cache.titles['a|1'].mal, 1); eq(cache.titles['b|1'].mal, 2); eq(cache.titles['c|1'].mal, 3)
end)

test('an unwritable cache only costs a warning', function()
	local m = load_module()
	mock.expand['~~/hikari-aniskip.json'] = '/nonexistent/dir/hikari-aniskip.json'
	local got = lookup(m, frieren(5))
	mock.finish_async(ok_answer(data('anilist-sousou-no-frieren.json')))
	mock.finish_async(ok_answer(data('aniskip-52991-5.json')))
	eq(#got.results, 2)
	assert(#mock.logs.warn >= 1, 'warned')
end)

test('the module avoids os.execute, io.popen and load*', function()
	local source = assert(read(MODULE))
	for _, bad in ipairs({'os.execute', 'io.popen', 'loadstring', 'loadfile', 'dofile', 'load('}) do
		assert(not source:find(bad, 1, true), bad)
	end
end)

-- ---------------------------------------------------------------------------
-- hikari-skip
-- ---------------------------------------------------------------------------

local PATH = '/anime/[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv'

-- Loads hikari-skip with a 1280x720 OSD, and plays a file without chapters
-- of `duration` seconds at `path`, for which hikari-title published `release`.
local function play(opts, release, chapters, duration)
	mock.install('hikari_skip')
	mock.script_opts = opts or {}
	if mock.script_opts['hikari-language'] == nil then mock.script_opts['hikari-language'] = 'es' end
	mock.props.platform = 'linux'
	mock.expand['~~/hikari-aniskip.json'] = CACHE
	fake_env.PATH = FAKE_BIN
	HIKARI_SKIP_TEST = true
	local s = assert(loadfile(SKIP))()
	if s.aniskip then s.aniskip.now = function() return clock.t end end
	mock.set('osd-dimensions', {w = 1280, h = 720})
	mock.props.path = PATH
	mock.set(RELEASE_PROP, release == nil and {series = 'Sousou no Frieren', episode = 5, anime = true, path = PATH} or release)
	mock.set('duration', duration or 1470)
	mock.set('chapter-list', chapters or {})
	mock.events['file-loaded']()
	return s
end

local function answer_all()
	mock.finish_async(ok_answer(data('anilist-sousou-no-frieren.json')))
	mock.finish_async(ok_answer(data('aniskip-52991-5.json')))
end

local function label(s) return s.layout() and s.layout().label end

test('skip: a file without chapters gets AniSkip\'s opening and ending', function()
	os.remove(CACHE)
	clock.t = T0
	local s = play()
	eq(#mock.async, 1, 'asked')
	answer_all()
	eq(#s.state.ranges, 2)
	mock.set('time-pos', 100)
	eq(s.is_visible(), false, 'before the opening')
	mock.set('time-pos', 160)
	eq(label(s), 'Saltar opening ›')
	assert(s.overlay.visible, 'drawn')
	assert(s.skip(), 'skipped')
	local seek = mock.commands[#mock.commands]
	eq(seek[1], 'seek'); eq(seek[2], '243.346'); eq(seek[3], 'absolute+exact')
	mock.set('time-pos', 1380)
	eq(label(s), 'Saltar ending ›')
	s.skip()
	eq(mock.commands[#mock.commands][2], '1460.000', 'the ending skips to its end')
	-- The key binding (Alt+s) works the same.
	mock.set('time-pos', 170)
	eq(label(s), 'Saltar opening ›')
	mock.bindings.skip()
	eq(mock.commands[#mock.commands][2], '243.346')
end)

test('skip: playing the same episode again asks nothing; the button is there at once', function()
	-- The cache from the test above.
	local s = play()
	eq(#mock.async, 0, 'nothing asked')
	mock.set('time-pos', 200)
	eq(label(s), 'Saltar opening ›')
end)

test('skip: files with opening or ending chapters never ask', function()
	os.remove(CACHE)
	local list = {{time = 0, title = 'Part A'}, {time = 90, title = 'OP'}, {time = 180, title = 'Part B'}}
	play(nil, nil, list)
	eq(#mock.async, 0, 'OP chapter')
	play({['hikari-skip-openings'] = 'no'}, nil, list)
	eq(#mock.async, 0, 'OP chapter, even with openings turned off')
	play(nil, nil, {{time = 0, title = 'Part A'}, {time = 1300, title = 'Ending'}})
	eq(#mock.async, 0, 'ED chapter')
	play({['hikari-skip-intros'] = 'no'}, nil, {{time = 0, title = 'Intro'}, {time = 90, title = 'Part A'}})
	eq(#mock.async, 0, 'an Intro chapter is the opening song in many releases')
	play(nil, nil, {{time = 0, title = 'Part A'}, {time = 1400, title = 'Preview'}})
	eq(#mock.async, 1, 'a preview chapter alone: asked')
	mock.async = {}
	play(nil, nil, {{time = 0, title = 'Chapter 1'}, {time = 600, title = 'Chapter 2'}})
	eq(#mock.async, 1, 'plain chapters: asked')
end)

test('skip: aniskip=no asks nothing and does not even load the module', function()
	os.remove(CACHE)
	local s = play({['hikari-skip-aniskip'] = 'no'})
	eq(s.aniskip, nil)
	eq(#mock.async, 0)
end)

test('skip: no lookup without a release for this very file, or for non-anime', function()
	os.remove(CACHE)
	play(nil, {})
	eq(#mock.async, 0, 'nothing published')
	play(nil, {series = 'Sousou no Frieren', episode = 5, anime = true, path = '/anime/other.mkv'})
	eq(#mock.async, 0, 'published for another path')
	play(nil, {series = 'Breaking Bad', episode = 5, season = 1, anime = false, path = PATH})
	eq(#mock.async, 0, 'not anime')
	play(nil, nil, nil, 0)
	eq(#mock.async, 0, 'no duration')
	play({['hikari-skip-openings'] = 'no', ['hikari-skip-endings'] = 'no'})
	eq(#mock.async, 0, 'openings and endings turned off')
end)

test('skip: a release published after file-loaded is still looked up, once', function()
	os.remove(CACHE)
	play(nil, {})
	eq(#mock.async, 0)
	mock.set(RELEASE_PROP, {series = 'Sousou no Frieren', episode = 5, anime = true, path = PATH})
	eq(#mock.async, 1, 'asked when it arrived')
	mock.set(RELEASE_PROP, {series = 'Sousou no Frieren', episode = 5, anime = true, path = PATH})
	mock.set('duration', 1470.5)
	eq(#mock.async, 1, 'only once per file')
end)

test('skip: an answer for a file that ended is dropped', function()
	os.remove(CACHE)
	local s = play()
	mock.events['end-file']()
	-- The next file, without a release, is already playing.
	mock.props.path = '/videos/holiday.mkv'
	mock.set(RELEASE_PROP, {})
	mock.set('duration', 1470)
	mock.set('chapter-list', {})
	mock.events['file-loaded']()
	answer_all()
	eq(#s.state.ranges, 0, 'no ranges for the new file')
	mock.set('time-pos', 160)
	eq(s.is_visible(), false)
	-- The answer was still cached for next time.
	eq(assert(mock.parse_json(read(CACHE))).titles['sousou no frieren|1'].mal, 52991)
end)

test('skip: times that arrive after the opening change nothing on screen', function()
	os.remove(CACHE)
	local s = play()
	mock.set('time-pos', 600)
	answer_all()
	eq(s.is_visible(), false, 'mid-episode: no button')
	eq(s.overlay.visible, false)
	mock.set('time-pos', 1375)
	eq(label(s), 'Saltar ending ›', 'the ending still gets it')
end)

test('skip: times that arrive during the opening show the button at once', function()
	os.remove(CACHE)
	local s = play()
	mock.set('time-pos', 160)
	eq(s.is_visible(), false)
	answer_all()
	eq(label(s), 'Saltar opening ›')
	assert(s.overlay.visible)
end)

test('skip: options choose the kinds; an ending to the end of the file goes to the next entry', function()
	os.remove(CACHE)
	local s = play({['hikari-skip-openings'] = 'no'})
	answer_all()
	eq(#s.state.ranges, 1, 'only the ending')
	eq(s.state.ranges[1].kind.name, 'endings')
	-- A file that ends where the ending does.
	os.remove(CACHE)
	s = play(nil, nil, nil, 1461)
	answer_all()
	local ending = s.state.ranges[2]
	eq(ending.next_time, nil, 'runs to the end')
	mock.props['playlist-pos'], mock.props['playlist-count'] = 0, 2
	mock.set('time-pos', 1400)
	assert(s.skip())
	eq(mock.commands[#mock.commands][1], 'playlist-next')
end)

test('skip: AniSkip times that do not fit this cut are not used', function()
	os.remove(CACHE)
	local s = play(nil, nil, nil, 1420)
	answer_all()
	eq(#s.state.ranges, 0)
end)

test('skip: without the module (an old install) the button still works with chapters', function()
	local dir = tmp_path()
	assert(os.execute('mkdir -p "' .. dir .. '"'))
	write(dir .. '/hikari-i18n.lua', assert(read('portable_config/script-modules/hikari-i18n.lua')))
	mock.install('hikari_skip')
	mock.script_opts = {['hikari-language'] = 'es'}
	mock.expand['~~/script-modules'] = dir
	HIKARI_SKIP_TEST = true
	local s = assert(loadfile(SKIP))()
	eq(s.aniskip, nil)
	assert(mock.logs.warn[1]:find('hikari-aniskip.lua', 1, true), 'warned')
	mock.set('osd-dimensions', {w = 1280, h = 720})
	mock.set('duration', 1420)
	mock.set('chapter-list', {{time = 0, title = 'A'}, {time = 90, title = 'OP'}, {time = 180, title = 'B'}})
	mock.set('time-pos', 100)
	eq(label(s), 'Saltar opening ›')
	mock.events['file-loaded']()
	eq(#mock.async, 0)
	os.execute('rm -rf "' .. dir .. '"')
	mock.expand['~~/script-modules'] = nil
end)

test('skip: the double-click guard works with AniSkip\'s button too', function()
	local s = play()
	mock.set('time-pos', 160)
	local rect = assert(s.layout())
	mock.props['mouse-pos'] = {x = (rect.x0 + rect.x1) / 2, y = (rect.y0 + rect.y1) / 2, hover = true}
	s.on_down()
	s.on_up()
	eq(mock.commands[#mock.commands][2], '243.346')
	assert(s.guard_active(), 'guard on after a mouse skip')
end)

os.remove(CACHE); os.remove(CACHE .. '.tmp')
os.execute('rm -rf "' .. FAKE_BIN .. '"')
print(string.format('\n%d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
