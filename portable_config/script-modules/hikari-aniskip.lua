-- hikari-aniskip: opening and ending times from AniSkip, for hikari-skip.lua.
-- A module, not a script: hikari-skip loads it (see the loader there).
--
-- hikari-skip only asks when the file has no opening or ending chapters. The
-- series, season and episode come from hikari-title.lua, which publishes what
-- it read from the release name (`[SubsPlease] Sousou no Frieren - 05 (1080p)`
-- -> Sousou no Frieren, episode 5). From there:
-- 1. MyAnimeList id of the series: AniList's public GraphQL API
--    (https://graphql.anilist.co, no key), searched with the series name. When
--    AniList cannot be reached or answers with an error, Jikan
--    (https://api.jikan.moe, an unofficial MyAnimeList API) is asked instead.
-- 2. Times: AniSkip (https://api.aniskip.com/v2/skip-times/<id>/<episode>),
--    asking for `op`, `ed`, `mixed-op` and `mixed-ed`.
-- 3. The answers are kept in ~~/hikari-aniskip.json, so the same episode, or
--    another of the same series, does not ask again.
--
-- Decisions:
-- - Why AniList first: one request gives every title of every match (romaji,
--   English, native, synonyms), its format, episode count and MyAnimeList id;
--   its limit is documented (30 to 90 requests a minute per address) and it is
--   the service most anime trackers use. Jikan scrapes MyAnimeList, allows 3
--   requests a second and 60 a minute, and is slower and down more often; it
--   is only the fallback, and only when AniList fails (not when AniList
--   answers "no such series").
-- - A match must be clear, or nothing is shown: a series (TV, TV_SHORT or ONA)
--   one of whose titles is, once normalised (lower case, punctuation as
--   spaces, apostrophes dropped, × as x), exactly the series name; for a
--   season N > 1, exactly the name followed by `Season N`, `Nth Season`,
--   `Second Season`, `SN` or `N` (as AniList names sequels). More than one
--   MyAnimeList id among the matches, or an episode number above the episode
--   count AniList knows, and the lookup stops.
-- - AniSkip answers with times submitted by players for one length of the
--   episode each. Only times whose episode length is within LENGTH_TOLERANCE
--   seconds of this file's duration are used (the closest one per kind), so a
--   release with another cut does not get times that do not fit.
-- - Nothing received is trusted: at most MAX_RESPONSE bytes, JSON through
--   utils.parse_json, every field checked for type and range (ids and episodes
--   positive integers, times finite, start < end, within MAX_SECONDS, a segment
--   no longer than MAX_SEGMENT). Received text is only compared, never shown,
--   put in a command line or used in a file name. The MyAnimeList id and the
--   episode go into the AniSkip URL as validated integers; the series name
--   goes to AniList as a JSON value on curl's stdin and to Jikan
--   percent-encoded.
-- - Network: curl, as in hikari-update.lua (same reasons): asynchronous
--   subprocesses (playback never waits), `-q` first so no .curlrc is read,
--   HTTPS only, no redirects, --max-time CURL_TIMEOUT; on Windows curl.exe by
--   absolute path in System32. Without curl, network or a valid answer:
--   nothing is shown, only a verbose log line, and nothing is cached (the next
--   time the episode is opened it asks again).
-- - Cache: ~~/hikari-aniskip.json, `{"version":1,"titles":{...},"episodes":{...}}`.
--   titles: normalised series name and season -> {at, mal, episodes} (mal 0:
--   no clear match). episodes: "<mal>:<episode>" -> {at, results} or
--   {at, found=false}. `at` is the unix time of the answer; entries expire
--   after TTL (shorter for "not found", as AniSkip keeps growing), and the
--   oldest go when there are more than CACHE_LIMITS. Read at most MAX_CACHE
--   bytes; a broken file or entry is ignored (as if never asked). Written
--   through a temporary file and a rename after re-reading it, so two mpv
--   windows do not undo each other's answers.

local msg = require('mp.msg')
local utils = require('mp.utils')

local M = {}

M.CACHE_PATH = '~~/hikari-aniskip.json'
M.ANILIST_URL = 'https://graphql.anilist.co'
M.JIKAN_URL = 'https://api.jikan.moe/v4/anime?limit=25&q='
M.ANISKIP_URL = 'https://api.aniskip.com/v2/skip-times/'
-- types[]=op&types[]=ed&types[]=mixed-op&types[]=mixed-ed, with the brackets
-- encoded so curl does not read them as a glob. episodeLength=0: every
-- submission, whatever its length (they are chosen here, see select).
M.ANISKIP_QUERY = '?types%5B%5D=op&types%5B%5D=ed&types%5B%5D=mixed-op&types%5B%5D=mixed-ed&episodeLength=0'
M.ANILIST_QUERY = 'query ($search: String) { Page(perPage: 25) { media(search: $search, type: ANIME) '
	.. '{ idMal format episodes title { romaji english native } synonyms } } }'

local CURL_TIMEOUT = 8          -- seconds, per request
local MAX_RESPONSE = 262144     -- bytes of an answer looked at; longer ones are refused
local MAX_CACHE = 524288        -- bytes of the cache file read
local MAX_SERIES = 200          -- bytes of a series name looked up
local MAX_CANDIDATES = 50       -- series in a search answer
local MAX_NAMES = 60            -- titles of one series
local MAX_NAME = 500            -- bytes of one title
local MAX_RESULTS = 30          -- AniSkip results kept
local MAX_ID = 999999999
local MAX_EPISODE = 9999
local MAX_SEASON = 99
local MAX_SECONDS = 6 * 3600    -- longest episode
local MAX_SEGMENT = 600         -- longest opening or ending
local LENGTH_TOLERANCE = 10     -- seconds between AniSkip's episode length and the file's
local DAY = 24 * 3600
M.TTL = {title = 30 * DAY, title_miss = 7 * DAY, times = 30 * DAY, times_miss = 3 * DAY}
M.CACHE_LIMITS = {titles = 500, episodes = 2000}

-- AniSkip skip types -> the kind of range in hikari-skip.
M.KIND_OF = {op = 'opening', ['mixed-op'] = 'opening', ed = 'ending', ['mixed-ed'] = 'ending'}
-- Formats that have episodes with an opening and an ending.
local FORMATS = {TV = true, TV_SHORT = true, ONA = true}
-- Jikan's names for them.
local JIKAN_FORMATS = {TV = 'TV', ONA = 'ONA'}

-- Unix time; tests replace it.
M.now = os.time

-- ---------------------------------------------------------------------------
-- Checks
-- ---------------------------------------------------------------------------

local function is_finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function is_int(n, min, max)
	return is_finite(n) and n == math.floor(n) and n >= min and n <= max
end

-- A string of 1..max bytes without control characters.
local function is_text(s, max)
	return type(s) == 'string' and #s > 0 and #s <= max and not s:find('%c')
end

-- An array (consecutive integer keys from 1) of at most `max` entries, or nil.
local function array(value, max)
	if type(value) ~= 'table' then return nil end
	local n = #value
	if n > max then return nil end
	for k in pairs(value) do
		if type(k) ~= 'number' or k < 1 or k > n or k ~= math.floor(k) then return nil end
	end
	return value
end

-- ---------------------------------------------------------------------------
-- Matching
-- ---------------------------------------------------------------------------

-- Lower case (ASCII), apostrophes dropped, `×` as x, any other ASCII
-- punctuation as a space, spaces squeezed. Other UTF-8 is kept as it is.
function M.normalize(text)
	if type(text) ~= 'string' then return '' end
	text = text:sub(1, MAX_NAME):lower()
	text = text:gsub("'", ''):gsub('\226\128\153', ''):gsub('\195\151', ' x ')
	text = text:gsub('[%c%p%s]', ' '):gsub(' +', ' '):gsub('^ ', ''):gsub(' $', '')
	return text
end

local ORDINAL_WORDS = {'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth', 'tenth'}

local function ordinal(n)
	local last2, last = n % 100, n % 10
	if last2 >= 11 and last2 <= 13 then return n .. 'th' end
	if last == 1 then return n .. 'st' end
	if last == 2 then return n .. 'nd' end
	if last == 3 then return n .. 'rd' end
	return n .. 'th'
end

-- Normalised titles that name `series` (normalised) in `season` (nil: 1).
function M.season_names(series, season)
	local names = {}
	if not season or season == 1 then
		names[series] = true
		names[series .. ' season 1'] = true
		names[series .. ' 1st season'] = true
		names[series .. ' s1'] = true
		return names
	end
	names[series .. ' season ' .. season] = true
	names[series .. ' ' .. ordinal(season) .. ' season'] = true
	names[series .. ' s' .. season] = true
	names[series .. ' ' .. season] = true
	if ORDINAL_WORDS[season] then names[series .. ' ' .. ORDINAL_WORDS[season] .. ' season'] = true end
	return names
end

-- The one MyAnimeList id among `candidates` ({mal, format, episodes, names})
-- that is clearly `series` in `season`, and its episode count (or nil).
-- nil when none is, or when the matches disagree.
function M.pick(candidates, series, season)
	local wanted = M.season_names(M.normalize(series), season)
	local found, episodes = nil, nil
	for _, c in ipairs(candidates) do
		if c.mal and FORMATS[c.format] then
			for _, name in ipairs(c.names) do
				if wanted[M.normalize(name)] then
					if found and found ~= c.mal then return nil end
					found, episodes = c.mal, c.episodes
					break
				end
			end
		end
	end
	return found, episodes
end

-- ---------------------------------------------------------------------------
-- Answers
-- ---------------------------------------------------------------------------

local function decode(body)
	if type(body) ~= 'string' or body == '' then return nil, 'empty answer' end
	if #body > MAX_RESPONSE then return nil, 'answer too long' end
	local value, err = utils.parse_json(body)
	if type(value) ~= 'table' then return nil, 'not JSON: ' .. tostring(err) end
	return value
end

-- Titles of a series: strings that pass is_text, at most MAX_NAMES.
local function add_names(names, value)
	if is_text(value, MAX_NAME) and #names < MAX_NAMES then names[#names + 1] = value end
end

-- Series in AniList's answer, as {mal, format, episodes, names}; nil and an
-- error for anything but a valid answer (GraphQL errors included).
function M.parse_anilist(body)
	local value, err = decode(body)
	if not value then return nil, err end
	if value.errors ~= nil then return nil, 'AniList error' end
	local data = type(value.data) == 'table' and value.data
	local page = data and type(data.Page) == 'table' and data.Page
	local media = page and array(page.media, MAX_CANDIDATES)
	if not media then return nil, 'unexpected answer' end
	local list = {}
	for _, m in ipairs(media) do
		if type(m) == 'table' then
			local c = {
				mal = is_int(m.idMal, 1, MAX_ID) and m.idMal or nil,
				format = type(m.format) == 'string' and m.format or nil,
				episodes = is_int(m.episodes, 1, MAX_EPISODE) and m.episodes or nil,
				names = {},
			}
			if type(m.title) == 'table' then
				add_names(c.names, m.title.romaji)
				add_names(c.names, m.title.english)
				add_names(c.names, m.title.native)
			end
			for _, name in ipairs(array(m.synonyms, MAX_NAMES) or {}) do add_names(c.names, name) end
			list[#list + 1] = c
		end
	end
	return list
end

-- The same from Jikan's answer (MyAnimeList's own fields).
function M.parse_jikan(body)
	local value, err = decode(body)
	if not value then return nil, err end
	local data = array(value.data, MAX_CANDIDATES)
	if not data then return nil, 'unexpected answer' end
	local list = {}
	for _, a in ipairs(data) do
		if type(a) == 'table' then
			local c = {
				mal = is_int(a.mal_id, 1, MAX_ID) and a.mal_id or nil,
				format = type(a.type) == 'string' and JIKAN_FORMATS[a.type] or nil,
				episodes = is_int(a.episodes, 1, MAX_EPISODE) and a.episodes or nil,
				names = {},
			}
			add_names(c.names, a.title)
			add_names(c.names, a.title_english)
			add_names(c.names, a.title_japanese)
			for _, name in ipairs(array(a.title_synonyms, MAX_NAMES) or {}) do add_names(c.names, name) end
			for _, t in ipairs(array(a.titles, MAX_NAMES) or {}) do
				if type(t) == 'table' then add_names(c.names, t.title) end
			end
			list[#list + 1] = c
		end
	end
	return list
end

-- One AniSkip result as kept here ({type, start, finish, length}), or nil.
local function check_result(r)
	if type(r) ~= 'table' then return nil end
	local kind, start, finish, length = r.type, r.start, r.finish, r.length
	if type(kind) ~= 'string' or not M.KIND_OF[kind] then return nil end
	if not is_finite(start) or not is_finite(finish) or not is_finite(length) then return nil end
	if start < 0 or finish <= start or finish - start > MAX_SEGMENT then return nil end
	if length <= 0 or length > MAX_SECONDS or start >= length then return nil end
	return {type = kind, start = start, finish = finish, length = length}
end

-- AniSkip's results ({type, start, finish, length}, empty when it has none
-- for the episode); nil and an error for anything but a valid answer.
-- Results of unknown types or with impossible times are dropped.
function M.parse_aniskip(body)
	local value, err = decode(body)
	if not value then return nil, err end
	if value.found == false then return {} end
	if value.found ~= true then return nil, 'unexpected answer' end
	local results = array(value.results, MAX_RESULTS)
	if not results then return nil, 'unexpected answer' end
	local list = {}
	for _, r in ipairs(results) do
		if type(r) == 'table' and type(r.interval) == 'table' then
			local checked = check_result({
				type = r.skipType, start = r.interval.startTime, finish = r.interval.endTime,
				length = r.episodeLength,
			})
			if checked then list[#list + 1] = checked end
		end
	end
	return list
end

-- The ranges for a file of `duration` seconds: per kind, the result whose
-- episode length is closest to it (within LENGTH_TOLERANCE), cut to the
-- duration. A list of {kind = 'opening'|'ending', start, finish}, by start.
function M.select(results, duration)
	local ranges = {}
	if type(results) ~= 'table' or not is_finite(duration) or duration <= 0 then return ranges end
	local best = {}
	for _, r in ipairs(results) do
		local kind = M.KIND_OF[r.type]
		local off = math.abs(r.length - duration)
		if kind and off <= LENGTH_TOLERANCE and r.start < duration
			and (not best[kind] or off < best[kind].off) then
			best[kind] = {off = off, start = r.start, finish = math.min(r.finish, duration)}
		end
	end
	for _, kind in ipairs({'opening', 'ending'}) do
		local b = best[kind]
		if b and b.finish > b.start then ranges[#ranges + 1] = {kind = kind, start = b.start, finish = b.finish} end
	end
	table.sort(ranges, function(a, b) return a.start < b.start end)
	return ranges
end

-- ---------------------------------------------------------------------------
-- What to look up
-- ---------------------------------------------------------------------------

-- The lookup for what hikari-title published (user-data/hikari_title/release),
-- or nil when it is not an anime episode that can be looked up:
-- {series, season, episode, key}. The table is another script's, so it is
-- checked as if it came from the network.
function M.query(release)
	if type(release) ~= 'table' or release.anime ~= true then return nil end
	local series, episode, season = release.series, release.episode, release.season
	if not is_text(series, MAX_SERIES) or not is_int(episode, 1, MAX_EPISODE) then return nil end
	if season ~= nil and not is_int(season, 1, MAX_SEASON) then return nil end
	local key = M.normalize(series)
	if key == '' then return nil end
	return {series = series, season = season, episode = episode, key = key .. '|' .. (season or 1)}
end

-- ---------------------------------------------------------------------------
-- Cache
-- ---------------------------------------------------------------------------

local function expand(path)
	local expanded = mp.command_native({'expand-path', path})
	if type(expanded) ~= 'string' or expanded == '' then return nil end
	return expanded
end

local function empty_cache() return {version = 1, titles = {}, episodes = {}} end

local function check_title(e)
	if type(e) ~= 'table' or not is_int(e.at, 0, 1e11) then return nil end
	if not is_int(e.mal, 0, MAX_ID) then return nil end
	if e.episodes ~= nil and not is_int(e.episodes, 1, MAX_EPISODE) then return nil end
	return {at = e.at, mal = e.mal, episodes = e.episodes}
end

local function check_episode(e)
	if type(e) ~= 'table' or not is_int(e.at, 0, 1e11) then return nil end
	if e.found == false then return {at = e.at, found = false} end
	local results = array(e.results, MAX_RESULTS)
	if not results then return nil end
	local list = {}
	for _, r in ipairs(results) do
		local checked = check_result(r)
		if not checked then return nil end
		list[#list + 1] = checked
	end
	if #list == 0 then return nil end
	return {at = e.at, results = list}
end

-- The cache, every entry checked; an empty one when there is none or it is broken.
function M.read_cache()
	local path = expand(M.CACHE_PATH)
	local file = path and io.open(path, 'rb')
	if not file then return empty_cache() end
	local content = file:read(MAX_CACHE + 1) or ''
	file:close()
	if #content > MAX_CACHE then
		msg.verbose('AniSkip cache too big, ignored')
		return empty_cache()
	end
	local ok, value = pcall(utils.parse_json, content)
	if not ok or type(value) ~= 'table' or value.version ~= 1 then
		if content ~= '' then msg.verbose('AniSkip cache unreadable, ignored') end
		return empty_cache()
	end
	local cache = empty_cache()
	if type(value.titles) == 'table' then
		for key, e in pairs(value.titles) do
			-- Normalising can make a name longer (`×` -> ` x `): twice the limit.
			if is_text(key, 2 * MAX_SERIES) then cache.titles[key] = check_title(e) end
		end
	end
	if type(value.episodes) == 'table' then
		for key, e in pairs(value.episodes) do
			if type(key) == 'string' and key:match('^%d+:%d+$') and #key <= 20 then cache.episodes[key] = check_episode(e) end
		end
	end
	return cache
end

-- The newest `limit` entries of a table of {at = ...}.
local function prune(entries, limit)
	local keys = {}
	for key in pairs(entries) do keys[#keys + 1] = key end
	if #keys <= limit then return entries end
	table.sort(keys, function(a, b)
		if entries[a].at ~= entries[b].at then return entries[a].at > entries[b].at end
		return a < b
	end)
	local kept = {}
	for i = 1, limit do kept[keys[i]] = entries[keys[i]] end
	return kept
end

-- Writes through a temporary file and a rename (as hikari-update.lua does).
local function write_file_atomic(path, content)
	local tmp = path .. '.tmp'
	os.remove(tmp)
	local file, err = io.open(tmp, 'wb')
	if not file then return false, err end
	local ok, write_err = file:write(content)
	local closed, close_err = file:close()
	if not ok or not closed then
		os.remove(tmp)
		return false, write_err or close_err
	end
	local renamed, rename_err = os.rename(tmp, path)
	if not renamed then
		-- On Windows rename() won't replace an existing file: remove it and retry.
		os.remove(path)
		renamed, rename_err = os.rename(tmp, path)
	end
	if not renamed then
		os.remove(tmp)
		return false, rename_err
	end
	return true
end

-- Adds one entry (section 'titles' or 'episodes') to the cache on disk,
-- re-read first so another mpv's answers are kept.
function M.save(section, key, entry)
	local path = expand(M.CACHE_PATH)
	if not path then return false end
	local cache = M.read_cache()
	cache[section][key] = entry
	cache.titles = prune(cache.titles, M.CACHE_LIMITS.titles)
	cache.episodes = prune(cache.episodes, M.CACHE_LIMITS.episodes)
	local json, err = utils.format_json(cache)
	local ok = false
	if json then ok, err = write_file_atomic(path, json .. '\n') end
	if not ok then msg.warn('Could not save ' .. M.CACHE_PATH .. ': ' .. tostring(err)) end
	return ok
end

-- An entry that is still valid at time `t`: not older than its TTL, and not
-- from the future (a clock moved back makes it old).
local function fresh(entry, ttl, t)
	return entry ~= nil and entry.at <= t and t - entry.at < ttl
end

function M.title_fresh(entry, t)
	return entry ~= nil and fresh(entry, entry.mal == 0 and M.TTL.title_miss or M.TTL.title, t)
end

function M.episode_fresh(entry, t)
	return entry ~= nil and fresh(entry, entry.found == false and M.TTL.times_miss or M.TTL.times, t)
end

-- ---------------------------------------------------------------------------
-- Network
-- ---------------------------------------------------------------------------

-- 'windows', 'darwin' or another name, from mpv when it says (as hikari-update.lua).
local function platform()
	local p = mp.get_property_native('platform')
	if type(p) == 'string' and p ~= '' then return p end
	if package.config:sub(1, 1) == '\\' then return 'windows' end
	return 'unix'
end

-- Windows: System32\curl.exe from a SystemRoot that is a plain drive path
-- (C:\Windows), nil otherwise (as hikari-update.lua).
local function windows_curl()
	local root = os.getenv('SystemRoot')
	if type(root) ~= 'string' then return nil end
	root = root:gsub('\\$', '')
	if not root:match('^%a:\\[^%c"/:*?<>|%%]+$') or root:match('\\\\') or root:match('\\$') then return nil end
	local curl = root .. '\\System32\\curl.exe'
	local info = utils.file_info(curl)
	if not info or not info.is_file then return nil end
	return curl
end

-- curl from PATH (outside Windows), so a missing one means no attempt at all.
local function path_curl()
	local path = os.getenv('PATH')
	if type(path) ~= 'string' then return nil end
	for dir in path:gmatch('[^:]+') do
		local file = io.open(dir .. '/curl', 'rb')
		if file then file:close(); return 'curl' end
	end
	return nil
end

function M.curl_program()
	if platform() == 'windows' then return windows_curl() end
	return path_curl()
end

-- curl's arguments for `url`; with `post`, the body comes from stdin.
function M.curl_args(program, url, post)
	local args = {
		program, '-q', '--silent', '--show-error', '--max-time', tostring(CURL_TIMEOUT),
		'--proto', '=https', '--max-redirs', '0', '--max-filesize', tostring(MAX_RESPONSE),
		'-H', 'Accept: application/json',
	}
	if post then
		args[#args + 1] = '-H'
		args[#args + 1] = 'Content-Type: application/json'
		args[#args + 1] = '--data-binary'
		args[#args + 1] = '@-'
	end
	args[#args + 1] = url
	return args
end

-- Runs curl and calls done(body) with its output, or done(nil) on failure.
local function fetch(what, url, body, done)
	local curl = M.curl_program()
	if not curl then
		msg.verbose('AniSkip: curl not found, not asking ' .. what)
		return done(nil)
	end
	mp.command_native_async({
		name = 'subprocess',
		args = M.curl_args(curl, url, body ~= nil),
		stdin_data = body,
		playback_only = false,
		capture_stdout = true,
		capture_stderr = true,
	}, function(success, result, err)
		if not success or type(result) ~= 'table' then
			msg.verbose('AniSkip: ' .. what .. ' failed: ' .. tostring(err))
			return done(nil)
		end
		if result.status ~= 0 then
			msg.verbose('AniSkip: ' .. what .. ' failed: curl ' .. tostring(result.status) .. ' '
				.. tostring(result.stderr or ''))
			return done(nil)
		end
		done(result.stdout)
	end)
end

-- Every byte but A-Z a-z 0-9 - . _ ~ as %XX.
local function url_encode(text)
	return (text:gsub('[^%w%-%._~]', function(c) return string.format('%%%02X', c:byte()) end))
end

-- Candidates for `series`: AniList, or Jikan when AniList fails. done(list)
-- or done(nil) when neither answered.
local function search(series, done)
	local body = utils.format_json({query = M.ANILIST_QUERY, variables = {search = series}})
	msg.verbose('AniSkip: asking AniList for the MyAnimeList id of "' .. series .. '"')
	fetch('AniList', M.ANILIST_URL, body, function(answer)
		local list, err = M.parse_anilist(answer)
		if list then return done(list) end
		if answer then msg.verbose('AniSkip: AniList: ' .. tostring(err)) end
		msg.verbose('AniSkip: asking Jikan instead')
		fetch('Jikan', M.JIKAN_URL .. url_encode(series), nil, function(jikan)
			local jlist, jerr = M.parse_jikan(jikan)
			if not jlist and jikan then msg.verbose('AniSkip: Jikan: ' .. tostring(jerr)) end
			done(jlist)
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- Lookup
-- ---------------------------------------------------------------------------

-- The AniSkip results for `query` (see M.query): done(results), a list as
-- parse_aniskip gives it, possibly empty; done(nil) when there is no answer.
-- From the cache when it has a fresh entry; otherwise asks and saves.
function M.lookup(query, done)
	local cache = M.read_cache()

	local function times(mal, episodes)
		if mal == 0 then
			msg.verbose('AniSkip: no clear match for "' .. query.series .. '"')
			return done(nil)
		end
		if episodes and query.episode > episodes then
			msg.verbose('AniSkip: episode ' .. query.episode .. ' is past the ' .. episodes .. ' of MyAnimeList id ' .. mal)
			return done(nil)
		end
		local key = string.format('%d:%d', mal, query.episode)
		local entry = cache.episodes[key]
		if M.episode_fresh(entry, M.now()) then
			msg.verbose('AniSkip: times of ' .. key .. ' from the cache')
			return done(entry.results or {})
		end
		msg.verbose('AniSkip: asking AniSkip for episode ' .. query.episode .. ' of MyAnimeList id ' .. mal)
		fetch('AniSkip', M.ANISKIP_URL .. string.format('%d/%d', mal, query.episode) .. M.ANISKIP_QUERY, nil, function(answer)
			local results, err = M.parse_aniskip(answer)
			if not results then
				if answer then msg.verbose('AniSkip: ' .. tostring(err)) end
				return done(nil)
			end
			if #results > 0 then
				M.save('episodes', key, {at = M.now(), results = results})
			else
				M.save('episodes', key, {at = M.now(), found = false})
			end
			done(results)
		end)
	end

	local entry = cache.titles[query.key]
	if M.title_fresh(entry, M.now()) then
		msg.verbose('AniSkip: MyAnimeList id of "' .. query.series .. '" from the cache')
		return times(entry.mal, entry.episodes)
	end
	search(query.series, function(candidates)
		if not candidates then return done(nil) end
		local mal, episodes = M.pick(candidates, query.series, query.season)
		M.save('titles', query.key, {at = M.now(), mal = mal or 0, episodes = mal and episodes or nil})
		times(mal or 0, episodes)
	end)
end

return M
