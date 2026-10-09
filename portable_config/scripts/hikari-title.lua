-- hikari-title: readable titles for anime (and other) releases, local or streamed.
--
-- mpv shows a file's `title` tag, or else its file name. For releases neither
-- reads well: `[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv`, a
-- tag that is just the release group, or, for streaming servers such as
-- Seanime, a whole URL with its token:
--   https://host/<uuid>?token=<secret>&filename=Show.S01E01.1080p.mkv
-- This script sets `force-media-title` to a tidy title instead:
--   Sousou no Frieren · E05        Show · S1 E01 (`T1 E01` in Spanish)
--   Show (2024) · S1 E05 · Episode Title
--
-- Which files get a title:
-- - Local files (plain paths and file:// URLs) with a video extension: the
--   file name, tidied by pretty_title(), but only when it really looks like a
--   release (an episode marker, a technical tail such as `1080p.WEB-DL`, or
--   [group] / (1080p) brackets to drop). Then it wins over the file's `title`
--   tag. Any other name (`Holiday video.mkv`) is left to mpv, which shows the
--   tag or the name.
-- - http(s) URLs with a `filename` query parameter (Seanime and the like): that
--   parameter, decoded, always (it is what names the file there).
-- - http(s) URLs whose last path segment is a video file name that looks like
--   a release (`https://host/files/[SubsPlease] Show - 05 (1080p).mkv`): that
--   segment, as for local files.
-- - Other http(s) URLs with a query: the last path segment without the query
--   (the fallback), so the token never shows; it gives way to a `title` tag.
--   URLs whose only path is `/` but that carry `user:password@` get the bare
--   host. Any other URL (ytdl://, rtsp://, YouTube pages...) is left alone.
--
-- Decisions:
-- - Runs on `start-file`, not `file-loaded`, so the title is replaced before
--   the network open instead of after the stream has buffered. mpv assigns
--   `path` before sending the event, so reading it there is reliable. The
--   event is asynchronous, though: the raw URL may still flash for an instant.
--   Hooks that run later (ytdl_hook's on_load, per-file options from a
--   playlist) can still override the title.
-- - Sets `file-local-options/force-media-title`, so mpv itself restores the
--   previous value when the file ends: the title never sticks to the next
--   playlist entry.
-- - Nothing is set if `force-media-title` is already non-empty (set by the
--   user) or the playlist entry has its own title (M3U #EXTINF, IPTV lists).
-- - The `filename` parameter and release-like file names win over the file's
--   `title` tag: they are known before the file opens, they name show and
--   episode, and the tag in these releases is often missing or just the
--   release group.
-- - The fallback is weaker (`stream`, `master.m3u8`, `watch`): if the file
--   turns out to have a `title` tag, it is cleared on `file-loaded` so the tag
--   shows. It still matters until then and for files without a tag, because
--   mpv would otherwise show the basename with its query (`stream?api_key=...`).
-- - Release names are recognised token by token (see pretty_title): episode
--   markers (`S01E05`, `E05`, `EP05`, `- 05`, `- 05v2`, `- 12.5`, `Episode 5`,
--   `SP01`, `Special 1`, `OVA`), a season written before the marker (`S2`,
--   `Season 2`, `2nd Season`, `(Season 2)`), the release group in front, the
--   technical tail (resolution, source, codecs, services, CRC) and, when it is
--   clearly there, an episode title after the marker (`- S01E05 - Title`,
--   `S01E05.Title.1080p`). The season and episode labels follow hikari's
--   language (hikari-i18n: `S1 E05`, `T1 E05`, `第1季 第05集`), and the title of
--   the file playing is redone when the language changes. The fallback and
--   playlist titles are never touched: they are not release names.
-- - Every pattern is anchored to a token and input is cut to MAX_RAW before
--   any work, so hostile names cost linear time.
--
-- Options (script-opts/hikari-title.conf): enabled=yes|no, pretty=yes|no
-- (pretty=no: only `filename=` and the fallback, shown as they come).

local msg = require('mp.msg')
local options = require('mp.options')

-- Texts in the chosen language: ~~/script-modules/hikari-i18n.lua. Single-file
-- scripts get no mpv folder in package.path, so the folder is added for this
-- one require and taken out again (see the header of hikari-i18n.lua).
local i18n = (function()
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then
		error('hikari: unusable script-modules folder: ' .. tostring(dir))
	end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, 'hikari-i18n')
	package.path = saved
	if not ok then error('hikari: cannot load script-modules/hikari-i18n.lua (reinstall hikari): ' .. tostring(module)) end
	return module
end)()

local OPTIONS_ID = 'hikari-title'
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
		if digits then return {first = digits, fraction = fraction}, 2 end
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

-- Turns a release name into `Series · S1 E05`, `Series · E05 · Episode title`
-- or, with no episode marker, the name up to its technical tail with dots as
-- spaces. Falls back to `name` itself when nothing sensible is left. The
-- second result says whether the name looked like a release (a marker, a
-- technical tail or brackets dropped); `lang` is the language of the labels
-- (hikari's when nil). Expects sanitized input already cut to MAX_RAW; every
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
				return title, true
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

-- ----------------------------------------------------------------------------

-- Sanitized and cut text; with `pretty`, tidied by pretty_title. Returns the
-- title (nil when nothing is left) and whether it looked like a release.
local function clean(text, pretty)
	local title = sanitize(text)
	local release = false
	if pretty and title ~= '' then title, release = pretty_title(title) end
	title = truncate(title)
	if title == '' then return nil, false end
	return title, release
end

local opts = {enabled = true, pretty = true}
options.read_options(opts, OPTIONS_ID)

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

-- Title for a video file name, only when it looks like a release.
local function release_title(name)
	if not name or not opts.pretty then return nil end
	local title, release = clean(name, true)
	if title and release then return title end
	return nil
end

-- Title for `path` and where it came from ('filename', 'file' or 'fallback'),
-- or nil when the path should keep mpv's own title.
local function title_for(path)
	if type(path) ~= 'string' then return nil end
	local scheme = path:match('^(%a[%w+.-]*)://')
	if not scheme then
		-- A local path (`/x/a.mkv`, `C:\x\a.mkv`, `a.mkv`).
		local title = release_title(video_file_name(path:sub(-MAX_RAW * 4)))
		if title then return title, 'file' end
		return nil
	end
	scheme = scheme:lower()
	if scheme == 'file' then
		local location = path:sub(#scheme + 4):sub(-MAX_RAW * 4)
		local title = release_title(video_file_name(url_decode(location, false)))
		if title then return title, 'file' end
		return nil
	end
	if scheme ~= 'http' and scheme ~= 'https' then return nil end
	local rest = path:sub(#scheme + 4):gsub('#.*$', '')
	local location, query = rest:match('^([^?]*)%?(.*)$')
	location = location or rest
	local authority, route = location:match('^([^/]*)(.*)$')
	local host = authority:gsub('^.*@', '')
	local has_userinfo = host ~= authority

	-- Last path segment, if any. Anchored so the match stays linear on long routes.
	local segment = route:match('^.*/([^/]+)/*$')
	local segment_title = segment and release_title(video_file_name(url_decode(segment:sub(1, MAX_RAW * 4), false)))

	if not query then
		if segment_title then return segment_title, 'file' end
		-- Credentials in the URL and no path to show instead: the bare host.
		if has_userinfo and route:match('^/*$') then
			local title = clean(host:sub(1, MAX_RAW))
			if title then return title, 'fallback' end
		end
		return nil
	end

	for pair in query:gmatch('[^&;]+') do
		local key, value = pair:match('^([^=]*)=(.*)$')
		if key and url_decode(key:sub(1, MAX_RAW), true) == 'filename' then
			local title = clean(strip_extension(url_decode(value:sub(1, MAX_RAW), true)), opts.pretty)
			if title then return title, 'filename' end
		end
	end
	if segment_title then return segment_title, 'file' end

	-- No usable filename: last path segment, or the host if the path is empty.
	if segment then
		local title = clean(url_decode(segment:sub(1, MAX_RAW), false))
		if title then return title, 'fallback' end
	end
	local title = clean(host:sub(1, MAX_RAW))
	if title then return title, 'fallback' end
	return nil
end

-- What we set for the current file: the title, and whether it is the weak
-- fallback (file-loaded withdraws it when the file has a title tag).
local current = nil

local function playlist_entry_title()
	local pos = mp.get_property_number('playlist-playing-pos', -1)
	if not pos or pos < 0 then return '' end
	return mp.get_property('playlist/' .. pos .. '/title', '') or ''
end

local function on_start_file()
	current = nil
	if not opts.enabled then return end
	local title, source = title_for(mp.get_property('path'))
	if not title then return end
	local existing = mp.get_property('force-media-title', '')
	if existing ~= nil and existing ~= '' then
		msg.verbose('force-media-title already set, leaving it alone')
		return
	end
	if playlist_entry_title() ~= '' then
		msg.verbose('playlist entry has its own title, leaving it alone')
		return
	end
	mp.set_property('file-local-options/force-media-title', title)
	current = {title = title, fallback = source == 'fallback'}
end

-- A container title beats our fallback. The file-local backup is already taken,
-- so mpv still restores the original value when the file ends.
local function on_file_loaded()
	if not current or not current.fallback then return end
	local tag = mp.get_property('metadata/by-key/title', '')
	if tag ~= nil and tag ~= '' and mp.get_property('force-media-title', '') == current.title then
		mp.set_property('file-local-options/force-media-title', '')
		current = nil
	end
end

-- Another language: the season and episode labels of the title on screen
-- change with it, as long as nothing else has replaced our title meanwhile.
local function on_language_change()
	if not current or current.fallback then return end
	if mp.get_property('force-media-title', '') ~= current.title then return end
	local title = title_for(mp.get_property('path'))
	if title and title ~= current.title then
		mp.set_property('file-local-options/force-media-title', title)
		current.title = title
	end
end

mp.register_event('start-file', on_start_file)
mp.register_event('file-loaded', on_file_loaded)
mp.register_event('end-file', function() current = nil end)
i18n.on_change(on_language_change)

if HIKARI_TITLE_TEST then
	return {
		title_for = title_for, url_decode = url_decode, sanitize = sanitize,
		truncate = truncate, strip_extension = strip_extension, pretty_title = pretty_title,
		on_start_file = on_start_file, on_file_loaded = on_file_loaded,
		MAX_CHARS = MAX_CHARS, MAX_RAW = MAX_RAW, opts = opts, i18n = i18n,
	}
end
