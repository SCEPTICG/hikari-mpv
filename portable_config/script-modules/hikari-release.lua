-- hikari-release: what a release name says, for hikari's scripts. A module,
-- not a script: hikari-title.lua (tidy titles, and what hikari-skip looks up
-- on AniSkip) and hikari-resume.lua (continue watching by series) load it, so
-- both read file names the same way.
--
-- Usage:
--   release.pretty_title('[SubsPlease] Frieren - 05 (1080p)')  -> 'Frieren · E05', true, info
--   release.release_for('/a/[SubsPlease] Frieren - 05 (1080p).mkv')
--     -> {series = 'Frieren', episode = 5, anime = true}
--   release.episode_of('Frieren S01E06.mkv')
--     -> {series = 'Frieren', season = 1, episode = 6, key = 'frieren|1', group = nil}
--   release.next_episode('Frieren - 05.mkv', names)  -> 'Frieren - 06.mkv' or nil
--
-- Decisions:
-- - The name rules are the ones hikari-title.lua had (see its header): moved
--   here as they were, nothing about the titles changes.
-- - The season and episode labels of pretty_title follow hikari's language:
--   this module requires hikari-i18n itself. The scripts load hikari-i18n
--   first and then this module with the same loader (~~/script-modules in
--   package.path for the require), so that require finds the texts the script
--   already has.
-- - An episode of a series (episode_of) is a video file name with one plain
--   episode: what release_info gives (series, season, episode), whether or
--   not it looks like anime (`Show.S01E05.1080p.WEB-DL.mkv` is one too).
--   Specials, OVAs, ranges (`E01-E02`) and half episodes (`12.5`) are not:
--   they are single files.
-- - The key of a series: the series name normalised as hikari-aniskip.lua
--   does (ASCII lower case, apostrophes dropped, punctuation as spaces,
--   spaces squeezed), `|` and the season (none: 1). `Frieren - 05` and
--   `Frieren S01E06` are the same series; `Frieren S02E01` is another. Lower
--   case makes it the same on Windows, whose names ignore case.
-- - The group of a release, to choose between two versions of the next
--   episode: the [Group] in front, or else a `-Group` at the end of the name,
--   after the technical tail and not a technical word itself
--   (`...1080p.WEB-DL.x264-GROUP`, never the `DL` of a final `WEB-DL`, nor
--   `Start` in `Show - 05 - Re-Start`); lower case. nil when there is neither.
-- - The next episode (next_episode) is looked for among the names given (the
--   folder of the file, read by the caller): same key, the smallest episode
--   number above the current one; of several files with that number, the one
--   of the same group, otherwise the first by name. Only names with a video
--   extension are read, and a folder with more than `max` names has none.
-- - Every pattern is anchored to a token and input is cut to MAX_RAW before
--   any work, so hostile names cost linear time.

local i18n = require('hikari-i18n')

local M = {}

local MAX_CHARS = 150
-- Raw input kept before decoding: enough for MAX_CHARS 4-byte characters
-- written as %XX%XX%XX%XX, and a bound on the work done per title.
local MAX_RAW = MAX_CHARS * 12
local ELLIPSIS = '…'

-- Extensions stripped from the end of `filename` (case-insensitive).
local VIDEO_EXTENSIONS = {
	'mkv', 'mp4', 'm4v', 'webm', 'avi', 'mov', 'wmv', 'flv', 'ts', 'm2ts', 'mts',
	'mpg', 'mpeg', 'ogv', '3gp',
}
local VIDEO_EXTENSION_SET = {}
for _, ext in ipairs(VIDEO_EXTENSIONS) do VIDEO_EXTENSION_SET[ext] = true end

-- Decodes %XX sequences; malformed ones are kept as they are. With `plus`, '+'
-- becomes a space (query strings only; in a path '+' is literal).
local function url_decode(text, plus)
	if plus then text = text:gsub('%+', ' ') end
	return (text:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end))
end

-- Keeps only valid UTF-8 and drops control and invisible characters: C0, DEL,
-- C1, zero-width and direction marks, line and paragraph separators, bidi
-- overrides and isolates, BOM. Newlines and tabs become spaces.
local function sanitize(text)
	local out = {}
	local i, len = 1, #text
	while i <= len do
		local c = text:byte(i)
		local size, min
		if c < 0x80 then size, min = 1, 0
		elseif c >= 0xC2 and c <= 0xDF then size, min = 2, 0x80
		elseif c >= 0xE0 and c <= 0xEF then size, min = 3, 0x800
		elseif c >= 0xF0 and c <= 0xF4 then size, min = 4, 0x10000
		end
		local code
		if size and i + size - 1 <= len then
			code = size == 1 and c or c % (2 ^ (7 - size))
			for j = i + 1, i + size - 1 do
				local b = text:byte(j)
				if b < 0x80 or b > 0xBF then code = nil break end
				code = code * 64 + b % 64
			end
			if code and (code < min or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF)) then code = nil end
		end
		if not code then
			i = i + 1 -- invalid byte: drop it
		else
			if code == 9 or code == 10 or code == 13 then
				out[#out + 1] = ' '
			elseif not (code < 32 or code == 127 or (code >= 0x80 and code <= 0x9F)
				or code == 0x061C or (code >= 0x200B and code <= 0x200F) or code == 0xFEFF
				or code == 0x2028 or code == 0x2029
				or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069)) then
				out[#out + 1] = text:sub(i, i + size - 1)
			end
			i = i + size
		end
	end
	return (table.concat(out):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''))
end

-- Cuts to MAX_CHARS characters (not bytes), never inside a UTF-8 sequence.
-- Expects sanitized (valid UTF-8) input.
local function truncate(text)
	local count, i = 0, 1
	while i <= #text do
		count = count + 1
		if count > MAX_CHARS then
			return text:sub(1, i - 1):gsub(' $', '') .. ELLIPSIS
		end
		local c = text:byte(i)
		i = i + (c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4)
	end
	return text
end

local function strip_extension(name)
	local base, ext = name:match('^(.+)%.([%w]+)$')
	if base and VIDEO_EXTENSION_SET[ext:lower()] then return base end
	return name
end

-- Release-name tidying ------------------------------------------------------

-- Lower-case tokens of the technical tail of a release name. STRONG ones
-- (source, codec, resolution...) never appear in a real title, so a film name
-- is cut at the first one. WEAK ones (services, `DUAL`, `PROPER`...) could be
-- ordinary words (`Dual Destinies`): they are only cut when they sit right
-- before a strong one, and they mark a [...] or (...) group as technical.
local STRONG_WORDS, WEAK_WORDS = {}, {}
local function word_set(set, list)
	for word in list:gmatch('%S+') do set[word] = true end
end
word_set(STRONG_WORDS, [[web-dl webdl web-rip webrip bluray blu-ray bdrip brrip bdremux
	hdtv dvdrip hdrip remux x264 x265 h264 h265 h.264 h.265 hevc avc xvid av1 vp9
	truehd dts-hd 10bit 8bit 10-bit hdr10 hdr10+]])
word_set(WEAK_WORDS, [[web 4k 8k uhd bd dvd hdr dovi sdr atmos dts dual dual-audio multi multisub
	multi-sub msubs subs subbed dubbed multiple subtitle subtitles jpn eng vostfr
	cr adn amzn nf dsnp hulu hmax atvp hidive funi uncensored proper repack opus
	dub sub raw internal dl vf vff multi-audio]])

-- 'strong', 'weak' or nil for one word.
local function tech_kind(word)
	word = word:lower()
	if STRONG_WORDS[word] then return 'strong' end
	if WEAK_WORDS[word] then return 'weak' end
	-- In space-separated names `1080p.WEB-DL` stays one token: check its head.
	local head = word:match('^([^.]+)%.')
	if head then
		if STRONG_WORDS[head] then return 'strong' end
		if WEAK_WORDS[head] then return 'weak' end
		word = head
	end
	if word:match('^%d%d%d%d?[pi]$')                               -- 480p, 1080p, 1080i
		or word:match('^aac[%d.]*$') or word:match('^ddp?[%d.]*$')
		or word:match('^e?ac3[%d.]*$') or word:match('^flac[%d.]*$')
		or word:match('^opus[%d.]+$') then                           -- `Opus` alone is a word
		return 'strong'
	end
	return nil
end

local function is_year(word)
	return word:match('^19%d%d$') ~= nil or word:match('^20%d%d$') ~= nil
end

-- [...] or (...) groups worth keeping in a title: a year, or words with no
-- digits and nothing technical, such as `(US)` or `[Oshi no Ko]`.
-- `(1080p)`, `[ABCD1234]` or `[Multiple Subtitle]` go.
local function keep_group(text)
	local inner = text:sub(2, -2)
	if is_year(inner) then return true end
	if inner:find('%d') or not inner:find('%w') then return false end
	for word in inner:gmatch('[^%s%._,]+') do
		if tech_kind(word) then return false end
	end
	return true
end

-- Splits a name into words and bracket groups (`[...]`, `(...)`, unnested).
-- Without spaces in the name, dots are separators too (`Show.Name.S01E01`);
-- with spaces they are kept (`Dr. Stone`). Every step consumes input and
-- `find` only looks for a closer once per kind, so the cost is linear.
local function tokenize(name)
	local spaced = name:find(' ', 1, true) ~= nil
	local sep = spaced and '^[%s_]+' or '^[%s%._]+'
	local word = spaced and '^[^%s_%[%(]+' or '^[^%s%._%[%(]+'
	-- After a lone '[' or '(' brackets are just characters: `(((` stays one word.
	local lone = spaced and '^[^%s_]+' or '^[^%s%._]+'
	local closer = {['['] = ']', ['('] = ')'}
	local has_closer = {['['] = true, ['('] = true}
	local tokens, i, len = {}, 1, #name
	while i <= len do
		local _, e = name:find(sep, i)
		if e then
			i = e + 1
		else
			local c = name:sub(i, i)
			local close_at
			if closer[c] and has_closer[c] then
				close_at = name:find(closer[c], i + 1, true)
				if not close_at then has_closer[c] = false end
			end
			if close_at then
				tokens[#tokens + 1] = {text = name:sub(i, close_at), group = c}
				i = close_at + 1
			else
				-- A word, or a lone '[' / '(' with no closer and the word after it.
				local _, w = name:find(closer[c] and lone or word, i)
				w = w or i
				tokens[#tokens + 1] = {text = name:sub(i, w)}
				i = w + 1
			end
		end
	end
	return tokens
end

local function episode_number(digits)
	if not digits or #digits > 4 then return nil end
	return string.format('%02d', tonumber(digits))
end

-- `05`, or `12.5` for a half episode (recaps, specials between two episodes).
local function episode_text(digits, fraction)
	local number = episode_number(digits)
	if number and fraction then return number .. '.' .. fraction end
	return number
end

-- What may follow an episode number: nothing, or punctuation that starts
-- something else (`.1080p` when dots are not separators).
local function ends_cleanly(rest)
	return rest == '' or rest:match('^[^%w]') ~= nil
end

-- `v2`, `-E02`, `-02`, `E02` after an episode number. Returns the end of the
-- range (or nil) and whether what is left is acceptable.
local function episode_suffix(rest)
	rest = rest:gsub('^[vV]%d+', '', 1)
	if rest:match('^[%-Ee]') then
		local last, after = rest:match('^%-?[Ee]?[Pp]?(%d+)(.*)$')
		if last then
			after = after:gsub('^[vV]%d+', '', 1)
			if ends_cleanly(after) then return last, true end
		end
	end
	return nil, ends_cleanly(rest)
end

-- A bare episode number token: `05`, `05v2`, `12.5` (a year is not one: `- 2049`).
-- Returns its digits and fraction, or nil.
local function bare_number(token)
	if not token or token.group then return nil end
	local digits, fraction = token.text:match('^(%d+)%.(%d)$')
	if digits then return digits, fraction end
	local after
	digits, after = token.text:match('^(%d+)(.*)$')
	if digits and (after == '' or after:match('^[vV]%d+$')) and not is_year(digits) and #digits <= 4 then
		return digits
	end
	return nil
end

local function is_separator(token)
	return token ~= nil and not token.group and token.text:match('^[%-~.]+$') ~= nil
end

-- Episode marker starting at tokens[i], and the number of tokens it uses. A
-- marker is a table: `first` and `last` (episode range, digits), `fraction`,
-- `season` (number), `special` (season 0, SP01) or `extra` (`OVA`, `OAD`, `ONA`).
local function marker_at(tokens, i)
	local t = tokens[i]
	if t.group then return nil end
	local text = t.text
	-- S01E01, s1e1, S01E01v2, S01E01-E02, S01E01E02
	local season, first, rest = text:match('^[Ss](%d+)[Ee](%d+)(.*)$')
	if season then
		local last, ok = episode_suffix(rest)
		if not ok or #season > 4 or not episode_number(first) or (last and not episode_number(last)) then return nil end
		season = tonumber(season)
		-- Season 0 holds the specials: `Show · Special E03`.
		if season == 0 then return {special = true, first = first, last = last}, 1 end
		return {season = season, first = first, last = last}, 1
	end
	-- E01, EP01, E01v2, EP01-02
	first, rest = text:match('^[Ee][Pp]?(%d+)(.*)$')
	if first then
		local last, ok = episode_suffix(rest)
		if not ok or not episode_number(first) or (last and not episode_number(last)) then return nil end
		return {first = first, last = last}, 1
	end
	-- SP01, SP1v2 (specials)
	first, rest = text:match('^[Ss][Pp](%d+)(.*)$')
	if first then
		rest = rest:gsub('^[vV]%d+', '', 1)
		if not ends_cleanly(rest) or not episode_number(first) then return nil end
		return {special = true, first = first}, 1
	end
	local lower = text:lower()
	local nxt = tokens[i + 1]
	-- OVA, OAD, ONA, alone or with a number: `OVA`, `OVA 2`, `OVA - 02`.
	if lower == 'ova' or lower == 'oad' or lower == 'ona' then
		local extra = text:upper()
		local digits = bare_number(nxt)
		if digits then return {extra = extra, first = digits}, 2 end
		if is_separator(nxt) then
			digits = bare_number(tokens[i + 2])
			if digits then return {extra = extra, first = digits}, 3 end
		end
		-- Alone only at the end of the name proper: `Show - OVA [1080p]`.
		if nxt == nil or nxt.group or is_separator(nxt) then return {extra = extra}, 1 end
		return nil
	end
	-- `Special 01`, `SP 01`
	if lower == 'special' or lower == 'sp' then
		local digits = bare_number(nxt)
		if digits then return {special = true, first = digits}, 2 end
		return nil
	end
	-- `Episode 01`, `Ep 01`, `- 01`, `- 01v2`, `- 12.5` (anime releases)
	if lower == 'episode' or lower == 'ep' or lower == 'ep.' or lower == '-' then
		local digits, fraction = bare_number(nxt)
		if digits then return {first = digits, fraction = fraction, dash = lower == '-'}, 2 end
	end
	return nil
end

-- The marker's label in `lang` (hikari's language when nil): `S1 E05`,
-- `T1 E01-E02`, `Special E03`, `OVA`, `E12.5`, `第1季 第05集`.
local function marker_label(marker, lang)
	local parts = {}
	if marker.extra then
		parts[#parts + 1] = marker.extra
	elseif marker.special then
		parts[#parts + 1] = i18n.t('title_special', nil, lang)
	elseif marker.season then
		parts[#parts + 1] = i18n.t('title_season', {season = marker.season}, lang)
	end
	if marker.first then
		local first = episode_text(marker.first, marker.fraction)
		local last = marker.last and episode_number(marker.last)
		if last and last ~= first then
			parts[#parts + 1] = i18n.t('title_episodes', {first = first, last = last}, lang)
		else
			parts[#parts + 1] = i18n.t('title_episode', {episode = first}, lang)
		end
	end
	return table.concat(parts, ' ')
end

-- Ordinals that may come before `Season`.
local ORDINAL_WORDS = {first = 1, second = 2, third = 3, fourth = 4, fifth = 5, sixth = 6}

-- A season written at the end of the series name, before position `stop`:
-- `S2`, `Season 2`, `2nd Season`, `Second Season`, `(Season 2)`. Returns the
-- season and the position where it starts, or nil.
local function season_before(tokens, stop)
	local j = stop - 1
	while j >= 1 and is_separator(tokens[j]) do j = j - 1 end
	if j < 2 then return nil end
	local t = tokens[j]
	local n, at
	if t.group then
		local inner = t.text:sub(2, -2):lower()
		n = inner:match('^season (%d%d?)$') or inner:match('^(%d%d?)%a%a season$') or inner:match('^s(%d%d?)$')
		at = j
	else
		local word = t.text:lower()
		n, at = word:match('^s(%d%d?)$'), j
		local prev = tokens[j - 1]
		if not n and j >= 3 and not prev.group then
			local before = prev.text:lower()
			if before == 'season' and word:match('^%d%d?$') then
				n, at = word, j - 1
			elseif word == 'season' then
				n = before:match('^(%d%d?)st$') or before:match('^(%d%d?)nd$') or before:match('^(%d%d?)rd$')
					or before:match('^(%d%d?)th$') or ORDINAL_WORDS[before]
				at = j - 1
			end
		end
	end
	n = tonumber(n)
	if not n or n == 0 then return nil end
	return n, at
end

-- Words before position `stop`, without the leading [...] group (the release
-- group), without technical [...] and (...) groups, and without separators
-- left dangling at either end. The second result is true when a group was
-- dropped (a sign of a release name).
local function join_words(tokens, stop, start)
	local words, dropped = {}, false
	start = start or 1
	for i = start, stop - 1 do
		local t = tokens[i]
		if not t.group or (i > 1 and keep_group(t.text)) then
			words[#words + 1] = t.text
		else
			dropped = true
		end
	end
	local first, last = 1, #words
	while first <= last and words[first]:match('^[%-~.]+$') do first = first + 1 end
	while last >= first and words[last]:match('^[%-~.]+$') do last = last - 1 end
	return table.concat(words, ' ', first, last), dropped
end

-- Some groups name a series in lower case (Erai-raws: `jukishi`). A name with
-- no capital letter at all gets one at its start (`Jukishi`); a name with any
-- capital (`DanMachi`, `sousou no Frieren`) is left as the group wrote it.
-- ASCII only: `%l` and `%u` do not see accented letters.
local function capitalize(title)
	if title:find('%u') or not title:find('^%l') then return title end
	return (title:gsub('^%l', string.upper))
end

-- Words that end an episode title: anything technical, plus a version (`v2`).
local function ends_episode_title(token)
	return token.group or is_separator(token) or tech_kind(token.text) ~= nil
		or token.text:match('^[vV]%d+$') ~= nil
end

-- The episode title after a marker that ends before position `from`, when it
-- is clearly one: in names with spaces it must follow a ` - `
-- (`Show - S01E05 - The Title [1080p]`); in dotted names it is the words up to
-- the technical tail (`Show.S01E05.The.Title.1080p.WEB`). nil otherwise.
local function episode_title(tokens, from, spaced)
	local i = from
	if spaced then
		if not tokens[i] or tokens[i].group or tokens[i].text ~= '-' then return nil end
		i = i + 1
	end
	local words = {}
	while tokens[i] and not ends_episode_title(tokens[i]) do
		words[#words + 1] = tokens[i].text
		i = i + 1
	end
	local title = table.concat(words, ' ')
	if not title:find('%a') then return nil end
	return title
end

-- Services and words that only anime releases carry.
local ANIME_WORDS = {}
word_set(ANIME_WORDS, [[cr crunchyroll adn hidive funi funimation b-global bilibili]])
-- Sources that only releases carry (not `web` or `dvd` alone: ordinary words).
local SOURCE_WORDS = {}
word_set(SOURCE_WORDS, [[bd bdrip bluray blu-ray bdremux web-dl webdl webrip web-rip hdtv dvdrip]])

-- A fansub [Group] in front: a [...] first token with a letter in it
-- (`[2024]` or `[01]` are not groups).
local function front_group(tokens)
	local t = tokens[1]
	return t ~= nil and t.group == '[' and t.text:sub(2, -2):find('%a') ~= nil
end

-- The words of a token, split at spaces, dots, underscores, commas and `+`
-- (`1080p.CR.WEB-DL` is three), lower-cased; a group without its brackets.
local function token_words(t)
	local text = t.group and t.text:sub(2, -2) or t.text
	local words = {}
	for word in text:gmatch('[^%s%._,%+]+') do words[#words + 1] = word:lower() end
	return words
end

-- Where the technical tail of a release starts, from token `from` on: exactly
-- at the first word outside brackets that is strongly technical (`1080p`,
-- `WEB-DL`, `BluRay`, `x264`; `1080p.CR.WEB-DL` in a spaced name). Never at a
-- weak word before it: `Costa Rica CR 720p` or `Prueba.ADN.1080p` would make
-- the `CR` or `ADN` of a description a sign. Past the end when there is none:
-- `Prueba.ADN` or `- 02 - Costa Rica CR` have no tail.
local function tail_start(tokens, from)
	for i = from, #tokens do
		local t = tokens[i]
		if not t.group and tech_kind(t.text) == 'strong' then return i end
	end
	return #tokens + 1
end

-- A resolution: `1080p`, `720p`, `2160p`, `1080i`.
local function is_resolution(word) return word:match('^%d%d%d%d?[pi]$') ~= nil end

-- Eight hex digits with a letter (`20240115` is a date).
local function is_crc_text(word) return word:match('^%x%x%x%x%x%x%x%x$') ~= nil and word:find('%a') ~= nil end

-- A CRC: `[ABCD1234]`.
local function is_crc(t)
	local inner = t.group == '[' and t.text:sub(2, -2)
	return inner and is_crc_text(inner) or false
end

-- Labels that only release groups put in brackets, besides the technical
-- words (`[Dual Audio]`, `[Multi-Subs]`).
local LABEL_WORDS = {}
word_set(LABEL_WORDS, [[audio multi-subs multisubs multi-subtitle multi-subtitles softsub softsubs
	hardsub hardsubs esub esubs]])

-- One lower-case word that is technical by itself: strong, weak, a service, a
-- source, a resolution, a CRC or a release label.
local function exact_tech(word)
	return STRONG_WORDS[word] or WEAK_WORDS[word] or ANIME_WORDS[word] or SOURCE_WORDS[word]
		or LABEL_WORDS[word] or is_resolution(word) or is_crc_text(word)
		or word:match('^aac[%d.]*$') or word:match('^ddp?[%d.]*$') or word:match('^e?ac3[%d.]*$')
		or word:match('^flac[%d.]*$') or word:match('^opus[%d.]+$')
end

-- Is every word of a [...] or (...) group technical? `[1080p CR WEB-DL AVC
-- AAC]`, `(HIDIVE)` and `[Multiple Subtitle]` are; `(prueba ADN Garcia)` is
-- not, and none of its words is then a sign. A dotted word counts when it is
-- technical whole (`H.264`) or in every part (`1080p.CR`).
local function technical_group(t)
	local any = false
	for word in t.text:sub(2, -2):lower():gmatch('[^%s_,%+]+') do
		any = true
		if not exact_tech(word) then
			if not word:find('.', 1, true) then return false end
			for part in word:gmatch('[^.]+') do
				if not exact_tech(part) then return false end
			end
		end
	end
	return any
end

-- The signs of a release after the episode number (from token `from` on).
-- Only two places count, never the free text that follows the number (an
-- episode title, loose words):
-- - a [...] or (...) group made only of technical words (`[1080p]`,
--   `(HIDIVE)`, `[CR]`, `[ABCD1234]`, `[1080p CR WEB-DL AVC AAC]`);
-- - the technical tail: from its first strong word (tail_start) on, for as
--   long as every word is technical (`.1080p.CR.WEB-DL.AAC2`), so a
--   description after it (`1080p.Prueba.ADN`) does not count either. `BD`,
--   an everyday abbreviation, only counts there in a dotted name
--   (`.1080p.BD.x264`): in a spaced one only in brackets (`[BD]`).
-- Returns whether there is an anime service in the tail, whether there is one
-- in a group, and how many kinds of technical sign (resolution, source, CRC)
-- there are.
local function release_signs(tokens, from, spaced)
	local tail = tail_start(tokens, from)
	local in_tail = false
	local tail_service, group_service, resolution, source, crc = false, false, false, false, false
	for i = from, #tokens do
		local t = tokens[i]
		local words
		if t.group then
			if technical_group(t) then words = token_words(t) end
		else
			if i == tail then in_tail = true end
			if in_tail then
				words = token_words(t)
				for _, word in ipairs(words) do
					if not exact_tech(word) then in_tail = false; words = nil; break end
				end
			end
		end
		for _, word in ipairs(words or {}) do
			if ANIME_WORDS[word] then
				if t.group then group_service = true else tail_service = true end
			elseif is_resolution(word) then resolution = true
			elseif SOURCE_WORDS[word] and (word ~= 'bd' or t.group or not spaced) then source = true end
		end
		if words and is_crc(t) then crc = true end
	end
	local kinds = (resolution and 1 or 0) + (source and 1 or 0) + (crc and 1 or 0)
	return tail_service, group_service, kinds
end

-- Does the release look like anime? An episode marker (the caller has one)
-- and a clear sign of an anime release, so that a home video (`Boda Ana -
-- 01 (1080p).mp4`, `Familia Lopez - 03 [ABCD1234].mkv`), a series such as
-- `The Office - 05.mkv` or a file whose episode title happens to hold `ADN` or
-- `CR` (`Paciente Garcia - 02 - Prueba ADN.mkv`) is never sent anywhere:
-- - a [Group] in front (`[SubsPlease] Show - 05`);
-- - an anime service (CR, HIDIVE, ADN...) in the technical tail
--   (`Show.S01E05.1080p.CR.WEB-DL`), or in brackets together with another
--   sign (`Show S01E05 (HIDIVE) [1080p]`): a lone `(ADN)` or `[CR]` is as easy
--   to write on a personal video as `(Garcia)`;
-- - or the `Show - 05` marker with two kinds of technical sign after it, in
--   brackets or in the tail: resolution, source, CRC (`- 05 (1080p)
--   [ABCD1234]`, `.-.05.1080p.WEB-DL`). One alone is not enough: a CRC or a
--   `(1080p)` is easy to find on a personal video.
-- The series name (before the marker) is never searched: it is what gets
-- sent, and in `Analisis ADN paciente Garcia - 02` its words are not signs. A
-- western `Show.S01E05.1080p.WEB-DL` has neither the group, the service nor
-- the `- 05` marker: not anime.
local function looks_like_anime(tokens, marker, tail, spaced)
	if front_group(tokens) then return true end
	local tail_service, group_service, kinds = release_signs(tokens, tail, spaced)
	if tail_service or (group_service and kinds >= 1) then return true end
	return marker.dash == true and kinds >= 2
end

-- What hikari-skip can look up on AniSkip for a marker: one plain episode of
-- a series (not a range, half episode, special or OVA). nil otherwise.
-- `tail` is the first token after the marker; `spaced`: the name has spaces.
local function release_info(tokens, marker, series, tail, spaced)
	if marker.last or marker.fraction or marker.special or marker.extra or not marker.first then return nil end
	return {
		series = series, season = marker.season, episode = tonumber(marker.first),
		anime = looks_like_anime(tokens, marker, tail, spaced),
	}
end

-- Turns a release name into `Series · S1 E05`, `Series · E05 · Episode title`
-- or, with no episode marker, the name up to its technical tail with dots as
-- spaces. Falls back to `name` itself when nothing sensible is left. The
-- second result says whether the name looked like a release (a marker, a
-- technical tail or brackets dropped); `lang` is the language of the labels
-- (hikari's when nil). The third, for names with an episode marker, is what
-- release_info gives. Expects sanitized input already cut to MAX_RAW; every
-- pattern is anchored to a token, so the work stays linear.
local function pretty_title(name, lang)
	local tokens = tokenize(name)
	local spaced = name:find(' ', 1, true) ~= nil
	local nameless_marker = false
	for i = 1, #tokens do
		local marker, used = marker_at(tokens, i)
		if marker then
			local stop, start = i, 1
			if not marker.season and not marker.special and not marker.extra then
				local season, at = season_before(tokens, i)
				if season and join_words(tokens, at) ~= '' then
					marker.season, stop = season, at
				end
			end
			local series = join_words(tokens, stop, start)
			if series ~= '' then
				local title = capitalize(series) .. ' · ' .. marker_label(marker, lang)
				local episode = episode_title(tokens, i + used, spaced)
				if episode then title = title .. ' · ' .. episode end
				return title, true, release_info(tokens, marker, capitalize(series), i + used, spaced)
			end
			-- `S01E01.1080p`, `- 01`: a marker but no series in front. Look on:
			-- in `Special 7 - 05` the series is `Special 7`.
			nameless_marker = true
		end
	end
	if nameless_marker then return name, false end
	-- No marker (a film): cut at the first strong technical word that is not
	-- the first word, plus the weak ones right before it (`NF.WEB-DL`), and
	-- keep a year right before the cut as `(2023)`. A year at the very end stays
	-- as it is: in `Blade Runner 2049` it is part of the title.
	local first_word
	for i = 1, #tokens do
		if not tokens[i].group then first_word = i break end
	end
	local stop = #tokens + 1
	if first_word then
		for i = first_word + 1, #tokens do
			if not tokens[i].group and tech_kind(tokens[i].text) == 'strong' then stop = i break end
		end
		while stop <= #tokens and stop - 1 > first_word and not tokens[stop - 1].group
			and tech_kind(tokens[stop - 1].text) == 'weak' do
			stop = stop - 1
		end
	end
	local year_at
	if stop <= #tokens and first_word and stop - 1 > first_word and not tokens[stop - 1].group
		and is_year(tokens[stop - 1].text) then
		year_at = stop - 1
	end
	local title, dropped = join_words(tokens, year_at or stop)
	if title == '' then return name, false end
	title = capitalize(title)
	if year_at then title = title .. ' (' .. tokens[year_at].text .. ')' end
	-- Groups after the cut were never looked at: they go with the tail.
	return title, stop <= #tokens or dropped
end

-- Name of a video file (without its extension) at the end of `path`, or nil
-- when the path does not end in a video file name. `\` separates folders too
-- (Windows paths). The last separator is found by a plain scan, so a long
-- path costs linear time.
local function video_file_name(path)
	local last = 0
	for pos in path:gmatch('()[/\\]') do last = pos end
	local name = path:sub(last + 1)
	local base, ext = name:match('^(.+)%.([%w]+)$')
	if not base or not VIDEO_EXTENSION_SET[ext:lower()] then return nil end
	return base:sub(1, MAX_RAW)
end

-- The release name in `path` for hikari-skip: a local or file:// video file
-- name, an http(s) URL's `filename` parameter, or the video file name at the
-- end of its path. Cut and decoded as title_for does; nil for anything else.
local function release_name(path)
	if type(path) ~= 'string' then return nil end
	local scheme = path:match('^(%a[%w+.-]*)://')
	if not scheme then return video_file_name(path:sub(-MAX_RAW * 4)) end
	scheme = scheme:lower()
	if scheme == 'file' then
		return video_file_name(url_decode(path:sub(#scheme + 4):sub(-MAX_RAW * 4), false))
	end
	if scheme ~= 'http' and scheme ~= 'https' then return nil end
	local rest = path:sub(#scheme + 4):gsub('#.*$', '')
	local location, query = rest:match('^([^?]*)%?(.*)$')
	location = location or rest
	for pair in (query or ''):gmatch('[^&;]+') do
		local key, value = pair:match('^([^=]*)=(.*)$')
		if key and url_decode(key:sub(1, MAX_RAW), true) == 'filename' then
			return strip_extension(url_decode(value:sub(1, MAX_RAW), true))
		end
	end
	local route = location:match('^[^/]*(.*)$')
	local segment = route:match('^.*/([^/]+)/*$')
	return segment and video_file_name(url_decode(segment:sub(1, MAX_RAW * 4), false))
end

-- What hikari-skip may look up on AniSkip for `path`: {series, season,
-- episode, anime} from a release name with one plain episode, nil otherwise.
-- Read whatever the title options say: they are about the title on screen.
local function release_for(path)
	local name = release_name(path)
	if not name then return nil end
	name = sanitize(name)
	if name == '' then return nil end
	local _, release, info = pretty_title(name, 'en')
	if not release then return nil end
	return info
end

-- Series and next episode ------------------------------------------------------

-- Lower case (ASCII), apostrophes dropped, `×` as x, any other ASCII
-- punctuation as a space, spaces squeezed (as hikari-aniskip.lua's normalize).
-- Other UTF-8 is kept as it is.
local function normalize(text)
	if type(text) ~= 'string' then return '' end
	text = text:sub(1, MAX_RAW):lower()
	text = text:gsub("'", ''):gsub('\226\128\153', ''):gsub('\195\151', ' x ')
	text = text:gsub('[%c%p%s]', ' '):gsub(' +', ' '):gsub('^ ', ''):gsub(' $', '')
	return text
end

-- The release group of a name (without extension), lower case, or nil: the
-- [Group] in front, or a `-Group` that ends the name after its technical tail
-- (`.1080p.WEB-DL.x264-GRP`) and is not a technical word itself (the `DL` of
-- `WEB-DL`). `Show - 05 - Re-Start` has none.
local function group_of(name)
	local tokens = tokenize(name)
	if front_group(tokens) then return tokens[1].text:sub(2, -2):lower() end
	local last = #tokens
	local t = tokens[last]
	if not t or t.group or tail_start(tokens, 1) >= last then return nil end
	local group = t.text:match('%-(%w+)$')
	if not group or exact_tech(group:lower()) or exact_tech(t.text:lower()) then return nil end
	return group:lower()
end

-- The episode of a series that the video file name `name` (no folder) is:
-- {series, season, episode, key, group}, or nil when it is not one.
local function episode_of(name)
	if type(name) ~= 'string' or name:find('[/\\]') then return nil end
	local base = video_file_name(name)
	if not base then return nil end
	base = sanitize(base)
	if base == '' then return nil end
	local _, release, info = pretty_title(base, 'en')
	if not release or not info then return nil end
	local series = normalize(info.series)
	if series == '' then return nil end
	local season = info.season or 1
	return {series = info.series, season = season, episode = info.episode,
		key = series .. '|' .. season, group = group_of(base)}
end

-- Is candidate `a` (an episode_of with its `name`) a better next episode
-- than `b`, for a current episode of `group`?
local function better(a, b, group)
	if not b then return true end
	if a.episode ~= b.episode then return a.episode < b.episode end
	local a_same, b_same = group ~= nil and a.group == group, group ~= nil and b.group == group
	if a_same ~= b_same then return a_same end
	local a_low, b_low = a.name:lower(), b.name:lower()
	if a_low ~= b_low then return a_low < b_low end
	return a.name < b.name
end

-- The name of the next episode after `current` (a file name) among `names`
-- (the file names of its folder), or nil. None when `names` has more than
-- `max` entries.
local function next_episode(current, names, max)
	if type(names) ~= 'table' or (max and #names > max) then return nil end
	local now = episode_of(current)
	if not now then return nil end
	local best
	for _, name in ipairs(names) do
		if type(name) == 'string' and name ~= current then
			local e = episode_of(name)
			if e and e.key == now.key and e.episode > now.episode then
				e.name = name
				if better(e, best, now.group) then best = e end
			end
		end
	end
	return best and best.name or nil
end

M.MAX_CHARS, M.MAX_RAW = MAX_CHARS, MAX_RAW
M.url_decode, M.sanitize, M.truncate, M.strip_extension = url_decode, sanitize, truncate, strip_extension
M.pretty_title, M.video_file_name = pretty_title, video_file_name
M.release_name, M.release_for = release_name, release_for
M.normalize, M.episode_of, M.next_episode = normalize, episode_of, next_episode

return M
