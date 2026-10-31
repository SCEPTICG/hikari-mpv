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
	-- The assertions below are in Spanish: unless a test says otherwise, hikari speaks Spanish.
	if mock.script_opts['hikari-language'] == nil then mock.script_opts['hikari-language'] = 'es' end
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
	eq(t.title_for('https://h/video;jsessionid=S3CR3T?x=1'), 'video', 'path parameters left out (query)')
	eq(t.title_for('https://h/Show - 01.mkv;jsessionid=S3CR3T'), 'Show · E01', 'path parameters left out (no query)')
	eq(t.title_for('https://h.example/;jsessionid=S3CR3T'), 'h.example', 'only path parameters: the host')
	eq(t.title_for('https://h/video.mp4;jsessionid=S3CR3T'), 'video.mp4', 'path parameters left out (not a release)')
	eq(t.title_for('https://h/stream;jsessionid=S3CR3T'), 'stream', 'path parameters left out (no extension)')
end)

test('names that are not releases, and other protocols, are untouched', function()
	local t = load()
	for _, path in ipairs({
		'/home/u/Videos/Holiday video.mkv', 'C:\\Videos\\a.mkv?filename=x.mkv', 'file:///tmp/a.mkv?x=1',
		'https://h/video.mkv', 'https://h/video.mkv#t=10', 'ytdl://abc?filename=x', 'rtsp://h/a?token=1',
		'/home/u/Music/Artist - 01 - Song.flac', '/home/u/Anime/Show.S01E01.srt', 'edl://Show.S01E01.mkv',
		'https://www.youtube.com/watch?v=abc', '/home/u/Anime/', 'C:\\Anime\\Show - 05',
	}) do
		local title, source = t.title_for(path)
		if path:find('youtube', 1, true) then eq(source, 'fallback', path) else eq(title, nil, path) end
	end
	start('/home/u/Videos/Holiday video.mkv')
	eq(mock.props['force-media-title'], nil, 'property not set')
end)

test('local files with a release name get the tidy title', function()
	local t = load()
	eq(t.title_for('/home/u/Anime/Show.S01E01.mkv'), 'Show · T1 E01')
	eq(t.title_for('C:\\Anime\\[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv'), 'Sousou no Frieren · E05',
		'Windows path')
	eq(t.title_for('file:///home/u/Anime/%5BSubsPlease%5D%20Sousou%20no%20Frieren%20-%2005%20(1080p).mkv'),
		'Sousou no Frieren · E05', 'file:// URL, decoded')
	eq(t.title_for('Movie.Name.2023.1080p.BluRay.x264-GRP.MP4'), 'Movie Name (2023)', 'relative path, upper-case ext')
	local title, source = t.title_for('/a/Show - 05.webm')
	eq(title, 'Show · E05'); eq(source, 'file')
end)

test('a local release name wins over the title tag and is restored after the file', function()
	load()
	eq(start('/home/u/Anime/[Erai-raws] jukishi - 15 [1080p].mkv'), 'Jukishi · E15')
	mock.props['metadata/by-key/title'] = 'Erai-raws'
	mock.events['file-loaded']()
	eq(mock.props['force-media-title'], 'Jukishi · E15', 'the tag does not replace it')
	mock.end_file()
	eq(mock.props['force-media-title'], '', 'restored at the end')
end)

test('local files: a title of the user or of the playlist entry is respected; pretty=no turns it off', function()
	load()
	mock.props['force-media-title'] = 'Mi título'
	eq(start('/a/Show.S01E01.mkv'), 'Mi título', 'force-media-title of the user')
	load()
	mock.props['playlist-playing-pos'] = 0
	mock.props['playlist/0/title'] = 'Capítulo 1'
	eq(start('/a/Show.S01E01.mkv'), nil, 'playlist title')
	load({['hikari-title-pretty'] = 'no'})
	eq(start('/a/Show.S01E01.mkv'), nil, 'pretty=no')
	load({['hikari-title-enabled'] = 'no'})
	eq(start('/a/Show.S01E01.mkv'), nil, 'enabled=no')
end)

test('URLs whose last segment is a release file name', function()
	local t = load()
	eq(t.title_for('https://h/files/%5BSubsPlease%5D%20Show%20-%2005%20(1080p).mkv'), 'Show · E05', 'no query')
	eq(t.title_for('https://h/dl/Show.S02E03.1080p.WEB-DL.mkv?token=abc'), 'Show · T2 E03', 'with a query, no filename')
	eq(t.title_for('https://h/dl/Show.S02E03.mkv?token=abc&filename=Other.S01E01.mkv'), 'Other · T1 E01',
		'filename= still wins')
	local title, source = t.title_for('https://h/dl/Show.S02E03.mkv')
	eq(source, 'file', 'strong, not a fallback')
	load()
	start('https://h/dl/Show.S02E03.mkv?token=abc')
	mock.props['metadata/by-key/title'] = 'Tag'
	mock.events['file-loaded']()
	eq(mock.props['force-media-title'], 'Show · T2 E03', 'kept despite the tag')
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
	eq(p('[Erai-raws] Show Name 2nd Season - 12v2 [1080p][Multiple Subtitle]'), 'Show Name · T2 E12', 'season read')
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

-- Real release names of many groups and naming styles, with the English
-- labels: {name, expected}.
local CORPUS = {
	{'[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234]', 'Sousou no Frieren · E05'},
	{'[SubsPlease] Kusuriya no Hitorigoto - 17v2 (1080p) [5E3B1A2C]', 'Kusuriya no Hitorigoto · E17'},
	{'[SubsPlease] Mob Psycho 100 III - 05 (1080p) [ABCD1234]', 'Mob Psycho 100 III · E05'},
	{'[Erai-raws] Shingeki no Kyojin - The Final Season Part 2 - 01 [1080p][Multiple Subtitle][ABCDEF01]',
		'Shingeki no Kyojin - The Final Season Part 2 · E01'},
	{'[Erai-raws] Mushoku Tensei II - Isekai Ittara Honki Dasu 2nd Season - 05 [1080p CR WEB-DL AVC AAC][MultiSub][ABCD1234]',
		'Mushoku Tensei II - Isekai Ittara Honki Dasu · S2 E05'},
	{'[Erai-raws] Kimetsu no Yaiba - Katanakaji no Sato Hen - 03 [1080p][Multiple Subtitle]',
		'Kimetsu no Yaiba - Katanakaji no Sato Hen · E03'},
	{'[HorribleSubs] One Punch Man S2 - 05 [1080p]', 'One Punch Man · S2 E05'},
	{'[HorribleSubs] Boku no Hero Academia - 88 [720p]', 'Boku no Hero Academia · E88'},
	{'[Judas] Jujutsu Kaisen - S02E05 [1080p][HEVC x265 10bit][Multi-Subs]', 'Jujutsu Kaisen · S2 E05'},
	{'[Judas] Vinland Saga (Season 2) - 05 [1080p][HEVC x265 10bit][Multi-Subs]', 'Vinland Saga · S2 E05'},
	{'[ASW] Dungeon Meshi - 05 [1080p HEVC x265 10Bit][AAC]', 'Dungeon Meshi · E05'},
	{'[EMBER] Frieren S01E05 [1080p] [HEVC WEBRip]', 'Frieren · S1 E05'},
	{'[EMBER] Kimi no Na wa (2016) [1080p] [HEVC BDRip]', 'Kimi no Na wa (2016)'},
	{'[Tsundere-Raws] Spy x Family S2 - 05 VOSTFR (CR) [WEB 1080p x264 AAC]', 'Spy x Family · S2 E05'},
	{'[DKB] Chainsaw Man - S01E05 [1080p][HEVC x265 10bit][Multi-Subs]', 'Chainsaw Man · S1 E05'},
	{'[Anime Time] Oshi no Ko (Season 2) - 05 [1080p][HEVC 10bit x265][AAC][Multi Sub]', 'Oshi no Ko · S2 E05'},
	{'[Anime Time] Bocchi the Rock! - 05 [1080p][HEVC 10bit x265][AAC][Multi Sub]', 'Bocchi the Rock! · E05'},
	{'[Yameii] The Apothecary Diaries - S01E05 [English Dub] [CR WEB-DL 1080p] [ABCD1234]',
		'The Apothecary Diaries · S1 E05'},
	{'Frieren.Beyond.Journeys.End.S01E05.1080p.CR.WEB-DL.AAC2.0.H.264-VARYG', 'Frieren Beyond Journeys End · S1 E05'},
	{'Dandadan.S01E05.Episode.Title.1080p.NF.WEB-DL.DDP5.1.H.264-VARYG', 'Dandadan · S1 E05 · Episode Title'},
	{'Show.S01E05.REPACK.1080p.WEB', 'Show · S1 E05'},
	{'Show.S01E05.Dual.Audio.1080p', 'Show · S1 E05'},
	-- Plex / Jellyfin / Sonarr
	{'Frieren (2023) - S01E05 - The Hero\'s Party', 'Frieren (2023) · S1 E05 · The Hero\'s Party'},
	{'Frieren - S01E05 - Phantoms of the Dead [WEBDL-1080p][AAC 2.0][x264]-GRP', 'Frieren · S1 E05 · Phantoms of the Dead'},
	{'[Group] Show - 05 - Episode Title [1080p]', 'Show · E05 · Episode Title'},
	-- Short forms
	{'Show - 05v2', 'Show · E05'},
	{'Show E05', 'Show · E05'},
	{'Show Episode 05', 'Show · E05'},
	{'Show - 12.5', 'Show · E12.5'},
	-- OVA, specials, seasons
	{'[Group] Show - OVA [1080p]', 'Show · OVA'},
	{'[Group] Show OVA 2 [1080p]', 'Show · OVA E02'},
	{'[Group] Show OVA - 03 [1080p]', 'Show · OVA E03'},
	{'[Group] Show - SP01 [1080p]', 'Show · Special E01'},
	{'[Group] Show - Special 01 [1080p]', 'Show · Special E01'},
	{'[Group] Special 7 - 05 [1080p]', 'Special 7 · E05'},
	{'[Group] Show Season 2 - 05 [1080p]', 'Show · S2 E05'},
	{'[Group] Show 3rd Season - 05 [1080p]', 'Show · S3 E05'},
	{'[Group] Show Second Season - 05 [1080p]', 'Show · S2 E05'},
	{'[Group] Show S2 E05 [1080p]', 'Show · S2 E05'},
	{'[Group] Re Zero kara Hajimeru Isekai Seikatsu S3 - 05 [1080p]', 'Re Zero kara Hajimeru Isekai Seikatsu · S3 E05'},
	{'[Group] 86 Eighty-Six - 05 [1080p]', '86 Eighty-Six · E05'},
	-- Not a season: the name would be left empty, or it is part of the title.
	{'[Group] S2 - 05 [1080p]', 'S2 · E05'},
	{'[Group] Season 2049 - 05', 'Season 2049 · E05'},
}

test('pretty: a corpus of real release names', function()
	local p = load({['hikari-language'] = 'en'}).pretty_title
	for _, case in ipairs(CORPUS) do eq(p(case[1]), case[2], case[1]) end
end)

test('pretty: a release name is flagged as one; other names are not', function()
	local p = load().pretty_title
	for _, case in ipairs(CORPUS) do eq(select(2, p(case[1])), true, case[1]) end
	for _, name in ipairs({'Holiday video', 'IMG_2034', 'Movie (2023)', 'Show.Name', 'S01E01.1080p', '- 01'}) do
		eq(select(2, p(name)), false, name)
	end
	eq(select(2, p('[Group] Movie')), true, 'a group dropped')
end)

test('pretty: labels in every language; the label of the title on screen follows a switch', function()
	local t = load({['hikari-language'] = 'en'})
	local name = '[Group] Show S2 - 05 [1080p]'
	local expected = {
		en = 'Show · S2 E05', es = 'Show · T2 E05', pt = 'Show · T2 E05', de = 'Show · S2 E05', fr = 'Show · S2 E05',
		tr = 'Show · S2 B05', ['zh-hans'] = 'Show · 第2季 第05集', ['zh-HK'] = 'Show · 第2季 第05集',
	}
	for lang, title in pairs(expected) do eq(t.pretty_title(name, lang), title, lang) end
	eq(t.pretty_title('Show.S00E03', 'es'), 'Show · Especial E03')
	eq(t.pretty_title('Show.S01E01E02', 'zh-hans'), 'Show · 第1季 第01-02集')
	eq(t.pretty_title('Show - 12.5', 'zh-HK'), 'Show · 第12.5集')
	eq(start('/a/' .. name .. '.mkv'), 'Show · S2 E05')
	mock.set_script_opt('hikari-language', 'es')
	eq(mock.props['force-media-title'], 'Show · T2 E05', 'redone in Spanish')
	mock.end_file()
	eq(mock.props['force-media-title'], '', 'still restored at the end')
end)

test('a language switch leaves alone a title someone else set, and the fallback', function()
	load({['hikari-language'] = 'en'})
	start('/a/Show.S01E01.mkv')
	mock.props['force-media-title'] = 'Changed by another script'
	mock.set_script_opt('hikari-language', 'es')
	eq(mock.props['force-media-title'], 'Changed by another script')
	load({['hikari-language'] = 'en'})
	eq(start('https://h/live/master.m3u8?token=abc'), 'master.m3u8')
	mock.set_script_opt('hikari-language', 'es')
	eq(mock.props['force-media-title'], 'master.m3u8')
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
		t.title_for('/home/u/' .. s .. '.mkv')
		t.title_for('file:///home/u/' .. s .. '.mkv')
		t.title_for('https://h/a/' .. s .. '.mkv')
	end
	-- Paths with no separator, or nothing but separators.
	t.title_for(string.rep('a', 1000000) .. '.mkv')
	t.title_for(string.rep('/', 1000000))
	t.title_for(string.rep('\\', 1000000) .. 'x.mkv')
	t.pretty_title(string.rep('S2 ', 20000) .. '- 05')
	t.pretty_title(string.rep('OVA - ', 20000))
	t.pretty_title(string.rep('Season 2 ', 20000) .. 'E05')
	t.pretty_title('Show - S01E05 - ' .. string.rep('Word ', 20000))
	assert(os.clock() - clock < 2, 'too slow: ' .. (os.clock() - clock))
end)

-- Release info for hikari-skip (AniSkip) ------------------------------------

local function info(t, path)
	local r = t.release_for(path)
	if not r then return 'nil' end
	return string.format('%s|%s|%s|%s', r.series, tostring(r.season), tostring(r.episode), tostring(r.anime))
end

test('release info: series, season and episode of anime releases', function()
	local t = load()
	eq(info(t, '/a/[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv'), 'Sousou no Frieren|nil|5|true')
	eq(info(t, '/a/[SubsPlease] Sousou no Frieren S2 - 05 (1080p) [ABCD1234].mkv'), 'Sousou no Frieren|2|5|true')
	eq(info(t, '/a/[Erai-raws] Shingeki no Kyojin Season 3 - 01v2 [1080p].mkv'), 'Shingeki no Kyojin|3|1|true')
	eq(info(t, '/a/[Group] Kusuriya no Hitorigoto 2nd Season - 03 [1080p].mkv'), 'Kusuriya no Hitorigoto|2|3|true')
	eq(info(t, '/a/Sousou no Frieren - 05 (1080p) [ABCD1234].mkv'), 'Sousou no Frieren|nil|5|true', 'the - 05 marker, 1080p and a CRC')
	eq(info(t, '/a/Sousou no Frieren - 05 [1080p][BD].mkv'), 'Sousou no Frieren|nil|5|true', 'the - 05 marker, 1080p and BD')
	eq(info(t, '/a/Sousou no Frieren - 05 [1080p WEB-DL].mkv'), 'Sousou no Frieren|nil|5|true', 'two signs in one group')
	eq(info(t, '/a/Sousou.no.Frieren.-.05.1080p.WEB-DL.mkv'), 'Sousou no Frieren|nil|5|true', 'dotted, 1080p and WEB-DL in the tail')
	eq(info(t, '/a/Sousou no Frieren - 05 1080p WEB-DL.mkv'), 'Sousou no Frieren|nil|5|true', 'spaced, 1080p and WEB-DL in the tail')
	eq(info(t, '/a/[Erai-raws] Sousou no Frieren - 12 [1080p][Multiple Subtitle].mkv'), 'Sousou no Frieren|nil|12|true')
	eq(info(t, '/a/Show.S01E05.1080p.CR.WEB-DL.mkv'), 'Show|1|5|true', 'CR')
	eq(info(t, '/a/Show S01E05 (HIDIVE) [1080p].mkv'), 'Show|1|5|true', 'a service in brackets, with a resolution')
	eq(info(t, '/a/[Erai-raws] Show - 12 [1080p][Multiple Subtitle].mkv'), 'Show|nil|12|true')
	eq(info(t, '/a/[Erai-raws] jukishi - 15 [1080p CR WEB-DL AVC AAC][MultiSub][799A2A46].mkv'), 'Jukishi|nil|15|true')
	eq(info(t, '/a/Show.S01E05.1080p.UNCENSORED.ADN.WEB-DL.mkv'), 'Show|1|5|true', 'UNCENSORED in the tail')
	eq(info(t, '/a/Show - 05 [1080p][Dual Audio].mkv'), 'Show|nil|5|false', 'a label is no sign by itself')
	eq(info(t, '/a/Show - 05 (CR) [ABCD1234].mkv'), 'Show|nil|5|true', 'a service in brackets with a CRC')
	eq(info(t, '/a/Show - 05 [Multi-Subs] [1080p BD].mkv'), 'Show|nil|5|true', 'labels and two signs in brackets')
	eq(info(t, '/a/Show.-.05.1080p.BD.x264.mkv'), 'Show|nil|5|true', 'BD in a dotted tail')
	eq(info(t, '/a/Show - 05 [1080p][BD].mkv'), 'Show|nil|5|true', 'BD in brackets')
	eq(info(t, '/a/Show S01E05 1080p.CR.WEB-DL.mkv'), 'Show|1|5|true', 'a service inside a dotted word')
	eq(info(t, '/a/[Group] Show S01E05 [1080p].mkv'), 'Show|1|5|true', '[group] in front')
	eq(info(t, '/a/Show.Name.S01E05.1080p.CR.WEB-DL.AAC2.0.H.264-VARYG.mkv'), 'Show Name|1|5|true', 'CR in the tail')
	eq(info(t, '/a/Show.Name.S01E05.1080p.ADN.WEB-DL.AAC2.0.H.264-VARYG.mkv'), 'Show Name|1|5|true', 'ADN in the tail')
	eq(info(t, '/a/Show.Name.S01E05.Episode.Title.1080p.ADN.WEB-DL.mkv'), 'Show Name|1|5|true', 'after a title')
	eq(info(t, '/a/Frieren.S01E05.Le.Voyage.1080p.ADN.WEB-DL.mkv'), 'Frieren|1|5|true', 'ADN in the tail, after a title')
	eq(info(t, '/a/[Erai-raws] Show - 12 [1080p][Multiple Subtitle][ABCD1234].mkv'), 'Show|nil|12|true')
	-- Seanime: a release name with .ADN. in its tail, through the filename parameter.
	eq(info(t, 'https://127.0.0.1:43211/api/v1/mediastream/file/x?token=s3cret&filename='
		.. 'Sousou.no.Frieren.S01E05.VOSTFR.1080p.ADN.WEB-DL.AAC2.0.H.264-Tsundere-Raws.mkv'), 'Sousou no Frieren|1|5|true')
	eq(info(t, '/a/[SubsPlease] Viaje CR - 02 (1080p).mkv'), 'Viaje CR|nil|2|true', '[group] in front still counts')
	eq(info(t, 'C:\\Anime\\[SubsPlease] Sousou no Frieren - 05 (1080p).mkv'), 'Sousou no Frieren|nil|5|true', 'Windows path')
	eq(info(t, 'file:///a/%5BSubsPlease%5D%20Sousou%20no%20Frieren%20-%2005%20(1080p).mkv'), 'Sousou no Frieren|nil|5|true')
	-- Seanime: the filename parameter.
	eq(info(t, 'https://127.0.0.1:43211/api/v1/mediastream/file/x?token=s3cret&filename='
		.. '%5BSubsPlease%5D%20Sousou%20no%20Frieren%20-%2005%20(1080p).mkv'), 'Sousou no Frieren|nil|5|true')
	eq(info(t, 'https://h/files/[SubsPlease] Sousou no Frieren - 05 (1080p).mkv'), 'Sousou no Frieren|nil|5|true')
end)

test('release info: not for other files, or anything but one plain episode', function()
	local t = load()
	eq(info(t, '/a/Show.Name.S01E05.1080p.WEB-DL.mkv'), 'Show Name|1|5|false', 'no sign of anime')
	-- Personal videos and western series with the `- 05` marker are not
	-- anime: the marker alone is not enough, it needs a release sign.
	eq(info(t, '/a/Boda Ana y Juan - 01.mp4'), 'Boda Ana y Juan|nil|1|false', 'a wedding video')
	eq(info(t, '/a/Reunion confidencial cliente ACME - 03.mp4'), 'Reunion confidencial cliente ACME|nil|3|false')
	eq(info(t, '/a/[2024] Viaje Japon S01E02.mkv'):match('|false$'), '|false', 'a year is not a [Group]')
	eq(info(t, '/a/[01] Viaje - 02.mkv'):match('|false$'), '|false', 'a number is not a [Group]')
	eq(info(t, '/a/The Office - 05.mkv'), 'The Office|nil|5|false', 'a western series')
	eq(info(t, '/a/Sousou no Frieren - 05.mkv'), 'Sousou no Frieren|nil|5|false', 'the marker alone')
	eq(info(t, '/a/Vacaciones - 05 [20240115].mkv'), 'Vacaciones|nil|5|false', 'a date is not a CRC')
	eq(info(t, '/a/Reunion web - 05.mkv'), 'Reunion web|nil|5|false', '`web` alone is a word')
	-- Signs in the series name do not count: the series name is what is sent.
	for _, name in ipairs({
		'Documental ADN - 03.mp4', 'Analisis ADN paciente Garcia - 02.mkv', 'Viaje CR - 02.mp4',
		'Clase CR - 01.mp4', 'Informe CR Lopez - 04.mkv', 'Prueba ADN - 01.mkv',
		'Juicio caso ADN S01E02.mkv', 'Entrevista Hidive Juan S01E01.mkv', 'Viaje Bilibili - 02.mkv',
		'Proyecto B-Global - 03.mkv', 'Funi - 01.mkv', 'Clase 1080p - 02.mp4',
		'Clase [1080p] - 02.mp4', 'Clase [ABCD1234] - 02.mp4', 'Viaje.CR.-.02.mp4', 'Viaje.CR.S01E02.mkv',
		'Informe BD WEB-DL - 05.mkv',
	}) do
		eq(info(t, '/a/' .. name):match('|false$'), '|false', name)
	end
	-- Signs only count in brackets or in the technical tail, never in the
	-- loose words after the number (an episode title, a description); a CRC
	-- or a resolution alone is not enough.
	for _, name in ipairs({
		'Boda Ana - 01 (1080p).mp4', 'Paciente Garcia - 02 - Prueba ADN.mkv', 'Paciente Garcia - 02 analisis ADN.mkv',
		'Analisis.paciente.Garcia.S01E02.Prueba.ADN.mkv', 'Boda Ana - 02 - Costa Rica CR.mp4',
		'Juicio Garcia S01E02 Prueba ADN.mkv', 'Familia Lopez - 03 [ABCD1234].mkv',
		'Sousou no Frieren - 05 (1080p).mkv', 'Sousou no Frieren - 05 [ABCD1234].mkv', 'Sousou no Frieren - 05 [BD].mkv',
		'Boda Ana - 01 [1080p] [1080p].mp4', 'Paciente Garcia - 02 - Prueba ADN [ABCD1234].mkv',
		'Viaje.Japon.S01E02.Funi.Bilibili.mkv', 'Boda Ana - 02 Crunchyroll Hidive.mp4', 'Show.S01E05.1080p.WEB-DL.mkv',
	}) do
		eq(info(t, '/a/' .. name):match('|false$'), '|false', name)
	end
	-- The tail starts exactly at its first strong word (resolution, WEB-DL,
	-- BluRay, codec): a CR or ADN right before it is part of the description,
	-- and so is a description after it. A lone BD is an abbreviation outside
	-- brackets or a dotted tail.
	for _, name in ipairs({
		'Boda Ana - 02 - Costa Rica CR 720p.mp4', 'Paciente Garcia - 02 - Prueba ADN 1080p.mkv',
		'Paciente.Garcia.S01E02.Prueba.ADN.1080p.mkv', 'Paciente.Garcia.S01E02.ADN.1080p.mkv',
		'Juicio Garcia S01E02 Prueba CR 1080p.mkv', 'Juicio Garcia S01E02 Prueba ADN 1080p.mkv',
		'Paciente Garcia - 02 - Prueba ADN WEB-DL.mkv', 'Boda Ana - 02 - Costa Rica CR 1080p.mp4',
		'Boda Ana - 01 BD 1080p.mp4', 'Boda Ana - 01 1080p BD.mp4', 'Show.S01E05.CR.WEB-DL.mkv',
		'Paciente.Garcia.S01E02.1080p.Prueba.ADN.mkv', 'Paciente Garcia - 02 1080p prueba ADN.mkv',
	}) do
		eq(info(t, '/a/' .. name):match('|false$'), '|false', name)
	end
	-- A group only counts when all its words are technical, and a service in
	-- brackets needs another sign.
	for _, name in ipairs({
		'Paciente Garcia - 02 (prueba ADN Garcia).mkv', 'Paciente Garcia - 02 [Prueba ADN].mkv',
		'Consulta Garcia - 02 (ADN).mkv', 'Juicio Garcia S01E02 (CR).mkv', 'Show S01E05 (HIDIVE).mkv',
		'Show - 05 [CR].mkv', 'Boda Ana - 01 (1080p boda) [ABCD1234].mp4', 'Boda Ana - 01 (video 1080p) (BD).mp4',
		'Consulta Garcia - 02 [ADN] [CR].mkv',
	}) do
		eq(info(t, '/a/' .. name):match('|false$'), '|false', name)
	end
	eq(info(t, '/a/Holiday video.mkv'), 'nil', 'not a release')
	eq(info(t, '/a/Blade.Runner.2049.2017.1080p.BluRay.x264.mkv'), 'nil', 'a film')
	eq(info(t, '/a/[Group] Show - 12.5 [1080p].mkv'), 'nil', 'half episode')
	eq(info(t, '/a/[Group] Show - S01E01-E02 [1080p].mkv'), 'nil', 'two episodes')
	eq(info(t, '/a/[Group] Show - OVA [1080p].mkv'), 'nil', 'OVA')
	eq(info(t, '/a/[Group] Show - SP01 [1080p].mkv'), 'nil', 'special')
	eq(info(t, '/a/[Group] Show S00E03 [1080p].mkv'), 'nil', 'season 0')
	eq(info(t, '/a/[Group] - 05 [1080p].mkv'), 'nil', 'no series')
	eq(info(t, '/a/notes.txt'), 'nil', 'not a video')
	eq(info(t, 'ytdl://x'), 'nil'); eq(info(t, 'https://h/stream?token=x'), 'nil'); eq(info(t, nil), 'nil')
end)

test('release info: published on start-file with its path, whatever the options; cleared on end-file', function()
	for _, opts in ipairs({{}, {['hikari-title-enabled'] = 'no'}, {['hikari-title-pretty'] = 'no'}}) do
		local t = load(opts)
		local path = '/a/[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv'
		start(path)
		local r = mock.props[t.RELEASE_PROP]
		eq(r.series, 'Sousou no Frieren'); eq(r.episode, 5); eq(r.anime, true); eq(r.path, path)
		mock.events['end-file']()
		eq(next(mock.props[t.RELEASE_PROP]), nil, 'cleared')
		start('/a/Holiday video.mkv')
		eq(next(mock.props[t.RELEASE_PROP]), nil, 'nothing for a non-release')
	end
end)

test('release info: hostile names stay fast and give nothing odd', function()
	local t = load()
	local clock = os.clock()
	t.release_for('https://h/' .. string.rep('a', 1000000) .. '?filename=' .. string.rep('- 05 ', 20000))
	t.release_for('https://' .. string.rep('a', 1000000))
	t.release_for(string.rep('[(', 200000) .. ' - 05.mkv')
	assert(os.clock() - clock < 2, 'too slow: ' .. (os.clock() - clock))
	local r = t.release_for('/a/[G] Bad\27[31mName\7 - 05.mkv')
	assert(r and not r.series:find('%c'), 'no control characters')
end)

-- suji's title in parts (suji 0.7.0 or newer) ------------------------------------

-- The set-title messages sent to suji, in order, each as its list of arguments.
local function suji_titles_sent()
	local list = {}
	for _, c in ipairs(mock.commands) do
		if c[1] == 'script-message-to' and c[2] == 'suji' and c[3] == 'set-title' then
			list[#list + 1] = {select(4, unpack(c))}
		end
	end
	return list
end

local function same_args(actual, expected, what)
	eq(#actual, #expected, (what or 'arguments') .. ': count')
	for i = 1, #expected do eq(actual[i], expected[i], (what or 'arguments') .. ' #' .. i) end
end

-- suji as it is after loading: there, on or off, and its version published.
local function suji(version, on)
	mock.suji = true
	mock.props['user-data/suji/version'] = version
	mock.props['user-data/suji/enabled'] = on ~= false
end

test('suji 0.7: set-title with the series and the label, and the name only when there is one', function()
	load()
	suji('0.7.0')
	eq(start('/a/[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv'), 'Sousou no Frieren · E05', 'title on screen')
	local sent = suji_titles_sent()
	eq(#sent, 1, 'one message')
	same_args(sent[1], {'Sousou no Frieren', 'E05'}, 'no name')
	mock.events['file-loaded']()
	eq(#suji_titles_sent(), 1, 'not again on file-loaded')
	mock.events['end-file'](); mock.end_file()
	eq(start('/a/Show - S01E06 - The Name [1080p].mkv'), 'Show · T1 E06 · The Name', 'title on screen, unchanged')
	sent = suji_titles_sent()
	eq(#sent, 2, 'sent again for the next file')
	same_args(sent[2], {'Show', 'T1 E06', 'The Name'}, 'with the name')
	mock.events['end-file'](); mock.end_file()
	start('https://h/x?token=a&filename=Show.S02E03.1080p.WEB-DL.mkv')
	same_args(suji_titles_sent()[3], {'Show', 'T2 E03'}, 'from filename=')
end)

test('suji 0.6, turned off, missing or of an unknown version: nothing is sent', function()
	for _, case in ipairs({
		{'0.6.1', true}, {'0.7.0', false}, {nil, nil}, {'x', true}, {'', true}, {'0.6.9', true},
	}) do
		load()
		if case[1] or case[2] ~= nil then suji(case[1], case[2]) end
		eq(start('/a/Show.S01E05.mkv'), 'Show · T1 E05', 'title on screen as before')
		mock.events['file-loaded']()
		eq(#suji_titles_sent(), 0, tostring(case[1]) .. '/' .. tostring(case[2]))
	end
	-- A version that is there but not valid wins over the message, as in hikari-skip.
	load()
	suji('junk')
	mock.messages['suji-version']('0.7.0')
	start('/a/Show.S01E05.mkv')
	eq(#suji_titles_sent(), 0, 'invalid property over a good message')
end)

test('suji versions are compared by number; the message counts without the property', function()
	for _, version in ipairs({'0.10.0', '1.0.0', '0.7.1'}) do
		load()
		suji(version)
		start('/a/Show.S01E05.mkv')
		eq(#suji_titles_sent(), 1, version)
	end
	load()
	mock.suji = true
	mock.props['user-data/suji/enabled'] = true
	mock.messages['suji-version']('0.7.0')
	start('/a/Show.S01E05.mkv')
	same_args(suji_titles_sent()[1], {'Show', 'T1 E05'}, 'version from the message')
end)

test('suji: no episode, the fallback or pretty=no: nothing is sent, media-title shows', function()
	load()
	suji('0.7.0')
	eq(start('/a/Movie.Name.2023.1080p.BluRay.x264-GRP.mkv'), 'Movie Name (2023)', 'film')
	mock.events['end-file'](); mock.end_file()
	eq(start('https://h/live/master.m3u8?token=abc'), 'master.m3u8', 'fallback')
	mock.props['metadata/by-key/title'] = 'Live'
	mock.events['file-loaded']()
	eq(mock.props['force-media-title'], '', 'fallback withdrawn')
	eq(#suji_titles_sent(), 0, 'nothing for a film or the fallback')
	load({['hikari-title-pretty'] = 'no'})
	suji('0.7.0')
	start('https://h/x?token=a&filename=Show.S01E05.mkv')
	eq(#suji_titles_sent(), 0, 'pretty=no')
end)

test('suji: a title of the user or of the playlist entry: nothing is sent', function()
	load()
	suji('0.7.0')
	mock.props['force-media-title'] = 'Mi título'
	eq(start('/a/Show.S01E05.mkv'), 'Mi título')
	mock.events['file-loaded']()
	eq(#suji_titles_sent(), 0, 'force-media-title of the user')
	load()
	suji('0.7.0')
	mock.props['playlist-playing-pos'] = 0
	mock.props['playlist/0/title'] = 'Capítulo 1'
	eq(start('/a/Show.S01E05.mkv'), nil)
	mock.events['file-loaded']()
	eq(#suji_titles_sent(), 0, 'playlist title')
end)

test('suji: control characters are gone and each part is cut', function()
	local t = load()
	suji('0.7.0')
	local long = string.rep('Ñame ', 100)
	start('/a/[G] Bad\27Se\226\128\174ries\7\127 - S01E05 - Na\226\128\139me\1 ' .. long .. '[1080p].mkv')
	local sent = suji_titles_sent()
	eq(#sent, 1, 'one message')
	eq(#sent[1], 3, 'three parts')
	for i, part in ipairs(sent[1]) do
		assert(not part:find('%c'), 'control character in part ' .. i)
		assert(not part:find('\226\128[\139\174]'), 'invisible character in part ' .. i)
		assert(utf8_len(part) <= t.MAX_CHARS + 1, 'part ' .. i .. ' too long: ' .. utf8_len(part))
	end
	eq(sent[1][1], 'BadSeries')
	eq(sent[1][2], 'T1 E05')
	assert(sent[1][3]:find('^Name Ñame') and sent[1][3]:sub(-3) == '…', 'the long name is cut, with an ellipsis: ' .. sent[1][3])
end)

test('suji: late, turned off and on, a new language, and a title replaced by another script', function()
	load()
	start('/a/Show.S01E05.mkv')
	eq(#suji_titles_sent(), 0, 'no suji yet')
	-- suji sets its properties after this script's start-file.
	mock.suji = true
	mock.set('user-data/suji/version', '0.7.0')
	eq(#suji_titles_sent(), 0, 'not on yet')
	mock.set('user-data/suji/enabled', true)
	local sent = suji_titles_sent()
	eq(#sent, 1, 'sent once suji is there'); same_args(sent[1], {'Show', 'T1 E05'})
	mock.set('user-data/suji/enabled', false)
	sent = suji_titles_sent()
	eq(#sent, 2, 'taken back when turned off'); same_args(sent[2], {'', ''})
	mock.set('user-data/suji/enabled', true)
	sent = suji_titles_sent()
	eq(#sent, 3, 'sent again when turned on'); same_args(sent[3], {'Show', 'T1 E05'})
	mock.messages['suji-version']('0.7.0')
	sent = suji_titles_sent()
	eq(#sent, 4, 'suji started again'); same_args(sent[4], {'Show', 'T1 E05'})
	mock.set_script_opt('hikari-language', 'en')
	sent = suji_titles_sent()
	eq(#sent, 5, 'new language'); same_args(sent[5], {'Show', 'S1 E05'})
	mock.set('force-media-title', 'Changed by another script')
	sent = suji_titles_sent()
	eq(#sent, 6, 'taken back'); same_args(sent[6], {'', ''})
	mock.set_script_opt('hikari-language', 'es')
	eq(#suji_titles_sent(), 6, 'nothing more')
	eq(mock.props['force-media-title'], 'Changed by another script')
end)

test('the script avoids os.execute, io.popen and load*', function()
	local f = assert(io.open(SCRIPT, 'rb')); local src = f:read('*a'); f:close()
	for _, bad in ipairs({'os.execute', 'io.popen', 'loadstring', 'loadfile', 'dofile', 'load('}) do
		assert(not src:find(bad, 1, true), bad)
	end
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
