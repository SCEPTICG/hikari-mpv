-- hikari-aniskip: opening and ending times from AniSkip, for hikari-skip.lua.
-- A module, not a script: hikari-skip loads it (see the loader there).
--
-- hikari-skip only asks when the file has no opening or ending chapters. The
-- series, season and episode come from hikari-title.lua, which publishes what
-- it read from the release name (`[SubsPlease] Sousou no Frieren - 05 (1080p)`
-- -> Sousou no Frieren, episode 5). From there:
-- 1. MyAnimeList id of the series: AniList's public GraphQL API
--    (https://graphql.anilist.co, no key), searched with the series name. When
--    AniList cannot be reached or answers with an error, Kitsu
--    (https://kitsu.app/api/edge, no key, JSON:API) is asked instead, and when
--    Kitsu fails too, Jikan (https://api.jikan.moe, an unofficial MyAnimeList
--    API).
-- 2. Times: AniSkip (https://api.aniskip.com/v2/skip-times/<id>/<episode>),
--    asking for `op`, `ed`, `mixed-op` and `mixed-ed` (an opening or ending
--    mixed with scenes of the episode: skipped as openings and endings too)
--    for an episode of this file's length (its duration rounded to seconds).
-- 3. The answers are kept in ~~/hikari-aniskip.json, so the same episode, or
--    another of the same series, does not ask again.
--
-- Decisions:
-- - Why AniList first: one request gives every title of every match (romaji,
--   English, native, synonyms), its format, episode count and MyAnimeList id;
--   its limit is documented (30 to 90 requests a minute per address) and it is
--   the service most anime trackers use (in October 2026 it answered every
--   request with a 403 and `errors`: "temporarily disabled", a failure like
--   any other). Kitsu next: one request gives the same (its titles by locale,
--   abbreviated titles, subtype, episode count, and its mappings to other
--   sites, MyAnimeList's among them), and it answers fast. Jikan last: it
--   scrapes MyAnimeList, allows 3 requests a second and 60 a minute, and is
--   the slowest and the one down most often. Each is asked only when the one
--   before fails (cannot be reached, an error, an answer that is not valid),
--   not when it answers "no such series".
-- - A match must be clear, or nothing is shown: a series (TV, TV_SHORT or ONA)
--   one of whose titles is, once normalised (lower case, punctuation as
--   spaces, apostrophes dropped, × as x), exactly the series name; for a
--   season N > 1, exactly the name followed by `Season N`, `Nth Season`,
--   `Second Season`, `SN` or `N` (as AniList and Kitsu name sequels). More
--   than one MyAnimeList id among the matches, or an episode number above the
--   episode count the service knows, and the lookup stops.
-- - AniSkip keeps times submitted by players, each for one length of the
--   episode, and answers with at most one per type: with `episodeLength`, the
--   one whose length is closest to it; without (or 0), the most voted
--   whatever its length, which may be another cut's (Shingeki no Kyojin 1 in
--   a 1442 s file: an opening for 1540 s with 0, one for 1441.9 s with 1442).
--   So the length is always sent, and the closest may still be far: only
--   times whose episode length is within LENGTH_TOLERANCE seconds of this
--   file's duration are used (the closest one per kind). 10 s takes in the
--   usual differences between encodes of one broadcast (a second of black, a
--   card or a preview more or less at the end, which leave the opening in
--   place) and leaves out other cuts (a TV broadcast against a BD, ads).
-- - Nothing received is trusted: at most MAX_RESPONSE bytes, JSON through
--   utils.parse_json, every field checked for type and range (ids and episodes
--   positive integers, times finite, start < end, within MAX_SECONDS, a segment
--   no longer than MAX_SEGMENT). Received text is only compared, never shown,
--   put in a command line or used in a file name. The MyAnimeList id and the
--   episode go into the AniSkip URL as validated integers (Kitsu's ids come
--   as text: digits only, then the same range); the series name goes to
--   AniList as a JSON value on curl's stdin and to Kitsu and Jikan
--   percent-encoded.
-- - Network: curl, as in hikari-update.lua (same reasons): asynchronous
--   subprocesses (playback never waits), `-q` first so no .curlrc is read,
--   HTTPS only, no redirects, --max-time CURL_TIMEOUT; on Windows curl.exe by
--   absolute path in System32. Without curl, network or a valid answer:
--   nothing is shown, only a verbose log line, and nothing is cached (the next
--   time the episode is opened it asks again).
-- - Cache: ~~/hikari-aniskip.json, `{"version":1,"titles":{...},"episodes":{...}}`.
--   titles: normalised series name and season -> {at, mal, episodes} (mal 0:
--   no clear match). episodes: "<mal>:<episode>:<length>" -> {at, results}
--   or {at, found=false}, the length (seconds) being the one sent to AniSkip,
--   so a "not found" for one cut does not stop another from asking. `at` is
--   the unix time of the answer; entries expire after TTL (shorter for "not
--   found", as AniSkip keeps growing). On saving, expired entries go, then
--   the oldest when there are more than CACHE_LIMITS or the file would pass
--   CACHE_BUDGET bytes (under MAX_CACHE, the most that is read: a bigger file
--   would be ignored whole). A broken file or entry is ignored (as if never
--   asked). Written through a temporary file of its own (named after mpv's
--   pid) and a rename after re-reading it, so two mpv windows do not undo
--   each other's answers or write into the same temporary file. Temporary
--   files more than a day old (an mpv that died before the rename) are
--   removed on the first save of each mpv; younger ones are left alone.

local msg = require('mp.msg')
local utils = require('mp.utils')

local M = {}

M.CACHE_PATH = '~~/hikari-aniskip.json'
M.ANILIST_URL = 'https://graphql.anilist.co'
M.JIKAN_URL = 'https://api.jikan.moe/v4/anime?limit=25&q='
-- 20 series (Kitsu's largest page), each with its mappings (ids on other
-- sites) and only the fields used; the brackets encoded as in ANISKIP_QUERY.
M.KITSU_URL = 'https://kitsu.app/api/edge/anime?page%5Blimit%5D=20&include=mappings'
	.. '&fields%5Banime%5D=canonicalTitle,titles,abbreviatedTitles,subtype,episodeCount,mappings'
	.. '&fields%5Bmappings%5D=externalSite,externalId&filter%5Btext%5D='
-- Kitsu refuses (406) any other Accept.
M.KITSU_ACCEPT = 'application/vnd.api+json'
M.ANISKIP_URL = 'https://api.aniskip.com/v2/skip-times/'
-- types[]=op&types[]=ed&types[]=mixed-op&types[]=mixed-ed, with the brackets
-- encoded so curl does not read them as a glob, and the episode length in
-- whole seconds (an integer, see M.query): AniSkip answers with the times
-- whose length is closest to it (see select for the check done here).
M.ANISKIP_QUERY = '?types%5B%5D=op&types%5B%5D=ed&types%5B%5D=mixed-op&types%5B%5D=mixed-ed&episodeLength='
M.ANILIST_QUERY = 'query ($search: String) { Page(perPage: 25) { media(search: $search, type: ANIME) '
	.. '{ idMal format episodes title { romaji english native } synonyms } } }'

local CURL_TIMEOUT = 8          -- seconds, per request
local MAX_RESPONSE = 262144     -- bytes of an answer looked at; longer ones are refused
local MAX_CACHE = 524288        -- bytes of the cache file read
local CACHE_BUDGET = MAX_CACHE - 65536 -- bytes the cache is kept under when saved
local MAX_SERIES = 200          -- bytes of a series name looked up
local MAX_CANDIDATES = 50       -- series in a search answer
local MAX_NAMES = 60            -- titles of one series
local MAX_NAME = 500            -- bytes of one title
local MAX_MAPPINGS = 1000       -- mappings (ids on other sites) in a Kitsu answer
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
M.CACHE_BUDGET = CACHE_BUDGET

-- AniSkip skip types -> the kind of range in hikari-skip.
M.KIND_OF = {op = 'opening', ['mixed-op'] = 'opening', ed = 'ending', ['mixed-ed'] = 'ending'}
-- Formats that have episodes with an opening and an ending.
local FORMATS = {TV = true, TV_SHORT = true, ONA = true}
-- Jikan's names for them.
local JIKAN_FORMATS = {TV = 'TV', ONA = 'ONA'}
-- Kitsu's (its subtypes: TV, ONA, OVA, movie, special, music; short series
-- are TV, there is no TV_SHORT).
local KITSU_FORMATS = {TV = 'TV', ONA = 'ONA'}

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

-- A MyAnimeList id as Kitsu writes it (text: "52991"), as a number; nil for
-- anything but digits without a leading zero, in range.
local function kitsu_id(text)
	if type(text) ~= 'string' or #text > 9 or not text:match('^[1-9]%d*$') then return nil end
	local id = tonumber(text)
	return is_int(id, 1, MAX_ID) and id or nil
end

-- The same from Kitsu's answer (JSON:API): each series lists its mappings
-- (relationships.mappings.data, {type, id}), and the mappings themselves are
-- in `included`; the one for "myanimelist/anime" holds the id. A series
-- linked to two different MyAnimeList ids gives one entry per id, so that a
-- match on it is ambiguous (see pick).
function M.parse_kitsu(body)
	local value, err = decode(body)
	if not value then return nil, err end
	if value.errors ~= nil then return nil, 'Kitsu error' end
	local data = array(value.data, MAX_CANDIDATES)
	local included = value.included == nil and {} or array(value.included, MAX_MAPPINGS)
	if not data or not included then return nil, 'unexpected answer' end
	-- Mapping id -> MyAnimeList id.
	local mal_of = {}
	for _, i in ipairs(included) do
		local attributes = type(i) == 'table' and i.type == 'mappings' and is_text(i.id, MAX_NAME)
			and type(i.attributes) == 'table' and i.attributes
		if attributes and attributes.externalSite == 'myanimelist/anime' then
			mal_of[i.id] = kitsu_id(attributes.externalId)
		end
	end
	local list = {}
	for _, a in ipairs(data) do
		local attributes = type(a) == 'table' and type(a.attributes) == 'table' and a.attributes
		if attributes then
			local format = type(attributes.subtype) == 'string' and KITSU_FORMATS[attributes.subtype] or nil
			local episodes = is_int(attributes.episodeCount, 1, MAX_EPISODE) and attributes.episodeCount or nil
			local names = {}
			add_names(names, attributes.canonicalTitle)
			if type(attributes.titles) == 'table' then
				-- An object of locale -> title; sorted so the MAX_NAMES kept do not
				-- depend on the order pairs gives.
				local locales = {}
				for locale in pairs(attributes.titles) do
					if type(locale) == 'string' then locales[#locales + 1] = locale end
				end
				table.sort(locales)
				for _, locale in ipairs(locales) do add_names(names, attributes.titles[locale]) end
			end
			for _, name in ipairs(array(attributes.abbreviatedTitles, MAX_NAMES) or {}) do add_names(names, name) end
			local relationships = type(a.relationships) == 'table' and a.relationships
			local mappings = relationships and type(relationships.mappings) == 'table' and relationships.mappings
			local links = mappings and array(mappings.data, MAX_MAPPINGS) or {}
			local ids, seen = {}, {}
			for _, link in ipairs(links) do
				local mal = type(link) == 'table' and link.type == 'mappings' and is_text(link.id, MAX_NAME)
					and mal_of[link.id]
				if mal and not seen[mal] then
					seen[mal] = true
					ids[#ids + 1] = mal
				end
			end
			if #ids == 0 then ids[1] = false end
			for _, mal in ipairs(ids) do
				list[#list + 1] = {mal = mal or nil, format = format, episodes = episodes, names = names}
			end
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

-- The lookup for what hikari-title published (user-data/hikari_title/release)
-- in a file of `duration` seconds, or nil when it is not an anime episode
-- that can be looked up: {series, season, episode, length, key}, `length`
-- being the duration rounded to whole seconds. The table is another
-- script's, so it is checked as if it came from the network.
function M.query(release, duration)
	if type(release) ~= 'table' or release.anime ~= true then return nil end
	if not is_finite(duration) then return nil end
	local length = math.floor(duration + 0.5)
	if not is_int(length, 1, MAX_SECONDS) then return nil end
	local series, episode, season = release.series, release.episode, release.season
	if not is_text(series, MAX_SERIES) or not is_int(episode, 1, MAX_EPISODE) then return nil end
	if season ~= nil and not is_int(season, 1, MAX_SEASON) then return nil end
	local key = M.normalize(series)
	if key == '' then return nil end
	return {series = series, season = season, episode = episode, length = length, key = key .. '|' .. (season or 1)}
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
			if type(key) == 'string' and key:match('^%d+:%d+:%d+$') and #key <= 30 then cache.episodes[key] = check_episode(e) end
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

-- The entries of `entries` still fresh at time `t` (see title_fresh).
local function unexpired(entries, is_fresh, t)
	local kept = {}
	for key, e in pairs(entries) do
		if is_fresh(e, t) then kept[key] = e end
	end
	return kept
end

-- The cache as JSON within `budget` bytes: the oldest entries (titles and
-- episodes together) go until it fits. nil and an error if it cannot be
-- written as JSON.
local function fit(cache, budget)
	local json, err = utils.format_json(cache)
	while json and #json > budget do
		local all = {}
		for _, section in ipairs({'titles', 'episodes'}) do
			for key, e in pairs(cache[section]) do all[#all + 1] = {section = section, key = key, at = e.at} end
		end
		if #all == 0 then break end
		table.sort(all, function(a, b)
			if a.at ~= b.at then return a.at < b.at end
			if a.section ~= b.section then return a.section < b.section end
			return a.key < b.key
		end)
		-- About the share that is over, and one more: few passes.
		local drop = math.min(#all, math.floor(#all * (#json - budget) / #json) + 1)
		for i = 1, drop do cache[all[i].section][all[i].key] = nil end
		json, err = utils.format_json(cache)
	end
	return json, err
end

-- A name for the temporary file of this mpv: two windows writing at once
-- must not share one. mpv's pid; a counter for writes within one mpv.
local tmp_count = 0
local function tmp_name(path)
	tmp_count = tmp_count + 1
	local pid = mp.get_property_number('pid')
	if not is_int(pid, 1, 2 ^ 31) then pid = math.random(1, 2 ^ 30) end
	return string.format('%s.%d-%d.tmp', path, pid, tmp_count)
end

-- Writes through a temporary file and a rename (as hikari-update.lua does).
local function write_file_atomic(path, content)
	local tmp = tmp_name(path)
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

-- Temporary files of the cache older than this are left over from an mpv that
-- died between writing and renaming: the first save of each mpv removes them.
-- Younger ones may be another window's write in progress and stay.
M.STALE_TMP_AGE = 24 * 3600
local swept = false

-- Removes `<cache>.<pid>-<n>.tmp` files (that exact pattern, next to the
-- cache) last changed more than STALE_TMP_AGE before time `t`.
local function remove_stale_tmp(path, t)
	local dir, base = utils.split_path(path)
	local names = dir and base and utils.readdir(dir, 'files')
	if type(names) ~= 'table' then return end
	local prefix = base .. '.'
	for _, name in ipairs(names) do
		if type(name) == 'string' and name:sub(1, #prefix) == prefix
			and name:sub(#prefix + 1):match('^%d+%-%d+%.tmp$') then
			local file = utils.join_path(dir, name)
			local info = utils.file_info(file)
			if info and info.is_file and type(info.mtime) == 'number' and t - info.mtime > M.STALE_TMP_AGE then
				os.remove(file)
			end
		end
	end
end

-- Adds one entry (section 'titles' or 'episodes') to the cache on disk,
-- re-read first so another mpv's answers are kept. Expired entries go first,
-- then the oldest beyond CACHE_LIMITS and CACHE_BUDGET.
function M.save(section, key, entry)
	local path = expand(M.CACHE_PATH)
	if not path then return false end
	local cache = M.read_cache()
	local t = M.now()
	if not swept then
		swept = true
		remove_stale_tmp(path, t)
	end
	cache.titles = unexpired(cache.titles, M.title_fresh, t)
	cache.episodes = unexpired(cache.episodes, M.episode_fresh, t)
	cache[section][key] = entry
	cache.titles = prune(cache.titles, M.CACHE_LIMITS.titles)
	cache.episodes = prune(cache.episodes, M.CACHE_LIMITS.episodes)
	local json, err = fit(cache, math.min(M.CACHE_BUDGET, CACHE_BUDGET))
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
-- `accept`: the media type asked for (nil: application/json).
function M.curl_args(program, url, post, accept)
	local args = {
		program, '-q', '--silent', '--show-error', '--max-time', tostring(CURL_TIMEOUT),
		'--proto', '=https', '--max-redirs', '0', '--max-filesize', tostring(MAX_RESPONSE),
		'-H', 'Accept: ' .. (accept or 'application/json'),
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
-- `accept` as in curl_args.
local function fetch(what, url, body, done, accept)
	local curl = M.curl_program()
	if not curl then
		msg.verbose('AniSkip: curl not found, not asking ' .. what)
		return done(nil)
	end
	mp.command_native_async({
		name = 'subprocess',
		args = M.curl_args(curl, url, body ~= nil, accept),
		stdin_data = body,
		playback_only = false,
		capture_stdout = true,
		capture_stderr = true,
		-- A bit more than curl may write (--max-filesize), not mpv's 64 MB.
		capture_size = MAX_RESPONSE + 4096,
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

-- Candidates for `series`: from AniList; when it cannot be reached or does
-- not answer validly, from Kitsu; and then the same, from Jikan. done(list),
-- empty when the one that answered knows no such series (the next is not
-- asked then), or done(nil) when none answered.
local function search(series, done)
	local sources = {
		{name = 'AniList', url = M.ANILIST_URL, parse = M.parse_anilist,
			body = utils.format_json({query = M.ANILIST_QUERY, variables = {search = series}})},
		{name = 'Kitsu', url = M.KITSU_URL .. url_encode(series), parse = M.parse_kitsu, accept = M.KITSU_ACCEPT},
		{name = 'Jikan', url = M.JIKAN_URL .. url_encode(series), parse = M.parse_jikan},
	}
	local function ask(i)
		local source = sources[i]
		if not source then return done(nil) end
		if i == 1 then
			msg.verbose('AniSkip: asking ' .. source.name .. ' for the MyAnimeList id of "' .. series .. '"')
		else
			msg.verbose('AniSkip: asking ' .. source.name .. ' instead')
		end
		fetch(source.name, source.url, source.body, function(answer)
			local list, err = source.parse(answer)
			if list then return done(list) end
			if answer then msg.verbose('AniSkip: ' .. source.name .. ': ' .. tostring(err)) end
			ask(i + 1)
		end, source.accept)
	end
	ask(1)
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
		local key = string.format('%d:%d:%d', mal, query.episode, query.length)
		local entry = cache.episodes[key]
		if M.episode_fresh(entry, M.now()) then
			msg.verbose('AniSkip: times of ' .. key .. ' from the cache')
			return done(entry.results or {})
		end
		msg.verbose('AniSkip: asking AniSkip for episode ' .. query.episode .. ' of MyAnimeList id ' .. mal
			.. ', ' .. query.length .. ' s long')
		local url = M.ANISKIP_URL .. string.format('%d/%d', mal, query.episode) .. M.ANISKIP_QUERY
			.. string.format('%d', query.length)
		fetch('AniSkip', url, nil, function(answer)
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
