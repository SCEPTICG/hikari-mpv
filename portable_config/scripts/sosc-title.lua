-- sosc-title: readable titles for streamed files.
--
-- Streaming servers such as Seanime hand mpv URLs like
--   https://host/<uuid>?token=<secret>&filename=Show.S01E01.1080p.mkv
-- and with no title of its own mpv (and uosc's top bar) shows the whole URL,
-- token included. For http(s) URLs with a query this script sets
-- `force-media-title` to the decoded `filename` parameter without its video
-- extension or, when there is none, to the last path segment without the query
-- (the fallback). URLs whose only path is `/` but that carry `user:password@`
-- get the bare host. Other local files and URLs are left alone.
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
-- - The `filename` parameter wins over the file's `title` metadata tag: it is
--   known before the file opens, it names show and episode, and the tag in
--   these releases is often missing or just the release group.
-- - The fallback is weaker (`stream`, `master.m3u8`, `watch`): if the file
--   turns out to have a `title` tag, it is cleared on `file-loaded` so the tag
--   shows. It still matters until then and for files without a tag, because
--   mpv would otherwise show the basename with its query (`stream?api_key=...`).
--
-- - With pretty=yes (default) a title taken from `filename` is tidied up by
--   pretty_title(): release names such as `Show.Name.S01E01.1080p.WEB-DL-GRP`
--   become `Show Name · T1 E01`. The fallback and playlist titles are never
--   touched: they are not release names.
--
-- Options (script-opts/sosc-title.conf): enabled=yes|no, pretty=yes|no

local msg = require('mp.msg')
local options = require('mp.options')

local OPTIONS_ID = 'sosc-title'
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
	cr adn amzn nf dsnp hulu hmax atvp hidive funi uncensored proper repack opus]])

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

-- `01`, or `01-E02` for a range.
local function episode_label(first, last)
	local e1, e2 = episode_number(first), last and episode_number(last)
	if not e1 or (last and not e2) then return nil end
	return e2 and e1 ~= e2 and (e1 .. '-E' .. e2) or e1
end

-- Episode marker starting at tokens[i]: label and number of tokens it uses.
local function marker_at(tokens, i)
	local t = tokens[i]
	if t.group then return nil end
	local text = t.text
	-- S01E01, s1e1, S01E01v2, S01E01-E02, S01E01E02
	local season, first, rest = text:match('^[Ss](%d+)[Ee](%d+)(.*)$')
	if season then
		local last, ok = episode_suffix(rest)
		local episodes = ok and #season <= 4 and episode_label(first, last)
		if not episodes then return nil end
		season = tonumber(season)
		-- Season 0 holds the specials: `Show · Especial E03`.
		if season == 0 then return 'Especial E' .. episodes, 1 end
		return 'T' .. season .. ' E' .. episodes, 1
	end
	-- E01, EP01, E01v2, EP01-02
	first, rest = text:match('^[Ee][Pp]?(%d+)(.*)$')
	if first then
		local last, ok = episode_suffix(rest)
		local episodes = ok and episode_label(first, last)
		if not episodes then return nil end
		return 'E' .. episodes, 1
	end
	-- `Episode 01`, `Ep 01`, `- 01`, `- 01v2` (anime releases)
	local lower = text:lower()
	local nxt = tokens[i + 1]
	if nxt and not nxt.group and (lower == 'episode' or lower == 'ep' or lower == 'ep.' or lower == '-') then
		-- Only a bare number (plus version): `- 2049` is a year, `- 3D` a word.
		local number, after = nxt.text:match('^(%d+)(.*)$')
		if number and (after == '' or after:match('^[vV]%d+$')) and not is_year(number) then
			local episodes = episode_label(number)
			if episodes then return 'E' .. episodes, 2 end
		end
	end
	return nil
end

-- Words before position `stop`, without the leading [...] group (the release
-- group), without technical [...] and (...) groups, and without separators
-- left dangling at either end.
local function join_words(tokens, stop)
	local words = {}
	for i = 1, stop - 1 do
		local t = tokens[i]
		if not t.group or (i > 1 and keep_group(t.text)) then
			words[#words + 1] = t.text
		end
	end
	local first, last = 1, #words
	while first <= last and words[first]:match('^[%-~.]+$') do first = first + 1 end
	while last >= first and words[last]:match('^[%-~.]+$') do last = last - 1 end
	return table.concat(words, ' ', first, last)
end

-- Turns a release name into `Series · T1 E01`, `Series · E05` or, with no
-- episode marker, the name up to its technical tail with dots as spaces.
-- Falls back to `name` itself when nothing sensible is left. Expects
-- sanitized input already cut to MAX_RAW; every pattern is anchored to a
-- token, so the work stays linear.
local function pretty_title(name)
	local tokens = tokenize(name)
	for i = 1, #tokens do
		local label = marker_at(tokens, i)
		if label then
			local series = join_words(tokens, i)
			if series == '' then return name end
			return series .. ' · ' .. label
		end
	end
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
	local title = join_words(tokens, year_at or stop)
	if title == '' then return name end
	if year_at then title = title .. ' (' .. tokens[year_at].text .. ')' end
	return title
end

-- ----------------------------------------------------------------------------

local function clean(text, pretty)
	local title = sanitize(text)
	if pretty and title ~= '' then title = pretty_title(title) end
	title = truncate(title)
	return title ~= '' and title or nil
end

local opts = {enabled = true, pretty = true}
options.read_options(opts, OPTIONS_ID)

-- Title for `path` and where it came from ('filename' or 'fallback'), or nil
-- when the path should keep mpv's own title.
local function title_for(path)
	if type(path) ~= 'string' then return nil end
	local scheme = path:match('^(%a[%w+.-]*)://')
	if not scheme or (scheme:lower() ~= 'http' and scheme:lower() ~= 'https') then return nil end
	local rest = path:sub(#scheme + 4):gsub('#.*$', '')
	local location, query = rest:match('^([^?]*)%?(.*)$')
	location = location or rest
	local authority, route = location:match('^([^/]*)(.*)$')
	local host = authority:gsub('^.*@', '')
	local has_userinfo = host ~= authority

	if not query then
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

	-- No usable filename: last path segment, or the host if the path is empty.
	-- Anchored so the match stays linear on long routes.
	local segment = route:match('^.*/([^/]+)/*$')
	if segment then
		local title = clean(url_decode(segment:sub(1, MAX_RAW), false))
		if title then return title, 'fallback' end
	end
	local title = clean(host:sub(1, MAX_RAW))
	if title then return title, 'fallback' end
	return nil
end

-- Fallback title we set for the current file, so file-loaded can withdraw it.
local fallback_title = nil

local function playlist_entry_title()
	local pos = mp.get_property_number('playlist-playing-pos', -1)
	if not pos or pos < 0 then return '' end
	return mp.get_property('playlist/' .. pos .. '/title', '') or ''
end

local function on_start_file()
	fallback_title = nil
	if not opts.enabled then return end
	local title, source = title_for(mp.get_property('path'))
	if not title then return end
	local current = mp.get_property('force-media-title', '')
	if current ~= nil and current ~= '' then
		msg.verbose('force-media-title already set, leaving it alone')
		return
	end
	if playlist_entry_title() ~= '' then
		msg.verbose('playlist entry has its own title, leaving it alone')
		return
	end
	mp.set_property('file-local-options/force-media-title', title)
	if source == 'fallback' then fallback_title = title end
end

-- A container title beats our fallback. The file-local backup is already taken,
-- so mpv still restores the original value when the file ends.
local function on_file_loaded()
	if not fallback_title then return end
	local tag = mp.get_property('metadata/by-key/title', '')
	if tag ~= nil and tag ~= '' and mp.get_property('force-media-title', '') == fallback_title then
		mp.set_property('file-local-options/force-media-title', '')
	end
	fallback_title = nil
end

mp.register_event('start-file', on_start_file)
mp.register_event('file-loaded', on_file_loaded)

if SOSC_TITLE_TEST then
	return {
		title_for = title_for, url_decode = url_decode, sanitize = sanitize,
		truncate = truncate, strip_extension = strip_extension, pretty_title = pretty_title,
		on_start_file = on_start_file, on_file_loaded = on_file_loaded,
		MAX_CHARS = MAX_CHARS, MAX_RAW = MAX_RAW, opts = opts,
	}
end
